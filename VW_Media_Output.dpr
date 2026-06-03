library VW_Media_Output;

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2OutputTypes in 'AviUtl\Output\AviUtl2OutputTypes.pas',
  FFmpegApi in 'Plugin_Output\FFmpegApi.pas',
  FFmpegOutputConfig in 'Plugin_Output\FFmpegOutputConfig.pas',
  FFmpegOutputEncoder in 'Plugin_Output\FFmpegOutputEncoder.pas',
  FFmpegOutputSettingsDialog in 'Plugin_Output\FFmpegOutputSettingsDialog.pas',
  FFmpegOutputSettingsStorage in 'Plugin_Output\FFmpegOutputSettingsStorage.pas';

var
  CurrentSettings: TOutputTestSettings;
  CurrentSettingsInitialized: Boolean = False;
  LastConfigText: string = '';

procedure EnsureCurrentSettings;
begin
  if CurrentSettingsInitialized then
    Exit;
  LoadOutputSettingsFromIni(CurrentSettings);
  CurrentSettingsInitialized := True;
end;

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
  Plugin: TOutputPluginTable = (
    flag: OUTPUT_PLUGIN_FLAG_VIDEO or OUTPUT_PLUGIN_FLAG_AUDIO;
    name: '動画/音声出力';
    filefilter: MEDIA_FILE_FILTER;
    information: '様々な動画/音声形式を書き出すための AviUtl2 出力プラグイン';
    func_output: func_output;
    func_config: func_config;
    func_get_config_text: func_get_config_text;
    func_load_project_config: nil;
    func_save_project_config: nil
  );

//------------------------------------------------------------------------------
function GetOutputPluginTable: POutputPluginTable; cdecl;
begin
  Result := @Plugin;
end;

exports
  GetOutputPluginTable name 'GetOutputPluginTable';

begin
end.
