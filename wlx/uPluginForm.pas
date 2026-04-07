{ Main plugin form: toolbar, frame display, and extraction coordination.
  The form is parented to TC's Lister window. }
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Clipbrd, Vcl.Buttons,
  uTypes, uSettings, uFrameOffsets, uFFmpegExe, uCache, uWlxAPI,
  uZoomController, uViewModeLogic,
  uExtractionPlanner, uToolbarLayout, uFrameView, uExtractionWorker,
  uFrameExtractor, uFrameExport, uExtractionController, uProbeCache;

type
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
    FProgressVisible: Boolean;
    { Per-element right pixel edges for collapse threshold checks }
    FFrameCountRight: Integer;
    FElementRights: array of Integer;
    FVisibleElementCount: Integer;
    { Status bar }
    FStatusBar: TStatusBar;
    { Content }
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    { Export }
    FExporter: TFrameExporter;
    { Extraction }
    FExtractCtrl: TExtractionController;
    FProbeCache: TProbeCache;
    { Animation }
    FAnimTimer: TTimer;
    { Layout guard: prevents re-entrant UpdateFrameViewSize during zoom }
    FUpdatingLayout: Boolean;
    { Prevents key-triggered reopen while Popup is still returning }
    FHamburgerMenuOpen: Boolean;
    { Suppresses WM_CHAR after OnKeyDown consumed the keystroke }
    FKeyConsumed: Boolean;
    { Tick count when LoadFile started (for load time measurement) }
    FLoadStartTick: UInt64;
    { Formatted load time string, populated when extraction completes }
    FLoadTimeStr: string;

    procedure CreateToolbar;
    procedure LayoutToolbar;
    procedure OnHamburgerClick(Sender: TObject);
    procedure OnHamburgerMenuPopup(Sender: TObject);
    procedure OnHamburgerModeClick(Sender: TObject);
    procedure OnHamburgerZoomClick(Sender: TObject);
    procedure OnHamburgerTimecodeClick(Sender: TObject);
    procedure OnHamburgerActionClick(Sender: TObject);
    procedure CreateFrameView;
    procedure OnFrameViewCtrlWheel(Sender: TObject; AWheelDelta: Integer);
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
    procedure ShowSettings;
    procedure NavigateToAdjacentFile(ADelta: Integer);
    procedure RefreshExtraction;
    procedure StartExtraction(const ACacheOverride: IFrameCache = nil);
    procedure OnFrameDelivered(AIndex: Integer; ABitmap: TBitmap);
    procedure OnExtractionProgress(Sender: TObject);
    procedure UpdateProgress;
    procedure ShowProgress(const AText: string);
    procedure HideProgress;
    procedure FinalizeLoadTime;
    procedure RepositionProgressBar;
    procedure OnAnimTimer(Sender: TObject);
    procedure OnFrameCountChange(Sender: TObject);
    procedure OnModeButtonClick(Sender: TObject);
    procedure OnSizingMenuClick(Sender: TObject);
    procedure OnTimecodeButtonClick(Sender: TObject);
    procedure OnScrollBoxResize(Sender: TObject);
    procedure OnContextMenuPopup(Sender: TObject);
    procedure OnContextMenuClick(Sender: TObject);
    procedure OnFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure OnFormKeyPress(Sender: TObject; var Key: Char);
    procedure WMFrameReady(var Message: TMessage); message WM_FRAME_READY;
    procedure WMExtractionDone(var Message: TMessage); message WM_EXTRACTION_DONE;
    procedure CMDialogKey(var Message: TWMKey); message CM_DIALOGKEY;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
  protected
    procedure WndProc(var Message: TMessage); override;
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
  System.IOUtils,
  uSettingsDlg, uFileNavigator, uDebugLog, uPathExpand, uCombinedImage;

procedure FormLog(const AMsg: string);
begin
  DebugLog('Form', AMsg);
end;

{ Closes the active menu on the calling thread }
function EndMenu: BOOL; stdcall; external user32 name 'EndMenu';

var
  { Thread-local keyboard hook handle, active only during hamburger popup }
  GMenuHook: HHOOK;

{ Intercepts VK_OEM_3 (tilde) during popup menu's modal loop to close it }
function MenuKeyboardProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  if (nCode = HC_ACTION) and (wParam = VK_OEM_3) and (lParam and (1 shl 31) = 0) then
  begin
    EndMenu;
    Result := 1;
  end
  else
    Result := CallNextHookEx(GMenuHook, nCode, wParam, lParam);
end;

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
  { Deferred self-subclass: installed after TC subclasses us so we fire first }
  FORM_SUBCLASS_ID = 2;
  WM_DEFERRED_INIT = WM_USER + 102; { Triggers self-subclass installation }
  WM_PLUGIN_FKEY   = WM_USER + 103; { Re-posted F-key intercepted from TC }

{ Self-subclass callback on the plugin form window.
  Installed AFTER TC subclasses us (via deferred PostMessage), so it fires
  first in the chain. Intercepts bare F2/F3 before TC can consume them. }
function FormSubclassProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM;
  lParam: LPARAM; uIdSubclass: UINT_PTR;
  dwRefData: DWORD_PTR): LRESULT; stdcall;
begin
  case uMsg of
    WM_KEYDOWN:
      if ((wParam = VK_F2) or (wParam = VK_F3)) and
         (GetKeyState(VK_CONTROL) >= 0) and
         (GetKeyState(VK_SHIFT) >= 0) and
         (GetKeyState(VK_MENU) >= 0) then
      begin
        { Bare F2/F3: re-post as custom message so our WndProc handles it
          instead of TC treating F2 as refresh and F3 as find. }
        PostMessage(hWnd, WM_PLUGIN_FKEY, wParam, 0);
        Result := 0;
        Exit;
      end;
    WM_NCDESTROY:
      RemoveWindowSubclass(hWnd, @FormSubclassProc, FORM_SUBCLASS_ID);
  end;
  Result := DefSubclassProc(hWnd, uMsg, wParam, lParam);
end;

const
  CLR_ERROR_LABEL      = TColor($00888888); { error message label }
  FONT_ERROR_LABEL  = 11;

  { UI layout }
  ANIM_INTERVAL_MS    = 80;   { placeholder spinner animation tick }
  MAX_FRAME_COUNT     = 99;   { upper limit for frame count spin edit }
  FRAME_COUNT_EDIT_W  = 40;   { width of the frame count edit control }
  STATUSBAR_HEIGHT    = 21;
  STATUSBAR_FONT      = 9;
  PROGRESSBAR_H       = 14;   { desired height of the embedded progress bar }
  PROGRESSBAR_MIN_W   = 40;   { minimum width before clamping }

  { Status bar panel widths }
  SBP_RESOLUTION_W = 120;
  SBP_FRAMERATE_W  = 100;
  SBP_DURATION_W   = 100;
  SBP_BITRATE_W    = 100;
  SBP_VIDEOCODEC_W = 90;
  SBP_AUDIO_W      = 300;
  SBP_NOAUDIO_W    = 110;
  SBP_LOADTIME_W   = 110;
  { Total width including per-panel borders added by the common control }
  SBP_TOTAL_RIGHT  = 1000;

  { Command tags, mode captions, sizing labels, and toolbar actions
    are defined in uToolbarLayout }

{ TPluginForm }

procedure TPluginForm.OnFrameViewCtrlWheel(Sender: TObject; AWheelDelta: Integer);
begin
  if AWheelDelta > 0 then
    ZoomBy(ZOOM_IN_FACTOR)
  else
    ZoomBy(ZOOM_OUT_FACTOR);
end;

constructor TPluginForm.CreateForPlugin(AParentWin: HWND; const AFileName: string;
  ASettings: TPluginSettings; const AFFmpegPath: string);
var
  R: TRect;
begin
  CreateNew(nil);
  BorderStyle := bsNone;
  KeyPreview := True;
  OnKeyDown := OnFormKeyDown;
  OnKeyPress := OnFormKeyPress;

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
  { Focus the form handle so TC recognises N/P as Lister shortcuts.
    Rapid N/P may lose focus due to TC briefly focusing its file list. }
  Winapi.Windows.SetFocus(Handle);
  { Install self-subclass AFTER TC subclasses us (which happens when ListLoad
    returns). PostMessage defers execution until the message loop resumes,
    guaranteeing TC's subclass is already in place. Our subclass then fires
    first and can intercept keys TC would otherwise consume (F2/F3). }
  PostMessage(Handle, WM_DEFERRED_INIT, 0, 0);

  {$IFDEF DEBUG}
  uDebugLog.GDebugLogPath := ExtractFilePath(FSettings.IniPath) + 'glimpse_debug.log';
  {$ENDIF}
  FormLog(Format('CreateForPlugin: file=%s handle=$%s', [AFileName, IntToHex(Handle)]));

  FProbeCache := TProbeCache.Create(DefaultProbeCacheDir);

  { Create extraction controller with appropriate cache }
  if FSettings.CacheEnabled then
    FExtractCtrl := TExtractionController.Create(Handle,
      TFrameCache.Create(EffectiveCacheFolder(FSettings.CacheFolder),
        FSettings.CacheMaxSizeMB))
  else
    FExtractCtrl := TExtractionController.Create(Handle,
      TNullFrameCache.Create);
  FExtractCtrl.OnFrameDelivered := OnFrameDelivered;
  FExtractCtrl.OnProgress := OnExtractionProgress;

  FExporter := TFrameExporter.Create(FFrameView, FSettings);

  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := ANIM_INTERVAL_MS;
  FAnimTimer.OnTimer := OnAnimTimer;
  FAnimTimer.Enabled := True;

  LoadFile(AFileName);
end;

destructor TPluginForm.Destroy;
begin
  if HandleAllocated then
    RemoveWindowSubclass(Handle, @FormSubclassProc, FORM_SUBCLASS_ID);
  if FParentWnd <> 0 then
    RemoveWindowSubclass(FParentWnd, @ParentSubclassProc, 1);
  { FAnimTimer may not exist yet if destructor runs during CreateForPlugin
    (VCL can destroy a windowed control before the constructor finishes) }
  if Assigned(FAnimTimer) then
    FAnimTimer.Enabled := False;
  FExtractCtrl.Free;
  FProbeCache.Free;
  if Assigned(FFrameView) then
    FFrameView.ClearCells;
  FExporter.Free;
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
  FEditFrameCount.Width := FRAME_COUNT_EDIT_W;
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

  FEditFrameCount.SetBounds(X, CY, FRAME_COUNT_EDIT_W, CtrlH);

  FUpDown := TUpDown.Create(FToolbar);
  FUpDown.Parent := FToolbar;
  FUpDown.Associate := FEditFrameCount;
  FUpDown.Min := 1;
  FUpDown.Max := MAX_FRAME_COUNT;
  Inc(X, FRAME_COUNT_EDIT_W + FUpDown.Width + CTRL_GAP);
  FFrameCountRight := X;

  { Collapsible elements: modes, timecodes, actions (left to right) }
  SetLength(FElementRights, ELEM_TOTAL_COUNT);

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

    FElementRights[Ord(VM)] := X + BW;
    Inc(TabIdx);
    if VM < High(TViewMode) then
      Inc(X, BW + BTN_GAP)
    else
      Inc(X, BW + CTRL_GAP);
  end;

  FBtnTimecode := TSpeedButton.Create(FToolbar);
  FBtnTimecode.Parent := FToolbar;
  BW := Canvas.TextWidth('Timecodes') + BTN_PAD;
  FBtnTimecode.SetBounds(X, CY, BW, CtrlH);
  FBtnTimecode.Caption := 'Timecodes';
  FBtnTimecode.GroupIndex := 1;
  FBtnTimecode.AllowAllUp := True;
  FBtnTimecode.OnClick := OnTimecodeButtonClick;
  FElementRights[ELEM_TIMECODE_INDEX] := X + BW;
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
    FElementRights[ELEM_ACTION_FIRST + I] := X + BW;
    Inc(X, BW + BTN_GAP);
    SetLength(FToolbarButtons, Length(FToolbarButtons) + 1);
    FToolbarButtons[High(FToolbarButtons)] := Btn;
  end;

  { Hamburger overflow button: hidden until toolbar is too narrow }
  FHamburgerMenu := TPopupMenu.Create(Self);
  FHamburgerMenu.OnPopup := OnHamburgerMenuPopup;

  FBtnHamburger := TButton.Create(FToolbar);
  FBtnHamburger.Parent := FToolbar;
  BW := Canvas.TextWidth(#$2261) + BTN_PAD;
  FBtnHamburger.SetBounds(0, CY, BW, CtrlH);
  FBtnHamburger.Caption := #$2261;
  FBtnHamburger.OnClick := OnHamburgerClick;
  FBtnHamburger.Visible := False;
end;

procedure TPluginForm.LayoutToolbar;
const
  CTRL_GAP = 8;
var
  Layout: TToolbarLayoutResult;
  VM: TViewMode;
  I: Integer;
begin
  if not Assigned(FBtnHamburger) then Exit;

  Layout := ComputeToolbarLayout(FToolbar.ClientWidth, FElementRights,
    FFrameCountRight, FBtnHamburger.Width, CTRL_GAP);
  FVisibleElementCount := Layout.VisibleCount;

  { Per-button visibility based on element index }
  for VM := Low(TViewMode) to High(TViewMode) do
    FModeButtons[VM].Visible := Ord(VM) < Layout.VisibleCount;

  FBtnTimecode.Visible := ELEM_TIMECODE_INDEX < Layout.VisibleCount;

  for I := 0 to High(FToolbarButtons) do
    FToolbarButtons[I].Visible := (ELEM_ACTION_FIRST + I) < Layout.VisibleCount;

  { Hamburger button }
  FBtnHamburger.Visible := Layout.HamburgerVisible;
  FBtnHamburger.Left := Layout.HamburgerLeft;
end;

procedure TPluginForm.OnHamburgerClick(Sender: TObject);
var
  P: TPoint;
begin
  if FHamburgerMenuOpen then Exit;
  FHamburgerMenuOpen := True;
  GMenuHook := SetWindowsHookEx(WH_KEYBOARD, @MenuKeyboardProc, 0, GetCurrentThreadId);
  try
    P := FBtnHamburger.ClientToScreen(Point(0, FBtnHamburger.Height));
    FHamburgerMenu.Popup(P.X, P.Y);
  finally
    if GMenuHook <> 0 then
      UnhookWindowsHookEx(GMenuHook);
    GMenuHook := 0;
    FHamburgerMenuOpen := False;
  end;
end;

procedure TPluginForm.OnHamburgerMenuPopup(Sender: TObject);
var
  State: THamburgerMenuState;
  VM: TViewMode;
begin
  State.VisibleCount := FVisibleElementCount;
  State.ActiveMode := FFrameView.ViewMode;
  State.ShowTimecode := FFrameView.ShowTimecode;
  State.HasFrames := FExtractCtrl.FramesLoaded > 0;
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
  FFrameView.OnCtrlWheel := OnFrameViewCtrlWheel;
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
  FLblError.Font.Size := FONT_ERROR_LABEL;
  FLblError.Font.Color := CLR_ERROR_LABEL;
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

  FProgressBar := TProgressBar.Create(FStatusBar);
  FProgressBar.Parent := FStatusBar;
  FProgressBar.Visible := False;
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

  procedure AddPanel(const AText: string; AWidth: Integer;
    AAlignment: TAlignment = taLeftJustify);
  var
    Panel: TStatusPanel;
  begin
    Panel := FStatusBar.Panels.Add;
    Panel.Text := AText;
    Panel.Width := AWidth;
    Panel.Alignment := AAlignment;
  end;

var
  AudioStr: string;
begin
  FStatusBar.Panels.Clear;

  if not FVideoInfo.IsValid then
    Exit;

  { Resolution }
  if (FVideoInfo.Width > 0) and (FVideoInfo.Height > 0) then
    AddPanel(Format('%dx%d', [FVideoInfo.Width, FVideoInfo.Height]), SBP_RESOLUTION_W);

  { Framerate }
  if FVideoInfo.Fps > 0 then
    AddPanel(Format('%.4g fps', [FVideoInfo.Fps]), SBP_FRAMERATE_W);

  { Duration }
  if FVideoInfo.Duration > 0 then
    AddPanel(FormatDuration(FVideoInfo.Duration), SBP_DURATION_W);

  { Overall bitrate }
  if FVideoInfo.Bitrate > 0 then
    AddPanel(FormatBitrate(FVideoInfo.Bitrate), SBP_BITRATE_W);

  { Video codec }
  if FVideoInfo.VideoCodec <> '' then
    AddPanel(FVideoInfo.VideoCodec, SBP_VIDEOCODEC_W);

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
    AddPanel(AudioStr, SBP_AUDIO_W);
  end
  else
    AddPanel('No audio', SBP_NOAUDIO_W);

  { Load time (shown after extraction completes) }
  if FLoadTimeStr <> '' then
  begin
    AddPanel(FLoadTimeStr, SBP_LOADTIME_W, taRightJustify);
    { Dummy panel absorbs last-panel stretching from the common control }
    AddPanel('', 0);
  end;
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
  FFrameView.TimestampFontName := FSettings.TimestampFontName;
  FFrameView.TimestampFontSize := FSettings.TimestampFontSize;
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
begin
  FExporter.CopyFrameToClipboard(FContextCellIndex);
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


procedure TPluginForm.LoadFile(const AFileName: string);
var
  FFmpeg: TFFmpegExe;
begin
  FormLog(Format('LoadFile: %s', [AFileName]));
  FLoadStartTick := GetTickCount64;
  FLoadTimeStr := '';
  FFileName := AFileName;
  SetWindowText(FParentWnd, PChar(Format('Lister (glimpse) - [%s]', [AFileName])));
  FExtractCtrl.Stop;
  FExtractCtrl.DrainPendingFrameMessages;
  FFrameView.ClearCells;
  FVideoInfo := Default(TVideoInfo);

  if FFFmpegPath = '' then
  begin
    ShowError('ffmpeg not found.'#13#10'Press F2 to configure.');
    Exit;
  end;

  { Try cached probe first; fall back to ffmpeg on miss }
  if not FProbeCache.TryGet(FFileName, FVideoInfo) then
  begin
    FFmpeg := TFFmpegExe.Create(FFFmpegPath);
    try
      FVideoInfo := FFmpeg.ProbeVideo(FFileName);
    finally
      FFmpeg.Free;
    end;
    FProbeCache.Put(FFileName, FVideoInfo);
  end;

  { Update banner info for combined image export }
  var BI: TBannerInfo := Default(TBannerInfo);
  BI.FileName := FFileName;
  if TFile.Exists(FFileName) then
    BI.FileSizeBytes := TFile.GetSize(FFileName);
  BI.DurationSec := FVideoInfo.Duration;
  BI.Width := FVideoInfo.Width;
  BI.Height := FVideoInfo.Height;
  BI.VideoCodec := FVideoInfo.VideoCodec;
  BI.VideoBitrateKbps := FVideoInfo.VideoBitrateKbps;
  BI.Fps := FVideoInfo.Fps;
  BI.AudioCodec := FVideoInfo.AudioCodec;
  BI.AudioSampleRate := FVideoInfo.AudioSampleRate;
  BI.AudioChannels := FVideoInfo.AudioChannels;
  BI.AudioBitrateKbps := FVideoInfo.AudioBitrateKbps;
  FExporter.UpdateBannerInfo(BI);

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
  Extractor: IFrameExtractor;
  MaxSide: Integer;
begin
  FExtractCtrl.Stop;
  FLoadStartTick := GetTickCount64;
  FLoadTimeStr := '';
  UpdateToolbarButtons;

  FProgressBar.Style := pbstMarquee;
  ShowProgress('Extracting...');
  FAnimTimer.Enabled := True;

  MaxSide := 0;
  if FSettings.ScaledExtraction then
    MaxSide := CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight,
      Length(FOffsets), FFrameView.AspectRatio,
      FVideoInfo.Width, FVideoInfo.Height,
      FSettings.MinFrameSide, FSettings.MaxFrameSide);

  Extractor := TFFmpegFrameExtractor.Create(FFFmpegPath);
  FExtractCtrl.Start(Extractor, FFileName, FOffsets,
    FSettings.MaxWorkers, FSettings.MaxThreads, FSettings.UseBmpPipe,
    MaxSide, FSettings.HwAccel, ACacheOverride);
end;

procedure TPluginForm.OnFrameDelivered(AIndex: Integer; ABitmap: TBitmap);
begin
  if ABitmap <> nil then
    FFrameView.SetFrame(AIndex, ABitmap)
  else
    FFrameView.SetCellError(AIndex);
end;

procedure TPluginForm.OnExtractionProgress(Sender: TObject);
begin
  UpdateProgress;
end;

procedure TPluginForm.ShowProgress(const AText: string);
begin
  FStatusBar.Visible := True;
  FProgressVisible := True;
  RepositionProgressBar;
  FProgressBar.Visible := True;
end;

procedure TPluginForm.HideProgress;
begin
  FProgressBar.Visible := False;
  FProgressVisible := False;
  FStatusBar.Visible := FSettings.ShowStatusBar;
end;

procedure TPluginForm.FinalizeLoadTime;
var
  ElapsedMs: UInt64;
  H, M, S, Ms: Integer;
begin
  if FLoadStartTick = 0 then Exit;
  if FLoadTimeStr <> '' then Exit; { already finalized }

  ElapsedMs := GetTickCount64 - FLoadStartTick;
  H := ElapsedMs div 3600000;
  M := (ElapsedMs mod 3600000) div 60000;
  S := (ElapsedMs mod 60000) div 1000;
  Ms := ElapsedMs mod 1000;

  if H > 0 then
    FLoadTimeStr := Format('%d:%.2d:%.2d', [H, M, S])
  else if M > 0 then
    FLoadTimeStr := Format('%d:%.2d.%.3d', [M, S, Ms])
  else
    FLoadTimeStr := Format('%d.%.3d s', [S, Ms]);

  UpdateStatusBar;
end;

procedure TPluginForm.RepositionProgressBar;
var
  Margin, BarWidth: Integer;
begin
  if not FProgressVisible then Exit;
  Margin := (FStatusBar.ClientHeight - PROGRESSBAR_H) div 2;
  BarWidth := FStatusBar.ClientWidth - SBP_TOTAL_RIGHT - 2 * Margin;
  if BarWidth < PROGRESSBAR_MIN_W then
    BarWidth := PROGRESSBAR_MIN_W;
  FProgressBar.SetBounds(SBP_TOTAL_RIGHT + Margin, Margin, BarWidth, FStatusBar.ClientHeight - 2 * Margin);
end;

procedure TPluginForm.UpdateProgress;
begin
  UpdateToolbarButtons;
  if FExtractCtrl.FramesLoaded >= FExtractCtrl.TotalFrames then
  begin
    FinalizeLoadTime;
    HideProgress;
    FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  end
  else if (FExtractCtrl.FramesLoaded > 0) and FProgressVisible then
  begin
    FProgressBar.Style := pbstNormal;
    FProgressBar.Max := FExtractCtrl.TotalFrames;
    FProgressBar.Position := FExtractCtrl.FramesLoaded;
  end;
end;

procedure TPluginForm.WMFrameReady(var Message: TMessage);
begin
  FExtractCtrl.ProcessPendingFrames;
end;

procedure TPluginForm.WMExtractionDone(var Message: TMessage);
begin
  FormLog(Format('WMExtractionDone: framesLoaded=%d total=%d',
    [FExtractCtrl.FramesLoaded, FExtractCtrl.TotalFrames]));
  { Safety net: process any frames that arrived after the last notification }
  FExtractCtrl.ProcessPendingFrames;
  FinalizeLoadTime;
  HideProgress;
  FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  FormLog(Format('  hasPlaceholders=%s timerEnabled=%s',
    [BoolToStr(FFrameView.HasPlaceholders, True), BoolToStr(FAnimTimer.Enabled, True)]));
end;

procedure TPluginForm.OnFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  FKeyConsumed := False;

  { Ctrl+Up/Down: adjust frame count }
  if (ssCtrl in Shift) and (Key in [VK_UP, VK_DOWN]) then
  begin
    if Key = VK_UP then
      FUpDown.Position := FUpDown.Position + 1
    else
      FUpDown.Position := FUpDown.Position - 1;
    Key := 0;
    FKeyConsumed := True;
    Exit;
  end;

  { Ctrl+Left/Right: navigate frames in single mode }
  if (Shift = [ssCtrl]) and (Key in [VK_LEFT, VK_RIGHT]) and
     (FFrameView.ViewMode = vmSingle) then
  begin
    if Key = VK_LEFT then
      FFrameView.NavigateFrame(-1)
    else
      FFrameView.NavigateFrame(1);
    Key := 0;
    FKeyConsumed := True;
    Exit;
  end;

  { Bare Left/Right/PageUp/PageDown: navigate between files }
  if (Shift = []) and (Key in [VK_LEFT, VK_RIGHT, VK_PRIOR, VK_NEXT]) then
  begin
    if Key in [VK_LEFT, VK_PRIOR] then
      NavigateToAdjacentFile(-1)
    else
      NavigateToAdjacentFile(1);
    Key := 0;
    FKeyConsumed := True;
    Exit;
  end;

  case Key of
    Ord('C'):
      if ssCtrl in Shift then
      begin
        if ssShift in Shift then
          FExporter.CopyAllToClipboard
        else
          CopyFrameToClipboard;
        Key := 0;
      end;
    Ord('S'):
      if ssCtrl in Shift then
      begin
        if [ssShift, ssAlt] * Shift = [ssAlt] then
        begin
          FExporter.SaveAllFrames(FFileName);
          Key := 0;
        end
        else if [ssShift, ssAlt] * Shift = [ssShift] then
        begin
          FExporter.SaveCombinedFrame(FFileName);
          Key := 0;
        end
        else if [ssShift, ssAlt] * Shift = [] then
        begin
          FContextCellIndex := -1;
          FExporter.SaveSingleFrame(FFileName, FContextCellIndex);
          Key := 0;
        end;
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
    Ord('T'):
      if Shift = [] then
      begin
        OnTimecodeButtonClick(nil);
        Key := 0;
      end;
    Ord('Z'):
      if Shift = [] then
      begin
        NavigateToAdjacentFile(-1);
        Key := 0;
      end;
    VK_SPACE:
      if Shift = [] then
      begin
        NavigateToAdjacentFile(1);
        Key := 0;
      end;
    VK_BACK:
      if Shift = [] then
      begin
        NavigateToAdjacentFile(-1);
        Key := 0;
      end;
    VK_TAB:
      if Shift - [ssShift] = [] then
      begin
        SelectNext(ActiveControl, not (ssShift in Shift), True);
        Key := 0;
      end;
    VK_ESCAPE:
      if Shift = [] then
      begin
        PostMessage(GetParent(Handle), WM_KEYDOWN, VK_ESCAPE, 0);
        PostMessage(GetParent(Handle), WM_KEYUP, VK_ESCAPE, 0);
        Key := 0;
      end;
    VK_OEM_PLUS, VK_ADD:
      if Shift = [] then
      begin
        ZoomBy(ZOOM_IN_FACTOR);
        Key := 0;
      end;
    VK_OEM_MINUS, VK_SUBTRACT:
      if Shift = [] then
      begin
        ZoomBy(ZOOM_OUT_FACTOR);
        Key := 0;
      end;
    Ord('0'), VK_NUMPAD0:
      if Shift = [] then
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
      if Shift = [] then
      begin
        ShowSettings;
        Key := 0;
      end;
    VK_F3:
      if Shift = [] then
      begin
        FStatusBar.Visible := not FStatusBar.Visible;
        FSettings.ShowStatusBar := FStatusBar.Visible;
        FSettings.Save;
        Key := 0;
      end;
    VK_F4:
      if Shift = [] then
      begin
        FToolbar.Visible := not FToolbar.Visible;
        { Reclaim focus so TC's subclass sees keystrokes again }
        if not FToolbar.Visible then
          Winapi.Windows.SetFocus(Handle);
        FSettings.ShowToolbar := FToolbar.Visible;
        FSettings.Save;
        Key := 0;
      end;
    VK_OEM_3: { ~ / ` key }
      if (Shift = []) and FBtnHamburger.Visible then
      begin
        OnHamburgerClick(FBtnHamburger);
        Key := 0;
      end;
  end;

  { When the frame count edit has Win32 focus and the key was not consumed by
    a hotkey above, only allow digit-editing and modifier keys through.
    Non-digit keys reclaim form focus so TC's subclass sees subsequent
    keystrokes. The current keystroke is consumed (not re-posted) to avoid
    corrupting keyboard state with unmatched WM_KEYDOWN messages. }
  if (Key <> 0) and (GetFocus = FEditFrameCount.Handle) then
    case Key of
      Ord('0')..Ord('9'), VK_NUMPAD0..VK_NUMPAD9,
      VK_BACK, VK_DELETE, VK_LEFT, VK_RIGHT, VK_HOME, VK_END,
      VK_UP, VK_DOWN,
      VK_SHIFT, VK_CONTROL, VK_MENU:
        ; { Allow through to the edit / UpDown / modifier state }
      VK_RETURN:
        begin
          Winapi.Windows.SetFocus(Handle);
          Key := 0;
        end;
    else
      Winapi.Windows.SetFocus(Handle);
      Key := 0;
    end;

  if Key = 0 then
    FKeyConsumed := True;
end;

procedure TPluginForm.OnFormKeyPress(Sender: TObject; var Key: Char);
begin
  if FKeyConsumed then
  begin
    Key := #0;
    FKeyConsumed := False;
  end
  { Suppress non-digit chars that slip through OnKeyDown (e.g. Shift+digit
    produces '!' etc.). Prevents the NumbersOnly balloon on the edit. }
  else if (GetFocus = FEditFrameCount.Handle) and not CharInSet(Key, ['0'..'9', #8]) then
    Key := #0;
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

procedure TPluginForm.WMSetFocus(var Message: TWMSetFocus);
begin
  { Do NOT call inherited. VCL's default WMSetFocus redirects focus to
    ActiveControl (a child). TC subclasses this window to catch N/P and
    other Lister hotkeys; that subclass only sees WM_KEYDOWN when THIS
    window has Win32 focus, not a child. Skipping inherited keeps focus
    on the form handle so TC's hotkey interception works. }
end;

procedure TPluginForm.ShowError(const AMessage: string);
begin
  FFrameView.Visible := False;
  FLblError.Caption := AMessage;
  FLblError.Visible := True;
  FAnimTimer.Enabled := False;
  HideProgress;
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
    CM_SAVE_FRAME:    FExporter.SaveSingleFrame(FFileName, FContextCellIndex);
    CM_SAVE_SELECTED: FExporter.SaveSelectedFrames(FFileName);
    CM_SAVE_COMBINED: FExporter.SaveCombinedFrame(FFileName);
    CM_SAVE_ALL:      FExporter.SaveAllFrames(FFileName);
    CM_COPY_FRAME:    FExporter.CopyFrameToClipboard(FContextCellIndex);
    CM_COPY_ALL:      FExporter.CopyAllToClipboard;
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
  HasFrames := Assigned(FExtractCtrl) and (FExtractCtrl.FramesLoaded > 0);
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

procedure TPluginForm.WndProc(var Message: TMessage);
var
  Key: Word;
begin
  case Message.Msg of
    WM_DEFERRED_INIT:
      begin
        SetWindowSubclass(Handle, @FormSubclassProc, FORM_SUBCLASS_ID, DWORD_PTR(Self));
        Exit;
      end;
    WM_PLUGIN_FKEY:
      begin
        Key := Message.WParam;
        OnFormKeyDown(Self, Key, []);
        Exit;
      end;
  end;
  inherited;
  if csDestroying in ComponentState then
    Exit;
  { When any child control is clicked, reclaim focus for the form handle.
    TC subclasses this window to catch Lister hotkeys (N/P etc.); that
    subclass only sees WM_KEYDOWN when this window has Win32 focus. }
  if Message.Msg = WM_PARENTNOTIFY then
    case LOWORD(Message.WParam) of
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
        Winapi.Windows.SetFocus(Handle);
    end;
end;

procedure TPluginForm.Resize;
begin
  inherited;
  Realign;
  LayoutToolbar;
  RepositionProgressBar;
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
  if Assigned(FExtractCtrl) then
    FExtractCtrl.ProcessPendingFrames;
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
    FExtractCtrl.RecreateCache(FSettings.CacheEnabled,
      FSettings.CacheFolder, FSettings.CacheMaxSizeMB);

  { FFmpeg path changed: update and reload from scratch (LoadFile re-probes
    the video, which is needed when ffmpeg was previously missing) }
  if (scFFmpegPathChanged in Changes) and (FSettings.FFmpegExePath <> '') then
  begin
    FFFmpegPath := ExpandEnvVars(FSettings.FFmpegExePath);
    LoadFile(FFileName);
    Exit;
  end;

  { Re-extract if skip edges or scaled extraction settings changed }
  if (Changes * [scSkipEdgesChanged, scScaledExtractionChanged]) <> [] then
    RefreshExtraction;
end;

procedure TPluginForm.NavigateToAdjacentFile(ADelta: Integer);
var
  Next: string;
begin
  Next := FindAdjacentFile(FFileName, FSettings.ExtensionList, ADelta);
  if (Next <> '') and not SameText(Next, FFileName) then
    LoadFile(Next);
end;

procedure TPluginForm.RefreshExtraction;
begin
  if not FVideoInfo.IsValid then Exit;
  FExtractCtrl.Stop;
  FExtractCtrl.DrainPendingFrameMessages;
  FFrameView.ClearCells;
  SetupPlaceholders;
  StartExtraction(TBypassFrameCache.Create(FExtractCtrl.Cache));
end;

end.
