unit AviUtl2OutputTypes;

{
  AviUtl2 Output Plugin Type Definitions
  --------------------------------------
  This unit contains the minimum OUTPUT_PLUGIN_TABLE definitions needed to
  build an AviUtl2 output plugin (.auo2) with Delphi.
}

interface

uses
  Winapi.Windows;

type
  // AviUtl2 SDK の LPCWSTR は Windows の UTF-16 文字列ポインタ。
  LPCWSTR = PWideChar;

  // PROJECT_FILE は plugin2.h 側の構造体。
  // このユニットでは中身を直接触らないので、不透明ポインタとして扱う。
  PProjectFile = Pointer;

const
  // TOutputInfo.flag に入る値。
  // 出力対象に映像/音声が含まれているかを AviUtl2 から通知される。
  OUTPUT_INFO_FLAG_VIDEO = 1;
  OUTPUT_INFO_FLAG_AUDIO = 2;

type
  POutputInfo = ^TOutputInfo;

  // 出力開始時に AviUtl2 から func_output へ渡される情報。
  // ここに含まれるコールバックから、フレーム画像や音声サンプルを取得して書き出す。
  TOutputInfo = record
    // OUTPUT_INFO_FLAG_* の組み合わせ。
    flag: Integer;

    // 映像サイズ。
    w: Integer;
    h: Integer;

    // フレームレートは rate / scale。
    // 例: 30000 / 1001 なら 29.97fps。
    rate: Integer;
    scale: Integer;

    // 総フレーム数。
    n: Integer;

    // 音声情報。
    // audio_n は総サンプル数で、チャンネル数ぶんの合計ではなく時間軸上のサンプル数。
    audio_rate: Integer;
    audio_ch: Integer;
    audio_n: Integer;

    // ユーザーが保存先として指定したファイル名。
    savefile: LPCWSTR;

    // 指定フレームの映像データを取得する。
    // format は SDK の指定値を渡す。0 は RGB24(BI_RGB)、YC48 なども指定可能。
    // 戻り値のポインタは、次に AviUtl2 の外部関数を呼ぶまで有効。
    func_get_video: function(frame: Integer; format: DWORD): Pointer; cdecl;

    // 指定範囲の音声データを取得する。
    // format は 1=PCM16bit、3=PCM float 32bit。
    // readed には実際に取得できたサンプル数が入る。
    func_get_audio: function(start, length: Integer; readed: PInteger; format: DWORD): Pointer; cdecl;

    // ユーザーが出力を中断したかを確認する。
    // 長いループでは定期的に呼ぶ。
    func_is_abort: function: Boolean; cdecl;

    // AviUtl2 側の残り時間表示を更新する。
    func_rest_time_disp: procedure(now, total: Integer); cdecl;

    // AviUtl2 側の先読みバッファ数を指定する。
    // 出力処理開始直後に必要なら設定する。
    func_set_buffer_size: procedure(video_size, audio_size: Integer); cdecl;
  end;

const
  // TOutputPluginTable.flag に入れる値。
  // このプラグインが対応する出力種別を AviUtl2 に知らせる。
  OUTPUT_PLUGIN_FLAG_VIDEO = 1;
  OUTPUT_PLUGIN_FLAG_AUDIO = 2;
  OUTPUT_PLUGIN_FLAG_IMAGE = 4;
  OUTPUT_PLUGIN_FLAG_PROJECT_CONFIG = 8;

type
  POutputPluginTable = ^TOutputPluginTable;

  // AviUtl2 に公開する出力プラグインテーブル。
  // .dpr 側でこの record を用意し、GetOutputPluginTable からポインタを返す。
  TOutputPluginTable = record
    // OUTPUT_PLUGIN_FLAG_* の組み合わせ。
    flag: Integer;

    // AviUtl2 の出力プラグイン一覧に表示される名前。
    name: LPCWSTR;

    // 保存ダイアログのフィルタ。
    // '説明'#0'*.ext'#0 のように null 区切りで指定する。
    filefilter: LPCWSTR;

    // プラグイン情報表示用の説明文。
    information: LPCWSTR;

    // 実際の出力処理。
    // 成功したら True、失敗または未実装なら False を返す。
    func_output: function(oip: POutputInfo): Boolean; cdecl;

    // 出力設定ダイアログ。
    // 不要なら .dpr 側のテーブルで nil を入れる。
    func_config: function(hwnd: HWND; hinst: HINST): Boolean; cdecl;

    // 現在の出力設定を短い文字列で返す。
    // AviUtl2 の設定確認表示などに使われる。
    func_get_config_text: function: LPCWSTR; cdecl;

    // プロジェクトファイルから出力設定を読み込む。
    // OUTPUT_PLUGIN_FLAG_PROJECT_CONFIG を使う場合だけ実装する。
    func_load_project_config: function(project: PProjectFile): Boolean; cdecl;

    // プロジェクトファイルへ出力設定を書き込む。
    // OUTPUT_PLUGIN_FLAG_PROJECT_CONFIG を使う場合だけ実装する。
    func_save_project_config: function(project: PProjectFile): Boolean; cdecl;
  end;

implementation

end.
