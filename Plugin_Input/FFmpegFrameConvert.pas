unit FFmpegFrameConvert;

// FFmpegの映像フレームをAviUtl2向けの生バッファや確認用Bitmapへ変換する補助ユニット。
// sws_scaleによるピクセル形式変換と上下方向の配置調整を担当する。

interface

uses
  Vcl.Graphics, FFmpegApi;

// AVFrameを32bit BGRxの呼び出し元バッファへ直接変換する。
procedure CopyFrameToBgrx32Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
// AVFrameを確認用のBGR TBitmapへ変換する。
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);

implementation

uses
  System.SysUtils;

// AVFrameを32bit BGRxの呼び出し元バッファへ直接変換する。
procedure CopyFrameToBgrx32Buffer(
  Frame: PAVFrame;
  Buffer: Pointer;
  BufferStride: Integer;
  var ScaleContext: Pointer;
  var CachedSrcWidth: Integer;
  var CachedSrcHeight: Integer;
  var CachedSrcFormat: Integer;
  var CachedDstFormat: Integer
);
var
  DstData: array[0..3] of PByte; // sws_scaleへ渡す出力プレーンポインタ
  DstLinesize: array[0..3] of Integer; // sws_scaleへ渡す出力ラインサイズ
  DstFormat: Integer; // AviUtl2へ返す出力ピクセル形式
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');
  if Buffer = nil then
    raise Exception.Create('Destination buffer is nil.');
  if BufferStride <= 0 then
    BufferStride := Frame.width * 4;
  DstFormat := AV_PIX_FMT_BGRA;

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := PByte(NativeUInt(Buffer) + NativeUInt((Frame.height - 1) * BufferStride));
  DstLinesize[0] := -BufferStride;

  if Assigned(ScaleContext) and
     ((CachedSrcWidth <> Frame.width) or
      (CachedSrcHeight <> Frame.height) or
      (CachedSrcFormat <> Frame.format) or
      (CachedDstFormat <> DstFormat)) then
  begin
    TFFmpegApi.sws_freeContext(PSwsContext(ScaleContext));
    ScaleContext := nil;
  end;

  if not Assigned(ScaleContext) then
  begin
    ScaleContext := TFFmpegApi.sws_getContext(Frame.width, Frame.height, Frame.format,
      Frame.width, Frame.height, DstFormat, SWS_BILINEAR, nil, nil, nil);
    CachedSrcWidth := Frame.width;
    CachedSrcHeight := Frame.height;
    CachedSrcFormat := Frame.format;
    CachedDstFormat := DstFormat;
  end;

  if not Assigned(ScaleContext) then
    raise Exception.Create('sws_getContext failed.');

  if TFFmpegApi.sws_scale(PSwsContext(ScaleContext), @Frame.data[0], @Frame.linesize[0], 0,
    Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
    raise Exception.Create('sws_scale failed.');
end;

// AVFrameを確認用のBGR TBitmapへ変換する。
procedure CopyFrameToBitmap(Frame: PAVFrame; Bitmap: TBitmap);
var
  ScaleContext: PSwsContext; // この変換だけで使うswsコンテキスト
  DstData: array[0..3] of PByte; // sws_scaleへ渡すBitmap側の出力ポインタ
  DstLinesize: array[0..3] of Integer; // Bitmap側の1行あたりバイト数
  Stride: NativeInt; // BitmapのScanLine間隔
begin
  if (Frame = nil) or (Frame.width <= 0) or (Frame.height <= 0) then
    raise Exception.Create('Decoded frame has invalid size.');

  Bitmap.PixelFormat := pf24bit;
  Bitmap.SetSize(Frame.width, Frame.height);

  FillChar(DstData, SizeOf(DstData), 0);
  FillChar(DstLinesize, SizeOf(DstLinesize), 0);

  DstData[0] := Bitmap.ScanLine[0];
  if Frame.height > 1 then
    Stride := NativeInt(Bitmap.ScanLine[1]) - NativeInt(Bitmap.ScanLine[0])
  else
    Stride := ((Frame.width * 3 + 3) div 4) * 4;
  DstLinesize[0] := Integer(Stride);

  ScaleContext := TFFmpegApi.sws_getContext(Frame.width, Frame.height, Frame.format,
    Frame.width, Frame.height, AV_PIX_FMT_BGR24, SWS_BILINEAR, nil, nil, nil);
  if not Assigned(ScaleContext) then
    raise Exception.Create('sws_getContext failed.');
  try
    if TFFmpegApi.sws_scale(ScaleContext, @Frame.data[0], @Frame.linesize[0], 0,
      Frame.height, @DstData[0], @DstLinesize[0]) <= 0 then
      raise Exception.Create('sws_scale failed.');
  finally
    TFFmpegApi.sws_freeContext(ScaleContext);
  end;
end;

end.
