unit TestBitmapResize;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBitmapResize = class
  public
    [Test] procedure TestNilBitmapReturnsNil;
    [Test] procedure TestZeroLimitReturnsNil;
    [Test] procedure TestNegativeLimitReturnsNil;
    [Test] procedure TestEmptyBitmapReturnsNil;
    [Test] procedure TestNoDownscaleNeededReturnsNil;
    [Test] procedure TestExactFitReturnsNil;
    [Test] procedure TestNoUpscaling;
    [Test] procedure TestLandscapeDownscale;
    [Test] procedure TestPortraitDownscale;
    [Test] procedure TestSquareSource;
    [Test] procedure TestPreservesAspectRatio;
    [Test] procedure TestResultMinimumDimension;
    [Test] procedure TestPf32BitInputProducesPf32BitOutput;
    [Test] procedure TestPf32BitDownscalePreservesAlpha;
  end;

implementation

uses
  System.SysUtils, Vcl.Graphics, uBitmapResize;

function MakeBitmap(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AW, AH);
end;

procedure TTestBitmapResize.TestNilBitmapReturnsNil;
begin
  Assert.IsNull(DownscaleBitmapToFit(nil, 100));
end;

procedure TTestBitmapResize.TestZeroLimitReturnsNil;
var
  Bmp, Result: TBitmap;
begin
  Bmp := MakeBitmap(1920, 1080);
  try
    Result := DownscaleBitmapToFit(Bmp, 0);
    try
      Assert.IsNull(Result, 'Zero limit must produce nil (no-op)');
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestNegativeLimitReturnsNil;
var
  Bmp, Result: TBitmap;
begin
  { Defensive: a negative limit must be treated as no-op, not crash }
  Bmp := MakeBitmap(1920, 1080);
  try
    Result := DownscaleBitmapToFit(Bmp, -10);
    try
      Assert.IsNull(Result);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestEmptyBitmapReturnsNil;
var
  Bmp, Result: TBitmap;
begin
  { A bitmap with no SetSize call has 0 dimensions; nothing to scale }
  Bmp := TBitmap.Create;
  try
    Result := DownscaleBitmapToFit(Bmp, 100);
    try
      Assert.IsNull(Result);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestNoDownscaleNeededReturnsNil;
var
  Bmp, Result: TBitmap;
begin
  { 800x600 already has long side <= 1920: no scaling required }
  Bmp := MakeBitmap(800, 600);
  try
    Result := DownscaleBitmapToFit(Bmp, 1920);
    try
      Assert.IsNull(Result);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestExactFitReturnsNil;
var
  Bmp, Result: TBitmap;
begin
  { Edge case: long side equals the cap exactly. No scaling, return nil. }
  Bmp := MakeBitmap(1920, 1080);
  try
    Result := DownscaleBitmapToFit(Bmp, 1920);
    try
      Assert.IsNull(Result);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestNoUpscaling;
var
  Bmp, Result: TBitmap;
begin
  { Source much smaller than the cap: no upscale, return nil }
  Bmp := MakeBitmap(320, 240);
  try
    Result := DownscaleBitmapToFit(Bmp, 1920);
    try
      Assert.IsNull(Result, 'Smaller-than-cap bitmaps must not be upscaled');
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestLandscapeDownscale;
var
  Bmp, Result: TBitmap;
begin
  { 1920x1080 capped to 800: long side W -> 800, H scales to 450 }
  Bmp := MakeBitmap(1920, 1080);
  try
    Result := DownscaleBitmapToFit(Bmp, 800);
    try
      Assert.IsNotNull(Result);
      Assert.AreEqual(800, Result.Width);
      Assert.AreEqual(450, Result.Height);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestPortraitDownscale;
var
  Bmp, Result: TBitmap;
begin
  { Portrait 1080x1920 capped to 800: long side H -> 800, W scales to 450 }
  Bmp := MakeBitmap(1080, 1920);
  try
    Result := DownscaleBitmapToFit(Bmp, 800);
    try
      Assert.IsNotNull(Result);
      Assert.AreEqual(450, Result.Width);
      Assert.AreEqual(800, Result.Height);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestSquareSource;
var
  Bmp, Result: TBitmap;
begin
  { Square: both dimensions are "long", scale uniformly to the cap }
  Bmp := MakeBitmap(1000, 1000);
  try
    Result := DownscaleBitmapToFit(Bmp, 400);
    try
      Assert.IsNotNull(Result);
      Assert.AreEqual(400, Result.Width);
      Assert.AreEqual(400, Result.Height);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestPreservesAspectRatio;
var
  Bmp, Result: TBitmap;
  RatioBefore, RatioAfter: Double;
begin
  Bmp := MakeBitmap(1280, 720);
  try
    Result := DownscaleBitmapToFit(Bmp, 640);
    try
      Assert.IsNotNull(Result);
      RatioBefore := 1280 / 720;
      RatioAfter := Result.Width / Result.Height;
      Assert.IsTrue(Abs(RatioBefore - RatioAfter) < 0.01,
        Format('Aspect ratio drift: before=%.4f after=%.4f',
          [RatioBefore, RatioAfter]));
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestResultMinimumDimension;
var
  Bmp, Result: TBitmap;
begin
  { Extreme aspect ratio with a tight cap could round the short axis to 0;
    the helper must clamp to at least 1 pixel per axis }
  Bmp := MakeBitmap(2000, 4);
  try
    Result := DownscaleBitmapToFit(Bmp, 100);
    try
      Assert.IsNotNull(Result);
      Assert.IsTrue(Result.Width >= 1);
      Assert.IsTrue(Result.Height >= 1);
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

function MakeAlphaBitmap(AW, AH: Integer; AAlpha: Byte): TBitmap;
var
  X, Y: Integer;
  Row: PByte;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.AlphaFormat := afDefined;
  Result.SetSize(AW, AH);
  for Y := 0 to AH - 1 do
  begin
    Row := PByte(Result.ScanLine[Y]);
    for X := 0 to AW - 1 do
    begin
      Row^ := 0; Inc(Row);          // B
      Row^ := 0; Inc(Row);          // G
      Row^ := 255; Inc(Row);        // R
      Row^ := AAlpha; Inc(Row);     // A
    end;
  end;
end;

function AlphaByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 3);
  Result := Row^;
end;

procedure TTestBitmapResize.TestPf32BitInputProducesPf32BitOutput;
var
  Bmp, Result: TBitmap;
begin
  {pf32bit source with alpha must take the bilinear path; output must
   stay pf32bit so the saver writes a 32-bit PNG.}
  Bmp := MakeAlphaBitmap(1024, 768, 200);
  try
    Result := DownscaleBitmapToFit(Bmp, 256);
    try
      Assert.IsNotNull(Result);
      Assert.AreEqual(Ord(pf32bit), Ord(Result.PixelFormat));
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TTestBitmapResize.TestPf32BitDownscalePreservesAlpha;
var
  Bmp, Result: TBitmap;
begin
  {Source is uniform alpha=128 across the whole bitmap; bilinear interpolation
   between four equal samples must yield 128. Sample the centre pixel.}
  Bmp := MakeAlphaBitmap(800, 600, 128);
  try
    Result := DownscaleBitmapToFit(Bmp, 200);
    try
      Assert.IsNotNull(Result);
      Assert.AreEqual(128,
        Integer(AlphaByteAt(Result, Result.Width div 2, Result.Height div 2)),
        'Alpha must survive the downscale unchanged for a uniform-alpha source');
    finally
      Result.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBitmapResize);

end.
