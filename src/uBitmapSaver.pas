{Bitmap saving to PNG and JPEG files.
 Near-pure: depends on VCL imaging classes but has no form or settings dependency.}
unit uBitmapSaver;

interface

uses
  System.SysUtils, System.Classes, Vcl.Graphics;

type
  TSaveFormat = (sfPNG, sfJPEG);

  {Bundled save knobs for one TBitmap -> file operation. Replaces three
   separate parameters at call sites that previously read
   `H.Settings.SaveFormat` / `H.Settings.JpegQuality` /
   `H.Settings.PngCompression` next to each other (Demeter friction).
   TWcxSettings.SaveOptions builds it once per archive open; the WCX
   entry extractors pass it to IBitmapSaverRouter.Save.}
  TSaveOptions = record
    Format: TSaveFormat;
    JpegQuality: Integer;
    PngCompression: Integer;
  end;

  {Per-format bitmap saver. One implementation per supported file format;
   adding a new format (WEBP, AVIF, ...) is a new class plus one entry
   in MakeBitmapSaver's case — no edits to SaveBitmapToFile or
   SaveFormatExtension. The concrete implementations encapsulate
   format-specific options (PNG compression level, JPEG quality)
   passed at construction time so per-call dispatch stays uniform.

   Distinct from `IBitmapSaverRouter` in `wcx/uWcxEntryExtractors.pas`:
   the router is a multi-format dispatcher (test seam for WCX entry
   extractors that record what would have been saved); this interface
   is the per-format polymorphic family used inside the router.}
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

{Enum <-> INI-string conversions for TSaveFormat. Match the
 StrToIntDef convention: StrToSaveFormat falls back to sfPNG (the
 historical default) when AValue is neither 'JPEG' nor 'JPG'.
 Lives here next to the enum so settings layers depending on uBitmapSaver
 do not need to drag in a separate codec unit.}
function StrToSaveFormat(const AValue: string): TSaveFormat;
function SaveFormatToStr(AFormat: TSaveFormat): string;

{Picks the saver implementation matching AFormat. AJpegQuality is
 ignored when AFormat=sfPNG, APngCompression is ignored when
 AFormat=sfJPEG — passing dummy values is fine when the call only
 needs the extension. The single dispatch point that selects the
 concrete class; SaveBitmapToFile and SaveFormatExtension both use it.}
function MakeBitmapSaver(AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer): IBitmapSaver;

{Returns the file extension for a save format, including the dot.}
function SaveFormatExtension(AFormat: TSaveFormat): string;

{Encodes a bitmap as PNG bytes into AStream starting at its current
 position. Used by both the file-save path (SaveBitmapToFile) and the
 clipboard publish path (TCompressedPngStrategy in uClipboardFormatStrategies).
 Routes pf32bit sources through the alpha-aware encoder; other formats
 go via Vcl's TPngImage.Assign. APngCompression: 0..9.}
procedure EncodeBitmapAsPng(ABitmap: TBitmap; AStream: TStream; APngCompression: Integer);

{Saves a bitmap to a file in the specified format.
 AJpegQuality: 1..100, APngCompression: 0..9.}
procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer); overload;

{TSaveOptions overload. Unpacks the bundle and routes through the
 polymorphic family the same way the 5-arg overload does.}
procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions); overload;

{Converts raw PNG bytes to a TBitmap.
 The returned bitmap is always pf24bit: any alpha channel the source PNG
 carried is stripped during the TPngImage.Assign step, then PixelFormat
 is set to pf24bit so the result is a plain DIB safe to render from any
 thread without GDI alpha handling. Callers needing the source PNG's
 alpha should decode through Vcl.Imaging.pngimage.TPngImage directly.
 Caller owns the returned bitmap. Raises on invalid data.}
function PngBytesToBitmap(const AData: TBytes): TBitmap;

implementation

uses
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

{Encodes a pf32bit bitmap as a 32-bit PNG with explicit alpha into
 AStream. Vcl's TPngImage.Assign(TBitmap) is unreliable for alpha —
 depending on Delphi version it silently emits a 24-bit PNG or stamps
 alpha=255 over real alpha values. We sidestep that by building a
 COLOR_RGBALPHA PNG of known geometry and writing each scanline
 byte-for-byte.

 Implementation note: TPngImage stores COLOR_RGBALPHA at 8 bits per
 channel as a 24-bit BGR DIB scanline plus a separate AlphaScanline
 (verified against TPngImage.SetInfo(24, FALSE) for COLOR_RGBALPHA).
 Source pf32bit DIBs are also BGRA, so for each pixel we copy three
 bytes verbatim to the BGR scanline and the fourth byte to the alpha
 line — no per-pixel TColor packing or property dispatch.
 TestSavePNGAlphaRoundTrip pins both the alpha and the colour ordering;
 a B/R swap regression there would scream "R<->B swap would land here".}
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
        {BGR triple: byte-for-byte from BGRA source. Then peel off A.}
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
    {Alpha-aware fast path: bypass TPngImage.Assign which is unreliable
     for 32-bit sources.}
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
  Jpg: TJPEGImage;
begin
  Jpg := TJPEGImage.Create;
  try
    Jpg.CompressionQuality := FQuality;
    Jpg.Assign(ABitmap);
    Jpg.SaveToFile(APath);
  finally
    Jpg.Free;
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
  {Extension is constant per format and independent of quality /
   compression, but route through the factory anyway so adding a new
   format only touches MakeBitmapSaver.}
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
