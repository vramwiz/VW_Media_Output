unit FFmpegOutputPreview;

{$WARN IMPLICIT_STRING_CAST OFF}

interface

uses
  Winapi.Windows, System.SysUtils;

type
  TOutputPreviewSeverity = (opsNormal, opsCaution, opsWarning, opsError);

  TOutputPreviewWindow = class
  public
    constructor Create(const SaveFileName, EncodeDescription: string;
      SourceWidth, SourceHeight, TotalFrames, Rate, Scale: Integer);
    destructor Destroy; override;
    procedure UpdateFrame(FrameIndex: Integer; FrameData: Pointer);
    procedure UpdateStatus(const Text: string);
    procedure Close;
  private
    FSourceWidth: Integer;
    FSourceHeight: Integer;
    FTotalFrames: Integer;
    FRate: Integer;
    FScale: Integer;
    FDurationMs: Int64;
    FSaveFileName: string;
    FEncodeDescription: string;
    FLastTick: UInt64;
    FForm: TObject;
    FImage: TObject;
    FStatusLabel: TObject;
    FBitmap: TObject;
    FSwsContext: Pointer;
    FPreviewBuffer: TBytes;
    FLogWriter: TObject;
    FLogFileName: string;
    FCautionCount: Integer;
    FWarningCount: Integer;
    FErrorCount: Integer;
    FDarkStartFrame: Integer;
    FCurrentSeverity: TOutputPreviewSeverity;
    FPreviewWidth: Integer;
    FPreviewHeight: Integer;
    procedure BuildWindow;
    procedure ConvertFrameToBitmap(FrameData: Pointer);
    procedure OpenLog;
    procedure CloseLog;
    procedure LogLine(const Text: string);
    function FramePositionMs(FrameIndex: Integer): Int64;
    function PreviewCornersMostlyDark: Boolean;
    procedure FinishDarkSegment(EndFrameIndex: Integer; const Reason: string);
    procedure UpdateFrameCheck(FrameIndex: Integer);
    procedure SetStatus(Severity: TOutputPreviewSeverity; const Text: string);
  end;

implementation

uses
  System.Classes, System.Math, System.Types, Winapi.ShellAPI, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, FFmpegApi,
  FFmpegOutputVideoInput;

const
  PREVIEW_MAX_WIDTH = 480;
  PREVIEW_MAX_HEIGHT = 270;
  PREVIEW_UPDATE_INTERVAL_MS = 200;
  FRAME_CHECK_DARK_CORNER_SIZE = 8;
  FRAME_CHECK_DARK_CORNER_THRESHOLD = 18;
  DARK_CAUTION_DURATION_MS = 500;
  DARK_WARNING_DURATION_MS = 1500;
  DARK_ERROR_DURATION_MS = 3000;

function FormatLogTimeMs(ValueMs: Int64): string;
var
  Hours: Int64;
  Minutes: Int64;
  Seconds: Int64;
  Milliseconds: Int64;
begin
  if ValueMs < 0 then
    ValueMs := 0;
  Hours := ValueMs div 3600000;
  ValueMs := ValueMs mod 3600000;
  Minutes := ValueMs div 60000;
  ValueMs := ValueMs mod 60000;
  Seconds := ValueMs div 1000;
  Milliseconds := ValueMs mod 1000;
  Result := Format('%.2d:%.2d:%.2d.%.3d',
    [Hours, Minutes, Seconds, Milliseconds]);
end;

function SeverityText(Severity: TOutputPreviewSeverity): string;
begin
  case Severity of
    opsCaution:
      Result := '疑い';
    opsWarning:
      Result := '警告';
    opsError:
      Result := '異常';
  else
    Result := '正常';
  end;
end;

constructor TOutputPreviewWindow.Create(const SaveFileName,
  EncodeDescription: string; SourceWidth, SourceHeight, TotalFrames, Rate,
  Scale: Integer);
var
  PreviewScale: Double;
begin
  inherited Create;
  FSaveFileName := SaveFileName;
  FEncodeDescription := EncodeDescription;
  FSourceWidth := SourceWidth;
  FSourceHeight := SourceHeight;
  FTotalFrames := TotalFrames;
  FRate := Rate;
  FScale := Scale;
  FDurationMs := 0;
  if (FTotalFrames > 0) and (FRate > 0) and (FScale > 0) then
    FDurationMs := (Int64(FTotalFrames) * FScale * 1000) div FRate;
  FLastTick := 0;
  FSwsContext := nil;
  FLogWriter := nil;
  FCautionCount := 0;
  FWarningCount := 0;
  FErrorCount := 0;
  FDarkStartFrame := -1;
  FCurrentSeverity := opsNormal;

  if (FSourceWidth <= 0) or (FSourceHeight <= 0) then
  begin
    FPreviewWidth := PREVIEW_MAX_WIDTH;
    FPreviewHeight := PREVIEW_MAX_HEIGHT;
  end
  else
  begin
    PreviewScale := Min(PREVIEW_MAX_WIDTH / FSourceWidth,
      PREVIEW_MAX_HEIGHT / FSourceHeight);
    if PreviewScale > 1.0 then
      PreviewScale := 1.0;
    FPreviewWidth := Max(1, Round(FSourceWidth * PreviewScale));
    FPreviewHeight := Max(1, Round(FSourceHeight * PreviewScale));
  end;

  OpenLog;
  BuildWindow;
end;

destructor TOutputPreviewWindow.Destroy;
begin
  Close;
  inherited;
end;

procedure TOutputPreviewWindow.BuildWindow;
var
  Form: TForm;
  Image: TImage;
  StatusLabel: TLabel;
  Bitmap: TBitmap;
  Margin: Integer;
begin
  Margin := 10;

  Form := TForm.Create(nil);
  Form.Caption := 'VW Media Output Preview';
  Form.BorderStyle := bsSizeToolWin;
  Form.Position := poScreenCenter;
  Form.Scaled := False;
  Form.AutoScroll := False;
  Form.Font.Name := 'Segoe UI';
  Form.Font.Size := 9;
  Form.Color := clBlack;
  Form.DoubleBuffered := True;
  Form.ClientWidth := FPreviewWidth + Margin * 2;
  Form.ClientHeight := FPreviewHeight + Margin * 2 + 24;

  Image := TImage.Create(Form);
  Image.Parent := Form;
  Image.Left := Margin;
  Image.Top := Margin;
  Image.Width := FPreviewWidth;
  Image.Height := FPreviewHeight;
  Image.Stretch := False;
  Image.Proportional := False;
  Image.Center := True;
  Image.Transparent := False;

  StatusLabel := TLabel.Create(Form);
  StatusLabel.Parent := Form;
  StatusLabel.Left := Margin;
  StatusLabel.Top := Image.Top + Image.Height + 6;
  StatusLabel.Width := FPreviewWidth;
  StatusLabel.Height := 18;
  StatusLabel.AutoSize := False;
  StatusLabel.Transparent := False;
  StatusLabel.Color := clBlack;
  StatusLabel.Font.Color := clWhite;
  StatusLabel.Caption := 'Preparing preview...';

  Bitmap := TBitmap.Create;
  Bitmap.PixelFormat := pf24bit;
  Bitmap.SetSize(FPreviewWidth, FPreviewHeight);
  Bitmap.Canvas.Brush.Color := clBlack;
  Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
  SetLength(FPreviewBuffer, FPreviewWidth * FPreviewHeight * 3);
  if (FSourceWidth > 0) and (FSourceHeight > 0) then
  begin
    TFFmpegApi.EnsureLoaded;
    FSwsContext := TFFmpegApi.sws_getContext(FSourceWidth, FSourceHeight,
      OutputVideoInputFFmpegPixelFormat, FPreviewWidth, FPreviewHeight,
      AV_PIX_FMT_BGR24, SWS_BILINEAR, nil, nil, nil);
  end;

  FForm := Form;
  FImage := Image;
  FStatusLabel := StatusLabel;
  FBitmap := Bitmap;

  Form.Show;
  Application.ProcessMessages;
end;

procedure TOutputPreviewWindow.Close;
begin
  if FBitmap <> nil then
  begin
    TBitmap(FBitmap).Free;
    FBitmap := nil;
  end;
  if FSwsContext <> nil then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(FSwsContext));
    FSwsContext := nil;
  end;
  if FForm <> nil then
  begin
    TForm(FForm).Close;
    TForm(FForm).Free;
    FForm := nil;
  end;
  FImage := nil;
  FStatusLabel := nil;
  CloseLog;
end;

procedure TOutputPreviewWindow.OpenLog;
begin
  if FSaveFileName = '' then
    Exit;

  FLogFileName := FSaveFileName + '.check.log';
  try
    FLogWriter := TStreamWriter.Create(FLogFileName, False, TEncoding.UTF8);
    LogLine('VW Media Output チェックログ');
    LogLine('');
    LogLine('【エンコード内容】');
    LogLine('出力ファイル: ' + FSaveFileName);
    LogLine('エンコード方式: ' + FEncodeDescription);
    LogLine(Format('映像サイズ: %d x %d', [FSourceWidth, FSourceHeight]));
    LogLine(Format('動画の長さ: %s', [FormatLogTimeMs(FDurationMs)]));
    if (FRate > 0) and (FScale > 0) then
      LogLine(Format('フレームレート: %.6f fps (rate=%d scale=%d)',
        [FRate / FScale, FRate, FScale]));
    LogLine(Format('プレビュー判定サイズ: %d x %d', [FPreviewWidth, FPreviewHeight]));
    LogLine('');
    LogLine('【判定条件】');
    LogLine(Format('暗いフレーム疑い: 四隅 %dx%d の平均輝度が %d 以下',
      [FRAME_CHECK_DARK_CORNER_SIZE, FRAME_CHECK_DARK_CORNER_SIZE,
       FRAME_CHECK_DARK_CORNER_THRESHOLD]));
    LogLine(Format('疑い: %s 以上 / 警告: %s 以上 / 異常: %s 以上',
      [FormatLogTimeMs(DARK_CAUTION_DURATION_MS),
       FormatLogTimeMs(DARK_WARNING_DURATION_MS),
       FormatLogTimeMs(DARK_ERROR_DURATION_MS)]));
    LogLine('');
    LogLine('【検出内容】');
  except
    FLogWriter := nil;
  end;
end;

procedure TOutputPreviewWindow.CloseLog;
var
  IssueCount: Integer;
begin
  FinishDarkSegment(FTotalFrames - 1, 'エンコード終了');
  IssueCount := FCautionCount + FWarningCount + FErrorCount;
  if FLogWriter <> nil then
  begin
    if IssueCount = 0 then
      LogLine('正常: 異常や疑いは検出されませんでした。');
    LogLine('');
    LogLine('【最終結果】');
    if IssueCount = 0 then
      LogLine('正常')
    else
      LogLine(Format('異常 %d 件、警告 %d 件、疑い %d 件があります。',
        [FErrorCount, FWarningCount, FCautionCount]));
    TStreamWriter(FLogWriter).Free;
    FLogWriter := nil;
  end;

  if (IssueCount > 0) and (FLogFileName <> '') and FileExists(FLogFileName) then
    ShellExecute(0, 'open', PChar(FLogFileName), nil, nil, SW_SHOWNORMAL);
end;

procedure TOutputPreviewWindow.FinishDarkSegment(EndFrameIndex: Integer;
  const Reason: string);
begin
  if FDarkStartFrame < 0 then
    Exit;

  if FCurrentSeverity <> opsNormal then
  begin
    case FCurrentSeverity of
      opsCaution:
    Inc(FCautionCount);
      opsWarning:
        Inc(FWarningCount);
      opsError:
        Inc(FErrorCount);
    end;
    LogLine(Format('位置: %s / 段階: %s / 内容: 暗いフレーム疑いの区間が終了しました。終了理由: %s / 開始: %s / 継続: %s',
      [FormatLogTimeMs(FramePositionMs(EndFrameIndex)),
       SeverityText(FCurrentSeverity), Reason,
       FormatLogTimeMs(FramePositionMs(FDarkStartFrame)),
       FormatLogTimeMs(FramePositionMs(EndFrameIndex) -
         FramePositionMs(FDarkStartFrame))]));
  end;

  FDarkStartFrame := -1;
  FCurrentSeverity := opsNormal;
end;

procedure TOutputPreviewWindow.LogLine(const Text: string);
begin
  if FLogWriter = nil then
    Exit;

  try
    TStreamWriter(FLogWriter).WriteLine(Text);
    TStreamWriter(FLogWriter).Flush;
  except
  end;
end;

function TOutputPreviewWindow.FramePositionMs(FrameIndex: Integer): Int64;
begin
  if FrameIndex < 0 then
    FrameIndex := 0;
  if (FRate > 0) and (FScale > 0) then
    Result := (Int64(FrameIndex) * FScale * 1000) div FRate
  else
    Result := 0;
end;

procedure TOutputPreviewWindow.ConvertFrameToBitmap(FrameData: Pointer);
var
  Bitmap: TBitmap;
  Y: Integer;
  SrcData: array[0..7] of Pointer;
  SrcStrideArray: array[0..7] of Integer;
  DstData: array[0..7] of Pointer;
  DstStrideArray: array[0..7] of Integer;
  DstLine: PByte;
  BufferLine: PByte;
  RowBytes: Integer;
begin
  if (FrameData = nil) or (FBitmap = nil) or (FSwsContext = nil) or
    (Length(FPreviewBuffer) <= 0) then
    Exit;

  Bitmap := TBitmap(FBitmap);
  Bitmap.Canvas.Brush.Color := clBlack;
  Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));

  FillChar(SrcData, SizeOf(SrcData), 0);
  FillChar(SrcStrideArray, SizeOf(SrcStrideArray), 0);
  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstStrideArray, SizeOf(DstStrideArray), 0);
  SrcData[0] := Pointer(NativeUInt(FrameData) +
    OutputVideoInputFirstLineOffset(FSourceWidth, FSourceHeight));
  SrcStrideArray[0] := OutputVideoInputSwsStride(FSourceWidth);
  DstData[0] := @FPreviewBuffer[0];
  DstStrideArray[0] := FPreviewWidth * 3;

  TFFmpegApi.sws_scale(PSwsContext(FSwsContext), @SrcData[0], @SrcStrideArray[0],
    0, FSourceHeight, @DstData[0], @DstStrideArray[0]);

  RowBytes := FPreviewWidth * 3;
  for Y := 0 to FPreviewHeight - 1 do
  begin
    DstLine := Bitmap.ScanLine[Y];
    BufferLine := @FPreviewBuffer[Y * RowBytes];
    Move(BufferLine^, DstLine^, RowBytes);
  end;
end;

function TOutputPreviewWindow.PreviewCornersMostlyDark: Boolean;

  function CornerIsDark(Left, Top, CornerWidth, CornerHeight: Integer): Boolean;
  var
    Line: PByte;
    Pixel: PByte;
    Total: Int64;
    X: Integer;
    Y: Integer;
  begin
    Total := 0;
    for Y := Top to Top + CornerHeight - 1 do
    begin
      Line := @FPreviewBuffer[Y * FPreviewWidth * 3];
      for X := Left to Left + CornerWidth - 1 do
      begin
        Pixel := Line + X * 3;
        Total := Total + Pixel^ + (Pixel + 1)^ + (Pixel + 2)^;
      end;
    end;

    Result := Total <= Int64(CornerWidth) * CornerHeight * 3 *
      FRAME_CHECK_DARK_CORNER_THRESHOLD;
  end;

var
  CornerHeight: Integer;
  CornerWidth: Integer;
begin
  Result := False;
  if (Length(FPreviewBuffer) <= 0) or (FPreviewWidth <= 0) or
    (FPreviewHeight <= 0) then
    Exit;

  CornerWidth := Min(FRAME_CHECK_DARK_CORNER_SIZE, FPreviewWidth);
  CornerHeight := Min(FRAME_CHECK_DARK_CORNER_SIZE, FPreviewHeight);
  Result := CornerIsDark(0, 0, CornerWidth, CornerHeight) and
    CornerIsDark(FPreviewWidth - CornerWidth, 0, CornerWidth, CornerHeight) and
    CornerIsDark(0, FPreviewHeight - CornerHeight, CornerWidth, CornerHeight) and
    CornerIsDark(FPreviewWidth - CornerWidth, FPreviewHeight - CornerHeight,
      CornerWidth, CornerHeight);
end;

procedure TOutputPreviewWindow.SetStatus(Severity: TOutputPreviewSeverity;
  const Text: string);
var
  StatusLabel: TLabel;
begin
  if FStatusLabel = nil then
    Exit;

  StatusLabel := TLabel(FStatusLabel);
  StatusLabel.Caption := Text;
  case Severity of
    opsNormal:
      StatusLabel.Font.Color := $00A0FFA0;
    opsCaution:
      StatusLabel.Font.Color := $0000D7FF;
    opsWarning:
      StatusLabel.Font.Color := $000080FF;
    opsError:
      StatusLabel.Font.Color := $000000FF;
  end;
end;

procedure TOutputPreviewWindow.UpdateFrameCheck(FrameIndex: Integer);
var
  Dark: Boolean;
  DurationMs: Int64;
  NewSeverity: TOutputPreviewSeverity;
  StatusText: string;
begin
  Dark := PreviewCornersMostlyDark;
  if not Dark then
  begin
    FinishDarkSegment(FrameIndex, '正常復帰');
    SetStatus(opsNormal, Format('正常 - frame %d / %d',
      [FrameIndex + 1, FTotalFrames]));
    Exit;
  end;

  if FDarkStartFrame < 0 then
    FDarkStartFrame := FrameIndex;

  DurationMs := FramePositionMs(FrameIndex) - FramePositionMs(FDarkStartFrame);
  if DurationMs < 0 then
    DurationMs := 0;
  NewSeverity := opsNormal;
  if DurationMs >= DARK_ERROR_DURATION_MS then
    NewSeverity := opsError
  else if DurationMs >= DARK_WARNING_DURATION_MS then
    NewSeverity := opsWarning
  else if DurationMs >= DARK_CAUTION_DURATION_MS then
    NewSeverity := opsCaution;

  case NewSeverity of
    opsError:
      StatusText := Format('異常: 暗いフレーム疑い - frame %d / %d',
        [FrameIndex + 1, FTotalFrames]);
    opsWarning:
      StatusText := Format('警告: 暗いフレーム疑い - frame %d / %d',
        [FrameIndex + 1, FTotalFrames]);
    opsCaution:
      StatusText := Format('疑い: 暗いフレーム疑い - frame %d / %d',
        [FrameIndex + 1, FTotalFrames]);
  else
    StatusText := Format('正常 - frame %d / %d', [FrameIndex + 1, FTotalFrames]);
  end;

  SetStatus(NewSeverity, StatusText);
  if Ord(NewSeverity) > Ord(FCurrentSeverity) then
  begin
    FCurrentSeverity := NewSeverity;
    if NewSeverity <> opsNormal then
    begin
      LogLine(Format('位置: %s / 段階: %s / 内容: 暗いフレームが混入している疑いがあります。開始: %s / 継続: %s',
        [FormatLogTimeMs(FramePositionMs(FrameIndex)), SeverityText(NewSeverity),
         FormatLogTimeMs(FramePositionMs(FDarkStartFrame)),
         FormatLogTimeMs(DurationMs)]));
    end;
  end;
end;

procedure TOutputPreviewWindow.UpdateFrame(FrameIndex: Integer; FrameData: Pointer);
var
  NowTick: UInt64;
  Image: TImage;
begin
  if (FForm = nil) or (FImage = nil) or (FStatusLabel = nil) then
    Exit;

  ConvertFrameToBitmap(FrameData);
  UpdateFrameCheck(FrameIndex);

  NowTick := GetTickCount64;
  if (FLastTick <> 0) and ((NowTick - FLastTick) < PREVIEW_UPDATE_INTERVAL_MS) and
    (FrameIndex < FTotalFrames - 1) then
    Exit;
  FLastTick := NowTick;

  Image := TImage(FImage);
  Image.Picture.Assign(TBitmap(FBitmap));
  Application.ProcessMessages;
end;

procedure TOutputPreviewWindow.UpdateStatus(const Text: string);
begin
  if FStatusLabel <> nil then
    TLabel(FStatusLabel).Caption := Text;
  if FForm <> nil then
    Application.ProcessMessages;
end;

end.
