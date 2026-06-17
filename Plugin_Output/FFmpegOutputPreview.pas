unit FFmpegOutputPreview;

{$WARN IMPLICIT_STRING_CAST OFF}

interface

// エンコード中の簡易プレビューと暗いフレーム検査ログを管理する。
// エンコード本体へは診断表示だけを提供し、出力ファイルの内容には影響させない。

uses
  Winapi.Windows, System.SysUtils, FFmpegOutputVideoInput;

type
  TOutputPreviewSeverity = (
    opsNormal,  // 問題を検出していない状態
    opsCaution, // 短時間の暗いフレームを検出した状態
    opsWarning, // 継続する暗いフレームを検出した状態
    opsError    // 長時間の暗いフレームを検出した状態
  );

  TOutputPreviewWindow = class
  public
    constructor Create(const SaveFileName, EncodeDescription: string;
      SourceWidth, SourceHeight, TotalFrames, Rate, Scale: Integer;
      VideoInputKind: TOutputVideoInputKind; ShowCheckLogAfterEncode: Boolean);
    destructor Destroy; override;
    procedure UpdateFrame(FrameIndex: Integer; FrameData: Pointer);
    procedure UpdateStatus(const Text: string);
    procedure Close;
  private
    FSourceWidth       : Integer;                // AviUtl2から受け取る元映像幅
    FSourceHeight      : Integer;                // AviUtl2から受け取る元映像高さ
    FTotalFrames       : Integer;                // 出力対象の総フレーム数
    FRate              : Integer;                // AviUtl2のフレームレート分子
    FScale             : Integer;                // AviUtl2のフレームレート分母
    FDurationMs        : Int64;                  // 動画全体の推定時間ms
    FVideoInputKind    : TOutputVideoInputKind;  // プレビュー変換に使う入力形式
    FSaveFileName      : string;                 // check logの基準になる出力ファイル名
    FEncodeDescription : string;                 // check logへ記録するエンコード設定説明
    FLastTick          : UInt64;                 // 前回プレビュー表示を更新したtick
    FForm              : TObject;                // 実体のTFormを遅延参照する枠
    FImage             : TObject;                // 実体のTImageを遅延参照する枠
    FPreviewPanel      : TObject;                // 実体のプレビュー配置用TPanelを遅延参照する枠
    FControlPanel      : TObject;                // 実体のTPanelを遅延参照する枠
    FStatusLabel       : TObject;                // 実体のTLabelを遅延参照する枠
    FCheckLogOption    : TObject;                // 実体のTCheckBoxを遅延参照する枠
    FCheckLogLabel     : TObject;                // 実体のTLabelを遅延参照する枠
    FBitmap            : TObject;                // プレビュー表示用TBitmap
    FSwsContext        : Pointer;                // プレビュー縮小変換用sws context
    FPreviewBuffer     : TBytes;                 // BGR24へ変換したプレビュー画素buffer
    FLogWriter         : TObject;                // check logを書き込むTStreamWriter
    FLogFileName       : string;                 // check logの出力先
    FCautionCount      : Integer;                // cautionとして記録した区間数
    FWarningCount      : Integer;                // warningとして記録した区間数
    FErrorCount        : Integer;                // errorとして記録した区間数
    FDarkStartFrame    : Integer;                // 暗いフレーム区間の開始フレーム
    FCurrentSeverity   : TOutputPreviewSeverity; // 現在表示している検査状態
    FShowCheckLogAfterEncode : Boolean;          // 確認ポイントがある場合に終了後check logを表示するか
    FPreviewWidth      : Integer;                // プレビュー表示幅
    FPreviewHeight     : Integer;                // プレビュー表示高さ
    procedure BuildWindow;
    procedure ConvertFrameToBitmap(FrameData: Pointer);
    procedure OpenLog;
    procedure CloseLog;
    procedure LogLine(const Text: string);
    function FramePositionMs(FrameIndex: Integer): Int64;
    function PreviewCornersMostlyDark: Boolean;
    procedure FinishDarkSegment(EndFrameIndex: Integer; const Reason: string);
    procedure UpdateFrameCheck(FrameIndex: Integer);
    procedure LogOptionClick(Sender: TObject);
    procedure LogOptionLabelClick(Sender: TObject);
    procedure ResizeControls(Sender: TObject);
    procedure SetStatus(Severity: TOutputPreviewSeverity; const Text: string);
  end;

implementation

uses
  System.Classes, System.Math, System.Types, Winapi.ShellAPI, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, FFmpegApi,
  FFmpegOutputSettingsStorage;

const
  PREVIEW_MAX_WIDTH              = 480;  // プレビュー表示の最大幅px
  PREVIEW_MAX_HEIGHT             = 270;  // プレビュー表示の最大高さpx
  PREVIEW_UPDATE_INTERVAL_MS     = 200;  // 画面表示更新を間引く最短間隔ms
  FRAME_CHECK_DARK_CORNER_SIZE   = 8;    // 暗いフレーム判定に使う四隅の検査サイズpx
  FRAME_CHECK_DARK_CORNER_THRESHOLD = 18; // 暗いフレーム判定で使う平均輝度の上限
  DARK_CAUTION_DURATION_MS       = 500;  // cautionへ上げる暗い区間の継続時間ms
  DARK_WARNING_DURATION_MS       = 1500; // warningへ上げる暗い区間の継続時間ms
  DARK_ERROR_DURATION_MS         = 3000; // errorへ上げる暗い区間の継続時間ms

// ログへ出す動画上の時刻をhh:mm:ss.mmmへ整形する。
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

// check logへ出す検査状態名を返す。
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

// 出力情報を保持し、check logとプレビューウィンドウを準備する。
constructor TOutputPreviewWindow.Create(const SaveFileName,
  EncodeDescription: string; SourceWidth, SourceHeight, TotalFrames, Rate,
  Scale: Integer; VideoInputKind: TOutputVideoInputKind;
  ShowCheckLogAfterEncode: Boolean);
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
  FVideoInputKind := VideoInputKind;
  FShowCheckLogAfterEncode := ShowCheckLogAfterEncode;
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

// プレビュー関連リソースを閉じる。
destructor TOutputPreviewWindow.Destroy;
begin
  Close;
  inherited;
end;

// プレビュー表示用のVCLウィンドウと縮小変換contextを作る。
procedure TOutputPreviewWindow.BuildWindow;
var
  Form: TForm;
  PreviewPanel: TPanel;
  Image: TImage;
  ControlPanel: TPanel;
  StatusLabel: TLabel;
  CheckLogOption: TCheckBox;
  CheckLogLabel: TLabel;
  Bitmap: TBitmap;
  CheckCaption: string;
  ContentWidth: Integer;
  Margin: Integer;
  PanelHeight: Integer;
begin
  Margin := 10;
  PanelHeight := 48;
  CheckCaption := '確認ポイントがある場合、出力後にログを表示';

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
  Form.Canvas.Font.Assign(Form.Font);
  ContentWidth := Max(FPreviewWidth, Form.Canvas.TextWidth(CheckCaption) + 24);
  Form.ClientWidth := ContentWidth + Margin * 2;
  Form.ClientHeight := FPreviewHeight + PanelHeight;
  Form.Constraints.MinWidth := ContentWidth + Margin * 2;
  Form.Constraints.MinHeight := PanelHeight + 120;

  PreviewPanel := TPanel.Create(Form);
  PreviewPanel.Parent := Form;
  PreviewPanel.Align := alClient;
  PreviewPanel.BevelOuter := bvNone;
  PreviewPanel.Color := clBlack;
  PreviewPanel.ParentBackground := False;

  Image := TImage.Create(Form);
  Image.Parent := PreviewPanel;
  Image.Align := alClient;
  Image.Stretch := True;
  Image.Proportional := True;
  Image.Center := True;
  Image.Transparent := False;

  ControlPanel := TPanel.Create(Form);
  ControlPanel.Parent := Form;
  ControlPanel.Align := alBottom;
  ControlPanel.Height := PanelHeight;
  ControlPanel.BevelOuter := bvNone;
  ControlPanel.Color := $00202020;
  ControlPanel.ParentBackground := False;

  StatusLabel := TLabel.Create(Form);
  StatusLabel.Parent := ControlPanel;
  StatusLabel.Left := Margin;
  StatusLabel.Top := 6;
  StatusLabel.Height := 18;
  StatusLabel.AutoSize := False;
  StatusLabel.Transparent := False;
  StatusLabel.Color := ControlPanel.Color;
  StatusLabel.Font.Color := clWhite;
  StatusLabel.Caption := 'Preparing preview...';

  CheckLogOption := TCheckBox.Create(Form);
  CheckLogOption.Parent := ControlPanel;
  CheckLogOption.Left := Margin;
  CheckLogOption.Top := StatusLabel.Top + StatusLabel.Height + 4;
  CheckLogOption.Width := 18;
  CheckLogOption.Height := 18;
  CheckLogOption.Caption := '';
  CheckLogOption.Checked := FShowCheckLogAfterEncode;
  CheckLogOption.Color := ControlPanel.Color;
  CheckLogOption.Font.Color := clWhite;
  CheckLogOption.OnClick := LogOptionClick;

  CheckLogLabel := TLabel.Create(Form);
  CheckLogLabel.Parent := ControlPanel;
  CheckLogLabel.Left := CheckLogOption.Left + CheckLogOption.Width + 4;
  CheckLogLabel.Top := CheckLogOption.Top + 1;
  CheckLogLabel.Height := 18;
  CheckLogLabel.AutoSize := False;
  CheckLogLabel.Transparent := False;
  CheckLogLabel.Color := ControlPanel.Color;
  CheckLogLabel.Font.Color := clWhite;
  CheckLogLabel.Caption := CheckCaption;
  CheckLogLabel.OnClick := LogOptionLabelClick;

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
      OutputVideoInputFFmpegPixelFormat(FVideoInputKind), FPreviewWidth, FPreviewHeight,
      AV_PIX_FMT_BGR24, SWS_BILINEAR, nil, nil, nil);
  end;

  FForm := Form;
  FImage := Image;
  FPreviewPanel := PreviewPanel;
  FControlPanel := ControlPanel;
  FStatusLabel := StatusLabel;
  FCheckLogOption := CheckLogOption;
  FCheckLogLabel := CheckLogLabel;
  FBitmap := Bitmap;
  Form.OnResize := ResizeControls;
  ResizeControls(Form);

  Form.Show;
  Application.ProcessMessages;
end;

// ウィンドウ、bitmap、sws context、check logを閉じる。
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
  FPreviewPanel := nil;
  FControlPanel := nil;
  FStatusLabel := nil;
  FCheckLogOption := nil;
  FCheckLogLabel := nil;
  CloseLog;
end;

// 出力ファイル名に対応するcheck logを開き、検査条件を書き出す。
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

// 未完了の暗い区間を確定し、問題があればcheck logを開く。
procedure TOutputPreviewWindow.CloseLog;
var
  IssueCount: Integer;
begin
  FinishDarkSegment(FTotalFrames - 1, 'エンコード終了');
  IssueCount := FCautionCount + FWarningCount + FErrorCount;
  if FLogWriter <> nil then
  begin
    if IssueCount = 0 then
      LogLine('正常: 確認ポイントは検出されませんでした。');
    LogLine('');
    LogLine('【最終結果】');
    if IssueCount = 0 then
      LogLine('正常')
    else
      LogLine(Format('確認ポイント %d 件があります。内訳: 異常 %d 件、警告 %d 件、疑い %d 件。',
        [IssueCount, FErrorCount, FWarningCount, FCautionCount]));
    TStreamWriter(FLogWriter).Free;
    FLogWriter := nil;
  end;

  if FShowCheckLogAfterEncode and (IssueCount > 0) and (FLogFileName <> '') and
    FileExists(FLogFileName) then
    ShellExecute(0, 'open', PChar(FLogFileName), nil, nil, SW_SHOWNORMAL);
end;

// 終了後check log表示の切り替えを保持する。
procedure TOutputPreviewWindow.LogOptionClick(Sender: TObject);
begin
  if Sender is TCheckBox then
  begin
    FShowCheckLogAfterEncode := TCheckBox(Sender).Checked;
    SaveOutputCheckLogDisplayToIni(FShowCheckLogAfterEncode);
  end;
end;

// ラベル側をクリックしたときもcheck log表示の切り替えとして扱う。
procedure TOutputPreviewWindow.LogOptionLabelClick(Sender: TObject);
begin
  if FCheckLogOption = nil then
    Exit;

  TCheckBox(FCheckLogOption).Checked := not TCheckBox(FCheckLogOption).Checked;
  FShowCheckLogAfterEncode := TCheckBox(FCheckLogOption).Checked;
  SaveOutputCheckLogDisplayToIni(FShowCheckLogAfterEncode);
end;

// フォーム幅に合わせて下部表示領域を広げる。
procedure TOutputPreviewWindow.ResizeControls(Sender: TObject);
const
  CONTROL_MARGIN = 10;
begin
  if FControlPanel = nil then
    Exit;

  if FStatusLabel <> nil then
    TLabel(FStatusLabel).Width := TPanel(FControlPanel).ClientWidth - CONTROL_MARGIN * 2;
  if FCheckLogLabel <> nil then
    TLabel(FCheckLogLabel).Width := TPanel(FControlPanel).ClientWidth -
      TLabel(FCheckLogLabel).Left - CONTROL_MARGIN;
end;

// 継続中の暗いフレーム区間を指定フレームで終了させてログへ記録する。
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

// check logへ1行書き込み、調査中に途中経過が残るよう即時flushする。
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

// フレーム番号を動画上の時刻msへ変換する。
function TOutputPreviewWindow.FramePositionMs(FrameIndex: Integer): Int64;
begin
  if FrameIndex < 0 then
    FrameIndex := 0;
  if (FRate > 0) and (FScale > 0) then
    Result := (Int64(FrameIndex) * FScale * 1000) div FRate
  else
    Result := 0;
end;

// AviUtl2から受け取った入力形式をプレビュー用BGR24 bitmapへ変換する。
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
    OutputVideoInputFirstLineOffset(FVideoInputKind, FSourceWidth, FSourceHeight));
  SrcStrideArray[0] := OutputVideoInputSwsStride(FVideoInputKind, FSourceWidth);
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

// プレビュー四隅の平均輝度から暗いフレームか判定する。
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

// 検査状態に応じてステータス表示の文字列と色を更新する。
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
      StatusLabel.Font.Color := clWhite;
  else
      StatusLabel.Font.Color := clYellow;
  end;
end;

// 現在フレームの暗さを検査し、状態遷移とcheck logを更新する。
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
      StatusText := Format('確認ポイントあり - frame %d / %d',
        [FrameIndex + 1, FTotalFrames]);
    opsWarning:
      StatusText := Format('確認ポイントあり - frame %d / %d',
        [FrameIndex + 1, FTotalFrames]);
    opsCaution:
      StatusText := Format('確認ポイントあり - frame %d / %d',
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

// フレームを検査し、必要な間隔でプレビュー表示を更新する。
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

// エンコード本体から渡された状態文字列を表示する。
procedure TOutputPreviewWindow.UpdateStatus(const Text: string);
begin
  if FStatusLabel <> nil then
    TLabel(FStatusLabel).Caption := Text;
  if FForm <> nil then
    Application.ProcessMessages;
end;

end.
