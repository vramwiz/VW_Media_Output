unit FFmpegOutputSettingsStorage;

interface

uses
  FFmpegOutputConfig;

procedure LoadOutputSettingsFromIni(var Settings: TOutputTestSettings);
procedure SaveOutputSettingsToIni(const Settings: TOutputTestSettings);
function OutputSettingsIniPath: string;

implementation

uses
  Winapi.Windows, System.IniFiles, System.SysUtils;

const
  SETTINGS_SECTION = 'Settings';
  SETTINGS_VERSION = 1;

function OutputSettingsIniPath: string;
var
  ModulePath: array[0..MAX_PATH - 1] of Char;
  Length: DWORD;
begin
  Length := GetModuleFileName(HInstance, ModulePath, MAX_PATH);
  if Length > 0 then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(string(ModulePath))) +
      'VW_Media_Output.ini'
  else
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'VW_Media_Output.ini';
end;

function EncoderKindToName(Kind: TOutputEncoderKind): string;
begin
  case Kind of
    oekCpuX264:
      Result := 'CpuX264';
    oekIntelQsv:
      Result := 'IntelQsv';
  else
    Result := 'IntelQsv';
  end;
end;

function EncoderKindFromName(const Name: string; Default: TOutputEncoderKind): TOutputEncoderKind;
begin
  if SameText(Name, 'CpuX264') or SameText(Name, 'libx264') then
    Result := oekCpuX264
  else if SameText(Name, 'IntelQsv') or SameText(Name, 'h264_qsv') then
    Result := oekIntelQsv
  else
    Result := Default;
end;

function VideoQualityToName(Quality: TOutputVideoQualityKind): string;
begin
  case Quality of
    ovqHigh:
      Result := 'High';
    ovqStandard:
      Result := 'Standard';
    ovqFast:
      Result := 'Fast';
  else
    Result := 'Standard';
  end;
end;

function VideoQualityFromName(const Name: string; Default: TOutputVideoQualityKind): TOutputVideoQualityKind;
begin
  if SameText(Name, 'High') or SameText(Name, 'HighQuality') then
    Result := ovqHigh
  else if SameText(Name, 'Fast') then
    Result := ovqFast
  else if SameText(Name, 'Standard') then
    Result := ovqStandard
  else
    Result := Default;
end;

function AudioModeToName(Mode: TOutputAudioModeKind): string;
begin
  case Mode of
    oamAac576:
      Result := 'Aac576';
    oamAac384:
      Result := 'Aac384';
    oamAac256:
      Result := 'Aac256';
    oamAac192:
      Result := 'Aac192';
    oamAac128:
      Result := 'Aac128';
    oamNone:
      Result := 'None';
  else
    Result := 'Aac192';
  end;
end;

function AudioModeFromName(const Name: string; Default: TOutputAudioModeKind): TOutputAudioModeKind;
begin
  if SameText(Name, 'Aac576') or SameText(Name, '576') then
    Result := oamAac576
  else if SameText(Name, 'Aac384') or SameText(Name, '384') then
    Result := oamAac384
  else if SameText(Name, 'Aac256') or SameText(Name, '256') then
    Result := oamAac256
  else if SameText(Name, 'Aac192') or SameText(Name, '192') then
    Result := oamAac192
  else if SameText(Name, 'Aac128') or SameText(Name, '128') then
    Result := oamAac128
  else if SameText(Name, 'None') or SameText(Name, 'Disabled') then
    Result := oamNone
  else
    Result := Default;
end;

function VideoQualityFromSettings(const Settings: TOutputTestSettings): TOutputVideoQualityKind;
begin
  if Settings.Video.BitRate >= 8000000 then
    Result := ovqHigh
  else if Settings.Video.BitRate <= 2500000 then
    Result := ovqFast
  else
    Result := ovqStandard;
end;

function AudioModeFromSettings(const Settings: TOutputTestSettings): TOutputAudioModeKind;
begin
  if not Settings.Audio.Enabled then
    Result := oamNone
  else if Settings.Audio.BitRate >= 576000 then
    Result := oamAac576
  else if Settings.Audio.BitRate >= 384000 then
    Result := oamAac384
  else if Settings.Audio.BitRate >= 256000 then
    Result := oamAac256
  else if Settings.Audio.BitRate >= 192000 then
    Result := oamAac192
  else if Settings.Audio.BitRate <= 128000 then
    Result := oamAac128
  else
    Result := oamAac192;
end;

procedure LoadOutputSettingsFromIni(var Settings: TOutputTestSettings);
var
  Ini: TIniFile;
  EncoderKind: TOutputEncoderKind;
  VideoQuality: TOutputVideoQualityKind;
  AudioMode: TOutputAudioModeKind;
begin
  InitDefaultOutputSettings(Settings);
  if not FileExists(OutputSettingsIniPath) then
    Exit;

  try
    Ini := TIniFile.Create(OutputSettingsIniPath);
    try
      EncoderKind := EncoderKindFromName(
        Ini.ReadString(SETTINGS_SECTION, 'Encoder', EncoderKindToName(Settings.Video.EncoderKind)),
        Settings.Video.EncoderKind);
      VideoQuality := VideoQualityFromName(
        Ini.ReadString(SETTINGS_SECTION, 'VideoQuality', VideoQualityToName(VideoQualityFromSettings(Settings))),
        VideoQualityFromSettings(Settings));
      AudioMode := AudioModeFromName(
        Ini.ReadString(SETTINGS_SECTION, 'AudioMode', AudioModeToName(AudioModeFromSettings(Settings))),
        AudioModeFromSettings(Settings));

      ApplyEncoderDefaults(Settings, EncoderKind);
      ApplyVideoQuality(Settings, VideoQuality);
      ApplyAudioMode(Settings, AudioMode);
    finally
      Ini.Free;
    end;
  except
    InitDefaultOutputSettings(Settings);
  end;
end;

procedure SaveOutputSettingsToIni(const Settings: TOutputTestSettings);
var
  Ini: TIniFile;
begin
  try
    ForceDirectories(ExtractFilePath(OutputSettingsIniPath));
    Ini := TIniFile.Create(OutputSettingsIniPath);
    try
      Ini.WriteInteger(SETTINGS_SECTION, 'Version', SETTINGS_VERSION);
      Ini.WriteString(SETTINGS_SECTION, 'Encoder',
        EncoderKindToName(Settings.Video.EncoderKind));
      Ini.WriteString(SETTINGS_SECTION, 'VideoQuality',
        VideoQualityToName(VideoQualityFromSettings(Settings)));
      Ini.WriteString(SETTINGS_SECTION, 'AudioMode',
        AudioModeToName(AudioModeFromSettings(Settings)));
    finally
      Ini.Free;
    end;
  except
    // Settings persistence must never prevent output.
  end;
end;

end.
