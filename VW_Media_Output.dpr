library VW_Media_Output;

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2OutputTypes in 'AviUtl\Output\AviUtl2OutputTypes.pas',
  FFmpegApi in 'Plugin_Output\FFmpegApi.pas',
  FFmpegOutputConfig in 'Plugin_Output\FFmpegOutputConfig.pas',
  FFmpegOutputEncoder in 'Plugin_Output\FFmpegOutputEncoder.pas',
  FFmpegOutputApiTypes in 'Plugin_Output\FFmpegOutputApiTypes.pas',
  FFmpegOutputPerfLog in 'Plugin_Output\FFmpegOutputPerfLog.pas',
  FFmpegOutputPreview in 'Plugin_Output\FFmpegOutputPreview.pas',
  FFmpegOutputSettingsDialog in 'Plugin_Output\FFmpegOutputSettingsDialog.pas',
  FFmpegOutputSettingsStorage in 'Plugin_Output\FFmpegOutputSettingsStorage.pas',
  FFmpegOutputVideoInput in 'Plugin_Output\FFmpegOutputVideoInput.pas';

var
  CurrentSettings: TOutputTestSettings; // DLL内で保持する現在の出力設定
  CurrentSettingsInitialized: Boolean = False; // INI読み込み済みかどうか
  LastConfigText: string = ''; // AviUtl2の保存ダイアログ下部へ返す文字列

// 現在設定を初期化し、INIがあれば安全に反映する。
procedure EnsureCurrentSettings;
begin
  if CurrentSettingsInitialized then
    Exit;
  LoadOutputSettingsFromIni(CurrentSettings);
  CurrentSettingsInitialized := True;
end;

// 保存ダイアログ下部に出す短い設定概要を更新する。
procedure UpdateConfigText;
var
  AudioText: string;
begin
  EnsureCurrentSettings;
  if CurrentSettings.Audio.Enabled then
    AudioText := Format('AAC %d kbps', [CurrentSettings.Audio.BitRate div 1000])
  else
    AudioText := 'Audio none';
  LastConfigText := Format('%s / %s / %s / %s',
    [CurrentSettings.Container, CurrentSettings.Video.CodecName,
     CurrentSettings.Video.PixelFormatName, AudioText]);
end;

//------------------------------------------------------------------------------
// Output process
//------------------------------------------------------------------------------
// AviUtl2から渡された保存先を使い、現在設定で直接MP4を書き出す。
function func_output(oip: POutputInfo): Boolean; cdecl;
var
  Settings: TOutputTestSettings;
  ErrorMessage: string;
begin
  try
    if oip = nil then
    begin
      MessageBox(0, 'OutputInfo is nil.', 'VW_Media_Output', MB_OK or MB_ICONERROR);
      Exit(False);
    end;

    EnsureCurrentSettings;
    Settings := CurrentSettings;
    Settings.SaveFileName := string(oip^.savefile);

    Result := ExportOutputInfo(oip, Settings, ErrorMessage);
    if not Result and (ErrorMessage <> '') then
      MessageBox(0, PChar(ErrorMessage), 'VW_Media_Output', MB_OK or MB_ICONERROR);
  except
    on E: Exception do
    begin
      MessageBox(0, PChar(E.ClassName + ': ' + E.Message),
        'VW_Media_Output', MB_OK or MB_ICONERROR);
      Result := False;
    end;
  end;
end;

//------------------------------------------------------------------------------
// Configuration dialog placeholder
//------------------------------------------------------------------------------
// AviUtl2の「設定」ボタンから呼ばれ、OK時だけINIへ保存する。
function func_config(hwnd: HWND; hinst: HINST): Boolean; cdecl;
begin
  EnsureCurrentSettings;
  Result := ExecuteOutputSettingsDialog(hwnd, CurrentSettings);
  if Result then
  begin
    SaveOutputSettingsToIni(CurrentSettings);
    UpdateConfigText;
  end;
end;

//------------------------------------------------------------------------------
// Configuration text placeholder
//------------------------------------------------------------------------------
// AviUtl2の保存ダイアログに表示する現在設定の概要を返す。
function func_get_config_text: LPCWSTR; cdecl;
begin
  UpdateConfigText;
  Result := PWideChar(LastConfigText);
end;

//------------------------------------------------------------------------------
// Plugin table
//------------------------------------------------------------------------------
const
  MEDIA_FILE_FILTER =
    'Media file (*.mp4;*.mov;*.mkv;*.avi)'#0 +
    '*.mp4;*.mov;*.mkv;*.avi'#0;

var
  // 保存ダイアログ本体はAviUtl2側が持つため、ここでは名前・拡張子・設定関数だけを渡す。
  Plugin: TOutputPluginTable = (
    flag: OUTPUT_PLUGIN_FLAG_VIDEO or OUTPUT_PLUGIN_FLAG_AUDIO;
    name: '動画OUT';
    filefilter: MEDIA_FILE_FILTER;
    information: '様々な動画/音声形式を書き出すための AviUtl2 出力プラグイン';
    func_output: func_output;
    func_config: func_config;
    func_get_config_text: func_get_config_text;
    func_load_project_config: nil;
    func_save_project_config: nil
  );

//------------------------------------------------------------------------------
// AviUtl2がこの関数を探して出力プラグインを登録する。
function GetOutputPluginTable: POutputPluginTable; cdecl;
begin
  Result := @Plugin;
end;

exports
  GetOutputPluginTable name 'GetOutputPluginTable';

begin
end.
