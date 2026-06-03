unit FFmpegOutputEncoder;

interface

uses
  System.SysUtils, System.Math, AviUtl2OutputTypes, FFmpegDecoderTypes,
  FFmpegOutputConfig;

type
  TOutputProgressEvent = procedure(Current, Total: Integer; CurrentFps,
    AverageFps, MinFps, MaxFps: Double) of object;

function ExportVideoWithOutputCallbacks(const SourceFileName: string;
  const Settings: TOutputTestSettings;
  const SourceInfo: TVideoInfo; OnProgress: TOutputProgressEvent;
  out ErrorMessage: string): Boolean;
function ExportOutputInfo(oip: POutputInfo; const Settings: TOutputTestSettings;
  out ErrorMessage: string): Boolean;
procedure RequestOutputAbort;

implementation

uses
  Winapi.Windows, System.Classes, System.Diagnostics, FFmpegApi, FFmpegDecoder;

const
  OUTPUT_VIDEO_FORMAT_RGB24 = 0;
  OUTPUT_TEST_FORMAT_PCM16 = 1;
  AUDIO_ENCODER_FRAME_SAMPLES = 1024;
  AV_SAMPLE_FMT_FLTP = 8;

type
  PAVCodecContextPublic = ^TAVCodecContextPublic;
  TAVCodecContextPublic = record
    av_class: Pointer;
    log_level_offset: Integer;
    codec_type: Integer;
    codec: PAVCodec;
    codec_id: Integer;
    codec_tag: Cardinal;
    priv_data: Pointer;
    internal: Pointer;
    opaque: Pointer;
    bit_rate: Int64;
    flags: Integer;
    flags2: Integer;
    extradata: PByte;
    extradata_size: Integer;
    time_base: TAVRational;
    pkt_timebase: TAVRational;
    framerate: TAVRational;
    delay: Integer;
    width: Integer;
    height: Integer;
    coded_width: Integer;
    coded_height: Integer;
    sample_aspect_ratio: TAVRational;
    pix_fmt: Integer;
    sw_pix_fmt: Integer;
    color_primaries: Integer;
    color_trc: Integer;
    colorspace: Integer;
    color_range: Integer;
    chroma_sample_location: Integer;
    field_order: Integer;
    refs: Integer;
    has_b_frames: Integer;
    slice_flags: Integer;
    draw_horiz_band: Pointer;
    get_format: Pointer;
    max_b_frames: Integer;
    b_quant_factor: Single;
    b_quant_offset: Single;
    i_quant_factor: Single;
    i_quant_offset: Single;
    lumi_masking: Single;
    temporal_cplx_masking: Single;
    spatial_cplx_masking: Single;
    p_masking: Single;
    dark_masking: Single;
    nsse_weight: Integer;
    me_cmp: Integer;
    me_sub_cmp: Integer;
    mb_cmp: Integer;
    ildct_cmp: Integer;
    dia_size: Integer;
    last_predictor_count: Integer;
    me_pre_cmp: Integer;
    pre_dia_size: Integer;
    me_subpel_quality: Integer;
    me_range: Integer;
    mb_decision: Integer;
    intra_matrix: Pointer;
    inter_matrix: Pointer;
    chroma_intra_matrix: Pointer;
    intra_dc_precision: Integer;
    mb_lmin: Integer;
    mb_lmax: Integer;
    bidir_refine: Integer;
    keyint_min: Integer;
    gop_size: Integer;
    mv0_threshold: Integer;
    slices: Integer;
    sample_rate: Integer;
    sample_fmt: Integer;
    ch_layout: TAVChannelLayout;
    frame_size: Integer;
  end;

  PAVFrameAudioPublic = ^TAVFrameAudioPublic;
  TAVFrameAudioPublic = record
    data: array[0..7] of PByte;
    linesize: array[0..7] of Integer;
    extended_data: Pointer;
    width: Integer;
    height: Integer;
    nb_samples: Integer;
    format: Integer;
    pict_type: Integer;
    sample_aspect_ratio: TAVRational;
    pts: Int64;
    pkt_dts: Int64;
    time_base: TAVRational;
    quality: Integer;
    opaque: Pointer;
    repeat_pict: Integer;
    sample_rate: Integer;
    buf: array[0..7] of Pointer;
    extended_buf: Pointer;
    nb_extended_buf: Integer;
    side_data: Pointer;
    nb_side_data: Integer;
    flags: Integer;
    color_range: Integer;
    color_primaries: Integer;
    color_trc: Integer;
    colorspace: Integer;
    chroma_location: Integer;
    best_effort_timestamp: Int64;
    metadata: Pointer;
    decode_error_flags: Integer;
    hw_frames_ctx: Pointer;
    opaque_ref: Pointer;
    crop_top: NativeUInt;
    crop_bottom: NativeUInt;
    crop_left: NativeUInt;
    crop_right: NativeUInt;
    private_ref: Pointer;
    ch_layout: TAVChannelLayout;
    duration: Int64;
    alpha_mode: Integer;
  end;

  TOutputVideoProvider = class
  private
    FDecoder: TFFmpegDecoder;
    FInfo: TVideoInfo;
    FBuffer: TBytes;
    FNextSequentialFrame: Integer;
    FLastError: string;
  public
    constructor Create(const SourceFileName: string; const SourceInfo: TVideoInfo);
    destructor Destroy; override;
    function GetVideo(Frame: Integer; Format: DWORD): Pointer;
    property LastError: string read FLastError;
  end;

  TOutputAudioProvider = class
  private
    FDecoder: TFFmpegDecoder;
    FCache: TBytes;
    FSampleCount: Integer;
    FFinished: Boolean;
    FLastError: string;
  public
    constructor Create(const SourceFileName: string);
    destructor Destroy; override;
    function GetAudio(Start, Length: Integer; Readed: PInteger; Format: DWORD): Pointer;
    property LastError: string read FLastError;
  end;

  Tav_opt_set_int = function(obj: Pointer; name: PAnsiChar; val: Int64;
    search_flags: Integer): Integer; cdecl;
  Tav_opt_set_sample_fmt = function(obj: Pointer; name: PAnsiChar;
    sample_fmt: Integer; search_flags: Integer): Integer; cdecl;
  Tav_opt_set_chlayout = function(obj: Pointer; name: PAnsiChar;
    const layout: PAVChannelLayout; search_flags: Integer): Integer; cdecl;

var
  CurrentProvider: TOutputVideoProvider;
  CurrentAudioProvider: TOutputAudioProvider;
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

procedure RequestOutputAbort;
begin
  CurrentAborted := True;
end;

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

constructor TOutputVideoProvider.Create(const SourceFileName: string; const SourceInfo: TVideoInfo);
var
  OpenInfo: TVideoInfo;
begin
  inherited Create;
  FInfo := SourceInfo;
  FDecoder := TFFmpegDecoder.Create;
  if not FDecoder.Open(SourceFileName, OpenInfo, FLastError) then
    raise Exception.Create('Failed to open source for output: ' + FLastError);
  SetLength(FBuffer, FInfo.Width * FInfo.Height * 4);
  FNextSequentialFrame := 0;
end;

destructor TOutputVideoProvider.Destroy;
begin
  FDecoder.Free;
  inherited Destroy;
end;

function TOutputVideoProvider.GetVideo(Frame: Integer; Format: DWORD): Pointer;
var
  PositionMs: Integer;
  DecodedPositionMs: Integer;
begin
  Result := nil;
  FLastError := '';
  if (Frame < 0) or (Length(FBuffer) = 0) then
    Exit;
  if Format <> OUTPUT_VIDEO_FORMAT_RGB24 then
  begin
    FLastError := 'Unsupported output test video format.';
    Exit;
  end;

  if Frame = FNextSequentialFrame then
  begin
    if not FDecoder.DecodeNextFrameToBgrx32(@FBuffer[0], FInfo.Width * 4,
      DecodedPositionMs, FLastError) then
      Exit;
    Inc(FNextSequentialFrame);
  end
  else
  begin
    PositionMs := Round(Frame * 1000.0 / FInfo.Fps);
    if not FDecoder.DecodeFrameToBgrx32(PositionMs, @FBuffer[0], FInfo.Width * 4, FLastError) then
      Exit;
    FNextSequentialFrame := Frame + 1;
  end;
  Result := @FBuffer[0];
end;

constructor TOutputAudioProvider.Create(const SourceFileName: string);
var
  OpenInfo: TVideoInfo;
begin
  inherited Create;
  FDecoder := TFFmpegDecoder.Create;
  if not FDecoder.Open(SourceFileName, OpenInfo, FLastError) then
    raise Exception.Create('Failed to open source audio for output: ' + FLastError);
  if not OpenInfo.Audio.Present then
  begin
    FLastError := 'Source has no audio stream.';
    Exit;
  end;
end;

destructor TOutputAudioProvider.Destroy;
begin
  FDecoder.Free;
  inherited Destroy;
end;

function TOutputAudioProvider.GetAudio(Start, Length: Integer; Readed: PInteger;
  Format: DWORD): Pointer;
var
  TargetSampleCount: Integer;
begin
  Result := nil;
  FLastError := '';
  if Readed <> nil then
    Readed^ := 0;

  if (FDecoder = nil) or (Length <= 0) or (Start < 0) then
    Exit;
  if Format <> OUTPUT_TEST_FORMAT_PCM16 then
  begin
    FLastError := 'Unsupported output test audio format.';
    Exit;
  end;

  TargetSampleCount := Start + Length;
  if (not FFinished) and (FSampleCount < TargetSampleCount) then
  begin
    if not FDecoder.DecodeAudioPcm16Stereo48kUntil(TargetSampleCount, FCache,
      FSampleCount, FFinished, FLastError) then
      Exit;
  end;

  if Start >= FSampleCount then
    Exit;

  if Readed <> nil then
    Readed^ := Min(Length, FSampleCount - Start);
  if (Readed = nil) or (Readed^ <= 0) then
    Exit;

  Result := @FCache[Start * AUDIO_OUTPUT_CHANNELS * SizeOf(SmallInt)];
end;

function OutputGetVideo(Frame: Integer; Format: DWORD): Pointer; cdecl;
begin
  Result := nil;
  if CurrentProvider <> nil then
    Result := CurrentProvider.GetVideo(Frame, Format);
end;

function OutputGetAudio(Start, Length: Integer; Readed: PInteger; Format: DWORD): Pointer; cdecl;
begin
  if Readed <> nil then
    Readed^ := 0;
  if CurrentAudioProvider <> nil then
    Result := CurrentAudioProvider.GetAudio(Start, Length, Readed, Format)
  else
    Result := nil;
end;

function OutputIsAbort: Boolean; cdecl;
begin
  Result := CurrentAborted;
end;

procedure OutputRestTimeDisp(NowValue, TotalValue: Integer); cdecl;
begin
end;

procedure OutputSetBufferSize(VideoSize, AudioSize: Integer); cdecl;
begin
end;

function CheckFFmpeg(ResultCode: Integer; const Operation: string; out ErrorMessage: string): Boolean;
begin
  Result := ResultCode >= 0;
  if not Result then
    ErrorMessage := Operation + ': ' + TFFmpegApi.ErrorText(ResultCode);
end;

function ReceiveAndWritePackets(FormatContext: PAVFormatContext; CodecContext: PAVCodecContext;
  Stream: PAVStream; Packet: PAVPacket; out ErrorMessage: string): Boolean;
var
  Code: Integer;
  CodecPublic: PAVCodecContextPublic;
begin
  Result := False;
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
  end;

  Result := True;
end;

function SendFrameAndWritePackets(FormatContext: PAVFormatContext; CodecContext: PAVCodecContext;
  Stream: PAVStream; Packet: PAVPacket; Frame: PAVFrame; out ErrorMessage: string): Boolean;
var
  Code: Integer;
begin
  Result := False;
  while True do
  begin
    Code := avcodec_send_frame(CodecContext, Frame);
    if Code = AVERROR_EAGAIN then
    begin
      if not ReceiveAndWritePackets(FormatContext, CodecContext, Stream, Packet, ErrorMessage) then
        Exit;
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

function EncodeAudioFromCallbacks(FormatContext: PAVFormatContext; AudioCodecContext: PAVCodecContext;
  AudioStream: PAVStream; Packet: PAVPacket; oip: POutputInfo; const Settings: TOutputTestSettings;
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
  Readed: Integer;
  AudioData: Pointer;
  ConvertedSamples: Integer;
  Code: Integer;
begin
  Result := False;
  Frame := nil;
  SwrContext := nil;
  FillChar(InLayout, SizeOf(InLayout), 0);
  FillChar(OutLayout, SizeOf(OutLayout), 0);
  SampleStart := 0;

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
        Break;

      SamplesToRead := Min(AUDIO_ENCODER_FRAME_SAMPLES, oip^.audio_n - SampleStart);
      AudioData := oip^.func_get_audio(SampleStart, SamplesToRead, @Readed, OUTPUT_TEST_FORMAT_PCM16);
      if (AudioData = nil) or (Readed <= 0) then
        Break;

      Code := av_frame_make_writable(Frame);
      if not CheckFFmpeg(Code, 'audio av_frame_make_writable', ErrorMessage) then
        Exit;

      AudioFrame^.nb_samples := Readed;
      AudioFrame^.pts := SampleStart;
      FillChar(InData, SizeOf(InData), 0);
      FillChar(OutData, SizeOf(OutData), 0);
      InData[0] := PByte(AudioData);
      OutData[0] := Frame^.data[0];
      OutData[1] := Frame^.data[1];
      ConvertedSamples := TFFmpegApi.swr_convert(SwrContext, @OutData[0], Readed,
        @InData[0], Readed);
      if ConvertedSamples <= 0 then
      begin
        ErrorMessage := 'audio swr_convert failed.';
        Exit;
      end;
      AudioFrame^.nb_samples := ConvertedSamples;

      if not SendFrameAndWritePackets(FormatContext, AudioCodecContext, AudioStream,
        Packet, Frame, ErrorMessage) then
        Exit;
      Inc(SampleStart, Readed);
    end;

    if not SendFrameAndWritePackets(FormatContext, AudioCodecContext, AudioStream,
      Packet, nil, ErrorMessage) then
      Exit;

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
  TotalStopwatch: TStopwatch;
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

  LoadOutputApi;
  SaveFileUtf8 := UTF8String(string(oip^.savefile));
  EncoderPixelFormat := OutputPixelFormatFFmpegValue(Settings.Video.PixelFormat);

  Code := avformat_alloc_output_context2(@FormatContext, nil, nil, PAnsiChar(SaveFileUtf8));
  if not CheckFFmpeg(Code, 'avformat_alloc_output_context2', ErrorMessage) then
    Exit;

  try
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
    if not CheckFFmpeg(Code, 'avcodec_open2', ErrorMessage) then
      Exit;

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
      if not OpenAudioEncoder(FormatContext, Settings, AudioCodecContext, AudioStream, ErrorMessage) then
        Exit;
    end;

    Code := avio_open(@FormatContext^.pb, PAnsiChar(SaveFileUtf8), AVIO_FLAG_WRITE);
    if not CheckFFmpeg(Code, 'avio_open', ErrorMessage) then
      Exit;

    Code := avformat_write_header(FormatContext, nil);
    if not CheckFFmpeg(Code, 'avformat_write_header', ErrorMessage) then
      Exit;

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

    SwsContext := TFFmpegApi.sws_getContext(oip^.w, oip^.h, AV_PIX_FMT_BGR24,
      oip^.w, oip^.h, EncoderPixelFormat, SWS_BILINEAR, nil, nil, nil);
    if SwsContext = nil then
    begin
      ErrorMessage := 'sws_getContext failed.';
      Exit;
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

      FrameData := oip^.func_get_video(FrameIndex, OUTPUT_VIDEO_FORMAT_RGB24);
      if FrameData = nil then
      begin
        if (FrameIndex > 0) or (EncodedFrameCount > 0) then
        begin
          if (CurrentProvider <> nil) and (CurrentProvider.LastError <> '') and
            (CurrentProvider.LastError <> 'End of stream.') then
          begin
            FatalAfterHeader := True;
            ErrorMessage := 'Output stopped while reading frame ' + IntToStr(FrameIndex) +
              ': ' + CurrentProvider.LastError;
          end
          else
            EndOfSource := True;
          Break;
        end
        else if CurrentProvider <> nil then
          ErrorMessage := CurrentProvider.LastError
        else
          ErrorMessage := 'func_get_video returned nil.';
        Exit;
      end;

      Code := av_frame_make_writable(Frame);
      if not CheckFFmpeg(Code, 'av_frame_make_writable', ErrorMessage) then
      begin
        FatalAfterHeader := True;
        Break;
      end;

      FillChar(SrcData, SizeOf(SrcData), 0);
      FillChar(SrcStride, SizeOf(SrcStride), 0);
      FillChar(DstData, SizeOf(DstData), 0);
      FillChar(DstStride, SizeOf(DstStride), 0);
      SrcData[0] := Pointer(NativeUInt(FrameData) + NativeUInt((oip^.h - 1) * oip^.w * 3));
      SrcStride[0] := -oip^.w * 3;
      DstData[0] := Frame^.data[0];
      DstData[1] := Frame^.data[1];
      DstData[2] := Frame^.data[2];
      DstStride[0] := Frame^.linesize[0];
      DstStride[1] := Frame^.linesize[1];
      DstStride[2] := Frame^.linesize[2];
      TFFmpegApi.sws_scale(SwsContext, @SrcData[0], @SrcStride[0], 0, oip^.h,
        @DstData[0], @DstStride[0]);

      Frame^.pts := FrameIndex;
      if not SendFrameAndWritePackets(FormatContext, CodecContext, Stream, Packet, Frame, ErrorMessage) then
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
    end;

    if EncodedFrameCount > 0 then
    begin
      if not SendFrameAndWritePackets(FormatContext, CodecContext, Stream, Packet, nil, ErrorMessage) then
        FatalAfterHeader := True;
    end;

    if (AudioCodecContext <> nil) and (not Aborted) and (not FatalAfterHeader) then
    begin
      if not EncodeAudioFromCallbacks(FormatContext, AudioCodecContext, AudioStream,
        Packet, oip, Settings, ErrorMessage) then
        FatalAfterHeader := True;
    end;

    Code := av_write_trailer(FormatContext);
    if not CheckFFmpeg(Code, 'av_write_trailer', ErrorMessage) then
      Exit;

    if EndOfSource and Assigned(OnProgress) then
      OnProgress(FrameIndex, FrameIndex, CurrentFps, AverageFps, MinFps, MaxFps);

    if Aborted then
    begin
      ErrorMessage := 'Output was stopped. Partial MP4 was finalized.';
      Result := False;
    end
    else if FatalAfterHeader then
    begin
      if ErrorMessage = '' then
        ErrorMessage := 'Output stopped after header. Partial MP4 was finalized.';
      Result := False;
    end
    else
      Result := True;
  finally
    if SwsContext <> nil then
      TFFmpegApi.sws_freeContext(SwsContext);
    if Packet <> nil then
      TFFmpegApi.av_packet_free(@Packet);
    if Frame <> nil then
      TFFmpegApi.av_frame_free(@Frame);
    if AudioCodecContext <> nil then
      TFFmpegApi.avcodec_free_context(@AudioCodecContext);
    if CodecContext <> nil then
      TFFmpegApi.avcodec_free_context(@CodecContext);
    if (FormatContext <> nil) and (FormatContext^.pb <> nil) then
      avio_closep(@FormatContext^.pb);
    if FormatContext <> nil then
      avformat_free_context(FormatContext);
  end;
end;

function ExportVideoWithOutputCallbacks(const SourceFileName: string;
  const Settings: TOutputTestSettings;
  const SourceInfo: TVideoInfo; OnProgress: TOutputProgressEvent;
  out ErrorMessage: string): Boolean;
var
  OutputInfo: TOutputInfo;
  SaveFileWide: string;
  Provider: TOutputVideoProvider;
  AudioProvider: TOutputAudioProvider;
begin
  Result := False;
  ErrorMessage := '';
  if SourceFileName = '' then
  begin
    ErrorMessage := 'Source video is not open.';
    Exit;
  end;
  if (SourceInfo.Width <= 0) or (SourceInfo.Height <= 0) or (SourceInfo.Fps <= 0) then
  begin
    ErrorMessage := 'Source video information is invalid.';
    Exit;
  end;

  Provider := TOutputVideoProvider.Create(SourceFileName, SourceInfo);
  AudioProvider := nil;
  try
    CurrentProvider := Provider;
    if SourceInfo.Audio.Present and Settings.Audio.Enabled then
    begin
      AudioProvider := TOutputAudioProvider.Create(SourceFileName);
      CurrentAudioProvider := AudioProvider;
    end;
    CurrentAborted := False;
    SaveFileWide := Settings.SaveFileName;
    FillChar(OutputInfo, SizeOf(OutputInfo), 0);
    OutputInfo.flag := OUTPUT_INFO_FLAG_VIDEO;
    if AudioProvider <> nil then
      OutputInfo.flag := OutputInfo.flag or OUTPUT_INFO_FLAG_AUDIO;
    OutputInfo.w := SourceInfo.Width;
    OutputInfo.h := SourceInfo.Height;
    OutputInfo.rate := Round(SourceInfo.Fps * 1000);
    OutputInfo.scale := 1000;
    OutputInfo.n := Max(1, Round(SourceInfo.DurationSec * SourceInfo.Fps));
    OutputInfo.audio_rate := Settings.Audio.SampleRate;
    OutputInfo.audio_ch := Settings.Audio.Channels;
    if AudioProvider <> nil then
      OutputInfo.audio_n := Max(1, Round(SourceInfo.DurationSec * Settings.Audio.SampleRate));
    OutputInfo.savefile := PWideChar(SaveFileWide);
    OutputInfo.func_get_video := OutputGetVideo;
    OutputInfo.func_get_audio := OutputGetAudio;
    OutputInfo.func_is_abort := OutputIsAbort;
    OutputInfo.func_rest_time_disp := OutputRestTimeDisp;
    OutputInfo.func_set_buffer_size := OutputSetBufferSize;

    Result := RunDirectFfmpegEncode(@OutputInfo, Settings, OnProgress, ErrorMessage);
  finally
    CurrentProvider := nil;
    CurrentAudioProvider := nil;
    AudioProvider.Free;
    Provider.Free;
  end;
end;

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
