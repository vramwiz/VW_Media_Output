unit PluginAudioInputReader;

// AviUtl2入力プラグインの音声読み取り処理を担当するユニット。
// FFmpegデコーダからPCM16 stereo 48kHzを順次読み込み、func_read_audioの要求範囲へ返す。

interface

uses
  Winapi.Windows, System.SysUtils, System.Math, AviUtl2InputTypes,
  FFmpegDecoderTypes, FFmpegDecoder;

type
  // AviUtl2の音声読み取り要求に合わせてPCMキャッシュを管理するクラス。
  TPluginAudioInputReader = class
  private
    FDecoder: TFFmpegDecoder; // 音声読み取り専用に開くFFmpegデコーダ
    FFormat: WAVEFORMATEX; // AviUtl2へ返すPCM形式
    FPcm: TBytes; // デコード済みPCMキャッシュ
    FSampleCount: Integer; // 音声全体の想定サンプル数
    FDecodedSamples: Integer; // PCMキャッシュへデコード済みのサンプル数
    FDecodeFinished: Boolean; // FFmpeg側の音声読み取りが終端に達したか
    FLastError: string; // 直近の音声読み取りエラー
    // WAVEFORMATEXのポインタをAviUtl2用に返す。
    function GetFormatPtr: PWAVEFORMATEX;
    // 音声入力として扱えるサンプル数を持っているかを返す。
    function GetHasAudio: Boolean;
  public
    // 音声読み取り用デコーダとPCMキャッシュを解放する。
    destructor Destroy; override;
    // 指定ファイルの音声ストリームを読み取り可能な状態で開く。
    function Open(const FileName: string; const VideoInfo: TVideoInfo; out ErrorMessage: string): Boolean;
    // 指定範囲のPCMサンプルをAviUtl2のバッファへコピーする。
    function ReadAudio(Start, SampleLength: Integer; Buffer: Pointer): Integer;
    property Format: WAVEFORMATEX read FFormat;
    property FormatPtr: PWAVEFORMATEX read GetFormatPtr;
    property HasAudio: Boolean read GetHasAudio;
    property SampleCount: Integer read FSampleCount;
    property LastError: string read FLastError;
  end;

implementation

// WAVEFORMATEXのポインタをAviUtl2用に返す。
function TPluginAudioInputReader.GetFormatPtr: PWAVEFORMATEX;
begin
  Result := @FFormat;
end;

// 音声入力として扱えるサンプル数を持っているかを返す。
function TPluginAudioInputReader.GetHasAudio: Boolean;
begin
  Result := FSampleCount > 0;
end;

// 音声読み取り用デコーダとPCMキャッシュを解放する。
destructor TPluginAudioInputReader.Destroy;
begin
  FDecoder.Free;
  FPcm := nil;
  inherited Destroy;
end;

// 指定ファイルの音声ストリームを読み取り可能な状態で開く。
function TPluginAudioInputReader.Open(const FileName: string; const VideoInfo: TVideoInfo; out ErrorMessage: string): Boolean;
var
  AudioInfo: TVideoInfo; // 音声読み取り用デコーダで取得した動画情報
  AudioDurationSec: Double; // サンプル数計算に使う音声長
begin
  Result := False;
  ErrorMessage := '';
  FLastError := '';

  if (not VideoInfo.Audio.Present) or (VideoInfo.Audio.OpenError <> '') then
  begin
    ErrorMessage := VideoInfo.Audio.OpenError;
    FLastError := ErrorMessage;
    Exit;
  end;

  FDecoder := TFFmpegDecoder.Create;
  if not FDecoder.Open(FileName, AudioInfo, ErrorMessage) then
  begin
    FLastError := ErrorMessage;
    FreeAndNil(FDecoder);
    Exit;
  end;

  FFormat.wFormatTag := 1;
  FFormat.nChannels := 2;
  FFormat.nSamplesPerSec := 48000;
  FFormat.wBitsPerSample := 16;
  FFormat.nBlockAlign := FFormat.nChannels * FFormat.wBitsPerSample div 8;
  FFormat.nAvgBytesPerSec := FFormat.nSamplesPerSec * FFormat.nBlockAlign;
  FFormat.cbSize := 0;

  AudioDurationSec := VideoInfo.Audio.DurationSec;
  if AudioDurationSec <= 0 then
    AudioDurationSec := VideoInfo.DurationSec;
  if AudioDurationSec > 0 then
    FSampleCount := Max(1, Ceil(AudioDurationSec * FFormat.nSamplesPerSec));

  Result := FSampleCount > 0;
end;

// 指定範囲のPCMサンプルをAviUtl2のバッファへコピーする。
function TPluginAudioInputReader.ReadAudio(Start, SampleLength: Integer; Buffer: Pointer): Integer;
var
  AvailableSamples: Integer; // 要求開始位置から残っているサンプル数
  SamplesToCopy: Integer; // 実際にコピーするサンプル数
  SourceOffset: Integer; // PCMキャッシュ内のコピー開始バイト位置
  BytesToCopy: Integer; // 実際にコピーするバイト数
begin
  Result := 0;
  if (Buffer = nil) or (SampleLength <= 0) or (FDecoder = nil) or (FSampleCount <= 0) then
    Exit;

  if Start < 0 then
    Start := 0;
  if Start >= FSampleCount then
    Exit;

  AvailableSamples := FSampleCount - Start;
  SamplesToCopy := Min(SampleLength, AvailableSamples);
  if (not FDecodeFinished) and (FDecodedSamples < Start + SamplesToCopy) then
  begin
    if not FDecoder.DecodeAudioPcm16Stereo48kUntil(Start + SamplesToCopy, FPcm,
      FDecodedSamples, FDecodeFinished, FLastError) then
      Exit;
    if FDecodeFinished and (FDecodedSamples < FSampleCount) then
      FSampleCount := FDecodedSamples;
  end;

  FillChar(Buffer^, SampleLength * FFormat.nBlockAlign, 0);
  if Start >= FDecodedSamples then
    Exit;

  SamplesToCopy := Min(SamplesToCopy, FDecodedSamples - Start);
  SourceOffset := Start * FFormat.nBlockAlign;
  BytesToCopy := SamplesToCopy * FFormat.nBlockAlign;
  if BytesToCopy > 0 then
    Move(FPcm[SourceOffset], Buffer^, BytesToCopy);

  Result := SamplesToCopy;
end;

end.
