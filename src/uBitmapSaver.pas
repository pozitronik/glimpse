{ Bitmap saving to PNG and JPEG files.
  Near-pure: depends on VCL imaging classes but has no form or settings dependency. }
unit uBitmapSaver;

interface

uses
  Vcl.Graphics, uSettings;

{ Saves a bitmap to a file in the specified format.
  AJpegQuality: 1..100, APngCompression: 0..9. }
procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string;
  AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer);

implementation

uses
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string;
  AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer);
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

end.
