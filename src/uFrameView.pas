{ Custom control that renders video frame cells in various layout modes:
  grid, scroll, filmstrip, single frame, and smart grid. }
unit uFrameView;

interface

uses
  System.Classes, System.Types,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Graphics,
  uSettings, uFrameOffsets;

const
  DEF_ASPECT_RATIO = 9.0 / 16.0; { fallback for 16:9 video }

type
  TFrameCellState = (fcsPlaceholder, fcsLoaded, fcsError);

  TFrameCell = record
    State: TFrameCellState;
    Bitmap: TBitmap;
    Timecode: string;
    TimeOffset: Double;
    Selected: Boolean;
  end;

  TSmartRow = record
    Count: Integer;
  end;

  TCtrlWheelEvent = procedure(Sender: TObject; AWheelDelta: Integer) of object;

  { Custom control that renders frame cells in various layout modes. }
  TFrameView = class(TCustomControl)
  strict private
    FCells: TArray<TFrameCell>;
  private
    FViewMode: TViewMode;
    FZoomMode: TZoomMode;
    FBackColor: TColor;
    FAnimStep: Integer;
    FCellGap: Integer;
    FColumnCount: Integer;
    FCurrentFrameIndex: Integer;
    FAspectRatio: Double;
    FNativeW: Integer;
    FNativeH: Integer;
    FViewportW: Integer;
    FViewportH: Integer;
    FBaseViewportW: Integer;  { frozen viewport for layout when zoomed }
    FBaseViewportH: Integer;
    FZoomFactor: Double;
    FShowTimecode: Boolean;
    FTimecodeBackColor: TColor;
    FTimecodeBackAlpha: Byte;
    FSmartRows: TArray<TSmartRow>;
    FBlendBmp: TBitmap;          { reusable 1x1 bitmap for alpha-blended timecode background }
    FBlendBmpColor: TColor;      { cached color to avoid redundant Pixels[] writes }
    FOnCtrlWheel: TCtrlWheelEvent;
    function GetBaseW: Integer;
    function GetBaseH: Integer;
    function GetColumnCount: Integer;
    function GetCellImageSize: TSize;
    function GetCellRectGrid(AIndex: Integer): TRect;
    function GetCellRectScroll(AIndex: Integer): TRect;
    function GetCellRectFilmstrip(AIndex: Integer): TRect;
    function GetCellRectSingle(AIndex: Integer): TRect;
    function GetCellRectSmartGrid(AIndex: Integer): TRect;
    function TimecodeRectFromCell(const ACellRect: TRect; AIndex: Integer): TRect;
    procedure CalcSmartGridLayout;
    procedure PaintCell(AIndex: Integer);
    procedure PaintPlaceholder(const ARect: TRect);
    procedure PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
    procedure PaintCropToFill(AIndex: Integer; const ARect: TRect);
    procedure PaintArc(const ARect: TRect);
    procedure PaintTimecode(AIndex: Integer; const ACellRect: TRect);
    procedure PaintErrorCell(const ARect: TRect);
    procedure SetShowTimecode(AValue: Boolean);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMMouseWheel(var Message: TWMMouseWheel); message WM_MOUSEWHEEL;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetCellRect(AIndex: Integer): TRect;
    function CellIndexAt(const APoint: TPoint): Integer;
    procedure ToggleSelection(AIndex: Integer);
    procedure SelectAll;
    procedure DeselectAll;
    function SelectedCount: Integer;
    procedure SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
    procedure SetFrame(AIndex: Integer; ABitmap: TBitmap);
    procedure SetCellError(AIndex: Integer);
    procedure ClearCells;
    function HasPlaceholders: Boolean;
    procedure AdvanceAnimation;
    procedure RecalcSize;
    function CalcFitColumns(AViewportW, AViewportH: Integer): Integer;
    function DefaultColumnCount: Integer;
    procedure NavigateFrame(ADelta: Integer);
    procedure SetViewport(AW, AH: Integer);
    function CellCount: Integer;
    function CellState(AIndex: Integer): TFrameCellState;
    function CellBitmap(AIndex: Integer): TBitmap;
    function CellTimeOffset(AIndex: Integer): Double;
    function CellTimecode(AIndex: Integer): string;
    function CellSelected(AIndex: Integer): Boolean;
    property ColumnCount: Integer read FColumnCount write FColumnCount;
    property ViewMode: TViewMode read FViewMode write FViewMode;
    property ZoomMode: TZoomMode read FZoomMode write FZoomMode;
    property AspectRatio: Double read FAspectRatio write FAspectRatio;
    property NativeW: Integer read FNativeW write FNativeW;
    property NativeH: Integer read FNativeH write FNativeH;
    property BackColor: TColor read FBackColor write FBackColor;
    property CurrentFrameIndex: Integer read FCurrentFrameIndex write FCurrentFrameIndex;
    property ZoomFactor: Double read FZoomFactor write FZoomFactor;
    property ShowTimecode: Boolean read FShowTimecode write SetShowTimecode;
    property TimecodeBackColor: TColor read FTimecodeBackColor write FTimecodeBackColor;
    property TimecodeBackAlpha: Byte read FTimecodeBackAlpha write FTimecodeBackAlpha;
    property OnCtrlWheel: TCtrlWheelEvent read FOnCtrlWheel write FOnCtrlWheel;
    property PopupMenu;
    property BaseW: Integer read GetBaseW;
    property BaseH: Integer read GetBaseH;
  end;

implementation

uses
  System.SysUtils, System.Math,
  Vcl.Forms,
  uZoomController;

const
  CELL_GAP       = 4;
  TIMECODE_H     = 20;

  { Painting colors }
  CLR_CELL_BG         = TColor($002D2D2D); { dark gray cell/placeholder background }
  CLR_ARC             = TColor($00707070); { loading spinner arc }
  CLR_TIMECODE_OVERLAY = TColor($00CCCCCC); { timecode text over smart grid cells }
  CLR_TIMECODE_PENDING = TColor($00555555); { timecode text for placeholders }
  CLR_ERROR_TEXT       = TColor($004040FF); { error cell label }
  CLR_SELECTION        = TColor($00F7C34F); { #4FC3F7 light blue selection border }
  SELECTION_BORDER_W   = 2;

  { Painting fonts and sizes }
  FONT_NAME         = 'Segoe UI';
  FONT_TIMECODE     = 8;
  FONT_ERROR        = 9;
  TIMECODE_PADDING  = 8;  { horizontal padding inside timecode label }
  ARC_PEN_WIDTH     = 3;
  ARC_RADIUS_DIV    = 8;  { spinner radius = min(cell dim) div this }
  MIN_ARC_RADIUS    = 5;  { skip spinner if cell too small }
  ARC_ANGLE_STEP    = 45.0; { spinner rotation angle per animation tick }

constructor TFrameView.Create(AOwner: TComponent);
begin
  inherited;
  DoubleBuffered := True;
  FCellGap := CELL_GAP;
  FShowTimecode := True;
  FTimecodeBackColor := DEF_TC_BACK_COLOR;
  FTimecodeBackAlpha := DEF_TC_BACK_ALPHA;
  FBackColor := DEF_BACKGROUND;
  FViewMode := vmGrid;
  FZoomMode := zmFitWindow;
  FAnimStep := 0;
  FColumnCount := 0;
  FCurrentFrameIndex := 0;
  FAspectRatio := DEF_ASPECT_RATIO;
  FNativeW := 0;
  FNativeH := 0;
  FViewportW := 0;
  FViewportH := 0;
  FBaseViewportW := 0;
  FBaseViewportH := 0;
  FZoomFactor := 1.0;
  FBlendBmp := TBitmap.Create;
  FBlendBmp.SetSize(1, 1);
  FBlendBmpColor := TColor(-1); { force first-use update }
end;

destructor TFrameView.Destroy;
begin
  ClearCells;
  FBlendBmp.Free;
  inherited;
end;

procedure TFrameView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TFrameView.WMMouseWheel(var Message: TWMMouseWheel);
begin
  { Ctrl+Wheel: delegate to owner for zoom }
  if (Message.Keys and MK_CONTROL) <> 0 then
  begin
    if Assigned(FOnCtrlWheel) then
      FOnCtrlWheel(Self, Message.WheelDelta);
    Message.Result := 1;
    Exit;
  end;

  case FViewMode of
    vmSingle:
      begin
        if Message.WheelDelta > 0 then
          NavigateFrame(-1)
        else
          NavigateFrame(1);
        Message.Result := 1;
      end;
    vmFilmstrip:
      begin
        if Parent is TScrollBox then
        begin
          TScrollBox(Parent).HorzScrollBar.Position :=
            TScrollBox(Parent).HorzScrollBar.Position - Message.WheelDelta;
          Message.Result := 1;
        end
        else
          inherited;
      end;
  else
    if Parent is TScrollBox then
    begin
      TScrollBox(Parent).VertScrollBar.Position :=
        TScrollBox(Parent).VertScrollBar.Position - Message.WheelDelta;
      Message.Result := 1;
    end
    else
      inherited;
  end;
end;

procedure TFrameView.SetViewport(AW, AH: Integer);
begin
  FViewportW := AW;
  FViewportH := AH;
  { Freeze base viewport when at zoom=1.0; keep frozen while zoomed so
    cell sizes stay constant across window resizes }
  if SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
  begin
    FBaseViewportW := AW;
    FBaseViewportH := AH;
  end;
end;

function TFrameView.GetBaseW: Integer;
begin
  if (FBaseViewportW > 0) and not SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
    Result := FBaseViewportW
  else
    Result := FViewportW;
end;

function TFrameView.GetBaseH: Integer;
begin
  if (FBaseViewportH > 0) and not SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
    Result := FBaseViewportH
  else
    Result := FViewportH;
end;

function TFrameView.GetColumnCount: Integer;
begin
  case FViewMode of
    vmScroll, vmSingle:
      Result := 1;
    vmFilmstrip:
      Result := Max(1, Length(FCells));
    vmSmartGrid:
      Result := 1; { not used for smart grid layout }
  else { vmGrid }
    begin
      if Length(FCells) <= 1 then
        Exit(1);
      { Original size: columns based on native frame width }
      if (FZoomMode = zmActual) and (FNativeW > 0) then
        Exit(Max(1, (BaseW - FCellGap) div (FNativeW + FCellGap)));
      if FColumnCount > 0 then
        Exit(FColumnCount);
      Result := Max(1, Floor(Sqrt(Length(FCells))));
    end;
  end;
end;

function TFrameView.DefaultColumnCount: Integer;
begin
  if (FViewMode = vmScroll) or (Length(FCells) <= 1) then
    Result := 1
  else
    Result := Max(1, Floor(Sqrt(Length(FCells))));
end;

function TFrameView.CalcFitColumns(AViewportW, AViewportH: Integer): Integer;
var
  C, Rows, CellW, CellH, RowH, TotalH: Integer;
begin
  if (Length(FCells) <= 1) or (AViewportW <= 0) or (AViewportH <= 0) then
    Exit(1);
  for C := 1 to Length(FCells) do
  begin
    CellW := Max(1, (AViewportW - (C + 1) * FCellGap) div C);
    CellH := Max(1, Round(CellW * FAspectRatio));
    RowH := CellH + FCellGap;
    Rows := (Length(FCells) + C - 1) div C;
    TotalH := FCellGap + Rows * RowH;
    if TotalH <= AViewportH then
      Exit(C);
  end;
  Result := Length(FCells);
end;

function TFrameView.GetCellImageSize: TSize;
var
  Cols, AvailW: Integer;
begin
  Cols := GetColumnCount;
  AvailW := BaseW - (Cols + 1) * FCellGap;
  Result.cx := Max(1, Round(AvailW / Cols * FZoomFactor));
  Result.cy := Max(1, Round(Result.cx * FAspectRatio));
end;

function TFrameView.GetCellRect(AIndex: Integer): TRect;
begin
  case FViewMode of
    vmScroll:    Result := GetCellRectScroll(AIndex);
    vmGrid:      Result := GetCellRectGrid(AIndex);
    vmSmartGrid: Result := GetCellRectSmartGrid(AIndex);
    vmFilmstrip: Result := GetCellRectFilmstrip(AIndex);
    vmSingle:    Result := GetCellRectSingle(AIndex);
  else
    Result := GetCellRectGrid(AIndex);
  end;
end;

function TFrameView.GetCellRectGrid(AIndex: Integer): TRect;
var
  Cols, Col, Row, Rows: Integer;
  Sz: TSize;
  RowH, GridW, GridH, OffsetX, OffsetY: Integer;
begin
  Cols := GetColumnCount;
  Sz := GetCellImageSize;
  Col := AIndex mod Cols;
  Row := AIndex div Cols;
  Rows := Ceil(Length(FCells) / Max(1, Cols));
  RowH := Sz.cy + FCellGap;

  GridW := Cols * (Sz.cx + FCellGap) + FCellGap;
  GridH := FCellGap + Rows * RowH;

  { Center grid horizontally }
  if GridW < ClientWidth then
    OffsetX := (ClientWidth - GridW) div 2
  else
    OffsetX := 0;

  { Center grid vertically }
  if GridH < ClientHeight then
    OffsetY := (ClientHeight - GridH) div 2
  else
    OffsetY := 0;

  Result.Left   := OffsetX + FCellGap + Col * (Sz.cx + FCellGap);
  Result.Top    := OffsetY + FCellGap + Row * RowH;
  Result.Right  := Result.Left + Sz.cx;
  Result.Bottom := Result.Top + Sz.cy;
end;

function TFrameView.GetCellRectScroll(AIndex: Integer): TRect;
var
  CellW, CellH, RowH, LeftX: Integer;
begin
  case FZoomMode of
    zmActual:
      begin
        CellW := Max(1, FNativeW);
        CellH := Max(1, FNativeH);
      end;
    zmFitIfLarger:
      begin
        CellW := Max(1, BaseW - 2 * FCellGap);
        if (FNativeW > 0) and (FNativeW < CellW) then
          CellW := FNativeW;
        CellH := Max(1, Round(CellW * FAspectRatio));
      end;
  else { zmFitWindow }
    begin
      CellW := Max(1, BaseW - 2 * FCellGap);
      CellH := Max(1, Round(CellW * FAspectRatio));
    end;
  end;

  { Apply continuous zoom }
  CellW := Max(1, Round(CellW * FZoomFactor));
  CellH := Max(1, Round(CellH * FZoomFactor));

  { Center horizontally when cell is narrower than control }
  if CellW + 2 * FCellGap < ClientWidth then
    LeftX := (ClientWidth - CellW) div 2
  else
    LeftX := FCellGap;

  RowH := CellH + FCellGap;
  Result.Left   := LeftX;
  Result.Top    := FCellGap + AIndex * RowH;
  Result.Right  := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TFrameView.GetCellRectFilmstrip(AIndex: Integer): TRect;
var
  CellH, CellW, AvailH, TopY: Integer;
begin
  AvailH := Max(1, BaseH - 2 * FCellGap);

  case FZoomMode of
    zmActual:
      CellH := Max(1, FNativeH);
    zmFitIfLarger:
      begin
        CellH := AvailH;
        if (FNativeH > 0) and (FNativeH < CellH) then
          CellH := FNativeH;
      end;
  else { zmFitWindow }
    CellH := AvailH;
  end;

  { Apply continuous zoom }
  CellH := Max(1, Round(CellH * FZoomFactor));
  CellW := Max(1, Round(CellH / Max(FAspectRatio, DEF_ASPECT_RATIO)));

  { Center vertically within control (ClientHeight reflects post-RecalcSize size) }
  if CellH < AvailH then
    TopY := (ClientHeight - CellH) div 2
  else
    TopY := FCellGap;

  Result.Left   := FCellGap + AIndex * (CellW + FCellGap);
  Result.Top    := TopY;
  Result.Right  := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TFrameView.GetCellRectSingle(AIndex: Integer): TRect;
var
  CellW, CellH: Integer;
  AvailW, AvailH: Integer;
begin
  { Base available space from frozen viewport, not control size }
  AvailW := Max(1, BaseW - 2 * FCellGap);
  AvailH := Max(1, BaseH - 2 * FCellGap);

  case FZoomMode of
    zmActual:
      begin
        CellW := Max(1, FNativeW);
        CellH := Max(1, FNativeH);
      end;
    zmFitIfLarger:
      begin
        if (FNativeW > 0) and (FNativeH > 0) and
           (FNativeW <= AvailW) and (FNativeH <= AvailH) then
        begin
          CellW := FNativeW;
          CellH := FNativeH;
        end
        else
        begin
          CellW := AvailW;
          CellH := Round(CellW * FAspectRatio);
          if CellH > AvailH then
          begin
            CellH := AvailH;
            CellW := Round(CellH / Max(FAspectRatio, DEF_ASPECT_RATIO));
          end;
        end;
      end;
  else { zmFitWindow }
    begin
      CellW := AvailW;
      CellH := Round(CellW * FAspectRatio);
      if CellH > AvailH then
      begin
        CellH := AvailH;
        CellW := Round(CellH / Max(FAspectRatio, DEF_ASPECT_RATIO));
      end;
    end;
  end;

  { Apply continuous zoom }
  CellW := Max(1, Round(CellW * FZoomFactor));
  CellH := Max(1, Round(CellH * FZoomFactor));

  { Center in control (ClientWidth may exceed viewport when zoomed) }
  Result.Left   := (ClientWidth - CellW) div 2;
  Result.Top    := FCellGap + (Max(1, ClientHeight - 2 * FCellGap) - CellH) div 2;
  Result.Right  := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TFrameView.GetCellRectSmartGrid(AIndex: Integer): TRect;
var
  RowIdx, CellInRow, RowTop, RowH, CellW, PrevCount: Integer;
  OffX, OffY: Integer;
begin
  if Length(FSmartRows) = 0 then
    Exit(Rect(0, 0, 1, 1));

  RowH := BaseH div Length(FSmartRows);

  { Find which row this index belongs to }
  PrevCount := 0;
  for RowIdx := 0 to High(FSmartRows) do
  begin
    if AIndex < PrevCount + FSmartRows[RowIdx].Count then
    begin
      CellInRow := AIndex - PrevCount;
      CellW := BaseW div Max(1, FSmartRows[RowIdx].Count);
      RowTop := RowIdx * RowH;

      { Last row/cell fills remaining space to avoid rounding gaps }
      Result.Left := CellInRow * CellW;
      if CellInRow = FSmartRows[RowIdx].Count - 1 then
        Result.Right := BaseW
      else
        Result.Right := Result.Left + CellW;

      Result.Top := RowTop;
      if RowIdx = High(FSmartRows) then
        Result.Bottom := BaseH
      else
        Result.Bottom := RowTop + RowH;

      { Apply continuous zoom }
      if not SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
      begin
        Result.Left   := Round(Result.Left * FZoomFactor);
        Result.Top    := Round(Result.Top * FZoomFactor);
        Result.Right  := Round(Result.Right * FZoomFactor);
        Result.Bottom := Round(Result.Bottom * FZoomFactor);
      end;

      { Center when zoomed content is smaller than control }
      OffX := Max(0, (ClientWidth - Round(BaseW * FZoomFactor)) div 2);
      OffY := Max(0, (ClientHeight - Round(BaseH * FZoomFactor)) div 2);
      if (OffX > 0) or (OffY > 0) then
        Result.Offset(OffX, OffY);

      Exit;
    end;
    Inc(PrevCount, FSmartRows[RowIdx].Count);
  end;

  Result := Rect(0, 0, 1, 1);
end;

procedure TFrameView.CalcSmartGridLayout;
var
  N, R, BestR, Base, Extra, I: Integer;
  BestScore, Score, DisplayedAR, OrigAR: Double;
  Rows: TArray<TSmartRow>;
begin
  N := Length(FCells);
  if (N = 0) or (BaseW <= 0) or (BaseH <= 0) then
  begin
    SetLength(FSmartRows, 0);
    Exit;
  end;

  if FAspectRatio <= 0 then
    FAspectRatio := DEF_ASPECT_RATIO;
  OrigAR := FAspectRatio; { height/width ratio }

  BestR := 1;
  BestScore := MaxDouble;

  { Try each possible row count and find the one with least cropping }
  for R := 1 to N do
  begin
    { Score: sum of per-row aspect ratio deviation }
    Score := 0;
    Base := N div R;
    Extra := N mod R;
    for I := 0 to R - 1 do
    begin
      if I < Extra then
        DisplayedAR := (BaseH / R) / (BaseW / (Base + 1))
      else
        DisplayedAR := (BaseH / R) / (BaseW / Max(1, Base));
      Score := Score + Abs(DisplayedAR - OrigAR);
    end;

    if Score < BestScore then
    begin
      BestScore := Score;
      BestR := R;
    end;
  end;

  { Build row array with BestR rows }
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

function TFrameView.TimecodeRectFromCell(const ACellRect: TRect; AIndex: Integer): TRect;
var
  TW: Integer;
begin
  Canvas.Font.Name := FONT_NAME;
  Canvas.Font.Size := FONT_TIMECODE;
  TW := Canvas.TextWidth(FCells[AIndex].Timecode) + TIMECODE_PADDING;
  Result := Rect(ACellRect.Left, ACellRect.Bottom - TIMECODE_H,
    ACellRect.Left + TW, ACellRect.Bottom);
end;

procedure TFrameView.Paint;
var
  I: Integer;
  Clip, Dummy: TRect;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);

  if FViewMode = vmSingle then
  begin
    if (FCurrentFrameIndex >= 0) and (FCurrentFrameIndex < Length(FCells)) then
      PaintCell(FCurrentFrameIndex);
  end
  else
  begin
    { Skip cells that are entirely outside the clip region. In scroll/filmstrip
      modes only a few cells are visible at a time, so this avoids GDI overhead
      for up to 99 off-screen cells. }
    Clip := Canvas.ClipRect;
    for I := 0 to High(FCells) do
      if IntersectRect(Dummy, GetCellRect(I), Clip) then
        PaintCell(I);
  end;
end;

procedure TFrameView.PaintCell(AIndex: Integer);
var
  R: TRect;
begin
  R := GetCellRect(AIndex);
  case FCells[AIndex].State of
    fcsPlaceholder: PaintPlaceholder(R);
    fcsLoaded:
      if FViewMode = vmSmartGrid then
        PaintCropToFill(AIndex, R)
      else
        PaintLoadedFrame(AIndex, R);
    fcsError: PaintErrorCell(R);
  end;
  PaintTimecode(AIndex, R);
  if FCells[AIndex].Selected then
  begin
    Canvas.Pen.Color := CLR_SELECTION;
    Canvas.Pen.Width := SELECTION_BORDER_W;
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    R.Inflate(-SELECTION_BORDER_W div 2, -SELECTION_BORDER_W div 2);
    Canvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
  end;
end;

procedure TFrameView.PaintPlaceholder(const ARect: TRect);
begin
  Canvas.Brush.Color := CLR_CELL_BG;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  PaintArc(ARect);
end;

procedure TFrameView.PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
var
  Bmp: TBitmap;
  DstR: TRect;
  Scale: Double;
  DW, DH: Integer;
begin
  Bmp := FCells[AIndex].Bitmap;
  if Bmp = nil then
  begin
    PaintPlaceholder(ARect);
    Exit;
  end;
  { Scale to fit cell, maintaining aspect ratio }
  Scale := Min(ARect.Width / Max(1, Bmp.Width),
               ARect.Height / Max(1, Bmp.Height));
  DW := Round(Bmp.Width * Scale);
  DH := Round(Bmp.Height * Scale);
  DstR.Left   := ARect.Left + (ARect.Width - DW) div 2;
  DstR.Top    := ARect.Top + (ARect.Height - DH) div 2;
  DstR.Right  := DstR.Left + DW;
  DstR.Bottom := DstR.Top + DH;

  { Fill letterbox area }
  Canvas.Brush.Color := CLR_CELL_BG;
  Canvas.FillRect(ARect);
  Canvas.StretchDraw(DstR, Bmp);
end;

procedure TFrameView.PaintCropToFill(AIndex: Integer; const ARect: TRect);
var
  Bmp: TBitmap;
  SrcR: TRect;
  Scale: Double;
  SrcW, SrcH: Integer;
begin
  Bmp := FCells[AIndex].Bitmap;
  if Bmp = nil then
  begin
    PaintPlaceholder(ARect);
    Exit;
  end;
  { Scale so smaller dimension fills the cell, crop the excess }
  Scale := Max(ARect.Width / Max(1, Bmp.Width),
               ARect.Height / Max(1, Bmp.Height));
  SrcW := Min(Bmp.Width, Round(ARect.Width / Scale));
  SrcH := Min(Bmp.Height, Round(ARect.Height / Scale));
  SrcR.Left   := (Bmp.Width - SrcW) div 2;
  SrcR.Top    := (Bmp.Height - SrcH) div 2;
  SrcR.Right  := SrcR.Left + SrcW;
  SrcR.Bottom := SrcR.Top + SrcH;

  { HALFTONE averages source pixels properly; default BLACKONWHITE ANDs
    channel values independently, corrupting colors when downscaling }
  SetStretchBltMode(Canvas.Handle, HALFTONE);
  SetBrushOrgEx(Canvas.Handle, 0, 0, nil);
  Canvas.CopyRect(ARect, Bmp.Canvas, SrcR);
end;

procedure TFrameView.PaintArc(const ARect: TRect);
var
  CX, CY, Radius, I: Integer;
  StartAngle, Angle: Double;
  X, Y: Integer;
const
  ARC_SPAN = 90.0;
  SEGMENTS = 12;
begin
  CX := (ARect.Left + ARect.Right) div 2;
  CY := (ARect.Top + ARect.Bottom) div 2;
  Radius := Min(ARect.Width, ARect.Height) div ARC_RADIUS_DIV;
  if Radius < MIN_ARC_RADIUS then Exit;

  StartAngle := FAnimStep * ARC_ANGLE_STEP;
  Canvas.Pen.Color := CLR_ARC;
  Canvas.Pen.Width := ARC_PEN_WIDTH;
  Canvas.Pen.Style := psSolid;

  for I := 0 to SEGMENTS do
  begin
    Angle := DegToRad(StartAngle + I * ARC_SPAN / SEGMENTS);
    X := CX + Round(Radius * Cos(Angle));
    Y := CY - Round(Radius * Sin(Angle));
    if I = 0 then
      Canvas.MoveTo(X, Y)
    else
      Canvas.LineTo(X, Y);
  end;
end;

procedure TFrameView.SetShowTimecode(AValue: Boolean);
begin
  if FShowTimecode = AValue then Exit;
  FShowTimecode := AValue;
end;

procedure TFrameView.PaintTimecode(AIndex: Integer; const ACellRect: TRect);
var
  R: TRect;
  BF: TBlendFunction;
begin
  if not FShowTimecode then Exit;
  if FCells[AIndex].Timecode = '' then Exit;
  R := TimecodeRectFromCell(ACellRect, AIndex);
  Canvas.Font.Name := FONT_NAME;
  Canvas.Font.Size := FONT_TIMECODE;

  { Alpha-blended background for readability }
  if FTimecodeBackAlpha > 0 then
  begin
    if FTimecodeBackAlpha = 255 then
    begin
      Canvas.Brush.Color := FTimecodeBackColor;
      Canvas.Brush.Style := bsSolid;
      Canvas.FillRect(R);
    end
    else
    begin
      if FBlendBmpColor <> FTimecodeBackColor then
      begin
        FBlendBmp.Canvas.Pixels[0, 0] := FTimecodeBackColor;
        FBlendBmpColor := FTimecodeBackColor;
      end;
      BF.BlendOp := AC_SRC_OVER;
      BF.BlendFlags := 0;
      BF.SourceConstantAlpha := FTimecodeBackAlpha;
      BF.AlphaFormat := 0;
      Winapi.Windows.AlphaBlend(Canvas.Handle, R.Left, R.Top, R.Width, R.Height,
        FBlendBmp.Canvas.Handle, 0, 0, 1, 1, BF);
    end;
  end;

  if FCells[AIndex].State = fcsLoaded then
    Canvas.Font.Color := CLR_TIMECODE_OVERLAY
  else
    Canvas.Font.Color := CLR_TIMECODE_PENDING;

  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(FCells[AIndex].Timecode), -1, R,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TFrameView.PaintErrorCell(const ARect: TRect);
var
  R: TRect;
begin
  Canvas.Brush.Color := CLR_CELL_BG;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  Canvas.Font.Name := FONT_NAME;
  Canvas.Font.Size := FONT_ERROR;
  Canvas.Font.Color := CLR_ERROR_TEXT;
  Canvas.Brush.Style := bsClear;
  R := ARect;
  DrawText(Canvas.Handle, 'Error', -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TFrameView.SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
var
  I: Integer;
begin
  SetLength(FCells, ACount);
  for I := 0 to ACount - 1 do
  begin
    FCells[I].State := fcsPlaceholder;
    FCells[I].Bitmap := nil;
    if (AOffsets <> nil) and (I < Length(AOffsets)) then
    begin
      FCells[I].Timecode := FormatTimecode(AOffsets[I].TimeOffset);
      FCells[I].TimeOffset := AOffsets[I].TimeOffset;
    end
    else
    begin
      FCells[I].Timecode := '';
      FCells[I].TimeOffset := 0;
    end;
  end;
  FCurrentFrameIndex := 0;
end;

procedure TFrameView.SetFrame(AIndex: Integer; ABitmap: TBitmap);
var
  Copy: TBitmap;
  Y, BytesPerRow: Integer;
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
  begin
    { Copy pixel data via raw memory, bypassing GDI entirely.
      Canvas.Draw on a bitmap created by another thread intermittently
      fails because the GDI DC handle is not reliably usable cross-thread. }
    Copy := TBitmap.Create;
    Copy.PixelFormat := pf24bit;
    Copy.SetSize(ABitmap.Width, ABitmap.Height);
    BytesPerRow := ABitmap.Width * 3;
    for Y := 0 to ABitmap.Height - 1 do
      Move(ABitmap.ScanLine[Y]^, Copy.ScanLine[Y]^, BytesPerRow);
    ABitmap.Free;

    FCells[AIndex].State := fcsLoaded;
    FCells[AIndex].Bitmap := Copy;
    Invalidate;
  end
  else
    ABitmap.Free;
end;

procedure TFrameView.SetCellError(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
  begin
    FCells[AIndex].State := fcsError;
    Invalidate;
  end;
end;

procedure TFrameView.ClearCells;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FreeAndNil(FCells[I].Bitmap);
  SetLength(FCells, 0);
  FCurrentFrameIndex := 0;
end;

function TFrameView.HasPlaceholders: Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    if FCells[I].State = fcsPlaceholder then
      Exit(True);
  Result := False;
end;

procedure TFrameView.AdvanceAnimation;
begin
  FAnimStep := (FAnimStep + 1) mod 8;
  Invalidate;
end;

procedure TFrameView.RecalcSize;
var
  Cols, Rows, GridW: Integer;
  Sz: TSize;
  N: Integer;
  R0: TRect;
begin
  N := Length(FCells);
  if N = 0 then
  begin
    Width := FViewportW;
    Height := FViewportH;
    Exit;
  end;

  case FViewMode of
    vmSmartGrid:
      begin
        CalcSmartGridLayout;
        Width := Max(FViewportW, Round(BaseW * FZoomFactor));
        Height := Max(FViewportH, Round(BaseH * FZoomFactor));
      end;
    vmSingle:
      begin
        R0 := GetCellRectSingle(FCurrentFrameIndex);
        Width := Max(FViewportW, R0.Width + 2 * FCellGap);
        Height := Max(FViewportH, R0.Height + 2 * FCellGap);
      end;
    vmFilmstrip:
      begin
        R0 := GetCellRectFilmstrip(0);
        Width := Max(FViewportW, FCellGap + N * (R0.Width + FCellGap));
        Height := Max(FViewportH, R0.Height + 2 * FCellGap);
      end;
    vmScroll:
      begin
        R0 := GetCellRectScroll(0);
        Width := Max(FViewportW, R0.Width + 2 * FCellGap);
        Height := Max(FViewportH, FCellGap + N * (R0.Height + FCellGap));
      end;
  else { vmGrid }
    begin
      Cols := GetColumnCount;
      Sz := GetCellImageSize;
      Rows := Ceil(N / Cols);
      GridW := Cols * (Sz.cx + FCellGap) + FCellGap;
      Width := Max(FViewportW, GridW);
      Height := Max(FViewportH, FCellGap + Rows * (Sz.cy + FCellGap));
    end;
  end;
end;

procedure TFrameView.NavigateFrame(ADelta: Integer);
var
  NewIdx: Integer;
begin
  if Length(FCells) = 0 then Exit;
  NewIdx := FCurrentFrameIndex + ADelta;
  if NewIdx < 0 then
    NewIdx := 0
  else if NewIdx >= Length(FCells) then
    NewIdx := Length(FCells) - 1;
  if NewIdx <> FCurrentFrameIndex then
  begin
    FCurrentFrameIndex := NewIdx;
    Invalidate;
  end;
end;

function TFrameView.CellCount: Integer;
begin
  Result := Length(FCells);
end;

function TFrameView.CellState(AIndex: Integer): TFrameCellState;
begin
  Result := FCells[AIndex].State;
end;

function TFrameView.CellBitmap(AIndex: Integer): TBitmap;
begin
  Result := FCells[AIndex].Bitmap;
end;

function TFrameView.CellTimeOffset(AIndex: Integer): Double;
begin
  Result := FCells[AIndex].TimeOffset;
end;

function TFrameView.CellTimecode(AIndex: Integer): string;
begin
  Result := FCells[AIndex].Timecode;
end;

function TFrameView.CellSelected(AIndex: Integer): Boolean;
begin
  Result := FCells[AIndex].Selected;
end;

function TFrameView.CellIndexAt(const APoint: TPoint): Integer;
var
  I: Integer;
begin
  if FViewMode = vmSingle then
  begin
    if (FCurrentFrameIndex >= 0) and (FCurrentFrameIndex < Length(FCells))
      and GetCellRect(FCurrentFrameIndex).Contains(APoint) then
      Exit(FCurrentFrameIndex);
    Exit(-1);
  end;
  for I := 0 to High(FCells) do
    if GetCellRect(I).Contains(APoint) then
      Exit(I);
  Result := -1;
end;

procedure TFrameView.ToggleSelection(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
  begin
    FCells[AIndex].Selected := not FCells[AIndex].Selected;
    Invalidate;
  end;
end;

procedure TFrameView.SelectAll;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FCells[I].Selected := True;
  Invalidate;
end;

procedure TFrameView.DeselectAll;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FCells[I].Selected := False;
  Invalidate;
end;

function TFrameView.SelectedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCells) do
    if FCells[I].Selected then
      Inc(Result);
end;

procedure TFrameView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Idx: Integer;
begin
  inherited;
  if (Button = mbLeft) and (ssCtrl in Shift) then
  begin
    Idx := CellIndexAt(Point(X, Y));
    if Idx >= 0 then
      ToggleSelection(Idx);
  end;
end;

end.
