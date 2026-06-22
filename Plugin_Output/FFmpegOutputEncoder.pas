unit FFmpegOutputEncoder;

// AviUtl2 の OUTPUT_INFO から映像/音声を取得し、FFmpeg で出力ファイルへエンコードする。
// 出力設定の解釈、FFmpeg encoder/muxer の準備、フレーム変換、進捗/診断ログを担当する。

interface

uses
  System.SysUtils, System.Math, AviUtl2OutputTypes, FFmpegOutputConfig;

type
  // 出力進捗 UI へ現在位置と瞬間/平均/最小/最大 FPS を通知する。
  TOutputProgressEvent = procedure(Current, Total: Integer; CurrentFps,
    AverageFps, MinFps, MaxFps: Double) of object;

// AviUtl2のOUTPUT_INFOをFFmpegへ流して現在設定の形式で書き出す公開入口。
function ExportOutputInfo(oip: POutputInfo; const Settings: TOutputTestSettings;
  out ErrorMessage: string): Boolean;
// 外部UIから出力中断を要求する。
procedure RequestOutputAbort;

implementation

uses
  Winapi.Windows, System.Classes, System.Diagnostics, FFmpegApi,
  FFmpegOutputApiTypes, FFmpegOutputPerfLog, FFmpegOutputPreview,
  FFmpegOutputVideoInput;

const
  OUTPUT_TEST_FORMAT_PCM16    = 1;                                // AviUtl2へ要求するPCM16音声format
  OUTPUT_VIDEO_BUFFER_COUNT   = 8;                                // AviUtl2のvideo先読みbuffer数
  OUTPUT_AUDIO_BUFFER_COUNT   = 16;                               // AviUtl2のaudio先読みbuffer数
  AUDIO_ENCODER_FRAME_SAMPLES = 1024;                             // AACへ渡す1frameあたりのsample数
  AUDIO_READ_CHUNK_SAMPLES    = AUDIO_ENCODER_FRAME_SAMPLES * 16; // AviUtl2からまとめて取得するsample数
  AV_SAMPLE_FMT_FLTP          = 8;                                // FFmpegのAAC encoder入力sample format
  ALPHA_LOG_FIRST_FRAMES      = 5;                                // alpha診断を必ず出す先頭frame数
  ALPHA_LOG_EVERY_N_FRAMES    = 30;                               // alpha診断を定期出力する間隔

var
  CurrentAborted                  : Boolean;                          // UI側から出力中断が要求されたか
  avformat_alloc_output_context2  : Tavformat_alloc_output_context2;  // muxer contextを作成するFFmpeg関数
  avformat_new_stream             : Tavformat_new_stream;             // muxerへstreamを追加するFFmpeg関数
  avformat_write_header           : Tavformat_write_header;           // コンテナheaderを書き込むFFmpeg関数
  av_interleaved_write_frame      : Tav_interleaved_write_frame;      // packetをstream間で時刻順に書くFFmpeg関数
  av_write_trailer                : Tav_write_trailer;                // コンテナtrailerを書き込むFFmpeg関数
  avformat_free_context           : Tavformat_free_context;           // muxer contextを解放するFFmpeg関数
  avio_open                       : Tavio_open;                       // 出力先IOを開くFFmpeg関数
  avio_closep                     : Tavio_closep;                     // 出力先IOを閉じるFFmpeg関数
  avcodec_find_encoder_by_name    : Tavcodec_find_encoder_by_name;    // 名前からencoderを取得するFFmpeg関数
  avcodec_parameters_from_context : Tavcodec_parameters_from_context; // codec contextをstreamへ反映するFFmpeg関数
  avcodec_send_frame              : Tavcodec_send_frame;              // encoderへframeを渡すFFmpeg関数
  avcodec_receive_packet          : Tavcodec_receive_packet;          // encoderからpacketを受け取るFFmpeg関数
  av_packet_rescale_ts            : Tav_packet_rescale_ts;            // packet timestampをstream時刻へ変換するFFmpeg関数
  av_frame_get_buffer             : Tav_frame_get_buffer;             // frame用bufferを確保するFFmpeg関数
  av_frame_make_writable          : Tav_frame_make_writable;          // frame bufferを書き込み可能にするFFmpeg関数
  av_opt_set                      : Tav_opt_set;                      // FFmpeg optionへ文字列値を設定する関数
  av_opt_set_int                  : Tav_opt_set_int;                  // FFmpeg optionへ整数値を設定する関数
  av_opt_set_sample_fmt           : Tav_opt_set_sample_fmt;           // FFmpeg optionへsample formatを設定する関数
  av_opt_set_chlayout             : Tav_opt_set_chlayout;             // FFmpeg optionへchannel layoutを設定する関数
  OutputApiLoaded                 : Boolean;                          // 出力用FFmpeg関数を遅延取得済みか

// 中断要求フラグを立てる。
procedure RequestOutputAbort;
begin
  CurrentAborted := True;
end;

// UIまたはAviUtl2側から中断要求が出ているか返す。
function OutputAbortRequested(oip: POutputInfo): Boolean;
begin
  Result := CurrentAborted;
  if (not Result) and (oip <> nil) and Assigned(oip^.func_is_abort) then
    Result := oip^.func_is_abort;
end;

// 出力に必要なFFmpeg関数をDLLから遅延取得する。
procedure LoadOutputApi;
begin
  if OutputApiLoaded then
    Exit;

  TFFmpegApi.EnsureLoaded;

  avformat_alloc_output_context2 := Tavformat_alloc_output_context2(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_alloc_output_context2'));
  avformat_new_stream := Tavformat_new_stream(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_new_stream'));
  avformat_write_header := Tavformat_write_header(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_write_header'));
  av_interleaved_write_frame := Tav_interleaved_write_frame(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'av_interleaved_write_frame'));
  av_write_trailer := Tav_write_trailer(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'av_write_trailer'));
  avformat_free_context := Tavformat_free_context(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_free_context'));
  avio_open := Tavio_open(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avio_open'));
  avio_closep := Tavio_closep(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avio_closep'));

  avcodec_find_encoder_by_name := Tavcodec_find_encoder_by_name(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_find_encoder_by_name'));
  avcodec_parameters_from_context := Tavcodec_parameters_from_context(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_parameters_from_context'));
  avcodec_send_frame := Tavcodec_send_frame(TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_send_frame'));
  avcodec_receive_packet := Tavcodec_receive_packet(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_receive_packet'));
  av_packet_rescale_ts := Tav_packet_rescale_ts(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'av_packet_rescale_ts'));

  av_frame_get_buffer := Tav_frame_get_buffer(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_frame_get_buffer'));
  av_frame_make_writable := Tav_frame_make_writable(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_frame_make_writable'));
  av_opt_set := Tav_opt_set(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set'));
  av_opt_set_int := Tav_opt_set_int(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set_int'));
  av_opt_set_sample_fmt := Tav_opt_set_sample_fmt(
    TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set_sample_fmt'));
  av_opt_set_chlayout := Tav_opt_set_chlayout(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set_chlayout'));

  OutputApiLoaded := True;
end;

// FFmpeg戻り値を共通形式のエラーメッセージへ変換する。
function CheckFFmpeg(ResultCode: Integer; const Operation: string; out ErrorMessage: string): Boolean;
begin
  Result := ResultCode >= 0;
  if not Result then
    ErrorMessage := Operation + ': ' + TFFmpegApi.ErrorText(ResultCode);
end;

// MP4/MOV系プレイヤーが解釈するdisplay matrix回転metadataをstreamへ追加する。
function AddVideoDisplayRotation(Stream: PAVStream; RotationDegrees: Integer;
  out ErrorMessage: string): Boolean;
const
  DISPLAY_MATRIX_SIZE = 9 * SizeOf(Integer);
var
  SideData: PAVPacketSideData; // codec parametersへ追加したdisplay matrix side data
begin
  ErrorMessage := '';
  Result := False;

  if Stream = nil then
  begin
    ErrorMessage := 'video stream is nil.';
    Exit;
  end;
  if RotationDegrees mod 360 = 0 then
  begin
    Result := True;
    Exit;
  end;

  if Stream^.codecpar = nil then
  begin
    ErrorMessage := 'video codec parameters is nil.';
    Exit;
  end;

  SideData := TFFmpegApi.av_packet_side_data_new(
    @Stream^.codecpar^.coded_side_data, @Stream^.codecpar^.nb_coded_side_data,
    AV_PKT_DATA_DISPLAYMATRIX, DISPLAY_MATRIX_SIZE, 0);
  if (SideData = nil) or (SideData^.data = nil) or
     (SideData^.size < DISPLAY_MATRIX_SIZE) then
  begin
    ErrorMessage := 'av_packet_side_data_new(displaymatrix) failed.';
    Exit;
  end;

  TFFmpegApi.av_display_rotation_set(PInteger(SideData^.data), RotationDegrees);
  Result := True;
end;

// PCM16音声buffer内の最大絶対振幅を返す。
function Pcm16MaxAbs(Data: Pointer; SampleCount, Channels: Integer): Integer;
var
  Values: PSmallInt;
  Index: Integer;
  TotalValues: Integer;
  Value: Integer;
begin
  Result := 0;
  if (Data = nil) or (SampleCount <= 0) or (Channels <= 0) then
    Exit;

  Values := PSmallInt(Data);
  TotalValues := SampleCount * Channels;
  for Index := 0 to TotalValues - 1 do
  begin
    Value := Values^;
    if Value < 0 then
      Value := -Value;
    if Value > Result then
      Result := Value;
    Inc(Values);
  end;
end;

// alpha診断ログを出す対象フレームか返す。
function ShouldLogAlphaFrame(FrameIndex, TotalFrames: Integer): Boolean;
begin
  Result := (FrameIndex < ALPHA_LOG_FIRST_FRAMES) or
    ((ALPHA_LOG_EVERY_N_FRAMES > 0) and ((FrameIndex mod ALPHA_LOG_EVERY_N_FRAMES) = 0)) or
    (FrameIndex = TotalFrames - 1);
end;

// PA64入力フレームのalpha値分布をログ用文字列にする。
function Pa64InputAlphaStatsText(FrameData: Pointer; Width, Height: Integer): string;
var
  Alpha: Cardinal;
  FullCount: Int64;
  MaxAlpha: Cardinal;
  MinAlpha: Cardinal;
  NonFullCount: Int64;
  Pixel: PWord;
  PixelCount: Int64;
  Row: Integer;
  RowData: PByte;
  SampleA0: Cardinal;
  SampleCenter: Cardinal;
  Stride: Integer;
  X: Integer;
  ZeroCount: Int64;
begin
  if (FrameData = nil) or (Width <= 0) or (Height <= 0) then
  begin
    Result := 'pa64_input invalid';
    Exit;
  end;

  Stride := OutputVideoInputStrideBytes(ovikPa64, Width);
  PixelCount := Int64(Width) * Height;
  MinAlpha := High(Cardinal);
  MaxAlpha := 0;
  ZeroCount := 0;
  FullCount := 0;
  NonFullCount := 0;
  SampleA0 := 0;
  SampleCenter := 0;

  for Row := 0 to Height - 1 do
  begin
    RowData := PByte(NativeUInt(FrameData) + NativeUInt(Row * Stride));
    Pixel := PWord(RowData);
    for X := 0 to Width - 1 do
    begin
      Inc(Pixel, 3);
      Alpha := Pixel^;
      Inc(Pixel);
      if (Row = 0) and (X = 0) then
        SampleA0 := Alpha;
      if (Row = Height div 2) and (X = Width div 2) then
        SampleCenter := Alpha;
      if Alpha < MinAlpha then
        MinAlpha := Alpha;
      if Alpha > MaxAlpha then
        MaxAlpha := Alpha;
      if Alpha = 0 then
        Inc(ZeroCount);
      if Alpha = 65535 then
        Inc(FullCount)
      else
        Inc(NonFullCount);
    end;
  end;

  if PixelCount <= 0 then
    PixelCount := 1;
  Result := Format(
    'pa64_input alpha_min=%d alpha_max=%d zero=%d full=%d non_full=%d ' +
    'zero_pct=%.3f full_pct=%.3f sample_a00=%d sample_acenter=%d',
    [MinAlpha, MaxAlpha, ZeroCount, FullCount, NonFullCount,
     ZeroCount * 100.0 / PixelCount, FullCount * 100.0 / PixelCount,
     SampleA0, SampleCenter]);
end;

// 16bit planeの値分布をログ用文字列にする。
function Plane16StatsText(const LabelText: string; Data: PByte; Width, Height,
  Linesize: Integer; FullValue: Cardinal): string;
var
  FullCount: Int64;
  MaxValue: Cardinal;
  MinValue: Cardinal;
  NonFullCount: Int64;
  PixelCount: Int64;
  Row: Integer;
  RowData: PWord;
  Sample0: Cardinal;
  SampleCenter: Cardinal;
  Value: Cardinal;
  X: Integer;
  ZeroCount: Int64;
begin
  if (Data = nil) or (Width <= 0) or (Height <= 0) or (Linesize = 0) then
  begin
    Result := LabelText + ' invalid';
    Exit;
  end;

  PixelCount := Int64(Width) * Height;
  MinValue := High(Cardinal);
  MaxValue := 0;
  ZeroCount := 0;
  FullCount := 0;
  NonFullCount := 0;
  Sample0 := 0;
  SampleCenter := 0;

  for Row := 0 to Height - 1 do
  begin
    RowData := PWord(NativeUInt(Data) + NativeUInt(Row * Linesize));
    for X := 0 to Width - 1 do
    begin
      Value := RowData^;
      Inc(RowData);
      if (Row = 0) and (X = 0) then
        Sample0 := Value;
      if (Row = Height div 2) and (X = Width div 2) then
        SampleCenter := Value;
      if Value < MinValue then
        MinValue := Value;
      if Value > MaxValue then
        MaxValue := Value;
      if Value = 0 then
        Inc(ZeroCount);
      if Value = FullValue then
        Inc(FullCount)
      else
        Inc(NonFullCount);
    end;
  end;

  if PixelCount <= 0 then
    PixelCount := 1;
  Result := Format(
    '%s min=%d max=%d zero=%d full=%d non_full=%d zero_pct=%.3f full_pct=%.3f sample00=%d sample_center=%d',
    [LabelText, MinValue, MaxValue, ZeroCount, FullCount, NonFullCount,
     ZeroCount * 100.0 / PixelCount, FullCount * 100.0 / PixelCount,
     Sample0, SampleCenter]);
end;

// 映像encoderを開けなかった理由をユーザー向けに整形する。
function VideoEncoderOpenErrorMessage(ResultCode: Integer;
  const Settings: TOutputTestSettings): string;
var
  Detail: string;
begin
  Detail := TFFmpegApi.ErrorText(ResultCode);
  Result := Format('avcodec_open2: %s'#13#10#13#10 +
    'Encoder: %s (%s)'#13#10 +
    'Pixel format: %s'#13#10 +
    'Preset: %s',
    [Detail, Settings.Video.CodecName, string(Settings.Video.EncoderName),
     Settings.Video.PixelFormatName, string(Settings.Video.Preset)]);

  if Settings.EncodeMode = oemNormal then
  begin
    case Settings.Video.EncoderKind of
      oekNvidiaNvenc:
        Result := Result + #13#10#13#10 +
          'NVIDIA NVENC is present in the FFmpeg DLL, but it could not be opened. ' +
          'If the error is "Function not implemented", the NVIDIA driver is often too old ' +
          'for the NVENC API required by this FFmpeg build, or NVENC is unavailable on this GPU.';
      oekAmdAmf:
        Result := Result + #13#10#13#10 +
          'AMD AMF is present in the FFmpeg DLL, but it could not be opened. ' +
          'Check that an AMD GPU and current AMD driver/runtime are available.';
      oekIntelQsv:
        Result := Result + #13#10#13#10 +
          'Intel QSV is present in the FFmpeg DLL, but it could not be opened. ' +
          'Check that the Intel GPU driver/runtime is available.';
    end;
  end;
end;

// encoderから出てきたpacketをmuxerへ書き込み、実際に進捗があったか返す。
function ReceiveAndWritePacketsWithCount(FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext; Stream: PAVStream; Packet: PAVPacket;
  out PacketCount: Integer; out ErrorMessage: string): Boolean;
var
  Code: Integer;
  CodecPublic: PAVCodecContextPublic;
begin
  Result := False;
  PacketCount := 0;
  CodecPublic := PAVCodecContextPublic(CodecContext);

  while True do
  begin
    Code := avcodec_receive_packet(CodecContext, Packet);
    if (Code = AVERROR_EAGAIN) or (Code = AVERROR_EOF) then
      Break;
    if Code < 0 then
    begin
      ErrorMessage := 'avcodec_receive_packet: ' + TFFmpegApi.ErrorText(Code);
      Exit;
    end;

    av_packet_rescale_ts(Packet, CodecPublic^.time_base, Stream^.time_base);
    Packet^.stream_index := Stream^.index;
    Code := av_interleaved_write_frame(FormatContext, Packet);
    TFFmpegApi.av_packet_unref(Packet);
    if not CheckFFmpeg(Code, 'av_interleaved_write_frame', ErrorMessage) then
      Exit;
    Inc(PacketCount);
  end;

  Result := True;
end;

// encoderから出てきたpacketをmuxerへ書き込む。
function ReceiveAndWritePackets(FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext; Stream: PAVStream; Packet: PAVPacket;
  out ErrorMessage: string): Boolean;
var
  PacketCount: Integer;
begin
  Result := ReceiveAndWritePacketsWithCount(FormatContext, CodecContext, Stream,
    Packet, PacketCount, ErrorMessage);
end;

// frame送信とpacket回収をまとめて行う。Frame=nilでflushする。
function SendFrameAndWritePackets(FormatContext: PAVFormatContext;
  CodecContext: PAVCodecContext; Stream: PAVStream; Packet: PAVPacket;
  Frame: PAVFrame; out ErrorMessage: string): Boolean;
var
  Code: Integer;
  PacketCount: Integer;
begin
  Result := False;
  while True do
  begin
    Code := avcodec_send_frame(CodecContext, Frame);
    if Code = AVERROR_EAGAIN then
    begin
      if not ReceiveAndWritePacketsWithCount(FormatContext, CodecContext, Stream,
        Packet, PacketCount, ErrorMessage) then
        Exit;
      if PacketCount <= 0 then
      begin
        ErrorMessage := 'avcodec_send_frame returned EAGAIN, but avcodec_receive_packet produced no packet.';
        Exit;
      end;
      Continue;
    end;
    if Code < 0 then
    begin
      ErrorMessage := 'avcodec_send_frame: ' + TFFmpegApi.ErrorText(Code);
      Exit;
    end;
    Break;
  end;

  Result := ReceiveAndWritePackets(FormatContext, CodecContext, Stream, Packet, ErrorMessage);
end;

// プレビュー/check logへ表示するエンコード設定説明を作る。
function OutputEncodeDescription(const Settings: TOutputTestSettings;
  const EffectiveSettings: TOutputTestSettings;
  VideoInputKind: TOutputVideoInputKind): string;
var
  AudioText: string;
  RotateText: string;
begin
  if EffectiveSettings.Audio.Enabled then
    AudioText := Format('%s / %s / %d kbps / %d Hz / %d ch',
      [EffectiveSettings.Audio.CodecName, string(EffectiveSettings.Audio.EncoderName),
       EffectiveSettings.Audio.BitRate div 1000, EffectiveSettings.Audio.SampleRate,
       EffectiveSettings.Audio.Channels])
  else
    AudioText := '音声なし';

  if (Settings.EncodeMode = oemNormal) and
    (NormalizeOutputRotationDegrees(Settings.RotateOutputDegrees) <> 0) then
    RotateText := Format(' / rotation_metadata=%d',
      [NormalizeOutputRotationDegrees(Settings.RotateOutputDegrees)])
  else
    RotateText := '';

  Result := Format('コンテナ=%s / 映像=%s / encoder=%s / pixel=%s / ' +
    'video_bitrate=%d kbps / preset=%s / 入力=%s / 音声=%s%s',
    [Settings.Container, Settings.Video.CodecName, string(Settings.Video.EncoderName),
     Settings.Video.PixelFormatName, Settings.Video.BitRate div 1000,
     string(Settings.Video.Preset), OutputVideoInputName(VideoInputKind), AudioText,
     RotateText]);
end;

// 設定からAviUtl2へ要求する映像入力形式を決める。
function OutputVideoInputKindForSettings(const Settings: TOutputTestSettings): TOutputVideoInputKind;
begin
  case Settings.EncodeMode of
    oemAlphaProRes:
      Result := ovikPa64;
  else
    Result := OUTPUT_VIDEO_INPUT_KIND;
  end;
end;

// 音声streamとAAC encoderを開く。
function OpenAudioEncoder(FormatContext: PAVFormatContext; const Settings: TOutputTestSettings;
  out AudioCodecContext: PAVCodecContext; out AudioStream: PAVStream;
  out ErrorMessage: string): Boolean;
var
  Codec: PAVCodec;
  CodecPublic: PAVCodecContextPublic;
  Layout: TAVChannelLayout;
  Code: Integer;
begin
  Result := False;
  AudioCodecContext := nil;
  AudioStream := nil;
  FillChar(Layout, SizeOf(Layout), 0);

  Codec := avcodec_find_encoder_by_name(PAnsiChar(Settings.Audio.EncoderName));
  if Codec = nil then
  begin
    ErrorMessage := 'AAC encoder was not found in FFmpeg DLLs.';
    Exit;
  end;

  AudioCodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
  if AudioCodecContext = nil then
  begin
    ErrorMessage := 'audio avcodec_alloc_context3 failed.';
    Exit;
  end;

  CodecPublic := PAVCodecContextPublic(AudioCodecContext);
  TFFmpegApi.av_channel_layout_default(@Layout, Settings.Audio.Channels);
  try
    CodecPublic^.codec_type := AVMEDIA_TYPE_AUDIO;
    CodecPublic^.bit_rate := Settings.Audio.BitRate;
    CodecPublic^.sample_rate := Settings.Audio.SampleRate;
    CodecPublic^.sample_fmt := AV_SAMPLE_FMT_FLTP;
    CodecPublic^.time_base.num := 1;
    CodecPublic^.time_base.den := Settings.Audio.SampleRate;
    CodecPublic^.flags := CodecPublic^.flags or AV_CODEC_FLAG_GLOBAL_HEADER;
    Code := TFFmpegApi.av_channel_layout_copy(@CodecPublic^.ch_layout, @Layout);
    if not CheckFFmpeg(Code, 'audio av_channel_layout_copy', ErrorMessage) then
      Exit;

    if Assigned(av_opt_set_int) then
    begin
      av_opt_set_int(AudioCodecContext, 'b', Settings.Audio.BitRate, 0);
      av_opt_set_int(AudioCodecContext, 'sample_rate', Settings.Audio.SampleRate, 0);
    end;
    if Assigned(av_opt_set_sample_fmt) then
      av_opt_set_sample_fmt(AudioCodecContext, 'sample_fmt', AV_SAMPLE_FMT_FLTP, 0);
    if Assigned(av_opt_set_chlayout) then
      av_opt_set_chlayout(AudioCodecContext, 'ch_layout', @Layout, 0);

    Code := TFFmpegApi.avcodec_open2(AudioCodecContext, Codec, nil);
    if not CheckFFmpeg(Code, 'audio avcodec_open2', ErrorMessage) then
      Exit;

    AudioStream := avformat_new_stream(FormatContext, nil);
    if AudioStream = nil then
    begin
      ErrorMessage := 'audio avformat_new_stream failed.';
      Exit;
    end;
    AudioStream^.time_base := CodecPublic^.time_base;

    Code := avcodec_parameters_from_context(AudioStream^.codecpar, AudioCodecContext);
    if not CheckFFmpeg(Code, 'audio avcodec_parameters_from_context', ErrorMessage) then
      Exit;

    Result := True;
  finally
    TFFmpegApi.av_channel_layout_uninit(@Layout);
  end;
end;

// AviUtl2のfunc_get_audioからPCM16を指定sample位置まで先読みする。
function PrefetchAudioUntilSample(oip: POutputInfo; const Settings: TOutputTestSettings;
  PerfLogger: TOutputPerfLogger; var AudioPcm: TBytes; var AudioSampleCount: Integer;
  TargetSample: Integer;
  out ErrorMessage: string): Boolean;
var
  SampleStart: Integer;
  SamplesToRead: Integer;
  Readed: Integer;
  AudioData: Pointer;
  StageStopwatch: TStopwatch;
  LastAudioTraceSample: Integer;
  BytesPerSample: Integer;
  TotalBytes: Int64;
  DestOffset: Int64;
  CopyBytes: Int64;
  MaxAbs: Integer;
begin
  Result := False;
  LastAudioTraceSample := 0;
  BytesPerSample := Settings.Audio.Channels * SizeOf(SmallInt);

  if (oip = nil) or (oip^.audio_n <= 0) or (BytesPerSample <= 0) then
  begin
    Result := True;
    Exit;
  end;
  TargetSample := EnsureRange(TargetSample, 0, oip^.audio_n);
  if AudioSampleCount >= TargetSample then
  begin
    Result := True;
    Exit;
  end;

  TotalBytes := Int64(oip^.audio_n) * BytesPerSample;
  if TotalBytes > MaxInt then
  begin
    ErrorMessage := Format('audio prefetch buffer is too large: %d bytes', [TotalBytes]);
    Exit;
  end;
  SetLength(AudioPcm, Integer(TotalBytes));
  SampleStart := AudioSampleCount;

  if PerfLogger <> nil then
    PerfLogger.Trace(Format('audio_prefetch_begin sample=%d target=%d total_samples=%d rate=%d ch=%d bytes=%d',
      [SampleStart, TargetSample, oip^.audio_n, Settings.Audio.SampleRate,
       Settings.Audio.Channels, TotalBytes]));

  while SampleStart < TargetSample do
  begin
    if OutputAbortRequested(oip) then
    begin
      CurrentAborted := True;
      ErrorMessage := 'Output was stopped.';
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('audio_prefetch_abort_requested sample=%d/%d',
          [SampleStart, oip^.audio_n]));
      Exit;
    end;

    SamplesToRead := Min(AUDIO_READ_CHUNK_SAMPLES, TargetSample - SampleStart);
    if PerfLogger <> nil then
      PerfLogger.Trace(Format('audio_prefetch_read_begin sample=%d length=%d',
        [SampleStart, SamplesToRead]));
    StageStopwatch := TStopwatch.StartNew;
    AudioData := oip^.func_get_audio(SampleStart, SamplesToRead, @Readed, OUTPUT_TEST_FORMAT_PCM16);
    StageStopwatch.Stop;
    if PerfLogger <> nil then
    begin
      PerfLogger.Add(opsGetAudio, StopwatchElapsedMs(StageStopwatch));
      PerfLogger.Trace(Format('audio_prefetch_read_end sample=%d requested=%d ' +
        'readed=%d elapsed_ms=%.3f data_nil=%s',
        [SampleStart, SamplesToRead, Readed, StopwatchElapsedMs(StageStopwatch),
         BoolToStr(AudioData = nil, True)]));
    end;

    if OutputAbortRequested(oip) then
    begin
      CurrentAborted := True;
      ErrorMessage := 'Output was stopped.';
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('audio_prefetch_abort_requested_after_read sample=%d/%d',
          [SampleStart, oip^.audio_n]));
      Exit;
    end;

    if Readed > SamplesToRead then
      Readed := SamplesToRead;
    if (AudioData = nil) or (Readed <= 0) then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('audio_prefetch_short_read sample=%d requested=%d readed=%d data_nil=%s',
          [SampleStart, SamplesToRead, Readed, BoolToStr(AudioData = nil, True)]));
      Break;
    end;

    DestOffset := Int64(SampleStart) * BytesPerSample;
    CopyBytes := Int64(Readed) * BytesPerSample;
    MaxAbs := Pcm16MaxAbs(AudioData, Readed, Settings.Audio.Channels);
    if PerfLogger <> nil then
      PerfLogger.Trace(Format('audio_prefetch_chunk_stats sample=%d readed=%d max_abs=%d silent=%s',
        [SampleStart, Readed, MaxAbs, BoolToStr(MaxAbs = 0, True)]));
    Move(PByte(AudioData)^, AudioPcm[Integer(DestOffset)], Integer(CopyBytes));
    Inc(SampleStart, Readed);
    AudioSampleCount := SampleStart;

    if (PerfLogger <> nil) and
      ((SampleStart - LastAudioTraceSample) >= Settings.Audio.SampleRate * 5) then
    begin
      LastAudioTraceSample := SampleStart;
      PerfLogger.Trace(Format('audio_prefetch_progress sample=%d/%d',
        [SampleStart, oip^.audio_n]));
    end;
  end;

  AudioSampleCount := SampleStart;
  if PerfLogger <> nil then
    PerfLogger.Trace(Format('audio_prefetch_end samples=%d/%d target=%d',
      [AudioSampleCount, oip^.audio_n, TargetSample]));
  Result := True;
end;

// 映像フレーム位置に対応する音声sample位置を返す。
function AudioTargetSampleForFrame(oip: POutputInfo; FrameCount: Integer): Integer;
var
  Target: Int64;
begin
  Result := 0;
  if (oip = nil) or (oip^.audio_n <= 0) or (oip^.audio_rate <= 0) or
    (oip^.rate <= 0) or (oip^.scale <= 0) then
    Exit;
  if FrameCount >= oip^.n then
  begin
    Result := oip^.audio_n;
    Exit;
  end;

  Target := (Int64(FrameCount) * Int64(oip^.audio_rate) * Int64(oip^.scale) +
    oip^.rate - 1) div oip^.rate;
  if Target > oip^.audio_n then
    Target := oip^.audio_n;
  Result := Integer(Target);
end;

// 先読み済みPCM16をAACへ変換して書く。
function EncodeAudioFromPcmBuffer(FormatContext: PAVFormatContext; AudioCodecContext: PAVCodecContext;
  AudioStream: PAVStream; Packet: PAVPacket; oip: POutputInfo; const Settings: TOutputTestSettings;
  AudioPcm: PByte; AudioSampleCount: Integer; PerfLogger: TOutputPerfLogger;
  out ErrorMessage: string): Boolean;
var
  Frame: PAVFrame;
  AudioFrame: PAVFrameAudioPublic;
  SwrContext: PSwrContext;
  InLayout: TAVChannelLayout;
  OutLayout: TAVChannelLayout;
  InData: array[0..0] of PByte;
  OutData: array[0..7] of Pointer;
  SampleStart: Integer;
  SamplesToRead: Integer;
  AudioData: Pointer;
  ConvertedSamples: Integer;
  Code: Integer;
  StageStopwatch: TStopwatch;
  LastAudioTraceSample: Integer;
  ChannelIndex: Integer;
  EncodeOk: Boolean;
  AudioOffset: Integer;
  EncodeSamples: Integer;
  AudioBaseSample: Integer;
  BytesPerSample: Integer;
begin
  Result := False;
  Frame := nil;
  SwrContext := nil;
  FillChar(InLayout, SizeOf(InLayout), 0);
  FillChar(OutLayout, SizeOf(OutLayout), 0);
  SampleStart := 0;
  LastAudioTraceSample := 0;
  BytesPerSample := Settings.Audio.Channels * SizeOf(SmallInt);
  if PerfLogger <> nil then
    PerfLogger.Trace(Format('audio_encode_begin total_samples=%d rate=%d ch=%d source=prefetched',
      [AudioSampleCount, Settings.Audio.SampleRate, Settings.Audio.Channels]));

  TFFmpegApi.av_channel_layout_default(@InLayout, Settings.Audio.Channels);
  TFFmpegApi.av_channel_layout_default(@OutLayout, Settings.Audio.Channels);
  try
    Code := TFFmpegApi.swr_alloc_set_opts2(@SwrContext, @OutLayout, AV_SAMPLE_FMT_FLTP,
      Settings.Audio.SampleRate, @InLayout, AV_SAMPLE_FMT_S16, Settings.Audio.SampleRate, 0, nil);
    if not CheckFFmpeg(Code, 'audio swr_alloc_set_opts2', ErrorMessage) then
      Exit;
    Code := TFFmpegApi.swr_init(SwrContext);
    if not CheckFFmpeg(Code, 'audio swr_init', ErrorMessage) then
      Exit;

    Frame := TFFmpegApi.av_frame_alloc();
    if Frame = nil then
    begin
      ErrorMessage := 'audio av_frame_alloc failed.';
      Exit;
    end;
    AudioFrame := PAVFrameAudioPublic(Frame);
    AudioFrame^.format := AV_SAMPLE_FMT_FLTP;
    AudioFrame^.nb_samples := AUDIO_ENCODER_FRAME_SAMPLES;
    AudioFrame^.sample_rate := Settings.Audio.SampleRate;
    Code := TFFmpegApi.av_channel_layout_copy(@AudioFrame^.ch_layout, @OutLayout);
    if not CheckFFmpeg(Code, 'audio frame av_channel_layout_copy', ErrorMessage) then
      Exit;

    Code := av_frame_get_buffer(Frame, 0);
    if not CheckFFmpeg(Code, 'audio av_frame_get_buffer', ErrorMessage) then
      Exit;

    while SampleStart < AudioSampleCount do
    begin
      if OutputAbortRequested(oip) then
      begin
        CurrentAborted := True;
        Result := False;
        ErrorMessage := 'Output was stopped.';
        if PerfLogger <> nil then
          PerfLogger.Trace(Format('audio_abort_requested sample=%d/%d',
            [SampleStart, AudioSampleCount]));
        Exit;
      end;

      SamplesToRead := Min(AUDIO_READ_CHUNK_SAMPLES, AudioSampleCount - SampleStart);
      AudioData := Pointer(NativeUInt(AudioPcm) + NativeUInt(SampleStart) * NativeUInt(BytesPerSample));

      AudioBaseSample := SampleStart;
      AudioOffset := 0;
      while AudioOffset < SamplesToRead do
      begin
        if OutputAbortRequested(oip) then
        begin
          CurrentAborted := True;
          Result := False;
          ErrorMessage := 'Output was stopped.';
          if PerfLogger <> nil then
            PerfLogger.Trace(Format('audio_abort_requested_inside_chunk sample=%d/%d',
              [AudioBaseSample + AudioOffset, AudioSampleCount]));
          Exit;
        end;

        EncodeSamples := Min(AUDIO_ENCODER_FRAME_SAMPLES, SamplesToRead - AudioOffset);
        StageStopwatch := TStopwatch.StartNew;
        Code := av_frame_make_writable(Frame);
        StageStopwatch.Stop;
        if PerfLogger <> nil then
          PerfLogger.Add(opsAudioWritable, StopwatchElapsedMs(StageStopwatch));
        if not CheckFFmpeg(Code, 'audio av_frame_make_writable', ErrorMessage) then
        begin
          Result := False;
          Exit;
        end;

        AudioFrame^.nb_samples := EncodeSamples;
        AudioFrame^.pts := AudioBaseSample + AudioOffset;
        FillChar(InData, SizeOf(InData), 0);
        FillChar(OutData, SizeOf(OutData), 0);
        InData[0] := PByte(NativeUInt(AudioData) +
          NativeUInt(AudioOffset) * NativeUInt(Settings.Audio.Channels) * SizeOf(SmallInt));
        for ChannelIndex := 0 to Min(Settings.Audio.Channels, Length(OutData)) - 1 do
          OutData[ChannelIndex] := Frame^.data[ChannelIndex];
        StageStopwatch := TStopwatch.StartNew;
        ConvertedSamples := TFFmpegApi.swr_convert(SwrContext, @OutData[0], EncodeSamples,
          @InData[0], EncodeSamples);
        StageStopwatch.Stop;
        if PerfLogger <> nil then
          PerfLogger.Add(opsAudioConvert, StopwatchElapsedMs(StageStopwatch));
        if ConvertedSamples <= 0 then
        begin
          Result := False;
          ErrorMessage := 'audio swr_convert failed.';
          Exit;
        end;
        AudioFrame^.nb_samples := ConvertedSamples;

        StageStopwatch := TStopwatch.StartNew;
        EncodeOk := SendFrameAndWritePackets(FormatContext, AudioCodecContext, AudioStream,
          Packet, Frame, ErrorMessage);
        StageStopwatch.Stop;
        if PerfLogger <> nil then
          PerfLogger.Add(opsAudioEncodeWrite, StopwatchElapsedMs(StageStopwatch));
        if not EncodeOk then
        begin
          Result := False;
          Exit;
        end;
        Inc(AudioOffset, EncodeSamples);
      end;
      Inc(SampleStart, SamplesToRead);
      if (PerfLogger <> nil) and
        ((SampleStart - LastAudioTraceSample) >= Settings.Audio.SampleRate * 5) then
      begin
        LastAudioTraceSample := SampleStart;
        PerfLogger.Trace(Format('audio_progress sample=%d/%d',
          [SampleStart, AudioSampleCount]));
      end;
    end;

    if PerfLogger <> nil then
      PerfLogger.Trace(Format('audio_flush_begin sample=%d/%d',
        [SampleStart, AudioSampleCount]));
    StageStopwatch := TStopwatch.StartNew;
    Result := SendFrameAndWritePackets(FormatContext, AudioCodecContext, AudioStream,
      Packet, nil, ErrorMessage);
    StageStopwatch.Stop;
    if PerfLogger <> nil then
      PerfLogger.Add(opsAudioEncodeWrite, StopwatchElapsedMs(StageStopwatch));
    if not Result then
      Exit;
    if PerfLogger <> nil then
      PerfLogger.Trace(Format('audio_flush_end elapsed_ms=%.3f',
        [StopwatchElapsedMs(StageStopwatch)]));

    Result := True;
  finally
    if SwrContext <> nil then
      TFFmpegApi.swr_free(@SwrContext);
    if Frame <> nil then
    begin
      AudioFrame := PAVFrameAudioPublic(Frame);
      TFFmpegApi.av_channel_layout_uninit(@AudioFrame^.ch_layout);
      TFFmpegApi.av_frame_free(@Frame);
    end;
    TFFmpegApi.av_channel_layout_uninit(@OutLayout);
    TFFmpegApi.av_channel_layout_uninit(@InLayout);
  end;
end;

// 映像取得、色変換、video/audio encode、mux、perf logをまとめて実行する。
function RunDirectFfmpegEncode(oip: POutputInfo; const Settings: TOutputTestSettings;
  OnProgress: TOutputProgressEvent; out ErrorMessage: string): Boolean;
var
  SaveFileUtf8: UTF8String;
  FormatContext: PAVFormatContext;
  Codec: PAVCodec;
  CodecContext: PAVCodecContext;
  AudioCodecContext: PAVCodecContext;
  CodecPublic: PAVCodecContextPublic;
  Stream: PAVStream;
  AudioStream: PAVStream;
  Frame: PAVFrame;
  Packet: PAVPacket;
  EffectiveSaveFileName: string;
  OriginalSaveFileName: string;
  MuxerFormatName: AnsiString;
  SwsContext: PSwsContext;
  SrcData: array[0..7] of Pointer;
  SrcStride: array[0..7] of Integer;
  DstData: array[0..7] of Pointer;
  DstStride: array[0..7] of Integer;
  FrameIndex: Integer;
  FrameData: Pointer;
  Code: Integer;
  FrameStopwatch: TStopwatch;
  StageStopwatch: TStopwatch;
  TotalStopwatch: TStopwatch;
  OverallStopwatch: TStopwatch;
  FrameSeconds: Double;
  CurrentFps: Double;
  AverageFps: Double;
  MinFps: Double;
  MaxFps: Double;
  Aborted: Boolean;
  EndOfSource: Boolean;
  FatalAfterHeader: Boolean;
  EncodedFrameCount: Integer;
  EncoderPixelFormat: Integer;
  PerfLogger: TOutputPerfLogger;
  PerfLogFinished: Boolean;
  PerfStatus: string;
  EffectiveSettings: TOutputTestSettings;
  AudioPcm: TBytes;
  AudioSampleCount: Integer;
  AudioTargetSample: Integer;
  PreviewWindow: TOutputPreviewWindow;
  VideoInputKind: TOutputVideoInputKind;
  RotateOutputDegrees: Integer;
  OutputWidth: Integer;
  OutputHeight: Integer;
begin
  Result := False;
  ErrorMessage := '';
  FormatContext := nil;
  CodecContext := nil;
  AudioCodecContext := nil;
  Frame := nil;
  Packet := nil;
  SwsContext := nil;
  Aborted := False;
  EndOfSource := False;
  FatalAfterHeader := False;
  EncodedFrameCount := 0;
  PerfLogFinished := False;
  PerfStatus := 'not_started';
  AudioSampleCount := 0;
  PreviewWindow := nil;

  EffectiveSettings := Settings;
  VideoInputKind := OutputVideoInputKindForSettings(Settings);
  RotateOutputDegrees := 0;
  if Settings.EncodeMode = oemNormal then
    RotateOutputDegrees :=
      NormalizeOutputRotationDegrees(Settings.RotateOutputDegrees);
  OutputWidth := oip^.w;
  OutputHeight := oip^.h;
  if ((oip^.flag and OUTPUT_INFO_FLAG_AUDIO) <> 0) and (oip^.audio_n > 0) then
  begin
    if oip^.audio_rate > 0 then
      EffectiveSettings.Audio.SampleRate := oip^.audio_rate;
    if oip^.audio_ch > 0 then
      EffectiveSettings.Audio.Channels := oip^.audio_ch;
  end;

  LoadOutputApi;
  OriginalSaveFileName := Settings.SaveFileName;
  if OriginalSaveFileName = '' then
    OriginalSaveFileName := string(oip^.savefile);
  EffectiveSaveFileName := OriginalSaveFileName;
  MuxerFormatName := '';
  if Settings.EncodeMode = oemAlphaProRes then
  begin
    MuxerFormatName := 'mov';
    if not SameText(ExtractFileExt(EffectiveSaveFileName), '.mov') then
      EffectiveSaveFileName := ChangeFileExt(EffectiveSaveFileName, '.mov');
  end;
  SaveFileUtf8 := UTF8String(EffectiveSaveFileName);
  EncoderPixelFormat := OutputPixelFormatFFmpegValue(Settings.Video.PixelFormat);
  if EncoderPixelFormat < 0 then
  begin
    ErrorMessage := 'FFmpeg pixel format was not found: ' + Settings.Video.PixelFormatName;
    Exit;
  end;
  OverallStopwatch := TStopwatch.StartNew;
  if OUTPUT_PERF_LOG_ENABLED then
    PerfLogger := TOutputPerfLogger.Create(EffectiveSaveFileName, oip^.w, oip^.h, oip^.n,
      string(Settings.Video.EncoderName), Settings.Video.PixelFormatName,
      OutputVideoInputName(VideoInputKind), OUTPUT_VIDEO_BUFFER_COUNT, OUTPUT_AUDIO_BUFFER_COUNT,
      Settings.Audio.Enabled, string(Settings.Audio.EncoderName), Settings.Audio.BitRate,
      EffectiveSettings.Audio.SampleRate, EffectiveSettings.Audio.Channels)
  else
    PerfLogger := nil;

  try
    if PerfLogger <> nil then
      PerfLogger.Trace(Format('encode_begin output_info w=%d h=%d frames=%d ' +
        'rate=%d scale=%d audio_flag=%d audio_n=%d audio_rate=%d audio_ch=%d ' +
        'rotate_degrees=%d output_w=%d output_h=%d',
        [oip^.w, oip^.h, oip^.n, oip^.rate, oip^.scale, oip^.flag,
         oip^.audio_n, oip^.audio_rate, oip^.audio_ch, RotateOutputDegrees,
         OutputWidth, OutputHeight]));
    if (PerfLogger <> nil) and (OriginalSaveFileName <> EffectiveSaveFileName) then
      PerfLogger.Trace(Format('output_filename_adjusted from="%s" to="%s" reason=alpha_prores_requires_mov',
        [OriginalSaveFileName, EffectiveSaveFileName]));
    if PerfLogger <> nil then
      PerfLogger.Trace(Format('audio_prefetch_mode frame_synced read_chunk_samples=%d',
        [AUDIO_READ_CHUNK_SAMPLES]));

    if MuxerFormatName <> '' then
      Code := avformat_alloc_output_context2(@FormatContext, nil, PAnsiChar(MuxerFormatName),
        PAnsiChar(SaveFileUtf8))
    else
      Code := avformat_alloc_output_context2(@FormatContext, nil, nil, PAnsiChar(SaveFileUtf8));
    if not CheckFFmpeg(Code, 'avformat_alloc_output_context2', ErrorMessage) then
      Exit;
    if PerfLogger <> nil then
      PerfLogger.Trace('avformat_alloc_output_context2 ok');

    Codec := avcodec_find_encoder_by_name(PAnsiChar(Settings.Video.EncoderName));
    if Codec = nil then
    begin
      ErrorMessage := Settings.Video.CodecName + ' encoder was not found in FFmpeg DLLs.';
      Exit;
    end;

    CodecContext := TFFmpegApi.avcodec_alloc_context3(Codec);
    if CodecContext = nil then
    begin
      ErrorMessage := 'avcodec_alloc_context3 failed.';
      Exit;
    end;
    CodecPublic := PAVCodecContextPublic(CodecContext);
    CodecPublic^.bit_rate := Settings.Video.BitRate;
    CodecPublic^.width := OutputWidth;
    CodecPublic^.height := OutputHeight;
    CodecPublic^.time_base.num := oip^.scale;
    CodecPublic^.time_base.den := oip^.rate;
    CodecPublic^.framerate.num := oip^.rate;
    CodecPublic^.framerate.den := oip^.scale;
    CodecPublic^.pix_fmt := EncoderPixelFormat;
    CodecPublic^.max_b_frames := 0;
    CodecPublic^.flags := CodecPublic^.flags or AV_CODEC_FLAG_GLOBAL_HEADER;

    if CodecPublic^.priv_data <> nil then
    begin
      if Settings.Video.Preset <> '' then
        av_opt_set(CodecPublic^.priv_data, 'preset', PAnsiChar(Settings.Video.Preset), 0);
      if Settings.Video.EncoderKind = oekCpuX264 then
        av_opt_set(CodecPublic^.priv_data, 'crf', PAnsiChar(AnsiString(IntToStr(Settings.Video.Quality))), 0);
      if Settings.EncodeMode = oemAlphaProRes then
      begin
        av_opt_set(CodecPublic^.priv_data, 'profile', PAnsiChar(AnsiString('4444')), 0);
        if Assigned(av_opt_set_int) then
          av_opt_set_int(CodecPublic^.priv_data, 'alpha_bits', 16, 0);
      end;
    end;

    Code := TFFmpegApi.avcodec_open2(CodecContext, Codec, nil);
    if Code < 0 then
    begin
      ErrorMessage := VideoEncoderOpenErrorMessage(Code, Settings);
      Exit;
    end;
    if PerfLogger <> nil then
      PerfLogger.Trace('video avcodec_open2 ok');

    Stream := avformat_new_stream(FormatContext, nil);
    if Stream = nil then
    begin
      ErrorMessage := 'avformat_new_stream failed.';
      Exit;
    end;
    Stream^.time_base := CodecPublic^.time_base;

    Code := avcodec_parameters_from_context(Stream^.codecpar, CodecContext);
    if not CheckFFmpeg(Code, 'avcodec_parameters_from_context', ErrorMessage) then
      Exit;
    if RotateOutputDegrees <> 0 then
    begin
      if not AddVideoDisplayRotation(Stream, -RotateOutputDegrees, ErrorMessage) then
        Exit;
      if PerfLogger <> nil then
        PerfLogger.Trace(Format(
          'video display_rotation_metadata=%d clockwise%d',
          [-RotateOutputDegrees, RotateOutputDegrees]));
    end;

    if ((oip^.flag and OUTPUT_INFO_FLAG_AUDIO) <> 0) and (oip^.audio_n > 0) and
      Assigned(oip^.func_get_audio) and Settings.Audio.Enabled then
    begin
      if not OpenAudioEncoder(FormatContext, EffectiveSettings,
        AudioCodecContext, AudioStream, ErrorMessage) then
        Exit;
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('audio encoder opened sample_rate=%d channels=%d total_samples=%d',
          [EffectiveSettings.Audio.SampleRate, EffectiveSettings.Audio.Channels, oip^.audio_n]));
    end;

    Code := avio_open(@FormatContext^.pb, PAnsiChar(SaveFileUtf8), AVIO_FLAG_WRITE);
    if not CheckFFmpeg(Code, 'avio_open', ErrorMessage) then
      Exit;
    if PerfLogger <> nil then
      PerfLogger.Trace('avio_open ok');

    Code := avformat_write_header(FormatContext, nil);
    if not CheckFFmpeg(Code, 'avformat_write_header', ErrorMessage) then
      Exit;
    if PerfLogger <> nil then
      PerfLogger.Trace('avformat_write_header ok');

    Frame := TFFmpegApi.av_frame_alloc();
    if Frame = nil then
    begin
      ErrorMessage := 'av_frame_alloc failed.';
      Exit;
    end;
    Frame^.format := EncoderPixelFormat;
    Frame^.width := OutputWidth;
    Frame^.height := OutputHeight;
    Code := av_frame_get_buffer(Frame, 32);
    if not CheckFFmpeg(Code, 'av_frame_get_buffer', ErrorMessage) then
      Exit;

    Packet := TFFmpegApi.av_packet_alloc();
    if Packet = nil then
    begin
      ErrorMessage := 'av_packet_alloc failed.';
      Exit;
    end;

    SwsContext := TFFmpegApi.sws_getContext(oip^.w, oip^.h,
      OutputVideoInputFFmpegPixelFormat(VideoInputKind), OutputWidth, OutputHeight,
      EncoderPixelFormat, SWS_BILINEAR, nil, nil, nil);
    if SwsContext = nil then
    begin
      ErrorMessage := 'sws_getContext failed.';
      Exit;
    end;
    if Assigned(oip^.func_set_buffer_size) then
    begin
      oip^.func_set_buffer_size(OUTPUT_VIDEO_BUFFER_COUNT, OUTPUT_AUDIO_BUFFER_COUNT);
      if PerfLogger <> nil then
        PerfLogger.Trace('func_set_buffer_size called');
    end;

    PreviewWindow := TOutputPreviewWindow.Create(EffectiveSaveFileName,
      OutputEncodeDescription(Settings, EffectiveSettings, VideoInputKind), oip^.w, oip^.h,
      oip^.n, oip^.rate, oip^.scale, VideoInputKind, RotateOutputDegrees,
      Settings.ShowCheckLogAfterEncode);
    if PerfLogger <> nil then
      PerfLogger.Trace('preview_window_created');

    TotalStopwatch := TStopwatch.StartNew;
    CurrentFps := 0;
    AverageFps := 0;
    MinFps := MaxDouble;
    MaxFps := 0;
    FrameIndex := 0;
    if (not Aborted) and (not FatalAfterHeader) then
    for FrameIndex := 0 to oip^.n - 1 do
    begin
      FrameStopwatch := TStopwatch.StartNew;
      if OutputAbortRequested(oip) then
      begin
        CurrentAborted := True;
        Aborted := True;
        Break;
      end;

      StageStopwatch := TStopwatch.StartNew;
      FrameData := oip^.func_get_video(FrameIndex, OutputVideoInputAviUtlFormat(VideoInputKind));
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsGetVideo, StopwatchElapsedMs(StageStopwatch));
      if FrameData = nil then
      begin
        if (FrameIndex > 0) or (EncodedFrameCount > 0) then
        begin
          EndOfSource := True;
          if PerfLogger <> nil then
            PerfLogger.Trace(Format('video_source_end frame_index=%d encoded_frames=%d',
              [FrameIndex, EncodedFrameCount]));
          Break;
        end;
        ErrorMessage := 'func_get_video returned nil.';
        Exit;
      end;
      if (PerfLogger <> nil) and (VideoInputKind = ovikPa64) and
        ShouldLogAlphaFrame(FrameIndex, oip^.n) then
        PerfLogger.Trace(Format('alpha_source frame=%d %s',
          [FrameIndex, Pa64InputAlphaStatsText(FrameData, oip^.w, oip^.h)]));
      if PreviewWindow <> nil then
        PreviewWindow.UpdateFrame(FrameIndex, FrameData);

      StageStopwatch := TStopwatch.StartNew;
      Code := av_frame_make_writable(Frame);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsFrameWritable, StopwatchElapsedMs(StageStopwatch));
      if not CheckFFmpeg(Code, 'av_frame_make_writable', ErrorMessage) then
      begin
        FatalAfterHeader := True;
        Break;
      end;

      FillChar(SrcData, SizeOf(SrcData), 0);
      FillChar(SrcStride, SizeOf(SrcStride), 0);
      FillChar(DstData, SizeOf(DstData), 0);
      FillChar(DstStride, SizeOf(DstStride), 0);
      SrcData[0] := Pointer(NativeUInt(FrameData) +
        OutputVideoInputFirstLineOffset(VideoInputKind, oip^.w, oip^.h));
      SrcStride[0] := OutputVideoInputSwsStride(VideoInputKind, oip^.w);
      StageStopwatch := TStopwatch.StartNew;
      DstData[0] := Frame^.data[0];
      DstData[1] := Frame^.data[1];
      DstData[2] := Frame^.data[2];
      DstData[3] := Frame^.data[3];
      DstStride[0] := Frame^.linesize[0];
      DstStride[1] := Frame^.linesize[1];
      DstStride[2] := Frame^.linesize[2];
      DstStride[3] := Frame^.linesize[3];
      TFFmpegApi.sws_scale(SwsContext, @SrcData[0], @SrcStride[0], 0, oip^.h,
        @DstData[0], @DstStride[0]);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsVideoConvert, StopwatchElapsedMs(StageStopwatch));
      if (PerfLogger <> nil) and (VideoInputKind = ovikPa64) and
        ShouldLogAlphaFrame(FrameIndex, oip^.n) then
        PerfLogger.Trace(Format('alpha_after_sws frame=%d data3_nil=%s linesize3=%d %s',
          [FrameIndex, BoolToStr(Frame^.data[3] = nil, True), Frame^.linesize[3],
           Plane16StatsText('yuva_alpha_plane', Frame^.data[3], oip^.w, oip^.h,
             Frame^.linesize[3], 1023)]));

      Frame^.pts := FrameIndex;
      StageStopwatch := TStopwatch.StartNew;
      Result := SendFrameAndWritePackets(FormatContext, CodecContext, Stream, Packet, Frame, ErrorMessage);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsVideoEncodeWrite, StopwatchElapsedMs(StageStopwatch));
      if not Result then
      begin
        FatalAfterHeader := True;
        Break;
      end;
      Inc(EncodedFrameCount);

      FrameStopwatch.Stop;
      FrameSeconds := FrameStopwatch.Elapsed.TotalSeconds;
      if FrameSeconds > 0 then
        CurrentFps := 1.0 / FrameSeconds
      else
        CurrentFps := 0;
      if CurrentFps > 0 then
      begin
        MinFps := Min(MinFps, CurrentFps);
        MaxFps := Max(MaxFps, CurrentFps);
      end;
      if TotalStopwatch.Elapsed.TotalSeconds > 0 then
        AverageFps := (FrameIndex + 1) / TotalStopwatch.Elapsed.TotalSeconds
      else
        AverageFps := 0;
      if MinFps = MaxDouble then
        MinFps := 0;

      if (AudioCodecContext <> nil) and (not Aborted) and (not FatalAfterHeader) then
      begin
        AudioTargetSample := AudioTargetSampleForFrame(oip, FrameIndex + 1);
        if AudioTargetSample > AudioSampleCount then
        begin
          if PerfLogger <> nil then
            PerfLogger.Trace(Format('audio_prefetch_call_begin frame=%d target_sample=%d',
              [FrameIndex + 1, AudioTargetSample]));
          if not PrefetchAudioUntilSample(oip, EffectiveSettings, PerfLogger, AudioPcm,
            AudioSampleCount, AudioTargetSample, ErrorMessage) then
          begin
            if OutputAbortRequested(oip) or CurrentAborted then
              Aborted := True
            else
              FatalAfterHeader := True;
            Break;
          end;
          if PerfLogger <> nil then
            PerfLogger.Trace(Format('audio_prefetch_call_end frame=%d samples=%d fatal=%s error="%s"',
              [FrameIndex + 1, AudioSampleCount, BoolToStr(FatalAfterHeader, True),
               ErrorMessage]));
        end;
      end;

      if Assigned(oip^.func_rest_time_disp) then
        oip^.func_rest_time_disp(FrameIndex + 1, oip^.n);
      if Assigned(OnProgress) then
        OnProgress(FrameIndex + 1, oip^.n, CurrentFps, AverageFps, MinFps, MaxFps);
      if PerfLogger <> nil then
        PerfLogger.LogFrame(FrameIndex + 1, oip^.n, StopwatchElapsedMs(FrameStopwatch), AverageFps);
    end;

    if PerfLogger <> nil then
      PerfLogger.Trace(Format('video_loop_end frame_index=%d encoded_frames=%d ' +
        'aborted=%s end_of_source=%s fatal=%s',
        [FrameIndex, EncodedFrameCount, BoolToStr(Aborted, True),
         BoolToStr(EndOfSource, True), BoolToStr(FatalAfterHeader, True)]));

    if Aborted or OutputAbortRequested(oip) then
    begin
      CurrentAborted := True;
      Aborted := True;
      if PerfLogger <> nil then
        PerfLogger.Trace('output_abort_skip_flush_trailer');
    end
    else if EncodedFrameCount > 0 then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('video_flush_begin');
      StageStopwatch := TStopwatch.StartNew;
      Result := SendFrameAndWritePackets(FormatContext, CodecContext, Stream, Packet, nil, ErrorMessage);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsVideoEncodeWrite, StopwatchElapsedMs(StageStopwatch));
      if not Result then
        FatalAfterHeader := True;
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('video_flush_end result=%s elapsed_ms=%.3f fatal=%s',
          [BoolToStr(Result, True), StopwatchElapsedMs(StageStopwatch),
           BoolToStr(FatalAfterHeader, True)]));
    end;

    if (not Aborted) and OutputAbortRequested(oip) then
    begin
      CurrentAborted := True;
      Aborted := True;
      if PerfLogger <> nil then
        PerfLogger.Trace('output_abort_after_video_flush');
    end;

    if (not Aborted) and (not FatalAfterHeader) and (CodecContext <> nil) then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('video_codec_free_before_audio_begin');
      TFFmpegApi.avcodec_free_context(@CodecContext);
      if PerfLogger <> nil then
        PerfLogger.Trace('video_codec_free_before_audio_end');
    end;

    if (AudioCodecContext <> nil) and (not Aborted) and (not FatalAfterHeader) then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('audio_encode_call_begin');
      if (Length(AudioPcm) > 0) and (AudioSampleCount > 0) then
        Result := EncodeAudioFromPcmBuffer(FormatContext, AudioCodecContext, AudioStream,
          Packet, oip, EffectiveSettings, @AudioPcm[0], AudioSampleCount, PerfLogger,
          ErrorMessage)
      else
        Result := EncodeAudioFromPcmBuffer(FormatContext, AudioCodecContext, AudioStream,
          Packet, oip, EffectiveSettings, nil, 0, PerfLogger, ErrorMessage);
      if not Result then
      begin
        if OutputAbortRequested(oip) or CurrentAborted then
          Aborted := True
        else
          FatalAfterHeader := True;
      end;
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('audio_encode_call_end fatal=%s error="%s"',
          [BoolToStr(FatalAfterHeader, True), ErrorMessage]));
    end;

    if not Aborted then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('av_write_trailer_begin');
      Code := av_write_trailer(FormatContext);
      if not CheckFFmpeg(Code, 'av_write_trailer', ErrorMessage) then
        Exit;
      if PerfLogger <> nil then
        PerfLogger.Trace('av_write_trailer_end');
    end
    else if PerfLogger <> nil then
      PerfLogger.Trace('av_write_trailer_skipped_by_abort');

    if EndOfSource and Assigned(OnProgress) then
      OnProgress(FrameIndex, FrameIndex, CurrentFps, AverageFps, MinFps, MaxFps);

    if Aborted then
    begin
      if PreviewWindow <> nil then
        PreviewWindow.UpdateStatus('中断しました。');
      ErrorMessage := '';
      PerfStatus := 'aborted';
      Result := False;
    end
    else if FatalAfterHeader then
    begin
      if ErrorMessage = '' then
        ErrorMessage := 'Output stopped after header. Partial MP4 was finalized.';
      if PreviewWindow <> nil then
        PreviewWindow.UpdateStatus('異常により停止しました。');
      PerfStatus := 'fatal_after_header';
      Result := False;
    end
    else
    begin
      if PreviewWindow <> nil then
        PreviewWindow.UpdateStatus('完了しました。');
      PerfStatus := 'ok';
      Result := True;
    end;

    if PerfLogger <> nil then
    begin
      OverallStopwatch.Stop;
      PerfLogger.Finish(EncodedFrameCount, StopwatchElapsedMs(OverallStopwatch), PerfStatus);
      PerfLogFinished := True;
    end;
  finally
    if PreviewWindow <> nil then
      FreeAndNil(PreviewWindow);
    if PerfLogger <> nil then
      PerfLogger.Trace('cleanup_begin');
    if SwsContext <> nil then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_sws_free_begin');
      TFFmpegApi.sws_freeContext(SwsContext);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_sws_free_end');
    end;
    if Packet <> nil then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_packet_free_begin');
      TFFmpegApi.av_packet_free(@Packet);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_packet_free_end');
    end;
    if Frame <> nil then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_frame_free_begin');
      TFFmpegApi.av_frame_free(@Frame);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_frame_free_end');
    end;
    if AudioCodecContext <> nil then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_audio_codec_free_begin');
      TFFmpegApi.avcodec_free_context(@AudioCodecContext);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_audio_codec_free_end');
    end;
    if CodecContext <> nil then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_video_codec_free_begin');
      TFFmpegApi.avcodec_free_context(@CodecContext);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_video_codec_free_end');
    end;
    if (FormatContext <> nil) and (FormatContext^.pb <> nil) then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_avio_close_begin');
      avio_closep(@FormatContext^.pb);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_avio_close_end');
    end;
    if FormatContext <> nil then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_format_free_begin');
      avformat_free_context(FormatContext);
      if PerfLogger <> nil then
        PerfLogger.Trace('cleanup_format_free_end');
    end;
    if PerfLogger <> nil then
      PerfLogger.Trace('cleanup_end');
    if PerfLogger <> nil then
    begin
      if not PerfLogFinished then
      begin
        OverallStopwatch.Stop;
        if PerfStatus = 'not_started' then
          PerfStatus := 'failed_before_finish';
        PerfLogger.Finish(EncodedFrameCount, StopwatchElapsedMs(OverallStopwatch), PerfStatus);
      end;
      PerfLogger.Free;
    end;
  end;
end;

// 公開入口の引数検証を行ってから実エンコードへ渡す。
function ExportOutputInfo(oip: POutputInfo; const Settings: TOutputTestSettings;
  out ErrorMessage: string): Boolean;
begin
  Result := False;
  ErrorMessage := '';
  if oip = nil then
  begin
    ErrorMessage := 'OutputInfo is nil.';
    Exit;
  end;
  if (oip^.w <= 0) or (oip^.h <= 0) or (oip^.n <= 0) then
  begin
    ErrorMessage := 'Output video information is invalid.';
    Exit;
  end;
  if not Assigned(oip^.func_get_video) then
  begin
    ErrorMessage := 'func_get_video is not assigned.';
    Exit;
  end;
  if (oip^.savefile = nil) or (string(oip^.savefile) = '') then
  begin
    ErrorMessage := 'Save file name is empty.';
    Exit;
  end;

  CurrentAborted := False;
  Result := RunDirectFfmpegEncode(oip, Settings, nil, ErrorMessage);
end;

end.
