{Custom control that renders video frame cells in various layout modes:
 grid, scroll, filmstrip, single frame, and smart grid.}
unit uFrameView;

interface

uses
  System.Classes, System.Types,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Graphics,
  uTypes, uSettings, uDefaults, uFrameOffsets, uViewModeLayout;

type
  TFrameCellState = (fcsPlaceholder, fcsLoaded, fcsError);

  TFrameCell = record
    State: TFrameCellState;
    Bitmap: TBitmap;
    Timecode: string;
    TimeOffset: Double;
    Selected: Boolean;
  end;

  TCtrlWheelEvent = procedure(Sender: TObject; AWheelDelta: Integer) of object;

  {Custom control that renders frame cells in various layout modes.}
  TFrameView = class(TCustomControl)
  strict private
    FCells: TArray<TFrameCell>;
  private
    FViewMode: TViewMode;
    FZoomMode: TZoomMode;
    FBackColor: TColor;
    FAnimStep: Integer;
    FCellGap: Integer;
    FCellMargin: Integer;
    FTimestampCorner: TTimestampCorner;
    FColumnCount: Integer;
    FCurrentFrameIndex: Integer;
    FAspectRatio: Double;
    FNativeW: Integer;
    FNativeH: Integer;
    FViewportW: Integer;
    FViewportH: Integer;
    FBaseViewportW: Integer; {frozen viewport for layout when zoomed}
    FBaseViewportH: Integer;
    FZoomFactor: Double;
    FShowTimecode: Boolean;
    FTimecodeBackColor: TColor;
    FTimecodeBackAlpha: Byte;
    FTimestampTextAlpha: Byte;
    FTimestampTextColor: TColor;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBlendBmp: TBitmap; {reusable 1x1 bitmap for alpha-blended timecode background}
    FBlendBmpColor: TColor; {cached color to avoid redundant Pixels[] writes}
    FTextBlendBmp: TBitmap; {offscreen bitmap for alpha-blended timecode text; resized on demand}
    FOnCtrlWheel: TCtrlWheelEvent;
    FLayout: TViewModeLayout;
    function GetBaseW: Integer;
    function GetBaseH: Integer;
    function BuildLayoutContext: TViewLayoutContext;
    function TimecodeRectFromCell(const ACellRect: TRect; AIndex: Integer): TRect;
    procedure SetViewMode(AValue: TViewMode);
    procedure SetCellGap(AValue: Integer);
    procedure SetCellMargin(AValue: Integer);
    procedure SetTimestampCorner(AValue: TTimestampCorner);
    procedure SetBackColor(AValue: TColor);
    procedure SetTimecodeBackColor(AValue: TColor);
    procedure SetTimecodeBackAlpha(AValue: Byte);
    procedure SetTimestampTextAlpha(AValue: Byte);
    procedure SetTimestampTextColor(AValue: TColor);
    procedure SetTimestampFontName(const AValue: string);
    procedure SetTimestampFontSize(AValue: Integer);
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
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
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
    property ViewMode: TViewMode read FViewMode write SetViewMode;
    property ZoomMode: TZoomMode read FZoomMode write FZoomMode;
    property AspectRatio: Double read FAspectRatio write FAspectRatio;
    property NativeW: Integer read FNativeW write FNativeW;
    property NativeH: Integer read FNativeH write FNativeH;
    property BackColor: TColor read FBackColor write SetBackColor;
    property CurrentFrameIndex: Integer read FCurrentFrameIndex write FCurrentFrameIndex;
    property ZoomFactor: Double read FZoomFactor write FZoomFactor;
    property ShowTimecode: Boolean read FShowTimecode write SetShowTimecode;
    property TimecodeBackColor: TColor read FTimecodeBackColor write SetTimecodeBackColor;
    property TimecodeBackAlpha: Byte read FTimecodeBackAlpha write SetTimecodeBackAlpha;
    property TimestampTextAlpha: Byte read FTimestampTextAlpha write SetTimestampTextAlpha;
    property TimestampTextColor: TColor read FTimestampTextColor write SetTimestampTextColor;
    property TimestampFontName: string read FTimestampFontName write SetTimestampFontName;
    property TimestampFontSize: Integer read FTimestampFontSize write SetTimestampFontSize;
    property CellGap: Integer read FCellGap write SetCellGap;
    property CellMargin: Integer read FCellMargin write SetCellMargin;
    property TimestampCorner: TTimestampCorner read FTimestampCorner write SetTimestampCorner;
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
  TIMECODE_H = 20;

  {Painting colors}
  CLR_CELL_BG = TColor($002D2D2D); {dark gray cell/placeholder background}
  CLR_ARC = TColor($00707070); {loading spinner arc}
  CLR_ERROR_TEXT = TColor($004040FF); {error cell label}
  CLR_SELECTION = TColor($00F7C34F); {#4FC3F7 light blue selection border}
  SELECTION_BORDER_W = 2;

  {Painting fonts and sizes}
  FONT_NAME = 'Segoe UI';
  FONT_TIMECODE = 8;
  FONT_ERROR = 9;
  TIMECODE_PADDING = 8; {horizontal padding inside timecode label}
  ARC_PEN_WIDTH = 3;
  ARC_RADIUS_DIV = 8; {spinner radius = min(cell dim) div this}
  MIN_ARC_RADIUS = 5; {skip spinner if cell too small}
  ARC_ANGLE_STEP = 45.0; {spinner rotation angle per animation tick}
  ANIM_STEP_COUNT = Round(360.0 / ARC_ANGLE_STEP);

constructor TFrameView.Create(AOwner: TComponent);
begin
  inherited;
  DoubleBuffered := True;
  FCellGap := DEF_CELL_GAP;
  FCellMargin := DEF_COMBINED_BORDER;
  FTimestampCorner := DEF_TIMESTAMP_CORNER;
  FShowTimecode := True;
  FTimecodeBackColor := DEF_TC_BACK_COLOR;
  FTimecodeBackAlpha := DEF_TC_BACK_ALPHA;
  FTimestampTextAlpha := DEF_TIMESTAMP_TEXT_ALPHA;
  FTimestampTextColor := DEF_TIMESTAMP_TEXT_COLOR;
  FTimestampFontName := DEF_TIMESTAMP_FONT;
  FTimestampFontSize := DEF_TIMESTAMP_FONT_SIZE;
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
  FBlendBmpColor := TColor(-1); {force first-use update}
  FTextBlendBmp := TBitmap.Create;
  FTextBlendBmp.PixelFormat := pf24bit;
  FLayout := CreateViewModeLayout(vmGrid);
end;

destructor TFrameView.Destroy;
begin
  ClearCells;
  FLayout.Free;
  FBlendBmp.Free;
  FTextBlendBmp.Free;
  inherited;
end;

procedure TFrameView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TFrameView.WMMouseWheel(var Message: TWMMouseWheel);
begin
  {Ctrl+Wheel: delegate to owner for zoom}
  if (Message.Keys and MK_CONTROL) <> 0 then
  begin
    if Assigned(FOnCtrlWheel) then
      FOnCtrlWheel(Self, Message.WheelDelta);
    Message.Result := 1;
    Exit;
  end;

  case FLayout.WheelScrollKind of
    lwaNavigateFrame:
      begin
        if Message.WheelDelta > 0 then
          NavigateFrame(-1)
        else
          NavigateFrame(1);
        Message.Result := 1;
      end;
    lwaHorizontalScroll:
      begin
        if Parent is TScrollBox then
        begin
          TScrollBox(Parent).HorzScrollBar.Position := TScrollBox(Parent).HorzScrollBar.Position - Message.WheelDelta;
          Message.Result := 1;
        end
        else
          inherited;
      end;
    lwaVerticalScroll:
      begin
        if Parent is TScrollBox then
        begin
          TScrollBox(Parent).VertScrollBar.Position := TScrollBox(Parent).VertScrollBar.Position - Message.WheelDelta;
          Message.Result := 1;
        end
        else
          inherited;
      end;
  end;
end;

procedure TFrameView.SetViewport(AW, AH: Integer);
begin
  FViewportW := AW;
  FViewportH := AH;
  {Freeze base viewport when at zoom=1.0; keep frozen while zoomed so
   cell sizes stay constant across window resizes}
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

function TFrameView.BuildLayoutContext: TViewLayoutContext;
var
  Margin2: Integer;
begin
  {Margin acts as an outer frame: layouts are given a viewport shrunk by the
   margin on every side. Cells are then shifted by +margin when drawn, and
   the control grows by 2*margin in RecalcSize. Keeps all layout math
   unchanged while the margin logic lives at the TFrameView boundary.}
  Margin2 := 2 * FCellMargin;
  Result.BaseW := Max(1, BaseW - Margin2);
  Result.BaseH := Max(1, BaseH - Margin2);
  Result.CellCount := Length(FCells);
  Result.CellGap := FCellGap;
  Result.AspectRatio := FAspectRatio;
  Result.NativeW := FNativeW;
  Result.NativeH := FNativeH;
  Result.ZoomMode := FZoomMode;
  Result.ZoomFactor := FZoomFactor;
  Result.ClientWidth := Max(1, ClientWidth - Margin2);
  Result.ClientHeight := Max(1, ClientHeight - Margin2);
  Result.CurrentFrameIndex := FCurrentFrameIndex;
  Result.ViewportW := Max(1, FViewportW - Margin2);
  Result.ViewportH := Max(1, FViewportH - Margin2);
  Result.ColumnCount := FColumnCount;
end;

procedure TFrameView.SetViewMode(AValue: TViewMode);
begin
  if FViewMode = AValue then
    Exit;
  FViewMode := AValue;
  FreeAndNil(FLayout);
  FLayout := CreateViewModeLayout(AValue);
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

function TFrameView.GetCellRect(AIndex: Integer): TRect;
begin
  Result := FLayout.GetCellRect(AIndex, BuildLayoutContext);
  if FCellMargin <> 0 then
    Result.Offset(FCellMargin, FCellMargin);
end;

function TFrameView.TimecodeRectFromCell(const ACellRect: TRect; AIndex: Integer): TRect;
var
  TW: Integer;
begin
  Canvas.Font.Name := FTimestampFontName;
  Canvas.Font.Size := FTimestampFontSize;
  TW := Canvas.TextWidth(FCells[AIndex].Timecode) + TIMECODE_PADDING;
  case FTimestampCorner of
    tcTopLeft:
      Result := Rect(ACellRect.Left, ACellRect.Top, ACellRect.Left + TW, ACellRect.Top + TIMECODE_H);
    tcTopRight:
      Result := Rect(ACellRect.Right - TW, ACellRect.Top, ACellRect.Right, ACellRect.Top + TIMECODE_H);
    tcBottomRight:
      Result := Rect(ACellRect.Right - TW, ACellRect.Bottom - TIMECODE_H, ACellRect.Right, ACellRect.Bottom);
    else {tcBottomLeft}
      Result := Rect(ACellRect.Left, ACellRect.Bottom - TIMECODE_H, ACellRect.Left + TW, ACellRect.Bottom);
  end;
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
  end else begin
    {Skip cells that are entirely outside the clip region. In scroll/filmstrip
     modes only a few cells are visible at a time, so this avoids GDI overhead
     for up to 99 off-screen cells.}
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
    fcsPlaceholder:
      PaintPlaceholder(R);
    fcsLoaded:
      if FViewMode = vmSmartGrid then
        PaintCropToFill(AIndex, R)
      else
        PaintLoadedFrame(AIndex, R);
    fcsError:
      PaintErrorCell(R);
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
  {Scale to fit cell, maintaining aspect ratio}
  Scale := Min(ARect.Width / Max(1, Bmp.Width), ARect.Height / Max(1, Bmp.Height));
  DW := Round(Bmp.Width * Scale);
  DH := Round(Bmp.Height * Scale);
  DstR.Left := ARect.Left + (ARect.Width - DW) div 2;
  DstR.Top := ARect.Top + (ARect.Height - DH) div 2;
  DstR.Right := DstR.Left + DW;
  DstR.Bottom := DstR.Top + DH;

  {Fill letterbox area}
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
  {Scale so smaller dimension fills the cell, crop the excess}
  Scale := Max(ARect.Width / Max(1, Bmp.Width), ARect.Height / Max(1, Bmp.Height));
  SrcW := Min(Bmp.Width, Round(ARect.Width / Scale));
  SrcH := Min(Bmp.Height, Round(ARect.Height / Scale));
  SrcR.Left := (Bmp.Width - SrcW) div 2;
  SrcR.Top := (Bmp.Height - SrcH) div 2;
  SrcR.Right := SrcR.Left + SrcW;
  SrcR.Bottom := SrcR.Top + SrcH;

  {HALFTONE averages source pixels properly; default BLACKONWHITE ANDs
   channel values independently, corrupting colors when downscaling}
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
  if Radius < MIN_ARC_RADIUS then
    Exit;

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
  if FShowTimecode = AValue then
    Exit;
  FShowTimecode := AValue;
  Invalidate;
end;

procedure TFrameView.SetBackColor(AValue: TColor);
begin
  if FBackColor = AValue then
    Exit;
  FBackColor := AValue;
  Invalidate;
end;

procedure TFrameView.SetTimecodeBackColor(AValue: TColor);
begin
  if FTimecodeBackColor = AValue then
    Exit;
  FTimecodeBackColor := AValue;
  {Reset cached blend color so AlphaBlend picks up the new hue next paint}
  FBlendBmpColor := TColor(-1);
  Invalidate;
end;

procedure TFrameView.SetTimecodeBackAlpha(AValue: Byte);
begin
  if FTimecodeBackAlpha = AValue then
    Exit;
  FTimecodeBackAlpha := AValue;
  Invalidate;
end;

procedure TFrameView.SetTimestampTextAlpha(AValue: Byte);
begin
  if FTimestampTextAlpha = AValue then
    Exit;
  FTimestampTextAlpha := AValue;
  Invalidate;
end;

procedure TFrameView.SetTimestampTextColor(AValue: TColor);
begin
  if FTimestampTextColor = AValue then
    Exit;
  FTimestampTextColor := AValue;
  Invalidate;
end;

procedure TFrameView.SetTimestampFontName(const AValue: string);
begin
  if FTimestampFontName = AValue then
    Exit;
  FTimestampFontName := AValue;
  Invalidate;
end;

procedure TFrameView.SetTimestampFontSize(AValue: Integer);
begin
  if FTimestampFontSize = AValue then
    Exit;
  FTimestampFontSize := AValue;
  Invalidate;
end;

procedure TFrameView.SetCellGap(AValue: Integer);
begin
  if FCellGap = AValue then
    Exit;
  FCellGap := AValue;
  {Cell gap affects component size in every layout mode; recalc so the
   scrollbox picks up the new dimensions and triggers a repaint.}
  RecalcSize;
  Invalidate;
end;

procedure TFrameView.SetCellMargin(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if FCellMargin = AValue then
    Exit;
  FCellMargin := AValue;
  RecalcSize;
  Invalidate;
end;

procedure TFrameView.SetTimestampCorner(AValue: TTimestampCorner);
begin
  if FTimestampCorner = AValue then
    Exit;
  FTimestampCorner := AValue;
  Invalidate;
end;

procedure TFrameView.PaintTimecode(AIndex: Integer; const ACellRect: TRect);
var
  R, LocalR: TRect;
  BF: TBlendFunction;
  TextColor: TColor;
begin
  if not FShowTimecode then
    Exit;
  if FTimestampCorner = tcNone then
    Exit;
  if FCells[AIndex].Timecode = '' then
    Exit;

  R := TimecodeRectFromCell(ACellRect, AIndex);
  Canvas.Font.Name := FTimestampFontName;
  Canvas.Font.Size := FTimestampFontSize;

  {Alpha-blended background for readability. Drawn independently of text alpha
   so users can disable text entirely while keeping a visible background.}
  if FTimecodeBackAlpha > 0 then
  begin
    if FTimecodeBackAlpha = 255 then
    begin
      Canvas.Brush.Color := FTimecodeBackColor;
      Canvas.Brush.Style := bsSolid;
      Canvas.FillRect(R);
    end else begin
      if FBlendBmpColor <> FTimecodeBackColor then
      begin
        FBlendBmp.Canvas.Pixels[0, 0] := FTimecodeBackColor;
        FBlendBmpColor := FTimecodeBackColor;
      end;
      BF.BlendOp := AC_SRC_OVER;
      BF.BlendFlags := 0;
      BF.SourceConstantAlpha := FTimecodeBackAlpha;
      BF.AlphaFormat := 0;
      Winapi.Windows.AlphaBlend(Canvas.Handle, R.Left, R.Top, R.Width, R.Height, FBlendBmp.Canvas.Handle, 0, 0, 1, 1, BF);
    end;
  end;

  if FTimestampTextAlpha = 0 then
    Exit;

  {Pending cells use the same hue at half luminance: the user's color choice
   still reads through, and the existing load-fade cue is preserved without
   a second configurable field.}
  if FCells[AIndex].State = fcsLoaded then
    TextColor := FTimestampTextColor
  else
    TextColor := RGB(GetRValue(FTimestampTextColor) shr 1,
                     GetGValue(FTimestampTextColor) shr 1,
                     GetBValue(FTimestampTextColor) shr 1);

  if FTimestampTextAlpha = 255 then
  begin
    {Fast path: opaque text straight onto canvas}
    Canvas.Font.Color := TextColor;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(FCells[AIndex].Timecode), -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    Exit;
  end;

  {Partial text opacity: blit the target region onto an offscreen bitmap,
   DrawText onto it, then AlphaBlend it back with SourceConstantAlpha. This
   blends the text correctly over the (already-painted) frame pixels.}
  if (FTextBlendBmp.Width < R.Width) or (FTextBlendBmp.Height < R.Height) then
    FTextBlendBmp.SetSize(Max(R.Width, FTextBlendBmp.Width), Max(R.Height, FTextBlendBmp.Height));

  BitBlt(FTextBlendBmp.Canvas.Handle, 0, 0, R.Width, R.Height, Canvas.Handle, R.Left, R.Top, SRCCOPY);

  FTextBlendBmp.Canvas.Font.Name := FTimestampFontName;
  FTextBlendBmp.Canvas.Font.Size := FTimestampFontSize;
  FTextBlendBmp.Canvas.Font.Color := TextColor;
  FTextBlendBmp.Canvas.Brush.Style := bsClear;
  LocalR := Rect(0, 0, R.Width, R.Height);
  DrawText(FTextBlendBmp.Canvas.Handle, PChar(FCells[AIndex].Timecode), -1, LocalR, DT_CENTER or DT_VCENTER or DT_SINGLELINE);

  BF.BlendOp := AC_SRC_OVER;
  BF.BlendFlags := 0;
  BF.SourceConstantAlpha := FTimestampTextAlpha;
  BF.AlphaFormat := 0;
  Winapi.Windows.AlphaBlend(Canvas.Handle, R.Left, R.Top, R.Width, R.Height, FTextBlendBmp.Canvas.Handle, 0, 0, R.Width, R.Height, BF);
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
    end else begin
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
    {Copy pixel data via raw memory, bypassing GDI entirely.
     Canvas.Draw on a bitmap created by another thread intermittently
     fails because the GDI DC handle is not reliably usable cross-thread.}
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
  FAnimStep := (FAnimStep + 1) mod ANIM_STEP_COUNT;
  Invalidate;
end;

procedure TFrameView.RecalcSize;
var
  Sz: TSize;
begin
  if Length(FCells) = 0 then
  begin
    Width := FViewportW;
    Height := FViewportH;
    Exit;
  end;
  Sz := FLayout.RecalcSize(BuildLayoutContext);
  Width := Sz.CX + 2 * FCellMargin;
  Height := Sz.CY + 2 * FCellMargin;
end;

procedure TFrameView.NavigateFrame(ADelta: Integer);
var
  NewIdx: Integer;
begin
  if Length(FCells) = 0 then
    Exit;
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
  P: TPoint;
begin
  P := APoint;
  if FCellMargin <> 0 then
  begin
    P.X := P.X - FCellMargin;
    P.Y := P.Y - FCellMargin;
  end;
  Result := FLayout.CellIndexAt(P, BuildLayoutContext);
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

procedure TFrameView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
