unit TestBitmapSaver;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBitmapSaver = class
  private
    FTempDir: string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestSavePNGCreatesFile;
    [Test] procedure TestSaveJPEGCreatesFile;
    [Test] procedure TestSavePNGReadable;
    [Test] procedure TestSaveJPEGReadable;
    [Test] procedure TestSaveJPEGQualityAffectsSize;
    [Test] procedure TestSavePNGCompressionAffectsSize;
    [Test] procedure TestPngBytesToBitmapValid;
    [Test] procedure TestPngBytesToBitmapDimensions;
    [Test] procedure TestPngBytesToBitmapEmptyRaises;
    [Test] procedure TestPngBytesToBitmapGarbageRaises;
    [Test] procedure TestSavePNGPixelFidelity;
    [Test] procedure TestSaveFormatExtensionPNG;
    [Test] procedure TestSaveFormatExtensionJPEG;
    [Test] procedure TestSavePNGAlphaRoundTrip;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, Winapi.Windows, Vcl.Graphics,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  uBitmapSaver;

function CreateTestBitmap(AWidth, AHeight: Integer): TBitmap;
var
  X, Y: Integer;
begin
  Result := TBitmap.Create;
  Result.SetSize(AWidth, AHeight);
  Result.PixelFormat := pf24bit;
  { Fill with a gradient so compression tests have meaningful data }
  for Y := 0 to AHeight - 1 do
    for X := 0 to AWidth - 1 do
      Result.Canvas.Pixels[X, Y] := RGB(X mod 256, Y mod 256, (X + Y) mod 256);
end;

procedure TTestBitmapSaver.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_SaveTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestBitmapSaver.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestBitmapSaver.TestSavePNGCreatesFile;
var
  Bmp: TBitmap;
  Path: string;
begin
  Path := TPath.Combine(FTempDir, 'test.png');
  Bmp := CreateTestBitmap(10, 10);
  try
    SaveBitmapToFile(Bmp, Path, sfPNG, 90, 6);
    Assert.IsTrue(TFile.Exists(Path), 'PNG file should exist');
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapSaver.TestSaveJPEGCreatesFile;
var
  Bmp: TBitmap;
  Path: string;
begin
  Path := TPath.Combine(FTempDir, 'test.jpg');
  Bmp := CreateTestBitmap(10, 10);
  try
    SaveBitmapToFile(Bmp, Path, sfJPEG, 90, 6);
    Assert.IsTrue(TFile.Exists(Path), 'JPEG file should exist');
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapSaver.TestSavePNGReadable;
var
  Bmp: TBitmap;
  Png: TPngImage;
  Path: string;
begin
  Path := TPath.Combine(FTempDir, 'readable.png');
  Bmp := CreateTestBitmap(20, 15);
  try
    SaveBitmapToFile(Bmp, Path, sfPNG, 90, 6);
  finally
    Bmp.Free;
  end;

  Png := TPngImage.Create;
  try
    Png.LoadFromFile(Path);
    Assert.AreEqual(20, Png.Width, 'Width');
    Assert.AreEqual(15, Png.Height, 'Height');
  finally
    Png.Free;
  end;
end;

procedure TTestBitmapSaver.TestSaveJPEGReadable;
var
  Bmp: TBitmap;
  Jpg: TJPEGImage;
  Path: string;
begin
  Path := TPath.Combine(FTempDir, 'readable.jpg');
  Bmp := CreateTestBitmap(20, 15);
  try
    SaveBitmapToFile(Bmp, Path, sfJPEG, 90, 6);
  finally
    Bmp.Free;
  end;

  Jpg := TJPEGImage.Create;
  try
    Jpg.LoadFromFile(Path);
    Assert.AreEqual(20, Jpg.Width, 'Width');
    Assert.AreEqual(15, Jpg.Height, 'Height');
  finally
    Jpg.Free;
  end;
end;

procedure TTestBitmapSaver.TestSaveJPEGQualityAffectsSize;
var
  Bmp: TBitmap;
  PathLow, PathHigh: string;
begin
  PathLow := TPath.Combine(FTempDir, 'low.jpg');
  PathHigh := TPath.Combine(FTempDir, 'high.jpg');
  Bmp := CreateTestBitmap(100, 100);
  try
    SaveBitmapToFile(Bmp, PathLow, sfJPEG, 10, 6);
    SaveBitmapToFile(Bmp, PathHigh, sfJPEG, 100, 6);
  finally
    Bmp.Free;
  end;
  Assert.IsTrue(TFile.GetSize(PathLow) < TFile.GetSize(PathHigh),
    'Low quality should produce smaller file');
end;

procedure TTestBitmapSaver.TestSavePNGCompressionAffectsSize;
var
  Bmp: TBitmap;
  PathNone, PathMax: string;
begin
  PathNone := TPath.Combine(FTempDir, 'none.png');
  PathMax := TPath.Combine(FTempDir, 'max.png');
  Bmp := CreateTestBitmap(100, 100);
  try
    SaveBitmapToFile(Bmp, PathNone, sfPNG, 90, 0);
    SaveBitmapToFile(Bmp, PathMax, sfPNG, 90, 9);
  finally
    Bmp.Free;
  end;
  Assert.IsTrue(TFile.GetSize(PathMax) < TFile.GetSize(PathNone),
    'Max compression should produce smaller file');
end;

function BitmapToPngBytes(ABmp: TBitmap): TBytes;
var
  Png: TPngImage;
  Stream: TMemoryStream;
begin
  Png := TPngImage.Create;
  try
    Png.Assign(ABmp);
    Stream := TMemoryStream.Create;
    try
      Png.SaveToStream(Stream);
      SetLength(Result, Stream.Size);
      Move(Stream.Memory^, Result[0], Stream.Size);
    finally
      Stream.Free;
    end;
  finally
    Png.Free;
  end;
end;

procedure TTestBitmapSaver.TestPngBytesToBitmapValid;
var
  Src: TBitmap;
  Data: TBytes;
  Dst: TBitmap;
begin
  Src := CreateTestBitmap(30, 20);
  try
    Data := BitmapToPngBytes(Src);
  finally
    Src.Free;
  end;
  Dst := PngBytesToBitmap(Data);
  try
    Assert.IsNotNull(Dst);
    Assert.AreEqual(30, Dst.Width);
    Assert.AreEqual(20, Dst.Height);
    Assert.AreEqual(Ord(pf24bit), Ord(Dst.PixelFormat), 'Must be pf24bit');
  finally
    Dst.Free;
  end;
end;

procedure TTestBitmapSaver.TestPngBytesToBitmapDimensions;
var
  Src: TBitmap;
  Data: TBytes;
  Dst: TBitmap;
begin
  { Verify a different aspect ratio round-trips correctly }
  Src := CreateTestBitmap(1, 200);
  try
    Data := BitmapToPngBytes(Src);
  finally
    Src.Free;
  end;
  Dst := PngBytesToBitmap(Data);
  try
    Assert.AreEqual(1, Dst.Width);
    Assert.AreEqual(200, Dst.Height);
  finally
    Dst.Free;
  end;
end;

procedure TTestBitmapSaver.TestPngBytesToBitmapEmptyRaises;
var
  Data: TBytes;
begin
  SetLength(Data, 0);
  Assert.WillRaise(
    procedure begin PngBytesToBitmap(Data); end,
    nil,
    'Empty bytes should raise');
end;

procedure TTestBitmapSaver.TestPngBytesToBitmapGarbageRaises;
var
  Data: TBytes;
begin
  { Random bytes that are not valid PNG. Must raise, not silently return
    a corrupt bitmap. }
  Data := TBytes.Create($DE, $AD, $BE, $EF, $CA, $FE, $00, $FF);
  Assert.WillRaise(
    procedure begin PngBytesToBitmap(Data); end,
    nil,
    'Garbage bytes must raise, not produce a corrupt bitmap');
end;

procedure TTestBitmapSaver.TestSavePNGPixelFidelity;
var
  Src, Dst: TBitmap;
  Path: string;
  Png: TPngImage;
begin
  { PNG is lossless: pixel values must survive a save/load round-trip. }
  Src := TBitmap.Create;
  try
    Src.SetSize(3, 1);
    Src.PixelFormat := pf24bit;
    Src.Canvas.Pixels[0, 0] := RGB(255, 0, 0);
    Src.Canvas.Pixels[1, 0] := RGB(0, 255, 0);
    Src.Canvas.Pixels[2, 0] := RGB(0, 0, 255);

    Path := TPath.Combine(FTempDir, 'fidelity.png');
    SaveBitmapToFile(Src, Path, sfPNG, 90, 6);
  finally
    Src.Free;
  end;

  Png := TPngImage.Create;
  try
    Png.LoadFromFile(Path);
    Dst := TBitmap.Create;
    try
      Dst.Assign(Png);
      Assert.AreEqual(Integer(RGB(255, 0, 0)), Integer(Dst.Canvas.Pixels[0, 0]),
        'Red pixel must survive round-trip');
      Assert.AreEqual(Integer(RGB(0, 255, 0)), Integer(Dst.Canvas.Pixels[1, 0]),
        'Green pixel must survive round-trip');
      Assert.AreEqual(Integer(RGB(0, 0, 255)), Integer(Dst.Canvas.Pixels[2, 0]),
        'Blue pixel must survive round-trip');
    finally
      Dst.Free;
    end;
  finally
    Png.Free;
  end;
end;

procedure TTestBitmapSaver.TestSaveFormatExtensionPNG;
begin
  Assert.AreEqual('.png', SaveFormatExtension(sfPNG));
end;

procedure TTestBitmapSaver.TestSaveFormatExtensionJPEG;
begin
  Assert.AreEqual('.jpg', SaveFormatExtension(sfJPEG));
end;

procedure TTestBitmapSaver.TestSavePNGAlphaRoundTrip;
var
  Src: TBitmap;
  Path: string;
  Png: TPngImage;
  X, Y: Integer;
  RowSrc: PByte;
  AlphaLine: PByteArray;
  ExpectedAlpha: Byte;
begin
  {Build a pf32bit bitmap whose alpha varies per pixel, save as PNG,
   load it back as a TPngImage, and verify the alpha bytes survived.
   This pins the fix for the "background opacity 0 produced a fully
   white image" regression caused by TPngImage.Assign(TBitmap) silently
   stripping alpha for pf32bit sources.}
  Src := TBitmap.Create;
  try
    Src.PixelFormat := pf32bit;
    Src.AlphaFormat := afDefined;
    Src.SetSize(8, 4);
    {Top half opaque green, bottom half fully transparent red.}
    for Y := 0 to Src.Height - 1 do
    begin
      RowSrc := PByte(Src.ScanLine[Y]);
      for X := 0 to Src.Width - 1 do
      begin
        if Y < Src.Height div 2 then
        begin
          RowSrc^ := 0; Inc(RowSrc);     // B
          RowSrc^ := 255; Inc(RowSrc);   // G
          RowSrc^ := 0; Inc(RowSrc);     // R
          RowSrc^ := 255; Inc(RowSrc);   // A
        end
        else
        begin
          RowSrc^ := 0; Inc(RowSrc);     // B
          RowSrc^ := 0; Inc(RowSrc);     // G
          RowSrc^ := 255; Inc(RowSrc);   // R
          RowSrc^ := 0; Inc(RowSrc);     // A (fully transparent)
        end;
      end;
    end;

    Path := TPath.Combine(FTempDir, 'alpha_roundtrip.png');
    SaveBitmapToFile(Src, Path, sfPNG, 90, 6);
  finally
    Src.Free;
  end;

  {Load via TPngImage and inspect alpha scanlines and pixel colours. The
   colour assertions catch a TColor byte-order swap (R<->B) that could
   silently slip past the alpha-only checks: clearly-asymmetric green
   vs red lets a saved-as-blue regression scream.}
  Png := TPngImage.Create;
  try
    Png.LoadFromFile(Path);
    for Y := 0 to Png.Height - 1 do
    begin
      AlphaLine := Png.AlphaScanline[Y];
      Assert.IsNotNull(AlphaLine,
        Format('AlphaScanline must be non-nil (Y=%d): the PNG must be saved with alpha', [Y]));
      if Y < Png.Height div 2 then
        ExpectedAlpha := 255
      else
        ExpectedAlpha := 0;
      for X := 0 to Png.Width - 1 do
      begin
        Assert.AreEqual(Integer(ExpectedAlpha), Integer(AlphaLine[X]),
          Format('Alpha mismatch at (%d,%d)', [X, Y]));
        if Y < Png.Height div 2 then
          {Top: opaque green = (R=0, G=255, B=0)}
          Assert.AreEqual<Integer>($0000FF00, Integer(Png.Pixels[X, Y]),
            Format('Top half must be green at (%d,%d); R<->B swap would land here', [X, Y]))
        else
          {Bottom: red = (R=255, G=0, B=0). Alpha is 0 but RGB is still preserved.}
          Assert.AreEqual<Integer>($000000FF, Integer(Png.Pixels[X, Y]),
            Format('Bottom half must be red at (%d,%d); R<->B swap would land here', [X, Y]));
      end;
    end;
  finally
    Png.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBitmapSaver);

end.
