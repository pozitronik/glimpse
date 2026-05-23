{View mode layout strategies: compute cell positions, sizes, and scroll
 behaviour. Adding a view mode means adding a class, not editing switches.}
unit ViewModeLayout;

interface

uses
  System.Types,
  Types;

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

  TScrollbarPolicy = record
    HorzVisible: Boolean;
    VertVisible: Boolean;
  end;

{AIsZoomed reflects the live ZoomFactor (independent of ZoomMode) —
 zmActual at ZoomFactor=1.0 still needs the actual-size scroll rules.}
function GetScrollbarPolicy(AMode: TViewMode; AZoom: TZoomMode; AIsZoomed: Boolean): TScrollbarPolicy;

{zmFitWindow = AFitCols; zmFitIfLarger = Max(AFitCols, ADefCols);
 zmActual = 0 ("let the layout strategy decide").}
function GridColumnCountFor(AZoom: TZoomMode; AFitCols, ADefCols: Integer): Integer;

type
  {Abstract base: each subclass defines geometry for one view mode.}
  TViewModeLayout = class abstract
  public
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect; virtual; abstract;
    function GetColumnCount(const ACtx: TViewLayoutContext): Integer; virtual; abstract;
    function RecalcSize(const ACtx: TViewLayoutContext): TSize; virtual; abstract;
    function WheelScrollKind: TLayoutWheelAction; virtual; abstract;
    {Default scans every index and returns the first cell rect containing
     APoint. Subclasses MAY restrict the result to a single active cell
     when only one is rendered (TSingleLayout returns the current frame
     index or -1, ignoring other cells whose rects would otherwise hit).
     Callers must not assume "if GetCellRect(I).Contains(APoint) then
     CellIndexAt(APoint) = I" — that holds for the grid layouts but not
     for restricted overrides.}
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

  {Returns per-row cell counts (sum = ACellCount) for the row layout that
   minimises aspect-ratio mismatch between displayed cells and the source.
   Shared between live view and save path so saved images match the view.}
function ComputeSmartGridRows(ACellCount, ABaseW, ABaseH, ACellGap: Integer; AAspectRatio: Double): TArray<Integer>;

function CreateViewModeLayout(AMode: TViewMode): TViewModeLayout;

implementation

uses
  System.SysUtils, System.Math, ZoomController;

function GetScrollbarPolicy(AMode: TViewMode; AZoom: TZoomMode; AIsZoomed: Boolean): TScrollbarPolicy;
begin
  case AMode of
    vmScroll:
      begin
        Result.HorzVisible := AIsZoomed or (AZoom = zmActual);
        Result.VertVisible := True;
      end;
    vmGrid:
      begin
        Result.HorzVisible := AIsZoomed;
        Result.VertVisible := True;
      end;
    vmSmartGrid, vmSingle:
      begin
        Result.HorzVisible := AIsZoomed;
        Result.VertVisible := AIsZoomed;
      end;
    vmFilmstrip:
      begin
        Result.HorzVisible := True;
        Result.VertVisible := AIsZoomed or (AZoom = zmActual);
      end;
  else
    Result.HorzVisible := False;
    Result.VertVisible := False;
  end;
end;

function GridColumnCountFor(AZoom: TZoomMode; AFitCols, ADefCols: Integer): Integer;
begin
  case AZoom of
    zmFitWindow:   Result := AFitCols;
    zmFitIfLarger: Result := Max(AFitCols, ADefCols);
  else
    Result := 0;
  end;
end;

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
  {Gaps live between cells only — caller adds outer padding via CellMargin.}
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

  {Outer margin is added by TFrameView via CellMargin; layout starts at 0.}
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

  {Outer margin is added by TFrameView via CellMargin; layout starts at 0.}
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
  {Use frozen viewport, not control size; outer margin added by TFrameView.}
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
  RowCounts: TArray<Integer>;
  Rows: TArray<TSmartRow>;
  I: Integer;
begin
  if (ACtx.CellCount = 0) or (ACtx.BaseW <= 0) or (ACtx.BaseH <= 0) then
  begin
    SetLength(FSmartRows, 0);
    Exit;
  end;

  RowCounts := ComputeSmartGridRows(ACtx.CellCount, ACtx.BaseW, ACtx.BaseH, ACtx.CellGap, ACtx.AspectRatio);
  SetLength(Rows, Length(RowCounts));
  for I := 0 to High(RowCounts) do
    Rows[I].Count := RowCounts[I];

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

      {Last cell/row absorbs the rounding remainder out to BaseW/BaseH.}
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

function ComputeSmartGridRows(ACellCount, ABaseW, ABaseH, ACellGap: Integer; AAspectRatio: Double): TArray<Integer>;
var
  N, R, BestR, Base, Extra, I, CellsInRow: Integer;
  BestScore, Score, DisplayedAR, OrigAR: Double;
  CellH, CellW: Double;
begin
  N := ACellCount;
  if (N <= 0) or (ABaseW <= 0) or (ABaseH <= 0) then
    Exit(nil);

  OrigAR := AAspectRatio;
  if OrigAR <= 0 then
    OrigAR := DEF_ASPECT_RATIO;

  BestR := 1;
  BestScore := MaxDouble;

  {Score with gap subtraction so the row count reflects actual rendering;
   without subtraction, gap>0 would bias toward overpacked rows.}
  for R := 1 to N do
  begin
    Score := 0;
    Base := N div R;
    Extra := N mod R;
    CellH := Max(1.0, (ABaseH - (R - 1) * ACellGap) / R);
    for I := 0 to R - 1 do
    begin
      if I < Extra then
        CellsInRow := Base + 1
      else
        CellsInRow := Max(1, Base);
      CellW := Max(1.0, (ABaseW - (CellsInRow - 1) * ACellGap) / CellsInRow);
      DisplayedAR := CellH / CellW;
      Score := Score + Abs(DisplayedAR - OrigAR);
    end;

    if Score < BestScore then
    begin
      BestScore := Score;
      BestR := R;
    end;
  end;

  SetLength(Result, BestR);
  Base := N div BestR;
  Extra := N mod BestR;
  for I := 0 to BestR - 1 do
  begin
    if I < Extra then
      Result[I] := Base + 1
    else
      Result[I] := Base;
  end;
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
      {Raise loudly on an unmapped TViewMode value so the omission cannot hide as a silent TGridLayout.}
      raise EArgumentException.CreateFmt(
        'CreateViewModeLayout: no factory branch for TViewMode(%d)', [Ord(AMode)]);
  end;
end;

end.
