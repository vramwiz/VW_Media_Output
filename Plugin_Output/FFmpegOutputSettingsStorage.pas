unit FFmpegOutputSettingsStorage;

// 出力設定をプラグイン横のINIへ保存/復元する。
// 破損値や旧形式の値は既定値へ丸め、設定読み込み失敗で出力処理を止めない。

interface

uses
  FFmpegOutputConfig;

// INIを読み、壊れた値や未知値は既定値へ丸めてSettingsへ展開する。
procedure LoadOutputSettingsFromIni(var Settings: TOutputTestSettings);
// 本質的な選択値だけをINIへ保存し、派生値の不整合を避ける。
procedure SaveOutputSettingsToIni(const Settings: TOutputTestSettings);
// プレビュー画面から切り替えたcheck log表示設定だけをINIへ反映する。
procedure SaveOutputCheckLogDisplayToIni(ShowCheckLogAfterEncode: Boolean);
// プラグインDLLと同じフォルダに置くINIのパスを返す。
function OutputSettingsIniPath: string;

implementation

uses
  Winapi.Windows, System.IniFiles, System.SysUtils;

const
  SETTINGS_SECTION = 'Settings'; // INIの設定セクション名
  SETTINGS_VERSION = 3;          // 現在の保存形式の目印

// 出力モードをINIへ保存する安定名へ変換する。
function EncodeModeToName(Mode: TOutputEncodeModeKind): string;
begin
  case Mode of
    oemAlphaProRes:
      Result := 'AlphaProRes';
  else
    Result := 'Normal';
  end;
end;

// 未知の出力モード名はDefaultへ丸める。
function EncodeModeFromName(const Name: string; Default: TOutputEncodeModeKind): TOutputEncodeModeKind;
begin
  if SameText(Name, 'AlphaProRes') or SameText(Name, 'Alpha') or
    SameText(Name, 'ProRes4444') then
    Result := oemAlphaProRes
  else if SameText(Name, 'Normal') or SameText(Name, 'MP4') then
    Result := oemNormal
  else
    Result := Default;
end;

// プラグインDLLと同じフォルダに置くINIのパスを返す。
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

// encoder種別をINIへ保存する安定名へ変換する。
function EncoderKindToName(Kind: TOutputEncoderKind): string;
begin
  case Kind of
    oekCpuX264:
      Result := 'CpuX264';
    oekIntelQsv:
      Result := 'IntelQsv';
    oekNvidiaNvenc:
      Result := 'NvidiaNvenc';
    oekAmdAmf:
      Result := 'AmdAmf';
  else
    Result := 'IntelQsv';
  end;
end;

// 未知のencoder名はDefaultへ丸め、古いINIでも読み込みエラーにしない。
function EncoderKindFromName(const Name: string; Default: TOutputEncoderKind): TOutputEncoderKind;
begin
  if SameText(Name, 'CpuX264') or SameText(Name, 'libx264') then
    Result := oekCpuX264
  else if SameText(Name, 'IntelQsv') or SameText(Name, 'h264_qsv') then
    Result := oekIntelQsv
  else if SameText(Name, 'NvidiaNvenc') or SameText(Name, 'NVENC') or
    SameText(Name, 'h264_nvenc') then
    Result := oekNvidiaNvenc
  else if SameText(Name, 'AmdAmf') or SameText(Name, 'AMF') or
    SameText(Name, 'h264_amf') then
    Result := oekAmdAmf
  else
    Result := Default;
end;

// video qualityをINIへ保存する安定名へ変換する。
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

// 未知のvideo quality名はDefaultへ丸める。
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

// audio modeをINIへ保存する安定名へ変換する。
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

// 未知のaudio mode名はDefaultへ丸める。
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

// 現在のSettingsからINIへ保存するvideo qualityを推定する。
function VideoQualityFromSettings(const Settings: TOutputTestSettings): TOutputVideoQualityKind;
begin
  if Settings.Video.BitRate >= 8000000 then
    Result := ovqHigh
  else if Settings.Video.BitRate <= 2500000 then
    Result := ovqFast
  else
    Result := ovqStandard;
end;

// 現在のSettingsからINIへ保存するaudio modeを推定する。
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

// INIを読み、壊れた値や未知値は既定値へ丸めてSettingsへ展開する。
procedure LoadOutputSettingsFromIni(var Settings: TOutputTestSettings);
var
  Ini: TIniFile;
  EncodeMode: TOutputEncodeModeKind;
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
      EncodeMode := EncodeModeFromName(
        Ini.ReadString(SETTINGS_SECTION, 'EncodeMode', EncodeModeToName(Settings.EncodeMode)),
        Settings.EncodeMode);
      VideoQuality := VideoQualityFromName(
        Ini.ReadString(SETTINGS_SECTION, 'VideoQuality',
          VideoQualityToName(VideoQualityFromSettings(Settings))),
        VideoQualityFromSettings(Settings));
      AudioMode := AudioModeFromName(
        Ini.ReadString(SETTINGS_SECTION, 'AudioMode', AudioModeToName(AudioModeFromSettings(Settings))),
        AudioModeFromSettings(Settings));

      ApplyEncoderDefaults(Settings, EncoderKind);
      ApplyVideoQuality(Settings, VideoQuality);
      ApplyAudioMode(Settings, AudioMode);
      ApplyEncodeMode(Settings, EncodeMode);
      Settings.RotateOutputDegrees := NormalizeOutputRotationDegrees(
        Ini.ReadInteger(SETTINGS_SECTION, 'RotateOutputDegrees',
          Settings.RotateOutputDegrees));
      if (Settings.RotateOutputDegrees = 0) and
        Ini.ReadBool(SETTINGS_SECTION, 'RotateOutput90Degrees', False) then
        Settings.RotateOutputDegrees := 90;
      Settings.ShowCheckLogAfterEncode := Ini.ReadBool(SETTINGS_SECTION,
        'ShowCheckLogAfterEncode', Settings.ShowCheckLogAfterEncode);
    finally
      Ini.Free;
    end;
  except
    InitDefaultOutputSettings(Settings);
  end;
end;

// 本質的な選択値だけをINIへ保存し、派生値の不整合を避ける。
procedure SaveOutputSettingsToIni(const Settings: TOutputTestSettings);
var
  Ini: TIniFile;
begin
  try
    ForceDirectories(ExtractFilePath(OutputSettingsIniPath));
    Ini := TIniFile.Create(OutputSettingsIniPath);
    try
      Ini.WriteInteger(SETTINGS_SECTION, 'Version', SETTINGS_VERSION);
      Ini.WriteString(SETTINGS_SECTION, 'EncodeMode',
        EncodeModeToName(Settings.EncodeMode));
      Ini.WriteString(SETTINGS_SECTION, 'Encoder',
        EncoderKindToName(Settings.Video.EncoderKind));
      Ini.WriteString(SETTINGS_SECTION, 'VideoQuality',
        VideoQualityToName(VideoQualityFromSettings(Settings)));
      Ini.WriteString(SETTINGS_SECTION, 'AudioMode',
        AudioModeToName(AudioModeFromSettings(Settings)));
      Ini.WriteInteger(SETTINGS_SECTION, 'RotateOutputDegrees',
        NormalizeOutputRotationDegrees(Settings.RotateOutputDegrees));
      Ini.WriteBool(SETTINGS_SECTION, 'RotateOutput90Degrees',
        NormalizeOutputRotationDegrees(Settings.RotateOutputDegrees) = 90);
      Ini.WriteBool(SETTINGS_SECTION, 'ShowCheckLogAfterEncode',
        Settings.ShowCheckLogAfterEncode);
    finally
      Ini.Free;
    end;
  except
    // 設定保存の失敗で出力処理を止めない。
  end;
end;

// プレビュー画面から切り替えたcheck log表示設定だけをINIへ反映する。
procedure SaveOutputCheckLogDisplayToIni(ShowCheckLogAfterEncode: Boolean);
var
  Ini: TIniFile;
begin
  try
    ForceDirectories(ExtractFilePath(OutputSettingsIniPath));
    Ini := TIniFile.Create(OutputSettingsIniPath);
    try
      Ini.WriteInteger(SETTINGS_SECTION, 'Version', SETTINGS_VERSION);
      Ini.WriteBool(SETTINGS_SECTION, 'ShowCheckLogAfterEncode',
        ShowCheckLogAfterEncode);
    finally
      Ini.Free;
    end;
  except
    // 設定保存の失敗で出力処理を止めない。
  end;
end;

end.
