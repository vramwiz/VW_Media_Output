unit FFmpegOutputConfig;

// 出力プラグインのUI/INI/encoderへ渡す設定値を定義し、選択肢を実設定へ展開する。
// 通常H.264系と透過保持用ProRes 4444系の設定差分もここで管理する。

interface

type
  TOutputEncodeModeKind = (oemNormal, oemAlphaProRes); // 通常出力と透過保持専用出力の種別
  TOutputEncoderKind = (oekCpuX264, oekIntelQsv, oekNvidiaNvenc, oekAmdAmf); // 通常出力で選べるencoder種別
  TOutputPixelFormatKind = (opfYuv420p, opfNv12, opfYuva444p10le); // FFmpeg encoderへ渡すpixel format種別
  TOutputVideoQualityKind = (ovqHigh, ovqStandard, ovqFast); // UIで選ぶ映像品質preset
  TOutputAudioModeKind = (oamAac576, oamAac384, oamAac256, oamAac192, oamAac128, oamNone); // UIで選ぶ音声出力preset

  TOutputEncoderInfo = record
    Kind            : TOutputEncoderKind;      // UI/INIで扱うencoder種別
    DisplayName     : string;                  // UI表示名
    EncoderName     : AnsiString;              // FFmpeg encoder名
    PixelFormat     : TOutputPixelFormatKind;  // encoder入力pixel format種別
    PixelFormatName : string;                  // log/UI表示用pixel format名
    IsGpu           : Boolean;                 // GPU encoderかどうか
    DefaultBitRate  : Int64;                   // encoder既定bitrate
    DefaultPreset   : AnsiString;              // encoder既定preset
    DefaultQuality  : Integer;                 // x264/qsvへ渡す品質目安
  end;

  TOutputVideoSettings = record
    EncoderKind     : TOutputEncoderKind;     // 選択されたencoder種別
    CodecName       : string;                 // UI/log表示用codec名
    EncoderName     : AnsiString;             // FFmpeg encoder名
    PixelFormat     : TOutputPixelFormatKind; // encoderへ渡すpixel format種別
    PixelFormatName : string;                 // UI/log表示用pixel format名
    BitRate         : Int64;                  // video bitrate
    Preset          : AnsiString;             // encoder preset
    Quality         : Integer;                // crf/global_quality相当の目安
  end;

  TOutputAudioSettings = record
    Enabled     : Boolean;    // audioを出力するか
    CodecName   : string;     // UI/log表示用codec名
    EncoderName : AnsiString; // FFmpeg encoder名
    BitRate     : Int64;      // audio bitrate
    SampleRate  : Integer;    // 出力sample rate
    Channels    : Integer;    // 出力channel数
  end;

  TOutputTestSettings = record
    SaveFileName             : string;                // AviUtl2から渡された保存先
    PresetName               : string;                // 将来用のpreset名
    EncodeMode               : TOutputEncodeModeKind; // 通常出力か透過保持専用出力か
    Container                : string;                // container表示名
    Video                    : TOutputVideoSettings;  // video encoder設定
    Audio                    : TOutputAudioSettings;  // audio encoder設定
    RotateOutputDegrees      : Integer;               // 通常MP4へ付与する回転metadata角度(0/90/180/270)
    ShowCheckLogAfterEncode  : Boolean;               // 確認ポイントがある場合に出力後check logを表示するか
  end;

const
  OUTPUT_ENCODE_MODE_COUNT   = 2; // UIの出力モード一覧に出す項目数
  OUTPUT_ENCODER_COUNT       = 4; // UIの通常encoder一覧に出す項目数
  OUTPUT_VIDEO_QUALITY_COUNT = 3; // UIの映像品質一覧に出す項目数
  OUTPUT_AUDIO_MODE_COUNT    = 6; // UIの音声mode一覧に出す項目数

// UIへ表示する出力モード名を返す。
function OutputEncodeModeName(Mode: TOutputEncodeModeKind): string;
// 出力モードenumをUI indexへ変換する。
function OutputEncodeModeIndex(Mode: TOutputEncodeModeKind): Integer;
// UI indexを出力モードenumへ変換する。
function OutputEncodeModeByIndex(Index: Integer): TOutputEncodeModeKind;
// UIのencoder一覧に出す固定情報を返す。
function OutputEncoderInfo(Index: Integer): TOutputEncoderInfo;
// encoder種別から固定情報を返す。
function OutputEncoderInfoByKind(Kind: TOutputEncoderKind): TOutputEncoderInfo;
// encoder種別からUI一覧のindexを返す。
function OutputEncoderIndexByKind(Kind: TOutputEncoderKind): Integer;
// UIへ表示するvideo quality名を返す。
function OutputVideoQualityName(Quality: TOutputVideoQualityKind): string;
// video quality enumをUI indexへ変換する。
function OutputVideoQualityIndex(Quality: TOutputVideoQualityKind): Integer;
// UI indexをvideo quality enumへ変換する。
function OutputVideoQualityByIndex(Index: Integer): TOutputVideoQualityKind;
// UIへ表示するaudio mode名を返す。
function OutputAudioModeName(Mode: TOutputAudioModeKind): string;
// audio mode enumをUI indexへ変換する。
function OutputAudioModeIndex(Mode: TOutputAudioModeKind): Integer;
// UI indexをaudio mode enumへ変換する。
function OutputAudioModeByIndex(Index: Integer): TOutputAudioModeKind;
// FFmpegへ渡すpixel format値へ変換する。
function OutputPixelFormatFFmpegValue(Format: TOutputPixelFormatKind): Integer;
// UI/logへ出すpixel format説明を返す。
function OutputPixelFormatDescription(Format: TOutputPixelFormatKind): string;
// encoder種別の既定値をSettingsへ展開する。
procedure ApplyEncoderDefaults(var Settings: TOutputTestSettings; Kind: TOutputEncoderKind);
// quality選択をbitrate/preset/qualityへ展開する。
procedure ApplyVideoQuality(var Settings: TOutputTestSettings; Quality: TOutputVideoQualityKind);
// audio選択をAAC設定または無効設定へ展開する。
procedure ApplyAudioMode(var Settings: TOutputTestSettings; Mode: TOutputAudioModeKind);
// 出力モードをSettingsへ展開する。
procedure ApplyEncodeMode(var Settings: TOutputTestSettings; Mode: TOutputEncodeModeKind);
// 回転metadata角度を0/90/180/270へ正規化する。
function NormalizeOutputRotationDegrees(Degrees: Integer): Integer;
// 回転metadata角度をUI/log向け文字列へ変換する。
function OutputRotationDegreesText(Degrees: Integer): string;
// プラグインの既定設定を作る。
procedure InitDefaultOutputSettings(var Settings: TOutputTestSettings);

implementation

uses
  System.SysUtils, FFmpegApi;

const
  AV_PIX_FMT_NV12 = 23; // 現在のFFmpegヘッダーで参照するNV12のpixel format値

function OutputEncodeModeName(Mode: TOutputEncodeModeKind): string;
begin
  case Mode of
    oemNormal:
      Result := 'Normal MP4';
    oemAlphaProRes:
      Result := 'Alpha MOV / ProRes 4444';
  else
    Result := 'Normal MP4';
  end;
end;

function OutputEncodeModeIndex(Mode: TOutputEncodeModeKind): Integer;
begin
  Result := Ord(Mode);
end;

function OutputEncodeModeByIndex(Index: Integer): TOutputEncodeModeKind;
begin
  case Index of
    1:
      Result := oemAlphaProRes;
  else
    Result := oemNormal;
  end;
end;

// UIのencoder一覧に出す固定情報を返す。
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
    2:
      begin
        Result.Kind := oekNvidiaNvenc;
        Result.DisplayName := 'GPU / H.264 NVIDIA NVENC';
        Result.EncoderName := 'h264_nvenc';
        Result.PixelFormat := opfNv12;
        Result.PixelFormatName := 'nv12';
        Result.IsGpu := True;
        Result.DefaultBitRate := 4000000;
        Result.DefaultPreset := 'p4';
        Result.DefaultQuality := 23;
      end;
    3:
      begin
        Result.Kind := oekAmdAmf;
        Result.DisplayName := 'GPU / H.264 AMD AMF';
        Result.EncoderName := 'h264_amf';
        Result.PixelFormat := opfNv12;
        Result.PixelFormatName := 'nv12';
        Result.IsGpu := True;
        Result.DefaultBitRate := 4000000;
        Result.DefaultPreset := 'balanced';
        Result.DefaultQuality := 23;
      end;
  else
    raise EArgumentOutOfRangeException.Create('Output encoder index is out of range.');
  end;
end;

// encoder種別から固定情報を返す。
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

// encoder種別からUI一覧のindexを返す。
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

// UIへ表示するvideo quality名を返す。
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

// video quality enumをUI indexへ変換する。
function OutputVideoQualityIndex(Quality: TOutputVideoQualityKind): Integer;
begin
  Result := Ord(Quality);
end;

// UI indexをvideo quality enumへ変換する。
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

// UIへ表示するaudio mode名を返す。
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

// audio mode enumをUI indexへ変換する。
function OutputAudioModeIndex(Mode: TOutputAudioModeKind): Integer;
begin
  Result := Ord(Mode);
end;

// UI indexをaudio mode enumへ変換する。
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

// FFmpegへ渡すpixel format値へ変換する。
function OutputPixelFormatFFmpegValue(Format: TOutputPixelFormatKind): Integer;
begin
  case Format of
    opfYuv420p:
      Result := AV_PIX_FMT_YUV420P;
    opfNv12:
      Result := AV_PIX_FMT_NV12;
    opfYuva444p10le:
      begin
        TFFmpegApi.EnsureLoaded;
        Result := TFFmpegApi.av_get_pix_fmt(PAnsiChar(AnsiString('yuva444p10le')));
      end;
  else
    Result := AV_PIX_FMT_YUV420P;
  end;
end;

// UI/logへ出すpixel format説明を返す。
function OutputPixelFormatDescription(Format: TOutputPixelFormatKind): string;
begin
  case Format of
    opfYuv420p:
      Result := 'source input -> yuv420p';
    opfNv12:
      Result := 'source input -> nv12';
    opfYuva444p10le:
      Result := 'PA64 alpha input -> yuva444p10le';
  else
    Result := 'source input';
  end;
end;

// encoder種別の既定値をSettingsへ展開する。
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

// quality選択をbitrate/preset/qualityへ展開する。
procedure ApplyVideoQuality(var Settings: TOutputTestSettings; Quality: TOutputVideoQualityKind);
begin
  case Quality of
    ovqHigh:
      begin
        Settings.Video.BitRate := 8000000;
        Settings.Video.Quality := 18;
        case Settings.Video.EncoderKind of
          oekNvidiaNvenc:
            Settings.Video.Preset := 'p5';
          oekAmdAmf:
            Settings.Video.Preset := 'quality';
        else
          Settings.Video.Preset := 'medium';
        end;
      end;
    ovqStandard:
      begin
        Settings.Video.BitRate := 4000000;
        Settings.Video.Quality := 23;
        case Settings.Video.EncoderKind of
          oekNvidiaNvenc:
            Settings.Video.Preset := 'p4';
          oekAmdAmf:
            Settings.Video.Preset := 'balanced';
        else
          Settings.Video.Preset := 'veryfast';
        end;
      end;
    ovqFast:
      begin
        Settings.Video.BitRate := 2500000;
        Settings.Video.Quality := 28;
        case Settings.Video.EncoderKind of
          oekNvidiaNvenc:
            Settings.Video.Preset := 'p3';
          oekAmdAmf:
            Settings.Video.Preset := 'speed';
        else
          Settings.Video.Preset := 'veryfast';
        end;
      end;
  end;
end;

// audio選択をAAC設定または無効設定へ展開する。
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

// 出力モードをSettingsへ展開する。透過保持モードは通常H.264経路とは別の専用設定にする。
procedure ApplyEncodeMode(var Settings: TOutputTestSettings; Mode: TOutputEncodeModeKind);
begin
  Settings.EncodeMode := Mode;
  case Mode of
    oemAlphaProRes:
      begin
        Settings.Container := 'MOV';
        Settings.Video.CodecName := 'ProRes 4444 (alpha)';
        Settings.Video.EncoderName := 'prores_ks';
        Settings.Video.PixelFormat := opfYuva444p10le;
        Settings.Video.PixelFormatName := 'yuva444p10le';
        Settings.Video.BitRate := 0;
        Settings.Video.Preset := '';
        Settings.Video.Quality := 0;
      end;
  else
    if Settings.Container = '' then
      Settings.Container := 'MP4';
  end;
end;

function NormalizeOutputRotationDegrees(Degrees: Integer): Integer;
begin
  Result := Degrees mod 360;
  if Result < 0 then
    Inc(Result, 360);
  case Result of
    90, 180, 270:
      ;
  else
    Result := 0;
  end;
end;

function OutputRotationDegreesText(Degrees: Integer): string;
begin
  case NormalizeOutputRotationDegrees(Degrees) of
    90:
      Result := '90 deg clockwise';
    180:
      Result := '180 deg';
    270:
      Result := '270 deg clockwise';
  else
    Result := 'None';
  end;
end;

// プラグインの既定設定を作る。INI読み込み前の基準値。
procedure InitDefaultOutputSettings(var Settings: TOutputTestSettings);
begin
  Settings.SaveFileName := '';
  Settings.PresetName := '';
  Settings.EncodeMode := oemNormal;
  Settings.Container := '';
  Settings.RotateOutputDegrees := 0;
  Settings.ShowCheckLogAfterEncode := False;
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
  ApplyEncodeMode(Settings, oemNormal);
end;

end.
