{Bitmap saving to PNG and JPEG files.
 Near-pure: depends on VCL imaging classes but has no form or settings dependency.}
unit uBitmapSaver;

interface

uses
  System.SysUtils, Vcl.Graphics;

type
  TSaveFormat = (sfPNG, sfJPEG);

  {Returns the file extension for a save format, including the dot.}
function SaveFormatExtension(AFormat: TSaveFormat): string;

{Saves a bitmap to a file in the specified format.
 AJpegQuality: 1..100, APngCompression: 0..9.}
procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer);

{Converts raw PNG bytes to a TBitmap (pf24bit).
 Caller owns the returned bitmap. Raises on invalid data.}
function PngBytesToBitmap(const AData: TBytes): TBitmap;

implementation

uses
  System.Classes, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

{Saves a pf32bit bitmap as a 32-bit PNG with explicit alpha. Vcl's
 TPngImage.Assign(TBitmap) is unreliable for alpha — depending on Delphi
 version it silently emits a 24-bit PNG or stamps alpha=255 over real
 alpha values. We sidestep that by building a COLOR_RGBALPHA PNG of
 known geometry and writing each scanline byte-for-byte.

 Implementation note: TPngImage stores COLOR_RGBALPHA at 8 bits per
 channel as a 24-bit BGR DIB scanline plus a separate AlphaScanline
 (verified against TPngImage.SetInfo(24, FALSE) for COLOR_RGBALPHA).
 Source pf32bit DIBs are also BGRA, so for each pixel we copy three
 bytes verbatim to the BGR scanline and the fourth byte to the alpha
 line — no per-pixel TColor packing or property dispatch.
 TestSavePNGAlphaRoundTrip pins both the alpha and the colour ordering;
 a B/R swap regression there would scream "R<->B swap would land here".}
procedure SaveAlphaBitmapAsPng(ABitmap: TBitmap; const APath: string; ACompressionLevel: Integer);
const
  COLOR_RGBALPHA = 6;
  BGR_BYTES_PER_PIXEL = 3;
var
  Png: TPngImage;
  X, Y: Integer;
  Src, Dst: PByte;
  AlphaLine: PByteArray;
begin
  Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, ABitmap.Width, ABitmap.Height);
  try
    Png.CompressionLevel := ACompressionLevel;
    for Y := 0 to ABitmap.Height - 1 do
    begin
      Src := PByte(ABitmap.ScanLine[Y]);
      Dst := PByte(Png.ScanLine[Y]);
      AlphaLine := Png.AlphaScanline[Y];
      for X := 0 to ABitmap.Width - 1 do
      begin
        {BGR triple: byte-for-byte from BGRA source. Then peel off A.}
        Move(Src^, Dst^, BGR_BYTES_PER_PIXEL);
        Inc(Src, BGR_BYTES_PER_PIXEL);
        Inc(Dst, BGR_BYTES_PER_PIXEL);
        AlphaLine[X] := Src^;
        Inc(Src);
      end;
    end;
    Png.SaveToFile(APath);
  finally
    Png.Free;
  end;
end;

function SaveFormatExtension(AFormat: TSaveFormat): string;
begin
  case AFormat of
    sfJPEG:
      Result := '.jpg';
    else
      Result := '.png';
  end;
end;

procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer);
var
  Png: TPngImage;
  Jpg: TJPEGImage;
begin
  case AFormat of
    sfPNG:
      begin
        if ABitmap.PixelFormat = pf32bit then
        begin
          {Alpha-aware fast path: bypass TPngImage.Assign which is
           unreliable for 32-bit sources.}
          SaveAlphaBitmapAsPng(ABitmap, APath, APngCompression);
          Exit;
        end;
        Png := TPngImage.Create;
        try
          Png.CompressionLevel := APngCompression;
          Png.Assign(ABitmap);
          Png.SaveToFile(APath);
        finally
          Png.Free;
        end;
      end;
    sfJPEG:
      begin
        Jpg := TJPEGImage.Create;
        try
          Jpg.CompressionQuality := AJpegQuality;
          Jpg.Assign(ABitmap);
          Jpg.SaveToFile(APath);
        finally
          Jpg.Free;
        end;
      end;
  end;
end;

function PngBytesToBitmap(const AData: TBytes): TBitmap;
var
  Stream: TMemoryStream;
  Png: TPngImage;
begin
  {Explicit guard: empty input would fall through to a confusing
   EPNGInvalidFileHeader (when range checks are off) or ERangeError on
   AData[0] (when on). Fail fast with a clear contract violation instead.}
  if Length(AData) = 0 then
    raise EArgumentException.Create('PngBytesToBitmap: AData is empty');
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(AData[0], Length(AData));
    Stream.Position := 0;
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(Stream);
      Result := TBitmap.Create;
      try
        Result.Assign(Png);
        Result.PixelFormat := pf24bit; {Force DIB for thread-safe rendering}
      except
        FreeAndNil(Result);
        raise;
      end;
    finally
      Png.Free;
    end;
  finally
    Stream.Free;
  end;
end;

end.
