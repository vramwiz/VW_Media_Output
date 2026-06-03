unit FFmpegOutputSettingsDialog;

interface

uses
  Winapi.Windows, FFmpegOutputConfig;

function ExecuteOutputSettingsDialog(OwnerWindow: HWND;
  var Settings: TOutputTestSettings): Boolean;

implementation

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TOutputSettingsDialogHandler = class(TComponent)
  public
    ComboEncoder: TComboBox;
    ComboQuality: TComboBox;
    ComboAudio: TComboBox;
    LabelSettings: TLabel;
    procedure SettingChange(Sender: TObject);
    procedure UpdateSettingsLabel;
  end;

procedure TOutputSettingsDialogHandler.SettingChange(Sender: TObject);
begin
  UpdateSettingsLabel;
end;

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
    Dialog.ClientWidth := 520;
    Dialog.ClientHeight := 220;

    LabelEncoder := TLabel.Create(Dialog);
    LabelEncoder.Parent := Dialog;
    LabelEncoder.Left := 16;
    LabelEncoder.Top := 16;
    LabelEncoder.Caption := 'Encoder';

    ComboEncoder := TComboBox.Create(Dialog);
    ComboEncoder.Parent := Dialog;
    ComboEncoder.Left := 16;
    ComboEncoder.Top := 36;
    ComboEncoder.Width := 240;
    ComboEncoder.Style := csDropDownList;
    for EncoderIndex := 0 to OUTPUT_ENCODER_COUNT - 1 do
    begin
      EncoderInfo := OutputEncoderInfo(EncoderIndex);
      ComboEncoder.Items.Add(EncoderInfo.DisplayName);
    end;
    ComboEncoder.ItemIndex := OutputEncoderIndexByKind(Settings.Video.EncoderKind);

    LabelQuality := TLabel.Create(Dialog);
    LabelQuality.Parent := Dialog;
    LabelQuality.Left := 272;
    LabelQuality.Top := 16;
    LabelQuality.Caption := 'Video quality';

    ComboQuality := TComboBox.Create(Dialog);
    ComboQuality.Parent := Dialog;
    ComboQuality.Left := 272;
    ComboQuality.Top := 36;
    ComboQuality.Width := 160;
    ComboQuality.Style := csDropDownList;
    for Index := 0 to OUTPUT_VIDEO_QUALITY_COUNT - 1 do
      ComboQuality.Items.Add(OutputVideoQualityName(OutputVideoQualityByIndex(Index)));
    ComboQuality.ItemIndex := OutputVideoQualityIndex(VideoQualityFromSettings(Settings));

    LabelAudio := TLabel.Create(Dialog);
    LabelAudio.Parent := Dialog;
    LabelAudio.Left := 16;
    LabelAudio.Top := 68;
    LabelAudio.Caption := 'Audio';

    ComboAudio := TComboBox.Create(Dialog);
    ComboAudio.Parent := Dialog;
    ComboAudio.Left := 16;
    ComboAudio.Top := 88;
    ComboAudio.Width := 160;
    ComboAudio.Style := csDropDownList;
    for Index := 0 to OUTPUT_AUDIO_MODE_COUNT - 1 do
      ComboAudio.Items.Add(OutputAudioModeName(OutputAudioModeByIndex(Index)));
    ComboAudio.ItemIndex := OutputAudioModeIndex(AudioModeFromSettings(Settings));

    LabelSettings := TLabel.Create(Dialog);
    LabelSettings.Parent := Dialog;
    LabelSettings.Left := 16;
    LabelSettings.Top := 120;
    LabelSettings.Width := 488;
    LabelSettings.Height := 48;
    LabelSettings.AutoSize := False;
    LabelSettings.Caption := '';

    ButtonOk := TButton.Create(Dialog);
    ButtonOk.Parent := Dialog;
    ButtonOk.Left := 344;
    ButtonOk.Top := 176;
    ButtonOk.Width := 75;
    ButtonOk.Height := 25;
    ButtonOk.Caption := 'OK';
    ButtonOk.Default := True;
    ButtonOk.ModalResult := mrOk;

    ButtonCancel := TButton.Create(Dialog);
    ButtonCancel.Parent := Dialog;
    ButtonCancel.Left := 429;
    ButtonCancel.Top := 176;
    ButtonCancel.Width := 75;
    ButtonCancel.Height := 25;
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
