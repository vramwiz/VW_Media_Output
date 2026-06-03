unit FFmpegOutputVideoInput;

interface

uses
  Winapi.Windows;

type
  TOutputVideoInputKind = (ovikRgb24, ovikYuy2);

const
  // AviUtl2から受け取る映像形式を切り替える。YUY2はRGB24より取得と変換が速かった。
  OUTPUT_VIDEO_INPUT_KIND = ovikYuy2;

function OutputVideoInputAviUtlFormat: DWORD;
function OutputVideoInputFFmpegPixelFormat: Integer;
function OutputVideoInputName: string;
function OutputVideoInputStrideBytes(Width: Integer): Integer;
function OutputVideoInputFirstLineOffset(Width, Height: Integer): NativeUInt;
function OutputVideoInputSwsStride(Width: Integer): Integer;

implementation

uses
  FFmpegApi;

const
  OUTPUT_VIDEO_FORMAT_RGB24 = 0; // BI_RGB
  OUTPUT_VIDEO_FORMAT_YUY2 = Ord('Y') or (Ord('U') shl 8) or
    (Ord('Y') shl 16) or (Ord('2') shl 24);

// DIB系の行幅を4byte境界へ揃える。
function Align4(Value: Integer): Integer;
begin
  Result := (Value + 3) and not 3;
end;

// AviUtl2のfunc_get_videoへ渡すformat値を返す。
function OutputVideoInputAviUtlFormat: DWORD;
begin
  case OUTPUT_VIDEO_INPUT_KIND of
    ovikRgb24:
      Result := OUTPUT_VIDEO_FORMAT_RGB24;
    ovikYuy2:
      Result := OUTPUT_VIDEO_FORMAT_YUY2;
  else
    Result := OUTPUT_VIDEO_FORMAT_RGB24;
  end;
end;

// sws_getContextへ渡すFFmpeg側の入力pixel formatを返す。
function OutputVideoInputFFmpegPixelFormat: Integer;
begin
  case OUTPUT_VIDEO_INPUT_KIND of
    ovikRgb24:
      Result := AV_PIX_FMT_BGR24;
    ovikYuy2:
      Result := AV_PIX_FMT_YUYV422;
  else
    Result := AV_PIX_FMT_BGR24;
  end;
end;

// perf logへ出す入力形式名を返す。
function OutputVideoInputName: string;
begin
  case OUTPUT_VIDEO_INPUT_KIND of
    ovikRgb24:
      Result := 'BI_RGB/RGB24';
    ovikYuy2:
      Result := 'YUY2';
  else
    Result := 'BI_RGB/RGB24';
  end;
end;

// AviUtl2から返る1行分のbyte数を返す。
function OutputVideoInputStrideBytes(Width: Integer): Integer;
begin
  case OUTPUT_VIDEO_INPUT_KIND of
    ovikRgb24:
      Result := Align4(Width * 3);
    ovikYuy2:
      Result := Align4(Width * 2);
  else
    Result := Align4(Width * 3);
  end;
end;

// RGB24はbottom-up、YUY2はtop-downとしてsws_scaleの先頭行を決める。
function OutputVideoInputFirstLineOffset(Width, Height: Integer): NativeUInt;
begin
  case OUTPUT_VIDEO_INPUT_KIND of
    ovikRgb24:
      Result := NativeUInt((Height - 1) * OutputVideoInputStrideBytes(Width));
    ovikYuy2:
      Result := 0;
  else
    Result := NativeUInt((Height - 1) * OutputVideoInputStrideBytes(Width));
  end;
end;

// RGB24は負stride、YUY2は正strideで上下反転を避ける。
function OutputVideoInputSwsStride(Width: Integer): Integer;
begin
  case OUTPUT_VIDEO_INPUT_KIND of
    ovikRgb24:
      Result := -OutputVideoInputStrideBytes(Width);
    ovikYuy2:
      Result := OutputVideoInputStrideBytes(Width);
  else
    Result := -OutputVideoInputStrideBytes(Width);
  end;
end;

end.
