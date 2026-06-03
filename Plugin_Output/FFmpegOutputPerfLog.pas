unit FFmpegOutputPerfLog;

interface

uses
  System.Diagnostics, System.SysUtils;

const
  OUTPUT_PERF_LOG_ENABLED = True;
  OUTPUT_PERF_LOG_EVERY_N_FRAMES = 30;

type
  TOutputPerfStage = (
    opsGetVideo,
    opsFrameWritable,
    opsVideoConvert,
    opsVideoEncodeWrite,
    opsGetAudio,
    opsAudioWritable,
    opsAudioConvert,
    opsAudioEncodeWrite
  );

  TOutputPerfStageStats = record
    Count: Int64;
    TotalMs: Double;
    MaxMs: Double;
    procedure Add(ElapsedMs: Double);
    function AverageMs: Double;
  end;

  TOutputPerfLogger = class
  private
    FFile: TextFile;
    FOpened: Boolean;
    FStats: array[TOutputPerfStage] of TOutputPerfStageStats;
    FLastFrameLog: Integer;
    procedure WriteLine(const Text: string);
    procedure WriteStageSummary(Stage: TOutputPerfStage);
  public
    constructor Create(const SaveFileName: string; Width, Height, TotalFrames: Integer;
      const VideoEncoder, PixelFormatName, VideoInputName: string; VideoBufferCount,
      AudioBufferCount: Integer);
    destructor Destroy; override;
    procedure Add(Stage: TOutputPerfStage; ElapsedMs: Double);
    procedure LogFrame(FrameIndex, TotalFrames: Integer; FrameMs, AverageFps: Double);
    procedure Finish(EncodedFrameCount: Integer; TotalMs: Double; const Status: string);
  end;

function OutputPerfStageName(Stage: TOutputPerfStage): string;
function OutputPerfLogPath(const SaveFileName: string): string;
function StopwatchElapsedMs(const Stopwatch: TStopwatch): Double;

implementation

uses
  System.IOUtils;

procedure TOutputPerfStageStats.Add(ElapsedMs: Double);
begin
  Inc(Count);
  TotalMs := TotalMs + ElapsedMs;
  if ElapsedMs > MaxMs then
    MaxMs := ElapsedMs;
end;

function TOutputPerfStageStats.AverageMs: Double;
begin
  if Count <= 0 then
    Result := 0
  else
    Result := TotalMs / Count;
end;

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

function OutputPerfLogPath(const SaveFileName: string): string;
begin
  if SaveFileName <> '' then
    Result := ChangeFileExt(SaveFileName, ExtractFileExt(SaveFileName) + '.perf.log')
  else
    Result := TPath.Combine(TPath.GetTempPath, 'VW_Media_Output.perf.log');
end;

function StopwatchElapsedMs(const Stopwatch: TStopwatch): Double;
begin
  Result := Stopwatch.Elapsed.TotalMilliseconds;
end;

constructor TOutputPerfLogger.Create(const SaveFileName: string; Width, Height,
  TotalFrames: Integer; const VideoEncoder, PixelFormatName, VideoInputName: string;
  VideoBufferCount, AudioBufferCount: Integer);
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
  WriteLine(Format('frame_log_interval=%d', [OUTPUT_PERF_LOG_EVERY_N_FRAMES]));
  WriteLine('');
end;

destructor TOutputPerfLogger.Destroy;
begin
  if FOpened then
  begin
    WriteLine('closed=' + FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now));
    CloseFile(FFile);
  end;
  inherited Destroy;
end;

procedure TOutputPerfLogger.WriteLine(const Text: string);
begin
  if not FOpened then
    Exit;
  System.Writeln(FFile, Text);
  Flush(FFile);
end;

procedure TOutputPerfLogger.Add(Stage: TOutputPerfStage; ElapsedMs: Double);
begin
  if not FOpened then
    Exit;
  FStats[Stage].Add(ElapsedMs);
end;

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

procedure TOutputPerfLogger.WriteStageSummary(Stage: TOutputPerfStage);
begin
  WriteLine(Format('%s count=%d avg_ms=%.3f max_ms=%.3f total_ms=%.3f',
    [OutputPerfStageName(Stage), FStats[Stage].Count, FStats[Stage].AverageMs,
     FStats[Stage].MaxMs, FStats[Stage].TotalMs]));
end;

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
  for Stage := Low(TOutputPerfStage) to High(TOutputPerfStage) do
    WriteStageSummary(Stage);
  WriteLine('');
end;

end.
