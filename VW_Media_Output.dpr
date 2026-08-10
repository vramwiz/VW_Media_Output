library VW_Media_Output;

uses
  Winapi.Windows,
  System.Diagnostics,
  System.IOUtils,
  System.SysUtils,
  AviUtl2OutputTypes in 'AviUtl\Output\AviUtl2OutputTypes.pas',
  FFmpegApi in 'Plugin_Output\FFmpegApi.pas',
  FFmpegOutputConfig in 'Plugin_Output\FFmpegOutputConfig.pas',
  FFmpegOutputEncoder in 'Plugin_Output\FFmpegOutputEncoder.pas',
  FFmpegOutputHostLog in 'Plugin_Output\FFmpegOutputHostLog.pas',
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

// AviUtl2のinfoログへ短い動作状況を出す。
procedure LogInfo(const MessageText: string);
begin
  OutputHostLogInfo(MessageText);
end;

// AviUtl2のwarnログへ中断などの結果を出す。
procedure LogWarning(const MessageText: string);
begin
  OutputHostLogWarning(MessageText);
end;

// AviUtl2のerrorログへエンコード失敗を出す。
procedure LogError(const MessageText: string);
begin
  OutputHostLogError(MessageText);
end;

// SDKからログハンドルを受け取り、以後の出力処理で利用する。
procedure InitializeLogger(Logger: PLogHandle); cdecl;
begin
  InitializeOutputHostLogger(Logger);
  LogInfo('VW Media Output: ログ連携を初期化しました。');
end;

// 出力開始ログへ載せる映像・音声設定の要約を作る。
function OutputStartLogText(oip: POutputInfo; const Settings: TOutputTestSettings): string;
var
  AudioText: string;
  FrameRate: Double;
begin
  if Settings.Audio.Enabled and ((oip^.flag and OUTPUT_INFO_FLAG_AUDIO) <> 0) then
    AudioText := Format('%s %d kbps',
      [Settings.Audio.CodecName, Settings.Audio.BitRate div 1000])
  else
    AudioText := '音声なし';
  if oip^.scale > 0 then
    FrameRate := oip^.rate / oip^.scale
  else
    FrameRate := 0;
  Result := Format('VW Media Output: 出力開始: %s | %s / %s (%s) / %dx%d / %.3f fps / %s',
    [ExtractFileName(Settings.SaveFileName), Settings.Container, Settings.Video.CodecName,
     string(Settings.Video.EncoderName), oip^.w, oip^.h, FrameRate, AudioText]);
end;

// 出力モードによる拡張子補正後の実ファイル名を返す。
function EffectiveOutputFileName(const Settings: TOutputTestSettings): string;
begin
  Result := Settings.SaveFileName;
  if (Settings.EncodeMode = oemAlphaProRes) and
    not SameText(ExtractFileExt(Result), '.mov') then
    Result := ChangeFileExt(Result, '.mov');
end;

// 出力完了ログへ載せる時間、平均fps、ファイルサイズを作る。
function OutputCompleteLogText(oip: POutputInfo; const Settings: TOutputTestSettings;
  const Stopwatch: TStopwatch): string;
var
  AverageFps: Double;
  ElapsedSeconds: Double;
  FileSizeBytes: Int64;
  FileSizeText: string;
  OutputFileName: string;
begin
  ElapsedSeconds := Stopwatch.Elapsed.TotalSeconds;
  if ElapsedSeconds > 0 then
    AverageFps := oip^.n / ElapsedSeconds
  else
    AverageFps := 0;
  OutputFileName := EffectiveOutputFileName(Settings);
  try
    FileSizeBytes := TFile.GetSize(OutputFileName);
    if FileSizeBytes >= Int64(1024) * 1024 * 1024 then
      FileSizeText := Format('%.2f GB', [FileSizeBytes / (1024.0 * 1024 * 1024)])
    else
      FileSizeText := Format('%.1f MB', [FileSizeBytes / (1024.0 * 1024)]);
  except
    FileSizeText := 'サイズ取得不可';
  end;
  Result := Format('VW Media Output: 出力完了: %s | 処理時間 %.1f秒 / 平均 %.1f fps / %s',
    [ExtractFileName(OutputFileName), ElapsedSeconds, AverageFps, FileSizeText]);
end;

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
  RotateText: string;
begin
  EnsureCurrentSettings;
  if CurrentSettings.Audio.Enabled then
    AudioText := Format('AAC %d kbps', [CurrentSettings.Audio.BitRate div 1000])
  else
    AudioText := 'Audio none';
  if (NormalizeOutputRotationDegrees(CurrentSettings.RotateOutputDegrees) <> 0) and
    (CurrentSettings.EncodeMode = oemNormal) then
    RotateText := Format(' / rotate-meta%d',
      [NormalizeOutputRotationDegrees(CurrentSettings.RotateOutputDegrees)])
  else
    RotateText := '';
  if CurrentSettings.EncodeMode = oemAlphaProRes then
    LastConfigText := Format('%s / %s / alpha / %s%s',
      [CurrentSettings.Container, CurrentSettings.Video.CodecName, AudioText, RotateText])
  else
    LastConfigText := Format('%s / %s / %s / %s%s',
      [CurrentSettings.Container, CurrentSettings.Video.CodecName,
       CurrentSettings.Video.PixelFormatName, AudioText, RotateText]);
end;

//------------------------------------------------------------------------------
// Output process
//------------------------------------------------------------------------------
// AviUtl2から渡された保存先を使い、現在設定の形式で直接書き出す。
function func_output(oip: POutputInfo): Boolean; cdecl;
var
  Settings: TOutputTestSettings;
  ErrorMessage: string;
  OutputStopwatch: TStopwatch;
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
    LogInfo(OutputStartLogText(oip, Settings));
    OutputStopwatch := TStopwatch.StartNew;

    Result := ExportOutputInfo(oip, Settings, ErrorMessage);
    OutputStopwatch.Stop;
    LoadOutputSettingsFromIni(CurrentSettings);
    if not Result and (ErrorMessage <> '') then
    begin
      LogError('VW Media Output: 出力失敗: ' + ErrorMessage);
      MessageBox(0, PChar(ErrorMessage), 'VW_Media_Output', MB_OK or MB_ICONERROR);
    end
    else if Result then
      LogInfo(OutputCompleteLogText(oip, Settings, OutputStopwatch))
    else
      LogWarning('VW Media Output: 出力は完了しませんでした: ' +
        ExtractFileName(Settings.SaveFileName));
  except
    on E: Exception do
    begin
      LogError('VW Media Output: 例外: ' + E.ClassName + ': ' + E.Message);
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
  LoadOutputSettingsFromIni(CurrentSettings);
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
  GetOutputPluginTable name 'GetOutputPluginTable',
  InitializeLogger name 'InitializeLogger';

begin
end.
