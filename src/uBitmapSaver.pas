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
