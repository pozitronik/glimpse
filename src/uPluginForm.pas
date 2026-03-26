/// Main plugin form, frame view control, and extraction worker thread.
/// The form is parented to TC's Lister window and hosts the toolbar and frame display.
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus,
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
    FSmartRows: TArray<TSmartRow>;
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
  public
    FCells: TArray<TFrameCell>;
    constructor Create(AOwner: TComponent); override;
    function GetCellRect(AIndex: Integer): TRect;
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

    procedure CreateToolbar;
    procedure CreateFrameView;
    procedure CreateErrorLabel;
    function CreateModePopup(AMode: TViewMode): TPopupMenu;
    procedure ApplySettings;
    procedure SetupPlaceholders;
    procedure ShowError(const AMessage: string);
    procedure HideError;
    procedure UpdateFrameViewSize;
    procedure UpdateViewModeButtons;
    procedure ActivateMode(AMode: TViewMode);
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
end;

procedure TFrameView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

procedure TFrameView.WMMouseWheel(var Message: TWMMouseWheel);
begin
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
        Exit(Max(1, (ClientWidth - FCellGap) div (FNativeW + FCellGap)));
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
  AvailW := ClientWidth - (Cols + 1) * FCellGap;
  Result.cx := Max(1, AvailW div Cols);
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
  Cols, Col, Row: Integer;
  Sz: TSize;
  RowH, GridW, OffsetX: Integer;
begin
  Cols := GetColumnCount;
  Sz := GetCellImageSize;
  Col := AIndex mod Cols;
  Row := AIndex div Cols;
  RowH := Sz.cy + FTimecodeHeight + FCellGap;

  { Center grid horizontally when total grid width < client width }
  GridW := Cols * (Sz.cx + FCellGap) + FCellGap;
  if GridW < ClientWidth then
    OffsetX := (ClientWidth - GridW) div 2
  else
    OffsetX := 0;

  Result.Left   := OffsetX + FCellGap + Col * (Sz.cx + FCellGap);
  Result.Top    := FCellGap + Row * RowH;
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
        CellW := Max(1, ClientWidth - 2 * FCellGap);
        if (FNativeW > 0) and (FNativeW < CellW) then
          CellW := FNativeW;
        CellH := Max(1, Round(CellW * FAspectRatio));
      end;
  else { zmFitWindow }
    begin
      CellW := Max(1, ClientWidth - 2 * FCellGap);
      CellH := Max(1, Round(CellW * FAspectRatio));
    end;
  end;

  { Center horizontally when cell is narrower than viewport }
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
  AvailH := Max(1, FViewportH - FTimecodeHeight - 2 * FCellGap);

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

  CellW := Max(1, Round(CellH / FAspectRatio));

  { Center vertically when cell is shorter than available height }
  if CellH < AvailH then
    TopY := (FViewportH - CellH - FTimecodeHeight) div 2
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
  AvailW := Max(1, ClientWidth - 2 * FCellGap);
  AvailH := Max(1, ClientHeight - FTimecodeHeight - 2 * FCellGap);

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
          { Native size fits, use it directly }
          CellW := FNativeW;
          CellH := FNativeH;
        end
        else
        begin
          { Scale down to fit }
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

  { Center in viewport }
  Result.Left   := (ClientWidth - CellW) div 2;
  Result.Top    := FCellGap + (AvailH - CellH) div 2;
  Result.Right  := Result.Left + CellW;
  Result.Bottom := Result.Top + CellH;
end;

function TFrameView.GetCellRectSmartGrid(AIndex: Integer): TRect;
var
  RowIdx, CellInRow, RowTop, RowH, CellW, PrevCount: Integer;
begin
  if Length(FSmartRows) = 0 then
    Exit(Rect(0, 0, 1, 1));

  RowH := FViewportH div Length(FSmartRows);

  { Find which row this index belongs to }
  PrevCount := 0;
  for RowIdx := 0 to High(FSmartRows) do
  begin
    if AIndex < PrevCount + FSmartRows[RowIdx].Count then
    begin
      CellInRow := AIndex - PrevCount;
      CellW := FViewportW div Max(1, FSmartRows[RowIdx].Count);
      RowTop := RowIdx * RowH;

      { Last row/cell fills remaining space to avoid rounding gaps }
      Result.Left := CellInRow * CellW;
      if CellInRow = FSmartRows[RowIdx].Count - 1 then
        Result.Right := FViewportW
      else
        Result.Right := Result.Left + CellW;

      Result.Top := RowTop;
      if RowIdx = High(FSmartRows) then
        Result.Bottom := FViewportH
      else
        Result.Bottom := RowTop + RowH;

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
  if (N = 0) or (FViewportW <= 0) or (FViewportH <= 0) then
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
        DisplayedAR := (FViewportH / R) / (FViewportW / (Base + 1))
      else
        DisplayedAR := (FViewportH / R) / (FViewportW / Max(1, Base));
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
end;

procedure TFrameView.PaintPlaceholder(const ARect: TRect);
begin
  Canvas.Brush.Color := $002D2D2D;
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
  Canvas.Brush.Color := $002D2D2D;
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
  Radius := Min(ARect.Width, ARect.Height) div 8;
  if Radius < 5 then Exit;

  StartAngle := FAnimStep * 45.0;
  Canvas.Pen.Color := $00707070;
  Canvas.Pen.Width := 3;
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
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 8;

  if FViewMode = vmSmartGrid then
  begin
    { Semi-transparent overlay for smart grid }
    Canvas.Brush.Color := $002D2D2D;
    Canvas.Brush.Style := bsSolid;
    Canvas.FillRect(R);
    Canvas.Font.Color := $00CCCCCC;
  end
  else
  begin
    if FCells[AIndex].State = fcsLoaded then
      Canvas.Font.Color := $00AAAAAA
    else
      Canvas.Font.Color := $00555555;
  end;

  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(FCells[AIndex].Timecode), -1, R,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TFrameView.PaintErrorCell(const ARect: TRect);
var
  R: TRect;
begin
  Canvas.Brush.Color := $002D2D2D;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Color := $004040FF;
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
  Cols, Rows: Integer;
  Sz: TSize;
  CellH, CellW, N: Integer;
begin
  N := Length(FCells);
  if N = 0 then
  begin
    Height := FViewportH;
    Exit;
  end;

  case FViewMode of
    vmSmartGrid:
      begin
        CalcSmartGridLayout;
        Width := FViewportW;
        Height := FViewportH;
      end;
    vmSingle:
      begin
        Width := FViewportW;
        Height := FViewportH;
      end;
    vmFilmstrip:
      begin
        { Use the same zoom logic as GetCellRectFilmstrip }
        CellH := Max(1, FViewportH - FTimecodeHeight - 2 * FCellGap);
        case FZoomMode of
          zmActual:
            CellH := Max(1, FNativeH);
          zmFitIfLarger:
            if (FNativeH > 0) and (FNativeH < CellH) then
              CellH := FNativeH;
        end;
        CellW := Max(1, Round(CellH / FAspectRatio));
        Width := Max(FViewportW, FCellGap + N * (CellW + FCellGap));
        Height := Max(FViewportH, CellH + FTimecodeHeight + 2 * FCellGap);
      end;
    vmScroll:
      begin
        { Width: at least viewport wide (for centering), wider if native exceeds }
        case FZoomMode of
          zmActual:
            if FNativeW > 0 then
              Width := Max(FViewportW, FNativeW + 2 * FCellGap);
        else
          Width := FViewportW;
        end;
        { Height: at least viewport tall (for background fill), taller if content exceeds }
        if N > 0 then
        begin
          CellH := GetCellRectScroll(0).Height;
          Height := Max(FViewportH, FCellGap + N * (CellH + FTimecodeHeight + FCellGap));
        end;
      end;
  else
    begin
      Cols := GetColumnCount;
      Sz := GetCellImageSize;
      Rows := Ceil(N / Cols);
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

  Winapi.Windows.GetClientRect(AParentWin, R);
  SetBounds(0, 0, R.Right, R.Bottom);

  CreateToolbar;
  CreateFrameView;
  CreateErrorLabel;
  ApplySettings;

  { Wire OnChange after ApplySettings so initial Position assignment doesn't
    trigger a save that overwrites the loaded DefaultN }
  FEditFrameCount.OnChange := OnFrameCountChange;

  ParentWindow := AParentWin;
  FParentWnd := AParentWin;
  SetWindowSubclass(AParentWin, @ParentSubclassProc, 1, DWORD_PTR(Self));
  Visible := True;

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

  FUpDown.Position := FSettings.DefaultN;
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
begin
  { Configure scrollbox FIRST so ClientWidth/ClientHeight reflect scrollbar state }
  case FFrameView.ViewMode of
    vmScroll:
      begin
        FScrollBox.HorzScrollBar.Visible := FFrameView.ZoomMode = zmActual;
        FScrollBox.VertScrollBar.Visible := True;
      end;
    vmGrid:
      begin
        FScrollBox.HorzScrollBar.Visible := False;
        FScrollBox.VertScrollBar.Visible := True;
      end;
    vmSmartGrid, vmSingle:
      begin
        FScrollBox.HorzScrollBar.Visible := False;
        FScrollBox.VertScrollBar.Visible := False;
      end;
    vmFilmstrip:
      begin
        FScrollBox.HorzScrollBar.Visible := True;
        FScrollBox.VertScrollBar.Visible := FFrameView.ZoomMode = zmActual;
      end;
  end;

  { Read viewport after scrollbar config }
  VW := FScrollBox.ClientWidth;
  VH := FScrollBox.ClientHeight;
  FFrameView.SetViewport(VW, VH);

  { Calculate column count for grid mode }
  if FFrameView.ViewMode = vmGrid then
  begin
    case FFrameView.ZoomMode of
      zmFitWindow:
        FFrameView.ColumnCount := FFrameView.CalcFitColumns(VW, VH);
      zmFitIfLarger:
        begin
          FitCols := FFrameView.CalcFitColumns(VW, VH);
          DefCols := FFrameView.DefaultColumnCount;
          FFrameView.ColumnCount := Max(FitCols, DefCols);
        end;
    else
      FFrameView.ColumnCount := 0;
    end;
  end
  else
    FFrameView.ColumnCount := 0;

  { Set initial frame view dimensions; RecalcSize may adjust Width/Height }
  case FFrameView.ViewMode of
    vmSmartGrid, vmSingle:
      FFrameView.SetBounds(0, 0, VW, VH);
  else
    begin
      FFrameView.Left := 0;
      FFrameView.Top := 0;
      FFrameView.Width := VW;
    end;
  end;

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
  if Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
end;

function TPluginForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if Assigned(FScrollBox) and FScrollBox.Visible then
  begin
    case FFrameView.ViewMode of
      vmSingle:
        begin
          if WheelDelta > 0 then
            FFrameView.NavigateFrame(-1)
          else
            FFrameView.NavigateFrame(1);
          Result := True;
        end;
      vmFilmstrip:
        begin
          FScrollBox.HorzScrollBar.Position :=
            FScrollBox.HorzScrollBar.Position - WheelDelta;
          Result := True;
        end;
    else
      begin
        FScrollBox.VertScrollBar.Position :=
          FScrollBox.VertScrollBar.Position - WheelDelta;
        Result := True;
      end;
    end;
  end
  else
    Result := inherited;
end;

procedure TPluginForm.OnScrollBoxResize(Sender: TObject);
begin
  if Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
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
  FSettings.DefaultN := FUpDown.Position;
  FSettings.Save;

  if not FVideoInfo.IsValid then Exit;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  SetupPlaceholders;
  StartExtraction;
end;

end.
