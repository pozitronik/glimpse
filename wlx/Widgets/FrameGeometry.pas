{Viewport, zoom and layout geometry for the frame view: the sizing state,
 the per-view-mode layout strategy, and cell-rect / hit-test / content-size
 queries. A plain non-visual class, unit-testable on its own; TFrameView
 owns one and delegates geometry to it.}
unit FrameGeometry;

interface

uses
  System.Types,
  Types,
  FrameCellStore,
  ViewModeLayout;

type
  TFrameGeometry = class
  strict private
    FCellStore: TFrameCellStore;
    FLayout: TViewModeLayout;
    FViewMode: TViewMode;
    FZoomMode: TZoomMode;
    FCellGap: Integer;
    FCellMargin: Integer;
    FColumnCount: Integer;
    FAspectRatio: Double;
    FNativeW: Integer;
    FNativeH: Integer;
    FViewportW: Integer;
    FViewportH: Integer;
    FBaseViewportW: Integer; {frozen viewport for layout when zoomed}
    FBaseViewportH: Integer;
    FZoomFactor: Double;
    procedure SetViewMode(AValue: TViewMode);
    function GetBaseW: Integer;
    function GetBaseH: Integer;
  public
    {ACellStore is borrowed, not owned: TFrameView owns it and the
     geometry only reads the cell count from it.}
    constructor Create(ACellStore: TFrameCellStore);
    destructor Destroy; override;

    {Freezes the base viewport at zoom 1.0 so cell sizes stay constant
     across window resizes while zoomed.}
    procedure SetViewport(AW, AH: Integer);
    {Named landing site for a zoom-factor change. Deliberately does not
     trigger a resize: callers pair the zoom write with the form-side
     UpdateFrameViewSize, and resizing here would paint once before the
     scrollbox-visibility adjustment settled, producing a visible flicker.}
    procedure ApplyZoom(ANewFactor: Double);

    {Assembles the layout-strategy input record. Client size and the
     current-frame index are owned by TFrameView and passed in.}
    function BuildContext(AClientWidth, AClientHeight, ACurrentFrameIndex: Integer): TViewLayoutContext;
    function GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
    function CellIndexAt(const APoint: TPoint; const ACtx: TViewLayoutContext): Integer;
    {Content size for the control, including the 2*margin outer frame.
     Returns the raw viewport when there are no cells.}
    function ContentSize(const ACtx: TViewLayoutContext): TSize;
    function WheelScrollKind: TLayoutWheelAction;

    function CalcFitColumns(AViewportW, AViewportH: Integer): Integer;
    function DefaultColumnCount: Integer;

    property ViewMode: TViewMode read FViewMode write SetViewMode;
    property ZoomMode: TZoomMode read FZoomMode write FZoomMode;
    property ZoomFactor: Double read FZoomFactor write FZoomFactor;
    property AspectRatio: Double read FAspectRatio write FAspectRatio;
    property NativeW: Integer read FNativeW write FNativeW;
    property NativeH: Integer read FNativeH write FNativeH;
    property CellGap: Integer read FCellGap write FCellGap;
    property CellMargin: Integer read FCellMargin write FCellMargin;
    property ColumnCount: Integer read FColumnCount write FColumnCount;
    property BaseW: Integer read GetBaseW;
    property BaseH: Integer read GetBaseH;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Defaults,
  Settings,
  ZoomController;

constructor TFrameGeometry.Create(ACellStore: TFrameCellStore);
begin
  inherited Create;
  FCellStore := ACellStore;
  FCellGap := DEF_CELL_GAP;
  FCellMargin := DEF_COMBINED_BORDER;
  FViewMode := vmGrid;
  FZoomMode := zmFitWindow;
  FColumnCount := 0;
  FAspectRatio := DEF_ASPECT_RATIO;
  FNativeW := 0;
  FNativeH := 0;
  FViewportW := 0;
  FViewportH := 0;
  FBaseViewportW := 0;
  FBaseViewportH := 0;
  FZoomFactor := 1.0;
  FLayout := CreateViewModeLayout(vmGrid);
end;

destructor TFrameGeometry.Destroy;
begin
  FLayout.Free;
  inherited;
end;

procedure TFrameGeometry.SetViewMode(AValue: TViewMode);
begin
  if FViewMode = AValue then
    Exit;
  FViewMode := AValue;
  FreeAndNil(FLayout);
  FLayout := CreateViewModeLayout(AValue);
end;

procedure TFrameGeometry.SetViewport(AW, AH: Integer);
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

function TFrameGeometry.GetBaseW: Integer;
begin
  if (FBaseViewportW > 0) and not SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
    Result := FBaseViewportW
  else
    Result := FViewportW;
end;

function TFrameGeometry.GetBaseH: Integer;
begin
  if (FBaseViewportH > 0) and not SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
    Result := FBaseViewportH
  else
    Result := FViewportH;
end;

procedure TFrameGeometry.ApplyZoom(ANewFactor: Double);
begin
  FZoomFactor := ANewFactor;
end;

function TFrameGeometry.BuildContext(AClientWidth, AClientHeight, ACurrentFrameIndex: Integer): TViewLayoutContext;
var
  Margin2: Integer;
begin
  {Margin acts as an outer frame: layouts are given a viewport shrunk by the
   margin on every side. Cells are then shifted by +margin when drawn, and
   the control grows by 2*margin in ContentSize. Keeps all layout math
   unchanged while the margin logic lives at the geometry boundary.}
  Margin2 := 2 * FCellMargin;
  Result.BaseW := Max(1, BaseW - Margin2);
  Result.BaseH := Max(1, BaseH - Margin2);
  Result.CellCount := FCellStore.Count;
  Result.CellGap := FCellGap;
  Result.AspectRatio := FAspectRatio;
  Result.NativeW := FNativeW;
  Result.NativeH := FNativeH;
  Result.ZoomMode := FZoomMode;
  Result.ZoomFactor := FZoomFactor;
  Result.ClientWidth := Max(1, AClientWidth - Margin2);
  Result.ClientHeight := Max(1, AClientHeight - Margin2);
  Result.CurrentFrameIndex := ACurrentFrameIndex;
  Result.ViewportW := Max(1, FViewportW - Margin2);
  Result.ViewportH := Max(1, FViewportH - Margin2);
  Result.ColumnCount := FColumnCount;
end;

function TFrameGeometry.GetCellRect(AIndex: Integer; const ACtx: TViewLayoutContext): TRect;
begin
  Result := FLayout.GetCellRect(AIndex, ACtx);
  if FCellMargin <> 0 then
    Result.Offset(FCellMargin, FCellMargin);
end;

function TFrameGeometry.CellIndexAt(const APoint: TPoint; const ACtx: TViewLayoutContext): Integer;
var
  P: TPoint;
begin
  P := APoint;
  if FCellMargin <> 0 then
  begin
    P.X := P.X - FCellMargin;
    P.Y := P.Y - FCellMargin;
  end;
  Result := FLayout.CellIndexAt(P, ACtx);
end;

function TFrameGeometry.ContentSize(const ACtx: TViewLayoutContext): TSize;
var
  Sz: TSize;
begin
  if FCellStore.Count = 0 then
  begin
    Result.CX := FViewportW;
    Result.CY := FViewportH;
    Exit;
  end;
  Sz := FLayout.RecalcSize(ACtx);
  Result.CX := Sz.CX + 2 * FCellMargin;
  Result.CY := Sz.CY + 2 * FCellMargin;
end;

function TFrameGeometry.WheelScrollKind: TLayoutWheelAction;
begin
  Result := FLayout.WheelScrollKind;
end;

function TFrameGeometry.CalcFitColumns(AViewportW, AViewportH: Integer): Integer;
var
  C, Rows, CellW, CellH, TotalH: Integer;
begin
  if (FCellStore.Count <= 1) or (AViewportW <= 0) or (AViewportH <= 0) then
    Exit(1);
  for C := 1 to FCellStore.Count do
  begin
    {Gaps live between cells only: C cells share (C-1) gaps. Outer margin
     is the caller's job (CellMargin), so the viewport handed in here is
     already the margin-shrunk usable area.}
    CellW := Max(1, (AViewportW - Max(C - 1, 0) * FCellGap) div C);
    CellH := Max(1, Round(CellW * FAspectRatio));
    Rows := (FCellStore.Count + C - 1) div C;
    TotalH := Rows * CellH + Max(Rows - 1, 0) * FCellGap;
    if TotalH <= AViewportH then
      Exit(C);
  end;
  Result := FCellStore.Count;
end;

function TFrameGeometry.DefaultColumnCount: Integer;
begin
  if (FViewMode = vmScroll) or (FCellStore.Count <= 1) then
    Result := 1
  else
    Result := Max(1, Floor(Sqrt(FCellStore.Count)));
end;

end.
