{Bitmap saving to PNG and JPEG files. No form or settings dependency.}
unit BitmapSaver;

interface

uses
  System.SysUtils, System.Classes, Vcl.Graphics;

type
  TSaveFormat = (sfPNG, sfJPEG);

  TSaveOptions = record
    Format: TSaveFormat;
    JpegQuality: Integer;
    PngCompression: Integer;
  end;

  {Per-format polymorphic saver. Adding a format = new class + one
   entry in MakeBitmapSaver. Distinct from IBitmapSaverRouter in
   wcx/WcxEntryExtractors.pas (multi-format dispatcher test seam).}
  IBitmapSaver = interface
    ['{B4F8E2A1-3C5D-4E6F-9A7B-8C9D0E1F2A3B}']
    procedure Save(ABitmap: TBitmap; const APath: string);
    function Extension: string;
  end;

  TPngBitmapSaver = class(TInterfacedObject, IBitmapSaver)
  strict private
    FCompression: Integer;
  public
    constructor Create(ACompression: Integer);
    procedure Save(ABitmap: TBitmap; const APath: string);
    function Extension: string;
  end;

  TJpegBitmapSaver = class(TInterfacedObject, IBitmapSaver)
  strict private
    FQuality: Integer;
  public
    constructor Create(AQuality: Integer);
    procedure Save(ABitmap: TBitmap; const APath: string);
    function Extension: string;
  end;

{Falls back to sfPNG when AValue is neither 'JPEG' nor 'JPG'.}
function StrToSaveFormat(const AValue: string): TSaveFormat;
function SaveFormatToStr(AFormat: TSaveFormat): string;

{Single dispatch point — SaveBitmapToFile and SaveFormatExtension both
 use it. Dummy values for the unused parameter are fine.}
function MakeBitmapSaver(AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer): IBitmapSaver;

function SaveFormatExtension(AFormat: TSaveFormat): string;

{APngCompression: 0..9. Routes pf32bit through the alpha-aware encoder.}
procedure EncodeBitmapAsPng(ABitmap: TBitmap; AStream: TStream; APngCompression: Integer);

{AQuality: 1..100. TJPEGImage.Assign flattens pf32bit per VCL semantics —
 callers that need explicit background compositing must do it themselves.}
procedure EncodeBitmapAsJpeg(ABitmap: TBitmap; AStream: TStream; AQuality: Integer);

{AJpegQuality: 1..100, APngCompression: 0..9.}
procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer); overload;

procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions); overload;

{Result is always pf24bit (alpha stripped) so the caller can render it
 from any thread without GDI alpha handling. Caller owns the bitmap.
 Raises on invalid data.}
function PngBytesToBitmap(const AData: TBytes): TBitmap;

implementation

uses
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

{TPngImage.Assign(TBitmap) is unreliable for alpha — it can emit 24-bit
 PNG or stamp alpha=255 depending on Delphi version. We build a
 COLOR_RGBALPHA PNG and write scanlines byte-for-byte. TPngImage's
 COLOR_RGBALPHA layout is 24-bit BGR plus a separate AlphaScanline,
 matching source pf32bit BGRA.}
procedure EncodeAlphaBitmapAsPng(ABitmap: TBitmap; AStream: TStream; ACompressionLevel: Integer);
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
        Move(Src^, Dst^, BGR_BYTES_PER_PIXEL);
        Inc(Src, BGR_BYTES_PER_PIXEL);
        Inc(Dst, BGR_BYTES_PER_PIXEL);
        AlphaLine[X] := Src^;
        Inc(Src);
      end;
    end;
    Png.SaveToStream(AStream);
  finally
    Png.Free;
  end;
end;

procedure EncodeBitmapAsPng(ABitmap: TBitmap; AStream: TStream; APngCompression: Integer);
var
  Png: TPngImage;
begin
  if ABitmap.PixelFormat = pf32bit then
  begin
    EncodeAlphaBitmapAsPng(ABitmap, AStream, APngCompression);
    Exit;
  end;
  Png := TPngImage.Create;
  try
    Png.CompressionLevel := APngCompression;
    Png.Assign(ABitmap);
    Png.SaveToStream(AStream);
  finally
    Png.Free;
  end;
end;

procedure EncodeBitmapAsJpeg(ABitmap: TBitmap; AStream: TStream; AQuality: Integer);
var
  Jpg: TJPEGImage;
begin
  Jpg := TJPEGImage.Create;
  try
    Jpg.CompressionQuality := AQuality;
    Jpg.Assign(ABitmap);
    Jpg.SaveToStream(AStream);
  finally
    Jpg.Free;
  end;
end;

{TPngBitmapSaver}

constructor TPngBitmapSaver.Create(ACompression: Integer);
begin
  inherited Create;
  FCompression := ACompression;
end;

procedure TPngBitmapSaver.Save(ABitmap: TBitmap; const APath: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmCreate);
  try
    EncodeBitmapAsPng(ABitmap, Stream, FCompression);
  finally
    Stream.Free;
  end;
end;

function TPngBitmapSaver.Extension: string;
begin
  Result := '.png';
end;

{TJpegBitmapSaver}

constructor TJpegBitmapSaver.Create(AQuality: Integer);
begin
  inherited Create;
  FQuality := AQuality;
end;

procedure TJpegBitmapSaver.Save(ABitmap: TBitmap; const APath: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmCreate);
  try
    EncodeBitmapAsJpeg(ABitmap, Stream, FQuality);
  finally
    Stream.Free;
  end;
end;

function TJpegBitmapSaver.Extension: string;
begin
  Result := '.jpg';
end;

function StrToSaveFormat(const AValue: string): TSaveFormat;
begin
  if SameText(AValue, 'JPEG') or SameText(AValue, 'JPG') then
    Result := sfJPEG
  else
    Result := sfPNG;
end;

function SaveFormatToStr(AFormat: TSaveFormat): string;
begin
  case AFormat of
    sfJPEG:
      Result := 'JPEG';
    else
      Result := 'PNG';
  end;
end;

function MakeBitmapSaver(AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer): IBitmapSaver;
begin
  case AFormat of
    sfJPEG: Result := TJpegBitmapSaver.Create(AJpegQuality);
  else
    Result := TPngBitmapSaver.Create(APngCompression);
  end;
end;

function SaveFormatExtension(AFormat: TSaveFormat): string;
begin
  {Route through the factory so adding a new format only touches
   MakeBitmapSaver.}
  Result := MakeBitmapSaver(AFormat, 0, 0).Extension;
end;

procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer);
begin
  MakeBitmapSaver(AFormat, AJpegQuality, APngCompression).Save(ABitmap, APath);
end;

procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions);
begin
  MakeBitmapSaver(AOptions.Format, AOptions.JpegQuality, AOptions.PngCompression).Save(ABitmap, APath);
end;

function PngBytesToBitmap(const AData: TBytes): TBitmap;
var
  Stream: TMemoryStream;
  Png: TPngImage;
begin
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
