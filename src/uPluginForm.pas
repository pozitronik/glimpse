/// Main plugin form, frame view control, and extraction worker thread.
/// The form is parented to TC's Lister window and hosts the toolbar and frame display.
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Clipbrd, Vcl.Dialogs,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  uSettings, uFrameOffsets, uFFmpegExe;

const
  WM_FRAME_READY     = WM_USER + 100; { Notification: pending frames available in queue }
  WM_EXTRACTION_DONE = WM_USER + 101; { Extraction finished }

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
    StartIndex: Integer;
    Count: Integer;
  end;

  { Extracted frame awaiting delivery to UI thread }
  TPendingFrame = record
    Index: Integer;
    Bitmap: TBitmap; { nil = extraction error }
  end;

  /// Worker thread that extracts frames sequentially via ffmpeg.exe.
  /// Stores results in a thread-safe queue and posts notifications.
  TExtractionThread = class(TThread)
  private
    FFFmpegPath: string;
    FFileName: string;
    FOffsets: TFrameOffsetArray;
    FNotifyWnd: HWND;
    FQueue: TList<TPendingFrame>;
    FQueueLock: TCriticalSection;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFFmpegPath, AFileName: string;
      const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND;
      AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection);
  end;

  /// Custom control that renders frame cells in various layout modes.
  TFrameView = class(TCustomControl)
  private
    FViewMode: TViewMode;
    FZoomMode: TZoomMode;
    FBackColor: TColor;
    FAnimStep: Integer;
    FCellGap: Integer;
    FTimecodeHeight: Integer;
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
    FSmartRows: TArray<TSmartRow>;
    function BaseW: Integer;
    function BaseH: Integer;
    function GetColumnCount: Integer;
    function GetCellImageSize: TSize;
    function GetCellRectGrid(AIndex: Integer): TRect;
    function GetCellRectScroll(AIndex: Integer): TRect;
    function GetCellRectFilmstrip(AIndex: Integer): TRect;
    function GetCellRectSingle(AIndex: Integer): TRect;
    function GetCellRectSmartGrid(AIndex: Integer): TRect;
    function GetTimecodeRect(AIndex: Integer): TRect;
    procedure CalcSmartGridLayout;
    procedure PaintCell(AIndex: Integer);
    procedure PaintPlaceholder(const ARect: TRect);
    procedure PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
    procedure PaintCropToFill(AIndex: Integer; const ARect: TRect);
    procedure PaintArc(const ARect: TRect);
    procedure PaintTimecode(AIndex: Integer);
    procedure PaintErrorCell(const ARect: TRect);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMMouseWheel(var Message: TWMMouseWheel); message WM_MOUSEWHEEL;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    FCells: TArray<TFrameCell>;
    constructor Create(AOwner: TComponent); override;
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
    property ColumnCount: Integer read FColumnCount write FColumnCount;
    property ViewMode: TViewMode read FViewMode write FViewMode;
    property ZoomMode: TZoomMode read FZoomMode write FZoomMode;
    property AspectRatio: Double read FAspectRatio write FAspectRatio;
    property NativeW: Integer read FNativeW write FNativeW;
    property NativeH: Integer read FNativeH write FNativeH;
    property BackColor: TColor read FBackColor write FBackColor;
    property CurrentFrameIndex: Integer read FCurrentFrameIndex write FCurrentFrameIndex;
    property ZoomFactor: Double read FZoomFactor write FZoomFactor;
  end;

  /// Plugin form created as a child of TC's Lister window.
  TPluginForm = class(TForm)
  private
    FFileName: string;
    FSettings: TPluginSettings;
    FFFmpegPath: string;
    FVideoInfo: TVideoInfo;
    FOffsets: TFrameOffsetArray;
    FParentWnd: HWND;
    { Toolbar }
    FToolbar: TPanel;
    FLblFrames: TLabel;
    FEditFrameCount: TEdit;
    FUpDown: TUpDown;
    FModeButtons: array[TViewMode] of TButton;
    FModePopups: array[TViewMode] of TPopupMenu;
    FContextMenu: TPopupMenu;
    FContextCellIndex: Integer;
    FProgressBar: TProgressBar;
    FLblProgress: TLabel;
    { Content }
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    { Worker }
    FWorkerThread: TExtractionThread;
    FFramesLoaded: Integer;
    FPendingFrames: TList<TPendingFrame>;
    FPendingLock: TCriticalSection;
    { Animation }
    FAnimTimer: TTimer;
    { Layout guard: prevents re-entrant UpdateFrameViewSize during zoom }
    FUpdatingLayout: Boolean;

    procedure CreateToolbar;
    procedure CreateFrameView;
    procedure CreateContextMenu;
    procedure CreateErrorLabel;
    function CreateModePopup(AMode: TViewMode): TPopupMenu;
    procedure ApplySettings;
    procedure SetupPlaceholders;
    procedure ShowError(const AMessage: string);
    procedure HideError;
    procedure UpdateFrameViewSize;
    procedure UpdateViewModeButtons;
    procedure ActivateMode(AMode: TViewMode);
    procedure ZoomBy(AFactor: Double);
    procedure ResetZoom;
    procedure SwitchOrCycleMode(AKey: Word);
    procedure CopyFrameToClipboard;
    procedure CopyAllToClipboard;
    function FrameFileName(AIndex: Integer; AFormat: TSaveFormat): string;
    procedure SaveBitmapToFile(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat);
    procedure SaveSingleFrame;
    procedure SaveCombinedFrame;
    procedure SaveAllFrames;
    procedure StartExtraction;
    procedure StopExtraction;
    procedure ProcessPendingFrames;
    procedure DrainPendingFrameMessages;
    procedure UpdateProgress;
    procedure OnAnimTimer(Sender: TObject);
    procedure OnFrameCountChange(Sender: TObject);
    procedure OnModeButtonClick(Sender: TObject);
    procedure OnSizingMenuClick(Sender: TObject);
    procedure OnScrollBoxResize(Sender: TObject);
    procedure OnContextMenuPopup(Sender: TObject);
    procedure OnContextMenuClick(Sender: TObject);
    procedure OnFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure WMFrameReady(var Message: TMessage); message WM_FRAME_READY;
    procedure WMExtractionDone(var Message: TMessage); message WM_EXTRACTION_DONE;
    procedure CMDialogKey(var Message: TWMKey); message CM_DIALOGKEY;
  protected
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor CreateForPlugin(AParentWin: HWND; const AFileName: string;
      ASettings: TPluginSettings; const AFFmpegPath: string);
    destructor Destroy; override;
    procedure LoadFile(const AFileName: string);
  end;

implementation

{ comctl32 v6 subclass API - lets us monitor the parent window's WM_SIZE }
function SetWindowSubclass(hWnd: HWND; pfnSubclass: Pointer;
  uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): BOOL; stdcall;
  external 'comctl32.dll' name 'SetWindowSubclass';
function RemoveWindowSubclass(hWnd: HWND; pfnSubclass: Pointer;
  uIdSubclass: UINT_PTR): BOOL; stdcall;
  external 'comctl32.dll' name 'RemoveWindowSubclass';
function DefSubclassProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
  external 'comctl32.dll' name 'DefSubclassProc';

/// Subclass callback on TC's Lister parent window.
/// TC may not resize the plugin child for all resize directions;
/// this ensures the plugin always fills the parent's client rect.
function ParentSubclassProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM;
  lParam: LPARAM; uIdSubclass: UINT_PTR;
  dwRefData: DWORD_PTR): LRESULT; stdcall;
var
  Form: TPluginForm;
  R: TRect;
begin
  Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
  if uMsg = WM_SIZE then
  begin
    Form := TPluginForm(Pointer(dwRefData));
    if (Form <> nil) and Form.HandleAllocated then
    begin
      Winapi.Windows.GetClientRect(hWnd, R);
      Form.SetBounds(0, 0, R.Right, R.Bottom);
    end;
  end;
end;

const
  CELL_GAP       = 4;
  TIMECODE_H     = 20;
  DEF_ASPECT_RATIO = 9.0 / 16.0; { fallback for 16:9 video }

  { Painting colors }
  CLR_CELL_BG         = TColor($002D2D2D); { dark gray cell/placeholder background }
  CLR_ARC             = TColor($00707070); { loading spinner arc }
  CLR_TIMECODE_OVERLAY = TColor($00CCCCCC); { timecode text over smart grid cells }
  CLR_TIMECODE_LOADED  = TColor($00AAAAAA); { timecode text for loaded frames }
  CLR_TIMECODE_PENDING = TColor($00555555); { timecode text for placeholders }
  CLR_ERROR_TEXT       = TColor($004040FF); { error cell label }
  CLR_SELECTION        = TColor($00F7C34F); { #4FC3F7 light blue selection border }
  SELECTION_BORDER_W   = 2;

  { Painting fonts and sizes }
  FONT_NAME         = 'Segoe UI';
  FONT_TIMECODE     = 8;
  FONT_ERROR        = 9;
  ARC_PEN_WIDTH     = 3;
  ARC_RADIUS_DIV    = 8;  { spinner radius = min(cell dim) div this }

  { Continuous zoom }
  ZOOM_IN_FACTOR  = 1.25;
  ZOOM_OUT_FACTOR = 1 / 1.25;
  MIN_ZOOM = 0.1;
  MAX_ZOOM = 10.0;
  ZOOM_EPSILON = 0.0001;

  { Context menu item tags }
  CM_SAVE_FRAME    = 1;
  CM_SAVE_SELECTED = 2;
  CM_SAVE_ALL      = 3;
  CM_SAVE_COMBINED = 4;
  CM_COPY_FRAME    = 5;
  CM_COPY_ALL      = 6;
  CM_SELECT_ALL    = 7;
  CM_DESELECT_ALL  = 8;
  CM_SETTINGS      = 9;

  MODE_CAPTIONS: array[TViewMode] of string = (
    'Smart', 'Grid', 'Scroll '#$2195, 'Scroll '#$2194, 'Single'
  );

  { Per-mode sizing submode labels }
  SIZING_LABELS: array[TViewMode, TZoomMode] of string = (
    { vmSmartGrid } ('', '', ''),
    { vmGrid }      ('', '', ''),
    { vmScroll }    ('Fit width',  'Fit if larger', 'Original size'),
    { vmFilmstrip } ('Fit height', 'Fit if larger', 'Original size'),
    { vmSingle }    ('Fit',        'Fit if larger', 'Original size')
  );

{ TExtractionThread }

constructor TExtractionThread.Create(const AFFmpegPath, AFileName: string;
  const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND;
  AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection);
begin
  inherited Create(True); { suspended }
  FreeOnTerminate := False;
  FFFmpegPath := AFFmpegPath;
  FFileName := AFileName;
  FOffsets := Copy(AOffsets);
  FNotifyWnd := ANotifyWnd;
  FQueue := AQueue;
  FQueueLock := AQueueLock;
end;

procedure TExtractionThread.Execute;
var
  FFmpeg: TFFmpegExe;
  Bmp: TBitmap;
  Frame: TPendingFrame;
  I: Integer;
begin
  FFmpeg := TFFmpegExe.Create(FFFmpegPath);
  try
    for I := 0 to High(FOffsets) do
    begin
      if Terminated then
        Exit;

      Bmp := FFmpeg.ExtractFrame(FFileName, FOffsets[I].TimeOffset);

      if Terminated then
      begin
        Bmp.Free;
        Exit;
      end;

      { Enqueue frame for the UI thread; PostMessage is just a notification }
      Frame.Index := I;
      Frame.Bitmap := Bmp;
      FQueueLock.Enter;
      try
        FQueue.Add(Frame);
      finally
        FQueueLock.Leave;
      end;
      PostMessage(FNotifyWnd, WM_FRAME_READY, 0, 0);
    end;
  finally
    FFmpeg.Free;
  end;

  if not Terminated then
    PostMessage(FNotifyWnd, WM_EXTRACTION_DONE, 0, 0);
end;

{ TFrameView }

constructor TFrameView.Create(AOwner: TComponent);
begin
  inherited;
  DoubleBuffered := True;
  FCellGap := CELL_GAP;
  FTimecodeHeight := TIMECODE_H;
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
end;

procedure TFrameView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TFrameView.WMMouseWheel(var Message: TWMMouseWheel);
begin
  { Ctrl+Wheel: delegate to parent form for zoom }
  if (Message.Keys and MK_CONTROL) <> 0 then
  begin
    if GetParentForm(Self) is TPluginForm then
    begin
      { Claim keyboard focus BEFORE zoom: when SetFocus fires after ZoomBy,
        the scrollbox handles CMFocusChanged by calling ScrollInView, which
        resets scroll positions to show the top-left corner of this control,
        overwriting the centered position that ZoomBy just computed. }
      Winapi.Windows.SetFocus(Self.Handle);
      if Message.WheelDelta > 0 then
        TPluginForm(GetParentForm(Self)).ZoomBy(ZOOM_IN_FACTOR)
      else
        TPluginForm(GetParentForm(Self)).ZoomBy(ZOOM_OUT_FACTOR);
    end;
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

function TFrameView.BaseW: Integer;
begin
  if (FBaseViewportW > 0) and not SameValue(FZoomFactor, 1.0, ZOOM_EPSILON) then
    Result := FBaseViewportW
  else
    Result := FViewportW;
end;

function TFrameView.BaseH: Integer;
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
    RowH := CellH + FTimecodeHeight + FCellGap;
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
  RowH := Sz.cy + FTimecodeHeight + FCellGap;

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

  RowH := CellH + FTimecodeHeight + FCellGap;
  Result.Left   := LeftX;
  Result.Top    := FCellGap + AIndex * RowH;
  Result.Right  := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TFrameView.GetCellRectFilmstrip(AIndex: Integer): TRect;
var
  CellH, CellW, AvailH, TopY: Integer;
begin
  AvailH := Max(1, BaseH - FTimecodeHeight - 2 * FCellGap);

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
  CellW := Max(1, Round(CellH / FAspectRatio));

  { Center vertically within control (ClientHeight reflects post-RecalcSize size) }
  if CellH < AvailH then
    TopY := (ClientHeight - CellH - FTimecodeHeight) div 2
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
  AvailH := Max(1, BaseH - FTimecodeHeight - 2 * FCellGap);

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
            CellW := Round(CellH / FAspectRatio);
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
        CellW := Round(CellH / FAspectRatio);
      end;
    end;
  end;

  { Apply continuous zoom }
  CellW := Max(1, Round(CellW * FZoomFactor));
  CellH := Max(1, Round(CellH * FZoomFactor));

  { Center in control (ClientWidth may exceed viewport when zoomed) }
  Result.Left   := (ClientWidth - CellW) div 2;
  Result.Top    := FCellGap + (Max(1, ClientHeight - 2 * FCellGap - FTimecodeHeight) - CellH) div 2;
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
    if I = 0 then
      Rows[I].StartIndex := 0
    else
      Rows[I].StartIndex := Rows[I - 1].StartIndex + Rows[I - 1].Count;
  end;

  FSmartRows := Rows;
end;

function TFrameView.GetTimecodeRect(AIndex: Integer): TRect;
var
  CR: TRect;
begin
  CR := GetCellRect(AIndex);
  if FViewMode = vmSmartGrid then
    { Overlay timecode at bottom of cell }
    Result := Rect(CR.Left, CR.Bottom - FTimecodeHeight, CR.Right, CR.Bottom)
  else
    Result := Rect(CR.Left, CR.Bottom, CR.Right, CR.Bottom + FTimecodeHeight);
end;

procedure TFrameView.Paint;
var
  I: Integer;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);

  if FViewMode = vmSingle then
  begin
    if (FCurrentFrameIndex >= 0) and (FCurrentFrameIndex < Length(FCells)) then
    begin
      PaintCell(FCurrentFrameIndex);
    end;
  end
  else
  begin
    for I := 0 to High(FCells) do
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
  PaintTimecode(AIndex);
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
  if Radius < 5 then Exit;

  StartAngle := FAnimStep * 45.0;
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

procedure TFrameView.PaintTimecode(AIndex: Integer);
var
  R: TRect;
begin
  R := GetTimecodeRect(AIndex);
  Canvas.Font.Name := FONT_NAME;
  Canvas.Font.Size := FONT_TIMECODE;

  if FViewMode = vmSmartGrid then
  begin
    { Semi-transparent overlay for smart grid }
    Canvas.Brush.Color := CLR_CELL_BG;
    Canvas.Brush.Style := bsSolid;
    Canvas.FillRect(R);
    Canvas.Font.Color := CLR_TIMECODE_OVERLAY;
  end
  else
  begin
    if FCells[AIndex].State = fcsLoaded then
      Canvas.Font.Color := CLR_TIMECODE_LOADED
    else
      Canvas.Font.Color := CLR_TIMECODE_PENDING;
  end;

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
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
  begin
    FCells[AIndex].State := fcsLoaded;
    FCells[AIndex].Bitmap := ABitmap;
    Invalidate;
  end;
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
        Height := Max(FViewportH, R0.Height + FTimecodeHeight + 2 * FCellGap);
      end;
    vmFilmstrip:
      begin
        R0 := GetCellRectFilmstrip(0);
        Width := Max(FViewportW, FCellGap + N * (R0.Width + FCellGap));
        Height := Max(FViewportH, R0.Height + FTimecodeHeight + 2 * FCellGap);
      end;
    vmScroll:
      begin
        R0 := GetCellRectScroll(0);
        Width := Max(FViewportW, R0.Width + 2 * FCellGap);
        Height := Max(FViewportH, FCellGap + N * (R0.Height + FTimecodeHeight + FCellGap));
      end;
  else { vmGrid }
    begin
      Cols := GetColumnCount;
      Sz := GetCellImageSize;
      Rows := Ceil(N / Cols);
      GridW := Cols * (Sz.cx + FCellGap) + FCellGap;
      Width := Max(FViewportW, GridW);
      Height := Max(FViewportH, FCellGap + Rows * (Sz.cy + FTimecodeHeight + FCellGap));
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

{ TPluginForm }

constructor TPluginForm.CreateForPlugin(AParentWin: HWND; const AFileName: string;
  ASettings: TPluginSettings; const AFFmpegPath: string);
var
  R: TRect;
begin
  CreateNew(nil);
  BorderStyle := bsNone;
  KeyPreview := True;
  OnKeyDown := OnFormKeyDown;

  FSettings := ASettings;
  FFFmpegPath := AFFmpegPath;
  FContextCellIndex := -1;

  Winapi.Windows.GetClientRect(AParentWin, R);
  SetBounds(0, 0, R.Right, R.Bottom);

  CreateToolbar;
  CreateFrameView;
  CreateContextMenu;
  CreateErrorLabel;
  ApplySettings;

  { Wire OnChange after ApplySettings so initial Position assignment doesn't
    trigger a save that overwrites the loaded FramesCount }
  FEditFrameCount.OnChange := OnFrameCountChange;

  ParentWindow := AParentWin;
  FParentWnd := AParentWin;
  SetWindowSubclass(AParentWin, @ParentSubclassProc, 1, DWORD_PTR(Self));
  Visible := True;
  { A child control must own Win32 focus for KeyPreview to fire in a WLX plugin }
  if FFrameView.HandleAllocated then
    Winapi.Windows.SetFocus(FFrameView.Handle);

  FPendingFrames := TList<TPendingFrame>.Create;
  FPendingLock := TCriticalSection.Create;

  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := 80;
  FAnimTimer.OnTimer := OnAnimTimer;
  FAnimTimer.Enabled := True;

  LoadFile(AFileName);
end;

destructor TPluginForm.Destroy;
begin
  if FParentWnd <> 0 then
    RemoveWindowSubclass(FParentWnd, @ParentSubclassProc, 1);
  if Assigned(FAnimTimer) then
    FAnimTimer.Enabled := False;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  FPendingLock.Free;
  FPendingFrames.Free;
  inherited;
end;

procedure TPluginForm.CreateToolbar;
const
  TB_PAD   = 4;   { Vertical padding above and below controls }
  CTRL_GAP = 8;   { Gap between control groups }
  BTN_GAP  = 2;   { Gap between adjacent buttons in a group }
  BTN_PAD  = 16;  { Horizontal text padding inside button (both sides) }
  SPLIT_ARROW_W = 20; { Extra width for split button dropdown arrow }
  PB_H     = 16;  { Progress bar height }
var
  X, CY, CtrlH, BW: Integer;
  VM: TViewMode;
  TabIdx: Integer;
begin
  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.BevelOuter := bvNone;
  FToolbar.ParentBackground := False;

  { Create edit first: its auto-sized height is the reference for all controls }
  FEditFrameCount := TEdit.Create(FToolbar);
  FEditFrameCount.Parent := FToolbar;
  FEditFrameCount.Width := 40;
  FEditFrameCount.NumbersOnly := True;
  FEditFrameCount.TabOrder := 0;
  CtrlH := FEditFrameCount.Height;

  FToolbar.Height := CtrlH + 2 * TB_PAD;
  CY := TB_PAD;
  X := CTRL_GAP;

  FLblFrames := TLabel.Create(FToolbar);
  FLblFrames.Parent := FToolbar;
  FLblFrames.Caption := 'Frames:';
  FLblFrames.AutoSize := True;
  FLblFrames.Left := X;
  FLblFrames.Top := CY + (CtrlH - FLblFrames.Height) div 2;
  Inc(X, FLblFrames.Width + 4);

  FEditFrameCount.SetBounds(X, CY, 40, CtrlH);

  FUpDown := TUpDown.Create(FToolbar);
  FUpDown.Parent := FToolbar;
  FUpDown.Associate := FEditFrameCount;
  FUpDown.Min := 1;
  FUpDown.Max := 99;
  Inc(X, 40 + FUpDown.Width + CTRL_GAP);

  { Create 5 mode buttons }
  TabIdx := 1;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    { Create popup menu first (needed for DropDownMenu assignment) }
    FModePopups[VM] := CreateModePopup(VM);

    FModeButtons[VM] := TButton.Create(FToolbar);
    FModeButtons[VM].Parent := FToolbar;

    { Auto-width: measure caption text and add padding }
    BW := Canvas.TextWidth(MODE_CAPTIONS[VM]) + BTN_PAD;
    if FModePopups[VM] <> nil then
      Inc(BW, SPLIT_ARROW_W);

    FModeButtons[VM].SetBounds(X, CY, BW, CtrlH);
    FModeButtons[VM].Caption := MODE_CAPTIONS[VM];
    FModeButtons[VM].Tag := Ord(VM);
    FModeButtons[VM].TabOrder := TabIdx;
    FModeButtons[VM].OnClick := OnModeButtonClick;

    { Split button: click activates mode, arrow shows submodes }
    if FModePopups[VM] <> nil then
    begin
      FModeButtons[VM].Style := bsSplitButton;
      FModeButtons[VM].DropDownMenu := FModePopups[VM];
    end;

    Inc(TabIdx);
    if VM < High(TViewMode) then
      Inc(X, BW + BTN_GAP)
    else
      Inc(X, BW + CTRL_GAP);
  end;

  FProgressBar := TProgressBar.Create(FToolbar);
  FProgressBar.Parent := FToolbar;
  FProgressBar.SetBounds(X, CY + (CtrlH - PB_H) div 2, 120, PB_H);
  FProgressBar.Visible := False;

  FLblProgress := TLabel.Create(FToolbar);
  FLblProgress.Parent := FToolbar;
  FLblProgress.AutoSize := True;
  FLblProgress.Left := X + 120 + 4;
  FLblProgress.Top := CY + (CtrlH - FLblProgress.Height) div 2;
  FLblProgress.Visible := False;
end;

function TPluginForm.CreateModePopup(AMode: TViewMode): TPopupMenu;
var
  ZM: TZoomMode;
  MI: TMenuItem;
begin
  { Grid modes always fit all frames to the available space }
  if AMode in [vmSmartGrid, vmGrid] then
    Exit(nil);

  Result := TPopupMenu.Create(Self);
  for ZM := Low(TZoomMode) to High(TZoomMode) do
  begin
    MI := TMenuItem.Create(Result);
    MI.Caption := SIZING_LABELS[AMode, ZM];
    MI.Tag := Ord(ZM);
    MI.RadioItem := True;
    MI.Checked := ZM = zmFitWindow;
    MI.OnClick := OnSizingMenuClick;
    Result.Items.Add(MI);
  end;
end;

procedure TPluginForm.CreateFrameView;
begin
  FScrollBox := TScrollBox.Create(Self);
  FScrollBox.Parent := Self;
  FScrollBox.Align := alClient;
  FScrollBox.BorderStyle := bsNone;
  FScrollBox.OnResize := OnScrollBoxResize;
  { Update scroll position live during thumb drag, not just on release }
  FScrollBox.VertScrollBar.Tracking := True;
  FScrollBox.HorzScrollBar.Tracking := True;

  FFrameView := TFrameView.Create(FScrollBox);
  FFrameView.Parent := FScrollBox;
  FFrameView.Left := 0;
  FFrameView.Top := 0;
end;

procedure TPluginForm.CreateContextMenu;

  function AddItem(const ACaption: string; ATag: Integer): TMenuItem;
  begin
    Result := TMenuItem.Create(FContextMenu);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := OnContextMenuClick;
    FContextMenu.Items.Add(Result);
  end;

  procedure AddSeparator;
  var
    MI: TMenuItem;
  begin
    MI := TMenuItem.Create(FContextMenu);
    MI.Caption := '-';
    FContextMenu.Items.Add(MI);
  end;

begin
  FContextMenu := TPopupMenu.Create(Self);
  FContextMenu.OnPopup := OnContextMenuPopup;

  AddItem('Save frame...'#9'Ctrl+S', CM_SAVE_FRAME);
  AddItem('Save selected...', CM_SAVE_SELECTED);
  AddItem('Save combined...'#9'Ctrl+Shift+S', CM_SAVE_COMBINED);
  AddItem('Save all...'#9'Ctrl+Alt+S', CM_SAVE_ALL);
  AddSeparator;
  AddItem('Copy frame'#9'Ctrl+C', CM_COPY_FRAME);
  AddItem('Copy all'#9'Ctrl+Shift+C', CM_COPY_ALL);
  AddSeparator;
  AddItem('Select all'#9'Ctrl+A', CM_SELECT_ALL);
  AddItem('Deselect all', CM_DESELECT_ALL);
  AddSeparator;
  AddItem('Settings...', CM_SETTINGS);

  FFrameView.PopupMenu := FContextMenu;
end;

procedure TPluginForm.CreateErrorLabel;
begin
  FLblError := TLabel.Create(Self);
  FLblError.Parent := FScrollBox;
  FLblError.Align := alClient;
  FLblError.Alignment := taCenter;
  FLblError.Layout := tlCenter;
  FLblError.Font.Size := 11;
  FLblError.Font.Color := $00888888;
  FLblError.WordWrap := True;
  FLblError.Visible := False;
end;

procedure TPluginForm.ApplySettings;
var
  VM: TViewMode;
  I: Integer;
begin
  if FSettings = nil then Exit;

  FUpDown.Position := FSettings.FramesCount;
  FFrameView.ViewMode := FSettings.ViewMode;
  FFrameView.ZoomMode := FSettings.ZoomMode;

  { Restore per-mode zoom selections in all popup menus }
  for VM := Low(TViewMode) to High(TViewMode) do
    if FModePopups[VM] <> nil then
      for I := 0 to FModePopups[VM].Items.Count - 1 do
        FModePopups[VM].Items[I].Checked :=
          I = Ord(FSettings.ModeZoom[VM]);

  UpdateViewModeButtons;
  FFrameView.BackColor := FSettings.Background;
  FScrollBox.Color := FSettings.Background;
  Color := FSettings.Background;
end;

procedure TPluginForm.ActivateMode(AMode: TViewMode);
begin
  FFrameView.ZoomFactor := 1.0;
  FFrameView.ViewMode := AMode;

  { Apply the zoom mode stored in the popup, or force Fit for modes without submodes }
  if FModePopups[AMode] <> nil then
  begin
    var I: Integer;
    for I := 0 to FModePopups[AMode].Items.Count - 1 do
      if FModePopups[AMode].Items[I].Checked then
      begin
        FFrameView.ZoomMode := TZoomMode(FModePopups[AMode].Items[I].Tag);
        Break;
      end;
  end
  else
    FFrameView.ZoomMode := zmFitWindow;

  UpdateViewModeButtons;
  UpdateFrameViewSize;

  { Persist user preference }
  FSettings.ViewMode := AMode;
  FSettings.ZoomMode := FFrameView.ZoomMode;
  FSettings.Save;
end;

procedure TPluginForm.ZoomBy(AFactor: Double);
var
  OldF, NewF, NormX, NormY: Double;
begin
  OldF := FFrameView.ZoomFactor;
  NewF := EnsureRange(OldF * AFactor, MIN_ZOOM, MAX_ZOOM);
  if SameValue(NewF, OldF, ZOOM_EPSILON) then
    Exit;

  { Normalized position (0..1) of the viewport center within the control.
    When content is centered with offsets, the center maps to 0.5.
    When content exceeds viewport, scroll position maps correctly.
    This handles the centering-offset transition on zoom boundary. }
  if FFrameView.Width > 0 then
    NormX := (FScrollBox.HorzScrollBar.Position + FScrollBox.ClientWidth / 2)
             / FFrameView.Width
  else
    NormX := 0.5;
  if FFrameView.Height > 0 then
    NormY := (FScrollBox.VertScrollBar.Position + FScrollBox.ClientHeight / 2)
             / FFrameView.Height
  else
    NormY := 0.5;

  { Suppress repainting while layout and scroll positions change
    to avoid flickering from intermediate visual states }
  SendMessage(FScrollBox.Handle, WM_SETREDRAW, WPARAM(False), 0);
  FUpdatingLayout := True;
  try
    FFrameView.ZoomFactor := NewF;
    UpdateFrameViewSize;

    { Map normalized position to new control dimensions }
    FScrollBox.HorzScrollBar.Position :=
      Max(0, Round(NormX * FFrameView.Width - FScrollBox.ClientWidth / 2));
    FScrollBox.VertScrollBar.Position :=
      Max(0, Round(NormY * FFrameView.Height - FScrollBox.ClientHeight / 2));
  finally
    FUpdatingLayout := False;
    SendMessage(FScrollBox.Handle, WM_SETREDRAW, WPARAM(True), 0);
    RedrawWindow(FScrollBox.Handle, nil, 0,
      RDW_ERASE or RDW_FRAME or RDW_INVALIDATE or RDW_ALLCHILDREN);
  end;
end;

procedure TPluginForm.ResetZoom;
begin
  if SameValue(FFrameView.ZoomFactor, 1.0, ZOOM_EPSILON) then
    Exit;
  FFrameView.ZoomFactor := 1.0;
  UpdateFrameViewSize;
end;

procedure TPluginForm.SwitchOrCycleMode(AKey: Word);
const
  KEY_TO_MODE: array[0..4] of TViewMode =
    (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);
var
  Idx: Integer;
  Target: TViewMode;
  NextZM: TZoomMode;
begin
  case AKey of
    Ord('1')..Ord('5'): Idx := AKey - Ord('1');
    VK_NUMPAD1..VK_NUMPAD5: Idx := AKey - VK_NUMPAD1;
  else
    Exit;
  end;
  Target := KEY_TO_MODE[Idx];

  if FFrameView.ViewMode <> Target then
    ActivateMode(Target)
  else if FModePopups[Target] <> nil then
  begin
    { Cycle to next zoom submode }
    NextZM := TZoomMode((Ord(FFrameView.ZoomMode) + 1) mod (Ord(High(TZoomMode)) + 1));
    FFrameView.ZoomMode := NextZM;
    UpdateFrameViewSize;
    { Update popup check marks }
    for var I := 0 to FModePopups[Target].Items.Count - 1 do
      FModePopups[Target].Items[I].Checked :=
        TZoomMode(FModePopups[Target].Items[I].Tag) = NextZM;
    { Persist }
    FSettings.ModeZoom[Target] := NextZM;
    FSettings.Save;
  end;
end;

procedure TPluginForm.CopyFrameToClipboard;
var
  Idx: Integer;
begin
  if Length(FFrameView.FCells) = 0 then Exit;
  { Context menu passes the right-clicked cell; keyboard uses current frame }
  Idx := FContextCellIndex;
  if (Idx < 0) or (Idx >= Length(FFrameView.FCells)) then
    Idx := FFrameView.CurrentFrameIndex;
  if (Idx < 0) or (Idx >= Length(FFrameView.FCells)) then
    Idx := 0;
  if FFrameView.FCells[Idx].State <> fcsLoaded then Exit;
  Clipboard.Assign(FFrameView.FCells[Idx].Bitmap);
end;

procedure TPluginForm.CopyAllToClipboard;
var
  Bmp: TBitmap;
begin
  if Length(FFrameView.FCells) = 0 then Exit;
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(FFrameView.Width, FFrameView.Height);
    Bmp.Canvas.Brush.Color := FFrameView.BackColor;
    Bmp.Canvas.FillRect(Rect(0, 0, Bmp.Width, Bmp.Height));
    FFrameView.PaintTo(Bmp.Canvas, 0, 0);
    Clipboard.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

function TPluginForm.FrameFileName(AIndex: Integer; AFormat: TSaveFormat): string;
var
  BaseName, Ext: string;
  T: Double;
  H, M, S, MS: Integer;
begin
  BaseName := ChangeFileExt(ExtractFileName(FFileName), '');
  T := FFrameView.FCells[AIndex].TimeOffset;
  H := Trunc(T) div 3600;
  M := (Trunc(T) mod 3600) div 60;
  S := Trunc(T) mod 60;
  MS := Round(Frac(T) * 1000);
  case AFormat of
    sfJPEG: Ext := '.jpg';
  else
    Ext := '.png';
  end;
  Result := Format('%s_frame_%.2d_%.2d-%.2d-%.2d.%.3d%s',
    [BaseName, AIndex + 1, H, M, S, MS, Ext]);
end;

procedure TPluginForm.SaveBitmapToFile(ABitmap: TBitmap; const APath: string;
  AFormat: TSaveFormat);
var
  Png: TPngImage;
  Jpg: TJPEGImage;
begin
  case AFormat of
    sfPNG:
      begin
        Png := TPngImage.Create;
        try
          Png.CompressionLevel := FSettings.PngCompression;
          Png.Assign(ABitmap);
          Png.SaveToFile(APath);
        finally
          Png.Free;
        end;
      end;
    sfJPEG:
      begin
        Jpg := TJPEGImage.Create;
        try
          Jpg.CompressionQuality := FSettings.JpegQuality;
          Jpg.Assign(ABitmap);
          Jpg.SaveToFile(APath);
        finally
          Jpg.Free;
        end;
      end;
  end;
end;

procedure TPluginForm.SaveSingleFrame;
var
  Dlg: TSaveDialog;
  Idx: Integer;
  Fmt: TSaveFormat;
begin
  if Length(FFrameView.FCells) = 0 then Exit;
  { Same selection logic as CopyFrameToClipboard }
  Idx := FContextCellIndex;
  if (Idx < 0) or (Idx >= Length(FFrameView.FCells)) then
    Idx := FFrameView.CurrentFrameIndex;
  if (Idx < 0) or (Idx >= Length(FFrameView.FCells)) then
    Idx := 0;
  if FFrameView.FCells[Idx].State <> fcsLoaded then Exit;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Save frame';
    Dlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG: Dlg.FilterIndex := 2;
    else
      Dlg.FilterIndex := 1;
    end;
    Dlg.DefaultExt := 'png';
    Dlg.FileName := FrameFileName(Idx, FSettings.SaveFormat);
    if FSettings.SaveFolder <> '' then
      Dlg.InitialDir := FSettings.SaveFolder;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];

    if Dlg.Execute then
    begin
      case Dlg.FilterIndex of
        2: Fmt := sfJPEG;
      else
        Fmt := sfPNG;
      end;
      SaveBitmapToFile(FFrameView.FCells[Idx].Bitmap, Dlg.FileName, Fmt);
      FSettings.SaveFolder := ExtractFilePath(Dlg.FileName);
      FSettings.Save;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TPluginForm.SaveCombinedFrame;
var
  Dlg: TSaveDialog;
  Bmp: TBitmap;
  Fmt: TSaveFormat;
  BaseName: string;
begin
  if Length(FFrameView.FCells) = 0 then Exit;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Save combined image';
    Dlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG: Dlg.FilterIndex := 2;
    else
      Dlg.FilterIndex := 1;
    end;
    Dlg.DefaultExt := 'png';
    BaseName := ChangeFileExt(ExtractFileName(FFileName), '');
    Dlg.FileName := BaseName + '_combined.png';
    if FSettings.SaveFolder <> '' then
      Dlg.InitialDir := FSettings.SaveFolder;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];

    if Dlg.Execute then
    begin
      case Dlg.FilterIndex of
        2: Fmt := sfJPEG;
      else
        Fmt := sfPNG;
      end;
      Bmp := TBitmap.Create;
      try
        Bmp.SetSize(FFrameView.Width, FFrameView.Height);
        Bmp.Canvas.Brush.Color := FFrameView.BackColor;
        Bmp.Canvas.FillRect(Rect(0, 0, Bmp.Width, Bmp.Height));
        FFrameView.PaintTo(Bmp.Canvas, 0, 0);
        SaveBitmapToFile(Bmp, Dlg.FileName, Fmt);
      finally
        Bmp.Free;
      end;
      FSettings.SaveFolder := ExtractFilePath(Dlg.FileName);
      FSettings.Save;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TPluginForm.SaveAllFrames;
var
  Dlg: TSaveDialog;
  I: Integer;
  Dir: string;
  Fmt: TSaveFormat;
begin
  if Length(FFrameView.FCells) = 0 then Exit;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Save all frames';
    Dlg.Filter := 'PNG images (*.png)|*.png|JPEG images (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG: Dlg.FilterIndex := 2;
    else
      Dlg.FilterIndex := 1;
    end;
    Dlg.DefaultExt := 'png';
    { Show a sample filename so user sees the pattern and picks the folder }
    Dlg.FileName := FrameFileName(0, FSettings.SaveFormat);
    if FSettings.SaveFolder <> '' then
      Dlg.InitialDir := FSettings.SaveFolder;

    if Dlg.Execute then
    begin
      case Dlg.FilterIndex of
        2: Fmt := sfJPEG;
      else
        Fmt := sfPNG;
      end;
      Dir := IncludeTrailingPathDelimiter(ExtractFilePath(Dlg.FileName));
      for I := 0 to High(FFrameView.FCells) do
      begin
        if FFrameView.FCells[I].State <> fcsLoaded then Continue;
        SaveBitmapToFile(FFrameView.FCells[I].Bitmap,
          Dir + FrameFileName(I, Fmt), Fmt);
      end;
      FSettings.SaveFolder := ExtractFilePath(Dlg.FileName);
      FSettings.Save;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TPluginForm.LoadFile(const AFileName: string);
var
  FFmpeg: TFFmpegExe;
begin
  FFileName := AFileName;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  FVideoInfo := Default(TVideoInfo);

  if FFFmpegPath = '' then
  begin
    ShowError('ffmpeg not found.'#13#10'Press F2 to configure.');
    Exit;
  end;

  { Probe video metadata synchronously (fast, reads only header) }
  FFmpeg := TFFmpegExe.Create(FFFmpegPath);
  try
    FVideoInfo := FFmpeg.ProbeVideo(FFileName);
  finally
    FFmpeg.Free;
  end;

  if not FVideoInfo.IsValid then
  begin
    ShowError('Could not read video file.'#13#10 + FVideoInfo.ErrorMessage);
    Exit;
  end;

  { Set actual dimensions and aspect ratio from video metadata }
  if (FVideoInfo.Width > 0) and (FVideoInfo.Height > 0) then
  begin
    FFrameView.NativeW := FVideoInfo.Width;
    FFrameView.NativeH := FVideoInfo.Height;
    FFrameView.AspectRatio := FVideoInfo.Height / FVideoInfo.Width;
  end
  else
  begin
    FFrameView.NativeW := 0;
    FFrameView.NativeH := 0;
    FFrameView.AspectRatio := DEF_ASPECT_RATIO;
  end;

  SetupPlaceholders;
  HideError;
  StartExtraction;
end;

procedure TPluginForm.SetupPlaceholders;
begin
  FOffsets := CalculateFrameOffsets(FVideoInfo.Duration,
    FUpDown.Position, FSettings.SkipEdgesPercent);

  FFrameView.SetCellCount(Length(FOffsets), FOffsets);
  UpdateFrameViewSize;
end;

procedure TPluginForm.StartExtraction;
begin
  StopExtraction;
  FFramesLoaded := 0;

  { Show progress in marquee mode until first frame arrives }
  FProgressBar.Style := pbstMarquee;
  FProgressBar.Visible := True;
  FLblProgress.Caption := 'Extracting...';
  FLblProgress.Visible := True;

  FAnimTimer.Enabled := True;

  FWorkerThread := TExtractionThread.Create(FFFmpegPath, FFileName, FOffsets,
    Handle, FPendingFrames, FPendingLock);
  FWorkerThread.Start;
end;

procedure TPluginForm.StopExtraction;
begin
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.Terminate;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;
end;

procedure TPluginForm.ProcessPendingFrames;
var
  Snapshot: TArray<TPendingFrame>;
  I: Integer;
begin
  { Drain the queue under lock, then process outside the lock }
  FPendingLock.Enter;
  try
    Snapshot := FPendingFrames.ToArray;
    FPendingFrames.Clear;
  finally
    FPendingLock.Leave;
  end;

  for I := 0 to High(Snapshot) do
  begin
    if Snapshot[I].Bitmap <> nil then
      FFrameView.SetFrame(Snapshot[I].Index, Snapshot[I].Bitmap)
    else
      FFrameView.SetCellError(Snapshot[I].Index);
    Inc(FFramesLoaded);
  end;

  if Length(Snapshot) > 0 then
    UpdateProgress;
end;

procedure TPluginForm.DrainPendingFrameMessages;
var
  Msg: TMsg;
  I: Integer;
begin
  { Free any bitmaps still in the queue }
  FPendingLock.Enter;
  try
    for I := 0 to FPendingFrames.Count - 1 do
      FPendingFrames[I].Bitmap.Free;
    FPendingFrames.Clear;
  finally
    FPendingLock.Leave;
  end;
  { Discard stale notification messages from the Win32 queue }
  while PeekMessage(Msg, Handle, WM_FRAME_READY, WM_FRAME_READY, PM_REMOVE) do
    ; { notifications carry no payload }
  PeekMessage(Msg, Handle, WM_EXTRACTION_DONE, WM_EXTRACTION_DONE, PM_REMOVE);
end;

procedure TPluginForm.UpdateProgress;
begin
  if FFramesLoaded >= Length(FOffsets) then
  begin
    FProgressBar.Visible := False;
    FLblProgress.Visible := False;
    FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  end
  else if FFramesLoaded > 0 then
  begin
    { Switch from marquee to ranged after first frame }
    FProgressBar.Style := pbstNormal;
    FProgressBar.Max := Length(FOffsets);
    FProgressBar.Position := FFramesLoaded;
    FLblProgress.Caption := Format('Extracting... (%d/%d)',
      [FFramesLoaded, Length(FOffsets)]);
  end;
end;

procedure TPluginForm.WMFrameReady(var Message: TMessage);
begin
  ProcessPendingFrames;
end;

procedure TPluginForm.WMExtractionDone(var Message: TMessage);
begin
  { Safety net: process any frames that arrived after the last notification }
  ProcessPendingFrames;
  FProgressBar.Visible := False;
  FLblProgress.Visible := False;
  FAnimTimer.Enabled := FFrameView.HasPlaceholders;
end;

procedure TPluginForm.OnFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { Ctrl+Up/Down: adjust frame count }
  if (ssCtrl in Shift) and (Key in [VK_UP, VK_DOWN]) then
  begin
    if Key = VK_UP then
      FUpDown.Position := FUpDown.Position + 1
    else
      FUpDown.Position := FUpDown.Position - 1;
    Key := 0;
    Exit;
  end;

  { Single mode: arrow keys navigate between frames }
  if FFrameView.ViewMode = vmSingle then
  begin
    case Key of
      VK_LEFT, VK_UP:
        begin
          FFrameView.NavigateFrame(-1);
          Key := 0;
          Exit;
        end;
      VK_RIGHT, VK_DOWN:
        begin
          FFrameView.NavigateFrame(1);
          Key := 0;
          Exit;
        end;
    end;
  end;

  case Key of
    Ord('C'):
      if ssCtrl in Shift then
      begin
        if ssShift in Shift then
          CopyAllToClipboard
        else
          CopyFrameToClipboard;
        Key := 0;
      end;
    Ord('S'):
      if ssCtrl in Shift then
      begin
        if [ssShift, ssAlt] * Shift = [ssAlt] then
          SaveAllFrames
        else if [ssShift, ssAlt] * Shift = [ssShift] then
          SaveCombinedFrame
        else if [ssShift, ssAlt] * Shift = [] then
        begin
          FContextCellIndex := -1;
          SaveSingleFrame;
        end;
        Key := 0;
      end;
    Ord('A'):
      if (ssCtrl in Shift) and not (ssShift in Shift) and not (ssAlt in Shift) then
      begin
        FFrameView.SelectAll;
        Key := 0;
      end;
    VK_TAB:
      begin
        SelectNext(ActiveControl, not (ssShift in Shift), True);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        PostMessage(GetParent(Handle), WM_KEYDOWN, VK_ESCAPE, 0);
        PostMessage(GetParent(Handle), WM_KEYUP, VK_ESCAPE, 0);
        Key := 0;
      end;
    VK_OEM_PLUS, VK_ADD:
      begin
        ZoomBy(ZOOM_IN_FACTOR);
        Key := 0;
      end;
    VK_OEM_MINUS, VK_SUBTRACT:
      begin
        ZoomBy(ZOOM_OUT_FACTOR);
        Key := 0;
      end;
    Ord('0'), VK_NUMPAD0:
      begin
        ResetZoom;
        Key := 0;
      end;
    Ord('1')..Ord('5'), VK_NUMPAD1..VK_NUMPAD5:
      if ssCtrl in Shift then
      begin
        SwitchOrCycleMode(Key);
        Key := 0;
      end;
  end;
end;

procedure TPluginForm.CMDialogKey(var Message: TWMKey);
begin
  case Message.CharCode of
    VK_TAB:
      begin
        SelectNext(ActiveControl, GetKeyState(VK_SHIFT) >= 0, True);
        Message.Result := 1;
      end;
    VK_ESCAPE:
      begin
        PostMessage(GetParent(Handle), WM_KEYDOWN, VK_ESCAPE, 0);
        PostMessage(GetParent(Handle), WM_KEYUP, VK_ESCAPE, 0);
        Message.Result := 1;
      end;
  else
    inherited;
  end;
end;

procedure TPluginForm.ShowError(const AMessage: string);
begin
  FFrameView.Visible := False;
  FLblError.Caption := AMessage;
  FLblError.Visible := True;
  FAnimTimer.Enabled := False;
  FProgressBar.Visible := False;
  FLblProgress.Visible := False;
end;

procedure TPluginForm.HideError;
begin
  FLblError.Visible := False;
  FFrameView.Visible := True;
  FAnimTimer.Enabled := True;
end;

procedure TPluginForm.UpdateFrameViewSize;
var
  FitCols, DefCols: Integer;
  VW, VH: Integer;
  Zoomed: Boolean;
begin
  Zoomed := not SameValue(FFrameView.ZoomFactor, 1.0, ZOOM_EPSILON);

  { Configure scrollbox FIRST so ClientWidth/ClientHeight reflect scrollbar state }
  case FFrameView.ViewMode of
    vmScroll:
      begin
        FScrollBox.HorzScrollBar.Visible := Zoomed or (FFrameView.ZoomMode = zmActual);
        FScrollBox.VertScrollBar.Visible := True;
      end;
    vmGrid:
      begin
        FScrollBox.HorzScrollBar.Visible := Zoomed;
        FScrollBox.VertScrollBar.Visible := True;
      end;
    vmSmartGrid, vmSingle:
      begin
        FScrollBox.HorzScrollBar.Visible := Zoomed;
        FScrollBox.VertScrollBar.Visible := Zoomed;
      end;
    vmFilmstrip:
      begin
        FScrollBox.HorzScrollBar.Visible := True;
        FScrollBox.VertScrollBar.Visible := Zoomed or (FFrameView.ZoomMode = zmActual);
      end;
  end;

  { Read viewport after scrollbar config }
  VW := FScrollBox.ClientWidth;
  VH := FScrollBox.ClientHeight;
  FFrameView.SetViewport(VW, VH);

  { Calculate column count for grid mode (use frozen base when zoomed) }
  if FFrameView.ViewMode = vmGrid then
  begin
    case FFrameView.ZoomMode of
      zmFitWindow:
        FFrameView.ColumnCount := FFrameView.CalcFitColumns(
          FFrameView.BaseW, FFrameView.BaseH);
      zmFitIfLarger:
        begin
          FitCols := FFrameView.CalcFitColumns(
            FFrameView.BaseW, FFrameView.BaseH);
          DefCols := FFrameView.DefaultColumnCount;
          FFrameView.ColumnCount := Max(FitCols, DefCols);
        end;
    else
      FFrameView.ColumnCount := 0;
    end;
  end
  else
    FFrameView.ColumnCount := 0;

  { RecalcSize sets Width/Height for all modes.
    Do NOT reset Left/Top here: the scrollbox manages child positioning
    via its scroll offset. Resetting Left=0 while Position>0 creates an
    inconsistency that breaks subsequent ScrollBy delta calculations. }
  FFrameView.RecalcSize;
  FFrameView.Invalidate;
end;

procedure TPluginForm.UpdateViewModeButtons;
var
  VM: TViewMode;
begin
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    if FFrameView.ViewMode = VM then
      FModeButtons[VM].Font.Style := [fsBold]
    else
      FModeButtons[VM].Font.Style := [];
  end;
end;

procedure TPluginForm.OnModeButtonClick(Sender: TObject);
begin
  ActivateMode(TViewMode(TButton(Sender).Tag));
end;

procedure TPluginForm.OnSizingMenuClick(Sender: TObject);
var
  MI: TMenuItem;
  I: Integer;
begin
  MI := Sender as TMenuItem;
  { Uncheck all siblings, check this one }
  for I := 0 to MI.Parent.Count - 1 do
    MI.Parent.Items[I].Checked := False;
  MI.Checked := True;

  FFrameView.ZoomMode := TZoomMode(MI.Tag);
  UpdateFrameViewSize;

  { Persist user preference }
  FSettings.ZoomMode := FFrameView.ZoomMode;
  FSettings.Save;
end;

procedure TPluginForm.Resize;
begin
  inherited;
  Realign;
  if not FUpdatingLayout and Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
end;

function TPluginForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Msg: TWMMouseWheel;
begin
  { Ctrl+Wheel: continuous zoom }
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ZoomBy(ZOOM_IN_FACTOR)
    else
      ZoomBy(ZOOM_OUT_FACTOR);
    Result := True;
    Exit;
  end;

  { Forward to TFrameView so wheel logic lives in one place (WMMouseWheel) }
  if Assigned(FFrameView) and Assigned(FScrollBox) and FScrollBox.Visible then
  begin
    ZeroMemory(@Msg, SizeOf(Msg));
    Msg.Msg := WM_MOUSEWHEEL;
    Msg.WheelDelta := WheelDelta;
    FFrameView.Perform(WM_MOUSEWHEEL, TMessage(Msg).WParam, TMessage(Msg).LParam);
    Result := True;
  end
  else
    Result := inherited;
end;

procedure TPluginForm.OnScrollBoxResize(Sender: TObject);
begin
  if not FUpdatingLayout and Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
end;

procedure TPluginForm.OnContextMenuPopup(Sender: TObject);
var
  I: Integer;
  MI: TMenuItem;
  Pt: TPoint;
  HasFrames, HasClickedFrame: Boolean;
begin
  HasFrames := Length(FFrameView.FCells) > 0;

  { Hit-test: which cell was right-clicked? }
  Pt := FFrameView.ScreenToClient(FContextMenu.PopupPoint);
  FContextCellIndex := FFrameView.CellIndexAt(Pt);
  HasClickedFrame := (FContextCellIndex >= 0)
    and (FFrameView.FCells[FContextCellIndex].State = fcsLoaded);

  for I := 0 to FContextMenu.Items.Count - 1 do
  begin
    MI := FContextMenu.Items[I];
    case MI.Tag of
      CM_SAVE_FRAME:    MI.Enabled := HasClickedFrame;
      CM_SAVE_COMBINED: MI.Enabled := HasFrames;
      CM_SAVE_ALL:      MI.Enabled := HasFrames;
      CM_COPY_FRAME:    MI.Enabled := HasClickedFrame;
      CM_COPY_ALL:      MI.Enabled := HasFrames;
      CM_SELECT_ALL:    MI.Enabled := HasFrames;
      CM_DESELECT_ALL:  MI.Enabled := FFrameView.SelectedCount > 0;
      CM_SAVE_SELECTED,
      CM_SETTINGS:      MI.Enabled := False;
    end;
  end;
end;

procedure TPluginForm.OnContextMenuClick(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    CM_SAVE_FRAME:    SaveSingleFrame;
    CM_SAVE_COMBINED: SaveCombinedFrame;
    CM_SAVE_ALL:      SaveAllFrames;
    CM_COPY_FRAME:    CopyFrameToClipboard;
    CM_COPY_ALL:      CopyAllToClipboard;
    CM_SELECT_ALL:    FFrameView.SelectAll;
    CM_DESELECT_ALL:  FFrameView.DeselectAll;
  end;
end;

procedure TPluginForm.OnAnimTimer(Sender: TObject);
begin
  { Drain any frames that arrived since the last notification.
    Covers the case where PostMessage notifications miss the HWND. }
  ProcessPendingFrames;
  if Assigned(FFrameView) and FFrameView.Visible then
    FFrameView.AdvanceAnimation;
end;

procedure TPluginForm.OnFrameCountChange(Sender: TObject);
begin
  { Persist user preference }
  FSettings.FramesCount := FUpDown.Position;
  FSettings.Save;

  if not FVideoInfo.IsValid then Exit;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  SetupPlaceholders;
  StartExtraction;
end;

end.
