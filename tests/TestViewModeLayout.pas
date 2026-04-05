unit TestViewModeLayout;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGridLayout = class
  public
    [Test] procedure TestColumnCountAuto;
    [Test] procedure TestColumnCountOverride;
    [Test] procedure TestColumnCountActualNative;
    [Test] procedure TestColumnCountSingleCell;
    [Test] procedure TestCellRectNoOverlap;
    [Test] procedure TestCellRectCentersHorizontally;
    [Test] procedure TestCellRectCentersVertically;
    [Test] procedure TestRecalcSizeCoversAllCells;
    [Test] procedure TestZoomScalesCells;
  end;

  [TestFixture]
  TTestScrollLayout = class
  public
    [Test] procedure TestColumnCountAlwaysOne;
    [Test] procedure TestCellsStackVertically;
    [Test] procedure TestActualUsesNativeDims;
    [Test] procedure TestFitIfLargerCaps;
    [Test] procedure TestRecalcSizeGrows;
    [Test] procedure TestWheelKindVertical;
  end;

  [TestFixture]
  TTestFilmstripLayout = class
  public
    [Test] procedure TestSingleHorizontalRow;
    [Test] procedure TestActualUsesNativeHeight;
    [Test] procedure TestFitIfLargerCaps;
    [Test] procedure TestWheelKindHorizontal;
    [Test] procedure TestRecalcSizeWidth;
  end;

  [TestFixture]
  TTestSingleLayout = class
  public
    [Test] procedure TestFitWindowFillsViewport;
    [Test] procedure TestActualUsesNativeSize;
    [Test] procedure TestFitIfLargerSmallNative;
    [Test] procedure TestWheelKindNavigate;
    [Test] procedure TestCellIndexAtHit;
    [Test] procedure TestCellIndexAtMiss;
  end;

  [TestFixture]
  TTestSmartGridLayout = class
  public
    [Test] procedure TestFillsViewport;
    [Test] procedure TestNoOverlap;
    [Test] procedure TestAllCellsCovered;
    [Test] procedure TestZoomScalesDimensions;
    [Test] procedure TestSingleFrame;
  end;

  [TestFixture]
  TTestLayoutFactory = class
  public
    [Test] procedure TestCreatesCorrectTypes;
  end;

implementation

uses
  System.Types, System.SysUtils, System.Math,
  uTypes, uViewModeLayout;

{ Builds a context with common defaults for testing }
function MakeCtx(ACellCount, ABaseW, ABaseH: Integer): TViewLayoutContext;
begin
  Result := Default(TViewLayoutContext);
  Result.BaseW := ABaseW;
  Result.BaseH := ABaseH;
  Result.CellCount := ACellCount;
  Result.CellGap := 4;
  Result.AspectRatio := 9.0 / 16.0;
  Result.ZoomMode := zmFitWindow;
  Result.ZoomFactor := 1.0;
  Result.ClientWidth := ABaseW;
  Result.ClientHeight := ABaseH;
  Result.ViewportW := ABaseW;
  Result.ViewportH := ABaseH;
end;

{ TTestGridLayout }

procedure TTestGridLayout.TestColumnCountAuto;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(9, 800, 600);
    Assert.AreEqual(3, L.GetColumnCount(Ctx), 'floor(sqrt(9)) = 3');
    Ctx.CellCount := 4;
    Assert.AreEqual(2, L.GetColumnCount(Ctx), 'floor(sqrt(4)) = 2');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestColumnCountOverride;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(9, 800, 600);
    Ctx.ColumnCount := 5;
    Assert.AreEqual(5, L.GetColumnCount(Ctx), 'Should use override');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestColumnCountActualNative;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    Ctx.ZoomMode := zmActual;
    Ctx.NativeW := 300;
    { (800 - 4) / (300 + 4) = 2.6 -> 2 }
    Assert.AreEqual(2, L.GetColumnCount(Ctx), 'Actual mode: fit 300px in 800px');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestColumnCountSingleCell;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    Assert.AreEqual(1, L.GetColumnCount(Ctx), 'Single cell = 1 column');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestCellRectNoOverlap;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
  I, J: Integer;
  R1, R2: TRect;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(9, 800, 600);
    for I := 0 to 7 do
      for J := I + 1 to 8 do
      begin
        R1 := L.GetCellRect(I, Ctx);
        R2 := L.GetCellRect(J, Ctx);
        Assert.IsFalse(
          (R1.Left < R2.Right) and (R1.Right > R2.Left) and
          (R1.Top < R2.Bottom) and (R1.Bottom > R2.Top),
          Format('Cells %d and %d overlap', [I, J]));
      end;
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestCellRectCentersHorizontally;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    R := L.GetCellRect(0, Ctx);
    Assert.IsTrue(R.Left > 0, 'Single cell should be centered, not at left edge');
    Assert.IsTrue(Abs(R.Left - (800 - R.Right)) <= 1, 'Should be centered');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestCellRectCentersVertically;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    Ctx.ColumnCount := 2;
    R := L.GetCellRect(0, Ctx);
    { Grid with 2 columns and 2 rows should be centered vertically in 600px }
    Assert.IsTrue(R.Top > 4, 'Grid should be centered vertically');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestRecalcSizeCoversAllCells;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
  Sz: TSize;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(9, 800, 600);
    Sz := L.RecalcSize(Ctx);
    Assert.IsTrue(Sz.cx >= 800, 'Width must be at least viewport');
    Assert.IsTrue(Sz.cy > 0, 'Height must be positive');
  finally
    L.Free;
  end;
end;

procedure TTestGridLayout.TestZoomScalesCells;
var
  L: TGridLayout;
  Ctx: TViewLayoutContext;
  R1, R2: TRect;
begin
  L := TGridLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    Ctx.ColumnCount := 2;
    R1 := L.GetCellRect(0, Ctx);

    Ctx.ZoomFactor := 2.0;
    R2 := L.GetCellRect(0, Ctx);

    Assert.IsTrue(Abs(R2.Width - R1.Width * 2) <= 2,
      Format('Zoomed width %d should be ~2x base %d', [R2.Width, R1.Width]));
  finally
    L.Free;
  end;
end;

{ TTestScrollLayout }

procedure TTestScrollLayout.TestColumnCountAlwaysOne;
var
  L: TScrollLayout;
  Ctx: TViewLayoutContext;
begin
  L := TScrollLayout.Create;
  try
    Ctx := MakeCtx(10, 800, 600);
    Assert.AreEqual(1, L.GetColumnCount(Ctx));
  finally
    L.Free;
  end;
end;

procedure TTestScrollLayout.TestCellsStackVertically;
var
  L: TScrollLayout;
  Ctx: TViewLayoutContext;
  R0, R1: TRect;
begin
  L := TScrollLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    R0 := L.GetCellRect(0, Ctx);
    R1 := L.GetCellRect(1, Ctx);
    Assert.AreEqual(R0.Left, R1.Left, 'Same left alignment');
    Assert.IsTrue(R1.Top > R0.Bottom, 'Cell 1 below cell 0');
  finally
    L.Free;
  end;
end;

procedure TTestScrollLayout.TestActualUsesNativeDims;
var
  L: TScrollLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TScrollLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    Ctx.ZoomMode := zmActual;
    Ctx.NativeW := 640;
    Ctx.NativeH := 360;
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(640, R.Width);
    Assert.AreEqual(360, R.Height);
  finally
    L.Free;
  end;
end;

procedure TTestScrollLayout.TestFitIfLargerCaps;
var
  L: TScrollLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TScrollLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    Ctx.ZoomMode := zmFitIfLarger;
    Ctx.NativeW := 400;
    Ctx.AspectRatio := 225 / 400;
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(400, R.Width, 'Should cap to native width');
  finally
    L.Free;
  end;
end;

procedure TTestScrollLayout.TestRecalcSizeGrows;
var
  L: TScrollLayout;
  C2, C4: TViewLayoutContext;
  S2, S4: TSize;
begin
  L := TScrollLayout.Create;
  try
    C2 := MakeCtx(2, 800, 600);
    C4 := MakeCtx(4, 800, 600);
    S2 := L.RecalcSize(C2);
    S4 := L.RecalcSize(C4);
    Assert.IsTrue(S4.cy > S2.cy, 'More cells = taller');
  finally
    L.Free;
  end;
end;

procedure TTestScrollLayout.TestWheelKindVertical;
var
  L: TScrollLayout;
begin
  L := TScrollLayout.Create;
  try
    Assert.AreEqual(Ord(lwaVerticalScroll), Ord(L.WheelScrollKind));
  finally
    L.Free;
  end;
end;

{ TTestFilmstripLayout }

procedure TTestFilmstripLayout.TestSingleHorizontalRow;
var
  L: TFilmstripLayout;
  Ctx: TViewLayoutContext;
  I: Integer;
  R: TRect;
begin
  L := TFilmstripLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 400);
    for I := 1 to 3 do
    begin
      R := L.GetCellRect(I, Ctx);
      Assert.AreEqual(L.GetCellRect(0, Ctx).Top, R.Top,
        Format('Cell %d should be on same row', [I]));
    end;
  finally
    L.Free;
  end;
end;

procedure TTestFilmstripLayout.TestActualUsesNativeHeight;
var
  L: TFilmstripLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TFilmstripLayout.Create;
  try
    Ctx := MakeCtx(2, 800, 600);
    Ctx.ZoomMode := zmActual;
    Ctx.NativeH := 360;
    Ctx.AspectRatio := 360 / 640;
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(360, R.Height);
  finally
    L.Free;
  end;
end;

procedure TTestFilmstripLayout.TestFitIfLargerCaps;
var
  L: TFilmstripLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TFilmstripLayout.Create;
  try
    Ctx := MakeCtx(2, 800, 600);
    Ctx.ZoomMode := zmFitIfLarger;
    Ctx.NativeH := 180;
    Ctx.AspectRatio := 180 / 320;
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(180, R.Height, 'Should cap to native');
  finally
    L.Free;
  end;
end;

procedure TTestFilmstripLayout.TestWheelKindHorizontal;
var
  L: TFilmstripLayout;
begin
  L := TFilmstripLayout.Create;
  try
    Assert.AreEqual(Ord(lwaHorizontalScroll), Ord(L.WheelScrollKind));
  finally
    L.Free;
  end;
end;

procedure TTestFilmstripLayout.TestRecalcSizeWidth;
var
  L: TFilmstripLayout;
  Ctx: TViewLayoutContext;
  Sz: TSize;
  R0: TRect;
begin
  L := TFilmstripLayout.Create;
  try
    Ctx := MakeCtx(5, 800, 400);
    Ctx.ZoomMode := zmActual;
    Ctx.NativeH := 360;
    Ctx.NativeW := 640;
    Ctx.AspectRatio := 360 / 640;
    Sz := L.RecalcSize(Ctx);
    R0 := L.GetCellRect(0, Ctx);
    Assert.AreEqual(Max(800, 4 + 5 * (R0.Width + 4)), Sz.cx,
      'Width must match cell geometry');
  finally
    L.Free;
  end;
end;

{ TTestSingleLayout }

procedure TTestSingleLayout.TestFitWindowFillsViewport;
var
  L: TSingleLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TSingleLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    R := L.GetCellRect(0, Ctx);
    Assert.IsTrue(R.Width > 0);
    Assert.IsTrue(R.Height > 0);
    Assert.IsTrue(R.Right <= 800);
    Assert.IsTrue(R.Bottom <= 600);
  finally
    L.Free;
  end;
end;

procedure TTestSingleLayout.TestActualUsesNativeSize;
var
  L: TSingleLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TSingleLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    Ctx.ZoomMode := zmActual;
    Ctx.NativeW := 320;
    Ctx.NativeH := 240;
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(320, R.Width);
    Assert.AreEqual(240, R.Height);
  finally
    L.Free;
  end;
end;

procedure TTestSingleLayout.TestFitIfLargerSmallNative;
var
  L: TSingleLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TSingleLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    Ctx.ZoomMode := zmFitIfLarger;
    Ctx.NativeW := 200;
    Ctx.NativeH := 150;
    Ctx.AspectRatio := 150 / 200;
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(200, R.Width, 'Small native: use native width');
    Assert.AreEqual(150, R.Height, 'Small native: use native height');
  finally
    L.Free;
  end;
end;

procedure TTestSingleLayout.TestWheelKindNavigate;
var
  L: TSingleLayout;
begin
  L := TSingleLayout.Create;
  try
    Assert.AreEqual(Ord(lwaNavigateFrame), Ord(L.WheelScrollKind));
  finally
    L.Free;
  end;
end;

procedure TTestSingleLayout.TestCellIndexAtHit;
var
  L: TSingleLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TSingleLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    Ctx.CurrentFrameIndex := 2;
    R := L.GetCellRect(2, Ctx);
    Assert.AreEqual(2, L.CellIndexAt(R.CenterPoint, Ctx));
  finally
    L.Free;
  end;
end;

procedure TTestSingleLayout.TestCellIndexAtMiss;
var
  L: TSingleLayout;
  Ctx: TViewLayoutContext;
begin
  L := TSingleLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    Ctx.CurrentFrameIndex := 0;
    Assert.AreEqual(-1, L.CellIndexAt(Point(0, 0), Ctx));
  finally
    L.Free;
  end;
end;

{ TTestSmartGridLayout }

procedure TTestSmartGridLayout.TestFillsViewport;
var
  L: TSmartGridLayout;
  Ctx: TViewLayoutContext;
  Sz: TSize;
begin
  L := TSmartGridLayout.Create;
  try
    Ctx := MakeCtx(9, 800, 600);
    Sz := L.RecalcSize(Ctx);
    Assert.AreEqual(800, Sz.cx, 'Width should match viewport');
    Assert.AreEqual(600, Sz.cy, 'Height should match viewport');
  finally
    L.Free;
  end;
end;

procedure TTestSmartGridLayout.TestNoOverlap;
var
  L: TSmartGridLayout;
  Ctx: TViewLayoutContext;
  I, J: Integer;
  R1, R2: TRect;
begin
  L := TSmartGridLayout.Create;
  try
    Ctx := MakeCtx(9, 800, 600);
    L.RecalcSize(Ctx); { populates internal row data }
    for I := 0 to 7 do
      for J := I + 1 to 8 do
      begin
        R1 := L.GetCellRect(I, Ctx);
        R2 := L.GetCellRect(J, Ctx);
        Assert.IsFalse(
          (R1.Left < R2.Right) and (R1.Right > R2.Left) and
          (R1.Top < R2.Bottom) and (R1.Bottom > R2.Top),
          Format('Cells %d and %d overlap', [I, J]));
      end;
  finally
    L.Free;
  end;
end;

procedure TTestSmartGridLayout.TestAllCellsCovered;
var
  L: TSmartGridLayout;
  Ctx: TViewLayoutContext;
  I: Integer;
  R: TRect;
begin
  L := TSmartGridLayout.Create;
  try
    Ctx := MakeCtx(7, 800, 600);
    L.RecalcSize(Ctx);
    for I := 0 to 6 do
    begin
      R := L.GetCellRect(I, Ctx);
      Assert.IsTrue(R.Width > 10,
        Format('Cell %d should have meaningful width', [I]));
      Assert.IsTrue(R.Height > 10,
        Format('Cell %d should have meaningful height', [I]));
    end;
  finally
    L.Free;
  end;
end;

procedure TTestSmartGridLayout.TestZoomScalesDimensions;
var
  L: TSmartGridLayout;
  Ctx: TViewLayoutContext;
  R1, R2: TRect;
begin
  L := TSmartGridLayout.Create;
  try
    Ctx := MakeCtx(4, 800, 600);
    L.RecalcSize(Ctx);
    R1 := L.GetCellRect(0, Ctx);

    Ctx.ZoomFactor := 2.0;
    L.RecalcSize(Ctx);
    R2 := L.GetCellRect(0, Ctx);

    Assert.IsTrue(Abs(R2.Width - R1.Width * 2) <= 2,
      Format('Zoomed width %d should be ~2x base %d', [R2.Width, R1.Width]));
  finally
    L.Free;
  end;
end;

procedure TTestSmartGridLayout.TestSingleFrame;
var
  L: TSmartGridLayout;
  Ctx: TViewLayoutContext;
  R: TRect;
begin
  L := TSmartGridLayout.Create;
  try
    Ctx := MakeCtx(1, 800, 600);
    L.RecalcSize(Ctx);
    R := L.GetCellRect(0, Ctx);
    Assert.AreEqual(800, R.Width, 'Single frame fills viewport width');
    Assert.AreEqual(600, R.Height, 'Single frame fills viewport height');
  finally
    L.Free;
  end;
end;

{ TTestLayoutFactory }

procedure TTestLayoutFactory.TestCreatesCorrectTypes;
var
  L: TViewModeLayout;
begin
  L := CreateViewModeLayout(vmGrid);
  try Assert.IsTrue(L is TGridLayout, 'vmGrid -> TGridLayout'); finally L.Free; end;
  L := CreateViewModeLayout(vmSmartGrid);
  try Assert.IsTrue(L is TSmartGridLayout, 'vmSmartGrid -> TSmartGridLayout'); finally L.Free; end;
  L := CreateViewModeLayout(vmScroll);
  try Assert.IsTrue(L is TScrollLayout, 'vmScroll -> TScrollLayout'); finally L.Free; end;
  L := CreateViewModeLayout(vmFilmstrip);
  try Assert.IsTrue(L is TFilmstripLayout, 'vmFilmstrip -> TFilmstripLayout'); finally L.Free; end;
  L := CreateViewModeLayout(vmSingle);
  try Assert.IsTrue(L is TSingleLayout, 'vmSingle -> TSingleLayout'); finally L.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGridLayout);
  TDUnitX.RegisterTestFixture(TTestScrollLayout);
  TDUnitX.RegisterTestFixture(TTestFilmstripLayout);
  TDUnitX.RegisterTestFixture(TTestSingleLayout);
  TDUnitX.RegisterTestFixture(TTestSmartGridLayout);
  TDUnitX.RegisterTestFixture(TTestLayoutFactory);

end.
