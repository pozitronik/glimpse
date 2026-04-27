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
 known geometry and writing each scanline byte-for-byte.}
procedure SaveAlphaBitmapAsPng(ABitmap: TBitmap; const APath: string;
  ACompressionLevel: Integer);
const
  COLOR_RGBALPHA = 6;
var
  Png: TPngImage;
  X, Y: Integer;
  Src: PByte;
  AlphaLine: PByteArray;
  B, G, R, A: Byte;
begin
  Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, ABitmap.Width, ABitmap.Height);
  try
    Png.CompressionLevel := ACompressionLevel;
    for Y := 0 to ABitmap.Height - 1 do
    begin
      Src := PByte(ABitmap.ScanLine[Y]);
      AlphaLine := Png.AlphaScanline[Y];
      for X := 0 to ABitmap.Width - 1 do
      begin
        {Win32 DIB pf32bit byte order is BGRA. TColor stores red in the
         low byte, so the COLORREF/RGB-macro packing is
         R | (G shl 8) | (B shl 16) — inlined here to avoid pulling in
         Winapi.Windows, which would shadow Vcl.Graphics.TBitmap with
         Winapi.Windows.tagBITMAP.}
        B := Src^; Inc(Src);
        G := Src^; Inc(Src);
        R := Src^; Inc(Src);
        A := Src^; Inc(Src);
        Png.Pixels[X, Y] := TColor(R or (G shl 8) or (B shl 16));
        AlphaLine[X] := A;
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
