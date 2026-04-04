unit TestZoomController;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestZoomController = class
  public
    [Test] procedure TestClampZoomFactorNormalZoomIn;
    [Test] procedure TestClampZoomFactorNormalZoomOut;
    [Test] procedure TestClampZoomFactorClampToMax;
    [Test] procedure TestClampZoomFactorClampToMin;
    [Test] procedure TestClampZoomFactorNoChangeAtMax;
    [Test] procedure TestClampZoomFactorEpsilonBoundary;
    [Test] procedure TestNormalizeViewportCenterZeroContent;
    [Test] procedure TestNormalizeViewportCenterCentered;
    [Test] procedure TestNormalizeViewportCenterScrolled;
    [Test] procedure TestDenormalizeViewportCenterRoundTrip;
    [Test] procedure TestDenormalizeViewportCenterNeverNegative;
    [Test] procedure TestDenormalizeViewportCenterMiddle;
    [Test] procedure TestClampZoomFactorNegativeFactor;
    [Test] procedure TestClampZoomFactorZeroFactor;
    [Test] procedure TestNormalizeViewportCenterZeroViewport;
  end;

implementation

uses
  System.Math, uZoomController;

procedure TTestZoomController.TestClampZoomFactorNormalZoomIn;
begin
  Assert.AreEqual(1.25, ClampZoomFactor(1.0, ZOOM_IN_FACTOR), 0.001);
end;

procedure TTestZoomController.TestClampZoomFactorNormalZoomOut;
begin
  Assert.AreEqual(0.8, ClampZoomFactor(1.0, ZOOM_OUT_FACTOR), 0.001);
end;

procedure TTestZoomController.TestClampZoomFactorClampToMax;
begin
  { 9.5 * 1.25 = 11.875, but clamped to 10.0 }
  Assert.AreEqual(MAX_ZOOM, ClampZoomFactor(9.5, ZOOM_IN_FACTOR), 0.001);
end;

procedure TTestZoomController.TestClampZoomFactorClampToMin;
begin
  { 0.12 * 0.8 = 0.096, but clamped to 0.1 }
  Assert.AreEqual(MIN_ZOOM, ClampZoomFactor(0.12, ZOOM_OUT_FACTOR), 0.001);
end;

procedure TTestZoomController.TestClampZoomFactorNoChangeAtMax;
begin
  { Already at MAX_ZOOM, zooming in further returns 0 (no change) }
  Assert.AreEqual(Double(0), ClampZoomFactor(MAX_ZOOM, ZOOM_IN_FACTOR), 0.0001);
end;

procedure TTestZoomController.TestClampZoomFactorEpsilonBoundary;
begin
  { Factor so close to 1.0 that the result is within ZOOM_EPSILON }
  Assert.AreEqual(Double(0), ClampZoomFactor(1.0, 1.00001), 0.0001,
    'Change smaller than epsilon should return 0');
end;

procedure TTestZoomController.TestNormalizeViewportCenterZeroContent;
begin
  Assert.AreEqual(0.5, NormalizeViewportCenter(0, 800, 0), 0.001,
    'Zero content should return center');
end;

procedure TTestZoomController.TestNormalizeViewportCenterCentered;
begin
  { Content exactly fits viewport: scroll=0, viewport=content=800 }
  Assert.AreEqual(0.5, NormalizeViewportCenter(0, 800, 800), 0.001,
    'Content fitting viewport should return center');
end;

procedure TTestZoomController.TestNormalizeViewportCenterScrolled;
begin
  { Content=2000, Viewport=800, Scroll=600 -> center at 600+400=1000 -> norm=0.5 }
  Assert.AreEqual(0.5, NormalizeViewportCenter(600, 800, 2000), 0.001);
end;

procedure TTestZoomController.TestDenormalizeViewportCenterRoundTrip;
var
  Norm: Double;
  Restored: Integer;
begin
  { Normalize then denormalize should return original scroll position }
  Norm := NormalizeViewportCenter(300, 800, 2000);
  Restored := DenormalizeViewportCenter(Norm, 2000, 800);
  Assert.AreEqual(300, Restored, 'Round-trip should preserve scroll position');
end;

procedure TTestZoomController.TestDenormalizeViewportCenterNeverNegative;
begin
  Assert.IsTrue(DenormalizeViewportCenter(0.0, 100, 800) >= 0,
    'Should never return negative');
  Assert.IsTrue(DenormalizeViewportCenter(0.1, 500, 800) >= 0,
    'Should never return negative');
end;

procedure TTestZoomController.TestDenormalizeViewportCenterMiddle;
begin
  { NormPos=0.5, content fits in viewport -> scroll should be 0 }
  Assert.AreEqual(0, DenormalizeViewportCenter(0.5, 800, 800),
    'Content fitting viewport should scroll to 0');
end;

procedure TTestZoomController.TestClampZoomFactorNegativeFactor;
begin
  { Negative factor clamps to MIN_ZOOM (1.0 * -1.0 = -1.0, clamped to 0.1) }
  Assert.AreEqual(MIN_ZOOM, ClampZoomFactor(1.0, -1.0), 0.001);
end;

procedure TTestZoomController.TestClampZoomFactorZeroFactor;
begin
  { Zero factor clamps to MIN_ZOOM (1.0 * 0.0 = 0.0, clamped to 0.1) }
  Assert.AreEqual(MIN_ZOOM, ClampZoomFactor(1.0, 0.0), 0.001);
end;

procedure TTestZoomController.TestNormalizeViewportCenterZeroViewport;
begin
  { Zero viewport: center is at ScrollPos / ContentSize }
  Assert.AreEqual(0.0, NormalizeViewportCenter(0, 0, 1000), 0.001,
    'Zero viewport at scroll 0 should return 0');
  Assert.AreEqual(0.5, NormalizeViewportCenter(500, 0, 1000), 0.001,
    'Zero viewport at scroll 500/1000 should return 0.5');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestZoomController);

end.
