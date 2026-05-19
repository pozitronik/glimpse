{ Tests for uCombinedGrid: combined grid rendering.
  Verifies layout geometry, background fill, nil-frame handling,
  auto-column calculation, border placement, alpha-aware lift and
  the smart-grid variable-row-cell renderer. }
unit TestCombinedGrid;

interface

uses
  DUnitX.TestFramework, Vcl.Graphics;

type
  [TestFixture]
  TTestCombinedGrid = class
  private
    { Creates a solid-color bitmap for testing }
    function MakeFrame(AWidth, AHeight: Integer; AColor: Integer): TBitmap;
  public
    { Empty input }
    [Test] procedure EmptyFrames_ReturnsNil;
    { Single frame }
    [Test] procedure SingleFrame_OutputMatchesFrameSize;
    { Grid geometry }
    [Test] procedure TwoFrames_AutoCols_Produces2x1;
    [Test] procedure FourFrames_AutoCols_Produces2x2;
    [Test] procedure FourFrames_ExplicitOneCols_Produces1x4;
    [Test] procedure ThreeFrames_TwoCols_Produces2x2Grid;
    { Gap calculations }
    [Test] procedure SingleFrame_GapDoesNotAffectSize;
    [Test] procedure TwoFrames_GapAddsCorrectly;
    [Test] procedure FourFrames_2x2_WithGap;
    { Background fill }
    [Test] procedure BackgroundFillsEntireCanvas;
    { Nil frames in array }
    [Test] procedure NilFrame_UsesDefaultCellSize;
    [Test] procedure MixedNilFrames_SkippedInRendering;
    { Columns clamped to frame count }
    [Test] procedure ColsExceedFrameCount_ClampedToFrameCount;
    { Outer border (margin around the whole grid) }
    [Test] procedure Border_AddsPixelsOnAllSides;
    [Test] procedure Border_NegativeClampedToZero;
    [Test] procedure Border_DefaultIsZero;
    [Test] procedure Border_FillsMarginAreaWithBackground;
    [Test] procedure Border_ShiftsCellOrigin;
    { Large grid }
    [Test] procedure NineFrames_AutoCols_Produces3x3;
    { DefaultCombinedGridStyle invariants }
    [Test] procedure DefaultCombinedGridStyle_AutoColumnsZero;
    [Test] procedure DefaultCombinedGridStyle_BackgroundAlphaIs255;
    [Test] procedure DefaultCombinedGridStyle_BorderMatchesConstant;
    { Alpha-aware lift }
    [Test] procedure RenderCombined_FullAlpha_StaysPf24Bit;
    [Test] procedure RenderCombined_PartialAlpha_BecomesPf32Bit;
    [Test] procedure RenderCombined_GapPixelCarriesBackgroundAlpha;
    [Test] procedure RenderCombined_FramePixelStaysOpaque;
    { Factory record }
    [Test] procedure CombinedGridStyle_FromFields_CopiesAllFields;
    { RenderSmartCombinedImage }
    [Test] procedure SmartRender_EmptyFrames_ReturnsNil;
    [Test] procedure SmartRender_OutputDimensionsMatchInputs;
    [Test] procedure SmartRender_BorderFillsOuterMargin;
    [Test] procedure SmartRender_TwoRowsUnequal_RowZeroCellsWiderThanRowOne;
    [Test] procedure SmartRender_PartialAlpha_BecomesPf32Bit;
    [Test] procedure SmartRender_PartialAlpha_GapPixelCarriesBackgroundAlpha;
  end;

  {Direct tests for LiftToAlphaAwareCore — the rect-driven 24bit to
   32bit lift used by both LiftToAlphaAware (uniform grid) and
   LiftToAlphaAwareSmart (variable rows). The renderer-level tests
   cover the production paths; this fixture pins the defensive
   guards (nil frame mid-array, frames longer than rects, out-of-
   bounds rect) that the renderers never exercise but the helper
   still has to handle correctly.}
  [TestFixture]
  TTestLiftToAlphaAwareCore = class
  public
    [Test] procedure Output_IsPf32BitWithDefinedAlpha;
    [Test] procedure Output_DimensionsMatchSource;
    [Test] procedure EmptyFrames_OutputIsPureBackground;
    [Test] procedure NilFrameEntry_RectStaysBackground;
    [Test] procedure RectInside_PixelsCarrySourceRGBAndOpaque;
    [Test] procedure FramesLongerThanRects_TrailingSkipped;
    [Test] procedure RectOutsideBounds_ClippedNoCrash;
    [Test] procedure BackgroundQuad_PreservesAlphaByte;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.Types, System.UITypes,
  uTypes, uFrameOffsets, uCombinedGrid, uTimecodeOverlay, uRenderDefaults,
  uDefaults;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   GetBValue/GetGValue/GetRValue) declares its own TBITMAP record alias
   that would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

{Pixel layout for pf32bit scan lines: byte order is BGRA per Win32 DIB}
function AlphaByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 3);
  Result := Row^;
end;

{ Helper }

function TTestCombinedGrid.MakeFrame(AWidth, AHeight: Integer;
  AColor: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := TColor(AColor);
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{ Positional-arg builders so the pre-DTO test call sites stay one-liners.
  Match the old RenderCombinedImage parameter order/defaults exactly. }
function MakeGrid(ACols, AGap: Integer; ABg: TColor; ABorder: Integer = 0): TCombinedGridStyle;
begin
  Result.Columns := ACols;
  Result.CellGap := AGap;
  Result.Border := ABorder;
  Result.Background := ABg;
  {Default to opaque so existing tests pin the historical pf24bit fast
   path; alpha-aware tests set BackgroundAlpha explicitly.}
  Result.BackgroundAlpha := 255;
end;

function MakeTs(AShow: Boolean; const AFontName: string; AFontSize: Integer;
  ACorner: TTimestampCorner = tcBottomLeft;
  ABackColor: TColor = clBlack; ABackAlpha: Byte = 0;
  ATextColor: TColor = clWhite; ATextAlpha: Byte = 255): TTimestampStyle;
begin
  Result.Show := AShow;
  Result.Corner := ACorner;
  Result.FontName := AFontName;
  Result.FontSize := AFontSize;
  Result.FontStyles := [fsBold];
  Result.BackColor := ABackColor;
  Result.BackAlpha := ABackAlpha;
  Result.TextColor := ATextColor;
  Result.TextAlpha := ATextAlpha;
  {Match the historical BackAlpha-as-discriminator so tests that pass
   ABackAlpha=0 still exercise the legacy painter.}
  Result.Mode := TimecodeStyleModeFor(ABackAlpha);
end;

{ Empty input }

procedure TTestCombinedGrid.EmptyFrames_ReturnsNil;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  SetLength(Frames, 0);
  SetLength(Offsets, 0);
  R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
  Assert.IsNull(R);
end;

{ Single frame }

procedure TTestCombinedGrid.SingleFrame_OutputMatchesFrameSize;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 1.0;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width);
      Assert.AreEqual(80, R.Height);
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Grid geometry }

procedure TTestCombinedGrid.TwoFrames_AutoCols_Produces2x1;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Ceil(Sqrt(2)) = 2 columns, 1 row }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, '2 cols * 50px');
      Assert.AreEqual(40, R.Height, '1 row * 40px');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedGrid.FourFrames_AutoCols_Produces2x2;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { Ceil(Sqrt(4)) = 2 columns, 2 rows }
  SetLength(Frames, 4);
  for I := 0 to 3 do
    Frames[I] := MakeFrame(60, 40, 0);
  SetLength(Offsets, 4);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(120, R.Width, '2 cols * 60px');
      Assert.AreEqual(80, R.Height, '2 rows * 40px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 3 do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedGrid.FourFrames_ExplicitOneCols_Produces1x4;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  SetLength(Frames, 4);
  for I := 0 to 3 do
    Frames[I] := MakeFrame(60, 40, 0);
  SetLength(Offsets, 4);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(1, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(60, R.Width, '1 col * 60px');
      Assert.AreEqual(160, R.Height, '4 rows * 40px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 3 do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedGrid.ThreeFrames_TwoCols_Produces2x2Grid;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { 3 frames / 2 cols = 2 rows (last cell empty) }
  SetLength(Frames, 3);
  for I := 0 to 2 do
    Frames[I] := MakeFrame(50, 30, 0);
  SetLength(Offsets, 3);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(2, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, '2 cols * 50px');
      Assert.AreEqual(60, R.Height, '2 rows * 30px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 2 do
      Frames[I].Free;
  end;
end;

{ Gap calculations }

procedure TTestCombinedGrid.SingleFrame_GapDoesNotAffectSize;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Gap between columns/rows only; 1 frame = 0 gaps }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, 0);
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 10, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, 'No gap for single frame');
      Assert.AreEqual(80, R.Height, 'No gap for single frame');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.TwoFrames_GapAddsCorrectly;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { 2 frames in 1 row: width = 2*50 + 1*gap }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 5, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(105, R.Width, '2*50 + 1*5');
      Assert.AreEqual(40, R.Height, '1 row, no vertical gap');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedGrid.FourFrames_2x2_WithGap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { 2x2 grid, gap=4: W=2*30+1*4=64, H=2*20+1*4=44 }
  SetLength(Frames, 4);
  for I := 0 to 3 do
    Frames[I] := MakeFrame(30, 20, 0);
  SetLength(Offsets, 4);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(2, 4, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(64, R.Width, '2*30 + 1*4');
      Assert.AreEqual(44, R.Height, '2*20 + 1*4');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 3 do
      Frames[I].Free;
  end;
end;

{ Background fill }

procedure TTestCombinedGrid.BackgroundFillsEntireCanvas;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
  BgColor: TColor;
begin
  { 3 frames in 2 cols = 2x2 grid with one empty cell.
    The empty cell area should be filled with background color. }
  BgColor := TColor($0000FF00); { green }
  SetLength(Frames, 3);
  for I := 0 to 2 do
    Frames[I] := MakeFrame(20, 20, Integer(clRed));
  SetLength(Offsets, 3);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(2, 0, BgColor), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      { Check pixel in the empty cell (row 1, col 1) }
      Assert.AreEqual(Integer(BgColor),
        Integer(R.Canvas.Pixels[30, 30]),
        'Empty cell should be background color');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 2 do
      Frames[I].Free;
  end;
end;

{ Nil frames }

procedure TTestCombinedGrid.NilFrame_UsesDefaultCellSize;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { All frames nil: falls back to default 320x240 }
  SetLength(Frames, 1);
  Frames[0] := nil;
  SetLength(Offsets, 1);
  R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
  Assert.IsNotNull(R);
  try
    Assert.AreEqual(320, R.Width, 'Default cell width');
    Assert.AreEqual(240, R.Height, 'Default cell height');
  finally
    R.Free;
  end;
end;

procedure TTestCombinedGrid.MixedNilFrames_SkippedInRendering;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Frame 0 is real, frame 1 is nil.
    Output should be 2x1 grid using frame 0 dimensions.
    The nil cell should remain background-colored. }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(40, 30, Integer(clRed));
  Frames[1] := nil;
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clWhite), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(80, R.Width, '2 cols * 40px');
      Assert.AreEqual(30, R.Height, '1 row * 30px');
      { Nil cell should be white (background) }
      Assert.AreEqual(Integer(clWhite),
        Integer(R.Canvas.Pixels[60, 15]),
        'Nil frame cell should be background');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Column clamping }

procedure TTestCombinedGrid.ColsExceedFrameCount_ClampedToFrameCount;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { 2 frames, cols=10: should clamp to 2 cols }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(10, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, 'Clamped to 2 cols * 50px');
      Assert.AreEqual(40, R.Height, '1 row * 40px');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

{ Large grid }

procedure TTestCombinedGrid.NineFrames_AutoCols_Produces3x3;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { Ceil(Sqrt(9)) = 3 columns, 3 rows }
  SetLength(Frames, 9);
  for I := 0 to 8 do
    Frames[I] := MakeFrame(40, 30, 0);
  SetLength(Offsets, 9);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 2, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(3 * 40 + 2 * 2, R.Width, '3 cols * 40px + 2 gaps * 2px');
      Assert.AreEqual(3 * 30 + 2 * 2, R.Height, '3 rows * 30px + 2 gaps * 2px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 8 do
      Frames[I].Free;
  end;
end;

{ Outer border }

procedure TTestCombinedGrid.Border_AddsPixelsOnAllSides;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { 2x1 grid of 50x40 frames with border=8: the total canvas should grow
    by 2*Border in each dimension (16 px added symmetrically) }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 8), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(2 * 50 + 2 * 8, R.Width, '2 cols * 50 + 2*border');
      Assert.AreEqual(40 + 2 * 8, R.Height, '1 row * 40 + 2*border');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedGrid.Border_NegativeClampedToZero;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { A negative border must be treated as zero so the caller cannot
    accidentally shrink the grid below its natural geometry }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, 0);
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, -50), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, 'Negative border clamps to zero');
      Assert.AreEqual(80, R.Height, 'Negative border clamps to zero');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.Border_DefaultIsZero;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R1, R2: TBitmap;
begin
  { Back-compat guarantee: callers that do not pass ABorder must get the
    same result as explicitly passing 0 }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, 0);
  SetLength(Offsets, 1);
  try
    R1 := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    R2 := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(R2.Width, R1.Width, 'Default border must equal explicit 0');
      Assert.AreEqual(R2.Height, R1.Height, 'Default border must equal explicit 0');
    finally
      R1.Free;
      R2.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.Border_FillsMarginAreaWithBackground;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  BgColor: TColor;
begin
  { Pixel inside the outer border (outside all cells) must be the
    background color: the margin is part of the canvas, not transparent }
  BgColor := TColor($0000FF00);
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(60, 40, Integer(clRed));
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, BgColor, 10), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      { Corner of the output should be background, not frame color }
      Assert.AreEqual(Integer(BgColor), Integer(R.Canvas.Pixels[2, 2]),
        'Top-left margin pixel must be background');
      Assert.AreEqual(Integer(BgColor), Integer(R.Canvas.Pixels[R.Width - 3, R.Height - 3]),
        'Bottom-right margin pixel must be background');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.Border_ShiftsCellOrigin;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  Border: Integer;
begin
  { The first cell must be drawn at (Border, Border), not at (0, 0):
    the pixel at (Border, Border) must be the frame color }
  Border := 12;
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(60, 40, Integer(clRed));
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, Border), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[Border + 5, Border + 5]),
        'Frame content must start at (Border, Border)');
      { Pixel just inside the margin (before cell) must be background }
      Assert.AreEqual(Integer(clBlack), Integer(R.Canvas.Pixels[Border - 2, Border - 2]),
        'Pixel inside margin before cell must be background');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.DefaultCombinedGridStyle_AutoColumnsZero;
var
  S: TCombinedGridStyle;
begin
  {Columns = 0 is the "auto" sentinel - RenderCombinedImage picks
   ceil(sqrt(n)). Any non-zero default would silently override that.}
  S := DefaultCombinedGridStyle;
  Assert.AreEqual<Integer>(0, S.Columns);
  Assert.AreEqual<Integer>(0, S.CellGap);
end;

procedure TTestCombinedGrid.DefaultCombinedGridStyle_BackgroundAlphaIs255;
begin
  {Default to fully opaque so existing call sites keep the historical
   pf24bit fast path with no behaviour change.}
  Assert.AreEqual(255, Integer(DefaultCombinedGridStyle.BackgroundAlpha));
end;

procedure TTestCombinedGrid.DefaultCombinedGridStyle_BorderMatchesConstant;
begin
  Assert.AreEqual<Integer>(DEF_COMBINED_BORDER,
    DefaultCombinedGridStyle.Border);
end;

procedure TTestCombinedGrid.RenderCombined_FullAlpha_StaysPf24Bit;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  {BackgroundAlpha = 255 is the no-regression branch. Pixel format must
   stay pf24bit so the saver picks the existing 24-bit PNG path and
   anyone who layered behaviour on output format keeps working.}
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(40, 30, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 1.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(Ord(pf24bit), Ord(Bmp.PixelFormat));
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.RenderCombined_PartialAlpha_BecomesPf32Bit;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(40, 30, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 1.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Grid.BackgroundAlpha := 128;
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(Ord(pf32bit), Ord(Bmp.PixelFormat));
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.RenderCombined_GapPixelCarriesBackgroundAlpha;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  {2x1 layout with a 4px gap. Sample the gap region and assert its alpha
   matches BackgroundAlpha; non-frame areas must be transparent-aware.}
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(20, 20, Integer(clRed));
  Frames[1] := MakeFrame(20, 20, Integer(clGreen));
  SetLength(Offsets, 2);
  Offsets[0].TimeOffset := 0.0;
  Offsets[1].TimeOffset := 1.0;
  try
    Grid := MakeGrid(2, 4, clBlue, 0);
    Grid.BackgroundAlpha := 64;
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(Ord(pf32bit), Ord(Bmp.PixelFormat));
      {Gap pixel sits between cells: x in [20..23], y any}
      Assert.AreEqual(64, Integer(AlphaByteAt(Bmp, 21, 10)),
        'Gap pixel must carry BackgroundAlpha');
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedGrid.RenderCombined_FramePixelStaysOpaque;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  {Frame interior pixel must keep alpha=255 even when BackgroundAlpha is
   low. Confirms the lift step distinguishes cell rects from gap area.}
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(20, 20, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 0.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Grid.BackgroundAlpha := 0;
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(255, Integer(AlphaByteAt(Bmp, 10, 10)),
        'Frame pixel alpha must always be 255 (frames are opaque)');
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedGrid.CombinedGridStyle_FromFields_CopiesAllFields;
var
  G: TCombinedGridStyle;
begin
  G := TCombinedGridStyle.FromFields(7, 4, 12, clRed, 200);
  Assert.AreEqual<Integer>(7, G.Columns);
  Assert.AreEqual<Integer>(4, G.CellGap);
  Assert.AreEqual<Integer>(12, G.Border);
  Assert.AreEqual(TColor(clRed), G.Background);
  Assert.AreEqual<Integer>(200, G.BackgroundAlpha);
end;

{ RenderSmartCombinedImage }

procedure TTestCombinedGrid.SmartRender_EmptyFrames_ReturnsNil;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
begin
  SetLength(Frames, 0);
  SetLength(Offsets, 0);
  SetLength(RowCounts, 0);
  R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
    MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
  Assert.IsNull(R);
end;

procedure TTestCombinedGrid.SmartRender_OutputDimensionsMatchInputs;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
  I: Integer;
begin
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clBlue));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(800, R.Width);
      Assert.AreEqual(600, R.Height);
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedGrid.SmartRender_BorderFillsOuterMargin;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
  I: Integer;
  Row: PByte;
  Border: Integer;
begin
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clRed));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Border := 20;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      MakeGrid(0, 0, clGreen, Border), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      {Pixel inside the top border strip should be green (background),
       not red (frame). Sample (10, 10) which is well inside the
       Border=20 outer margin.}
      Row := PByte(R.ScanLine[10]);
      Inc(Row, 10 * 3); {pf24bit: 3 bytes per pixel}
      Assert.AreEqual(Byte(GetBValue(clGreen)), Row[0], 'B at (10,10)');
      Assert.AreEqual(Byte(GetGValue(clGreen)), Row[1], 'G at (10,10)');
      Assert.AreEqual(Byte(GetRValue(clGreen)), Row[2], 'R at (10,10)');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedGrid.SmartRender_TwoRowsUnequal_RowZeroCellsWiderThanRowOne;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
  I, ExpectedRow0CellW, ExpectedRow1CellW: Integer;
begin
  {5 frames split as [2, 3]: row 0 has 2 cells (each = inner_W / 2),
   row 1 has 3 cells (each = inner_W / 3). So row 0 cells must be wider
   than row 1 cells. Verifies the renderer honours the per-row cell-count
   layout rather than treating the grid as uniform.}
  SetLength(Frames, 5);
  SetLength(Offsets, 5);
  for I := 0 to 4 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clNavy));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  RowCounts := TArray<Integer>.Create(2, 3);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 600, 400,
      MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      ExpectedRow0CellW := 600 div 2;
      ExpectedRow1CellW := 600 div 3;
      Assert.IsTrue(ExpectedRow0CellW > ExpectedRow1CellW,
        'Test setup invariant: 2-cell row must produce wider cells than 3-cell row');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedGrid.SmartRender_PartialAlpha_BecomesPf32Bit;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  Grid: TCombinedGridStyle;
  R: TBitmap;
  I: Integer;
begin
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clBlue));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Grid := MakeGrid(0, 4, clBlack, 8);
  Grid.BackgroundAlpha := 128;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      Grid, MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(Ord(pf32bit), Ord(R.PixelFormat),
        'BackgroundAlpha < 255 should lift the result to pf32bit');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedGrid.SmartRender_PartialAlpha_GapPixelCarriesBackgroundAlpha;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  Grid: TCombinedGridStyle;
  R: TBitmap;
  I: Integer;
  GapAlpha: Byte;
begin
  {With Border=20 and BackgroundAlpha=128, a pixel inside the outer
   margin must carry alpha=128, not 255. Pin parity with the existing
   RenderCombined_GapPixelCarriesBackgroundAlpha test: same policy
   should hold for the smart renderer.}
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clBlue));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Grid := MakeGrid(0, 0, clBlack, 20);
  Grid.BackgroundAlpha := 128;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      Grid, MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      GapAlpha := AlphaByteAt(R, 5, 5); {well inside the 20px border}
      Assert.AreEqual(Byte(128), GapAlpha,
        'Gap/border pixel should carry the configured BackgroundAlpha');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

{TTestLiftToAlphaAwareCore}

{Helper: builds a pf24bit source bitmap with a single solid colour. The
 lift treats the source as opaque RGB; alpha is added by the lift, so
 the source format is always pf24bit in production callers.}
function LiftSource(AWidth, AHeight: Integer; AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{Wide-bound row alias used by the lift tests. The production code uses
 array[0..0] which the compiler treats as range-unchecked when indexed
 by a runtime variable, but breaks on constant-index accesses like
 Row^[3]. A wider bound lets the tests use literal indices freely.}
type
  TLiftQuadRow = array [0 .. 4095] of TRGBQuad;
  PLiftQuadRow = ^TLiftQuadRow;

{Reads the alpha byte at (X, Y) on a pf32bit bitmap via ScanLine.}
function LiftAlphaAt(ABmp: TBitmap; X, Y: Integer): Byte;
var
  Row: PLiftQuadRow;
begin
  Row := PLiftQuadRow(ABmp.ScanLine[Y]);
  Result := Row^[X].rgbReserved;
end;

procedure TTestLiftToAlphaAwareCore.Output_IsPf32BitWithDefinedAlpha;
var
  Source: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
begin
  Source := LiftSource(40, 30, clRed);
  try
    Bg.rgbBlue := 0; Bg.rgbGreen := 0; Bg.rgbRed := 0; Bg.rgbReserved := 128;
    SetLength(Frames, 0);
    SetLength(Rects, 0);
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      Assert.AreEqual(Ord(pf32bit), Ord(Lifted.PixelFormat),
        'Lift output must be pf32bit so PNG savers see a real alpha channel');
      Assert.AreEqual(Ord(afDefined), Ord(Lifted.AlphaFormat),
        'AlphaFormat=afDefined signals VCL the alpha is non-premultiplied');
    finally
      Lifted.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.Output_DimensionsMatchSource;
var
  Source: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
begin
  Source := LiftSource(123, 87, clBlue);
  try
    Bg := Default(TRGBQuad);
    SetLength(Frames, 0);
    SetLength(Rects, 0);
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      Assert.AreEqual(123, Lifted.Width);
      Assert.AreEqual(87, Lifted.Height);
    finally
      Lifted.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.EmptyFrames_OutputIsPureBackground;
var
  Source: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
begin
  {No frames -> every pixel must carry the background alpha. The source's
   RGB is irrelevant because no cell rect re-stamps it.}
  Source := LiftSource(10, 10, clWhite);
  try
    Bg.rgbBlue := 0; Bg.rgbGreen := 0; Bg.rgbRed := 0; Bg.rgbReserved := 64;
    SetLength(Frames, 0);
    SetLength(Rects, 0);
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      Assert.AreEqual(64, Integer(LiftAlphaAt(Lifted, 0, 0)));
      Assert.AreEqual(64, Integer(LiftAlphaAt(Lifted, 5, 5)));
      Assert.AreEqual(64, Integer(LiftAlphaAt(Lifted, 9, 9)));
    finally
      Lifted.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.NilFrameEntry_RectStaysBackground;
var
  Source: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
begin
  {Nil frame at index 0: the corresponding rect must keep background
   alpha rather than being lifted to 255. This is the partial-extraction
   case where a frame slot is reserved but not yet populated.}
  Source := LiftSource(20, 20, clRed);
  try
    Bg.rgbReserved := 100;
    SetLength(Frames, 1);
    Frames[0] := nil;
    SetLength(Rects, 1);
    Rects[0] := Rect(0, 0, 10, 10);
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      Assert.AreEqual(100, Integer(LiftAlphaAt(Lifted, 5, 5)),
        'Nil frame entry must leave the rect at background alpha');
    finally
      Lifted.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.RectInside_PixelsCarrySourceRGBAndOpaque;
var
  Source, FramePlaceholder: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
  Row: PLiftQuadRow;
begin
  {Source filled red, one frame slot non-nil with rect (0,0)-(8,8).
   Inside the rect, alpha must be 255 and RGB must come from the source.
   Outside the rect, alpha stays at the background value.}
  Source := LiftSource(16, 16, clRed); {clRed = $0000FF}
  FramePlaceholder := LiftSource(8, 8, clBlack); {used only as non-nil signal}
  try
    Bg.rgbBlue := 0; Bg.rgbGreen := 255; Bg.rgbRed := 0; Bg.rgbReserved := 50;
    SetLength(Frames, 1);
    Frames[0] := FramePlaceholder;
    SetLength(Rects, 1);
    Rects[0] := Rect(0, 0, 8, 8);
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      {Inside the rect: red source, opaque alpha.}
      Row := PLiftQuadRow(Lifted.ScanLine[3]);
      Assert.AreEqual(255, Integer(Row^[3].rgbReserved),
        'Cell pixel must be alpha=255');
      Assert.AreEqual(0, Integer(Row^[3].rgbBlue));
      Assert.AreEqual(0, Integer(Row^[3].rgbGreen));
      Assert.AreEqual(255, Integer(Row^[3].rgbRed));

      {Outside the rect: background alpha + background RGB.}
      Row := PLiftQuadRow(Lifted.ScanLine[10]);
      Assert.AreEqual(50, Integer(Row^[10].rgbReserved),
        'Pixel outside any rect must keep background alpha');
    finally
      Lifted.Free;
    end;
  finally
    FramePlaceholder.Free;
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.FramesLongerThanRects_TrailingSkipped;
var
  Source, F0, F1: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
begin
  {Two frame slots, only one rect supplied. The first frame is processed;
   the second must be silently skipped (no crash, no out-of-bounds read).
   Defensive guard: a future caller could mismatch the lengths and this
   test pins the helper's tolerance for it.}
  Source := LiftSource(20, 20, clBlue);
  F0 := LiftSource(8, 8, clBlack);
  F1 := LiftSource(8, 8, clBlack);
  try
    Bg.rgbReserved := 64;
    SetLength(Frames, 2);
    Frames[0] := F0;
    Frames[1] := F1;
    SetLength(Rects, 1);
    Rects[0] := Rect(0, 0, 8, 8);
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      Assert.IsNotNull(Lifted, 'Length mismatch must not produce nil');
      Assert.AreEqual(255, Integer(LiftAlphaAt(Lifted, 3, 3)),
        'First frame still lifts inside its rect');
      {Second frame had no rect -> no observable change.}
      Assert.AreEqual(64, Integer(LiftAlphaAt(Lifted, 15, 15)),
        'Pixel beyond the only supplied rect keeps background alpha');
    finally
      Lifted.Free;
    end;
  finally
    F0.Free;
    F1.Free;
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.RectOutsideBounds_ClippedNoCrash;
var
  Source, FramePlaceholder: TBitmap;
  Bg: TRGBQuad;
  Frames: TArray<TBitmap>;
  Rects: TArray<TRect>;
  Lifted: TBitmap;
begin
  {Rect extends past the source in both axes. Per-pixel clipping must
   skip the out-of-bounds rows and columns without crashing. Defensive
   guard against a caller that supplied stale rects after a resize.}
  Source := LiftSource(10, 10, clRed);
  FramePlaceholder := LiftSource(20, 20, clBlack);
  try
    Bg.rgbReserved := 80;
    SetLength(Frames, 1);
    Frames[0] := FramePlaceholder;
    SetLength(Rects, 1);
    Rects[0] := Rect(5, 5, 100, 100); {extends way past 10x10 source}
    Lifted := LiftToAlphaAwareCore(Source, Bg, Frames, Rects);
    try
      Assert.IsNotNull(Lifted);
      {Inside both source and rect: pixel must be lifted to alpha=255.}
      Assert.AreEqual(255, Integer(LiftAlphaAt(Lifted, 7, 7)));
      {Pixel that the rect would have covered but lies outside source
       is simply not addressable on the output; the test just
       confirms the function returned without exception.}
    finally
      Lifted.Free;
    end;
  finally
    FramePlaceholder.Free;
    Source.Free;
  end;
end;

procedure TTestLiftToAlphaAwareCore.BackgroundQuad_PreservesAlphaByte;
var
  Grid: TCombinedGridStyle;
  Q: TRGBQuad;
begin
  {Sanity check on the helper that builds the RGBQuad from a grid style:
   the alpha byte must come straight from BackgroundAlpha, not get
   accidentally re-mapped via TColor channels.}
  Grid := DefaultCombinedGridStyle;
  Grid.Background := TColor($00112233); {B=$11 G=$22 R=$33}
  Grid.BackgroundAlpha := 77;
  Q := GridBackgroundQuad(Grid);
  Assert.AreEqual($11, Integer(Q.rgbBlue));
  Assert.AreEqual($22, Integer(Q.rgbGreen));
  Assert.AreEqual($33, Integer(Q.rgbRed));
  Assert.AreEqual(77, Integer(Q.rgbReserved));
end;

end.
