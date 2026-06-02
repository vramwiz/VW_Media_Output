library VW_Media_Output;

uses
  Winapi.Windows,
  System.SysUtils,
  AviUtl2OutputTypes in 'AviUtl\Output\AviUtl2OutputTypes.pas';

//------------------------------------------------------------------------------
// Output process placeholder
//------------------------------------------------------------------------------
function func_output(oip: POutputInfo): Boolean; cdecl;
begin
  // TODO: Implement media export using oip^.func_get_video / func_get_audio.
  Result := False;
end;

//------------------------------------------------------------------------------
// Configuration dialog placeholder
//------------------------------------------------------------------------------
function func_config(hwnd: HWND; hinst: HINST): Boolean; cdecl;
begin
  MessageBox(hwnd, 'VW_Media_Output output settings are not implemented yet.',
    'VW_Media_Output', MB_OK or MB_ICONINFORMATION);
  Result := True;
end;

//------------------------------------------------------------------------------
// Configuration text placeholder
//------------------------------------------------------------------------------
function func_get_config_text: LPCWSTR; cdecl;
begin
  Result := 'Default settings';
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
