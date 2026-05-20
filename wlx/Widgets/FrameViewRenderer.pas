{Frame-cell painting for the frame view: the per-cell paint paths
 (placeholder spinner, fitted frame, crop-to-fill, error cell), the
 timecode overlay and the selection border. Given a canvas plus the cell
 store and geometry, it draws the whole control.

 The painting itself has no automated coverage, so changes here need a
 manual check in the running plugin.}
unit FrameViewRenderer;

interface

uses
  System.Types,
  Vcl.Graphics,
  FrameCellStore,
  FrameGeometry,
  ViewModeLayout,
  TimecodeOverlay;

type
  TFrameViewRenderer = class
  strict private
    FCanvas: TCanvas;
    FCellStore: TFrameCellStore;
    FGeometry: TFrameGeometry;
    FStyle: TTimestampStyle;
    FBlendBmp: TBitmap; {reusable 1x1 bitmap for alpha-blended timecode background}
    FTextBlendBmp: TBitmap; {offscreen bitmap for alpha-blended timecode text; resized on demand}
    FAnimStep: Integer;
    FBackColor: TColor;
    FCtx: TViewLayoutContext; {layout context, valid only for the duration of one Paint}
    function GetShowTimecode: Boolean;
    procedure SetShowTimecode(AValue: Boolean);
    function TimecodeRectFromCell(const ACellRect: TRect; AIndex: Integer): TRect;
    procedure PaintCell(AIndex: Integer);
    procedure PaintPlaceholder(const ARect: TRect);
    procedure PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
    procedure PaintCropToFill(AIndex: Integer; const ARect: TRect);
    procedure PaintArc(const ARect: TRect);
    procedure PaintTimecode(AIndex: Integer; const ACellRect: TRect);
    procedure PaintErrorCell(const ARect: TRect);
  public
    {ACanvas, ACellStore and AGeometry are borrowed; TFrameView owns them.}
    constructor Create(ACanvas: TCanvas; ACellStore: TFrameCellStore; AGeometry: TFrameGeometry);
    destructor Destroy; override;

    {Paints the whole control: the background fill, then the visible cells.}
    procedure Paint(const AClientRect: TRect; ACurrentFrameIndex: Integer);
    {Advances the placeholder spinner by one tick.}
    procedure AdvanceAnimation;
    {Assigns the timecode style, returning True only when a visible field
     actually changed, so the caller can skip a needless repaint.}
    function ApplyTimestampStyle(const AValue: TTimestampStyle): Boolean;

    property BackColor: TColor read FBackColor write FBackColor;
    property ShowTimecode: Boolean read GetShowTimecode write SetShowTimecode;
    property TimestampStyle: TTimestampStyle read FStyle;
    property AnimStep: Integer read FAnimStep;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Types,
  Defaults,
  Settings,
  RenderDefaults;

type
  {Re-bind TBitmap to the VCL class: Winapi.Windows, used for the GDI calls
   below, declares a TBITMAP record that would otherwise shadow
   Vcl.Graphics.TBitmap and break the bitmap-typed code here.}
  TBitmap = Vcl.Graphics.TBitmap;

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
  FONT_ERROR = 9;
  TIMECODE_PADDING = 8; {horizontal padding inside timecode label}
  ARC_PEN_WIDTH = 3;
  ARC_RADIUS_DIV = 8; {spinner radius = min(cell dim) div this}
  MIN_ARC_RADIUS = 5; {skip spinner if cell too small}
  ARC_ANGLE_STEP = 45.0; {spinner rotation angle per animation tick}
  ANIM_STEP_COUNT = Round(360.0 / ARC_ANGLE_STEP);

constructor TFrameViewRenderer.Create(ACanvas: TCanvas; ACellStore: TFrameCellStore; AGeometry: TFrameGeometry);
begin
  inherited Create;
  FCanvas := ACanvas;
  FCellStore := ACellStore;
  FGeometry := AGeometry;
  FStyle := DefaultTimestampStyle;
  FStyle.Show := True;
  FStyle.FontName := DEF_TIMESTAMP_FONT;
  FStyle.FontSize := DEF_TIMESTAMP_FONT_SIZE;
  FStyle.FontStyles := []; {live-view timecodes render non-bold (canvas default)}
  FStyle.BackAlpha := DEF_TC_BACK_ALPHA;
  {Live view always uses the modern rect renderer to match what the
   user sees on screen; legacy mode is a combined-image-only concern.}
  FStyle.Mode := tsmModern;
  FBackColor := DEF_BACKGROUND;
  FAnimStep := 0;
  FBlendBmp := TBitmap.Create;
  FBlendBmp.PixelFormat := pf24bit;
  FBlendBmp.SetSize(1, 1);
  FTextBlendBmp := TBitmap.Create;
  FTextBlendBmp.PixelFormat := pf24bit;
end;

destructor TFrameViewRenderer.Destroy;
begin
  FBlendBmp.Free;
  FTextBlendBmp.Free;
  inherited;
end;

function TFrameViewRenderer.GetShowTimecode: Boolean;
begin
  Result := FStyle.Show;
end;

procedure TFrameViewRenderer.SetShowTimecode(AValue: Boolean);
begin
  FStyle.Show := AValue;
end;

function TFrameViewRenderer.ApplyTimestampStyle(const AValue: TTimestampStyle): Boolean;
begin
  {Field-by-field compare rather than a single record-equality check because
   TTimestampStyle contains a managed string (FontName) compared by value.}
  Result := not ((FStyle.Show = AValue.Show) and (FStyle.Corner = AValue.Corner) and
    (FStyle.FontName = AValue.FontName) and (FStyle.FontSize = AValue.FontSize) and
    (FStyle.FontStyles = AValue.FontStyles) and (FStyle.BackColor = AValue.BackColor) and
    (FStyle.BackAlpha = AValue.BackAlpha) and (FStyle.TextColor = AValue.TextColor) and
    (FStyle.TextAlpha = AValue.TextAlpha));
  if Result then
    FStyle := AValue;
end;

procedure TFrameViewRenderer.AdvanceAnimation;
begin
  FAnimStep := (FAnimStep + 1) mod ANIM_STEP_COUNT;
end;

function TFrameViewRenderer.TimecodeRectFromCell(const ACellRect: TRect; AIndex: Integer): TRect;
var
  TW: Integer;
begin
  FCanvas.Font.Name := FStyle.FontName;
  FCanvas.Font.Size := FStyle.FontSize;
  FCanvas.Font.Style := FStyle.FontStyles;
  TW := FCanvas.TextWidth(FCellStore.Timecode(AIndex)) + TIMECODE_PADDING;
  case FStyle.Corner of
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

procedure TFrameViewRenderer.Paint(const AClientRect: TRect; ACurrentFrameIndex: Integer);
var
  I: Integer;
  Clip, Dummy: TRect;
begin
  FCtx := FGeometry.BuildContext(AClientRect.Width, AClientRect.Height, ACurrentFrameIndex);
  FCanvas.Brush.Color := FBackColor;
  FCanvas.FillRect(AClientRect);

  if FGeometry.ViewMode = vmSingle then
  begin
    if (ACurrentFrameIndex >= 0) and (ACurrentFrameIndex < FCellStore.Count) then
      PaintCell(ACurrentFrameIndex);
  end else begin
    {Skip cells that are entirely outside the clip region. In scroll/filmstrip
     modes only a few cells are visible at a time, so this avoids GDI overhead
     for up to 99 off-screen cells.}
    Clip := FCanvas.ClipRect;
    for I := 0 to FCellStore.Count - 1 do
      if IntersectRect(Dummy, FGeometry.GetCellRect(I, FCtx), Clip) then
        PaintCell(I);
  end;
end;

procedure TFrameViewRenderer.PaintCell(AIndex: Integer);
var
  R: TRect;
begin
  R := FGeometry.GetCellRect(AIndex, FCtx);
  case FCellStore.State(AIndex) of
    fcsPlaceholder:
      PaintPlaceholder(R);
    fcsLoaded:
      if FGeometry.ViewMode = vmSmartGrid then
        PaintCropToFill(AIndex, R)
      else
        PaintLoadedFrame(AIndex, R);
    fcsError:
      PaintErrorCell(R);
  end;
  PaintTimecode(AIndex, R);
  if FCellStore.Selected(AIndex) then
  begin
    FCanvas.Pen.Color := CLR_SELECTION;
    FCanvas.Pen.Width := SELECTION_BORDER_W;
    FCanvas.Pen.Style := psSolid;
    FCanvas.Brush.Style := bsClear;
    R.Inflate(-SELECTION_BORDER_W div 2, -SELECTION_BORDER_W div 2);
    FCanvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
  end;
end;

procedure TFrameViewRenderer.PaintPlaceholder(const ARect: TRect);
begin
  FCanvas.Brush.Color := CLR_CELL_BG;
  FCanvas.Pen.Style := psClear;
  FCanvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  PaintArc(ARect);
end;

procedure TFrameViewRenderer.PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
var
  Bmp: TBitmap;
  DstR: TRect;
  Scale: Double;
  DW, DH: Integer;
begin
  Bmp := FCellStore.Bitmap(AIndex);
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
  FCanvas.Brush.Color := CLR_CELL_BG;
  FCanvas.FillRect(ARect);
  FCanvas.StretchDraw(DstR, Bmp);
end;

procedure TFrameViewRenderer.PaintCropToFill(AIndex: Integer; const ARect: TRect);
var
  Bmp: TBitmap;
  SrcR: TRect;
  Scale: Double;
  SrcW, SrcH: Integer;
begin
  Bmp := FCellStore.Bitmap(AIndex);
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
  SetStretchBltMode(FCanvas.Handle, HALFTONE);
  SetBrushOrgEx(FCanvas.Handle, 0, 0, nil);
  FCanvas.CopyRect(ARect, Bmp.Canvas, SrcR);
end;

procedure TFrameViewRenderer.PaintArc(const ARect: TRect);
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
  FCanvas.Pen.Color := CLR_ARC;
  FCanvas.Pen.Width := ARC_PEN_WIDTH;
  FCanvas.Pen.Style := psSolid;

  for I := 0 to SEGMENTS do
  begin
    Angle := DegToRad(StartAngle + I * ARC_SPAN / SEGMENTS);
    X := CX + Round(Radius * Cos(Angle));
    Y := CY - Round(Radius * Sin(Angle));
    if I = 0 then
      FCanvas.MoveTo(X, Y)
    else
      FCanvas.LineTo(X, Y);
  end;
end;

procedure TFrameViewRenderer.PaintTimecode(AIndex: Integer; const ACellRect: TRect);
var
  R: TRect;
  EffectiveStyle: TTimestampStyle;
begin
  if not FStyle.Show then
    Exit;
  if FStyle.Corner = tcNone then
    Exit;
  if FCellStore.Timecode(AIndex) = '' then
    Exit;

  R := TimecodeRectFromCell(ACellRect, AIndex);

  {Pending cells dim the configured text color to half luminance so the
   load-fade cue stays visible with any user-chosen hue.}
  EffectiveStyle := FStyle;
  if FCellStore.State(AIndex) <> fcsLoaded then
    EffectiveStyle.TextColor := RGB(
      GetRValue(FStyle.TextColor) shr 1,
      GetGValue(FStyle.TextColor) shr 1,
      GetBValue(FStyle.TextColor) shr 1);

  DrawTimecodeOverlay(FCanvas, R, FCellStore.Timecode(AIndex), EffectiveStyle, FBlendBmp, FTextBlendBmp);
end;

procedure TFrameViewRenderer.PaintErrorCell(const ARect: TRect);
var
  R: TRect;
begin
  FCanvas.Brush.Color := CLR_CELL_BG;
  FCanvas.Pen.Style := psClear;
  FCanvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  FCanvas.Font.Name := FONT_NAME;
  FCanvas.Font.Size := FONT_ERROR;
  FCanvas.Font.Color := CLR_ERROR_TEXT;
  FCanvas.Brush.Style := bsClear;
  R := ARect;
  DrawText(FCanvas.Handle, 'Error', -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

end.
