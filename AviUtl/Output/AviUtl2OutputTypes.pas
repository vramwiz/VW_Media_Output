unit AviUtl2OutputTypes;

interface

uses
  Winapi.Windows;

type
  LPCWSTR = PWideChar;

const
  OUTPUT_INFO_FLAG_VIDEO = 1;
  OUTPUT_INFO_FLAG_AUDIO = 2;

type
  POutputInfo = ^TOutputInfo;
  TOutputInfo = record
    flag: Integer;
    w: Integer;
    h: Integer;
    rate: Integer;
    scale: Integer;
    n: Integer;
    audio_rate: Integer;
    audio_ch: Integer;
    audio_n: Integer;
    savefile: LPCWSTR;
    func_get_video: function(frame: Integer; format: DWORD): Pointer; cdecl;
    func_get_audio: function(start, length: Integer; readed: PInteger; format: DWORD): Pointer; cdecl;
    func_is_abort: function: Boolean; cdecl;
    func_rest_time_disp: procedure(now, total: Integer); cdecl;
    func_set_buffer_size: procedure(video_size, audio_size: Integer); cdecl;
  end;

const
  OUTPUT_PLUGIN_FLAG_VIDEO = 1;
  OUTPUT_PLUGIN_FLAG_AUDIO = 2;

type
  POutputPluginTable = ^TOutputPluginTable;
  TOutputPluginTable = record
    flag: Integer;
    name: LPCWSTR;
    filefilter: LPCWSTR;
    information: LPCWSTR;
    func_output: function(oip: POutputInfo): Boolean; cdecl;
    func_config: function(hwnd: HWND; hinst: HINST): Boolean; cdecl;
    func_get_config_text: function: LPCWSTR; cdecl;
  end;

implementation

end.
