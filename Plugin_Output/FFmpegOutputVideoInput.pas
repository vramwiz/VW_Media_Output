unit FFmpegOutputVideoInput;

interface

uses
  Winapi.Windows;

type
  TOutputVideoInputKind = (ovikRgb24, ovikYuy2);

const
  // Switch this to compare AviUtl2 frame retrieval and sws_scale cost.
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

function Align4(Value: Integer): Integer;
begin
  Result := (Value + 3) and not 3;
end;

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
