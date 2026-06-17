unit FFmpegApi;

// FFmpeg 8.1系DLLをDelphiから呼び出すための低レベルAPI定義ユニット。
// 必要なFFmpeg構造体、関数ポインタ、DLLロード処理、時間軸変換の補助関数をまとめる。

interface

uses
  Winapi.Windows, System.SysUtils;

type
  TAVMediaType = Integer;

  // FFmpegの分数値を表す型。
  TAVRational = record
    num : Integer; // 分子
    den : Integer; // 分母
  end;

  PAVCodecParameters = ^TAVCodecParameters;
  PAVChannelLayout = ^TAVChannelLayout;
  // FFmpegのチャンネルレイアウト情報。
  TAVChannelLayout = record
    order       : Integer; // レイアウト表現方式
    nb_channels : Integer; // チャンネル数
    u           : UInt64;  // FFmpeg側のレイアウト値
    opaque      : Pointer; // FFmpeg内部用ポインタ
  end;

  // FFmpegストリームのコーデック基本情報。
  TAVCodecParameters = record
    codec_type             : TAVMediaType;     // 映像/音声などのメディア種別
    codec_id               : Integer;          // FFmpegのコーデックID
    codec_tag              : Cardinal;         // コンテナ側のコーデックタグ
    extradata              : PByte;            // デコーダ初期化用の追加データ
    extradata_size         : Integer;          // 追加データのバイト数
    coded_side_data        : Pointer;          // FFmpeg側のサイドデータ
    nb_coded_side_data     : Integer;          // サイドデータ数
    format                 : Integer;          // ピクセル形式またはサンプル形式
    bit_rate               : Int64;            // ビットレート
    bits_per_coded_sample  : Integer;          // 符号化サンプルあたりビット数
    bits_per_raw_sample    : Integer;          // 生サンプルあたりビット数
    profile                : Integer;          // コーデックプロファイル
    level                  : Integer;          // コーデックレベル
    width                  : Integer;          // 映像幅
    height                 : Integer;          // 映像高さ
    sample_aspect_ratio    : TAVRational;      // サンプルアスペクト比
    framerate              : TAVRational;      // ストリーム側のフレームレート
    field_order            : Integer;          // フィールド順
    color_range            : Integer;          // 色範囲
    color_primaries        : Integer;          // 色域
    color_trc              : Integer;          // 伝達特性
    color_space            : Integer;          // 色空間
    chroma_location        : Integer;          // クロマ位置
    video_delay            : Integer;          // 映像デコード遅延
    ch_layout              : TAVChannelLayout; // 音声チャンネルレイアウト
    sample_rate            : Integer;          // 音声サンプルレート
    block_align            : Integer;          // 音声ブロック境界
    frame_size             : Integer;          // 音声フレームサイズ
    initial_padding        : Integer;          // 先頭パディング
    trailing_padding       : Integer;          // 末尾パディング
    seek_preroll           : Integer;          // シーク後に必要なプリロール
  end;

  PAVStream = ^TAVStream;
  PPAVStream = ^PAVStream;
  // FFmpegの入力ストリーム情報。
  TAVStream = record
    av_class            : Pointer;                    // FFmpeg内部クラス情報
    index               : Integer;                    // ストリーム番号
    id                  : Integer;                    // コンテナ内のストリームID
    codecpar            : PAVCodecParameters;         // コーデック情報
    priv_data           : Pointer;                    // FFmpeg内部用データ
    time_base           : TAVRational;                // PTS/DTSの時間単位
    start_time          : Int64;                      // 開始時刻
    duration            : Int64;                      // ストリーム長
    nb_frames           : Int64;                      // フレーム数
    disposition         : Integer;                    // ストリーム属性
    discard             : Integer;                    // 破棄設定
    sample_aspect_ratio : TAVRational;                // サンプルアスペクト比
    metadata            : Pointer;                    // メタデータ
    avg_frame_rate      : TAVRational;                // 平均フレームレート
    attached_pic        : array[0..103] of Byte;      // 添付画像情報の予約領域
    event_flags         : Integer;                    // FFmpegイベントフラグ
    r_frame_rate        : TAVRational;                // 推定フレームレート
    pts_wrap_bits       : Integer;                    // PTS折り返しビット数
  end;

  PAVFormatContext = ^TAVFormatContext;
  PPAVFormatContext = ^PAVFormatContext;
  // FFmpegの入力フォーマットコンテキスト。
  TAVFormatContext = record
    av_class         : Pointer;     // FFmpeg内部クラス情報
    iformat          : Pointer;     // 入力フォーマット
    oformat          : Pointer;     // 出力フォーマット
    priv_data        : Pointer;     // FFmpeg内部用データ
    pb               : Pointer;     // I/Oコンテキスト
    ctx_flags        : Integer;     // コンテキストフラグ
    nb_streams       : Cardinal;    // ストリーム数
    streams          : PPAVStream;  // ストリーム配列
    nb_stream_groups : Cardinal;    // ストリームグループ数
    stream_groups    : Pointer;     // ストリームグループ配列
    nb_chapters      : Cardinal;    // チャプター数
    chapters         : Pointer;     // チャプター配列
    url              : PAnsiChar;   // 入力URL
    start_time       : Int64;       // 入力全体の開始時刻
    duration         : Int64;       // 入力全体の長さ
  end;

  PAVCodec = Pointer;
  PAVCodecContext = Pointer;
  PPAVCodecContext = ^PAVCodecContext;
  PSwsContext = Pointer;
  PSwrContext = Pointer;
  PPSwrContext = ^PSwrContext;

  PAVPacket = ^TAVPacket;
  PPAVPacket = ^PAVPacket;
  // FFmpegから読み込む圧縮済みパケット。
  TAVPacket = record
    buf             : Pointer;     // FFmpeg内部バッファ参照
    pts             : Int64;       // 表示時刻
    dts             : Int64;       // デコード時刻
    data            : PByte;       // パケットデータ
    size            : Integer;     // パケットデータのバイト数
    stream_index    : Integer;     // 所属ストリーム番号
    flags           : Integer;     // パケットフラグ
    side_data       : Pointer;     // サイドデータ
    side_data_elems : Integer;     // サイドデータ数
    duration        : Int64;       // パケットの長さ
    pos             : Int64;       // 入力内の位置
    opaque          : Pointer;     // FFmpeg内部用ポインタ
    opaque_ref      : Pointer;     // FFmpeg内部用参照
    time_base       : TAVRational; // パケット時刻の時間単位
  end;

  PAVFrame = ^TAVFrame;
  PPAVFrame = ^PAVFrame;
  // FFmpegがデコードした映像/音声フレーム。
  TAVFrame = record
    data                : array[0..7] of PByte;   // フレームデータのプレーンポインタ
    linesize            : array[0..7] of Integer; // 各プレーンの1行バイト数
    extended_data       : Pointer;                // 音声などで使う拡張プレーン
    width               : Integer;                // 映像幅
    height              : Integer;                // 映像高さ
    nb_samples          : Integer;                // 音声サンプル数
    format              : Integer;                // ピクセル形式またはサンプル形式
    pict_type           : Integer;                // 映像フレーム種別
    sample_aspect_ratio : TAVRational;            // サンプルアスペクト比
    pts                 : Int64;                  // フレームの表示時刻
  end;

  Tavformat_open_input           = function(ps: PPAVFormatContext; url: PAnsiChar;
    fmt: Pointer; options: Pointer): Integer; cdecl;
  Tavformat_find_stream_info     = function(ic: PAVFormatContext;
    options: Pointer): Integer; cdecl;
  Tavformat_close_input          = procedure(ps: PPAVFormatContext); cdecl;
  Tavformat_network_init         = function: Integer; cdecl;
  Tav_find_best_stream           = function(ic: PAVFormatContext; media_type: Integer;
    wanted_stream_nb: Integer; related_stream: Integer; decoder_ret: Pointer;
    flags: Integer): Integer; cdecl;
  Tav_read_frame                 = function(s: PAVFormatContext;
    pkt: PAVPacket): Integer; cdecl;
  Tav_seek_frame                 = function(s: PAVFormatContext; stream_index: Integer;
    timestamp: Int64; flags: Integer): Integer; cdecl;
  Tavformat_alloc_output_context2 = function(ctx: PPAVFormatContext;
    oformat: Pointer; format_name, filename: PAnsiChar): Integer; cdecl;
  Tavformat_new_stream           = function(ctx: PAVFormatContext;
    codec: PAVCodec): PAVStream; cdecl;
  Tavformat_write_header         = function(ctx: PAVFormatContext;
    options: Pointer): Integer; cdecl;
  Tav_interleaved_write_frame    = function(ctx: PAVFormatContext;
    pkt: PAVPacket): Integer; cdecl;
  Tav_write_trailer              = function(ctx: PAVFormatContext): Integer; cdecl;
  Tavformat_free_context         = procedure(ctx: PAVFormatContext); cdecl;
  Tavio_open                     = function(s: PPointer; url: PAnsiChar;
    flags: Integer): Integer; cdecl;
  Tavio_closep                   = function(s: PPointer): Integer; cdecl;

  Tavcodec_find_decoder          = function(id: Integer): PAVCodec; cdecl;
  Tavcodec_find_encoder_by_name  = function(name: PAnsiChar): PAVCodec; cdecl;
  Tavcodec_alloc_context3        = function(codec: PAVCodec): PAVCodecContext; cdecl;
  Tavcodec_parameters_to_context = function(codecContext: PAVCodecContext;
    codecpar: PAVCodecParameters): Integer; cdecl;
  Tavcodec_parameters_from_context = function(codecpar: PAVCodecParameters;
    codecContext: PAVCodecContext): Integer; cdecl;
  Tavcodec_open2                 = function(codecContext: PAVCodecContext;
    codec: PAVCodec; options: Pointer): Integer; cdecl;
  Tavcodec_free_context          = procedure(codecContext: PPAVCodecContext); cdecl;
  Tavcodec_send_packet           = function(codecContext: PAVCodecContext;
    packet: PAVPacket): Integer; cdecl;
  Tavcodec_receive_frame         = function(codecContext: PAVCodecContext;
    frame: PAVFrame): Integer; cdecl;
  Tavcodec_send_frame            = function(codecContext: PAVCodecContext;
    frame: PAVFrame): Integer; cdecl;
  Tavcodec_receive_packet        = function(codecContext: PAVCodecContext;
    packet: PAVPacket): Integer; cdecl;
  Tavcodec_flush_buffers         = procedure(codecContext: PAVCodecContext); cdecl;
  Tav_packet_alloc               = function: PAVPacket; cdecl;
  Tav_packet_free                = procedure(packet: PPAVPacket); cdecl;
  Tav_packet_unref               = procedure(packet: PAVPacket); cdecl;
  Tav_packet_rescale_ts          = procedure(packet: PAVPacket;
    tb_src, tb_dst: TAVRational); cdecl;

  Tav_frame_alloc                = function: PAVFrame; cdecl;
  Tav_frame_free                 = procedure(frame: PPAVFrame); cdecl;
  Tav_frame_get_buffer           = function(frame: PAVFrame;
    align: Integer): Integer; cdecl;
  Tav_frame_make_writable        = function(frame: PAVFrame): Integer; cdecl;
  Tav_strerror                   = function(errnum: Integer; errbuf: PAnsiChar;
    errbuf_size: NativeUInt): Integer; cdecl;
  Tav_get_sample_fmt_name        = function(sample_fmt: Integer): PAnsiChar; cdecl;
  Tav_get_pix_fmt                = function(name: PAnsiChar): Integer; cdecl;
  Tav_opt_set                    = function(obj: Pointer; name, val: PAnsiChar;
    search_flags: Integer): Integer; cdecl;

  Tsws_getContext                = function(srcW, srcH, srcFormat, dstW, dstH, dstFormat,
    flags: Integer; srcFilter, dstFilter, param: Pointer): PSwsContext; cdecl;
  Tsws_scale                     = function(context: PSwsContext; srcSlice, srcStride: Pointer;
    srcSliceY, srcSliceH: Integer; dst, dstStride: Pointer): Integer; cdecl;
  Tsws_freeContext               = procedure(context: PSwsContext); cdecl;

  Tav_channel_layout_default     = procedure(ch_layout: PAVChannelLayout;
    nb_channels: Integer); cdecl;
  Tav_channel_layout_copy        = function(dst: PAVChannelLayout;
    const src: PAVChannelLayout): Integer; cdecl;
  Tav_channel_layout_uninit      = procedure(ch_layout: PAVChannelLayout); cdecl;

  Tswr_alloc_set_opts2           = function(ps: PPSwrContext;
    const out_ch_layout: PAVChannelLayout; out_sample_fmt: Integer;
    out_sample_rate: Integer; const in_ch_layout: PAVChannelLayout;
    in_sample_fmt: Integer; in_sample_rate: Integer; log_offset: Integer;
    log_ctx: Pointer): Integer; cdecl;
  Tswr_init                      = function(s: PSwrContext): Integer; cdecl;
  Tswr_convert                   = function(s: PSwrContext; out_arg: Pointer;
    out_count: Integer; in_arg: Pointer; in_count: Integer): Integer; cdecl;
  Tswr_free                      = procedure(s: PPSwrContext); cdecl;

const
  AVMEDIA_TYPE_VIDEO          = 0;                    // FFmpegの映像stream種別
  AVMEDIA_TYPE_AUDIO          = 1;                    // FFmpegの音声stream種別
  AV_TIME_BASE                = 1000000;              // FFmpeg共通時間軸の1秒あたりtick数
  AVSEEK_FLAG_BACKWARD        = 1;                    // 指定位置以前のkeyframeへseekするflag
  AV_PIX_FMT_YUYV422          = 1;                    // YUY2/YUYV422のpixel format値
  AV_PIX_FMT_BGR24            = 3;                    // BGR24のpixel format値
  AV_PIX_FMT_YUV420P          = 0;                    // yuv420pのpixel format値
  AV_PIX_FMT_BGRA             = 28;                   // BGRAのpixel format値
  SWS_BILINEAR                = 2;                    // sws_scaleのbilinear変換flag
  AVIO_FLAG_WRITE             = 2;                    // avio_openで出力書き込みを指定するflag
  AV_CODEC_FLAG_GLOBAL_HEADER = 1 shl 22;             // codec headerをstream extradataへ出すflag
  AVERROR_EOF                 = -541478725;           // FFmpegのEOFエラー値
  AVERROR_EAGAIN              = -11;                  // FFmpegの再試行要求エラー値
  AV_NOPTS_VALUE              = -9223372036854775808; // PTS未設定を表すFFmpeg値
  AV_SAMPLE_FMT_S16           = 1;                    // signed 16bit PCMのsample format値
  AUDIO_OUTPUT_SAMPLE_RATE    = 48000;                // 既定の音声出力sample rate
  AUDIO_OUTPUT_CHANNELS       = 2;                    // 既定の音声出力channel数

type
  // FFmpeg DLLのロード状態と関数ポインタを保持するクラス。
  TFFmpegApi = class
  public
    class var FLoaded                         : Boolean;                       // FFmpeg DLLロード済みフラグ
    class var FAvUtil                         : HMODULE;                       // avutil DLLハンドル
    class var FAvCodec                        : HMODULE;                       // avcodec DLLハンドル
    class var FAvFormat                       : HMODULE;                       // avformat DLLハンドル
    class var FSwResample                     : HMODULE;                       // swresample DLLハンドル
    class var FSwScale                        : HMODULE;                       // swscale DLLハンドル
    class var avformat_open_input             : Tavformat_open_input;          // 入力ファイルを開く関数
    class var avformat_find_stream_info       : Tavformat_find_stream_info;    // ストリーム情報を読む関数
    class var avformat_close_input            : Tavformat_close_input;         // 入力コンテキストを閉じる関数
    class var avformat_network_init           : Tavformat_network_init;        // FFmpegネットワーク機能初期化関数
    class var av_find_best_stream             : Tav_find_best_stream;          // 最適な映像ストリームを探す関数
    class var av_read_frame                   : Tav_read_frame;                // 次のパケットを読む関数
    class var av_seek_frame                   : Tav_seek_frame;                // 指定位置へシークする関数
    class var avcodec_find_decoder            : Tavcodec_find_decoder;         // コーデックIDからデコーダを探す関数
    class var avcodec_alloc_context3          : Tavcodec_alloc_context3;       // デコードコンテキストを確保する関数
    class var avcodec_parameters_to_context   : Tavcodec_parameters_to_context; // ストリーム情報をデコードコンテキストへコピーする関数
    class var avcodec_open2                   : Tavcodec_open2;                // デコーダを開く関数
    class var avcodec_free_context            : Tavcodec_free_context;         // デコードコンテキストを解放する関数
    class var avcodec_send_packet             : Tavcodec_send_packet;          // パケットをデコーダへ渡す関数
    class var avcodec_receive_frame           : Tavcodec_receive_frame;        // デコード済みフレームを受け取る関数
    class var avcodec_flush_buffers           : Tavcodec_flush_buffers;        // シーク後にデコーダ内部バッファを捨てる関数
    class var av_packet_alloc                 : Tav_packet_alloc;              // AVPacketを確保する関数
    class var av_packet_free                  : Tav_packet_free;               // AVPacketを解放する関数
    class var av_packet_unref                 : Tav_packet_unref;              // AVPacketの参照を解放する関数
    class var av_frame_alloc                  : Tav_frame_alloc;               // AVFrameを確保する関数
    class var av_frame_free                   : Tav_frame_free;                // AVFrameを解放する関数
    class var av_strerror                     : Tav_strerror;                  // FFmpegエラーコードを文字列化する関数
    class var av_get_sample_fmt_name          : Tav_get_sample_fmt_name;       // サンプル形式名を取得する関数
    class var av_get_pix_fmt                  : Tav_get_pix_fmt;               // pixel format名から番号を取得する関数
    class var av_channel_layout_default       : Tav_channel_layout_default;    // 標準チャンネルレイアウトを作る関数
    class var av_channel_layout_copy          : Tav_channel_layout_copy;       // チャンネルレイアウトをコピーする関数
    class var av_channel_layout_uninit        : Tav_channel_layout_uninit;     // チャンネルレイアウトを解放する関数
    class var sws_getContext                  : Tsws_getContext;               // 色変換コンテキストを作る関数
    class var sws_scale                       : Tsws_scale;                    // フレームをBGRへ変換する関数
    class var sws_freeContext                 : Tsws_freeContext;              // 色変換コンテキストを解放する関数
    class var swr_alloc_set_opts2             : Tswr_alloc_set_opts2;          // 音声変換コンテキストを作る関数
    class var swr_init                        : Tswr_init;                     // 音声変換コンテキストを初期化する関数
    class var swr_convert                     : Tswr_convert;                  // 音声フレームをPCMへ変換する関数
    class var swr_free                        : Tswr_free;                     // 音声変換コンテキストを解放する関数
    // この入力プラグインが置かれているフォルダを取得する。
    class function ModuleDirectory: string; static;
    // 指定DLLを実行ファイルフォルダからロードする。
    class function LoadDll(const DllPath, DllName: string): HMODULE; static;
    // DLLから指定関数を取得する。
    class function LoadProc(Module: HMODULE; const ProcName: PAnsiChar): Pointer; static;
    // 必要なFFmpeg DLLと関数ポインタを初期化する。
    class procedure EnsureLoaded; static;
    // FFmpegエラーコードを表示用文字列に変換する。
    class function ErrorText(Code: Integer): string; static;
  end;
// FFmpegの分数値を実数に変換する。
function RationalToDouble(const Value: TAVRational): Double;
// FFmpegの分数値を文字列に変換する。
function RationalToText(const Value: TAVRational): string;
// フォーマットコンテキストから指定ストリームを取り出す。
function StreamAt(FormatContext: PAVFormatContext; StreamIndex: Integer): PAVStream;
// ミリ秒位置をストリーム時間軸のPTSへ変換する。
function StreamTimestampFromMs(Stream: PAVStream; PositionMs: Integer): Int64;
// ストリーム時間軸のPTSをミリ秒位置へ変換する。
function StreamTimestampToMs(Stream: PAVStream; Timestamp: Int64): Integer;
// FFmpegのサンプル形式番号を表示用文字列に変換する。
function SampleFormatName(SampleFormat: Integer): string;
implementation

// この入力プラグインが置かれているフォルダを取得する。
class function TFFmpegApi.ModuleDirectory: string;
var
  ModuleFileName: array[0..MAX_PATH - 1] of Char; // プラグインDLLのフルパス取得先
  Len: DWORD; // GetModuleFileNameが返した文字数
begin
  Len := GetModuleFileName(HInstance, ModuleFileName, Length(ModuleFileName));
  if Len > 0 then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(string(ModuleFileName)))
  else
    Result := ExtractFilePath(ParamStr(0));
end;

// 指定DLLを実行ファイルフォルダからロードする。
class function TFFmpegApi.LoadDll(const DllPath, DllName: string): HMODULE;
var
  FullName: string; // ロード対象DLLのフルパス
  ErrorCode: Cardinal; // LoadLibrary失敗時のWindowsエラーコード
begin
  FullName := DllPath + DllName;
  Result := LoadLibrary(PChar(FullName));
  if Result = 0 then
  begin
    ErrorCode := GetLastError;
    raise Exception.CreateFmt('Failed to load %s. Path=%s WindowsError=%d %s',
      [DllName, FullName, ErrorCode, SysErrorMessage(ErrorCode)]);
  end;
end;

// DLLから指定関数を取得する。
class function TFFmpegApi.LoadProc(Module: HMODULE; const ProcName: PAnsiChar): Pointer;
begin
  Result := GetProcAddress(Module, ProcName);
  if Result = nil then
    raise Exception.CreateFmt('FFmpeg function not found: %s', [string(ProcName)]);
end;

// 必要なFFmpeg DLLと関数ポインタを初期化する。
class procedure TFFmpegApi.EnsureLoaded;
var
  DllPath: string; // FFmpeg DLLを探すプラグインフォルダ
begin
  if FLoaded then
    Exit;

  DllPath := ModuleDirectory;
  SetDllDirectory(PChar(DllPath));

  FAvUtil := LoadDll(DllPath, 'avutil-60.dll');
  FSwResample := LoadDll(DllPath, 'swresample-6.dll');
  FSwScale := LoadDll(DllPath, 'swscale-9.dll');
  FAvCodec := LoadDll(DllPath, 'avcodec-62.dll');
  FAvFormat := LoadDll(DllPath, 'avformat-62.dll');

  av_strerror := Tav_strerror(LoadProc(FAvUtil, 'av_strerror'));
  av_get_sample_fmt_name := Tav_get_sample_fmt_name(LoadProc(FAvUtil, 'av_get_sample_fmt_name'));
  av_get_pix_fmt := Tav_get_pix_fmt(LoadProc(FAvUtil, 'av_get_pix_fmt'));
  av_frame_alloc := Tav_frame_alloc(LoadProc(FAvUtil, 'av_frame_alloc'));
  av_frame_free := Tav_frame_free(LoadProc(FAvUtil, 'av_frame_free'));
  av_channel_layout_default := Tav_channel_layout_default(LoadProc(FAvUtil, 'av_channel_layout_default'));
  av_channel_layout_copy := Tav_channel_layout_copy(LoadProc(FAvUtil, 'av_channel_layout_copy'));
  av_channel_layout_uninit := Tav_channel_layout_uninit(LoadProc(FAvUtil, 'av_channel_layout_uninit'));

  avformat_open_input := Tavformat_open_input(LoadProc(FAvFormat, 'avformat_open_input'));
  avformat_find_stream_info := Tavformat_find_stream_info(LoadProc(FAvFormat, 'avformat_find_stream_info'));
  avformat_close_input := Tavformat_close_input(LoadProc(FAvFormat, 'avformat_close_input'));
  avformat_network_init := Tavformat_network_init(LoadProc(FAvFormat, 'avformat_network_init'));
  av_find_best_stream := Tav_find_best_stream(LoadProc(FAvFormat, 'av_find_best_stream'));
  av_read_frame := Tav_read_frame(LoadProc(FAvFormat, 'av_read_frame'));
  av_seek_frame := Tav_seek_frame(LoadProc(FAvFormat, 'av_seek_frame'));

  avcodec_find_decoder := Tavcodec_find_decoder(LoadProc(FAvCodec, 'avcodec_find_decoder'));
  avcodec_alloc_context3 := Tavcodec_alloc_context3(LoadProc(FAvCodec, 'avcodec_alloc_context3'));
  avcodec_parameters_to_context := Tavcodec_parameters_to_context(
    LoadProc(FAvCodec, 'avcodec_parameters_to_context'));
  avcodec_open2 := Tavcodec_open2(LoadProc(FAvCodec, 'avcodec_open2'));
  avcodec_free_context := Tavcodec_free_context(LoadProc(FAvCodec, 'avcodec_free_context'));
  avcodec_send_packet := Tavcodec_send_packet(LoadProc(FAvCodec, 'avcodec_send_packet'));
  avcodec_receive_frame := Tavcodec_receive_frame(LoadProc(FAvCodec, 'avcodec_receive_frame'));
  avcodec_flush_buffers := Tavcodec_flush_buffers(LoadProc(FAvCodec, 'avcodec_flush_buffers'));
  av_packet_alloc := Tav_packet_alloc(LoadProc(FAvCodec, 'av_packet_alloc'));
  av_packet_free := Tav_packet_free(LoadProc(FAvCodec, 'av_packet_free'));
  av_packet_unref := Tav_packet_unref(LoadProc(FAvCodec, 'av_packet_unref'));

  sws_getContext := Tsws_getContext(LoadProc(FSwScale, 'sws_getContext'));
  sws_scale := Tsws_scale(LoadProc(FSwScale, 'sws_scale'));
  sws_freeContext := Tsws_freeContext(LoadProc(FSwScale, 'sws_freeContext'));

  swr_alloc_set_opts2 := Tswr_alloc_set_opts2(LoadProc(FSwResample, 'swr_alloc_set_opts2'));
  swr_init := Tswr_init(LoadProc(FSwResample, 'swr_init'));
  swr_convert := Tswr_convert(LoadProc(FSwResample, 'swr_convert'));
  swr_free := Tswr_free(LoadProc(FSwResample, 'swr_free'));

  avformat_network_init;
  FLoaded := True;
end;

// FFmpegエラーコードを表示用文字列に変換する。
class function TFFmpegApi.ErrorText(Code: Integer): string;
var
  Buffer: array[0..255] of AnsiChar; // av_strerrorの出力先
begin
  FillChar(Buffer, SizeOf(Buffer), 0);
  if Assigned(av_strerror) and (av_strerror(Code, Buffer, SizeOf(Buffer)) = 0) then
    Result := string(AnsiString(Buffer))
  else
    Result := Format('FFmpeg error %d', [Code]);
end;

// FFmpegの分数値を実数に変換する。
function RationalToDouble(const Value: TAVRational): Double;
begin
  if Value.den = 0 then
    Result := 0
  else
    Result := Value.num / Value.den;
end;

// FFmpegの分数値を文字列に変換する。
function RationalToText(const Value: TAVRational): string;
begin
  if Value.den = 0 then
    Result := ''
  else
    Result := Format('%d/%d', [Value.num, Value.den]);
end;

// フォーマットコンテキストから指定ストリームを取り出す。
function StreamAt(FormatContext: PAVFormatContext; StreamIndex: Integer): PAVStream;
begin
  Result := PAVStream(PPointer(NativeUInt(FormatContext.streams) + NativeUInt(StreamIndex) * SizeOf(Pointer))^);
end;

// ミリ秒位置をストリーム時間軸のPTSへ変換する。
function StreamTimestampFromMs(Stream: PAVStream; PositionMs: Integer): Int64;
begin
  if (Stream.time_base.num <= 0) or (Stream.time_base.den <= 0) then
    Result := 0
  else
    Result := Round((PositionMs / 1000.0) * Stream.time_base.den / Stream.time_base.num);
end;

// ストリーム時間軸のPTSをミリ秒位置へ変換する。
function StreamTimestampToMs(Stream: PAVStream; Timestamp: Int64): Integer;
begin
  if (Timestamp = AV_NOPTS_VALUE) or (Stream.time_base.num <= 0) or (Stream.time_base.den <= 0) then
    Result := -1
  else
    Result := Round(Timestamp * 1000.0 * Stream.time_base.num / Stream.time_base.den);
end;

// FFmpegのサンプル形式番号を表示用文字列に変換する。
function SampleFormatName(SampleFormat: Integer): string;
var
  Name: PAnsiChar; // FFmpegから返るサンプル形式名
begin
  Result := Format('fmt %d', [SampleFormat]);
  if Assigned(TFFmpegApi.av_get_sample_fmt_name) then
  begin
    Name := TFFmpegApi.av_get_sample_fmt_name(SampleFormat);
    if Name <> nil then
      Result := string(AnsiString(Name));
  end;
end;

end.
