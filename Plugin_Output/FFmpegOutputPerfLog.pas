unit FFmpegOutputPerfLog;

// エンコード中の処理時間をstage別に記録し、調査用のperf logへ即時flushする。
// Debug時だけ有効にし、通常のRelease出力ではログ生成の負荷を避ける。

interface

uses
  System.Diagnostics, System.SysUtils;

const
  {$IFDEF DEBUG}
  OUTPUT_PERF_LOG_ENABLED        = True;  // Debugビルドでperf logを出すか
  {$ELSE}
  OUTPUT_PERF_LOG_ENABLED        = False; // Releaseビルドでperf logを出さない
  {$ENDIF}
  OUTPUT_PERF_LOG_EVERY_N_FRAMES = 30; // 途中経過を出すフレーム間隔

type
  TOutputPerfStage = (
    opsGetVideo,          // AviUtl2から映像フレームを取得するstage
    opsFrameWritable,     // FFmpeg映像frameを書き込み可能にするstage
    opsVideoConvert,      // 入力映像をencoder用pixel formatへ変換するstage
    opsVideoEncodeWrite,  // 映像frameをencodeしpacketをmuxerへ書くstage
    opsGetAudio,          // AviUtl2からPCM音声を取得するstage
    opsAudioWritable,     // FFmpeg音声frameを書き込み可能にするstage
    opsAudioConvert,      // PCM音声をAAC encoder用sample formatへ変換するstage
    opsAudioEncodeWrite   // 音声frameをencodeしpacketをmuxerへ書くstage
  );

  TOutputPerfStageStats = record
    Count   : Int64;  // 計測回数
    TotalMs : Double; // 合計ms
    MaxMs   : Double; // 最大ms
    procedure Add(ElapsedMs: Double);
    function AverageMs: Double;
  end;

  TOutputPerfLogger = class
  private
    FFile         : TextFile;                                         // 出力中のlog file
    FOpened       : Boolean;                                          // log fileを開けたかどうか
    FStats        : array[TOutputPerfStage] of TOutputPerfStageStats; // stage別統計
    FLastFrameLog : Integer;                                          // 最後に途中経過を出したframe
    procedure WriteLine(const Text: string);
    procedure WriteStageSummary(Stage: TOutputPerfStage; TotalMs: Double);
    procedure WriteBottleneckSummary(TotalMs: Double);
  public
    constructor Create(const SaveFileName: string; Width, Height, TotalFrames: Integer;
      const VideoEncoder, PixelFormatName, VideoInputName: string; VideoBufferCount,
      AudioBufferCount: Integer; AudioEnabled: Boolean; const AudioEncoder: string;
      AudioBitRate, AudioSampleRate, AudioChannels: Integer);
    destructor Destroy; override;
    procedure Add(Stage: TOutputPerfStage; ElapsedMs: Double);
    procedure Trace(const Text: string);
    procedure LogFrame(FrameIndex, TotalFrames: Integer; FrameMs, AverageFps: Double);
    procedure Finish(EncodedFrameCount: Integer; TotalMs: Double; const Status: string);
  end;

function OutputPerfStageName(Stage: TOutputPerfStage): string;
function OutputPerfLogPath(const SaveFileName: string): string;
function StopwatchElapsedMs(const Stopwatch: TStopwatch): Double;

implementation

uses
  System.IOUtils;

// stage統計へ1回分の経過時間を加算する。
procedure TOutputPerfStageStats.Add(ElapsedMs: Double);
begin
  Inc(Count);
  TotalMs := TotalMs + ElapsedMs;
  if ElapsedMs > MaxMs then
    MaxMs := ElapsedMs;
end;

// stage統計の平均msを返す。
function TOutputPerfStageStats.AverageMs: Double;
begin
  if Count <= 0 then
    Result := 0
  else
    Result := TotalMs / Count;
end;

// logへ出すstage名を返す。
function OutputPerfStageName(Stage: TOutputPerfStage): string;
begin
  case Stage of
    opsGetVideo:
      Result := 'get_video';
    opsFrameWritable:
      Result := 'frame_writable';
    opsVideoConvert:
      Result := 'video_convert';
    opsVideoEncodeWrite:
      Result := 'video_encode_write';
    opsGetAudio:
      Result := 'get_audio';
    opsAudioWritable:
      Result := 'audio_writable';
    opsAudioConvert:
      Result := 'audio_convert';
    opsAudioEncodeWrite:
      Result := 'audio_encode_write';
  else
    Result := 'unknown';
  end;
end;

// 出力ファイル名に.perf.logを付けたlog pathを返す。
function OutputPerfLogPath(const SaveFileName: string): string;
begin
  if SaveFileName <> '' then
    Result := ChangeFileExt(SaveFileName, ExtractFileExt(SaveFileName) + '.perf.log')
  else
    Result := TPath.Combine(TPath.GetTempPath, 'VW_Media_Output.perf.log');
end;

// TStopwatchをmsへ変換する。
function StopwatchElapsedMs(const Stopwatch: TStopwatch): Double;
begin
  Result := Stopwatch.Elapsed.TotalMilliseconds;
end;

// log fileを開き、出力条件のheaderを書く。
constructor TOutputPerfLogger.Create(const SaveFileName: string; Width, Height,
  TotalFrames: Integer; const VideoEncoder, PixelFormatName, VideoInputName: string;
  VideoBufferCount, AudioBufferCount: Integer; AudioEnabled: Boolean;
  const AudioEncoder: string; AudioBitRate, AudioSampleRate, AudioChannels: Integer);
var
  LogPath: string;
  LogDir: string;
begin
  inherited Create;
  if not OUTPUT_PERF_LOG_ENABLED then
    Exit;

  LogPath := OutputPerfLogPath(SaveFileName);
  LogDir := ExtractFilePath(LogPath);
  if LogDir <> '' then
    ForceDirectories(LogDir);

  AssignFile(FFile, LogPath);
  Rewrite(FFile);
  FOpened := True;
  FLastFrameLog := -1;

  WriteLine('VW_Media_Output performance log');
  WriteLine('started=' + FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now));
  WriteLine(Format('output=%s', [SaveFileName]));
  WriteLine(Format('size=%dx%d frames=%d encoder=%s pixel=%s input=%s',
    [Width, Height, TotalFrames, VideoEncoder, PixelFormatName, VideoInputName]));
  WriteLine(Format('buffer video=%d audio=%d', [VideoBufferCount, AudioBufferCount]));
  WriteLine(Format('audio enabled=%s encoder=%s bitrate=%d sample_rate=%d channels=%d',
    [BoolToStr(AudioEnabled, True), AudioEncoder, AudioBitRate, AudioSampleRate,
     AudioChannels]));
  WriteLine(Format('frame_log_interval=%d', [OUTPUT_PERF_LOG_EVERY_N_FRAMES]));
  WriteLine('');
end;

// log fileを閉じる前にclosed時刻を書く。
destructor TOutputPerfLogger.Destroy;
begin
  if FOpened then
  begin
    WriteLine('closed=' + FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now));
    CloseFile(FFile);
  end;
  inherited Destroy;
end;

// logへ1行書き、クラッシュ時にも残るようflushする。
procedure TOutputPerfLogger.WriteLine(const Text: string);
begin
  if not FOpened then
    Exit;
  System.Writeln(FFile, Text);
  Flush(FFile);
end;

// stage別統計を追加する。
procedure TOutputPerfLogger.Add(Stage: TOutputPerfStage; ElapsedMs: Double);
begin
  if not FOpened then
    Exit;
  FStats[Stage].Add(ElapsedMs);
end;

// 終了処理のどこで止まったか追えるよう、即時flushされるbreadcrumbを出す。
procedure TOutputPerfLogger.Trace(const Text: string);
begin
  WriteLine(Format('trace time=%s %s',
    [FormatDateTime('hh:nn:ss.zzz', Now), Text]));
end;

// 指定間隔ごとにフレーム単位の途中経過を書く。
procedure TOutputPerfLogger.LogFrame(FrameIndex, TotalFrames: Integer; FrameMs,
  AverageFps: Double);
begin
  if not FOpened then
    Exit;
  if (OUTPUT_PERF_LOG_EVERY_N_FRAMES <= 0) or
    ((FrameIndex - FLastFrameLog) < OUTPUT_PERF_LOG_EVERY_N_FRAMES) then
    Exit;

  FLastFrameLog := FrameIndex;
  WriteLine(Format('frame=%d/%d frame_ms=%.3f avg_fps=%.3f get_video_avg=%.3f convert_avg=%.3f encode_avg=%.3f',
    [FrameIndex, TotalFrames, FrameMs, AverageFps,
     FStats[opsGetVideo].AverageMs,
     FStats[opsVideoConvert].AverageMs,
     FStats[opsVideoEncodeWrite].AverageMs]));
end;

// stage別の最終集計を書く。
procedure TOutputPerfLogger.WriteStageSummary(Stage: TOutputPerfStage; TotalMs: Double);
var
  Percent: Double;
begin
  if TotalMs > 0 then
    Percent := FStats[Stage].TotalMs * 100.0 / TotalMs
  else
    Percent := 0;

  WriteLine(Format('%s count=%d avg_ms=%.3f max_ms=%.3f total_ms=%.3f pct=%.1f',
    [OutputPerfStageName(Stage), FStats[Stage].Count, FStats[Stage].AverageMs,
     FStats[Stage].MaxMs, FStats[Stage].TotalMs, Percent]));
end;

// 最も時間を使ったstageを1行で出し、次の調査先を見つけやすくする。
procedure TOutputPerfLogger.WriteBottleneckSummary(TotalMs: Double);
var
  Stage: TOutputPerfStage;
  DominantStage: TOutputPerfStage;
  DominantMs: Double;
  DominantPercent: Double;
begin
  DominantStage := Low(TOutputPerfStage);
  DominantMs := 0;
  for Stage := Low(TOutputPerfStage) to High(TOutputPerfStage) do
  begin
    if FStats[Stage].TotalMs > DominantMs then
    begin
      DominantMs := FStats[Stage].TotalMs;
      DominantStage := Stage;
    end;
  end;

  if TotalMs > 0 then
    DominantPercent := DominantMs * 100.0 / TotalMs
  else
    DominantPercent := 0;

  WriteLine(Format('dominant_stage=%s total_ms=%.3f pct=%.1f',
    [OutputPerfStageName(DominantStage), DominantMs, DominantPercent]));
end;

// 出力完了時の総時間とstage別集計を書く。
procedure TOutputPerfLogger.Finish(EncodedFrameCount: Integer; TotalMs: Double;
  const Status: string);
var
  Stage: TOutputPerfStage;
  AverageFps: Double;
begin
  if not FOpened then
    Exit;

  if TotalMs > 0 then
    AverageFps := EncodedFrameCount * 1000.0 / TotalMs
  else
    AverageFps := 0;

  WriteLine('');
  WriteLine(Format('finish status=%s encoded_frames=%d total_ms=%.3f avg_fps=%.3f',
    [Status, EncodedFrameCount, TotalMs, AverageFps]));
  WriteBottleneckSummary(TotalMs);
  for Stage := Low(TOutputPerfStage) to High(TOutputPerfStage) do
    WriteStageSummary(Stage, TotalMs);
  WriteLine('');
end;

end.
