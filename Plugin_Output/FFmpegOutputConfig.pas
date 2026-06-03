unit FFmpegOutputConfig;

interface

type
  TOutputEncoderKind = (oekCpuX264, oekIntelQsv);
  TOutputPixelFormatKind = (opfYuv420p, opfNv12);
  TOutputVideoQualityKind = (ovqHigh, ovqStandard, ovqFast);
  TOutputAudioModeKind = (oamAac576, oamAac384, oamAac256, oamAac192, oamAac128, oamNone);

  TOutputEncoderInfo = record
    Kind: TOutputEncoderKind;
    DisplayName: string;
    EncoderName: AnsiString;
    PixelFormat: TOutputPixelFormatKind;
    PixelFormatName: string;
    IsGpu: Boolean;
    DefaultBitRate: Int64;
    DefaultPreset: AnsiString;
    DefaultQuality: Integer;
  end;

  TOutputVideoSettings = record
    EncoderKind: TOutputEncoderKind;
    CodecName: string;
    EncoderName: AnsiString;
    PixelFormat: TOutputPixelFormatKind;
    PixelFormatName: string;
    BitRate: Int64;
    Preset: AnsiString;
    Quality: Integer;
  end;

  TOutputAudioSettings = record
    Enabled: Boolean;
    CodecName: string;
    EncoderName: AnsiString;
    BitRate: Int64;
    SampleRate: Integer;
    Channels: Integer;
  end;

  TOutputTestSettings = record
    SaveFileName: string;
    PresetName: string;
    Container: string;
    Video: TOutputVideoSettings;
    Audio: TOutputAudioSettings;
  end;

const
  OUTPUT_ENCODER_COUNT = 2;
  OUTPUT_VIDEO_QUALITY_COUNT = 3;
  OUTPUT_AUDIO_MODE_COUNT = 6;

function OutputEncoderInfo(Index: Integer): TOutputEncoderInfo;
function OutputEncoderInfoByKind(Kind: TOutputEncoderKind): TOutputEncoderInfo;
function OutputEncoderIndexByKind(Kind: TOutputEncoderKind): Integer;
function OutputVideoQualityName(Quality: TOutputVideoQualityKind): string;
function OutputVideoQualityIndex(Quality: TOutputVideoQualityKind): Integer;
function OutputVideoQualityByIndex(Index: Integer): TOutputVideoQualityKind;
function OutputAudioModeName(Mode: TOutputAudioModeKind): string;
function OutputAudioModeIndex(Mode: TOutputAudioModeKind): Integer;
function OutputAudioModeByIndex(Index: Integer): TOutputAudioModeKind;
function OutputPixelFormatFFmpegValue(Format: TOutputPixelFormatKind): Integer;
function OutputPixelFormatDescription(Format: TOutputPixelFormatKind): string;
procedure ApplyEncoderDefaults(var Settings: TOutputTestSettings; Kind: TOutputEncoderKind);
procedure ApplyVideoQuality(var Settings: TOutputTestSettings; Quality: TOutputVideoQualityKind);
procedure ApplyAudioMode(var Settings: TOutputTestSettings; Mode: TOutputAudioModeKind);
procedure InitDefaultOutputSettings(var Settings: TOutputTestSettings);

implementation

uses
  System.SysUtils, FFmpegApi;

const
  AV_PIX_FMT_NV12 = 23;

function OutputEncoderInfo(Index: Integer): TOutputEncoderInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  case Index of
    0:
      begin
        Result.Kind := oekCpuX264;
        Result.DisplayName := 'CPU / H.264 libx264';
        Result.EncoderName := 'libx264';
        Result.PixelFormat := opfYuv420p;
        Result.PixelFormatName := 'yuv420p';
        Result.IsGpu := False;
        Result.DefaultBitRate := 4000000;
        Result.DefaultPreset := 'veryfast';
        Result.DefaultQuality := 23;
      end;
    1:
      begin
        Result.Kind := oekIntelQsv;
        Result.DisplayName := 'GPU / H.264 Intel QSV';
        Result.EncoderName := 'h264_qsv';
        Result.PixelFormat := opfNv12;
        Result.PixelFormatName := 'nv12';
        Result.IsGpu := True;
        Result.DefaultBitRate := 4000000;
        Result.DefaultPreset := 'veryfast';
        Result.DefaultQuality := 23;
      end;
  else
    raise EArgumentOutOfRangeException.Create('Output encoder index is out of range.');
  end;
end;

function OutputEncoderInfoByKind(Kind: TOutputEncoderKind): TOutputEncoderInfo;
var
  Index: Integer;
begin
  for Index := 0 to OUTPUT_ENCODER_COUNT - 1 do
  begin
    Result := OutputEncoderInfo(Index);
    if Result.Kind = Kind then
      Exit;
  end;
  Result := OutputEncoderInfo(0);
end;

function OutputEncoderIndexByKind(Kind: TOutputEncoderKind): Integer;
var
  Index: Integer;
  Info: TOutputEncoderInfo;
begin
  for Index := 0 to OUTPUT_ENCODER_COUNT - 1 do
  begin
    Info := OutputEncoderInfo(Index);
    if Info.Kind = Kind then
      Exit(Index);
  end;
  Result := 0;
end;

function OutputVideoQualityName(Quality: TOutputVideoQualityKind): string;
begin
  case Quality of
    ovqHigh:
      Result := 'High quality';
    ovqStandard:
      Result := 'Standard';
    ovqFast:
      Result := 'Fast';
  else
    Result := 'Standard';
  end;
end;

function OutputVideoQualityIndex(Quality: TOutputVideoQualityKind): Integer;
begin
  Result := Ord(Quality);
end;

function OutputVideoQualityByIndex(Index: Integer): TOutputVideoQualityKind;
begin
  case Index of
    0:
      Result := ovqHigh;
    1:
      Result := ovqStandard;
    2:
      Result := ovqFast;
  else
    Result := ovqStandard;
  end;
end;

function OutputAudioModeName(Mode: TOutputAudioModeKind): string;
begin
  case Mode of
    oamAac576:
      Result := 'AAC 576 kbps';
    oamAac384:
      Result := 'AAC 384 kbps';
    oamAac256:
      Result := 'AAC 256 kbps';
    oamAac192:
      Result := 'AAC 192 kbps';
    oamAac128:
      Result := 'AAC 128 kbps';
    oamNone:
      Result := 'None';
  else
    Result := 'AAC 192 kbps';
  end;
end;

function OutputAudioModeIndex(Mode: TOutputAudioModeKind): Integer;
begin
  Result := Ord(Mode);
end;

function OutputAudioModeByIndex(Index: Integer): TOutputAudioModeKind;
begin
  case Index of
    0:
      Result := oamAac576;
    1:
      Result := oamAac384;
    2:
      Result := oamAac256;
    3:
      Result := oamAac192;
    4:
      Result := oamAac128;
    5:
      Result := oamNone;
  else
    Result := oamAac192;
  end;
end;

function OutputPixelFormatFFmpegValue(Format: TOutputPixelFormatKind): Integer;
begin
  case Format of
    opfYuv420p:
      Result := AV_PIX_FMT_YUV420P;
    opfNv12:
      Result := AV_PIX_FMT_NV12;
  else
    Result := AV_PIX_FMT_YUV420P;
  end;
end;

function OutputPixelFormatDescription(Format: TOutputPixelFormatKind): string;
begin
  case Format of
    opfYuv420p:
      Result := 'source input -> yuv420p';
    opfNv12:
      Result := 'source input -> nv12';
  else
    Result := 'source input';
  end;
end;

procedure ApplyEncoderDefaults(var Settings: TOutputTestSettings; Kind: TOutputEncoderKind);
var
  Info: TOutputEncoderInfo;
begin
  Info := OutputEncoderInfoByKind(Kind);
  Settings.Container := 'MP4';
  Settings.Video.EncoderKind := Info.Kind;
  Settings.Video.CodecName := Info.DisplayName;
  Settings.Video.EncoderName := Info.EncoderName;
  Settings.Video.PixelFormat := Info.PixelFormat;
  Settings.Video.PixelFormatName := Info.PixelFormatName;
  Settings.Video.BitRate := Info.DefaultBitRate;
  Settings.Video.Preset := Info.DefaultPreset;
  Settings.Video.Quality := Info.DefaultQuality;
  Settings.Audio.Enabled := True;
  Settings.Audio.CodecName := 'AAC';
  Settings.Audio.EncoderName := 'aac';
  Settings.Audio.BitRate := 192000;
  Settings.Audio.SampleRate := AUDIO_OUTPUT_SAMPLE_RATE;
  Settings.Audio.Channels := AUDIO_OUTPUT_CHANNELS;
end;

procedure ApplyVideoQuality(var Settings: TOutputTestSettings; Quality: TOutputVideoQualityKind);
begin
  case Quality of
    ovqHigh:
      begin
        Settings.Video.BitRate := 8000000;
        Settings.Video.Quality := 18;
        Settings.Video.Preset := 'medium';
      end;
    ovqStandard:
      begin
        Settings.Video.BitRate := 4000000;
        Settings.Video.Quality := 23;
        Settings.Video.Preset := 'veryfast';
      end;
    ovqFast:
      begin
        Settings.Video.BitRate := 2500000;
        Settings.Video.Quality := 28;
        Settings.Video.Preset := 'veryfast';
      end;
  end;
end;

procedure ApplyAudioMode(var Settings: TOutputTestSettings; Mode: TOutputAudioModeKind);
begin
  Settings.Audio.SampleRate := AUDIO_OUTPUT_SAMPLE_RATE;
  Settings.Audio.Channels := AUDIO_OUTPUT_CHANNELS;
  case Mode of
    oamAac576:
      begin
        Settings.Audio.Enabled := True;
        Settings.Audio.CodecName := 'AAC';
        Settings.Audio.EncoderName := 'aac';
        Settings.Audio.BitRate := 576000;
      end;
    oamAac384:
      begin
        Settings.Audio.Enabled := True;
        Settings.Audio.CodecName := 'AAC';
        Settings.Audio.EncoderName := 'aac';
        Settings.Audio.BitRate := 384000;
      end;
    oamAac256:
      begin
        Settings.Audio.Enabled := True;
        Settings.Audio.CodecName := 'AAC';
        Settings.Audio.EncoderName := 'aac';
        Settings.Audio.BitRate := 256000;
      end;
    oamAac192:
      begin
        Settings.Audio.Enabled := True;
        Settings.Audio.CodecName := 'AAC';
        Settings.Audio.EncoderName := 'aac';
        Settings.Audio.BitRate := 192000;
      end;
    oamAac128:
      begin
        Settings.Audio.Enabled := True;
        Settings.Audio.CodecName := 'AAC';
        Settings.Audio.EncoderName := 'aac';
        Settings.Audio.BitRate := 128000;
      end;
    oamNone:
      begin
        Settings.Audio.Enabled := False;
        Settings.Audio.CodecName := 'None';
        Settings.Audio.EncoderName := '';
        Settings.Audio.BitRate := 0;
      end;
  end;
end;

procedure InitDefaultOutputSettings(var Settings: TOutputTestSettings);
begin
  Settings.SaveFileName := '';
  Settings.PresetName := '';
  Settings.Container := '';
  Settings.Video.CodecName := '';
  Settings.Video.EncoderName := '';
  Settings.Video.PixelFormatName := '';
  Settings.Video.BitRate := 0;
  Settings.Video.Preset := '';
  Settings.Video.Quality := 0;
  Settings.Audio.Enabled := False;
  Settings.Audio.CodecName := '';
  Settings.Audio.EncoderName := '';
  Settings.Audio.BitRate := 0;
  Settings.Audio.SampleRate := 0;
  Settings.Audio.Channels := 0;
  ApplyEncoderDefaults(Settings, oekIntelQsv);
  ApplyVideoQuality(Settings, ovqStandard);
  ApplyAudioMode(Settings, oamAac192);
end;

end.
