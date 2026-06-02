unit FFmpegDecoder;

// FFmpegを使って動画/音声ファイルを開き、映像フレームやPCM音声を読み出すデコーダ本体ユニット。
// AviUtl2入力プラグイン側から使う高レベルなopen/read/seek処理を担当する。

interface

uses
  Winapi.Windows, Winapi.MMSystem, System.SysUtils, System.Generics.Collections,
  System.Diagnostics, Vcl.Graphics, FFmpegDecoderTypes;

type
  // FFmpegデコード処理で発生した例外を表すクラス。
  EFFmpegDecoder = class(Exception);

  // 1つの入力ファイルに対するFFmpegリソースとデコード状態を管理するクラス。
  TFFmpegDecoder = class
  private
    FFileName: string; // 現在開いている動画ファイル名
    FFormatContext: Pointer; // avformatで開いた入力コンテキスト
    FCodecContext: Pointer; // avcodecで開いたデコードコンテキスト
    FStream: Pointer; // 対象の映像ストリーム
    FStreamIndex: Integer; // 対象の映像ストリーム番号
    FAudioCodecContext: Pointer; // 音声用デコードコンテキスト
    FAudioStream: Pointer; // 対象の音声ストリーム
    FAudioStreamIndex: Integer; // 対象の音声ストリーム番号
    FAudioFrame: Pointer; // 音声デコードに再利用するAVFrame
    FSwrContext: Pointer; // PCM変換用swresampleコンテキスト
    FWaveOut: HWAVEOUT; // デバッグ用音声出力
    FAudioPlaybackActive: Boolean; // 音声出力中かどうか
    FAudioBuffers: TList<PAudioWaveBuffer>; // waveOut完了待ちのPCMバッファ
    FAudioStats: TAudioPlaybackStats; // 音声デコード確認用の数値
    FDecodeStats: TDecodeLoadStats; // デコード負荷確認用の数値
    FPacket: Pointer; // 読み込みに再利用するAVPacket
    FFrame: Pointer; // デコードに再利用するAVFrame
    FInfo: TVideoInfo; // 現在開いている動画の基本情報
    FDirectSwsContext: Pointer; // AviUtl2バッファ直接出力用の色変換コンテキスト
    FDirectSwsSrcWidth: Integer; // 直接出力用swsの入力幅
    FDirectSwsSrcHeight: Integer; // 直接出力用swsの入力高さ
    FDirectSwsSrcFormat: Integer; // 直接出力用swsの入力ピクセル形式
    FDirectSwsDstFormat: Integer; // 直接出力用swsの出力ピクセル形式
    // 音声パケットをデコードし、デバッグ用にPCM再生と統計更新を行う
    procedure DecodeAudioPacket(Packet: Pointer);
    // waveOutで再生完了したPCMバッファを解放する
    procedure CleanupAudioBuffers;
    // PCMバッファをwaveOutへ渡す
    procedure QueueAudioPcm(const Pcm: TBytes);
    // PCMバッファから音量確認用の統計を更新する
    procedure UpdateAudioStats(const Pcm: TBytes; SampleCount: Integer; PtsMs: Integer);
    // 映像デコード負荷の統計を更新する
    procedure UpdateVideoLoadStats(ElapsedMs: Double);
    // 音声デコード負荷の統計を更新する
    procedure UpdateAudioLoadStats(ElapsedMs: Double);
  public
    // デコーダインスタンスを初期化する
    constructor Create;
    // 開いている動画を閉じてインスタンスを破棄する
    destructor Destroy; override;
    // 保持しているFFmpegリソースを解放する
    procedure Close;
    // 動画を開いてデコード可能な状態にする
    function Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
    // 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
    function DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload;
    // 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
    function DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードする
    function DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 現在位置から次の映像フレームを順方向デコードして32bit BGRxバッファへ直接変換する
    function DecodeNextFrameToBgrx32(Buffer: Pointer; BufferStride: Integer; out PositionMs: Integer; out ErrorMessage: string): Boolean;
    // 開いているファイルの音声を指定サンプル数までPCM16 stereo 48kHzへ順次デコードする
    function DecodeAudioPcm16Stereo48kUntil(TargetSampleCount: Integer; var Pcm: TBytes; var SampleCount: Integer; out Finished: Boolean; out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を開始する
    function StartAudioPlayback(out ErrorMessage: string): Boolean;
    // デバッグ用の音声再生を停止する
    procedure StopAudioPlayback;
    // 一時デコーダで動画情報だけを読む
    class function ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean; static;
    // 一時デコーダで指定位置のフレームだけを読む
    class function DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean; overload; static;
    property Info: TVideoInfo read FInfo;
    property AudioStats: TAudioPlaybackStats read FAudioStats;
    property DecodeStats: TDecodeLoadStats read FDecodeStats;
    property FileName: string read FFileName;
  end;

implementation

uses
  FFmpegApi, FFmpegAudioConvert, FFmpegAudioOpen, FFmpegDecodeStats, FFmpegFrameConvert,
  FFmpegStreamInfo;

// デコーダインスタンスを初期化する
constructor TFFmpegDecoder.Create;
begin
  inherited Create;
  FStreamIndex := -1;
  FAudioStreamIndex := -1;
  FWaveOut := 0;
  FAudioBuffers := TList<PAudioWaveBuffer>.Create;
end;

// 開いている動画を閉じてインスタンスを破棄する
destructor TFFmpegDecoder.Destroy;
begin
  Close;
  FAudioBuffers.Free;
  inherited Destroy;
end;

// 保持しているFFmpegリソースを解放する
procedure TFFmpegDecoder.Close;
var
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト解放用の型付きポインタ
  AudioCodecContext: PAVCodecContext; // 音声デコードコンテキスト解放用の型付きポインタ
  FormatContext: PAVFormatContext; // 入力フォーマットコンテキスト解放用の型付きポインタ
  Packet: PAVPacket; // 再利用AVPacket解放用の型付きポインタ
  Frame: PAVFrame; // 映像AVFrame解放用の型付きポインタ
  AudioFrame: PAVFrame; // 音声AVFrame解放用の型付きポインタ
  SwrContext: PSwrContext; // 音声変換コンテキスト解放用の型付きポインタ
begin
  StopAudioPlayback;

  if FDirectSwsContext <> nil then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(FDirectSwsContext));
    FDirectSwsContext := nil;
  end;
  FDirectSwsSrcWidth := 0;
  FDirectSwsSrcHeight := 0;
  FDirectSwsSrcFormat := 0;
  FDirectSwsDstFormat := 0;

  Packet := PAVPacket(FPacket);
  if Assigned(Packet) then
  begin
    TFFmpegApi.av_packet_free(@Packet);
    FPacket := nil;
  end;

  Frame := PAVFrame(FFrame);
  if Assigned(Frame) then
  begin
    TFFmpegApi.av_frame_free(@Frame);
    FFrame := nil;
  end;

  AudioFrame := PAVFrame(FAudioFrame);
  if Assigned(AudioFrame) then
  begin
    TFFmpegApi.av_frame_free(@AudioFrame);
    FAudioFrame := nil;
  end;

  SwrContext := PSwrContext(FSwrContext);
  if Assigned(SwrContext) then
  begin
    TFFmpegApi.swr_free(@SwrContext);
    FSwrContext := nil;
  end;

  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  if Assigned(AudioCodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
    FAudioCodecContext := nil;
  end;

  CodecContext := PAVCodecContext(FCodecContext);
  if Assigned(CodecContext) then
  begin
    TFFmpegApi.avcodec_free_context(@CodecContext);
    FCodecContext := nil;
  end;

  FormatContext := PAVFormatContext(FFormatContext);
  if Assigned(FormatContext) then
  begin
    TFFmpegApi.avformat_close_input(@FormatContext);
    FFormatContext := nil;
  end;

  FFileName := '';
  FStream := nil;
  FStreamIndex := -1;
  FAudioStream := nil;
  FAudioStreamIndex := -1;
  FillChar(FInfo, SizeOf(FInfo), 0);
  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FillChar(FDecodeStats, SizeOf(FDecodeStats), 0);
  FAudioStats.LastPtsMs := -1;
end;

// 映像デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateVideoLoadStats(ElapsedMs: Double);
begin
  FFmpegDecodeStats.UpdateVideoLoadStats(FDecodeStats, ElapsedMs);
end;

// 音声デコード負荷の統計を更新する
procedure TFFmpegDecoder.UpdateAudioLoadStats(ElapsedMs: Double);
begin
  FFmpegDecodeStats.UpdateAudioLoadStats(FDecodeStats, ElapsedMs);
end;

// デバッグ用の音声再生を開始する
function TFFmpegDecoder.StartAudioPlayback(out ErrorMessage: string): Boolean;
var
  WaveFormat: TWaveFormatEx; // waveOutへ渡すPCM形式
  Ret: MMRESULT; // waveOut APIの戻り値
begin
  ErrorMessage := '';
  Result := False;

  StopAudioPlayback;

  if (not FInfo.Audio.Present) or (FAudioCodecContext = nil) or (FAudioStream = nil) or (FSwrContext = nil) then
  begin
    ErrorMessage := Format('Audio decoder is not open. present=%s codec=%s stream=%s swr=%s %s',
      [BoolToStr(FInfo.Audio.Present, True),
       BoolToStr(FAudioCodecContext <> nil, True),
       BoolToStr(FAudioStream <> nil, True),
       BoolToStr(FSwrContext <> nil, True),
       FInfo.Audio.OpenError]);
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := AUDIO_OUTPUT_CHANNELS;
  WaveFormat.nSamplesPerSec := AUDIO_OUTPUT_SAMPLE_RATE;
  WaveFormat.wBitsPerSample := 16;
  WaveFormat.nBlockAlign := WaveFormat.nChannels * WaveFormat.wBitsPerSample div 8;
  WaveFormat.nAvgBytesPerSec := WaveFormat.nSamplesPerSec * WaveFormat.nBlockAlign;

  Ret := waveOutOpen(@FWaveOut, WAVE_MAPPER, @WaveFormat, 0, 0, CALLBACK_NULL);
  if Ret <> MMSYSERR_NOERROR then
  begin
    FWaveOut := 0;
    ErrorMessage := Format('waveOutOpen failed: %d', [Ret]);
    Exit;
  end;

  FillChar(FAudioStats, SizeOf(FAudioStats), 0);
  FAudioStats.LastPtsMs := -1;
  FAudioPlaybackActive := True;
  Result := True;
end;

// デバッグ用の音声再生を停止する
procedure TFFmpegDecoder.StopAudioPlayback;
var
  Buffer: PAudioWaveBuffer; // 解放対象のwaveOut用PCMバッファ
begin
  FAudioPlaybackActive := False;

  if FWaveOut <> 0 then
    waveOutReset(FWaveOut);

  if FAudioBuffers <> nil then
  begin
    while FAudioBuffers.Count > 0 do
    begin
      Buffer := FAudioBuffers[FAudioBuffers.Count - 1];
      if FWaveOut <> 0 then
        waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      FAudioBuffers.Delete(FAudioBuffers.Count - 1);
    end;
  end;

  if FWaveOut <> 0 then
  begin
    waveOutClose(FWaveOut);
    FWaveOut := 0;
  end;

  FAudioStats.QueuedBuffers := 0;
end;

// 動画を開いてデコード可能な状態にする
function TFFmpegDecoder.Open(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // avformatで開く入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  AudioCodecContext: PAVCodecContext; // 音声デコードコンテキスト
  Codec: PAVCodec; // 映像ストリームに対応するFFmpegデコーダ
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // 映像デコードに再利用するAVFrame
  AudioFrame: PAVFrame; // 音声デコードに再利用するAVFrame
  SwrContext: PSwrContext; // PCM変換用swresampleコンテキスト
  Utf8FileName: UTF8String; // FFmpegへ渡すUTF-8ファイル名
  Ret: Integer; // FFmpeg APIの戻り値
  StreamIndex: Integer; // 対象の映像ストリーム番号
  AudioStreamIndex: Integer; // 対象の音声ストリーム番号
  Stream: PAVStream; // 対象の映像ストリーム
  AudioStream: PAVStream; // 対象の音声ストリーム
  CodecPar: PAVCodecParameters; // 映像ストリームのコーデック情報
  HasVideoStream: Boolean; // 映像ストリームがあるかどうか
begin
  Close;
  FillChar(Info, SizeOf(Info), 0);
  ErrorMessage := '';
  Result := False;
  FormatContext := nil;
  CodecContext := nil;
  AudioCodecContext := nil;
  Packet := nil;
  Frame := nil;
  AudioFrame := nil;
  SwrContext := nil;
  AudioStream := nil;
  AudioStreamIndex := -1;

  try
    TFFmpegApi.EnsureLoaded;

    Utf8FileName := UTF8String(FileName);
    Ret := TFFmpegApi.avformat_open_input(@FormatContext, PAnsiChar(Utf8FileName), nil, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    Ret := TFFmpegApi.avformat_find_stream_info(FormatContext, nil);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;

    if FormatContext.duration > 0 then
      Info.DurationSec := FormatContext.duration / AV_TIME_BASE;
    ReadAudioInfo(FormatContext, Info);

    StreamIndex := TFFmpegApi.av_find_best_stream(FormatContext, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0);
    HasVideoStream := StreamIndex >= 0;
    Stream := nil;
    if HasVideoStream then
    begin
      Stream := StreamAt(FormatContext, StreamIndex);
      if not Assigned(Stream) then
      begin
        ErrorMessage := 'Video stream pointer is nil.';
        Exit;
      end;

      CodecPar := Stream.codecpar;
      if not Assigned(CodecPar) then
      begin
        ErrorMessage := 'Codec parameters pointer is nil.';
        Exit;
      end;

      Codec := TFFmpegApi.avcodec_find_decoder(CodecPar.codec_id);
      if not Assigned(Codec) then
      begin
        ErrorMessage := 'Decoder was not found.';
        Exit;
      end;

      CodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
      if not Assigned(CodecContext) then
      begin
        ErrorMessage := 'avcodec_alloc_context3 failed.';
        Exit;
      end;

      Ret := TFFmpegApi.avcodec_parameters_to_context(CodecContext, CodecPar);
      if Ret < 0 then
      begin
        ErrorMessage := TFFmpegApi.ErrorText(Ret);
        Exit;
      end;

      Ret := TFFmpegApi.avcodec_open2(CodecContext, Codec, nil);
      if Ret < 0 then
      begin
        ErrorMessage := TFFmpegApi.ErrorText(Ret);
        Exit;
      end;

      Frame := TFFmpegApi.av_frame_alloc();
      if Frame = nil then
      begin
        ErrorMessage := 'Failed to allocate video frame.';
        Exit;
      end;

      Info.Width := CodecPar.width;
      Info.Height := CodecPar.height;
      Info.FpsText := RationalToText(Stream.avg_frame_rate);
      Info.Fps := RationalToDouble(Stream.avg_frame_rate);

      if (Info.Width <= 0) or (Info.Height <= 0) then
      begin
        ErrorMessage := 'Video stream was found, but size could not be read.';
        Exit;
      end;
    end
    else if not Info.Audio.Present then
    begin
      ErrorMessage := 'No supported video or audio stream was found.';
      Exit;
    end;

    OpenAudioDecoder(FormatContext, Info, AudioCodecContext, AudioStream, AudioStreamIndex, AudioFrame, SwrContext);
    if (not HasVideoStream) and ((not Info.Audio.Present) or (Info.Audio.OpenError <> '')) then
    begin
      ErrorMessage := 'Audio decoder is not open. ' + Info.Audio.OpenError;
      Exit;
    end;

    Packet := TFFmpegApi.av_packet_alloc();
    if Packet = nil then
    begin
      ErrorMessage := 'Failed to allocate packet.';
      Exit;
    end;

    FFileName := FileName;
    FFormatContext := FormatContext;
    FCodecContext := CodecContext;
    FStream := Stream;
    FStreamIndex := StreamIndex;
    FAudioCodecContext := AudioCodecContext;
    FAudioStream := AudioStream;
    FAudioStreamIndex := AudioStreamIndex;
    FAudioFrame := AudioFrame;
    FSwrContext := SwrContext;
    FPacket := Packet;
    FFrame := Frame;
    FInfo := Info;

    FormatContext := nil;
    CodecContext := nil;
    AudioCodecContext := nil;
    Packet := nil;
    Frame := nil;
    AudioFrame := nil;
    SwrContext := nil;
    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;

  if Assigned(Frame) then
    TFFmpegApi.av_frame_free(@Frame);
  if Assigned(Packet) then
    TFFmpegApi.av_packet_free(@Packet);
  if Assigned(SwrContext) then
    TFFmpegApi.swr_free(@SwrContext);
  if Assigned(AudioFrame) then
    TFFmpegApi.av_frame_free(@AudioFrame);
  if Assigned(AudioCodecContext) then
    TFFmpegApi.avcodec_free_context(@AudioCodecContext);
  if Assigned(CodecContext) then
    TFFmpegApi.avcodec_free_context(@CodecContext);
  if Assigned(FormatContext) then
    TFFmpegApi.avformat_close_input(@FormatContext);
end;

// 指定ミリ秒位置へシークしてフレームをBitmapへ変換する
function TFFmpegDecoder.DecodeFrameToBitmap(PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // デコード結果を受け取るAVFrame
  Stream: PAVStream; // 対象の映像ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  TargetTs: Int64; // 目的位置のストリーム時間軸PTS
  Stopwatch: TStopwatch; // デコード負荷測定用タイマー
begin
  ErrorMessage := '';
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, FStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if FAudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(FAudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            CopyFrameToBitmap(Frame, Bitmap);
            Stopwatch.Stop;
            UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 指定ミリ秒位置へシークしてフレームを32bit BGRxバッファへ直接変換する
function TFFmpegDecoder.DecodeFrameToBgrx32(PositionMs: Integer; Buffer: Pointer; BufferStride: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // デコード結果を受け取るAVFrame
  Stream: PAVStream; // 対象の映像ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  TargetTs: Int64; // 目的位置のストリーム時間軸PTS
  Stopwatch: TStopwatch; // デコード負荷測定用タイマー
begin
  ErrorMessage := '';
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    TargetTs := StreamTimestampFromMs(Stream, PositionMs);
    Ret := TFFmpegApi.av_seek_frame(FormatContext, FStreamIndex, TargetTs, AVSEEK_FLAG_BACKWARD);
    if Ret < 0 then
    begin
      ErrorMessage := TFFmpegApi.ErrorText(Ret);
      Exit;
    end;
    TFFmpegApi.avcodec_flush_buffers(CodecContext);
    if FAudioCodecContext <> nil then
      TFFmpegApi.avcodec_flush_buffers(PAVCodecContext(FAudioCodecContext));

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          if (Frame.pts = AV_NOPTS_VALUE) or (Frame.pts >= TargetTs) then
          begin
            CopyFrameToBgrx32Buffer(Frame, Buffer, BufferStride,
              FDirectSwsContext, FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat, FDirectSwsDstFormat);
            Stopwatch.Stop;
            UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
            Result := True;
            Exit;
          end;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'Frame could not be decoded.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 現在位置から次の映像フレームを順方向デコードする
function TFFmpegDecoder.DecodeNextFrameToBitmap(Bitmap: TBitmap; out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // デコード結果を受け取るAVFrame
  Stream: PAVStream; // 対象の映像ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  Stopwatch: TStopwatch; // デコード負荷測定用タイマー
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = FAudioStreamIndex then
        begin
          DecodeAudioPacket(Packet);
          Continue;
        end;

        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBitmap(Frame, Bitmap);
          Stopwatch.Stop;
          UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 現在位置から次の映像フレームを順方向デコードして32bit BGRxバッファへ直接変換する
function TFFmpegDecoder.DecodeNextFrameToBgrx32(Buffer: Pointer; BufferStride: Integer; out PositionMs: Integer; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  CodecContext: PAVCodecContext; // 映像デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  Frame: PAVFrame; // デコード結果を受け取るAVFrame
  Stream: PAVStream; // 対象の映像ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  Stopwatch: TStopwatch; // デコード負荷測定用タイマー
begin
  ErrorMessage := '';
  PositionMs := -1;
  Result := False;

  FormatContext := PAVFormatContext(FFormatContext);
  CodecContext := PAVCodecContext(FCodecContext);
  Packet := PAVPacket(FPacket);
  Frame := PAVFrame(FFrame);
  Stream := PAVStream(FStream);

  if (FormatContext = nil) or (CodecContext = nil) or (Packet = nil) or (Frame = nil) or (Stream = nil) then
  begin
    ErrorMessage := 'Decoder is not open.';
    Exit;
  end;

  try
    Stopwatch := TStopwatch.StartNew;
    if TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 then
    begin
      CopyFrameToBgrx32Buffer(Frame, Buffer, BufferStride,
        FDirectSwsContext, FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat, FDirectSwsDstFormat);
      Stopwatch.Stop;
      UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
      PositionMs := StreamTimestampToMs(Stream, Frame.pts);
      Result := True;
      Exit;
    end;

    while TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0 do
    begin
      try
        if Packet.stream_index = FAudioStreamIndex then
        begin
          DecodeAudioPacket(Packet);
          Continue;
        end;

        if Packet.stream_index <> FStreamIndex then
          Continue;

        Stopwatch := TStopwatch.StartNew;
        Ret := TFFmpegApi.avcodec_send_packet(CodecContext, Packet);
        if Ret < 0 then
          Continue;

        while TFFmpegApi.avcodec_receive_frame(CodecContext, Frame) = 0 do
        begin
          CopyFrameToBgrx32Buffer(Frame, Buffer, BufferStride,
            FDirectSwsContext, FDirectSwsSrcWidth, FDirectSwsSrcHeight, FDirectSwsSrcFormat, FDirectSwsDstFormat);
          Stopwatch.Stop;
          UpdateVideoLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
          PositionMs := StreamTimestampToMs(Stream, Frame.pts);
          Result := True;
          Exit;
        end;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    ErrorMessage := 'End of stream.';
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// waveOutで再生完了したPCMバッファを解放する
procedure TFFmpegDecoder.CleanupAudioBuffers;
var
  I: Integer; // FAudioBuffersを後ろから走査するインデックス
  Buffer: PAudioWaveBuffer; // 解放判定中のwaveOut用PCMバッファ
begin
  if FAudioBuffers = nil then
    Exit;

  for I := FAudioBuffers.Count - 1 downto 0 do
  begin
    Buffer := FAudioBuffers[I];
    if (FWaveOut = 0) or ((Buffer.Header.dwFlags and WHDR_DONE) <> 0) then
    begin
      if FWaveOut <> 0 then
        waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
      if Buffer.Data <> nil then
        FreeMem(Buffer.Data);
      Dispose(Buffer);
      FAudioBuffers.Delete(I);
    end;
  end;

  FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// PCMバッファをwaveOutへ渡す
procedure TFFmpegDecoder.QueueAudioPcm(const Pcm: TBytes);
var
  Buffer: PAudioWaveBuffer; // waveOutへ渡す新規PCMバッファ
begin
  if (not FAudioPlaybackActive) or (FWaveOut = 0) or (Length(Pcm) = 0) then
    Exit;

  CleanupAudioBuffers;

  New(Buffer);
  FillChar(Buffer^, SizeOf(Buffer^), 0);
  Buffer.Size := Length(Pcm);
  GetMem(Buffer.Data, Buffer.Size);
  Move(Pcm[0], Buffer.Data^, Buffer.Size);
  Buffer.Header.lpData := PAnsiChar(Buffer.Data);
  Buffer.Header.dwBufferLength := Buffer.Size;

  if waveOutPrepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header)) <> MMSYSERR_NOERROR then
  begin
    FreeMem(Buffer.Data);
    Dispose(Buffer);
    Exit;
  end;

  if waveOutWrite(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header)) <> MMSYSERR_NOERROR then
  begin
    waveOutUnprepareHeader(FWaveOut, @Buffer.Header, SizeOf(Buffer.Header));
    FreeMem(Buffer.Data);
    Dispose(Buffer);
    Exit;
  end;

  FAudioBuffers.Add(Buffer);
  FAudioStats.QueuedBuffers := FAudioBuffers.Count;
end;

// PCMバッファから音量確認用の統計を更新する
procedure TFFmpegDecoder.UpdateAudioStats(const Pcm: TBytes; SampleCount: Integer; PtsMs: Integer);
var
  QueuedBuffers: Integer; // waveOutに渡して未完了のバッファ数
begin
  if FAudioBuffers <> nil then
    QueuedBuffers := FAudioBuffers.Count
  else
    QueuedBuffers := 0;
  FFmpegDecodeStats.UpdateAudioPlaybackStats(FAudioStats, Pcm, SampleCount, PtsMs, QueuedBuffers);
end;

// 音声パケットをデコードし、デバッグ用にPCM再生と統計更新を行う
procedure TFFmpegDecoder.DecodeAudioPacket(Packet: Pointer);
var
  AudioCodecContext: PAVCodecContext; // 音声デコードコンテキスト
  AudioFrame: PAVFrame; // デコード結果を受け取る音声AVFrame
  AudioStream: PAVStream; // 対象の音声ストリーム
  Ret: Integer; // FFmpeg APIの戻り値
  Pcm: TBytes; // 変換後のPCM16 stereo 48kHz
  SampleCount: Integer; // 変換後PCMのサンプル数
  PtsMs: Integer; // 音声フレームのミリ秒位置
  Stopwatch: TStopwatch; // 音声処理負荷測定用タイマー
begin
  if (not FAudioPlaybackActive) or (Packet = nil) then
    Exit;

  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  AudioFrame := PAVFrame(FAudioFrame);
  AudioStream := PAVStream(FAudioStream);
  if (AudioCodecContext = nil) or (AudioFrame = nil) or (AudioStream = nil) or (FSwrContext = nil) then
    Exit;

  Stopwatch := TStopwatch.StartNew;
  try
    Inc(FAudioStats.AudioPackets);
    Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, PAVPacket(Packet));
    if Ret < 0 then
    begin
      Inc(FAudioStats.SendErrors);
      Exit;
    end;

    while TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0 do
    begin
      if not ConvertAudioFrameToPcm16Stereo48k(AudioFrame, PSwrContext(FSwrContext),
        FInfo.Audio.SampleRate, Pcm, SampleCount) then
      begin
        Inc(FAudioStats.ConvertErrors);
        Continue;
      end;

      PtsMs := StreamTimestampToMs(AudioStream, AudioFrame.pts);
      UpdateAudioStats(Pcm, SampleCount, PtsMs);
      QueueAudioPcm(Pcm);
    end;
  finally
    Stopwatch.Stop;
    UpdateAudioLoadStats(Stopwatch.Elapsed.TotalMilliseconds);
  end;
end;

// 開いているファイルの音声を指定サンプル数までPCM16 stereo 48kHzへ順次デコードする
function TFFmpegDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount: Integer; var Pcm: TBytes; var SampleCount: Integer; out Finished: Boolean; out ErrorMessage: string): Boolean;
var
  FormatContext: PAVFormatContext; // 開いている入力コンテキスト
  AudioCodecContext: PAVCodecContext; // 音声デコードコンテキスト
  Packet: PAVPacket; // 読み込みに再利用するAVPacket
  AudioFrame: PAVFrame; // デコード結果を受け取る音声AVFrame
  Ret: Integer; // FFmpeg APIの戻り値
  Chunk: TBytes; // 1フレーム分の変換後PCM
  ChunkSampleCount: Integer; // Chunkに含まれるサンプル数
  OldBytes: Integer; // 追記前のPCMバッファサイズ

  // 受け取った音声AVFrameをPCMキャッシュの末尾へ追加する。
  procedure AppendDecodedAudioFrame;
  begin
    if not ConvertAudioFrameToPcm16Stereo48k(AudioFrame, PSwrContext(FSwrContext),
      FInfo.Audio.SampleRate, Chunk, ChunkSampleCount) then
      Exit;

    OldBytes := Length(Pcm);
    SetLength(Pcm, OldBytes + Length(Chunk));
    if Length(Chunk) > 0 then
      Move(Chunk[0], Pcm[OldBytes], Length(Chunk));
    Inc(SampleCount, ChunkSampleCount);
  end;

begin
  ErrorMessage := '';
  Finished := False;
  Result := False;

  if TargetSampleCount <= SampleCount then
  begin
    Result := True;
    Exit;
  end;

  FormatContext := PAVFormatContext(FFormatContext);
  AudioCodecContext := PAVCodecContext(FAudioCodecContext);
  Packet := PAVPacket(FPacket);
  AudioFrame := PAVFrame(FAudioFrame);

  if (not FInfo.Audio.Present) or (AudioCodecContext = nil) or (Packet = nil) or
     (AudioFrame = nil) or (FSwrContext = nil) or (FormatContext = nil) then
  begin
    ErrorMessage := 'Audio decoder is not open. ' + FInfo.Audio.OpenError;
    Exit;
  end;

  try
    while (SampleCount < TargetSampleCount) and (TFFmpegApi.av_read_frame(FormatContext, Packet) >= 0) do
    begin
      try
        if Packet.stream_index <> FAudioStreamIndex then
          Continue;

        Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, Packet);
        if Ret < 0 then
          Continue;

        while (SampleCount < TargetSampleCount) and (TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0) do
          AppendDecodedAudioFrame;
      finally
        TFFmpegApi.av_packet_unref(Packet);
      end;
    end;

    if SampleCount < TargetSampleCount then
    begin
      Ret := TFFmpegApi.avcodec_send_packet(AudioCodecContext, nil);
      if Ret >= 0 then
        while (SampleCount < TargetSampleCount) and (TFFmpegApi.avcodec_receive_frame(AudioCodecContext, AudioFrame) = 0) do
          AppendDecodedAudioFrame;
      Finished := True;
    end;

    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.ClassName + ': ' + E.Message;
  end;
end;

// 一時デコーダで動画情報だけを読む
class function TFFmpegDecoder.ReadVideoInfo(const FileName: string; out Info: TVideoInfo; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder; // 情報取得だけに使う一時デコーダ
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

// 一時デコーダで指定位置のフレームだけを読む
class function TFFmpegDecoder.DecodeFrameToBitmap(const FileName: string; PositionMs: Integer; Bitmap: TBitmap; out ErrorMessage: string): Boolean;
var
  Decoder: TFFmpegDecoder; // フレーム取得だけに使う一時デコーダ
  Info: TVideoInfo; // 一時デコーダで取得する動画情報
begin
  Decoder := TFFmpegDecoder.Create;
  try
    Result := Decoder.Open(FileName, Info, ErrorMessage);
    if Result then
      Result := Decoder.DecodeFrameToBitmap(PositionMs, Bitmap, ErrorMessage);
  finally
    Decoder.Free;
  end;
end;

end.
