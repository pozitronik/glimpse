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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, Vcl.Graphics,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  uSettings, uBitmapSaver;

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

initialization
  TDUnitX.RegisterTestFixture(TTestBitmapSaver);

end.
