unit FFmpegOutputEncoder;

interface

uses
  System.SysUtils, System.Math, AviUtl2OutputTypes, FFmpegOutputConfig;

type
  TOutputProgressEvent = procedure(Current, Total: Integer; CurrentFps,
    AverageFps, MinFps, MaxFps: Double) of object;

// AviUtl2のOUTPUT_INFOをFFmpegへ流してMP4を書き出す公開入口。
function ExportOutputInfo(oip: POutputInfo; const Settings: TOutputTestSettings;
  out ErrorMessage: string): Boolean;
// 外部UIから出力中断を要求する。
procedure RequestOutputAbort;

implementation

uses
  Winapi.Windows, System.Classes, System.Diagnostics, FFmpegApi,
  FFmpegOutputApiTypes, FFmpegOutputPerfLog, FFmpegOutputVideoInput;

const
  OUTPUT_TEST_FORMAT_PCM16 = 1; // AviUtl2へ要求するPCM16音声format
  OUTPUT_VIDEO_BUFFER_COUNT = 8; // AviUtl2のvideo先読みbuffer数
  OUTPUT_AUDIO_BUFFER_COUNT = 16; // AviUtl2のaudio先読みbuffer数
  AUDIO_ENCODER_FRAME_SAMPLES = 1024; // AACへ渡す1frameあたりのsample数
  AV_SAMPLE_FMT_FLTP = 8; // FFmpegのAAC encoder入力sample format

var
  CurrentAborted: Boolean;
  avformat_alloc_output_context2: Tavformat_alloc_output_context2;
  avformat_new_stream: Tavformat_new_stream;
  avformat_write_header: Tavformat_write_header;
  av_interleaved_write_frame: Tav_interleaved_write_frame;
  av_write_trailer: Tav_write_trailer;
  avformat_free_context: Tavformat_free_context;
  avio_open: Tavio_open;
  avio_closep: Tavio_closep;
  avcodec_find_encoder_by_name: Tavcodec_find_encoder_by_name;
  avcodec_parameters_from_context: Tavcodec_parameters_from_context;
  avcodec_send_frame: Tavcodec_send_frame;
  avcodec_receive_packet: Tavcodec_receive_packet;
  av_packet_rescale_ts: Tav_packet_rescale_ts;
  av_frame_get_buffer: Tav_frame_get_buffer;
  av_frame_make_writable: Tav_frame_make_writable;
  av_opt_set: Tav_opt_set;
  av_opt_set_int: Tav_opt_set_int;
  av_opt_set_sample_fmt: Tav_opt_set_sample_fmt;
  av_opt_set_chlayout: Tav_opt_set_chlayout;
  OutputApiLoaded: Boolean;

// 中断要求フラグを立てる。
procedure RequestOutputAbort;
begin
  CurrentAborted := True;
end;

// 出力に必要なFFmpeg関数をDLLから遅延取得する。
procedure LoadOutputApi;
begin
  if OutputApiLoaded then
    Exit;

  TFFmpegApi.EnsureLoaded;

  avformat_alloc_output_context2 := Tavformat_alloc_output_context2(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_alloc_output_context2'));
  avformat_new_stream := Tavformat_new_stream(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_new_stream'));
  avformat_write_header := Tavformat_write_header(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_write_header'));
  av_interleaved_write_frame := Tav_interleaved_write_frame(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'av_interleaved_write_frame'));
  av_write_trailer := Tav_write_trailer(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'av_write_trailer'));
  avformat_free_context := Tavformat_free_context(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avformat_free_context'));
  avio_open := Tavio_open(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avio_open'));
  avio_closep := Tavio_closep(TFFmpegApi.LoadProc(TFFmpegApi.FAvFormat, 'avio_closep'));

  avcodec_find_encoder_by_name := Tavcodec_find_encoder_by_name(TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_find_encoder_by_name'));
  avcodec_parameters_from_context := Tavcodec_parameters_from_context(TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_parameters_from_context'));
  avcodec_send_frame := Tavcodec_send_frame(TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_send_frame'));
  avcodec_receive_packet := Tavcodec_receive_packet(TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'avcodec_receive_packet'));
  av_packet_rescale_ts := Tav_packet_rescale_ts(TFFmpegApi.LoadProc(TFFmpegApi.FAvCodec, 'av_packet_rescale_ts'));

  av_frame_get_buffer := Tav_frame_get_buffer(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_frame_get_buffer'));
  av_frame_make_writable := Tav_frame_make_writable(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_frame_make_writable'));
  av_opt_set := Tav_opt_set(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set'));
  av_opt_set_int := Tav_opt_set_int(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set_int'));
  av_opt_set_sample_fmt := Tav_opt_set_sample_fmt(TFFmpegApi.LoadProc(TFFmpegApi.FAvUtil, 'av_opt_set_sample_fmt'));
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
function ReceiveAndWritePackets(FormatContext: PAVFormatContext; CodecContext: PAVCodecContext;
  Stream: PAVStream; Packet: PAVPacket; out ErrorMessage: string): Boolean;
var
  PacketCount: Integer;
begin
  Result := ReceiveAndWritePacketsWithCount(FormatContext, CodecContext, Stream,
    Packet, PacketCount, ErrorMessage);
end;

// frame送信とpacket回収をまとめて行う。Frame=nilでflushする。
function SendFrameAndWritePackets(FormatContext: PAVFormatContext; CodecContext: PAVCodecContext;
  Stream: PAVStream; Packet: PAVPacket; Frame: PAVFrame; out ErrorMessage: string): Boolean;
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

// AviUtl2のfunc_get_audioからPCM16を受け取り、AACへ変換して書く。
function EncodeAudioFromCallbacks(FormatContext: PAVFormatContext; AudioCodecContext: PAVCodecContext;
  AudioStream: PAVStream; Packet: PAVPacket; oip: POutputInfo; const Settings: TOutputTestSettings;
  PerfLogger: TOutputPerfLogger; out ErrorMessage: string): Boolean;
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
  Readed: Integer;
  AudioData: Pointer;
  ConvertedSamples: Integer;
  Code: Integer;
  StageStopwatch: TStopwatch;
  LastAudioTraceSample: Integer;
  ChannelIndex: Integer;
begin
  Result := False;
  Frame := nil;
  SwrContext := nil;
  FillChar(InLayout, SizeOf(InLayout), 0);
  FillChar(OutLayout, SizeOf(OutLayout), 0);
  SampleStart := 0;
  LastAudioTraceSample := 0;
  if PerfLogger <> nil then
    PerfLogger.Trace(Format('audio_encode_begin total_samples=%d rate=%d ch=%d',
      [oip^.audio_n, Settings.Audio.SampleRate, Settings.Audio.Channels]));

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

    while SampleStart < oip^.audio_n do
    begin
      if Assigned(oip^.func_is_abort) and oip^.func_is_abort then
      begin
        if PerfLogger <> nil then
          PerfLogger.Trace(Format('audio_abort_requested sample=%d/%d',
            [SampleStart, oip^.audio_n]));
        Break;
      end;

      SamplesToRead := Min(AUDIO_ENCODER_FRAME_SAMPLES, oip^.audio_n - SampleStart);
      StageStopwatch := TStopwatch.StartNew;
      AudioData := oip^.func_get_audio(SampleStart, SamplesToRead, @Readed, OUTPUT_TEST_FORMAT_PCM16);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsGetAudio, StopwatchElapsedMs(StageStopwatch));
      if (AudioData = nil) or (Readed <= 0) then
      begin
        if PerfLogger <> nil then
          PerfLogger.Trace(Format('audio_read_end sample=%d requested=%d readed=%d data_nil=%s',
            [SampleStart, SamplesToRead, Readed, BoolToStr(AudioData = nil, True)]));
        Break;
      end;

      StageStopwatch := TStopwatch.StartNew;
      Code := av_frame_make_writable(Frame);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsAudioWritable, StopwatchElapsedMs(StageStopwatch));
      if not CheckFFmpeg(Code, 'audio av_frame_make_writable', ErrorMessage) then
        Exit;

      AudioFrame^.nb_samples := Readed;
      AudioFrame^.pts := SampleStart;
      FillChar(InData, SizeOf(InData), 0);
      FillChar(OutData, SizeOf(OutData), 0);
      InData[0] := PByte(AudioData);
      for ChannelIndex := 0 to Min(Settings.Audio.Channels, Length(OutData)) - 1 do
        OutData[ChannelIndex] := Frame^.data[ChannelIndex];
      StageStopwatch := TStopwatch.StartNew;
      ConvertedSamples := TFFmpegApi.swr_convert(SwrContext, @OutData[0], Readed,
        @InData[0], Readed);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsAudioConvert, StopwatchElapsedMs(StageStopwatch));
      if ConvertedSamples <= 0 then
      begin
        ErrorMessage := 'audio swr_convert failed.';
        Exit;
      end;
      AudioFrame^.nb_samples := ConvertedSamples;

      StageStopwatch := TStopwatch.StartNew;
      Result := SendFrameAndWritePackets(FormatContext, AudioCodecContext, AudioStream,
        Packet, Frame, ErrorMessage);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsAudioEncodeWrite, StopwatchElapsedMs(StageStopwatch));
      if not Result then
        Exit;
      Inc(SampleStart, Readed);
      if (PerfLogger <> nil) and
        ((SampleStart - LastAudioTraceSample) >= Settings.Audio.SampleRate * 5) then
      begin
        LastAudioTraceSample := SampleStart;
        PerfLogger.Trace(Format('audio_progress sample=%d/%d',
          [SampleStart, oip^.audio_n]));
      end;
    end;

    if PerfLogger <> nil then
      PerfLogger.Trace(Format('audio_flush_begin sample=%d/%d',
        [SampleStart, oip^.audio_n]));
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

  EffectiveSettings := Settings;
  if ((oip^.flag and OUTPUT_INFO_FLAG_AUDIO) <> 0) and (oip^.audio_n > 0) then
  begin
    if oip^.audio_rate > 0 then
      EffectiveSettings.Audio.SampleRate := oip^.audio_rate;
    if oip^.audio_ch > 0 then
      EffectiveSettings.Audio.Channels := oip^.audio_ch;
  end;

  LoadOutputApi;
  SaveFileUtf8 := UTF8String(string(oip^.savefile));
  EncoderPixelFormat := OutputPixelFormatFFmpegValue(Settings.Video.PixelFormat);
  OverallStopwatch := TStopwatch.StartNew;
  if OUTPUT_PERF_LOG_ENABLED then
    PerfLogger := TOutputPerfLogger.Create(string(oip^.savefile), oip^.w, oip^.h, oip^.n,
      string(Settings.Video.EncoderName), Settings.Video.PixelFormatName,
      OutputVideoInputName, OUTPUT_VIDEO_BUFFER_COUNT, OUTPUT_AUDIO_BUFFER_COUNT,
      Settings.Audio.Enabled, string(Settings.Audio.EncoderName), Settings.Audio.BitRate,
      EffectiveSettings.Audio.SampleRate, EffectiveSettings.Audio.Channels)
  else
    PerfLogger := nil;

  try
    if PerfLogger <> nil then
      PerfLogger.Trace(Format('encode_begin output_info w=%d h=%d frames=%d rate=%d scale=%d audio_flag=%d audio_n=%d audio_rate=%d audio_ch=%d',
        [oip^.w, oip^.h, oip^.n, oip^.rate, oip^.scale, oip^.flag,
         oip^.audio_n, oip^.audio_rate, oip^.audio_ch]));

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
    CodecPublic^.width := oip^.w;
    CodecPublic^.height := oip^.h;
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

    if ((oip^.flag and OUTPUT_INFO_FLAG_AUDIO) <> 0) and (oip^.audio_n > 0) and
      Assigned(oip^.func_get_audio) and Settings.Audio.Enabled then
    begin
      if not OpenAudioEncoder(FormatContext, EffectiveSettings, AudioCodecContext, AudioStream, ErrorMessage) then
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
    Frame^.width := oip^.w;
    Frame^.height := oip^.h;
    Code := av_frame_get_buffer(Frame, 32);
    if not CheckFFmpeg(Code, 'av_frame_get_buffer', ErrorMessage) then
      Exit;

    Packet := TFFmpegApi.av_packet_alloc();
    if Packet = nil then
    begin
      ErrorMessage := 'av_packet_alloc failed.';
      Exit;
    end;

    SwsContext := TFFmpegApi.sws_getContext(oip^.w, oip^.h, OutputVideoInputFFmpegPixelFormat,
      oip^.w, oip^.h, EncoderPixelFormat, SWS_BILINEAR, nil, nil, nil);
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

    TotalStopwatch := TStopwatch.StartNew;
    CurrentFps := 0;
    AverageFps := 0;
    MinFps := MaxDouble;
    MaxFps := 0;
    for FrameIndex := 0 to oip^.n - 1 do
    begin
      FrameStopwatch := TStopwatch.StartNew;
      if Assigned(oip^.func_is_abort) and oip^.func_is_abort then
      begin
        Aborted := True;
        Break;
      end;

      StageStopwatch := TStopwatch.StartNew;
      FrameData := oip^.func_get_video(FrameIndex, OutputVideoInputAviUtlFormat);
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
        OutputVideoInputFirstLineOffset(oip^.w, oip^.h));
      SrcStride[0] := OutputVideoInputSwsStride(oip^.w);
      DstData[0] := Frame^.data[0];
      DstData[1] := Frame^.data[1];
      DstData[2] := Frame^.data[2];
      DstStride[0] := Frame^.linesize[0];
      DstStride[1] := Frame^.linesize[1];
      DstStride[2] := Frame^.linesize[2];
      StageStopwatch := TStopwatch.StartNew;
      TFFmpegApi.sws_scale(SwsContext, @SrcData[0], @SrcStride[0], 0, oip^.h,
        @DstData[0], @DstStride[0]);
      StageStopwatch.Stop;
      if PerfLogger <> nil then
        PerfLogger.Add(opsVideoConvert, StopwatchElapsedMs(StageStopwatch));

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

      if Assigned(oip^.func_rest_time_disp) then
        oip^.func_rest_time_disp(FrameIndex + 1, oip^.n);
      if Assigned(OnProgress) then
        OnProgress(FrameIndex + 1, oip^.n, CurrentFps, AverageFps, MinFps, MaxFps);
      if PerfLogger <> nil then
        PerfLogger.LogFrame(FrameIndex + 1, oip^.n, StopwatchElapsedMs(FrameStopwatch), AverageFps);
    end;

    if PerfLogger <> nil then
      PerfLogger.Trace(Format('video_loop_end frame_index=%d encoded_frames=%d aborted=%s end_of_source=%s fatal=%s',
        [FrameIndex, EncodedFrameCount, BoolToStr(Aborted, True),
         BoolToStr(EndOfSource, True), BoolToStr(FatalAfterHeader, True)]));

    if EncodedFrameCount > 0 then
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

    if (AudioCodecContext <> nil) and (not Aborted) and (not FatalAfterHeader) then
    begin
      if PerfLogger <> nil then
        PerfLogger.Trace('audio_encode_call_begin');
      if not EncodeAudioFromCallbacks(FormatContext, AudioCodecContext, AudioStream,
        Packet, oip, EffectiveSettings, PerfLogger, ErrorMessage) then
        FatalAfterHeader := True;
      if PerfLogger <> nil then
        PerfLogger.Trace(Format('audio_encode_call_end fatal=%s error="%s"',
          [BoolToStr(FatalAfterHeader, True), ErrorMessage]));
    end;

    if PerfLogger <> nil then
      PerfLogger.Trace('av_write_trailer_begin');
    Code := av_write_trailer(FormatContext);
    if not CheckFFmpeg(Code, 'av_write_trailer', ErrorMessage) then
      Exit;
    if PerfLogger <> nil then
      PerfLogger.Trace('av_write_trailer_end');

    if EndOfSource and Assigned(OnProgress) then
      OnProgress(FrameIndex, FrameIndex, CurrentFps, AverageFps, MinFps, MaxFps);

    if Aborted then
    begin
      ErrorMessage := 'Output was stopped. Partial MP4 was finalized.';
      PerfStatus := 'aborted';
      Result := False;
    end
    else if FatalAfterHeader then
    begin
      if ErrorMessage = '' then
        ErrorMessage := 'Output stopped after header. Partial MP4 was finalized.';
      PerfStatus := 'fatal_after_header';
      Result := False;
    end
    else
    begin
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
