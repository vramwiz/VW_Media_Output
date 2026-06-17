unit FFmpegOutputVideoInput;

// AviUtl2へ要求する映像入力形式と、FFmpegへ渡すpixel format/stride情報を対応付ける。
// 通常出力はYUY2、透過保持の専用出力はPA64を選ぶため、形式ごとの差異をここへ集約する。

interface

uses
  Winapi.Windows;

type
  TOutputVideoInputKind = (
    ovikRgb24, // 互換用の24bit DIB入力
    ovikYuy2,  // 通常出力で使う高速なYUY2入力
    ovikPa64   // AlphaProRes出力で使うRGBA64 alpha入力
  );

const
  OUTPUT_VIDEO_INPUT_KIND = ovikYuy2; // 通常出力でAviUtl2から受け取る映像形式

// AviUtl2のfunc_get_videoへ渡すformat値を返す。
function OutputVideoInputAviUtlFormat(Kind: TOutputVideoInputKind): DWORD;
// sws_getContextへ渡すFFmpeg側の入力pixel formatを返す。
function OutputVideoInputFFmpegPixelFormat(Kind: TOutputVideoInputKind): Integer;
// perf logやcheck logへ出す入力形式名を返す。
function OutputVideoInputName(Kind: TOutputVideoInputKind): string;
// AviUtl2から返る1行分のbyte数を返す。
function OutputVideoInputStrideBytes(Kind: TOutputVideoInputKind; Width: Integer): Integer;
// sws_scaleへ渡す先頭行のoffsetを返す。
function OutputVideoInputFirstLineOffset(Kind: TOutputVideoInputKind;
  Width, Height: Integer): NativeUInt;
// sws_scaleへ渡す入力strideを返す。
function OutputVideoInputSwsStride(Kind: TOutputVideoInputKind; Width: Integer): Integer;

implementation

uses
  FFmpegApi;

const
  OUTPUT_VIDEO_FORMAT_RGB24 = 0; // AviUtl2へBI_RGB入力を要求するformat値
  OUTPUT_VIDEO_FORMAT_PA64  = Ord('P') or (Ord('A') shl 8) or
    (Ord('6') shl 16) or (Ord('4') shl 24); // AviUtl2へPA64入力を要求するformat値
  OUTPUT_VIDEO_FORMAT_YUY2  = Ord('Y') or (Ord('U') shl 8) or
    (Ord('Y') shl 16) or (Ord('2') shl 24); // AviUtl2へYUY2入力を要求するformat値

// DIB系の行幅を4byte境界へ揃える。
function Align4(Value: Integer): Integer;
begin
  Result := (Value + 3) and not 3;
end;

// AviUtl2のfunc_get_videoへ渡すformat値を返す。
function OutputVideoInputAviUtlFormat(Kind: TOutputVideoInputKind): DWORD;
begin
  case Kind of
    ovikRgb24:
      Result := OUTPUT_VIDEO_FORMAT_RGB24;
    ovikYuy2:
      Result := OUTPUT_VIDEO_FORMAT_YUY2;
    ovikPa64:
      Result := OUTPUT_VIDEO_FORMAT_PA64;
  else
    Result := OUTPUT_VIDEO_FORMAT_RGB24;
  end;
end;

// sws_getContextへ渡すFFmpeg側の入力pixel formatを返す。
function OutputVideoInputFFmpegPixelFormat(Kind: TOutputVideoInputKind): Integer;
begin
  case Kind of
    ovikRgb24:
      Result := AV_PIX_FMT_BGR24;
    ovikYuy2:
      Result := AV_PIX_FMT_YUYV422;
    ovikPa64:
      begin
        TFFmpegApi.EnsureLoaded;
        Result := TFFmpegApi.av_get_pix_fmt(PAnsiChar(AnsiString('rgba64le')));
      end;
  else
    Result := AV_PIX_FMT_BGR24;
  end;
end;

// perf logへ出す入力形式名を返す。
function OutputVideoInputName(Kind: TOutputVideoInputKind): string;
begin
  case Kind of
    ovikRgb24:
      Result := 'BI_RGB/RGB24';
    ovikYuy2:
      Result := 'YUY2';
    ovikPa64:
      Result := 'PA64/RGBA64 premultiplied alpha';
  else
    Result := 'BI_RGB/RGB24';
  end;
end;

// AviUtl2から返る1行分のbyte数を返す。
function OutputVideoInputStrideBytes(Kind: TOutputVideoInputKind; Width: Integer): Integer;
begin
  case Kind of
    ovikRgb24:
      Result := Align4(Width * 3);
    ovikYuy2:
      Result := Align4(Width * 2);
    ovikPa64:
      Result := Width * 8;
  else
    Result := Align4(Width * 3);
  end;
end;

// RGB24はbottom-up、YUY2はtop-downとしてsws_scaleの先頭行を決める。
function OutputVideoInputFirstLineOffset(Kind: TOutputVideoInputKind;
  Width, Height: Integer): NativeUInt;
begin
  case Kind of
    ovikRgb24:
      Result := NativeUInt((Height - 1) * OutputVideoInputStrideBytes(Kind, Width));
    ovikYuy2:
      Result := 0;
    ovikPa64:
      Result := 0;
  else
    Result := NativeUInt((Height - 1) * OutputVideoInputStrideBytes(Kind, Width));
  end;
end;

// RGB24は負stride、YUY2は正strideで上下反転を避ける。
function OutputVideoInputSwsStride(Kind: TOutputVideoInputKind; Width: Integer): Integer;
begin
  case Kind of
    ovikRgb24:
      Result := -OutputVideoInputStrideBytes(Kind, Width);
    ovikYuy2:
      Result := OutputVideoInputStrideBytes(Kind, Width);
    ovikPa64:
      Result := OutputVideoInputStrideBytes(Kind, Width);
  else
    Result := -OutputVideoInputStrideBytes(Kind, Width);
  end;
end;

end.
