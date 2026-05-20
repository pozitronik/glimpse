{Tests for TFrameGeometry: viewport-freeze logic, fit-column math,
 default-column logic, and layout-context assembly.}
unit TestFrameGeometry;

interface

uses
  DUnitX.TestFramework,
  FrameCellStore,
  FrameGeometry;

type
  [TestFixture]
  TTestFrameGeometry = class
  strict private
    FStore: TFrameCellStore;
    FGeo: TFrameGeometry;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure ViewMode_RoundTrips;
    [Test] procedure ZoomMode_RoundTrips;
    [Test] procedure ZoomFactor_RoundTrips;
    [Test] procedure AspectRatio_RoundTrips;
    [Test] procedure NativeW_RoundTrips;
    [Test] procedure NativeH_RoundTrips;
    [Test] procedure CellGap_RoundTrips;
    [Test] procedure CellMargin_RoundTrips;
    [Test] procedure ColumnCount_RoundTrips;

    [Test] procedure Viewport_AtZoom1_BaseTracksViewport;
    [Test] procedure Viewport_WhenZoomed_BaseStaysFrozen;
    [Test] procedure Viewport_BackToZoom1_BaseTracksViewportAgain;
    [Test] procedure ApplyZoom_SetsZoomFactor;

    [Test] procedure CalcFitColumns_SingleCell_ReturnsOne;
    [Test] procedure CalcFitColumns_ZeroViewport_ReturnsOne;
    [Test] procedure CalcFitColumns_WideShortViewport_ReturnsAllColumns;

    [Test] procedure DefaultColumnCount_ScrollMode_ReturnsOne;
    [Test] procedure DefaultColumnCount_SingleCell_ReturnsOne;
    [Test] procedure DefaultColumnCount_GridFourCells_ReturnsTwo;
    [Test] procedure DefaultColumnCount_GridNineCells_ReturnsThree;

    [Test] procedure BuildContext_FillsCellCountFromStore;
    [Test] procedure BuildContext_FillsGeometryState;
    [Test] procedure BuildContext_ShrinksClientSizeByMargin;
    [Test] procedure BuildContext_PassesCurrentFrameIndex;

    [Test] procedure ContentSize_NoCells_ReturnsViewport;
  end;

implementation

uses
  System.Types,
  Types,
  ViewModeLayout;

procedure TTestFrameGeometry.Setup;
begin
  FStore := TFrameCellStore.Create;
  FGeo := TFrameGeometry.Create(FStore);
end;

procedure TTestFrameGeometry.TearDown;
begin
  {Geometry borrows the store, so free the borrower first.}
  FGeo.Free;
  FGeo := nil;
  FStore.Free;
  FStore := nil;
end;

procedure TTestFrameGeometry.ViewMode_RoundTrips;
begin
  FGeo.ViewMode := vmSingle;
  Assert.AreEqual(Ord(vmSingle), Ord(FGeo.ViewMode));
end;

procedure TTestFrameGeometry.ZoomMode_RoundTrips;
begin
  FGeo.ZoomMode := zmActual;
  Assert.AreEqual(Ord(zmActual), Ord(FGeo.ZoomMode));
end;

procedure TTestFrameGeometry.ZoomFactor_RoundTrips;
begin
  FGeo.ZoomFactor := 3.0;
  Assert.AreEqual(3.0, FGeo.ZoomFactor, 0.0001);
end;

procedure TTestFrameGeometry.AspectRatio_RoundTrips;
begin
  FGeo.AspectRatio := 0.5625;
  Assert.AreEqual(0.5625, FGeo.AspectRatio, 0.0001);
end;

procedure TTestFrameGeometry.NativeW_RoundTrips;
begin
  FGeo.NativeW := 1280;
  Assert.AreEqual(1280, FGeo.NativeW);
end;

procedure TTestFrameGeometry.NativeH_RoundTrips;
begin
  FGeo.NativeH := 720;
  Assert.AreEqual(720, FGeo.NativeH);
end;

procedure TTestFrameGeometry.CellGap_RoundTrips;
begin
  FGeo.CellGap := 12;
  Assert.AreEqual(12, FGeo.CellGap);
end;

procedure TTestFrameGeometry.CellMargin_RoundTrips;
begin
  FGeo.CellMargin := 6;
  Assert.AreEqual(6, FGeo.CellMargin);
end;

procedure TTestFrameGeometry.ColumnCount_RoundTrips;
begin
  FGeo.ColumnCount := 5;
  Assert.AreEqual(5, FGeo.ColumnCount);
end;

procedure TTestFrameGeometry.Viewport_AtZoom1_BaseTracksViewport;
begin
  FGeo.SetViewport(800, 600);
  Assert.AreEqual(800, FGeo.BaseW);
  Assert.AreEqual(600, FGeo.BaseH);
end;

procedure TTestFrameGeometry.Viewport_WhenZoomed_BaseStaysFrozen;
begin
  FGeo.SetViewport(800, 600);
  FGeo.ApplyZoom(2.0);
  FGeo.SetViewport(400, 300);
  Assert.AreEqual(800, FGeo.BaseW, 'base width stays frozen at the zoom-1.0 viewport');
  Assert.AreEqual(600, FGeo.BaseH, 'base height stays frozen at the zoom-1.0 viewport');
end;

procedure TTestFrameGeometry.Viewport_BackToZoom1_BaseTracksViewportAgain;
begin
  FGeo.SetViewport(800, 600);
  FGeo.ApplyZoom(2.0);
  FGeo.SetViewport(400, 300);
  FGeo.ApplyZoom(1.0);
  Assert.AreEqual(400, FGeo.BaseW, 'back at zoom 1.0 the base follows the current viewport');
  Assert.AreEqual(300, FGeo.BaseH);
end;

procedure TTestFrameGeometry.ApplyZoom_SetsZoomFactor;
begin
  FGeo.ApplyZoom(2.5);
  Assert.AreEqual(2.5, FGeo.ZoomFactor, 0.0001);
end;

procedure TTestFrameGeometry.CalcFitColumns_SingleCell_ReturnsOne;
begin
  FStore.SetCellCount(1, nil);
  Assert.AreEqual(1, FGeo.CalcFitColumns(800, 600));
end;

procedure TTestFrameGeometry.CalcFitColumns_ZeroViewport_ReturnsOne;
begin
  FStore.SetCellCount(4, nil);
  Assert.AreEqual(1, FGeo.CalcFitColumns(0, 600));
end;

procedure TTestFrameGeometry.CalcFitColumns_WideShortViewport_ReturnsAllColumns;
begin
  FStore.SetCellCount(4, nil);
  FGeo.CellGap := 0;
  FGeo.AspectRatio := 0.5;
  {A viewport wide enough that only a single row of all four cells fits
   the height budget.}
  Assert.AreEqual(4, FGeo.CalcFitColumns(4000, 1000));
end;

procedure TTestFrameGeometry.DefaultColumnCount_ScrollMode_ReturnsOne;
begin
  FStore.SetCellCount(9, nil);
  FGeo.ViewMode := vmScroll;
  Assert.AreEqual(1, FGeo.DefaultColumnCount);
end;

procedure TTestFrameGeometry.DefaultColumnCount_SingleCell_ReturnsOne;
begin
  FStore.SetCellCount(1, nil);
  FGeo.ViewMode := vmGrid;
  Assert.AreEqual(1, FGeo.DefaultColumnCount);
end;

procedure TTestFrameGeometry.DefaultColumnCount_GridFourCells_ReturnsTwo;
begin
  FStore.SetCellCount(4, nil);
  FGeo.ViewMode := vmGrid;
  Assert.AreEqual(2, FGeo.DefaultColumnCount);
end;

procedure TTestFrameGeometry.DefaultColumnCount_GridNineCells_ReturnsThree;
begin
  FStore.SetCellCount(9, nil);
  FGeo.ViewMode := vmGrid;
  Assert.AreEqual(3, FGeo.DefaultColumnCount);
end;

procedure TTestFrameGeometry.BuildContext_FillsCellCountFromStore;
var
  Ctx: TViewLayoutContext;
begin
  FStore.SetCellCount(5, nil);
  Ctx := FGeo.BuildContext(800, 600, 0);
  Assert.AreEqual(5, Ctx.CellCount);
end;

procedure TTestFrameGeometry.BuildContext_FillsGeometryState;
var
  Ctx: TViewLayoutContext;
begin
  FGeo.CellGap := 7;
  FGeo.AspectRatio := 0.75;
  FGeo.NativeW := 1920;
  FGeo.NativeH := 1080;
  FGeo.ZoomMode := zmActual;
  FGeo.ColumnCount := 3;
  FGeo.ZoomFactor := 1.5;
  Ctx := FGeo.BuildContext(800, 600, 0);
  Assert.AreEqual(7, Ctx.CellGap);
  Assert.AreEqual(0.75, Ctx.AspectRatio, 0.0001);
  Assert.AreEqual(1920, Ctx.NativeW);
  Assert.AreEqual(1080, Ctx.NativeH);
  Assert.AreEqual(Ord(zmActual), Ord(Ctx.ZoomMode));
  Assert.AreEqual(3, Ctx.ColumnCount);
  Assert.AreEqual(1.5, Ctx.ZoomFactor, 0.0001);
end;

procedure TTestFrameGeometry.BuildContext_ShrinksClientSizeByMargin;
var
  Ctx: TViewLayoutContext;
begin
  FGeo.CellMargin := 10;
  Ctx := FGeo.BuildContext(800, 600, 0);
  Assert.AreEqual(780, Ctx.ClientWidth, 'client width shrunk by 2*margin');
  Assert.AreEqual(580, Ctx.ClientHeight, 'client height shrunk by 2*margin');
end;

procedure TTestFrameGeometry.BuildContext_PassesCurrentFrameIndex;
var
  Ctx: TViewLayoutContext;
begin
  Ctx := FGeo.BuildContext(800, 600, 7);
  Assert.AreEqual(7, Ctx.CurrentFrameIndex);
end;

procedure TTestFrameGeometry.ContentSize_NoCells_ReturnsViewport;
var
  Sz: TSize;
begin
  FGeo.SetViewport(800, 600);
  Sz := FGeo.ContentSize(FGeo.BuildContext(800, 600, 0));
  Assert.AreEqual(800, Sz.CX, 'with no cells the content size is the raw viewport');
  Assert.AreEqual(600, Sz.CY);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameGeometry);

end.
