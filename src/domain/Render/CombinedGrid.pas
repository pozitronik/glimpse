{Renders multiple frame bitmaps into a single combined grid image.
 Uniform (RenderCombinedImage) and smart-row (RenderSmartCombinedImage)
 layouts. Lifts to pf32bit when BackgroundAlpha < 255 so PNG saves
 preserve gap/border transparency; opaque output stays on pf24bit.}
unit CombinedGrid;

interface

uses
  Winapi.Windows, Vcl.Graphics,
  FrameOffsets, TimecodeOverlay;

type
  {Columns = 0 means auto (ceil(sqrt(n))). BackgroundAlpha < 255 yields
   a pf32bit bitmap with gap/border alpha; frames stay opaque.}
  TCombinedGridStyle = record
    Columns: Integer;
    CellGap: Integer;
    Border: Integer;
    Background: TColor;
    BackgroundAlpha: Byte;
    class function FromFields(AColumns, ACellGap, ABorder: Integer;
      ABackground: TColor; ABackgroundAlpha: Byte): TCombinedGridStyle; static;
  end;

function GridBackgroundQuad(const AGrid: TCombinedGridStyle): TRGBQuad;

{nil entries in AFrames leave the rect at ABg (partial extraction).
 Caller owns the returned bitmap.}
function LiftToAlphaAwareCore(ASource: TBitmap; const ABg: TRGBQuad; const AFrames: TArray<TBitmap>; const ACellRects: TArray<TRect>): TBitmap;

{Returns 1 when AFrameCount is zero so callers can divide safely.}
function ResolveCombinedGridCols(AFrameCount, ARequestedCols: Integer): Integer;

{Shared by RenderCombinedImage and layout predictors that need the size
 before deciding to render.}
function ComputeCombinedImageSize(AFrameCount, ACols, ACellW, ACellH, ABorder, ACellGap: Integer): TPoint;

{Returns nil for an empty AFrames. Caller owns the result.}
function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;

{ARowCounts sum must equal Length(AFrames). Frames are crop-to-filled
 to preserve aspect without letterbox bands.}
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

    for Y := 0 to Result.Height - 1 do
    begin
      DstRow := PQuadRow(Result.ScanLine[Y]);
      for X := 0 to Result.Width - 1 do
        DstRow^[X] := ABg;
    end;

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

function GridBackgroundQuad(const AGrid: TCombinedGridStyle): TRGBQuad;
begin
  Result.rgbBlue := GetBValue(AGrid.Background);
  Result.rgbGreen := GetGValue(AGrid.Background);
  Result.rgbRed := GetRValue(AGrid.Background);
  Result.rgbReserved := AGrid.BackgroundAlpha;
end;

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
  try
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

    if AGrid.BackgroundAlpha < 255 then
    begin
      Lifted := LiftToAlphaAware(Result, AGrid, AFrames, Cols, CellW, CellH, Border);
      Result.Free;
      Result := Lifted;
    end;
  except
    Result.Free;
    raise;
  end;
end;

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

    {Algorithm matches TFrameView.PaintCropToFill so saved smart-combined
     output mirrors the live view.}
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
