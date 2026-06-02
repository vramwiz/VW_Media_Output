unit AviUtl2InputTypes;

{
  AviUtl2 Input Plugin Type Definitions (SDK β18c 対応)
  ----------------------------------------------------
  このユニットは AviUtl2 β18c の入力プラグイン (.aui2) を
  Delphi で実装する際に使用する型定義をまとめたものです。

  対応バージョン : AviUtl2 β18c
  対応機能 :
    - 同時アクセス (FLAG_CONCURRENT)
    - マルチトラック (FLAG_MULTI_TRACK)
    - 時間→フレーム変換 (FLAG_TIME_TO_FRAME)
    - RGB24 / RGBA32 / PA64 / HF64 / YUY2 / YC48 形式
    - PCM16bit / PCM32bit(float)

  2025-11-07
  Based on AviUtl2 SDK β18c (By KENくん)
}

interface

uses
  Winapi.Windows, Winapi.MMSystem;

type
  LPCWSTR = PWideChar;
  INPUT_HANDLE = Pointer;
  PBITMAPINFOHEADER = ^BITMAPINFOHEADER;

  // Delphi環境によっては未定義の場合があるため明示的に定義
  PWAVEFORMATEX = ^WAVEFORMATEX;
  WAVEFORMATEX = packed record
    wFormatTag: Word;
    nChannels: Word;
    nSamplesPerSec: Cardinal;
    nAvgBytesPerSec: Cardinal;
    nBlockAlign: Word;
    wBitsPerSample: Word;
    cbSize: Word;
  end;

{-----------------------------------------------------------------------------
  入力ファイル情報構造体
 -----------------------------------------------------------------------------}
const
  INPUT_INFO_FLAG_VIDEO         = 1;   // 映像データあり
  INPUT_INFO_FLAG_AUDIO         = 2;   // 音声データあり
  INPUT_INFO_FLAG_TIME_TO_FRAME = 16;  // 時間→フレーム変換を使用 (func_time_to_frame 有効)

type
  PInputInfo = ^TInputInfo;
  TInputInfo = record
    flag: Integer;
    rate: Integer;             // フレームレート (分子)
    scale: Integer;            // フレームレート (分母)
    n: Integer;                // フレーム総数
    format: PBITMAPINFOHEADER; // 画像フォーマット情報 (保持期間: 次の呼び出しまで)
    format_size: Integer;      // 画像フォーマットサイズ
    audio_n: Integer;          // 音声サンプル数
    audio_format: PWAVEFORMATEX; // 音声フォーマット情報 (保持期間: 次の呼び出しまで)
    audio_format_size: Integer;  // 音声フォーマットサイズ
  end;

{-----------------------------------------------------------------------------
  入力プラグイン関数テーブル構造体
 -----------------------------------------------------------------------------}
const
  INPUT_PLUGIN_FLAG_VIDEO       = 1;   // 映像サポート
  INPUT_PLUGIN_FLAG_AUDIO       = 2;   // 音声サポート
  INPUT_PLUGIN_FLAG_CONCURRENT  = 16;  // 映像・音声の同時アクセス対応
  INPUT_PLUGIN_FLAG_MULTI_TRACK = 32;  // マルチトラック対応 (func_set_track 使用)
  INPUT_PLUGIN_TRACK_TYPE_VIDEO = 0;   // トラック種別: 映像
  INPUT_PLUGIN_TRACK_TYPE_AUDIO = 1;   // トラック種別: 音声

type
  PInputPluginTable = ^TInputPluginTable;
  TInputPluginTable = record
    flag: Integer;              // フラグ (上記定数を組み合わせ)
    name: LPCWSTR;              // プラグイン名
    filefilter: LPCWSTR;        // 入力ファイルフィルタ
    information: LPCWSTR;       // プラグイン情報

    // ファイルを開く
    func_open: function(fileName: LPCWSTR): INPUT_HANDLE; cdecl;

    // ファイルを閉じる
    func_close: function(ih: INPUT_HANDLE): BOOL; cdecl;

    // ファイル情報を取得
    func_info_get: function(ih: INPUT_HANDLE; info: PInputInfo): BOOL; cdecl;

    // 指定フレームの映像データを読み込み
    func_read_video: function(ih: INPUT_HANDLE; frame: Integer; buf: Pointer): Integer; cdecl;

    // 指定範囲の音声データを読み込み
    func_read_audio: function(ih: INPUT_HANDLE; start, length: Integer; buf: Pointer): Integer; cdecl;

    // 設定ダイアログを表示（不要なら nil）
    func_config: function(hwnd: HWND; hinst: HINST): BOOL; cdecl;

    // マルチトラック設定 (FLAG_MULTI_TRACK 時のみ)
    // 戻り値: 設定成功ならトラック番号、トラック数取得時は総数
    func_set_track: function(ih: INPUT_HANDLE; mediaType, index: Integer): Integer; cdecl;

    // 時間→フレーム変換 (FLAG_TIME_TO_FRAME 時のみ)
    func_time_to_frame: function(ih: INPUT_HANDLE; time: Double): Integer; cdecl;
  end;

{-----------------------------------------------------------------------------
  備考：
  - 入力プラグインでモジュール機能を追加する場合、
    GetInputPluginTable() に加えて GetScriptModuleTable() を同一DLLでエクスポート可能。
  - 本ユニットは INPUT_PLUGIN_TABLE の宣言のみを提供し、モジュール側とは分離管理する。
 -----------------------------------------------------------------------------}

implementation

end.

