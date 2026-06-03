unit FFmpegOutputSettingsDialog;

interface

uses
  Winapi.Windows, FFmpegOutputConfig;

function ExecuteOutputSettingsDialog(OwnerWindow: HWND;
  var Settings: TOutputTestSettings): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.Math, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TOutputSettingsDialogHandler = class(TComponent)
  public
    ComboEncoder: TComboBox; // encoder選択
    ComboQuality: TComboBox; // video quality選択
    ComboAudio: TComboBox; // audio bitrate選択
    LabelSettings: TLabel; // 下部の短い設定概要
    procedure SettingChange(Sender: TObject);
    procedure UpdateSettingsLabel;
  end;

// いずれかの選択が変わったら概要表示だけ更新する。
procedure TOutputSettingsDialogHandler.SettingChange(Sender: TObject);
begin
  UpdateSettingsLabel;
end;

// 本番UIでは情報を詰め込みすぎず、2行の概要に抑える。
procedure TOutputSettingsDialogHandler.UpdateSettingsLabel;
var
  Info: TOutputEncoderInfo;
  Quality: TOutputVideoQualityKind;
  AudioMode: TOutputAudioModeKind;
  BitRate: Int64;
  AudioText: string;
begin
  if (ComboEncoder = nil) or (ComboQuality = nil) or (ComboAudio = nil) or
     (LabelSettings = nil) or (ComboEncoder.ItemIndex < 0) or
     (ComboQuality.ItemIndex < 0) or (ComboAudio.ItemIndex < 0) then
    Exit;

  Info := OutputEncoderInfo(ComboEncoder.ItemIndex);
  Quality := OutputVideoQualityByIndex(ComboQuality.ItemIndex);
  AudioMode := OutputAudioModeByIndex(ComboAudio.ItemIndex);
  case Quality of
    ovqHigh:
      BitRate := 8000000;
    ovqFast:
      BitRate := 2500000;
  else
    BitRate := 4000000;
  end;

  case AudioMode of
    oamAac576:
      AudioText := 'AAC 576 kbps';
    oamAac384:
      AudioText := 'AAC 384 kbps';
    oamAac256:
      AudioText := 'AAC 256 kbps';
    oamAac192:
      AudioText := 'AAC 192 kbps';
    oamAac128:
      AudioText := 'AAC 128 kbps';
    oamNone:
      AudioText := 'None';
  else
    AudioText := 'AAC 192 kbps';
  end;

  LabelSettings.Caption :=
    Format('MP4 / %s / %s', [Info.DisplayName, AudioText]) + sLineBreak +
    Format('Video %s / %.1f Mbps', [OutputVideoQualityName(Quality),
      BitRate / 1000000.0]);
end;

// 現在のbitrateからダイアログ選択用のqualityへ戻す。
function VideoQualityFromSettings(const Settings: TOutputTestSettings): TOutputVideoQualityKind;
begin
  if Settings.Video.BitRate >= 8000000 then
    Result := ovqHigh
  else if Settings.Video.BitRate <= 2500000 then
    Result := ovqFast
  else
    Result := ovqStandard;
end;

// 現在のbitrateからダイアログ選択用のaudio modeへ戻す。
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

// AviUtl2の設定ボタンから開く、保存先を持たないエンコード専用ダイアログ。
function ExecuteOutputSettingsDialog(OwnerWindow: HWND;
  var Settings: TOutputTestSettings): Boolean;
var
  Dialog: TForm;
  LabelEncoder: TLabel;
  ComboEncoder: TComboBox;
  LabelQuality: TLabel;
  ComboQuality: TComboBox;
  LabelAudio: TLabel;
  ComboAudio: TComboBox;
  LabelSettings: TLabel;
  ButtonOk: TButton;
  ButtonCancel: TButton;
  DialogHandler: TOutputSettingsDialogHandler;
  EncoderIndex: Integer;
  EncoderInfo: TOutputEncoderInfo;
  Index: Integer;
  OldApplicationHandle: HWND;
  Margin: Integer;
  Gap: Integer;
  LabelHeight: Integer;
  LabelGap: Integer;
  RowGap: Integer;
  ComboHeight: Integer;
  ButtonWidth: Integer;
  ButtonHeight: Integer;
  EncoderWidth: Integer;
  QualityWidth: Integer;
  AudioWidth: Integer;
  SettingsHeight: Integer;
  ButtonTop: Integer;

  function S(Value: Integer): Integer;
  var
    PPI: Integer;
  begin
    PPI := Dialog.CurrentPPI;
    if PPI <= 0 then
      PPI := Screen.PixelsPerInch;
    if PPI <= 0 then
      PPI := 96;
    Result := MulDiv(Value, PPI, 96);
  end;

  function TextWidthWithPadding(const Text: string; MinimumWidth: Integer): Integer;
  begin
    Result := Max(MinimumWidth, Dialog.Canvas.TextWidth(Text) + S(48));
  end;
begin
  Result := False;

  OldApplicationHandle := Application.Handle;
  if OwnerWindow <> 0 then
    Application.Handle := OwnerWindow;

  Dialog := TForm.Create(nil);
  try
    Dialog.Caption := 'VW Media Output Settings';
    Dialog.BorderStyle := bsDialog;
    Dialog.Position := poOwnerFormCenter;
    Dialog.Scaled := False;
    Dialog.AutoScroll := False;
    Dialog.Font.Name := 'Segoe UI';
    Dialog.Font.Size := 9;
    Dialog.Canvas.Font.Assign(Dialog.Font);

    Margin := S(16);
    Gap := S(16);
    LabelHeight := Dialog.Canvas.TextHeight('Video quality') + S(2);
    LabelGap := S(5);
    RowGap := S(14);
    ComboHeight := S(25);
    ButtonWidth := S(88);
    ButtonHeight := S(29);
    EncoderWidth := TextWidthWithPadding('GPU / H.264 Intel QSV', S(280));
    QualityWidth := TextWidthWithPadding('High quality', S(170));
    AudioWidth := TextWidthWithPadding('AAC 576 kbps', S(170));
    SettingsHeight := Dialog.Canvas.TextHeight('MP4') * 2 + S(14);
    Dialog.ClientWidth := Margin * 2 + EncoderWidth + Gap + QualityWidth;
    Dialog.ClientHeight := Margin + LabelHeight + LabelGap + ComboHeight +
      RowGap + LabelHeight + LabelGap + ComboHeight + RowGap + SettingsHeight +
      RowGap + ButtonHeight + Margin;
    ButtonTop := Dialog.ClientHeight - Margin - ButtonHeight;

    LabelEncoder := TLabel.Create(Dialog);
    LabelEncoder.Parent := Dialog;
    LabelEncoder.Left := Margin;
    LabelEncoder.Top := Margin;
    LabelEncoder.Caption := 'Encoder';

    ComboEncoder := TComboBox.Create(Dialog);
    ComboEncoder.Parent := Dialog;
    ComboEncoder.Left := Margin;
    ComboEncoder.Top := LabelEncoder.Top + LabelHeight + LabelGap;
    ComboEncoder.Width := EncoderWidth;
    ComboEncoder.Height := ComboHeight;
    ComboEncoder.Style := csDropDownList;
    for EncoderIndex := 0 to OUTPUT_ENCODER_COUNT - 1 do
    begin
      EncoderInfo := OutputEncoderInfo(EncoderIndex);
      ComboEncoder.Items.Add(EncoderInfo.DisplayName);
    end;
    ComboEncoder.ItemIndex := OutputEncoderIndexByKind(Settings.Video.EncoderKind);

    LabelQuality := TLabel.Create(Dialog);
    LabelQuality.Parent := Dialog;
    LabelQuality.Left := ComboEncoder.Left + ComboEncoder.Width + Gap;
    LabelQuality.Top := LabelEncoder.Top;
    LabelQuality.Caption := 'Video quality';

    ComboQuality := TComboBox.Create(Dialog);
    ComboQuality.Parent := Dialog;
    ComboQuality.Left := LabelQuality.Left;
    ComboQuality.Top := ComboEncoder.Top;
    ComboQuality.Width := QualityWidth;
    ComboQuality.Height := ComboHeight;
    ComboQuality.Style := csDropDownList;
    for Index := 0 to OUTPUT_VIDEO_QUALITY_COUNT - 1 do
      ComboQuality.Items.Add(OutputVideoQualityName(OutputVideoQualityByIndex(Index)));
    ComboQuality.ItemIndex := OutputVideoQualityIndex(VideoQualityFromSettings(Settings));

    LabelAudio := TLabel.Create(Dialog);
    LabelAudio.Parent := Dialog;
    LabelAudio.Left := Margin;
    LabelAudio.Top := ComboEncoder.Top + ComboHeight + RowGap;
    LabelAudio.Caption := 'Audio';

    ComboAudio := TComboBox.Create(Dialog);
    ComboAudio.Parent := Dialog;
    ComboAudio.Left := Margin;
    ComboAudio.Top := LabelAudio.Top + LabelHeight + LabelGap;
    ComboAudio.Width := AudioWidth;
    ComboAudio.Height := ComboHeight;
    ComboAudio.Style := csDropDownList;
    for Index := 0 to OUTPUT_AUDIO_MODE_COUNT - 1 do
      ComboAudio.Items.Add(OutputAudioModeName(OutputAudioModeByIndex(Index)));
    ComboAudio.ItemIndex := OutputAudioModeIndex(AudioModeFromSettings(Settings));

    LabelSettings := TLabel.Create(Dialog);
    LabelSettings.Parent := Dialog;
    LabelSettings.Left := Margin;
    LabelSettings.Top := ComboAudio.Top + ComboHeight + RowGap;
    LabelSettings.Width := Dialog.ClientWidth - Margin * 2;
    LabelSettings.Height := SettingsHeight;
    LabelSettings.AutoSize := False;
    LabelSettings.Caption := '';

    ButtonOk := TButton.Create(Dialog);
    ButtonOk.Parent := Dialog;
    ButtonOk.Left := Dialog.ClientWidth - Margin - ButtonWidth * 2 - S(8);
    ButtonOk.Top := ButtonTop;
    ButtonOk.Width := ButtonWidth;
    ButtonOk.Height := ButtonHeight;
    ButtonOk.Caption := 'OK';
    ButtonOk.Default := True;
    ButtonOk.ModalResult := mrOk;

    ButtonCancel := TButton.Create(Dialog);
    ButtonCancel.Parent := Dialog;
    ButtonCancel.Left := Dialog.ClientWidth - Margin - ButtonWidth;
    ButtonCancel.Top := ButtonTop;
    ButtonCancel.Width := ButtonWidth;
    ButtonCancel.Height := ButtonHeight;
    ButtonCancel.Caption := 'Cancel';
    ButtonCancel.Cancel := True;
    ButtonCancel.ModalResult := mrCancel;

    DialogHandler := TOutputSettingsDialogHandler.Create(Dialog);
    DialogHandler.ComboEncoder := ComboEncoder;
    DialogHandler.ComboQuality := ComboQuality;
    DialogHandler.ComboAudio := ComboAudio;
    DialogHandler.LabelSettings := LabelSettings;
    ComboEncoder.OnChange := DialogHandler.SettingChange;
    ComboQuality.OnChange := DialogHandler.SettingChange;
    ComboAudio.OnChange := DialogHandler.SettingChange;
    DialogHandler.UpdateSettingsLabel;

    if Dialog.ShowModal <> mrOk then
      Exit;

    if ComboEncoder.ItemIndex >= 0 then
    begin
      EncoderInfo := OutputEncoderInfo(ComboEncoder.ItemIndex);
      ApplyEncoderDefaults(Settings, EncoderInfo.Kind);
    end;
    ApplyVideoQuality(Settings, OutputVideoQualityByIndex(ComboQuality.ItemIndex));
    ApplyAudioMode(Settings, OutputAudioModeByIndex(ComboAudio.ItemIndex));
    Result := True;
  finally
    Dialog.Free;
    Application.Handle := OldApplicationHandle;
  end;
end;

end.
