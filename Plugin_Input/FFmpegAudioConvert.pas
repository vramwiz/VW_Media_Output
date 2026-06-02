unit FFmpegAudioConvert;

// FFmpegの音声フレームをAviUtl2側で扱いやすいPCM形式へ変換する補助ユニット。
// swr_convertの呼び出しと出力バッファサイズ調整をここに集約する。

interface

uses
  System.SysUtils, FFmpegApi;

// AVFrameの音声サンプルをPCM16 stereo 48kHzへ変換する。
function ConvertAudioFrameToPcm16Stereo48k(AudioFrame: PAVFrame; SwrContext: PSwrContext;
  SourceSampleRate: Integer; out Pcm: TBytes; out SampleCount: Integer): Boolean;

implementation

uses
  System.Math;

// AVFrameの音声サンプルをPCM16 stereo 48kHzへ変換する。
function ConvertAudioFrameToPcm16Stereo48k(AudioFrame: PAVFrame; SwrContext: PSwrContext;
  SourceSampleRate: Integer; out Pcm: TBytes; out SampleCount: Integer): Boolean;
var
  OutData: array[0..0] of PByte; // swr_convertへ渡す出力バッファポインタ
  OutSamples: Integer; // 変換後に必要になる最大サンプル数
begin
  Result := False;
  Pcm := nil;
  SampleCount := 0;

  if (AudioFrame = nil) or (SwrContext = nil) then
    Exit;

  if SourceSampleRate > 0 then
    OutSamples := Ceil(AudioFrame.nb_samples * AUDIO_OUTPUT_SAMPLE_RATE / SourceSampleRate) + 256
  else
    OutSamples := AudioFrame.nb_samples + 256;

  SetLength(Pcm, OutSamples * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
  if Length(Pcm) = 0 then
    Exit;

  OutData[0] := @Pcm[0];
  SampleCount := TFFmpegApi.swr_convert(SwrContext, @OutData[0], OutSamples,
    @AudioFrame.data[0], AudioFrame.nb_samples);
  if SampleCount <= 0 then
  begin
    Pcm := nil;
    SampleCount := 0;
    Exit;
  end;

  SetLength(Pcm, SampleCount * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt));
  Result := True;
end;

end.
