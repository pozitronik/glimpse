{ Main plugin form, frame view control, and extraction worker thread.
  The form is parented to TC's Lister window and hosts the toolbar and frame display. }
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.IOUtils,
  System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Clipbrd, Vcl.Dialogs, Vcl.Buttons,
  uSettings, uFrameOffsets, uFFmpegExe, uCache, uWlxAPI,
  uFrameFileNames, uBitmapSaver, uZoomController, uViewModeLogic,
  uExtractionPlanner, uToolbarLayout;

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
    Count: Integer;
  end;

  { Extracted frame awaiting delivery to UI thread }
  TPendingFrame = record
    Index: Integer;
    Bitmap: TBitmap; { nil = extraction error }
  end;

  { Worker thread that extracts frames sequentially via ffmpeg.exe.
    Stores results in a thread-safe queue and posts notifications. }
  TExtractionThread = class(TThread)
  private
    FFFmpegPath: string;
    FFileName: string;
    FOffsets: TFrameOffsetArray;
    FNotifyWnd: HWND;
    FQueue: TList<TPendingFrame>;
    FQueueLock: TCriticalSection;
    FCache: IFrameCache;
    FActiveWorkerCount: PInteger; { shared counter; last thread posts WM_EXTRACTION_DONE }
  protected
    procedure Execute; override;
  public
    constructor Create(const AFFmpegPath, AFileName: string; const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND; AQueue: TList<TPendingFrame>;  AQueueLock: TCriticalSection; const ACache: IFrameCache; AActiveWorkerCount: PInteger);
  end;

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
    function BaseW: Integer;
    function BaseH: Integer;
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
  end;

  { Plugin form created as a child of TC's Lister window. }
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
    FBtnTimecode: TSpeedButton;
    FToolbarButtons: array of TButton;
    FBtnHamburger: TButton;
    FHamburgerMenu: TPopupMenu;
    FProgressBar: TProgressBar;
    FLblProgress: TLabel;
    { Stored X positions from initial layout for collapse threshold checks }
    FFrameCountRight: Integer;
    FModeGroupRight: Integer;
    FActionsRight: Integer;
    { Status bar }
    FStatusBar: TStatusBar;
    { Content }
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    { Worker }
    FWorkerThreads: TArray<TExtractionThread>;
    FActiveWorkerCount: Integer;
    FFramesLoaded: Integer;
    FPendingFrames: TList<TPendingFrame>;
    FPendingLock: TCriticalSection;
    FCache: IFrameCache;
    { Animation }
    FAnimTimer: TTimer;
    { Layout guard: prevents re-entrant UpdateFrameViewSize during zoom }
    FUpdatingLayout: Boolean;

    procedure CreateToolbar;
    procedure LayoutToolbar;
    procedure OnHamburgerClick(Sender: TObject);
    procedure OnHamburgerMenuPopup(Sender: TObject);
    procedure OnHamburgerModeClick(Sender: TObject);
    procedure OnHamburgerZoomClick(Sender: TObject);
    procedure OnHamburgerTimecodeClick(Sender: TObject);
    procedure OnHamburgerActionClick(Sender: TObject);
    procedure CreateFrameView;
    procedure CreateStatusBar;
    procedure UpdateStatusBar;
    procedure OnStatusBarDblClick(Sender: TObject);
    procedure CreateContextMenu;
    procedure CreateErrorLabel;
    function CreateModePopup(AMode: TViewMode): TPopupMenu;
    procedure ApplySettings;
    procedure SetupPlaceholders;
    procedure ShowError(const AMessage: string);
    procedure HideError;
    procedure UpdateFrameViewSize;
    procedure UpdateViewModeButtons;
    procedure SyncZoomMenuChecks(AMode: TViewMode; AZoom: TZoomMode);
    procedure UpdateTimecodeButton;
    procedure UpdateToolbarButtons;
    procedure DispatchCommand(ATag: Integer);
    procedure OnToolbarButtonClick(Sender: TObject);
    procedure ActivateMode(AMode: TViewMode);
    procedure ZoomBy(AFactor: Double);
    procedure ResetZoom;
    procedure SwitchOrCycleMode(AKey: Word);
    function RenderFrameView: TBitmap;
    procedure CopyAllToClipboard;
    function ResolveFrameIndex(out AIndex: Integer): Boolean;
    function ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean; out APath: string; out AFormat: TSaveFormat): Boolean;
    procedure SaveSingleFrame;
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean);
    procedure SaveSelectedFrames;
    procedure SaveCombinedFrame;
    procedure SaveAllFrames;
    procedure ShowSettings;
    procedure RefreshExtraction;
    procedure StartExtraction(const ACacheOverride: IFrameCache = nil);
    procedure StopExtraction;
    procedure ProcessPendingFrames;
    procedure DrainPendingFrameMessages;
    procedure UpdateProgress;
    procedure OnAnimTimer(Sender: TObject);
    procedure OnFrameCountChange(Sender: TObject);
    procedure OnModeButtonClick(Sender: TObject);
    procedure OnSizingMenuClick(Sender: TObject);
    procedure OnTimecodeButtonClick(Sender: TObject);
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
    procedure CopyFrameToClipboard;
    procedure ApplyListerParams(AParams: Integer);
  end;

implementation

uses
  uSettingsDlg;

{$IFDEF DEBUG}
procedure FormLog(const AMsg: string);
begin
  DebugLog('Form', AMsg);
end;
{$ENDIF}

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

{ Subclass callback on TC's Lister parent window.
  TC may not resize the plugin child for all resize directions;
  this ensures the plugin always fills the parent's client rect. }
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

  { UI layout }
  ANIM_INTERVAL_MS = 80;   { placeholder spinner animation tick }
  MAX_FRAME_COUNT  = 99;   { upper limit for frame count spin edit }
  STATUSBAR_HEIGHT = 21;
  STATUSBAR_FONT   = 9;

  { Command tags, mode captions, sizing labels, and toolbar actions
    are defined in uToolbarLayout }

{ TExtractionThread }

constructor TExtractionThread.Create(const AFFmpegPath, AFileName: string; const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND; AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection; const ACache: IFrameCache; AActiveWorkerCount: PInteger);
begin
  inherited Create(True); { suspended }
  FreeOnTerminate := False;
  FFFmpegPath := AFFmpegPath;
  FFileName := AFileName;
  FOffsets := Copy(AOffsets);
  FNotifyWnd := ANotifyWnd;
  FQueue := AQueue;
  FQueueLock := AQueueLock;
  FCache := ACache;
  FActiveWorkerCount := AActiveWorkerCount;
end;

procedure TExtractionThread.Execute;
var
  FFmpeg: TFFmpegExe;
  Bmp: TBitmap;
  Frame: TPendingFrame;
  I, CellIdx: Integer;
  Source: string;
begin
  {$IFDEF DEBUG}FormLog(Format('Thread.Execute START frames=%d', [Length(FOffsets)]));{$ENDIF}
  try
    FFmpeg := TFFmpegExe.Create(FFFmpegPath);
    try
      for I := 0 to High(FOffsets) do
      begin
        if Terminated then
        begin
          {$IFDEF DEBUG}FormLog(Format('Thread.Execute TERMINATED at i=%d', [I]));{$ENDIF}
          Exit;
        end;

        CellIdx := FOffsets[I].Index - 1; { 1-based offset index to 0-based cell index }
        Bmp := nil;

        try
          Source := 'none';

          Bmp := FCache.TryGet(FFileName, FOffsets[I].TimeOffset);
          if Bmp <> nil then
            Source := 'cache';

          { Cache miss: extract via ffmpeg }
          if Bmp = nil then
          begin
            Bmp := FFmpeg.ExtractFrame(FFileName, FOffsets[I].TimeOffset);
            if Bmp <> nil then
            begin
              Source := 'ffmpeg';
              FCache.Put(FFileName, FOffsets[I].TimeOffset, Bmp);
            end;
          end;

          {$IFDEF DEBUG}
          if Bmp <> nil then
            FormLog(Format('Frame[%d] source=%s size=%dx%d empty=%s',
              [CellIdx, Source, Bmp.Width, Bmp.Height, BoolToStr(Bmp.Empty, True)]))
          else
            FormLog(Format('Frame[%d] source=%s Bmp=NIL', [CellIdx, Source]));
          {$ENDIF}
        except
          on E: Exception do
          begin
            {$IFDEF DEBUG}
            FormLog(Format('Frame[%d] EXCEPTION: %s: %s', [CellIdx, E.ClassName, E.Message]));
            {$ENDIF}
            FreeAndNil(Bmp);
          end;
        end;

        if Terminated then
        begin
          Bmp.Free;
          Exit;
        end;

        { Enqueue frame for the UI thread; PostMessage is just a notification.
          Bitmap = nil signals an error placeholder to the UI. }
        Frame.Index := CellIdx;
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
  finally
    { Always decrement; last worker to finish notifies the UI }
    if InterlockedDecrement(FActiveWorkerCount^) = 0 then
      if not Terminated then
        PostMessage(FNotifyWnd, WM_EXTRACTION_DONE, 0, 0);
  end;
end;

{ TFrameView }

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
  CreateStatusBar;
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

  {$IFDEF DEBUG}
  uCache.GDebugLogPath := ExtractFilePath(FSettings.IniPath) + 'glimpse_debug.log';
  FormLog(Format('CreateForPlugin: file=%s handle=$%s', [AFileName, IntToHex(Handle)]));
  {$ENDIF}

  if FSettings.CacheEnabled then
  begin
    FCache := TFrameCache.Create(EffectiveCacheFolder(FSettings.CacheFolder), FSettings.CacheMaxSizeMB);
  end
  else
    FCache := TNullFrameCache.Create;

  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := ANIM_INTERVAL_MS;
  FAnimTimer.OnTimer := OnAnimTimer;
  FAnimTimer.Enabled := True;

  LoadFile(AFileName);
end;

destructor TPluginForm.Destroy;
begin
  if FParentWnd <> 0 then
    RemoveWindowSubclass(FParentWnd, @ParentSubclassProc, 1);
  { FAnimTimer may not exist yet if destructor runs during CreateForPlugin
    (VCL can destroy a windowed control before the constructor finishes) }
  if Assigned(FAnimTimer) then
    FAnimTimer.Enabled := False;
  StopExtraction;
  if Assigned(FPendingLock) then
    DrainPendingFrameMessages;
  if Assigned(FFrameView) then
    FFrameView.ClearCells;
  FPendingLock.Free;
  FPendingFrames.Free;
  { FCache is an interface reference, released automatically }
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
  X, CY, CtrlH, BW, I: Integer;
  VM: TViewMode;
  TabIdx: Integer;
  Btn: TButton;
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
  FUpDown.Max := MAX_FRAME_COUNT;
  Inc(X, 40 + FUpDown.Width + CTRL_GAP);
  FFrameCountRight := X;

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
  FModeGroupRight := X;

  FBtnTimecode := TSpeedButton.Create(FToolbar);
  FBtnTimecode.Parent := FToolbar;
  BW := Canvas.TextWidth('Timecodes') + BTN_PAD;
  FBtnTimecode.SetBounds(X, CY, BW, CtrlH);
  FBtnTimecode.Caption := 'Timecodes';
  FBtnTimecode.GroupIndex := 1;
  FBtnTimecode.AllowAllUp := True;
  FBtnTimecode.OnClick := OnTimecodeButtonClick;
  Inc(X, BW + CTRL_GAP);

  { Action buttons matching context menu (except selection-dependent commands) }
  SetLength(FToolbarButtons, 0);
  for I := 0 to High(TB_ACTIONS) do
  begin
    Btn := TButton.Create(FToolbar);
    Btn.Parent := FToolbar;
    BW := Canvas.TextWidth(TB_ACTIONS[I].Caption) + BTN_PAD;
    Btn.SetBounds(X, CY, BW, CtrlH);
    Btn.Caption := TB_ACTIONS[I].Caption;
    Btn.Tag := TB_ACTIONS[I].Tag;
    Btn.Enabled := False;
    Btn.OnClick := OnToolbarButtonClick;
    Inc(X, BW + BTN_GAP);
    SetLength(FToolbarButtons, Length(FToolbarButtons) + 1);
    FToolbarButtons[High(FToolbarButtons)] := Btn;
  end;
  Inc(X, CTRL_GAP - BTN_GAP);
  FActionsRight := X;

  FProgressBar := TProgressBar.Create(FToolbar);
  FProgressBar.Parent := FToolbar;
  FProgressBar.SetBounds(X, CY + (CtrlH - PB_H) div 2, 120, PB_H);
  FProgressBar.Visible := False;

  FLblProgress := TLabel.Create(FToolbar);
  FLblProgress.Parent := FToolbar;
  FLblProgress.AutoSize := True;
  FLblProgress.Caption := 'Extracting...'; { set text for correct height measurement }
  FLblProgress.Left := X + 120 + 4;
  FLblProgress.Top := CY + (CtrlH - FLblProgress.Height) div 2;
  FLblProgress.Caption := '';
  FLblProgress.Visible := False;

  { Hamburger overflow button: hidden until toolbar is too narrow }
  FHamburgerMenu := TPopupMenu.Create(Self);
  FHamburgerMenu.OnPopup := OnHamburgerMenuPopup;

  FBtnHamburger := TButton.Create(FToolbar);
  FBtnHamburger.Parent := FToolbar;
  BW := Canvas.TextWidth(#$2630) + BTN_PAD;
  FBtnHamburger.SetBounds(0, CY, BW, CtrlH);
  FBtnHamburger.Caption := #$2630;
  FBtnHamburger.OnClick := OnHamburgerClick;
  FBtnHamburger.Visible := False;
end;

procedure TPluginForm.LayoutToolbar;
const
  CTRL_GAP = 8;
  PB_H     = 16;
var
  Layout: TToolbarLayoutResult;
  VM: TViewMode;
  I: Integer;
  CY, CtrlH: Integer;
begin
  if not Assigned(FBtnHamburger) then Exit;

  Layout := ComputeToolbarLayout(FToolbar.ClientWidth, FFrameCountRight,
    FModeGroupRight, FActionsRight, FBtnHamburger.Width, CTRL_GAP);

  { Show/hide mode buttons }
  for VM := Low(TViewMode) to High(TViewMode) do
    FModeButtons[VM].Visible := Layout.CollapseState <> tcsAllCollapsed;

  { Show/hide timecodes + action buttons }
  FBtnTimecode.Visible := Layout.CollapseState = tcsExpanded;
  for I := 0 to High(FToolbarButtons) do
    FToolbarButtons[I].Visible := Layout.CollapseState = tcsExpanded;

  { Hamburger button }
  FBtnHamburger.Visible := Layout.CollapseState <> tcsExpanded;
  FBtnHamburger.Left := Layout.HamburgerLeft;

  { Reposition progress bar and label }
  CtrlH := FEditFrameCount.Height;
  CY := (FToolbar.Height - CtrlH) div 2;
  FProgressBar.SetBounds(Layout.ProgressLeft, CY + (CtrlH - PB_H) div 2, 120, PB_H);
  FLblProgress.Left := Layout.ProgressLeft + 120 + 4;
end;

procedure TPluginForm.OnHamburgerClick(Sender: TObject);
var
  P: TPoint;
begin
  P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
  FHamburgerMenu.Popup(P.X, P.Y);
end;

procedure TPluginForm.OnHamburgerMenuPopup(Sender: TObject);
var
  State: THamburgerMenuState;
  VM: TViewMode;
begin
  if not FModeButtons[vmSmartGrid].Visible then
    State.CollapseState := tcsAllCollapsed
  else
    State.CollapseState := tcsActionsCollapsed;
  State.ActiveMode := FFrameView.ViewMode;
  State.ShowTimecode := FFrameView.ShowTimecode;
  State.HasFrames := FFramesLoaded > 0;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    State.ModeZooms[VM] := FSettings.ModeZoom[VM];
    State.ModeHasSubmenu[VM] := FModePopups[VM] <> nil;
  end;

  PopulateHamburgerMenu(FHamburgerMenu, State,
    OnHamburgerModeClick, OnHamburgerZoomClick,
    OnHamburgerTimecodeClick, OnHamburgerActionClick);
end;

procedure TPluginForm.OnHamburgerModeClick(Sender: TObject);
begin
  ActivateMode(TViewMode(TMenuItem(Sender).Tag));
end;

procedure TPluginForm.OnHamburgerZoomClick(Sender: TObject);
var
  AMode: TViewMode;
  AZoom: TZoomMode;
  Tag: Integer;
begin
  Tag := TMenuItem(Sender).Tag;
  AMode := TViewMode(Tag shr 8);
  AZoom := TZoomMode(Tag and $FF);

  { First activate the mode, then override its zoom }
  ActivateMode(AMode);
  FFrameView.ZoomMode := AZoom;
  UpdateFrameViewSize;

  { Persist and sync the popup menu checks }
  FSettings.ModeZoom[AMode] := AZoom;
  FSettings.ZoomMode := AZoom;
  FSettings.Save;
  SyncZoomMenuChecks(AMode, AZoom);
end;

procedure TPluginForm.OnHamburgerTimecodeClick(Sender: TObject);
begin
  OnTimecodeButtonClick(Sender);
end;

procedure TPluginForm.OnHamburgerActionClick(Sender: TObject);
begin
  DispatchCommand(TMenuItem(Sender).Tag);
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
  AddItem('Refresh'#9'R', CM_REFRESH);
  AddItem('Settings...'#9'F2', CM_SETTINGS);

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

procedure TPluginForm.CreateStatusBar;
begin
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Height := STATUSBAR_HEIGHT;
  FStatusBar.SimplePanel := False;
  FStatusBar.SizeGrip := False;
  FStatusBar.Font.Size := STATUSBAR_FONT;
  FStatusBar.OnDblClick := OnStatusBarDblClick;
  FStatusBar.Visible := False;
end;

procedure TPluginForm.UpdateStatusBar;

  function FormatDuration(ASeconds: Double): string;
  var
    H, M, S: Integer;
    Total: Integer;
  begin
    if ASeconds <= 0 then
      Exit('?');
    Total := Round(ASeconds);
    H := Total div 3600;
    M := (Total mod 3600) div 60;
    S := Total mod 60;
    if H > 0 then
      Result := Format('%d:%.2d:%.2d', [H, M, S])
    else
      Result := Format('%d:%.2d', [M, S]);
  end;

  function FormatBitrate(AKbps: Integer): string;
  begin
    if AKbps >= 1000 then
      Result := Format('%.1f Mbps', [AKbps / 1000])
    else
      Result := Format('%d kbps', [AKbps]);
  end;

  procedure AddPanel(const AText: string; AWidth: Integer);
  var
    Panel: TStatusPanel;
  begin
    Panel := FStatusBar.Panels.Add;
    Panel.Text := AText;
    Panel.Width := AWidth;
  end;

var
  AudioStr: string;
begin
  FStatusBar.Panels.Clear;

  if not FVideoInfo.IsValid then
    Exit;

  { Resolution }
  if (FVideoInfo.Width > 0) and (FVideoInfo.Height > 0) then
    AddPanel(Format('%dx%d', [FVideoInfo.Width, FVideoInfo.Height]), 120);

  { Framerate }
  if FVideoInfo.Fps > 0 then
    AddPanel(Format('%.4g fps', [FVideoInfo.Fps]), 100);

  { Duration }
  if FVideoInfo.Duration > 0 then
    AddPanel(FormatDuration(FVideoInfo.Duration), 100);

  { Overall bitrate }
  if FVideoInfo.Bitrate > 0 then
    AddPanel(FormatBitrate(FVideoInfo.Bitrate), 100);

  { Video codec }
  if FVideoInfo.VideoCodec <> '' then
    AddPanel(FVideoInfo.VideoCodec, 90);

  { Audio section }
  if FVideoInfo.AudioCodec <> '' then
  begin
    AudioStr := FVideoInfo.AudioCodec;
    if FVideoInfo.AudioSampleRate > 0 then
      AudioStr := AudioStr + Format(' %d Hz', [FVideoInfo.AudioSampleRate]);
    if FVideoInfo.AudioChannels <> '' then
      AudioStr := AudioStr + ' ' + FVideoInfo.AudioChannels;
    if FVideoInfo.AudioBitrateKbps > 0 then
      AudioStr := AudioStr + Format(' %d kbps', [FVideoInfo.AudioBitrateKbps]);
    AddPanel(AudioStr, 200);
  end
  else
    AddPanel('No audio', 110);
end;

procedure TPluginForm.OnStatusBarDblClick(Sender: TObject);
var
  Pt: TPoint;
  PanelLeft, I: Integer;
begin
  if FStatusBar.Panels.Count = 0 then
    Exit;

  Pt := FStatusBar.ScreenToClient(Mouse.CursorPos);
  PanelLeft := 0;
  for I := 0 to FStatusBar.Panels.Count - 1 do
  begin
    if Pt.X < PanelLeft + FStatusBar.Panels[I].Width then
    begin
      Clipboard.AsText := FStatusBar.Panels[I].Text;
      Exit;
    end;
    Inc(PanelLeft, FStatusBar.Panels[I].Width);
  end;

  { Click past last panel: copy last panel }
  Clipboard.AsText := FStatusBar.Panels[FStatusBar.Panels.Count - 1].Text;
end;

procedure TPluginForm.ApplySettings;
var
  VM: TViewMode;
begin
  if FSettings = nil then Exit;

  FUpDown.Position := FSettings.FramesCount;
  FFrameView.ViewMode := FSettings.ViewMode;
  FFrameView.ZoomMode := FSettings.ZoomMode;

  { Restore per-mode zoom selections in all popup menus }
  for VM := Low(TViewMode) to High(TViewMode) do
    SyncZoomMenuChecks(VM, FSettings.ModeZoom[VM]);

  UpdateViewModeButtons;
  FToolbar.Visible := FSettings.ShowToolbar;
  FStatusBar.Visible := FSettings.ShowStatusBar;
  FFrameView.ShowTimecode := FSettings.ShowTimecode;
  FFrameView.TimecodeBackColor := FSettings.TimecodeBackColor;
  FFrameView.TimecodeBackAlpha := FSettings.TimecodeBackAlpha;
  UpdateTimecodeButton;
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
  NewF, NormX, NormY: Double;
begin
  NewF := ClampZoomFactor(FFrameView.ZoomFactor, AFactor);
  if NewF = 0 then
    Exit;

  NormX := NormalizeViewportCenter(
    FScrollBox.HorzScrollBar.Position, FScrollBox.ClientWidth, FFrameView.Width);
  NormY := NormalizeViewportCenter(
    FScrollBox.VertScrollBar.Position, FScrollBox.ClientHeight, FFrameView.Height);

  SendMessage(FScrollBox.Handle, WM_SETREDRAW, WPARAM(False), 0);
  FUpdatingLayout := True;
  try
    FFrameView.ZoomFactor := NewF;
    UpdateFrameViewSize;
    FScrollBox.HorzScrollBar.Position :=
      DenormalizeViewportCenter(NormX, FFrameView.Width, FScrollBox.ClientWidth);
    FScrollBox.VertScrollBar.Position :=
      DenormalizeViewportCenter(NormY, FFrameView.Height, FScrollBox.ClientHeight);
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
var
  Target: TViewMode;
  NextZM: TZoomMode;
begin
  if not KeyToViewMode(AKey, Target) then
    Exit;

  if FFrameView.ViewMode <> Target then
    ActivateMode(Target)
  else if ModeHasZoomSubmodes(Target) then
  begin
    NextZM := NextZoomMode(FFrameView.ZoomMode);
    FFrameView.ZoomMode := NextZM;
    UpdateFrameViewSize;
    SyncZoomMenuChecks(Target, NextZM);
    FSettings.ModeZoom[Target] := NextZM;
    FSettings.Save;
  end;
end;

procedure TPluginForm.CopyFrameToClipboard;
var
  Idx: Integer;
begin
  if not ResolveFrameIndex(Idx) then Exit;
  Clipboard.Assign(FFrameView.CellBitmap(Idx));
end;

procedure TPluginForm.ApplyListerParams(AParams: Integer);
var
  NewZM: TZoomMode;
begin
  NewZM := ListerParamsToZoomMode(AParams);
  if FFrameView.ZoomMode = NewZM then
    Exit;

  FFrameView.ZoomFactor := 1.0;
  FFrameView.ZoomMode := NewZM;
  UpdateFrameViewSize;
  SyncZoomMenuChecks(FFrameView.ViewMode, NewZM);
  FSettings.ZoomMode := NewZM;
  FSettings.Save;
end;

{ Renders the entire frame view into a new bitmap. Caller owns the result. }
function TPluginForm.RenderFrameView: TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(FFrameView.Width, FFrameView.Height);
  Result.Canvas.Brush.Color := FFrameView.BackColor;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));
  FFrameView.PaintTo(Result.Canvas, 0, 0);
end;

procedure TPluginForm.CopyAllToClipboard;
var
  Bmp: TBitmap;
begin
  if FFrameView.CellCount = 0 then Exit;
  Bmp := RenderFrameView;
  try
    Clipboard.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

function TPluginForm.ResolveFrameIndex(out AIndex: Integer): Boolean;
begin
  Result := False;
  if FFrameView.CellCount = 0 then Exit;
  { Prefer the right-clicked cell, fall back to current frame, then index 0 }
  AIndex := FContextCellIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := FFrameView.CurrentFrameIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := 0;
  Result := FFrameView.CellState(AIndex) = fcsLoaded;
end;

function TPluginForm.ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean;
  out APath: string; out AFormat: TSaveFormat): Boolean;
var
  Dlg: TSaveDialog;
begin
  Result := False;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := ATitle;
    Dlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG: Dlg.FilterIndex := 2;
    else
      Dlg.FilterIndex := 1;
    end;
    Dlg.DefaultExt := 'png';
    Dlg.FileName := ADefaultName;
    if FSettings.SaveFolder <> '' then
      Dlg.InitialDir := FSettings.SaveFolder;
    if AOverwritePrompt then
      Dlg.Options := Dlg.Options + [ofOverwritePrompt];

    if Dlg.Execute then
    begin
      case Dlg.FilterIndex of
        2: AFormat := sfJPEG;
      else
        AFormat := sfPNG;
      end;
      APath := Dlg.FileName;
      FSettings.SaveFolder := ExtractFilePath(Dlg.FileName);
      FSettings.Save;
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TPluginForm.SaveSingleFrame;
var
  Idx: Integer;
  Fmt: TSaveFormat;
  Path: string;
begin
  if not ResolveFrameIndex(Idx) then Exit;

  if ShowSaveDialog('Save frame',
    GenerateFrameFileName(FFileName, Idx, FFrameView.CellTimeOffset(Idx), FSettings.SaveFormat),
    True, Path, Fmt) then
    uBitmapSaver.SaveBitmapToFile(FFrameView.CellBitmap(Idx), Path, Fmt,
      FSettings.JpegQuality, FSettings.PngCompression);
end;

procedure TPluginForm.SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean);
var
  I: Integer;
begin
  for I := 0 to FFrameView.CellCount - 1 do
  begin
    if ASelectedOnly and not FFrameView.CellSelected(I) then Continue;
    if FFrameView.CellState(I) <> fcsLoaded then Continue;
    uBitmapSaver.SaveBitmapToFile(FFrameView.CellBitmap(I),
      ADir + GenerateFrameFileName(FFileName, I, FFrameView.CellTimeOffset(I), AFormat), AFormat,
      FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TPluginForm.SaveSelectedFrames;
var
  I, FirstSel: Integer;
  Path: string;
  Fmt: TSaveFormat;
begin
  if FFrameView.SelectedCount < 2 then Exit;

  { Find first selected frame for the sample filename }
  FirstSel := 0;
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellSelected(I) then begin FirstSel := I; Break; end;

  if not ShowSaveDialog('Save selected frames',
    GenerateFrameFileName(FFileName, FirstSel, FFrameView.CellTimeOffset(FirstSel), FSettings.SaveFormat),
    False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, True);
end;

procedure TPluginForm.SaveCombinedFrame;
var
  Bmp: TBitmap;
  Fmt: TSaveFormat;
  Path, BaseName: string;
begin
  if FFrameView.CellCount = 0 then Exit;

  BaseName := ChangeFileExt(ExtractFileName(FFileName), '');
  if not ShowSaveDialog('Save combined image', BaseName + '_combined.png', True, Path, Fmt) then
    Exit;

  Bmp := RenderFrameView;
  try
    uBitmapSaver.SaveBitmapToFile(Bmp, Path, Fmt,
      FSettings.JpegQuality, FSettings.PngCompression);
  finally
    Bmp.Free;
  end;
end;

procedure TPluginForm.SaveAllFrames;
var
  Path: string;
  Fmt: TSaveFormat;
begin
  if FFrameView.CellCount = 0 then Exit;

  { Show a sample filename so user sees the pattern and picks the folder }
  if not ShowSaveDialog('Save all frames',
    GenerateFrameFileName(FFileName, 0, FFrameView.CellTimeOffset(0), FSettings.SaveFormat),
    False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, False);
end;

procedure TPluginForm.LoadFile(const AFileName: string);
var
  FFmpeg: TFFmpegExe;
begin
  {$IFDEF DEBUG}FormLog(Format('LoadFile: %s', [AFileName]));{$ENDIF}
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

  UpdateStatusBar;

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

procedure TPluginForm.StartExtraction(const ACacheOverride: IFrameCache);
var
  ThreadCache: IFrameCache;
  Chunks: TArray<TWorkerChunk>;
  W: Integer;
  Chunk: TFrameOffsetArray;
begin
  StopExtraction;
  FFramesLoaded := 0;
  UpdateToolbarButtons;

  { Show progress in marquee mode until first frame arrives }
  FProgressBar.Style := pbstMarquee;
  FProgressBar.Visible := True;
  FLblProgress.Caption := 'Extracting...';
  FLblProgress.Visible := True;

  FAnimTimer.Enabled := True;

  if ACacheOverride <> nil then
    ThreadCache := ACacheOverride
  else
    ThreadCache := FCache;

  Chunks := PlanWorkerChunks(Length(FOffsets), FSettings.MaxWorkers);
  FActiveWorkerCount := Length(Chunks);
  SetLength(FWorkerThreads, Length(Chunks));

  for W := 0 to High(Chunks) do
  begin
    Chunk := Copy(FOffsets, Chunks[W].Start, Chunks[W].Len);
    FWorkerThreads[W] := TExtractionThread.Create(FFFmpegPath, FFileName, Chunk,
      Handle, FPendingFrames, FPendingLock, ThreadCache, @FActiveWorkerCount);
  end;

  { Start all threads after creation to minimize scheduling skew }
  for W := 0 to High(Chunks) do
    FWorkerThreads[W].Start;
end;

procedure TPluginForm.StopExtraction;
var
  W: Integer;
begin
  { Signal all workers to stop }
  for W := 0 to High(FWorkerThreads) do
    FWorkerThreads[W].Terminate;
  { Wait for all workers to finish, then free }
  for W := 0 to High(FWorkerThreads) do
  begin
    FWorkerThreads[W].WaitFor;
    FWorkerThreads[W].Free;
  end;
  FWorkerThreads := nil;
end;

procedure TPluginForm.ProcessPendingFrames;
var
  Snapshot: TArray<TPendingFrame>;
  I: Integer;
begin
  { Drain the queue under lock, then process outside the lock }
  FPendingLock.Enter;
  try
    if FPendingFrames.Count = 0 then
      Exit;
    Snapshot := FPendingFrames.ToArray;
    FPendingFrames.Clear;
  finally
    FPendingLock.Leave;
  end;

  {$IFDEF DEBUG}
  if Length(Snapshot) > 0 then
    FormLog(Format('ProcessPending: count=%d', [Length(Snapshot)]));
  {$ENDIF}

  for I := 0 to High(Snapshot) do
  begin
    if Snapshot[I].Bitmap <> nil then
    begin
      {$IFDEF DEBUG}
      FormLog(Format('  SetFrame[%d] bmp=%dx%d empty=%s',
        [Snapshot[I].Index, Snapshot[I].Bitmap.Width, Snapshot[I].Bitmap.Height,
         BoolToStr(Snapshot[I].Bitmap.Empty, True)]));
      {$ENDIF}
      FFrameView.SetFrame(Snapshot[I].Index, Snapshot[I].Bitmap);
    end
    else
    begin
      {$IFDEF DEBUG}FormLog(Format('  SetCellError[%d]', [Snapshot[I].Index]));{$ENDIF}
      FFrameView.SetCellError(Snapshot[I].Index);
    end;
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
  UpdateToolbarButtons;
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
  {$IFDEF DEBUG}FormLog(Format('WMExtractionDone: framesLoaded=%d total=%d', [FFramesLoaded, Length(FOffsets)]));{$ENDIF}
  { Safety net: process any frames that arrived after the last notification }
  ProcessPendingFrames;
  FProgressBar.Visible := False;
  FLblProgress.Visible := False;
  FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  {$IFDEF DEBUG}FormLog(Format('  hasPlaceholders=%s timerEnabled=%s',
    [BoolToStr(FFrameView.HasPlaceholders, True), BoolToStr(FAnimTimer.Enabled, True)]));{$ENDIF}
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
    Ord('R'):
      if Shift = [] then
      begin
        RefreshExtraction;
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
    VK_F2:
      begin
        ShowSettings;
        Key := 0;
      end;
    VK_F3:
      begin
        FStatusBar.Visible := not FStatusBar.Visible;
        FSettings.ShowStatusBar := FStatusBar.Visible;
        FSettings.Save;
        Key := 0;
      end;
    VK_F4:
      begin
        FToolbar.Visible := not FToolbar.Visible;
        FSettings.ShowToolbar := FToolbar.Visible;
        FSettings.Save;
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

procedure TPluginForm.SyncZoomMenuChecks(AMode: TViewMode; AZoom: TZoomMode);
var
  I: Integer;
begin
  if FModePopups[AMode] = nil then Exit;
  for I := 0 to FModePopups[AMode].Items.Count - 1 do
    FModePopups[AMode].Items[I].Checked :=
      TZoomMode(FModePopups[AMode].Items[I].Tag) = AZoom;
end;

procedure TPluginForm.UpdateTimecodeButton;
begin
  FBtnTimecode.Down := FFrameView.ShowTimecode;
end;

procedure TPluginForm.OnTimecodeButtonClick(Sender: TObject);
begin
  FFrameView.ShowTimecode := not FFrameView.ShowTimecode;
  UpdateTimecodeButton;
  UpdateFrameViewSize;
  FSettings.ShowTimecode := FFrameView.ShowTimecode;
  FSettings.Save;
end;

procedure TPluginForm.DispatchCommand(ATag: Integer);
begin
  case ATag of
    CM_SAVE_FRAME:    SaveSingleFrame;
    CM_SAVE_SELECTED: SaveSelectedFrames;
    CM_SAVE_COMBINED: SaveCombinedFrame;
    CM_SAVE_ALL:      SaveAllFrames;
    CM_COPY_FRAME:    CopyFrameToClipboard;
    CM_COPY_ALL:      CopyAllToClipboard;
    CM_SELECT_ALL:    FFrameView.SelectAll;
    CM_DESELECT_ALL:  FFrameView.DeselectAll;
    CM_REFRESH:       RefreshExtraction;
    CM_SETTINGS:      ShowSettings;
  end;
end;

procedure TPluginForm.OnToolbarButtonClick(Sender: TObject);
begin
  DispatchCommand(TButton(Sender).Tag);
end;

procedure TPluginForm.UpdateToolbarButtons;
var
  I: Integer;
  HasFrames: Boolean;
begin
  HasFrames := FFramesLoaded > 0;
  for I := 0 to High(FToolbarButtons) do
    case FToolbarButtons[I].Tag of
      CM_SETTINGS: FToolbarButtons[I].Enabled := True;
      else         FToolbarButtons[I].Enabled := HasFrames;
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
  LayoutToolbar;
  { VCL fires Resize during window creation, before CreateForPlugin finishes
    constructing sub-controls, so FFrameView may not exist yet }
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

  { Forward to TFrameView so wheel logic lives in one place (WMMouseWheel).
    Guards needed: VCL fires DoMouseWheel before constructor finishes. }
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
  { Same VCL lifecycle guard as Resize: FFrameView may not exist yet }
  if not FUpdatingLayout and Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
end;

procedure TPluginForm.OnContextMenuPopup(Sender: TObject);
var
  I, SelCount: Integer;
  MI: TMenuItem;
  Pt: TPoint;
  HasFrames, HasClickedFrame: Boolean;
begin
  HasFrames := FFrameView.CellCount > 0;

  { Hit-test: which cell was right-clicked? }
  Pt := FFrameView.ScreenToClient(FContextMenu.PopupPoint);
  FContextCellIndex := FFrameView.CellIndexAt(Pt);
  HasClickedFrame := (FContextCellIndex >= 0)
    and (FFrameView.CellState(FContextCellIndex) = fcsLoaded);

  for I := 0 to FContextMenu.Items.Count - 1 do
  begin
    MI := FContextMenu.Items[I];
    case MI.Tag of
      CM_SAVE_FRAME:    MI.Enabled := HasClickedFrame;
      CM_SAVE_COMBINED: MI.Enabled := HasFrames;
      CM_SAVE_ALL:      MI.Enabled := HasFrames;
      CM_COPY_FRAME:    MI.Enabled := HasClickedFrame;
      CM_COPY_ALL:      MI.Enabled := HasFrames;
      CM_SAVE_SELECTED:
        begin
          SelCount := FFrameView.SelectedCount;
          MI.Visible := SelCount >= 2;
          if MI.Visible then
            MI.Caption := Format('Save selected (%d)...', [SelCount]);
        end;
      CM_SELECT_ALL:    MI.Enabled := HasFrames;
      CM_DESELECT_ALL:  MI.Enabled := FFrameView.SelectedCount > 0;
      CM_REFRESH:       MI.Enabled := HasFrames;
      CM_SETTINGS:      ; { always enabled }
    end;
  end;
end;

procedure TPluginForm.OnContextMenuClick(Sender: TObject);
begin
  DispatchCommand(TMenuItem(Sender).Tag);
end;

procedure TPluginForm.OnAnimTimer(Sender: TObject);
begin
  { Drain any frames that arrived since the last notification.
    Covers the case where PostMessage notifications miss the HWND. }
  ProcessPendingFrames;
  { Timer fires during construction; FFrameView may not be ready yet }
  if Assigned(FFrameView) and FFrameView.Visible then
    FFrameView.AdvanceAnimation;
end;

procedure TPluginForm.OnFrameCountChange(Sender: TObject);
begin
  { VCL re-fires OnChange when a hidden TUpDown+TEdit pair becomes visible
    (handle recreation re-sends the position). Ignore if value unchanged. }
  if FUpDown.Position = FSettings.FramesCount then Exit;

  FSettings.FramesCount := FUpDown.Position;
  FSettings.Save;

  RefreshExtraction;
end;

procedure TPluginForm.ShowSettings;
var
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  Snap := TakeSettingsSnapshot(FSettings);

  if not ShowSettingsDialog(FSettings, FFFmpegPath) then
    Exit;

  FSettings.Save;
  ApplySettings;

  Changes := DetectSettingsChanges(Snap, FSettings);

  { Recreate cache if cache settings changed }
  if scCacheChanged in Changes then
  begin
    if FSettings.CacheEnabled then
      FCache := TFrameCache.Create(EffectiveCacheFolder(FSettings.CacheFolder), FSettings.CacheMaxSizeMB)
    else
      FCache := TNullFrameCache.Create;
  end;

  { FFmpeg path changed: update and reload from scratch (LoadFile re-probes
    the video, which is needed when ffmpeg was previously missing) }
  if (scFFmpegPathChanged in Changes) and (FSettings.FFmpegExePath <> '') then
  begin
    FFFmpegPath := FSettings.FFmpegExePath;
    LoadFile(FFileName);
    Exit;
  end;

  { Re-extract if skip edges changed }
  if scSkipEdgesChanged in Changes then
    RefreshExtraction;
end;

procedure TPluginForm.RefreshExtraction;
begin
  if not FVideoInfo.IsValid then Exit;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  SetupPlaceholders;
  StartExtraction(TBypassFrameCache.Create(FCache));
end;

end.
