{Renders multiple frame bitmaps into a single combined grid image.
 Pure rendering: no I/O, no settings dependency.

 Two layouts are supported:
 - Uniform grid (RenderCombinedImage): every cell the same width and
   height, columns either explicitly supplied or auto-derived via
   ceil(sqrt(N)). Cells laid out left-to-right, top-to-bottom.
 - Smart grid (RenderSmartCombinedImage): cells per row caller-supplied
   via ARowCounts; within a row cells are uniform-width but rows can
   differ. Frames are crop-to-filled into their cells to preserve
   aspect ratio without letterbox bands.

 Both layouts optionally lift the rendered pf24bit bitmap into a pf32bit
 alpha-aware output when the grid's BackgroundAlpha is < 255 - this lets
 the PNG saver preserve gap/border transparency while keeping the
 historical pf24bit fast path for the opaque case.}
unit uCombinedGrid;

interface

uses
  Winapi.Windows, Vcl.Graphics,
  uFrameOffsets, uTimecodeOverlay;

type
  {Grid geometry for the combined image. Columns = 0 means "auto" (ceil(sqrt(n)));
   Border is the outer margin painted with Background around the whole grid.
   BackgroundAlpha controls how opaque the gap/border fill is in the rendered
   bitmap: 255 keeps the historical pf24bit output unchanged; values < 255
   produce a pf32bit bitmap whose gap/border pixels carry that alpha while
   frame pixels stay fully opaque.}
  TCombinedGridStyle = record
    Columns: Integer;
    CellGap: Integer;
    Border: Integer;
    Background: TColor;
    BackgroundAlpha: Byte;
    {The combined-grid settings do not live in a single settings group
     today (Background / CellGap / CombinedBorder are on TPluginSettings
     and TWcxSettings as flat fields under different INI sections;
     CombinedColumns is WCX-only). Restructuring that storage to host a
     group is out of scope here, so the factory takes individual fields.
     Saves the zero-init line plus the 5 assignments at every call
     site without forcing a settings-layer refactor.}
    class function FromFields(AColumns, ACellGap, ABorder: Integer;
      ABackground: TColor; ABackgroundAlpha: Byte): TCombinedGridStyle; static;
  end;

{Builds a TRGBQuad from AGrid.Background + AGrid.BackgroundAlpha. Surfaced
 in the interface so test code can construct the same gap/border colour
 the production lift wrappers use.}
function GridBackgroundQuad(const AGrid: TCombinedGridStyle): TRGBQuad;

{Rect-driven alpha-aware lift core. Allocates a pf32bit bitmap matching
 ASource, fills it with ABg (gap/border colour + alpha), then re-stamps
 each non-nil frame's cell rect with the source RGB at alpha=255. Used
 by both the uniform-grid and smart-grid lift wrappers, which differ
 only in how they compute the cell rects.

 Defensive guards:
 - AFrames[I] = nil -> the corresponding rect stays at ABg (frame slot
 not yet populated, e.g. partial extraction).
 - Length(AFrames) > Length(ACellRects) -> trailing frames skipped.
 - Rect coordinates outside ASource bounds -> clipped per-pixel.

 Caller owns the returned bitmap.}
function LiftToAlphaAwareCore(ASource: TBitmap; const ABg: TRGBQuad; const AFrames: TArray<TBitmap>; const ACellRects: TArray<TRect>): TBitmap;

{Resolves the column count the uniform grid will use. Mirrors the
 selection RenderCombinedImage applies internally so callers (e.g. the
 dimension predictor in TFrameExporter) get the same value the renderer
 will pick - 0 means auto, in which case ceil(sqrt(N)) is used and capped
 at FrameCount. Returns 1 when AFrameCount is zero so callers can divide
 safely.}
function ResolveCombinedGridCols(AFrameCount, ARequestedCols: Integer): Integer;

{Computes the bitmap dimensions RenderCombinedImage would produce for
 the given inputs, without performing the render. Single source of
 truth shared by RenderCombinedImage (for its own SetSize) and by
 layout predictors that need to know the output size before deciding to
 actually render. AFrameCount is the number of cells in the grid (used
 to compute Rows = ceil(N/Cols)); ACols is the resolved column count
 (use ResolveCombinedGridCols when only the requested count is in hand).}
function ComputeCombinedImageSize(AFrameCount, ACols, ACellW, ACellH, ABorder, ACellGap: Integer): TPoint;

{Renders all frames into a single grid image.
 @param AFrames Array of frame bitmaps (nil entries are skipped)
 @param AOffsets Frame time offsets (used for the timestamp overlay)
 @param AGrid Grid geometry (columns, gap, border, background)
 @param ATimestamp Per-cell timecode overlay style; ignored when Show=False
 @return Combined bitmap, or nil if AFrames is empty. Caller owns result.}
function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;

{Renders frames into a smart-grid combined image. Cells per row come from
 ARowCounts (sum must equal Length(AFrames)); within each row cells are
 uniform-width, between rows widths can differ. Frames are crop-to-filled
 into their cells so aspect ratio is preserved without letterbox bands.

 @param AFrames Array of frame bitmaps (nil entries are skipped)
 @param AOffsets Frame time offsets (used for the timestamp overlay)
 @param ARowCounts Cells per row (sum must equal Length(AFrames))
 @param AOutputW Total output width including 2*AGrid.Border
 @param AOutputH Total output height including 2*AGrid.Border
 @param AGrid Border, gap, and background colour/alpha
 @param ATimestamp Per-cell timecode overlay style
 @return Combined bitmap. Caller owns result.}
function RenderSmartCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; const ARowCounts: TArray<Integer>; AOutputW, AOutputH: Integer; const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;

implementation

uses
  System.Math, System.Types;

class function TCombinedGridStyle.FromFields(AColumns, ACellGap, ABorder: Integer;
  ABackground: TColor; ABackgroundAlpha: Byte): TCombinedGridStyle;
begin
  Result.Columns := AColumns;
  Result.CellGap := ACellGap;
  Result.Border := ABorder;
  Result.Background := ABackground;
  Result.BackgroundAlpha := ABackgroundAlpha;
end;

{Rect-driven alpha-aware lift core. Allocates a pf32bit bitmap matching
 ASource, fills it with ABg (gap/border colour + alpha), then re-stamps
 each cell rect with the source RGB at alpha=255. Used by both the
 uniform-grid and smart-grid lift wrappers, which differ only in how
 they compute the cell rects. Rect entries paired with nil frame slots
 are skipped so partial coverage degrades gracefully.}
function LiftToAlphaAwareCore(ASource: TBitmap; const ABg: TRGBQuad; const AFrames: TArray<TBitmap>; const ACellRects: TArray<TRect>): TBitmap;
type
  TQuadRow = array [0 .. 0] of TRGBQuad;
  PQuadRow = ^TQuadRow;
  TTripleRow = array [0 .. 0] of TRGBTriple;
  PTripleRow = ^TTripleRow;
var
  X, Y, I, Px, Py: Integer;
  R: TRect;
  DstRow: PQuadRow;
  SrcRow: PTripleRow;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf32bit;
    Result.AlphaFormat := afDefined;
    Result.SetSize(ASource.Width, ASource.Height);

    {Initial fill: gap/border colour + BackgroundAlpha. Outside-cell pixels
     never get touched again, so the gap/border becomes alpha-aware here.}
    for Y := 0 to Result.Height - 1 do
    begin
      DstRow := PQuadRow(Result.ScanLine[Y]);
      for X := 0 to Result.Width - 1 do
        DstRow^[X] := ABg;
    end;

    {Each non-nil frame's cell rect: copy RGB from the pf24bit source,
     alpha=255. Captures both the frame pixels and any timecode overlay
     that was drawn within the cell rect.}
    for I := 0 to High(AFrames) do
    begin
      if AFrames[I] = nil then
        Continue;
      if I >= Length(ACellRects) then
        Continue;
      R := ACellRects[I];
      for Py := R.Top to R.Bottom - 1 do
      begin
        if (Py < 0) or (Py >= Result.Height) then
          Continue;
        SrcRow := PTripleRow(ASource.ScanLine[Py]);
        DstRow := PQuadRow(Result.ScanLine[Py]);
        for Px := R.Left to R.Right - 1 do
        begin
          if (Px < 0) or (Px >= Result.Width) then
            Continue;
          DstRow^[Px].rgbBlue := SrcRow^[Px].rgbtBlue;
          DstRow^[Px].rgbGreen := SrcRow^[Px].rgbtGreen;
          DstRow^[Px].rgbRed := SrcRow^[Px].rgbtRed;
          DstRow^[Px].rgbReserved := 255;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{Builds a TRGBQuad from AGrid.Background + AGrid.BackgroundAlpha for
 the lift core's gap/border fill.}
function GridBackgroundQuad(const AGrid: TCombinedGridStyle): TRGBQuad;
begin
  Result.rgbBlue := GetBValue(AGrid.Background);
  Result.rgbGreen := GetGValue(AGrid.Background);
  Result.rgbRed := GetRValue(AGrid.Background);
  Result.rgbReserved := AGrid.BackgroundAlpha;
end;

{Lifts the rendered pf24bit uniform grid into a pf32bit bitmap. Computes
 the cell-rect array from grid math (ACols x cell rect, with CellGap
 between cells and ABorder around the inner area), then calls the
 shared rect-driven core. Called by RenderCombinedImage when alpha < 255
 so the historical pf24bit fast path is unaffected for opaque output.}
function LiftToAlphaAware(ASource: TBitmap; const AGrid: TCombinedGridStyle; const AFrames: TArray<TBitmap>; ACols, ACellW, ACellH, ABorder: Integer): TBitmap;
var
  Rects: TArray<TRect>;
  I, Row, Col, FrameX, FrameY: Integer;
begin
  SetLength(Rects, Length(AFrames));
  for I := 0 to High(AFrames) do
  begin
    Row := I div ACols;
    Col := I mod ACols;
    FrameX := ABorder + Col * (ACellW + AGrid.CellGap);
    FrameY := ABorder + Row * (ACellH + AGrid.CellGap);
    Rects[I].Left := FrameX;
    Rects[I].Top := FrameY;
    Rects[I].Right := FrameX + ACellW;
    Rects[I].Bottom := FrameY + ACellH;
  end;
  Result := LiftToAlphaAwareCore(ASource, GridBackgroundQuad(AGrid), AFrames, Rects);
end;

function ResolveCombinedGridCols(AFrameCount, ARequestedCols: Integer): Integer;
begin
  if AFrameCount <= 0 then
    Exit(1);
  Result := ARequestedCols;
  if Result <= 0 then
    Result := Ceil(Sqrt(AFrameCount));
  if Result > AFrameCount then
    Result := AFrameCount;
end;

function ComputeCombinedImageSize(AFrameCount, ACols, ACellW, ACellH, ABorder, ACellGap: Integer): TPoint;
var
  Rows, Border: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  if (AFrameCount <= 0) or (ACols <= 0) then
    Exit;
  Border := ABorder;
  if Border < 0 then
    Border := 0;
  Rows := Ceil(AFrameCount / ACols);
  Result.X := ACols * ACellW + Max(ACols - 1, 0) * ACellGap + 2 * Border;
  Result.Y := Rows * ACellH + Max(Rows - 1, 0) * ACellGap + 2 * Border;
end;

function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;
var
  Cols, CellW, CellH, I, Row, Col, X, Y: Integer;
  FrameCount: Integer;
  Border: Integer;
  Sz: TPoint;
  Lifted: TBitmap;
begin
  FrameCount := Length(AFrames);
  if FrameCount = 0 then
    Exit(nil);

  Border := AGrid.Border;
  if Border < 0 then
    Border := 0;

  Cols := ResolveCombinedGridCols(FrameCount, AGrid.Columns);

  {Use first non-nil frame dimensions as cell size}
  CellW := 320;
  CellH := 240;
  for I := 0 to FrameCount - 1 do
    if AFrames[I] <> nil then
    begin
      CellW := AFrames[I].Width;
      CellH := AFrames[I].Height;
      Break;
    end;

  Sz := ComputeCombinedImageSize(FrameCount, Cols, CellW, CellH, Border, AGrid.CellGap);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Sz.X, Sz.Y);
  Result.Canvas.Brush.Color := AGrid.Background;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then
      Continue;
    Row := I div Cols;
    Col := I mod Cols;
    X := Border + Col * (CellW + AGrid.CellGap);
    Y := Border + Row * (CellH + AGrid.CellGap);
    Result.Canvas.Draw(X, Y, AFrames[I]);

    if I < Length(AOffsets) then
      DrawCellTimecode(Result.Canvas, Rect(X, Y, X + CellW, Y + CellH), AOffsets[I].TimeOffset, ATimestamp);
  end;

  {Optional alpha-aware output. When BackgroundAlpha is 255 the pf24bit
   Result is exactly the historical output (no behaviour change). For
   alpha < 255 we lift into pf32bit so PNG savers preserve the gap/border
   transparency; frame pixels stay at alpha=255 because they are
   conceptually opaque content.}
  if AGrid.BackgroundAlpha < 255 then
  begin
    Lifted := LiftToAlphaAware(Result, AGrid, AFrames, Cols, CellW, CellH, Border);
    Result.Free;
    Result := Lifted;
  end;
end;

{Lifts a smart-grid combined render into a pf32bit bitmap so PNG savers
 preserve gap/border transparency. Smart-grid cells have row-dependent
 widths so the caller supplies the rects directly; the shared
 LiftToAlphaAwareCore does the actual lift.}
function LiftToAlphaAwareSmart(ASource: TBitmap; const AGrid: TCombinedGridStyle; const AFrames: TArray<TBitmap>; const ACellRects: TArray<TRect>): TBitmap;
begin
  Result := LiftToAlphaAwareCore(ASource, GridBackgroundQuad(AGrid), AFrames, ACellRects);
end;

function RenderSmartCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; const ARowCounts: TArray<Integer>; AOutputW, AOutputH: Integer; const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;
var
  Border, InnerW, InnerH, Gap: Integer;
  NRows, FrameCount, MaxCells: Integer;
  RowH, CellW, CellsInRow, CellsBefore, FrameIdx, RowIdx, CellInRow: Integer;
  RowTop, CellLeft: Integer;
  Bmp: TBitmap;
  CellRect, SrcR: TRect;
  CellRects: TArray<TRect>;
  Scale: Double;
  SrcW, SrcH: Integer;
  Lifted: TBitmap;
begin
  FrameCount := Length(AFrames);
  if (FrameCount = 0) or (Length(ARowCounts) = 0) then
    Exit(nil);

  Border := AGrid.Border;
  if Border < 0 then
    Border := 0;
  Gap := AGrid.CellGap;
  if Gap < 0 then
    Gap := 0;

  NRows := Length(ARowCounts);
  InnerW := Max(1, AOutputW - 2 * Border);
  InnerH := Max(1, AOutputH - 2 * Border);
  RowH := Max(1, (InnerH - (NRows - 1) * Gap) div NRows);

  MaxCells := 1;
  for RowIdx := 0 to NRows - 1 do
    if ARowCounts[RowIdx] > MaxCells then
      MaxCells := ARowCounts[RowIdx];

  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AOutputW, AOutputH);
    Result.Canvas.Brush.Color := AGrid.Background;
    Result.Canvas.FillRect(Rect(0, 0, AOutputW, AOutputH));

    SetLength(CellRects, FrameCount);

    {Walk rows, then cells within each row. Crop-to-fill each frame into
     its cell so aspect ratio is preserved without letterbox bands. The
     algorithm matches TFrameView.PaintCropToFill so saved smart-combined
     output looks exactly like the live view.}
    CellsBefore := 0;
    for RowIdx := 0 to NRows - 1 do
    begin
      CellsInRow := Max(1, ARowCounts[RowIdx]);
      CellW := Max(1, (InnerW - (CellsInRow - 1) * Gap) div CellsInRow);
      RowTop := Border + RowIdx * (RowH + Gap);

      for CellInRow := 0 to CellsInRow - 1 do
      begin
        FrameIdx := CellsBefore + CellInRow;
        if FrameIdx >= FrameCount then
          Break;

        CellLeft := Border + CellInRow * (CellW + Gap);
        CellRect := Rect(CellLeft, RowTop, CellLeft + CellW, RowTop + RowH);
        CellRects[FrameIdx] := CellRect;

        Bmp := AFrames[FrameIdx];
        if Bmp = nil then
          Continue;

        Scale := Max(CellW / Max(1, Bmp.Width), RowH / Max(1, Bmp.Height));
        SrcW := Min(Bmp.Width, Round(CellW / Scale));
        SrcH := Min(Bmp.Height, Round(RowH / Scale));
        SrcR.Left := (Bmp.Width - SrcW) div 2;
        SrcR.Top := (Bmp.Height - SrcH) div 2;
        SrcR.Right := SrcR.Left + SrcW;
        SrcR.Bottom := SrcR.Top + SrcH;

        SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
        SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
        Result.Canvas.CopyRect(CellRect, Bmp.Canvas, SrcR);

        if FrameIdx < Length(AOffsets) then
          DrawCellTimecode(Result.Canvas, CellRect, AOffsets[FrameIdx].TimeOffset, ATimestamp);
      end;
      Inc(CellsBefore, CellsInRow);
    end;

    {Optional alpha-aware output. Same policy as RenderCombinedImage:
     when BackgroundAlpha is 255 the pf24bit Result is the final output;
     otherwise we lift to pf32bit so the gap/border carries the chosen
     alpha while frame pixels stay opaque.}
    if AGrid.BackgroundAlpha < 255 then
    begin
      Lifted := LiftToAlphaAwareSmart(Result, AGrid, AFrames, CellRects);
      Result.Free;
      Result := Lifted;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
