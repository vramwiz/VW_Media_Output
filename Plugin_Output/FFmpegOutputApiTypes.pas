unit FFmpegOutputApiTypes;

interface

uses
  FFmpegApi;

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

  Tav_opt_set_int = function(obj: Pointer; name: PAnsiChar; val: Int64;
    search_flags: Integer): Integer; cdecl;
  Tav_opt_set_sample_fmt = function(obj: Pointer; name: PAnsiChar;
    sample_fmt: Integer; search_flags: Integer): Integer; cdecl;
  Tav_opt_set_chlayout = function(obj: Pointer; name: PAnsiChar;
    const layout: PAVChannelLayout; search_flags: Integer): Integer; cdecl;

implementation

end.
