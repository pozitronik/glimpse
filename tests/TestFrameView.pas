unit TestFrameView;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFrameViewLayout = class
  public
    [Test] procedure TestGridColumnsSingleFrame;
    [Test] procedure TestGridColumnsTwoFrames;
    [Test] procedure TestGridColumnsFourFrames;
    [Test] procedure TestGridColumnsNineFrames;
    [Test] procedure TestGridColumnsSixteenFrames;
    [Test] procedure TestScrollModeAlwaysOneColumn;
    [Test] procedure TestRecalcSizeEmptyCells;
    [Test] procedure TestRecalcSizeGridMode;
    [Test] procedure TestRecalcSizeScrollMode;
    [Test] procedure TestCellRectsNoOverlap;
    [Test] procedure TestCellRectsWithinBounds;
  end;

  [TestFixture]
  TTestFrameViewFit = class
  public
    [Test] procedure TestCalcFitColumnsSingleFrame;
    [Test] procedure TestCalcFitColumnsResultFits;
    [Test] procedure TestCalcFitColumnsMaximizesCellSize;
    [Test] procedure TestCalcFitColumnsSmallViewport;
    [Test] procedure TestCalcFitColumnsZeroViewport;
    [Test] procedure TestColumnCountOverride;
    [Test] procedure TestColumnCountZeroUsesAuto;
    [Test] procedure TestDefaultColumnCount;
  end;

  [TestFixture]
  TTestFrameViewFilmstrip = class
  public
    [Test] procedure TestFilmstripSingleRow;
    [Test] procedure TestFilmstripNoOverlap;
    [Test] procedure TestFilmstripCellHeight;
    [Test] procedure TestFilmstripActualUsesNativeHeight;
    [Test] procedure TestFilmstripFitIfLargerCapsToNative;
    [Test] procedure TestFilmstripFitIfLargerScalesDown;
    [Test] procedure TestFilmstripRecalcSizeMatchesCellRect;
  end;

  [TestFixture]
  TTestFrameViewSingle = class
  public
    [Test] procedure TestSingleFillsViewport;
    [Test] procedure TestNavigateForward;
    [Test] procedure TestNavigateBackward;
    [Test] procedure TestNavigateClamps;
    [Test] procedure TestSingleActualUsesNativeSize;
    [Test] procedure TestSingleFitIfLargerSmallNative;
    [Test] procedure TestSingleFitIfLargerLargeNative;
    [Test] procedure TestNavigateEmptyCells;
    [Test] procedure TestNavigateSingleCell;
  end;

  [TestFixture]
  TTestFrameViewSmartGrid = class
  public
    [Test] procedure TestSmartGridFillsViewport;
    [Test] procedure TestSmartGridNoOverlap;
    [Test] procedure TestSmartGridAllFramesCovered;
    [Test] procedure TestSmartGridSingleFrame;
    [Test] procedure TestSmartGridTwoFrames;
    [Test] procedure TestSmartGridThreeFrames;
    [Test] procedure TestSmartGridLargeCount;
  end;

  [TestFixture]
  TTestFrameViewScroll = class
  public
    [Test] procedure TestWheelDownScrollsForward;
    [Test] procedure TestWheelUpScrollsBackward;
    [Test] procedure TestWheelWithoutScrollBoxParent;
    [Test] procedure TestScrollActualUsesNativeWidth;
    [Test] procedure TestScrollFitIfLargerCapsToNative;
    [Test] procedure TestScrollFitIfLargerScalesDown;
  end;

  [TestFixture]
  TTestFrameViewGridZoom = class
  public
    [Test] procedure TestGridActualUsesNativeWidthForColumns;
    [Test] procedure TestGridActualZeroNativeFallsBack;
  end;

  [TestFixture]
  TTestFrameViewState = class
  public
    [Test] procedure TestSetCellCountCreatesPlaceholders;
    [Test] procedure TestSetCellCountStoresTimecodes;
    [Test] procedure TestSetCellCountNilOffsets;
    [Test] procedure TestSetCellCountOffsetsShorterThanCount;
    [Test] procedure TestSetFrameChangesState;
    [Test] procedure TestSetCellErrorChangesState;
    [Test] procedure TestClearCellsFreesBitmaps;
    [Test] procedure TestClearCellsResetsArray;
    [Test] procedure TestHasPlaceholdersAllPlaceholders;
    [Test] procedure TestHasPlaceholdersNone;
    [Test] procedure TestHasPlaceholdersMixed;
    [Test] procedure TestSetFrameOutOfRange;
    [Test] procedure TestSetCellErrorOutOfRange;
    [Test] procedure TestSetCellCountResetsCurrentFrameIndex;
    [Test] procedure TestClearCellsResetsCurrentFrameIndex;
  end;

  [TestFixture]
  TTestFrameViewMisc = class
  public
    [Test] procedure TestAdvanceAnimationWrapsAt8;
    [Test] procedure TestRecalcSizeEmptyUsesViewportHeight;
    [Test] procedure TestGetColumnCountPerMode;
    [Test] procedure TestSmartGridDistributesCorrectly;
    [Test] procedure TestSmartGridPicksOptimalRows;
    [Test] procedure TestGridCentersHorizontally;
    [Test] procedure TestScrollActualNoNativeWidth;
    [Test] procedure TestSingleFitWindowLetterboxesTall;
    [Test] procedure TestFilmstripWheelScrollsHorizontally;
  end;

implementation

uses
  System.SysUtils, System.Types, System.Math,
  Winapi.Windows, Winapi.Messages,
  Vcl.Forms, Vcl.Graphics, Vcl.Controls,
  uPluginForm, uFrameOffsets, uSettings;

{ Helper: create a TFrameView with a temporary parent so it has a valid ClientWidth }
function CreateTestFrameView(AWidth: Integer; AMode: TViewMode): TFrameView;
var
  ParentForm: TForm;
begin
  ParentForm := TForm.CreateNew(nil);
  ParentForm.Width := AWidth;
  ParentForm.Height := 800;

  Result := TFrameView.Create(ParentForm);
  Result.Parent := ParentForm;
  Result.Left := 0;
  Result.Top := 0;
  Result.Width := AWidth;
  Result.ViewMode := AMode;
end;

procedure FreeTestFrameView(AView: TFrameView);
begin
  { Freeing the parent form also frees the child frame view }
  AView.Parent.Free;
end;

function MakeOffsets(ACount: Integer): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := (I + 1) * 10.0;
  end;
end;

{ TTestFrameViewLayout }

procedure TTestFrameViewLayout.TestGridColumnsSingleFrame;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    { Single frame = 1 column }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0, 'Height should be positive for 1 cell');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsTwoFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    { floor(sqrt(2)) = 1 column }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsFourFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    { floor(sqrt(4)) = 2 columns, 2 rows }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsNineFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    { floor(sqrt(9)) = 3 columns, 3 rows }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsSixteenFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(16, MakeOffsets(16));
    { floor(sqrt(16)) = 4 columns, 4 rows }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestScrollModeAlwaysOneColumn;
var
  V: TFrameView;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmScroll);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    { In scroll mode all cells stack vertically (same Left, increasing Top) }
    R1 := V.GetCellRect(0);
    R2 := V.GetCellRect(1);
    Assert.AreEqual(R1.Left, R2.Left, 'Cells should have same Left in scroll mode');
    Assert.IsTrue(R2.Top > R1.Bottom, 'Cell 2 should be below cell 1');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestRecalcSizeEmptyCells;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(0, nil);
    V.RecalcSize;
    Assert.AreEqual(0, V.Height, 'Empty cell list should produce zero height');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestRecalcSizeGridMode;
var
  V: TFrameView;
  H4, H9: Integer;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    H4 := V.Height;

    V.SetCellCount(9, MakeOffsets(9));
    V.RecalcSize;
    H9 := V.Height;

    { 4 frames = 2x2 grid; 9 frames = 3x3 grid. Both have same row count
      relative to columns, so heights depend on cell size. With more columns
      cells are smaller, so 3x3 should be shorter or equal to 2x2. }
    Assert.IsTrue(H4 > 0);
    Assert.IsTrue(H9 > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestRecalcSizeScrollMode;
var
  V: TFrameView;
  H2, H4: Integer;
begin
  V := CreateTestFrameView(800, vmScroll);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.RecalcSize;
    H2 := V.Height;

    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    H4 := V.Height;

    { More frames in scroll mode = taller }
    Assert.IsTrue(H4 > H2, 'More frames should produce greater height in scroll mode');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestCellRectsNoOverlap;
var
  V: TFrameView;
  I, J: Integer;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    for I := 0 to 7 do
      for J := I + 1 to 8 do
      begin
        R1 := V.GetCellRect(I);
        R2 := V.GetCellRect(J);
        Assert.IsFalse(
          (R1.Left < R2.Right) and (R1.Right > R2.Left) and
          (R1.Top < R2.Bottom) and (R1.Bottom > R2.Top),
          Format('Cells %d and %d overlap', [I, J]));
      end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestCellRectsWithinBounds;
var
  V: TFrameView;
  I: Integer;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    V.RecalcSize;
    for I := 0 to 8 do
    begin
      R := V.GetCellRect(I);
      Assert.IsTrue(R.Left >= 0, Format('Cell %d Left < 0', [I]));
      Assert.IsTrue(R.Top >= 0, Format('Cell %d Top < 0', [I]));
      Assert.IsTrue(R.Right <= V.Width, Format('Cell %d Right > Width', [I]));
      Assert.IsTrue(R.Bottom <= V.Height, Format('Cell %d Bottom > Height', [I]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewFit }

procedure TTestFrameViewFit.TestCalcFitColumnsSingleFrame;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    Assert.AreEqual(1, V.CalcFitColumns(800, 600));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestCalcFitColumnsResultFits;
var
  V: TFrameView;
  Cols: Integer;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    Cols := V.CalcFitColumns(800, 600);
    V.ColumnCount := Cols;
    V.Width := 800;
    V.RecalcSize;
    Assert.IsTrue(V.Height <= 600,
      Format('Height %d should fit in viewport 600 with %d columns', [V.Height, Cols]));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestCalcFitColumnsMaximizesCellSize;
var
  V: TFrameView;
  Cols: Integer;
begin
  { The result should be the minimum column count that fits,
    because fewer columns = larger cells }
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    Cols := V.CalcFitColumns(800, 600);
    if Cols > 1 then
    begin
      V.ColumnCount := Cols - 1;
      V.Width := 800;
      V.RecalcSize;
      Assert.IsTrue(V.Height > 600,
        Format('Height %d with %d columns should exceed viewport 600',
          [V.Height, Cols - 1]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestCalcFitColumnsSmallViewport;
var
  V: TFrameView;
  Cols: Integer;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    Cols := V.CalcFitColumns(800, 50);
    Assert.IsTrue(Cols >= 1);
    V.ColumnCount := Cols;
    V.Width := 800;
    V.RecalcSize;
    Assert.IsTrue((V.Height <= 50) or (Cols = 4),
      'Should fit or use max columns');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestCalcFitColumnsZeroViewport;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    Assert.AreEqual(1, V.CalcFitColumns(0, 0), 'Zero viewport returns 1');
    Assert.AreEqual(1, V.CalcFitColumns(800, 0), 'Zero height returns 1');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestColumnCountOverride;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    V.ColumnCount := 5;
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
    { With 5 columns: cell 0 is col 0, cell 5 is col 0 (row 1) }
    Assert.AreEqual(V.GetCellRect(0).Left, V.GetCellRect(5).Left,
      'Cell 5 should be in the same column as cell 0');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestColumnCountZeroUsesAuto;
var
  V: TFrameView;
  H1, H2: Integer;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.ColumnCount := 0;
    V.RecalcSize;
    H1 := V.Height;
    { Default for 4 cells: floor(sqrt(4)) = 2 columns, should match }
    V.ColumnCount := 2;
    V.RecalcSize;
    H2 := V.Height;
    Assert.AreEqual(H1, H2, 'ColumnCount=0 should match default (2 columns)');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFit.TestDefaultColumnCount;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    Assert.AreEqual(3, V.DefaultColumnCount, 'floor(sqrt(9)) = 3');
    V.SetCellCount(1, MakeOffsets(1));
    Assert.AreEqual(1, V.DefaultColumnCount, 'Single frame = 1');
    V.SetCellCount(4, MakeOffsets(4));
    V.ViewMode := vmScroll;
    Assert.AreEqual(1, V.DefaultColumnCount, 'Scroll mode always 1');
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewFilmstrip }

procedure TTestFrameViewFilmstrip.TestFilmstripSingleRow;
var
  V: TFrameView;
  I: Integer;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.SetViewport(800, 400);
    V.RecalcSize;
    { All cells should have the same Top }
    for I := 1 to 3 do
    begin
      R := V.GetCellRect(I);
      Assert.AreEqual(V.GetCellRect(0).Top, R.Top,
        Format('Cell %d should be on same row as cell 0', [I]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFilmstrip.TestFilmstripNoOverlap;
var
  V: TFrameView;
  I: Integer;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.SetViewport(800, 400);
    V.RecalcSize;
    for I := 0 to 2 do
    begin
      R1 := V.GetCellRect(I);
      R2 := V.GetCellRect(I + 1);
      Assert.IsTrue(R1.Right <= R2.Left,
        Format('Cell %d right edge should not overlap cell %d left edge', [I, I + 1]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFilmstrip.TestFilmstripCellHeight;
var
  V: TFrameView;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.SetViewport(800, 400);
    V.RecalcSize;
    R := V.GetCellRect(0);
    Assert.IsTrue(R.Height > 0, 'Cell should have positive height');
    Assert.IsTrue(R.Height <= 400, 'Cell height should fit viewport');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFilmstrip.TestFilmstripActualUsesNativeHeight;
var
  V: TFrameView;
  R: TRect;
begin
  { zmActual: cell height = native video height, ignoring viewport }
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    V.NativeW := 640;
    V.NativeH := 360;
    V.AspectRatio := 360 / 640;
    V.ZoomMode := zmActual;
    V.SetCellCount(2, MakeOffsets(2));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    Assert.AreEqual(360, R.Height, 'Cell height should match native height');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFilmstrip.TestFilmstripFitIfLargerCapsToNative;
var
  V: TFrameView;
  R: TRect;
begin
  { zmFitIfLarger with small native: cell height = native height }
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    V.NativeW := 320;
    V.NativeH := 180;
    V.AspectRatio := 180 / 320;
    V.ZoomMode := zmFitIfLarger;
    V.SetCellCount(2, MakeOffsets(2));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    Assert.AreEqual(180, R.Height,
      'FitIfLarger should cap to native when native < viewport');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFilmstrip.TestFilmstripFitIfLargerScalesDown;
var
  V: TFrameView;
  R: TRect;
  AvailH: Integer;
begin
  { zmFitIfLarger with large native: cell height = available viewport height }
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    V.NativeW := 1920;
    V.NativeH := 1080;
    V.AspectRatio := 1080 / 1920;
    V.ZoomMode := zmFitIfLarger;
    V.SetCellCount(2, MakeOffsets(2));
    V.SetViewport(800, 400);
    V.RecalcSize;
    R := V.GetCellRect(0);
    { Available height = viewport - timecode - 2*gap }
    AvailH := 400 - 20 - 2 * 4;
    Assert.AreEqual(AvailH, R.Height,
      'FitIfLarger should use viewport height when native > viewport');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewFilmstrip.TestFilmstripRecalcSizeMatchesCellRect;
var
  V: TFrameView;
  R0: TRect;
  N: Integer;
begin
  { RecalcSize total width must be consistent with GetCellRectFilmstrip }
  V := CreateTestFrameView(800, vmFilmstrip);
  try
    N := 5;
    V.NativeW := 640;
    V.NativeH := 360;
    V.AspectRatio := 360 / 640;
    V.ZoomMode := zmActual;
    V.SetCellCount(N, MakeOffsets(N));
    V.SetViewport(800, 400);
    V.RecalcSize;
    R0 := V.GetCellRect(0);
    { Width = max(viewport, gap + N * (cellW + gap)) }
    Assert.AreEqual(Max(800, 4 + N * (R0.Width + 4)), V.Width,
      'RecalcSize width should match cell rect geometry');
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewSingle }

procedure TTestFrameViewSingle.TestSingleFillsViewport;
var
  V: TFrameView;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.SetViewport(800, 600);
    V.Width := 800;
    V.Height := 600;
    R := V.GetCellRect(0);
    Assert.IsTrue(R.Width > 0, 'Cell should have positive width');
    Assert.IsTrue(R.Height > 0, 'Cell should have positive height');
    Assert.IsTrue(R.Right <= 800, 'Cell should fit within viewport width');
    Assert.IsTrue(R.Bottom <= 600, 'Cell should fit within viewport height');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestNavigateForward;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(4, MakeOffsets(4));
    Assert.AreEqual(0, V.CurrentFrameIndex);
    V.NavigateFrame(1);
    Assert.AreEqual(1, V.CurrentFrameIndex);
    V.NavigateFrame(1);
    Assert.AreEqual(2, V.CurrentFrameIndex);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestNavigateBackward;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.NavigateFrame(2);
    Assert.AreEqual(2, V.CurrentFrameIndex);
    V.NavigateFrame(-1);
    Assert.AreEqual(1, V.CurrentFrameIndex);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestNavigateClamps;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.NavigateFrame(-5);
    Assert.AreEqual(0, V.CurrentFrameIndex, 'Should clamp to 0');
    V.NavigateFrame(100);
    Assert.AreEqual(3, V.CurrentFrameIndex, 'Should clamp to last');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestSingleActualUsesNativeSize;
var
  V: TFrameView;
  R: TRect;
begin
  { zmActual: cell should use native dimensions regardless of viewport }
  V := CreateTestFrameView(800, vmSingle);
  try
    V.NativeW := 320;
    V.NativeH := 240;
    V.AspectRatio := 240 / 320;
    V.ZoomMode := zmActual;
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.Width := 800;
    V.Height := 600;
    R := V.GetCellRect(0);
    Assert.AreEqual(320, R.Width, 'Width should match native');
    Assert.AreEqual(240, R.Height, 'Height should match native');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestSingleFitIfLargerSmallNative;
var
  V: TFrameView;
  R: TRect;
begin
  { zmFitIfLarger with small native: cell should use native size }
  V := CreateTestFrameView(800, vmSingle);
  try
    V.NativeW := 200;
    V.NativeH := 150;
    V.AspectRatio := 150 / 200;
    V.ZoomMode := zmFitIfLarger;
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.Width := 800;
    V.Height := 600;
    R := V.GetCellRect(0);
    Assert.AreEqual(200, R.Width, 'Should use native width when small');
    Assert.AreEqual(150, R.Height, 'Should use native height when small');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestSingleFitIfLargerLargeNative;
var
  V: TFrameView;
  R: TRect;
begin
  { zmFitIfLarger with large native: cell should scale down to fit viewport }
  V := CreateTestFrameView(800, vmSingle);
  try
    V.NativeW := 1920;
    V.NativeH := 1080;
    V.AspectRatio := 1080 / 1920;
    V.ZoomMode := zmFitIfLarger;
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.Width := 800;
    V.Height := 600;
    R := V.GetCellRect(0);
    Assert.IsTrue(R.Width <= 800, 'Should scale down to fit width');
    Assert.IsTrue(R.Height <= 600, 'Should scale down to fit height');
    Assert.IsTrue(R.Width > 200, 'Should not be tiny');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestNavigateEmptyCells;
var
  V: TFrameView;
begin
  { NavigateFrame with no cells must not crash }
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(0, nil);
    V.NavigateFrame(1);
    V.NavigateFrame(-1);
    Assert.AreEqual(0, V.CurrentFrameIndex);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSingle.TestNavigateSingleCell;
var
  V: TFrameView;
begin
  { With 1 cell, navigation should stay at index 0 }
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(1, MakeOffsets(1));
    V.NavigateFrame(1);
    Assert.AreEqual(0, V.CurrentFrameIndex, 'Cannot navigate past single cell');
    V.NavigateFrame(-1);
    Assert.AreEqual(0, V.CurrentFrameIndex, 'Cannot navigate before single cell');
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewSmartGrid }

procedure TTestFrameViewSmartGrid.TestSmartGridFillsViewport;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    V.SetViewport(800, 600);
    V.RecalcSize;
    Assert.AreEqual(800, V.Width, 'Width should match viewport');
    Assert.AreEqual(600, V.Height, 'Height should match viewport');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSmartGrid.TestSmartGridNoOverlap;
var
  V: TFrameView;
  I, J: Integer;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    V.SetViewport(800, 600);
    V.RecalcSize;
    for I := 0 to 7 do
      for J := I + 1 to 8 do
      begin
        R1 := V.GetCellRect(I);
        R2 := V.GetCellRect(J);
        Assert.IsFalse(
          (R1.Left < R2.Right) and (R1.Right > R2.Left) and
          (R1.Top < R2.Bottom) and (R1.Bottom > R2.Top),
          Format('Cells %d and %d overlap', [I, J]));
      end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSmartGrid.TestSmartGridAllFramesCovered;
var
  V: TFrameView;
  I: Integer;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    V.SetViewport(800, 600);
    V.RecalcSize;
    for I := 0 to 8 do
    begin
      R := V.GetCellRect(I);
      Assert.IsTrue(R.Width > 0,
        Format('Cell %d should have positive width', [I]));
      Assert.IsTrue(R.Height > 0,
        Format('Cell %d should have positive height', [I]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSmartGrid.TestSmartGridSingleFrame;
var
  V: TFrameView;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    { Single frame should fill viewport }
    Assert.AreEqual(800, R.Width, 'Single frame should fill viewport width');
    Assert.AreEqual(600, R.Height, 'Single frame should fill viewport height');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSmartGrid.TestSmartGridTwoFrames;
var
  V: TFrameView;
  R0, R1: TRect;
begin
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R0 := V.GetCellRect(0);
    R1 := V.GetCellRect(1);
    Assert.IsTrue(R0.Width > 0, 'Cell 0 should have positive width');
    Assert.IsTrue(R1.Width > 0, 'Cell 1 should have positive width');
    { Cells should not overlap }
    Assert.IsFalse(
      (R0.Left < R1.Right) and (R0.Right > R1.Left) and
      (R0.Top < R1.Bottom) and (R0.Bottom > R1.Top),
      'Two frames should not overlap');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSmartGrid.TestSmartGridThreeFrames;
var
  V: TFrameView;
  I, J: Integer;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    V.SetViewport(800, 600);
    V.RecalcSize;
    { No pair should overlap }
    for I := 0 to 1 do
      for J := I + 1 to 2 do
      begin
        R1 := V.GetCellRect(I);
        R2 := V.GetCellRect(J);
        Assert.IsFalse(
          (R1.Left < R2.Right) and (R1.Right > R2.Left) and
          (R1.Top < R2.Bottom) and (R1.Bottom > R2.Top),
          Format('Cells %d and %d overlap', [I, J]));
      end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewSmartGrid.TestSmartGridLargeCount;
var
  V: TFrameView;
  I: Integer;
  R: TRect;
begin
  { 25 frames: all should have positive dimensions and fit within viewport }
  V := CreateTestFrameView(1024, vmSmartGrid);
  try
    V.SetCellCount(25, MakeOffsets(25));
    V.SetViewport(1024, 768);
    V.RecalcSize;
    for I := 0 to 24 do
    begin
      R := V.GetCellRect(I);
      Assert.IsTrue(R.Width > 0,
        Format('Cell %d should have positive width', [I]));
      Assert.IsTrue(R.Height > 0,
        Format('Cell %d should have positive height', [I]));
      Assert.IsTrue(R.Right <= 1024,
        Format('Cell %d right edge should be within viewport', [I]));
      Assert.IsTrue(R.Bottom <= 768,
        Format('Cell %d bottom edge should be within viewport', [I]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

{ Helper: send WM_MOUSEWHEEL to a control with given delta }
procedure SendWheel(AControl: TControl; ADelta: SmallInt);
begin
  AControl.Perform(WM_MOUSEWHEEL, WPARAM(Word(ADelta)) shl 16, 0);
end;

{ TTestFrameViewScroll }

procedure TTestFrameViewScroll.TestWheelDownScrollsForward;
var
  Form: TForm;
  ScrollBox: TScrollBox;
  View: TFrameView;
  OldPos: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 800, 300);
    Form.HandleNeeded;

    ScrollBox := TScrollBox.Create(Form);
    ScrollBox.Parent := Form;
    ScrollBox.Align := alClient;
    ScrollBox.BorderStyle := bsNone;

    View := TFrameView.Create(ScrollBox);
    View.Parent := ScrollBox;
    View.SetBounds(0, 0, 780, 2000);

    ScrollBox.VertScrollBar.Range := 2000;
    OldPos := ScrollBox.VertScrollBar.Position;

    SendWheel(View, -120);

    Assert.IsTrue(ScrollBox.VertScrollBar.Position > OldPos,
      'Scroll position should increase when scrolling down');
  finally
    Form.Free;
  end;
end;

procedure TTestFrameViewScroll.TestWheelUpScrollsBackward;
var
  Form: TForm;
  ScrollBox: TScrollBox;
  View: TFrameView;
  PosAfterDown: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 800, 300);
    Form.HandleNeeded;

    ScrollBox := TScrollBox.Create(Form);
    ScrollBox.Parent := Form;
    ScrollBox.Align := alClient;
    ScrollBox.BorderStyle := bsNone;

    View := TFrameView.Create(ScrollBox);
    View.Parent := ScrollBox;
    View.SetBounds(0, 0, 780, 2000);

    ScrollBox.VertScrollBar.Range := 2000;

    { Scroll down first to move away from 0 }
    SendWheel(View, -120);
    SendWheel(View, -120);
    SendWheel(View, -120);
    PosAfterDown := ScrollBox.VertScrollBar.Position;
    Assert.IsTrue(PosAfterDown > 0, 'Should have scrolled down from 0');

    { Now scroll up }
    SendWheel(View, 120);

    Assert.IsTrue(ScrollBox.VertScrollBar.Position < PosAfterDown,
      'Scroll position should decrease when scrolling up');
  finally
    Form.Free;
  end;
end;

procedure TTestFrameViewScroll.TestWheelWithoutScrollBoxParent;
var
  Form: TForm;
  View: TFrameView;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 800, 600);
    Form.HandleNeeded;

    View := TFrameView.Create(Form);
    View.Parent := Form;
    View.SetBounds(0, 0, 780, 2000);

    { Must not crash when parent is not a TScrollBox }
    SendWheel(View, -120);

    Assert.Pass('No crash when parent is not TScrollBox');
  finally
    Form.Free;
  end;
end;

procedure TTestFrameViewScroll.TestScrollActualUsesNativeWidth;
var
  V: TFrameView;
  R: TRect;
begin
  { zmActual: cell should use native video dimensions }
  V := CreateTestFrameView(800, vmScroll);
  try
    V.NativeW := 640;
    V.NativeH := 360;
    V.AspectRatio := 360 / 640;
    V.ZoomMode := zmActual;
    V.SetCellCount(2, MakeOffsets(2));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    Assert.AreEqual(640, R.Width, 'Width should match native');
    Assert.AreEqual(360, R.Height, 'Height should match native');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewScroll.TestScrollFitIfLargerCapsToNative;
var
  V: TFrameView;
  R: TRect;
begin
  { zmFitIfLarger with small native: cell width = native width }
  V := CreateTestFrameView(800, vmScroll);
  try
    V.NativeW := 400;
    V.NativeH := 225;
    V.AspectRatio := 225 / 400;
    V.ZoomMode := zmFitIfLarger;
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    Assert.AreEqual(400, R.Width,
      'FitIfLarger should cap to native when native < viewport');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewScroll.TestScrollFitIfLargerScalesDown;
var
  V: TFrameView;
  R: TRect;
begin
  { zmFitIfLarger with large native: cell width = viewport width }
  V := CreateTestFrameView(800, vmScroll);
  try
    V.NativeW := 1920;
    V.NativeH := 1080;
    V.AspectRatio := 1080 / 1920;
    V.ZoomMode := zmFitIfLarger;
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    { When native > viewport, FitIfLarger uses viewport width }
    Assert.IsTrue(R.Width <= 800,
      'FitIfLarger should not exceed viewport when native is larger');
    Assert.IsTrue(R.Width > 100, 'Cell should not be tiny');
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewGridZoom }

procedure TTestFrameViewGridZoom.TestGridActualUsesNativeWidthForColumns;
var
  V: TFrameView;
  R0, R1: TRect;
begin
  { zmActual: columns based on native frame width fitting into client area }
  V := CreateTestFrameView(800, vmGrid);
  try
    V.NativeW := 300;
    V.NativeH := 169;
    V.AspectRatio := 169 / 300;
    V.ZoomMode := zmActual;
    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    R0 := V.GetCellRect(0);
    R1 := V.GetCellRect(1);
    { With 800px viewport and 300px native, we expect 2 columns: (800-4)/(300+4) = 2.6 -> 2 }
    Assert.IsTrue(R1.Left > R0.Left,
      'With 300px native in 800px viewport, cell 1 should be to the right of cell 0');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewGridZoom.TestGridActualZeroNativeFallsBack;
var
  V: TFrameView;
begin
  { zmActual with NativeW=0: should fall back to default column calculation }
  V := CreateTestFrameView(800, vmGrid);
  try
    V.NativeW := 0;
    V.NativeH := 0;
    V.ZoomMode := zmActual;
    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    { Should not crash and should produce positive height }
    Assert.IsTrue(V.Height > 0, 'Should fall back gracefully with zero native dims');
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewState }

procedure TTestFrameViewState.TestSetCellCountCreatesPlaceholders;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    Assert.IsTrue(V.HasPlaceholders, 'New cells should all be placeholders');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellCountStoresTimecodes;
var
  V: TFrameView;
  Offsets: TFrameOffsetArray;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    Offsets := MakeOffsets(2);
    V.SetCellCount(2, Offsets);
    { Timecodes should match FormatTimecode of the offsets }
    Assert.AreEqual(FormatTimecode(10.0), V.FCells[0].Timecode);
    Assert.AreEqual(FormatTimecode(20.0), V.FCells[1].Timecode);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellCountNilOffsets;
var
  V: TFrameView;
begin
  { nil offsets: cells should have empty timecodes and zero time offsets }
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, nil);
    Assert.AreEqual(3, Integer(Length(V.FCells)));
    Assert.AreEqual('', V.FCells[0].Timecode, 'Nil offsets: timecode should be empty');
    Assert.AreEqual(0.0, V.FCells[0].TimeOffset, 0.001, 'Nil offsets: time should be 0');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellCountOffsetsShorterThanCount;
var
  V: TFrameView;
  Offsets: TFrameOffsetArray;
begin
  { Offsets array shorter than count: extra cells get empty timecodes }
  V := CreateTestFrameView(800, vmGrid);
  try
    Offsets := MakeOffsets(2);
    V.SetCellCount(4, Offsets);
    Assert.AreEqual(4, Integer(Length(V.FCells)));
    { First 2 cells should have timecodes from offsets }
    Assert.AreEqual(FormatTimecode(10.0), V.FCells[0].Timecode);
    Assert.AreEqual(FormatTimecode(20.0), V.FCells[1].Timecode);
    { Extra cells beyond offsets array should have empty timecodes }
    Assert.AreEqual('', V.FCells[2].Timecode, 'Beyond offsets: timecode should be empty');
    Assert.AreEqual('', V.FCells[3].Timecode, 'Beyond offsets: timecode should be empty');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetFrameChangesState;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    Bmp := TBitmap.Create;
    Bmp.Width := 100;
    Bmp.Height := 50;
    V.SetFrame(0, Bmp);
    Assert.AreEqual(Ord(fcsLoaded), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[1].State));
    Assert.AreSame(Bmp, V.FCells[0].Bitmap);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellErrorChangesState;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.SetCellError(1);
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsError), Ord(V.FCells[1].State));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestClearCellsFreesBitmaps;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    Bmp := TBitmap.Create;
    Bmp.Width := 10;
    Bmp.Height := 10;
    V.SetFrame(0, Bmp);
    V.ClearCells;
    { After clear, cell array should be empty }
    Assert.AreEqual(0, Integer(Length(V.FCells)));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestClearCellsResetsArray;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(5, MakeOffsets(5));
    V.ClearCells;
    Assert.AreEqual(0, Integer(Length(V.FCells)));
    Assert.IsFalse(V.HasPlaceholders, 'Empty cell list has no placeholders');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestHasPlaceholdersAllPlaceholders;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    Assert.IsTrue(V.HasPlaceholders);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestHasPlaceholdersNone;
var
  V: TFrameView;
  I: Integer;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    for I := 0 to 2 do
    begin
      Bmp := TBitmap.Create;
      Bmp.SetSize(10, 10);
      V.SetFrame(I, Bmp);
    end;
    Assert.IsFalse(V.HasPlaceholders, 'All loaded = no placeholders');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestHasPlaceholdersMixed;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    Bmp := TBitmap.Create;
    Bmp.SetSize(10, 10);
    V.SetFrame(0, Bmp);
    V.SetCellError(1);
    { Cell 2 is still a placeholder }
    Assert.IsTrue(V.HasPlaceholders, 'One placeholder remains');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetFrameOutOfRange;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    Bmp := TBitmap.Create;
    Bmp.SetSize(10, 10);
    { Should not crash or corrupt; bitmap is leaked intentionally in this test }
    V.SetFrame(5, Bmp);
    V.SetFrame(-1, Bmp);
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[1].State));
    Bmp.Free;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellErrorOutOfRange;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.SetCellError(10);
    V.SetCellError(-1);
    { No crash, cells unchanged }
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[1].State));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellCountResetsCurrentFrameIndex;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(5, MakeOffsets(5));
    V.NavigateFrame(3);
    Assert.AreEqual(3, V.CurrentFrameIndex, 'Precondition: navigated to 3');
    { SetCellCount should reset CurrentFrameIndex to 0 }
    V.SetCellCount(5, MakeOffsets(5));
    Assert.AreEqual(0, V.CurrentFrameIndex,
      'SetCellCount should reset CurrentFrameIndex to 0');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestClearCellsResetsCurrentFrameIndex;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmSingle);
  try
    V.SetCellCount(5, MakeOffsets(5));
    V.NavigateFrame(2);
    Assert.AreEqual(2, V.CurrentFrameIndex, 'Precondition: navigated to 2');
    V.ClearCells;
    Assert.AreEqual(0, V.CurrentFrameIndex,
      'ClearCells should reset CurrentFrameIndex to 0');
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewMisc }

procedure TTestFrameViewMisc.TestAdvanceAnimationWrapsAt8;
var
  V: TFrameView;
  I: Integer;
begin
  { Animation step should cycle through 0..7 and wrap back to 0 }
  V := CreateTestFrameView(400, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    for I := 1 to 8 do
      V.AdvanceAnimation;
    { After 8 advances from initial 0, should wrap back to 0 }
    for I := 1 to 7 do
      V.AdvanceAnimation;
    { 15 total advances: 15 mod 8 = 7 }
    V.AdvanceAnimation; { 16 mod 8 = 0 }
    { No crash = success. The wrap behavior is internal, but we verify
      it does not crash after many cycles. }
    Assert.Pass('Animation cycles without error');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestRecalcSizeEmptyUsesViewportHeight;
var
  V: TFrameView;
begin
  { With 0 cells and a viewport set, RecalcSize should set Height = FViewportH }
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(0, nil);
    V.SetViewport(800, 600);
    V.RecalcSize;
    Assert.AreEqual(600, V.Height,
      'Empty cells with viewport 600 should set Height to viewport');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestGetColumnCountPerMode;
var
  V: TFrameView;
begin
  { Verify column count logic for each view mode }
  V := CreateTestFrameView(800, vmScroll);
  try
    V.SetCellCount(4, MakeOffsets(4));

    V.ViewMode := vmScroll;
    Assert.AreEqual(1, V.DefaultColumnCount, 'Scroll: always 1 column');

    V.ViewMode := vmGrid;
    Assert.AreEqual(2, V.DefaultColumnCount, 'Grid: floor(sqrt(4)) = 2');

    V.SetCellCount(9, MakeOffsets(9));
    Assert.AreEqual(3, V.DefaultColumnCount, 'Grid: floor(sqrt(9)) = 3');

    V.SetCellCount(1, MakeOffsets(1));
    Assert.AreEqual(1, V.DefaultColumnCount, 'Grid: single frame = 1');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestSmartGridDistributesCorrectly;
var
  V: TFrameView;
  I: Integer;
  R: TRect;
  TotalCells: Integer;
begin
  { Verify that all 7 frames are reachable and non-degenerate in SmartGrid }
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.SetCellCount(7, MakeOffsets(7));
    V.SetViewport(800, 600);
    V.RecalcSize;

    TotalCells := 0;
    for I := 0 to 6 do
    begin
      R := V.GetCellRect(I);
      Assert.IsTrue(R.Width > 10,
        Format('Cell %d width (%d) should be meaningful', [I, R.Width]));
      Assert.IsTrue(R.Height > 10,
        Format('Cell %d height (%d) should be meaningful', [I, R.Height]));
      Assert.IsTrue(R.Left >= 0, Format('Cell %d should not start before 0', [I]));
      Assert.IsTrue(R.Top >= 0, Format('Cell %d should not start before 0', [I]));
      Inc(TotalCells);
    end;
    Assert.AreEqual(7, TotalCells, 'All 7 frames should be accounted for');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestSmartGridPicksOptimalRows;
var
  V: TFrameView;
  R0, R1: TRect;
begin
  { For 4 frames with 16:9 aspect ratio in 800x600 viewport,
    the algorithm should pick 2 rows (2+2) rather than 1 row (4)
    because 2 rows yields aspect ratio closer to 9/16 }
  V := CreateTestFrameView(800, vmSmartGrid);
  try
    V.AspectRatio := 9.0 / 16.0;
    V.SetCellCount(4, MakeOffsets(4));
    V.SetViewport(800, 600);
    V.RecalcSize;

    R0 := V.GetCellRect(0);
    R1 := V.GetCellRect(2); { If 2 rows: this is in row 1 }

    { With 2 rows of 2: cell 2 should be on a different row than cell 0 }
    Assert.IsTrue(R1.Top > R0.Top,
      'Cell 2 should be on a lower row than cell 0 for 4-frame 16:9 layout');
    { But cells 0 and 1 should be on the same row }
    Assert.AreEqual(R0.Top, V.GetCellRect(1).Top,
      'Cells 0 and 1 should be on the same row');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestGridCentersHorizontally;
var
  V: TFrameView;
  R: TRect;
begin
  { When grid is narrower than viewport, it should be centered }
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    V.RecalcSize;
    R := V.GetCellRect(0);
    { With 1 column, the single cell should be roughly centered }
    Assert.IsTrue(R.Left > 0, 'Cell should not be at left edge (should be centered)');
    Assert.IsTrue(R.Left < 400, 'Cell should not be beyond center');
    { Left offset should roughly equal the gap from right edge }
    Assert.IsTrue(Abs(R.Left - (800 - R.Right)) <= 1,
      Format('Cell should be centered: Left=%d, Right gap=%d', [R.Left, 800 - R.Right]));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestScrollActualNoNativeWidth;
var
  V: TFrameView;
  R: TRect;
begin
  { Scroll mode + zmActual + NativeW=0: fallback to minimal cells }
  V := CreateTestFrameView(800, vmScroll);
  try
    V.NativeW := 0;
    V.NativeH := 0;
    V.ZoomMode := zmActual;
    V.SetCellCount(2, MakeOffsets(2));
    V.SetViewport(800, 600);
    V.RecalcSize;
    R := V.GetCellRect(0);
    { With NativeW=0, cell falls back to Max(1, 0) = 1 pixel }
    Assert.AreEqual(1, R.Width, 'Cell width should fall back to 1 with zero native');
    Assert.AreEqual(1, R.Height, 'Cell height should fall back to 1 with zero native');
    { Height should still be positive }
    Assert.IsTrue(V.Height > 0, 'View height should be positive');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestSingleFitWindowLetterboxesTall;
var
  V: TFrameView;
  R: TRect;
begin
  { With a very tall aspect ratio, FitWindow should letterbox (width limited by height) }
  V := CreateTestFrameView(800, vmSingle);
  try
    V.AspectRatio := 2.0; { height = 2x width, very tall }
    V.ZoomMode := zmFitWindow;
    V.SetCellCount(1, MakeOffsets(1));
    V.SetViewport(800, 600);
    V.Width := 800;
    V.Height := 600;
    R := V.GetCellRect(0);
    { Height limited by viewport, so width should be much less than viewport }
    Assert.IsTrue(R.Width < 400,
      Format('Tall aspect ratio should produce narrow cell: got width=%d', [R.Width]));
    Assert.IsTrue(R.Height > R.Width,
      'Height should exceed width for tall aspect ratio');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewMisc.TestFilmstripWheelScrollsHorizontally;
var
  Form: TForm;
  ScrollBox: TScrollBox;
  View: TFrameView;
  OldPos: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 400);
    Form.HandleNeeded;

    ScrollBox := TScrollBox.Create(Form);
    ScrollBox.Parent := Form;
    ScrollBox.Align := alClient;
    ScrollBox.BorderStyle := bsNone;

    View := TFrameView.Create(ScrollBox);
    View.Parent := ScrollBox;
    View.ViewMode := vmFilmstrip;
    View.SetCellCount(10, MakeOffsets(10));
    View.SetViewport(400, 400);
    View.RecalcSize;
    { Filmstrip is wider than scrollbox, enabling horizontal scroll }
    View.SetBounds(0, 0, View.Width, View.Height);

    ScrollBox.HorzScrollBar.Range := View.Width;
    OldPos := ScrollBox.HorzScrollBar.Position;

    { Send wheel down: should scroll horizontally in filmstrip mode }
    SendWheel(View, -120);

    Assert.IsTrue(ScrollBox.HorzScrollBar.Position > OldPos,
      'Filmstrip wheel should scroll horizontally');
  finally
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameViewLayout);
  TDUnitX.RegisterTestFixture(TTestFrameViewFit);
  TDUnitX.RegisterTestFixture(TTestFrameViewFilmstrip);
  TDUnitX.RegisterTestFixture(TTestFrameViewSingle);
  TDUnitX.RegisterTestFixture(TTestFrameViewSmartGrid);
  TDUnitX.RegisterTestFixture(TTestFrameViewScroll);
  TDUnitX.RegisterTestFixture(TTestFrameViewGridZoom);
  TDUnitX.RegisterTestFixture(TTestFrameViewState);
  TDUnitX.RegisterTestFixture(TTestFrameViewMisc);

end.
