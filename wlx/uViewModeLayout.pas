{View mode layout strategies: compute cell positions, sizes, and scroll behavior.
 Extracted from TFrameView to satisfy OCP: adding a view mode means adding
 a class, not editing switch statements across the control.}
unit uViewModeLayout;

interface

uses
  System.Types,
  uTypes;

const
  DEF_ASPECT_RATIO = 9.0 / 16.0; {16:9 fallback, height/width}

type
  TViewLayoutContext = record
    BaseW: Integer; {base viewport width (frozen when zoomed)}
    BaseH: Integer; {base viewport height}
    CellCount: Integer;
    CellGap: Integer;
    AspectRatio: Double; {height / width}
    NativeW: Integer;
    NativeH: Integer;
    ZoomMode: TZoomMode;
    ZoomFactor: Double;
    ClientWidth: Integer; {actual control width}
    ClientHeight: Integer;
    CurrentFrameIndex: Integer;
    ViewportW: Integer;
    ViewportH: Integer;
    ColumnCount: Integer; {user-set, 0 = auto}
  end;

  TLayoutWheelAction = (lwaVerticalScroll, lwaHorizontalScroll, lwaNavigateFrame);

  {Abstract base: each subclass defines geometry for one view mode.}
  TViewModeLayout = class abstract
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; virtual; abstract;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; virtual; abstract;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; virtual; abstract;
    function WheelScrollKind: TLayoutWheelAction; virtual; abstract;
    function CellIndexAt(const APoint: TPoint; const ACtx: TViewLayoutContext): Integer; virtual;
  end;

  TGridLayout = class(TViewModeLayout)
  private
    function CalcCellImageSize(const ACtx: TViewLayoutContext): TSize;
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; override;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; override;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; override;
    function WheelScrollKind: TLayoutWheelAction; override;
  end;

  TSmartRow = record
    Count: Integer;
  end;

  TSmartGridLayout = class(TViewModeLayout)
  strict private
    FSmartRows: TArray<TSmartRow>;
    procedure CalcRows(const ACtx: TViewLayoutContext);
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; override;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; override;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; override;
    function WheelScrollKind: TLayoutWheelAction; override;
  end;

  TScrollLayout = class(TViewModeLayout)
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; override;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; override;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; override;
    function WheelScrollKind: TLayoutWheelAction; override;
  end;

  TFilmstripLayout = class(TViewModeLayout)
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; override;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; override;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; override;
    function WheelScrollKind: TLayoutWheelAction; override;
  end;

  TSingleLayout = class(TViewModeLayout)
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; override;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; override;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; override;
    function WheelScrollKind: TLayoutWheelAction; override;
    function CellIndexAt(const APoint: TPoint; const ACtx: TViewLayoutContext): Integer; override;
  end;

function CreateViewModeLayout(AMode: TViewMode): TViewModeLayout;

implementation

uses
  System.Math, uZoomController;

{TViewModeLayout}

function TViewModeLayout.CellIndexAt(const APoint: TPoint; const ACtx: TViewLayoutContext): Integer;
var
  I: Integer;
begin
  for I := 0 to ACtx.CellCount - 1 do
    if GetCellRect(I, ACtx).Contains(APoint) then
      Exit(I);
  Result := -1;
end;

{TGridLayout}

function TGridLayout.GetColumnCount(const ACtx: TViewLayoutContext): Integer;
begin
  if ACtx.CellCount <= 1 then
    Exit(1);
  {Original size: columns based on native frame width}
  if (ACtx.ZoomMode = zmActual) and (ACtx.NativeW > 0) then
    Exit(Max(1, (ACtx.BaseW - ACtx.CellGap) div (ACtx.NativeW + ACtx.CellGap)));
  if ACtx.ColumnCount > 0 then
    Exit(ACtx.ColumnCount);
  Result := Max(1, Floor(Sqrt(ACtx.CellCount)));
end;

function TGridLayout.CalcCellImageSize(const ACtx: TViewLayoutContext): TSize;
var
  Cols, AvailW: Integer;
begin
  Cols := GetColumnCount(ACtx);
  {Gaps live between cells only: N cells share (N-1) gaps. Outer padding
   is the caller's job (TFrameView applies CellMargin around the layout).}
  AvailW := ACtx.BaseW - Max(Cols - 1, 0) * ACtx.CellGap;
  Result.cx := Max(1, Round(AvailW / Cols * ACtx.ZoomFactor));
  Result.cy := Max(1, Round(Result.cx * ACtx.AspectRatio));
end;

function TGridLayout.GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
var
  Cols, Col, Row, Rows: Integer;
  Sz: TSize;
  GridW, GridH, OffsetX, OffsetY: Integer;
begin
  Cols := GetColumnCount(ACtx);
  Sz := CalcCellImageSize(ACtx);
  Col := AIndex mod Cols;
  Row := AIndex div Cols;
  Rows := Ceil(ACtx.CellCount / Max(1, Cols));

  GridW := Cols * Sz.cx + Max(Cols - 1, 0) * ACtx.CellGap;
  GridH := Rows * Sz.cy + Max(Rows - 1, 0) * ACtx.CellGap;

  {Center grid horizontally}
  if GridW < ACtx.ClientWidth then
    OffsetX := (ACtx.ClientWidth - GridW) div 2
  else
    OffsetX := 0;

  {Center grid vertically}
  if GridH < ACtx.ClientHeight then
    OffsetY := (ACtx.ClientHeight - GridH) div 2
  else
    OffsetY := 0;

  Result.Left := OffsetX + Col * (Sz.cx + ACtx.CellGap);
  Result.Top := OffsetY + Row * (Sz.cy + ACtx.CellGap);
  Result.Right := Result.Left + Sz.cx;
  Result.Bottom := Result.Top + Sz.cy;
end;

function TGridLayout.RecalcSize(const ACtx: TViewLayoutContext): TSize;
var
  Cols, Rows, GridW, GridH: Integer;
  Sz: TSize;
begin
  Cols := GetColumnCount(ACtx);
  Sz := CalcCellImageSize(ACtx);
  Rows := Ceil(ACtx.CellCount / Cols);
  GridW := Cols * Sz.cx + Max(Cols - 1, 0) * ACtx.CellGap;
  GridH := Rows * Sz.cy + Max(Rows - 1, 0) * ACtx.CellGap;
  Result.cx := Max(ACtx.ViewportW, GridW);
  Result.cy := Max(ACtx.ViewportH, GridH);
end;

function TGridLayout.WheelScrollKind: TLayoutWheelAction;
begin
  Result := lwaVerticalScroll;
end;

{TScrollLayout}

function TScrollLayout.GetColumnCount(const ACtx: TViewLayoutContext): Integer;
begin
  Result := 1;
end;

function TScrollLayout.GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
var
  CellW, CellH, LeftX: Integer;
begin
  case ACtx.ZoomMode of
    zmActual:
      begin
        CellW := Max(1, ACtx.NativeW);
        CellH := Max(1, ACtx.NativeH);
      end;
    zmFitIfLarger:
      begin
        CellW := Max(1, ACtx.BaseW);
        if (ACtx.NativeW > 0) and (ACtx.NativeW < CellW) then
          CellW := ACtx.NativeW;
        CellH := Max(1, Round(CellW * ACtx.AspectRatio));
      end;
    else {zmFitWindow}
      begin
        CellW := Max(1, ACtx.BaseW);
        CellH := Max(1, Round(CellW * ACtx.AspectRatio));
      end;
  end;

  {Apply continuous zoom}
  CellW := Max(1, Round(CellW * ACtx.ZoomFactor));
  CellH := Max(1, Round(CellH * ACtx.ZoomFactor));

  {Center horizontally when cell is narrower than control. Outer margin
   is added by TFrameView via CellMargin, so the layout itself starts
   cells at column 0 / row 0.}
  if CellW < ACtx.ClientWidth then
    LeftX := (ACtx.ClientWidth - CellW) div 2
  else
    LeftX := 0;

  Result.Left := LeftX;
  Result.Top := AIndex * (CellH + ACtx.CellGap);
  Result.Right := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TScrollLayout.RecalcSize(const ACtx: TViewLayoutContext): TSize;
var
  R0: TRect;
begin
  R0 := GetCellRect(0, ACtx);
  Result.cx := Max(ACtx.ViewportW, R0.Width);
  Result.cy := Max(ACtx.ViewportH, ACtx.CellCount * R0.Height + Max(ACtx.CellCount - 1, 0) * ACtx.CellGap);
end;

function TScrollLayout.WheelScrollKind: TLayoutWheelAction;
begin
  Result := lwaVerticalScroll;
end;

{TFilmstripLayout}

function TFilmstripLayout.GetColumnCount(const ACtx: TViewLayoutContext): Integer;
begin
  Result := Max(1, ACtx.CellCount);
end;

function TFilmstripLayout.GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
var
  CellH, CellW, AvailH, TopY: Integer;
begin
  AvailH := Max(1, ACtx.BaseH);

  case ACtx.ZoomMode of
    zmActual:
      CellH := Max(1, ACtx.NativeH);
    zmFitIfLarger:
      begin
        CellH := AvailH;
        if (ACtx.NativeH > 0) and (ACtx.NativeH < CellH) then
          CellH := ACtx.NativeH;
      end;
    else {zmFitWindow}
      CellH := AvailH;
  end;

  {Apply continuous zoom}
  CellH := Max(1, Round(CellH * ACtx.ZoomFactor));
  CellW := Max(1, Round(CellH / Max(ACtx.AspectRatio, DEF_ASPECT_RATIO)));

  {Center vertically within control. Outer margin is added by TFrameView
   via CellMargin, so the layout itself starts at top 0 when the strip
   spans the full height.}
  if CellH < AvailH then
    TopY := (ACtx.ClientHeight - CellH) div 2
  else
    TopY := 0;

  Result.Left := AIndex * (CellW + ACtx.CellGap);
  Result.Top := TopY;
  Result.Right := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TFilmstripLayout.RecalcSize(const ACtx: TViewLayoutContext): TSize;
var
  R0: TRect;
begin
  R0 := GetCellRect(0, ACtx);
  Result.cx := Max(ACtx.ViewportW, ACtx.CellCount * R0.Width + Max(ACtx.CellCount - 1, 0) * ACtx.CellGap);
  Result.cy := Max(ACtx.ViewportH, R0.Height);
end;

function TFilmstripLayout.WheelScrollKind: TLayoutWheelAction;
begin
  Result := lwaHorizontalScroll;
end;

{TSingleLayout}

function TSingleLayout.GetColumnCount(const ACtx: TViewLayoutContext): Integer;
begin
  Result := 1;
end;

function TSingleLayout.GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
var
  CellW, CellH: Integer;
  AvailW, AvailH: Integer;
begin
  {Base available space from frozen viewport, not control size. Outer
   margin is added by TFrameView via CellMargin; the layout consumes the
   full BaseW/BaseH it was handed.}
  AvailW := Max(1, ACtx.BaseW);
  AvailH := Max(1, ACtx.BaseH);

  case ACtx.ZoomMode of
    zmActual:
      begin
        CellW := Max(1, ACtx.NativeW);
        CellH := Max(1, ACtx.NativeH);
      end;
    zmFitIfLarger:
      begin
        if (ACtx.NativeW > 0) and (ACtx.NativeH > 0) and (ACtx.NativeW <= AvailW) and (ACtx.NativeH <= AvailH) then
        begin
          CellW := ACtx.NativeW;
          CellH := ACtx.NativeH;
        end else begin
          CellW := AvailW;
          CellH := Round(CellW * ACtx.AspectRatio);
          if CellH > AvailH then
          begin
            CellH := AvailH;
            CellW := Round(CellH / Max(ACtx.AspectRatio, DEF_ASPECT_RATIO));
          end;
        end;
      end;
    else {zmFitWindow}
      begin
        CellW := AvailW;
        CellH := Round(CellW * ACtx.AspectRatio);
        if CellH > AvailH then
        begin
          CellH := AvailH;
          CellW := Round(CellH / Max(ACtx.AspectRatio, DEF_ASPECT_RATIO));
        end;
      end;
  end;

  {Apply continuous zoom}
  CellW := Max(1, Round(CellW * ACtx.ZoomFactor));
  CellH := Max(1, Round(CellH * ACtx.ZoomFactor));

  {Center in control}
  Result.Left := (ACtx.ClientWidth - CellW) div 2;
  Result.Top := (ACtx.ClientHeight - CellH) div 2;
  Result.Right := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TSingleLayout.RecalcSize(const ACtx: TViewLayoutContext): TSize;
var
  R0: TRect;
begin
  R0 := GetCellRect(ACtx.CurrentFrameIndex, ACtx);
  Result.cx := Max(ACtx.ViewportW, R0.Width);
  Result.cy := Max(ACtx.ViewportH, R0.Height);
end;

function TSingleLayout.WheelScrollKind: TLayoutWheelAction;
begin
  Result := lwaNavigateFrame;
end;

function TSingleLayout.CellIndexAt(const APoint: TPoint; const ACtx: TViewLayoutContext): Integer;
begin
  if (ACtx.CurrentFrameIndex >= 0) and (ACtx.CurrentFrameIndex < ACtx.CellCount) and GetCellRect(ACtx.CurrentFrameIndex, ACtx).Contains(APoint) then
    Result := ACtx.CurrentFrameIndex
  else
    Result := -1;
end;

{TSmartGridLayout}

function TSmartGridLayout.GetColumnCount(const ACtx: TViewLayoutContext): Integer;
begin
  Result := 1; {not meaningful for smart grid}
end;

procedure TSmartGridLayout.CalcRows(const ACtx: TViewLayoutContext);
var
  N, R, BestR, Base, Extra, I, CellsInRow: Integer;
  BestScore, Score, DisplayedAR, OrigAR: Double;
  CellH, CellW: Double;
  Rows: TArray<TSmartRow>;
begin
  N := ACtx.CellCount;
  if (N = 0) or (ACtx.BaseW <= 0) or (ACtx.BaseH <= 0) then
  begin
    SetLength(FSmartRows, 0);
    Exit;
  end;

  OrigAR := ACtx.AspectRatio;
  if OrigAR <= 0 then
    OrigAR := DEF_ASPECT_RATIO;

  BestR := 1;
  BestScore := MaxDouble;

  {Try each possible row count and find the one with least cropping.
   Cell dimensions include gap subtraction so the scoring reflects how the
   cells will actually render -- otherwise gap>0 would bias the score
   toward row counts that cram more cells per row than they can fit cleanly.}
  for R := 1 to N do
  begin
    Score := 0;
    Base := N div R;
    Extra := N mod R;
    CellH := Max(1.0, (ACtx.BaseH - (R - 1) * ACtx.CellGap) / R);
    for I := 0 to R - 1 do
    begin
      if I < Extra then
        CellsInRow := Base + 1
      else
        CellsInRow := Max(1, Base);
      CellW := Max(1.0, (ACtx.BaseW - (CellsInRow - 1) * ACtx.CellGap) / CellsInRow);
      DisplayedAR := CellH / CellW;
      Score := Score + Abs(DisplayedAR - OrigAR);
    end;

    if Score < BestScore then
    begin
      BestScore := Score;
      BestR := R;
    end;
  end;

  {Build row array with BestR rows}
  SetLength(Rows, BestR);
  Base := N div BestR;
  Extra := N mod BestR;
  for I := 0 to BestR - 1 do
  begin
    if I < Extra then
      Rows[I].Count := Base + 1
    else
      Rows[I].Count := Base;
  end;

  FSmartRows := Rows;
end;

function TSmartGridLayout.GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
var
  RowIdx, CellInRow, RowTop, RowH, CellW, PrevCount, Gap: Integer;
  OffX, OffY: Integer;
begin
  if Length(FSmartRows) = 0 then
    Exit(Rect(0, 0, 1, 1));

  Gap := ACtx.CellGap;
  RowH := Max(1, (ACtx.BaseH - (Length(FSmartRows) - 1) * Gap) div Length(FSmartRows));

  {Find which row this index belongs to}
  PrevCount := 0;
  for RowIdx := 0 to High(FSmartRows) do
  begin
    if AIndex < PrevCount + FSmartRows[RowIdx].Count then
    begin
      CellInRow := AIndex - PrevCount;
      CellW := Max(1, (ACtx.BaseW - (FSmartRows[RowIdx].Count - 1) * Gap) div Max(1, FSmartRows[RowIdx].Count));
      RowTop := RowIdx * (RowH + Gap);

      {Last row/cell fills remaining space to absorb rounding remainder.
       Gaps sit between cells only, so the last cell's right edge is BaseW
       and the last row's bottom edge is BaseH -- no gap trails after them}
      Result.Left := CellInRow * (CellW + Gap);
      if CellInRow = FSmartRows[RowIdx].Count - 1 then
        Result.Right := ACtx.BaseW
      else
        Result.Right := Result.Left + CellW;

      Result.Top := RowTop;
      if RowIdx = High(FSmartRows) then
        Result.Bottom := ACtx.BaseH
      else
        Result.Bottom := RowTop + RowH;

      {Apply continuous zoom}
      if not SameValue(ACtx.ZoomFactor, 1.0, ZOOM_EPSILON) then
      begin
        Result.Left := Round(Result.Left * ACtx.ZoomFactor);
        Result.Top := Round(Result.Top * ACtx.ZoomFactor);
        Result.Right := Round(Result.Right * ACtx.ZoomFactor);
        Result.Bottom := Round(Result.Bottom * ACtx.ZoomFactor);
      end;

      {Center when zoomed content is smaller than control}
      OffX := Max(0, (ACtx.ClientWidth - Round(ACtx.BaseW * ACtx.ZoomFactor)) div 2);
      OffY := Max(0, (ACtx.ClientHeight - Round(ACtx.BaseH * ACtx.ZoomFactor)) div 2);
      if (OffX > 0) or (OffY > 0) then
        Result.Offset(OffX, OffY);

      Exit;
    end;
    Inc(PrevCount, FSmartRows[RowIdx].Count);
  end;

  Result := Rect(0, 0, 1, 1);
end;

function TSmartGridLayout.RecalcSize(const ACtx: TViewLayoutContext): TSize;
begin
  CalcRows(ACtx);
  Result.cx := Max(ACtx.ViewportW, Round(ACtx.BaseW * ACtx.ZoomFactor));
  Result.cy := Max(ACtx.ViewportH, Round(ACtx.BaseH * ACtx.ZoomFactor));
end;

function TSmartGridLayout.WheelScrollKind: TLayoutWheelAction;
begin
  Result := lwaVerticalScroll;
end;

{Factory}

function CreateViewModeLayout(AMode: TViewMode): TViewModeLayout;
begin
  case AMode of
    vmGrid:
      Result := TGridLayout.Create;
    vmSmartGrid:
      Result := TSmartGridLayout.Create;
    vmScroll:
      Result := TScrollLayout.Create;
    vmFilmstrip:
      Result := TFilmstripLayout.Create;
    vmSingle:
      Result := TSingleLayout.Create;
    else
      Result := TGridLayout.Create;
  end;
end;

end.
