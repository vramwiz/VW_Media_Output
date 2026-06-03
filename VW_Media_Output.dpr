library VW_Media_Output;

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2OutputTypes in 'AviUtl\Output\AviUtl2OutputTypes.pas',
  FFmpegApi in 'Plugin_Input\FFmpegApi.pas',
  FFmpegOutputConfig in 'Plugin_Output\FFmpegOutputConfig.pas',
  FFmpegOutputEncoder in 'Plugin_Output\FFmpegOutputEncoder.pas';

var
  LastConfigText: string = 'MP4 / H.264 Intel QSV / AAC 192 kbps';

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

    InitDefaultOutputSettings(Settings);
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
  MessageBox(hwnd,
    'Current fixed settings:'#13#10 +
    'MP4 / H.264 Intel QSV / AAC 192 kbps',
    'VW_Media_Output', MB_OK or MB_ICONINFORMATION);
  Result := True;
end;

//------------------------------------------------------------------------------
// Configuration text placeholder
//------------------------------------------------------------------------------
function func_get_config_text: LPCWSTR; cdecl;
begin
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
    func_get_config_text: func_get_config_text
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
