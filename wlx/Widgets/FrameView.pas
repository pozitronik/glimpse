{Custom control that renders video frame cells in various layout modes:
 grid, scroll, filmstrip, single frame, and smart grid.}
unit FrameView;

interface

uses
  System.Classes, System.Types,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Graphics,
  Types, Settings, Defaults, FrameOffsets, FrameCellStore, FrameGeometry,
  FrameViewRenderer, ViewModeLayout, TimecodeOverlay, RenderDefaults,
  ScrollableHost;

type
  TCtrlWheelEvent = procedure(Sender: TObject; AWheelDelta: Integer) of object;

  {Custom control that renders frame cells in various layout modes. It owns
   the cell store, geometry and renderer collaborators and wires them to the
   VCL window; the cell data, sizing math and painting live in those.}
  TFrameView = class(TCustomControl)
  strict private
    FCellStore: TFrameCellStore;
    FGeometry: TFrameGeometry;
    FRenderer: TFrameViewRenderer;
    FScrollableHost: IScrollableHost;
  private
    FCurrentFrameIndex: Integer;
    FOnCtrlWheel: TCtrlWheelEvent;
    function LayoutContext: TViewLayoutContext;
    procedure SetCellGap(AValue: Integer);
    procedure SetCellMargin(AValue: Integer);
    function GetBackColor: TColor;
    procedure SetBackColor(AValue: TColor);
    function GetTimestampStyle: TTimestampStyle;
    procedure SetTimestampStyle(const AValue: TTimestampStyle);
    function GetShowTimecode: Boolean;
    procedure SetShowTimecode(AValue: Boolean);
    function GetViewMode: TViewMode;
    procedure SetViewMode(AValue: TViewMode);
    function GetZoomMode: TZoomMode;
    procedure SetZoomMode(AValue: TZoomMode);
    function GetZoomFactor: Double;
    procedure SetZoomFactor(AValue: Double);
    function GetAspectRatio: Double;
    procedure SetAspectRatio(AValue: Double);
    function GetNativeW: Integer;
    procedure SetNativeW(AValue: Integer);
    function GetNativeH: Integer;
    procedure SetNativeH(AValue: Integer);
    function GetColumnCount: Integer;
    procedure SetColumnCount(AValue: Integer);
    function GetCellGap: Integer;
    function GetCellMargin: Integer;
    function GetBaseW: Integer;
    function GetBaseH: Integer;
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
    procedure InvertSelection;
    function SelectedCount: Integer;
    procedure SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
    procedure SetFrame(AIndex: Integer; ABitmap: TBitmap);
    procedure SetCellError(AIndex: Integer);
    procedure ClearCells;
    function HasPlaceholders: Boolean;
    function HasLoadedCells: Boolean;
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
    property ColumnCount: Integer read GetColumnCount write SetColumnCount;
    property ViewMode: TViewMode read GetViewMode write SetViewMode;
    property ZoomMode: TZoomMode read GetZoomMode write SetZoomMode;
    property AspectRatio: Double read GetAspectRatio write SetAspectRatio;
    property NativeW: Integer read GetNativeW write SetNativeW;
    property NativeH: Integer read GetNativeH write SetNativeH;
    property BackColor: TColor read GetBackColor write SetBackColor;
    property CurrentFrameIndex: Integer read FCurrentFrameIndex write FCurrentFrameIndex;
    property ZoomFactor: Double read GetZoomFactor write SetZoomFactor;
    procedure ApplyZoom(ANewFactor: Double);
    {Convenience accessor: the timecode toggle button and settings write-back
     only care about the visible/hidden flag, so it gets a narrow property;
     the rest of the overlay configuration flows through TimestampStyle.}
    property ShowTimecode: Boolean read GetShowTimecode write SetShowTimecode;
    property TimestampStyle: TTimestampStyle read GetTimestampStyle write SetTimestampStyle;
    property CellGap: Integer read GetCellGap write SetCellGap;
    property CellMargin: Integer read GetCellMargin write SetCellMargin;
    property OnCtrlWheel: TCtrlWheelEvent read FOnCtrlWheel write FOnCtrlWheel;
    {Optional. When wired, lwaHorizontalScroll / lwaVerticalScroll wheel
     events are dispatched through this interface; when nil, they fall
     through to the inherited handler. The hosting form is responsible
     for constructing the adapter (typically TScrollBoxScrollableHost
     around its actual TScrollBox parent) and assigning it after
     parenting.}
    property ScrollableHost: IScrollableHost read FScrollableHost write FScrollableHost;
    property PopupMenu;
    property BaseW: Integer read GetBaseW;
    property BaseH: Integer read GetBaseH;
  end;

const
  {Animation timer interval used by the form's FAnimTimer to advance the
   placeholder spinner. The animation policy belongs with the view that
   draws the placeholder; the form just wires the timer to it.}
  ANIM_INTERVAL_MS = 80;

implementation

constructor TFrameView.Create(AOwner: TComponent);
begin
  inherited;
  FCellStore := TFrameCellStore.Create;
  FGeometry := TFrameGeometry.Create(FCellStore);
  FRenderer := TFrameViewRenderer.Create(Canvas, FCellStore, FGeometry);
  DoubleBuffered := True;
  FCurrentFrameIndex := 0;
end;

destructor TFrameView.Destroy;
begin
  FRenderer.Free;
  FGeometry.Free;
  FCellStore.Free;
  inherited;
end;

function TFrameView.GetViewMode: TViewMode;
begin
  Result := FGeometry.ViewMode;
end;

procedure TFrameView.SetViewMode(AValue: TViewMode);
begin
  FGeometry.ViewMode := AValue;
end;

function TFrameView.GetZoomMode: TZoomMode;
begin
  Result := FGeometry.ZoomMode;
end;

procedure TFrameView.SetZoomMode(AValue: TZoomMode);
begin
  FGeometry.ZoomMode := AValue;
end;

function TFrameView.GetZoomFactor: Double;
begin
  Result := FGeometry.ZoomFactor;
end;

procedure TFrameView.SetZoomFactor(AValue: Double);
begin
  FGeometry.ZoomFactor := AValue;
end;

function TFrameView.GetAspectRatio: Double;
begin
  Result := FGeometry.AspectRatio;
end;

procedure TFrameView.SetAspectRatio(AValue: Double);
begin
  FGeometry.AspectRatio := AValue;
end;

function TFrameView.GetNativeW: Integer;
begin
  Result := FGeometry.NativeW;
end;

procedure TFrameView.SetNativeW(AValue: Integer);
begin
  FGeometry.NativeW := AValue;
end;

function TFrameView.GetNativeH: Integer;
begin
  Result := FGeometry.NativeH;
end;

procedure TFrameView.SetNativeH(AValue: Integer);
begin
  FGeometry.NativeH := AValue;
end;

function TFrameView.GetColumnCount: Integer;
begin
  Result := FGeometry.ColumnCount;
end;

procedure TFrameView.SetColumnCount(AValue: Integer);
begin
  FGeometry.ColumnCount := AValue;
end;

function TFrameView.GetCellGap: Integer;
begin
  Result := FGeometry.CellGap;
end;

function TFrameView.GetCellMargin: Integer;
begin
  Result := FGeometry.CellMargin;
end;

function TFrameView.GetBaseW: Integer;
begin
  Result := FGeometry.BaseW;
end;

function TFrameView.GetBaseH: Integer;
begin
  Result := FGeometry.BaseH;
end;

function TFrameView.GetBackColor: TColor;
begin
  Result := FRenderer.BackColor;
end;

procedure TFrameView.SetBackColor(AValue: TColor);
begin
  if FRenderer.BackColor = AValue then
    Exit;
  FRenderer.BackColor := AValue;
  Invalidate;
end;

function TFrameView.GetTimestampStyle: TTimestampStyle;
begin
  Result := FRenderer.TimestampStyle;
end;

procedure TFrameView.SetTimestampStyle(const AValue: TTimestampStyle);
begin
  if FRenderer.ApplyTimestampStyle(AValue) then
    Invalidate;
end;

function TFrameView.GetShowTimecode: Boolean;
begin
  Result := FRenderer.ShowTimecode;
end;

procedure TFrameView.SetShowTimecode(AValue: Boolean);
begin
  if FRenderer.ShowTimecode = AValue then
    Exit;
  FRenderer.ShowTimecode := AValue;
  Invalidate;
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

  case FGeometry.WheelScrollKind of
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
        if FScrollableHost <> nil then
        begin
          FScrollableHost.ScrollHorz(Message.WheelDelta);
          Message.Result := 1;
        end
        else
          inherited;
      end;
    lwaVerticalScroll:
      begin
        if FScrollableHost <> nil then
        begin
          FScrollableHost.ScrollVert(Message.WheelDelta);
          Message.Result := 1;
        end
        else
          inherited;
      end;
  end;
end;

procedure TFrameView.SetViewport(AW, AH: Integer);
begin
  FGeometry.SetViewport(AW, AH);
end;

function TFrameView.LayoutContext: TViewLayoutContext;
begin
  Result := FGeometry.BuildContext(ClientWidth, ClientHeight, FCurrentFrameIndex);
end;

function TFrameView.DefaultColumnCount: Integer;
begin
  Result := FGeometry.DefaultColumnCount;
end;

function TFrameView.CalcFitColumns(AViewportW, AViewportH: Integer): Integer;
begin
  Result := FGeometry.CalcFitColumns(AViewportW, AViewportH);
end;

function TFrameView.GetCellRect(AIndex: Integer): TRect;
begin
  Result := FGeometry.GetCellRect(AIndex, LayoutContext);
end;

procedure TFrameView.Paint;
begin
  FRenderer.Paint(ClientRect, FCurrentFrameIndex);
end;

procedure TFrameView.SetCellGap(AValue: Integer);
begin
  if FGeometry.CellGap = AValue then
    Exit;
  FGeometry.CellGap := AValue;
  {Cell gap affects component size in every layout mode; recalc so the
   scrollbox picks up the new dimensions and triggers a repaint.}
  RecalcSize;
  Invalidate;
end;

procedure TFrameView.SetCellMargin(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if FGeometry.CellMargin = AValue then
    Exit;
  FGeometry.CellMargin := AValue;
  RecalcSize;
  Invalidate;
end;

procedure TFrameView.SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
begin
  FCellStore.SetCellCount(ACount, AOffsets);
  FCurrentFrameIndex := 0;
end;

procedure TFrameView.SetFrame(AIndex: Integer; ABitmap: TBitmap);
begin
  FCellStore.SetFrame(AIndex, ABitmap);
  Invalidate;
end;

procedure TFrameView.SetCellError(AIndex: Integer);
begin
  FCellStore.SetCellError(AIndex);
  Invalidate;
end;

procedure TFrameView.ClearCells;
begin
  FCellStore.Clear;
  FCurrentFrameIndex := 0;
end;

function TFrameView.HasPlaceholders: Boolean;
begin
  Result := FCellStore.HasPlaceholders;
end;

function TFrameView.HasLoadedCells: Boolean;
begin
  Result := FCellStore.HasLoadedCells;
end;

procedure TFrameView.AdvanceAnimation;
begin
  FRenderer.AdvanceAnimation;
  Invalidate;
end;

procedure TFrameView.ApplyZoom(ANewFactor: Double);
begin
  FGeometry.ApplyZoom(ANewFactor);
end;

procedure TFrameView.RecalcSize;
var
  Sz: TSize;
begin
  Sz := FGeometry.ContentSize(LayoutContext);
  Width := Sz.CX;
  Height := Sz.CY;
end;

procedure TFrameView.NavigateFrame(ADelta: Integer);
var
  NewIdx: Integer;
begin
  if FCellStore.Count = 0 then
    Exit;
  NewIdx := FCurrentFrameIndex + ADelta;
  if NewIdx < 0 then
    NewIdx := 0
  else if NewIdx >= FCellStore.Count then
    NewIdx := FCellStore.Count - 1;
  if NewIdx <> FCurrentFrameIndex then
  begin
    FCurrentFrameIndex := NewIdx;
    Invalidate;
  end;
end;

function TFrameView.CellCount: Integer;
begin
  Result := FCellStore.Count;
end;

function TFrameView.CellState(AIndex: Integer): TFrameCellState;
begin
  Result := FCellStore.State(AIndex);
end;

function TFrameView.CellBitmap(AIndex: Integer): TBitmap;
begin
  Result := FCellStore.Bitmap(AIndex);
end;

function TFrameView.CellTimeOffset(AIndex: Integer): Double;
begin
  Result := FCellStore.TimeOffset(AIndex);
end;

function TFrameView.CellTimecode(AIndex: Integer): string;
begin
  Result := FCellStore.Timecode(AIndex);
end;

function TFrameView.CellSelected(AIndex: Integer): Boolean;
begin
  Result := FCellStore.Selected(AIndex);
end;

function TFrameView.CellIndexAt(const APoint: TPoint): Integer;
begin
  Result := FGeometry.CellIndexAt(APoint, LayoutContext);
end;

procedure TFrameView.ToggleSelection(AIndex: Integer);
begin
  FCellStore.ToggleSelection(AIndex);
  Invalidate;
end;

procedure TFrameView.SelectAll;
begin
  FCellStore.SelectAll;
  Invalidate;
end;

procedure TFrameView.DeselectAll;
begin
  FCellStore.DeselectAll;
  Invalidate;
end;

procedure TFrameView.InvertSelection;
begin
  FCellStore.InvertSelection;
  Invalidate;
end;

function TFrameView.SelectedCount: Integer;
begin
  Result := FCellStore.SelectedCount;
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
