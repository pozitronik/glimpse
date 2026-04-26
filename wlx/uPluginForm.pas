{Main plugin form: toolbar, frame display, and extraction coordination.
 The form is parented to TC's Lister window.}
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Clipbrd, Vcl.Buttons, Vcl.ImgList,
  uTypes, uSettings, uHotkeys, uFrameOffsets, uFFmpegExe, uCache, uWlxAPI,
  uZoomController, uViewModeLogic,
  uExtractionPlanner, uToolbarLayout, uFrameView, uViewModeLayout, uExtractionWorker,
  uFrameExtractor, uFrameExport, uExtractionController, uProbeCache;

type
  {Plugin form created as a child of TC's Lister window.}
  TPluginForm = class(TForm)
  private
    FFileName: string;
    FSettings: TPluginSettings;
    FFFmpegPath: string;
    FVideoInfo: TVideoInfo;
    FOffsets: TFrameOffsetArray;
    FParentWnd: HWND;
    {Toolbar}
    FToolbar: TPanel;
    FLblFrames: TLabel;
    FEditFrameCount: TEdit;
    FUpDown: TUpDown;
    FModeButtons: array [TViewMode] of TButton;
    FModePopups: array [TViewMode] of TPopupMenu;
    FContextMenu: TPopupMenu;
    FContextCellIndex: Integer;
    FBtnTimecode: TSpeedButton;
    FToolbarButtons: array of TButton;
    FBtnHamburger: TButton;
    FHamburgerMenu: TPopupMenu;
    {Holds embedded PNG glyphs for toolbar buttons that have no good Unicode
     equivalent; the hamburger is the first user. Owned by Self.}
    FToolbarImages: TImageList;
    FProgressBar: TProgressBar;
    FProgressVisible: Boolean;
    {Per-element right pixel edges for collapse threshold checks}
    FFrameCountRight: Integer;
    FElementRights: array of Integer;
    FVisibleElementCount: Integer;
    {Status bar}
    FStatusBar: TStatusBar;
    {Content}
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    {Export}
    FExporter: TFrameExporter;
    {Extraction}
    FExtractCtrl: TExtractionController;
    FProbeCache: TProbeCache;
    {Animation}
    FAnimTimer: TTimer;
    {Debounce timer for "re-extract after the user stops resizing / switching
     modes". Kicked on every viewport-changing event; its OnTimer fires once
     the events settle, compares the computed MaxSide to what was used for
     the last extraction, and triggers a soft refresh when they differ.}
    FViewportRefreshTimer: TTimer;
    {Options.MaxSide value from the last StartExtraction. 0 means no prior
     extraction or scaling was off; compared against the freshly-computed
     MaxSide in OnViewportRefreshTimer to decide whether to soft-refresh.}
    FLastExtractionMaxSide: Integer;
    {Layout guard: prevents re-entrant UpdateFrameViewSize during zoom}
    FUpdatingLayout: Boolean;
    {True when the plugin is hosted in TC's Quick View panel (Ctrl+Q)}
    FQuickViewMode: Boolean;
    {Prevents key-triggered reopen while Popup is still returning}
    FHamburgerMenuOpen: Boolean;
    {Suppresses WM_CHAR after OnKeyDown consumed the keystroke}
    FKeyConsumed: Boolean;
    {Tick count when LoadFile started (for load time measurement)}
    FLoadStartTick: Cardinal;
    {Formatted load time string, populated when extraction completes}
    FLoadTimeStr: string;
    {Rolling snapshot used by ShowSettings to detect what changed since the
     previous Apply/OK commit, so Apply can be pressed repeatedly and only
     trigger the side-effects (cache recreate, re-extract) that apply to the
     delta, not to the full original-to-current diff}
    FSettingsSnap: TSettingsSnapshot;

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
    procedure CommitSettingsChanges;
    procedure OnSettingsApply(Sender: TObject);
    procedure NavigateToAdjacentFile(ADelta: Integer);
    procedure RefreshExtraction;
    procedure SoftRefreshExtraction;
    procedure ScheduleViewportRefresh;
    procedure OnViewportRefreshTimer(Sender: TObject);
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
    function ExecuteHotkey(AAction: TPluginAction): Boolean;
    procedure ForwardKeyToLister(AKey: Word; ASysKey: Boolean);
    procedure WMFrameReady(var Message: TMessage); message WM_FRAME_READY;
    procedure WMExtractionDone(var Message: TMessage); message WM_EXTRACTION_DONE;
    procedure CMDialogKey(var Message: TWMKey); message CM_DIALOGKEY;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor CreateForPlugin(AParentWin: HWND; const AFileName: string; ASettings: TPluginSettings; const AFFmpegPath: string);
    destructor Destroy; override;
    procedure LoadFile(const AFileName: string);
    procedure CopyFrameToClipboard;
    procedure ApplyListerParams(AParams: Integer);
  end;

implementation

uses
  System.IOUtils, Winapi.ShellAPI,
  uSettingsDlg, uFileNavigator, uDebugLog, uPathExpand, uCombinedImage;

{Embedded toolbar glyph resources; see CreateToolbar for use. The .res is
 generated from icons.rc by cgrc as a pre-build step in build.bat and
 test.bat — brcc32 (the default $R 'foo.rc' compiler) emits 16-bit-format
 resources that the Win64 linker rejects.}
{$R icons.res}

{Loads an icon resource into AImageList. Icons preserve their alpha channel
 natively through TImageList.AddIcon; no manual scanline copy is needed.}
procedure LoadIconResourceToImageList(AImageList: TImageList; const AResName: string);
var
  Icon: TIcon;
begin
  Icon := TIcon.Create;
  try
    Icon.LoadFromResourceName(HInstance, AResName);
    AImageList.AddIcon(Icon);
  finally
    Icon.Free;
  end;
end;

procedure FormLog(const AMsg: string);
begin
  DebugLog('Form', AMsg);
end;

{Closes the active menu on the calling thread}
function EndMenu: BOOL; stdcall; external user32 name 'EndMenu';

var
  {Thread-local keyboard hook handle, active only during hamburger popup}
  GMenuHook: HHOOK;

  {Intercepts VK_OEM_3 (tilde) during popup menu's modal loop to close it}
function MenuKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;
begin
  if (nCode = HC_ACTION) and (wParam = VK_OEM_3) and (lParam and (1 shl 31) = 0) then
  begin
    EndMenu;
    Result := 1;
  end
  else
    Result := CallNextHookEx(GMenuHook, nCode, wParam, lParam);
end;

{comctl32 v6 subclass API - lets us monitor the parent window's WM_SIZE}
function SetWindowSubclass(HWND: HWND; pfnSubclass: Pointer; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): BOOL; stdcall; external 'comctl32.dll' name 'SetWindowSubclass';
function RemoveWindowSubclass(HWND: HWND; pfnSubclass: Pointer; uIdSubclass: UINT_PTR): BOOL; stdcall; external 'comctl32.dll' name 'RemoveWindowSubclass';
function DefSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam): LRESULT; stdcall; external 'comctl32.dll' name 'DefSubclassProc';

{Subclass callback on TC's Lister parent window.
 TC may not resize the plugin child for all resize directions;
 this ensures the plugin always fills the parent's client rect.}
function ParentSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
var
  Form: TPluginForm;
  R: TRect;
begin
  Result := DefSubclassProc(HWND, uMsg, wParam, lParam);
  if uMsg = WM_SIZE then
  begin
    Form := TPluginForm(Pointer(dwRefData));
    if (Form <> nil) and Form.HandleAllocated then
    begin
      Winapi.Windows.GetClientRect(HWND, R);
      Form.SetBounds(0, 0, R.Right, R.Bottom);
    end;
  end;
end;

const
  {Toolbar icon list slots; loaded in CreateToolbar in this order and
   referenced from OnHamburgerMenuPopup as well, so the indices live at
   unit scope instead of inside CreateToolbar's local const block.}
  IDX_ICON_HAMBURGER = 0;
  IDX_ICON_ARROW_W = 1; {Vertical arrow for vmScroll}
  IDX_ICON_ARROW_H = 2; {Horizontal arrow for vmFilmstrip}

  {Deferred self-subclass: installed after TC subclasses us so we fire first}
  FORM_SUBCLASS_ID = 2;
  WM_DEFERRED_INIT = WM_USER + 102; {Triggers self-subclass installation}
  WM_PLUGIN_FKEY = WM_USER + 103; {Re-posted key intercepted from TC}

  {Bit flags packed into the re-posted WM_PLUGIN_FKEY's lParam so the form
   WndProc can reconstruct TShiftState on the other side of the re-post.}
  FKEY_LPARAM_SHIFT = 1;
  FKEY_LPARAM_CTRL = 2;
  FKEY_LPARAM_ALT = 4;

{True when AKey should flow through to the VCL/OS key pipeline unchanged
 instead of being swallowed by the plugin's key-interception. These are the
 keys the plugin cannot own without breaking system behaviour:
 - Tab: VCL focus cycling relies on the standard WM_KEYDOWN path.
 - Alt+F4: Windows delivers SC_CLOSE via the normal chain; hijacking it
   would leave users unable to close the Lister window.
 - Bare modifier keys: meaningless alone, and we need TranslateMessage to
   see their down/up transitions for subsequent key combinations to build
   correct WM_SYSKEYDOWN messages.}
function ShouldLetKeyPassThrough(AKey: Word): Boolean;
begin
  case AKey of
    VK_TAB, VK_SHIFT, VK_CONTROL, VK_MENU,
    VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU:
      Exit(True);
  end;
  {Alt+F4 is a system close shortcut — let the OS deliver its SC_CLOSE.}
  if (AKey = VK_F4) and (GetKeyState(VK_MENU) < 0) then
    Exit(True);
  Result := False;
end;

{Packs the live modifier-key state into a single LPARAM value so the
 repost target can rebuild TShiftState without another GetKeyState call.}
function PackShiftIntoLParam: LPARAM;
begin
  Result := 0;
  if GetKeyState(VK_SHIFT) < 0 then
    Result := Result or FKEY_LPARAM_SHIFT;
  if GetKeyState(VK_CONTROL) < 0 then
    Result := Result or FKEY_LPARAM_CTRL;
  if GetKeyState(VK_MENU) < 0 then
    Result := Result or FKEY_LPARAM_ALT;
end;

{Self-subclass callback on the plugin form window.
 Installed AFTER TC subclasses us (via deferred PostMessage), so it fires
 first in the chain. Claims every key-down message so Lister's built-in
 shortcuts (Escape to close, 1-9 view-mode switch, N/P file navigation,
 letter-key mode toggles, etc.) stay out of the plugin's way and every
 key flows through the plugin's own hotkey dispatcher instead. Excluded
 keys (see ShouldLetKeyPassThrough) flow through unchanged.}
function FormSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
begin
  case uMsg of
    WM_KEYDOWN, WM_SYSKEYDOWN:
      if not ShouldLetKeyPassThrough(wParam) then
      begin
        PostMessage(HWND, WM_PLUGIN_FKEY, wParam, PackShiftIntoLParam);
        Result := 0;
        Exit;
      end;
    WM_NCDESTROY:
      RemoveWindowSubclass(HWND, @FormSubclassProc, FORM_SUBCLASS_ID);
  end;
  Result := DefSubclassProc(HWND, uMsg, wParam, lParam);
end;

const
  CLR_ERROR_LABEL = TColor($00888888); {error message label}
  FONT_ERROR_LABEL = 11;

  {UI layout}
  ANIM_INTERVAL_MS = 80; {placeholder spinner animation tick}
  MAX_FRAME_COUNT = 99; {upper limit for frame count spin edit}
  {Resize-drag debounce for the background viewport-refresh timer. Long
   enough that mid-drag pixel deltas don't trigger ffmpeg spawns, short
   enough that the user sees the high-res refresh promptly after release.}
  VIEWPORT_REFRESH_DEBOUNCE_MS = 500;
  FRAME_COUNT_EDIT_W = 40; {width of the frame count edit control}
  STATUSBAR_HEIGHT = 21;
  STATUSBAR_FONT = 9;
  PROGRESSBAR_H = 14; {desired height of the embedded progress bar}
  PROGRESSBAR_MIN_W = 40; {minimum width before clamping}

  {Status bar panel widths}
  SBP_RESOLUTION_W = 120;
  SBP_FRAMERATE_W = 100;
  SBP_DURATION_W = 100;
  SBP_BITRATE_W = 100;
  SBP_VIDEOCODEC_W = 90;
  SBP_AUDIO_W = 300;
  SBP_NOAUDIO_W = 110;
  {Panel width fits "999 / 999" comfortably. File count in a typical video
   folder sits well below 1000; capping visual width here keeps the panel
   from stretching when the user stumbles into a huge directory.}
  SBP_FILEPOS_W = 80;
  SBP_FRAMEPOS_W = 70;
  SBP_LOADTIME_W = 110;
  {Total width including per-panel borders added by the common control}
  SBP_TOTAL_RIGHT = 1000;

  {Command tags, mode captions, sizing labels, and toolbar actions
   are defined in uToolbarLayout}

  {TPluginForm}

procedure TPluginForm.OnFrameViewCtrlWheel(Sender: TObject; AWheelDelta: Integer);
begin
  if AWheelDelta > 0 then
    ZoomBy(ZOOM_IN_FACTOR)
  else
    ZoomBy(ZOOM_OUT_FACTOR);
end;

constructor TPluginForm.CreateForPlugin(AParentWin: HWND; const AFileName: string; ASettings: TPluginSettings; const AFFmpegPath: string);
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

  {Quick View panel is a child window; Lister is a top-level window.
   Must be set before ApplySettings so QV defaults take effect.}
  FQuickViewMode := (GetWindowLong(AParentWin, GWL_STYLE) and WS_CHILD) <> 0;

  CreateToolbar;
  CreateStatusBar;
  CreateFrameView;
  CreateContextMenu;
  CreateErrorLabel;
  ApplySettings;

  {Wire OnChange after ApplySettings so initial Position assignment doesn't
   trigger a save that overwrites the loaded FramesCount}
  FEditFrameCount.OnChange := OnFrameCountChange;

  ParentWindow := AParentWin;
  FParentWnd := AParentWin;
  SetWindowSubclass(AParentWin, @ParentSubclassProc, 1, DWORD_PTR(Self));
  Visible := True;
  {Focus the form handle so TC recognises N/P as Lister shortcuts.
   Rapid N/P may lose focus due to TC briefly focusing its file list.}
  Winapi.Windows.SetFocus(Handle);
  {Install self-subclass AFTER TC subclasses us (which happens when ListLoad
   returns). PostMessage defers execution until the message loop resumes,
   guaranteeing TC's subclass is already in place. Our subclass then fires
   first and can intercept keys TC would otherwise consume (F2/F3).}
  PostMessage(Handle, WM_DEFERRED_INIT, 0, 0);

{$IFDEF DEBUG}
  uDebugLog.GDebugLogPath := ExtractFilePath(FSettings.IniPath) + 'glimpse_debug.log';
{$ENDIF}
  FormLog(Format('CreateForPlugin: file=%s handle=$%s', [AFileName, IntToHex(Handle)]));

  FProbeCache := TProbeCache.Create(DefaultProbeCacheDir);

  {Create extraction controller with appropriate cache}
  if FSettings.CacheEnabled then
    FExtractCtrl := TExtractionController.Create(Handle, TFrameCache.Create(EffectiveCacheFolder(FSettings.CacheFolder), FSettings.CacheMaxSizeMB))
  else
    FExtractCtrl := TExtractionController.Create(Handle, TNullFrameCache.Create);
  FExtractCtrl.OnFrameDelivered := OnFrameDelivered;
  FExtractCtrl.OnProgress := OnExtractionProgress;

  FExporter := TFrameExporter.Create(FFrameView, FSettings);

  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := ANIM_INTERVAL_MS;
  FAnimTimer.OnTimer := OnAnimTimer;
  FAnimTimer.Enabled := True;

  FViewportRefreshTimer := TTimer.Create(Self);
  FViewportRefreshTimer.Interval := VIEWPORT_REFRESH_DEBOUNCE_MS;
  FViewportRefreshTimer.OnTimer := OnViewportRefreshTimer;
  FViewportRefreshTimer.Enabled := False;

  LoadFile(AFileName);
end;

destructor TPluginForm.Destroy;
begin
  if HandleAllocated then
    RemoveWindowSubclass(Handle, @FormSubclassProc, FORM_SUBCLASS_ID);
  if FParentWnd <> 0 then
    RemoveWindowSubclass(FParentWnd, @ParentSubclassProc, 1);
  {FAnimTimer may not exist yet if destructor runs during CreateForPlugin
   (VCL can destroy a windowed control before the constructor finishes)}
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
  TB_PAD = 4; {Vertical padding above and below controls}
  CTRL_GAP = 8; {Gap between control groups}
  BTN_GAP = 2; {Gap between adjacent buttons in a group}
  BTN_PAD = 16; {Horizontal text padding inside button (both sides)}
  SPLIT_ARROW_W = 20; {Extra width for split button dropdown arrow}
  PB_H = 16; {Progress bar height}
  ICON_W = 16; {Toolbar icon width}
  ICON_GAP = 4; {Space between icon and caption on iaLeft buttons}
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

  {Create edit first: its auto-sized height is the reference for all controls}
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

  {Collapsible elements: modes, timecodes, actions (left to right)}
  SetLength(FElementRights, ELEM_TOTAL_COUNT);

  {Toolbar glyphs are loaded from embedded ICON resources rather than relying
   on Unicode characters: the runtime font (Tahoma/MS Sans Serif under TC's
   Lister window) does not reliably cover U+2261/U+2194/U+2195. Index order
   here must match the IDX_ICON_* constants.}
  FToolbarImages := TImageList.Create(Self);
  FToolbarImages.SetSize(ICON_W, ICON_W);
  FToolbarImages.ColorDepth := cd32Bit;
  LoadIconResourceToImageList(FToolbarImages, 'MENU');
  LoadIconResourceToImageList(FToolbarImages, 'ARROW_W');
  LoadIconResourceToImageList(FToolbarImages, 'ARROW_H');

  {Create 5 mode buttons}
  TabIdx := 1;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    {Create popup menu first (needed for DropDownMenu assignment)}
    FModePopups[VM] := CreateModePopup(VM);

    FModeButtons[VM] := TButton.Create(FToolbar);
    FModeButtons[VM].Parent := FToolbar;

    {Auto-width: measure caption text and add padding. Scroll/Filmstrip
     also reserve space for a directional arrow icon to the left of the
     caption.}
    BW := Canvas.TextWidth(MODE_CAPTIONS[VM]) + BTN_PAD;
    if FModePopups[VM] <> nil then
      Inc(BW, SPLIT_ARROW_W);
    if VM in [vmScroll, vmFilmstrip] then
      Inc(BW, ICON_W + ICON_GAP);

    FModeButtons[VM].SetBounds(X, CY, BW, CtrlH);
    FModeButtons[VM].Caption := MODE_CAPTIONS[VM];
    FModeButtons[VM].Tag := Ord(VM);
    FModeButtons[VM].TabOrder := TabIdx;
    FModeButtons[VM].OnClick := OnModeButtonClick;

    if VM = vmScroll then
    begin
      FModeButtons[VM].Images := FToolbarImages;
      FModeButtons[VM].ImageIndex := IDX_ICON_ARROW_W;
      {Qualified — TIconArrangement (Vcl.ComCtrls) also defines iaRight.
       Icon sits to the right of the caption, matching the original ↕/↔
       glyph position.}
      FModeButtons[VM].ImageAlignment := Vcl.StdCtrls.iaRight;
    end
    else if VM = vmFilmstrip then
    begin
      FModeButtons[VM].Images := FToolbarImages;
      FModeButtons[VM].ImageIndex := IDX_ICON_ARROW_H;
      FModeButtons[VM].ImageAlignment := Vcl.StdCtrls.iaRight;
    end;

    {Split button: click activates mode, arrow shows submodes}
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

  {Action buttons matching context menu (except selection-dependent commands)}
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

  {Hamburger overflow button: hidden until toolbar is too narrow. Glyph
   comes from FToolbarImages (created earlier with the mode-button arrow
   icons) so the toolbar does not depend on the runtime font's coverage
   of U+2261.}
  FHamburgerMenu := TPopupMenu.Create(Self);
  FHamburgerMenu.OnPopup := OnHamburgerMenuPopup;
  {Sharing the toolbar's image list lets MI.ImageIndex paint the same arrow
   glyphs next to the Scroll/Filmstrip menu items that the toolbar buttons
   show — necessary because both modes share the textual caption.}
  FHamburgerMenu.Images := FToolbarImages;

  FBtnHamburger := TButton.Create(FToolbar);
  FBtnHamburger.Parent := FToolbar;
  FBtnHamburger.Images := FToolbarImages;
  FBtnHamburger.ImageIndex := IDX_ICON_HAMBURGER;
  FBtnHamburger.ImageAlignment := iaCenter;
  {Square button matched to the rest of the toolbar's height}
  FBtnHamburger.SetBounds(0, CY, CtrlH, CtrlH);
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
  if not Assigned(FBtnHamburger) then
    Exit;

  Layout := ComputeToolbarLayout(FToolbar.ClientWidth, FElementRights, FFrameCountRight, FBtnHamburger.Width, CTRL_GAP);
  FVisibleElementCount := Layout.VisibleCount;

  {Per-button visibility based on element index}
  for VM := Low(TViewMode) to High(TViewMode) do
    FModeButtons[VM].Visible := Ord(VM) < Layout.VisibleCount;

  FBtnTimecode.Visible := ELEM_TIMECODE_INDEX < Layout.VisibleCount;

  for I := 0 to High(FToolbarButtons) do
    FToolbarButtons[I].Visible := (ELEM_ACTION_FIRST + I) < Layout.VisibleCount;

  {Hamburger button}
  FBtnHamburger.Visible := Layout.HamburgerVisible;
  FBtnHamburger.Left := Layout.HamburgerLeft;
end;

procedure TPluginForm.OnHamburgerClick(Sender: TObject);
var
  P: TPoint;
begin
  if FHamburgerMenuOpen then
    Exit;
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
  {Source of truth: do any cells currently display a real frame? Reading this
   off the extraction controller's FramesLoaded counter is wrong because a
   soft refresh resets it to 0 while the cells stay on screen.}
  State.HasFrames := FFrameView.HasLoadedCells;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    State.ModeZooms[VM] := FSettings.ModeZoom[VM];
    State.ModeHasSubmenu[VM] := FModePopups[VM] <> nil;
    State.ModeImageIndex[VM] := -1;
  end;
  State.ModeImageIndex[vmScroll] := IDX_ICON_ARROW_W;
  State.ModeImageIndex[vmFilmstrip] := IDX_ICON_ARROW_H;

  PopulateHamburgerMenu(FHamburgerMenu, State, OnHamburgerModeClick, OnHamburgerZoomClick, OnHamburgerTimecodeClick, OnHamburgerActionClick);
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

  {First activate the mode, then override its zoom}
  ActivateMode(AMode);
  FFrameView.ZoomMode := AZoom;
  UpdateFrameViewSize;

  {Persist and sync the popup menu checks}
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
  {Grid modes always fit all frames to the available space}
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
  {Update scroll position live during thumb drag, not just on release}
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

  function FormatBitrate(AKbps: Integer): string;
  begin
    if AKbps >= 1000 then
      Result := Format('%.1f Mbps', [AKbps / 1000])
    else
      Result := Format('%d kbps', [AKbps]);
  end;

  procedure AddPanel(const AText: string; AWidth: Integer; AAlignment: TAlignment = taLeftJustify);
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
  FileIdx, FileTotal: Integer;
begin
  FStatusBar.Panels.Clear;

  if not FVideoInfo.IsValid then
    Exit;

  {File position: 1-based index within the directory's supported files.
   Omitted when the current file can't be located (e.g. extension not in
   the list or directory unreadable).}
  if GetFilePosition(FFileName, FSettings.ExtensionList, FileIdx, FileTotal) then
    AddPanel(Format('%d / %d', [FileIdx, FileTotal]), SBP_FILEPOS_W);

  {Frame position: shown as "current / total" only in single view, where
   the notion of "current frame" is visible. Other modes render the whole
   grid, so the "current" slot is meaningless; show just the total.}
  if Length(FOffsets) > 0 then
  begin
    if FFrameView.ViewMode = vmSingle then
      AddPanel(Format('%d / %d',
        [FFrameView.CurrentFrameIndex + 1, Length(FOffsets)]),
        SBP_FRAMEPOS_W)
    else
      AddPanel(IntToStr(Length(FOffsets)), SBP_FRAMEPOS_W);
  end;

  {Resolution}
  if (FVideoInfo.Width > 0) and (FVideoInfo.Height > 0) then
    AddPanel(Format('%dx%d', [FVideoInfo.Width, FVideoInfo.Height]), SBP_RESOLUTION_W);

  {Framerate}
  if FVideoInfo.Fps > 0 then
    AddPanel(Format('%.4g fps', [FVideoInfo.Fps]), SBP_FRAMERATE_W);

  {Duration}
  if FVideoInfo.Duration > 0 then
    AddPanel(FormatDurationHMS(FVideoInfo.Duration), SBP_DURATION_W);

  {Overall bitrate}
  if FVideoInfo.Bitrate > 0 then
    AddPanel(FormatBitrate(FVideoInfo.Bitrate), SBP_BITRATE_W);

  {Video codec}
  if FVideoInfo.VideoCodec <> '' then
    AddPanel(FVideoInfo.VideoCodec, SBP_VIDEOCODEC_W);

  {Audio section}
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

  {Load time (shown after extraction completes)}
  if FLoadTimeStr <> '' then
  begin
    AddPanel(FLoadTimeStr, SBP_LOADTIME_W, taRightJustify);
    {Dummy panel absorbs last-panel stretching from the common control}
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

  {Click past last panel: copy last panel}
  Clipboard.AsText := FStatusBar.Panels[FStatusBar.Panels.Count - 1].Text;
end;

procedure TPluginForm.ApplySettings;
var
  VM: TViewMode;
  Style: TTimestampStyle;
begin
  if FSettings = nil then
    Exit;

  FUpDown.Position := FSettings.FramesCount;
  FFrameView.ViewMode := FSettings.ViewMode;
  FFrameView.ZoomMode := FSettings.ZoomMode;

  {Restore per-mode zoom selections in all popup menus}
  for VM := Low(TViewMode) to High(TViewMode) do
    SyncZoomMenuChecks(VM, FSettings.ModeZoom[VM]);

  UpdateViewModeButtons;
  FToolbar.Visible := FSettings.ShowToolbar and not(FQuickViewMode and FSettings.QVHideToolbar);
  FStatusBar.Visible := FSettings.ShowStatusBar and not(FQuickViewMode and FSettings.QVHideStatusBar);
  {Copy the current style so fields the live view owns (FontStyles: live view
   renders non-bold) survive while settings-driven fields update.}
  Style := FFrameView.TimestampStyle;
  Style.Show := FSettings.ShowTimecode;
  Style.Corner := FSettings.TimestampCorner;
  Style.FontName := FSettings.TimestampFontName;
  Style.FontSize := FSettings.TimestampFontSize;
  Style.BackColor := FSettings.TimecodeBackColor;
  Style.BackAlpha := FSettings.TimecodeBackAlpha;
  Style.TextColor := FSettings.TimestampTextColor;
  Style.TextAlpha := FSettings.TimestampTextAlpha;
  FFrameView.TimestampStyle := Style;
  FFrameView.CellGap := FSettings.CellGap;
  FFrameView.CellMargin := FSettings.CombinedBorder;
  UpdateTimecodeButton;
  FFrameView.BackColor := FSettings.Background;
  FScrollBox.Color := FSettings.Background;
  Color := FSettings.Background;
end;

procedure TPluginForm.ActivateMode(AMode: TViewMode);
begin
  FFrameView.ZoomFactor := 1.0;
  FFrameView.ViewMode := AMode;
  {Mode change might have altered the effective per-frame viewport
   (grid<->single), so kick the debounce timer; the actual refresh only
   fires if the computed MaxSide actually changes.}
  ScheduleViewportRefresh;
  {Status bar's frame-position cell switches between "N / Total" and
   "Total" based on mode.}
  UpdateStatusBar;

  {Apply the zoom mode stored in the popup, or force Fit for modes without submodes}
  if FModePopups[AMode] <> nil then
  begin
    var
      I: Integer;
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

  {Persist user preference}
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

  NormX := NormalizeViewportCenter(FScrollBox.HorzScrollBar.Position, FScrollBox.ClientWidth, FFrameView.Width);
  NormY := NormalizeViewportCenter(FScrollBox.VertScrollBar.Position, FScrollBox.ClientHeight, FFrameView.Height);

  SendMessage(FScrollBox.Handle, WM_SETREDRAW, wParam(False), 0);
  FUpdatingLayout := True;
  try
    FFrameView.ZoomFactor := NewF;
    UpdateFrameViewSize;
    FScrollBox.HorzScrollBar.Position := DenormalizeViewportCenter(NormX, FFrameView.Width, FScrollBox.ClientWidth);
    FScrollBox.VertScrollBar.Position := DenormalizeViewportCenter(NormY, FFrameView.Height, FScrollBox.ClientHeight);
  finally
    FUpdatingLayout := False;
    SendMessage(FScrollBox.Handle, WM_SETREDRAW, wParam(True), 0);
    RedrawWindow(FScrollBox.Handle, nil, 0, RDW_ERASE or RDW_FRAME or RDW_INVALIDATE or RDW_ALLCHILDREN);
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
begin
  FormLog(Format('LoadFile: %s', [AFileName]));
  FLoadStartTick := GetTickCount;
  FLoadTimeStr := '';
  FFileName := AFileName;
  SetWindowText(FParentWnd, PChar(Format('Lister (glimpse) - [%s]', [AFileName])));
  FExtractCtrl.Stop;
  FExtractCtrl.DrainPendingFrameMessages;
  FFrameView.ClearCells;
  FVideoInfo := Default (TVideoInfo);

  if FFFmpegPath = '' then
  begin
    ShowError('ffmpeg not found.'#13#10'Press F2 to configure.');
    Exit;
  end;

  FVideoInfo := FProbeCache.TryGetOrProbe(FFileName, FFFmpegPath);

  FExporter.UpdateBannerInfo(BuildBannerInfo(FFileName, FVideoInfo));

  UpdateStatusBar;

  if not FVideoInfo.IsValid then
  begin
    ShowError('Could not read video file.'#13#10 + FVideoInfo.ErrorMessage);
    Exit;
  end;

  {Set actual dimensions and aspect ratio from video metadata}
  if (FVideoInfo.Width > 0) and (FVideoInfo.Height > 0) then
  begin
    FFrameView.NativeW := FVideoInfo.Width;
    FFrameView.NativeH := FVideoInfo.Height;
    FFrameView.AspectRatio := FVideoInfo.Height / FVideoInfo.Width;
  end else begin
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
  FOffsets := CalculateFrameOffsets(FVideoInfo.Duration, FUpDown.Position, FSettings.SkipEdgesPercent);

  FFrameView.SetCellCount(Length(FOffsets), FOffsets);
  UpdateFrameViewSize;
end;

procedure TPluginForm.StartExtraction(const ACacheOverride: IFrameCache);
var
  Extractor: IFrameExtractor;
  Options: TExtractionOptions;
  ViewportFrames: Integer;
begin
  FExtractCtrl.Stop;
  FLoadStartTick := GetTickCount;
  FLoadTimeStr := '';
  UpdateToolbarButtons;

  FProgressBar.Style := pbstMarquee;
  ShowProgress('Extracting...');
  FAnimTimer.Enabled := True;

  {Zero-init so any future TExtractionOptions fields default to 0}
  Options := Default (TExtractionOptions);
  Options.UseBmpPipe := FSettings.UseBmpPipe;
  if FSettings.ScaledExtraction then
  begin
    ViewportFrames := ViewportFrameCount(FFrameView.ViewMode, Length(FOffsets));
    Options.MaxSide := CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight, ViewportFrames, FFrameView.AspectRatio, FVideoInfo.Width, FVideoInfo.Height, FSettings.MinFrameSide, FSettings.MaxFrameSide);
  end;
  Options.HwAccel := FSettings.HwAccel;
  Options.UseKeyframes := FSettings.UseKeyframes;

  {Remember the extraction size so OnViewportRefreshTimer can decide
   whether the next viewport-change event actually changed anything.}
  FLastExtractionMaxSide := Options.MaxSide;

  Extractor := TFFmpegFrameExtractor.Create(FFFmpegPath);
  FExtractCtrl.Start(Extractor, FFileName, FOffsets, FSettings.MaxWorkers, FSettings.MaxThreads, Options, ACacheOverride);
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
  FStatusBar.Visible := FSettings.ShowStatusBar and not(FQuickViewMode and FSettings.QVHideStatusBar);
end;

procedure TPluginForm.FinalizeLoadTime;
var
  ElapsedMs: Cardinal;
  H, M, S, Ms: Integer;
begin
  if FLoadStartTick = 0 then
    Exit;
  if FLoadTimeStr <> '' then
    Exit; {already finalized}

  {Cast guards correct unsigned wraparound; GetTickCount avoids the Vista+ GetTickCount64 dependency that crashes on XP via delay-load}
  ElapsedMs := Cardinal(GetTickCount - FLoadStartTick);
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
  if not FProgressVisible then
    Exit;
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
  end else if (FExtractCtrl.FramesLoaded > 0) and FProgressVisible then
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
  FormLog(Format('WMExtractionDone: framesLoaded=%d total=%d', [FExtractCtrl.FramesLoaded, FExtractCtrl.TotalFrames]));
  {Safety net: process any frames that arrived after the last notification}
  FExtractCtrl.ProcessPendingFrames;
  FinalizeLoadTime;
  HideProgress;
  FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  FormLog(Format('  hasPlaceholders=%s timerEnabled=%s', [BoolToStr(FFrameView.HasPlaceholders, True), BoolToStr(FAnimTimer.Enabled, True)]));
end;

procedure TPluginForm.ForwardKeyToLister(AKey: Word; ASysKey: Boolean);
begin
  {Synthesises a keystroke into Lister's message queue so it can handle its
   own shortcuts (Escape to close, F11 to maximise, Alt+Enter for full-screen)
   while the plugin holds focus. SysKey mode sets the context-code bits on
   the lParam so Lister accepts the message as a genuine Alt-combo regardless
   of the physical Alt state when the message is pumped.}
  if ASysKey then
  begin
    PostMessage(GetParent(Handle), WM_SYSKEYDOWN, AKey, Integer($20000000));
    PostMessage(GetParent(Handle), WM_SYSKEYUP, AKey, Integer($E0000000));
  end else
  begin
    PostMessage(GetParent(Handle), WM_KEYDOWN, AKey, 0);
    PostMessage(GetParent(Handle), WM_KEYUP, AKey, 0);
  end;
end;

function TPluginForm.ExecuteHotkey(AAction: TPluginAction): Boolean;
begin
  Result := True;
  case AAction of
    paSettings:
      ShowSettings;
    paToggleToolbar:
      begin
        FToolbar.Visible := not FToolbar.Visible;
        {Reclaim focus so TC's subclass sees keystrokes again}
        if not FToolbar.Visible then
          Winapi.Windows.SetFocus(Handle);
        if not FQuickViewMode then
        begin
          FSettings.ShowToolbar := FToolbar.Visible;
          FSettings.Save;
        end;
      end;
    paToggleStatusBar:
      begin
        FStatusBar.Visible := not FStatusBar.Visible;
        if not FQuickViewMode then
        begin
          FSettings.ShowStatusBar := FStatusBar.Visible;
          FSettings.Save;
        end;
      end;
    paToggleTimecode:
      OnTimecodeButtonClick(nil);
    paToggleMaximize:
      ForwardKeyToLister(VK_F11, False);
    paToggleFullScreen:
      ForwardKeyToLister(VK_RETURN, True);
    paHamburgerMenu:
      if FBtnHamburger.Visible then
        OnHamburgerClick(FBtnHamburger)
      else
        Result := False;
    paCloseLister:
      ForwardKeyToLister(VK_ESCAPE, False);
    paPrevFile:
      NavigateToAdjacentFile(-1);
    paNextFile:
      NavigateToAdjacentFile(1);
    paPrevFrame:
      {Frame navigation is only meaningful in single-view mode. Returning
       False when the guard fails lets the keystroke fall through to any
       edit that had focus (same as the pre-refactor behaviour).}
      if FFrameView.ViewMode = vmSingle then
      begin
        FFrameView.NavigateFrame(-1);
        UpdateStatusBar;
      end
      else
        Result := False;
    paNextFrame:
      if FFrameView.ViewMode = vmSingle then
      begin
        FFrameView.NavigateFrame(1);
        UpdateStatusBar;
      end
      else
        Result := False;
    paFrameCountInc:
      FUpDown.Position := FUpDown.Position + 1;
    paFrameCountDec:
      FUpDown.Position := FUpDown.Position - 1;
    paOpenInPlayer:
      {Don't consume Enter while the frame-count edit has focus — the
       edit-focus fallback below commits the value. No file loaded is also
       a valid no-op: let the key pass through.}
      if (GetFocus <> FEditFrameCount.Handle) and (FFileName <> '') then
        ShellExecute(Handle, 'open', PChar(FFileName), nil, nil, SW_SHOWNORMAL)
      else
        Result := False;
    paRefreshExtraction:
      RefreshExtraction;
    paSaveSingleFrame:
      begin
        FContextCellIndex := -1;
        FExporter.SaveSingleFrame(FFileName, FContextCellIndex);
      end;
    paSaveAllFrames:
      FExporter.SaveAllFrames(FFileName);
    paSaveCombined:
      FExporter.SaveCombinedFrame(FFileName);
    paSaveSelected:
      FExporter.SaveSelectedFrames(FFileName);
    paSelectAllFrames:
      FFrameView.SelectAll;
    paCopyToClipboard:
      CopyFrameToClipboard;
    paCopyAllToClipboard:
      FExporter.CopyAllToClipboard;
    paZoomIn:
      ZoomBy(ZOOM_IN_FACTOR);
    paZoomOut:
      ZoomBy(ZOOM_OUT_FACTOR);
    paZoomReset:
      ResetZoom;
    {View-mode actions pass the canonical digit to SwitchOrCycleMode so the
     cycle-submodes logic keeps working regardless of what key the user
     bound the action to.}
    paViewModeSmartGrid:
      SwitchOrCycleMode(Ord('1'));
    paViewModeGrid:
      SwitchOrCycleMode(Ord('2'));
    paViewModeScroll:
      SwitchOrCycleMode(Ord('3'));
    paViewModeFilmstrip:
      SwitchOrCycleMode(Ord('4'));
    paViewModeSingle:
      SwitchOrCycleMode(Ord('5'));
  else
    Result := False;
  end;
end;

procedure TPluginForm.OnFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Action: TPluginAction;
begin
  FKeyConsumed := False;

  {Tab: VCL focus cycling. System-level, never user-configurable; the
   configurable dispatcher intentionally doesn't handle this.}
  if (Key = VK_TAB) and (Shift - [ssShift] = []) then
  begin
    SelectNext(ActiveControl, not(ssShift in Shift), True);
    Key := 0;
    FKeyConsumed := True;
    Exit;
  end;

  {Edit-focus passthrough (fires BEFORE hotkey dispatch). When the frame
   count edit holds focus, digits and basic editing keys must reach the
   edit regardless of whether the user happened to bind them to a global
   action. Without this check, typing "12" in the edit would fire
   paViewModeSmartGrid and paViewModeGrid on a default install because
   "1" and "2" are default Ctrl+digit chords that collapse to the bare
   digit when no modifier keys are held. The post-dispatch fallback below
   still handles the non-typable keys (Enter to commit, unbound Ctrl+V
   to reclaim focus, etc.).}
  if (GetFocus = FEditFrameCount.Handle) and (Shift * [ssCtrl, ssAlt] = []) then
    case Key of
      Ord('0') .. Ord('9'), VK_NUMPAD0 .. VK_NUMPAD9,
      VK_BACK, VK_DELETE, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_UP, VK_DOWN:
        Exit;
    end;

  {Configurable hotkeys. ExecuteHotkey returns False when the action's
   contextual guards say "not applicable right now" (e.g. paPrevFrame when
   not in single-view mode, or paOpenInPlayer with no file), in which case
   the key falls through to the edit-focus fallback below rather than being
   silently swallowed — matching pre-refactor behaviour.}
  Action := FSettings.Hotkeys.Lookup(Key, Shift);
  if (Action <> paNone) and ExecuteHotkey(Action) then
    Key := 0;

  {Post-dispatch edit-focus fallback: any keystroke that the edit wasn't
   allowed to handle above AND wasn't consumed by a hotkey is mopped up
   here. Enter is allowed to commit the value; everything else reclaims
   form focus so TC's subclass sees subsequent keystrokes.}
  if (Key <> 0) and (GetFocus = FEditFrameCount.Handle) then
    case Key of
      VK_SHIFT, VK_CONTROL, VK_MENU:
        ; {Let modifier key-downs flow through naturally}
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
  {Suppress non-digit chars that slip through OnKeyDown (e.g. Shift+digit
   produces '!' etc.). Prevents the NumbersOnly balloon on the edit.}
  else if (GetFocus = FEditFrameCount.Handle) and not CharInSet(Key, ['0' .. '9', #8]) then
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
  {Do NOT call inherited. VCL's default WMSetFocus redirects focus to
   ActiveControl (a child). TC subclasses this window to catch N/P and
   other Lister hotkeys; that subclass only sees WM_KEYDOWN when THIS
   window has Win32 focus, not a child. Skipping inherited keeps focus
   on the form handle so TC's hotkey interception works.}
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

  {Configure scrollbox FIRST so ClientWidth/ClientHeight reflect scrollbar state}
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

  {Read viewport after scrollbar config}
  VW := FScrollBox.ClientWidth;
  VH := FScrollBox.ClientHeight;
  FFrameView.SetViewport(VW, VH);

  {Calculate column count for grid mode (use frozen base when zoomed)}
  if FFrameView.ViewMode = vmGrid then
  begin
    case FFrameView.ZoomMode of
      zmFitWindow:
        FFrameView.ColumnCount := FFrameView.CalcFitColumns(FFrameView.BaseW, FFrameView.BaseH);
      zmFitIfLarger:
        begin
          FitCols := FFrameView.CalcFitColumns(FFrameView.BaseW, FFrameView.BaseH);
          DefCols := FFrameView.DefaultColumnCount;
          FFrameView.ColumnCount := Max(FitCols, DefCols);
        end;
      else
        FFrameView.ColumnCount := 0;
    end;
  end
  else
    FFrameView.ColumnCount := 0;

  {RecalcSize sets Width/Height for all modes.
   Do NOT reset Left/Top here: the scrollbox manages child positioning
   via its scroll offset. Resetting Left=0 while Position>0 creates an
   inconsistency that breaks subsequent ScrollBy delta calculations.}
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
  if FModePopups[AMode] = nil then
    Exit;
  for I := 0 to FModePopups[AMode].Items.Count - 1 do
    FModePopups[AMode].Items[I].Checked := TZoomMode(FModePopups[AMode].Items[I].Tag) = AZoom;
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
    CM_SAVE_FRAME:
      FExporter.SaveSingleFrame(FFileName, FContextCellIndex);
    CM_SAVE_SELECTED:
      FExporter.SaveSelectedFrames(FFileName);
    CM_SAVE_COMBINED:
      FExporter.SaveCombinedFrame(FFileName);
    CM_SAVE_ALL:
      FExporter.SaveAllFrames(FFileName);
    CM_COPY_FRAME:
      FExporter.CopyFrameToClipboard(FContextCellIndex);
    CM_COPY_ALL:
      FExporter.CopyAllToClipboard;
    CM_SELECT_ALL:
      FFrameView.SelectAll;
    CM_DESELECT_ALL:
      FFrameView.DeselectAll;
    CM_REFRESH:
      RefreshExtraction;
    CM_SETTINGS:
      ShowSettings;
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
  HasFrames := Assigned(FFrameView) and FFrameView.HasLoadedCells;
  for I := 0 to High(FToolbarButtons) do
    case FToolbarButtons[I].Tag of
      CM_SETTINGS:
        FToolbarButtons[I].Enabled := True;
      else
        FToolbarButtons[I].Enabled := HasFrames;
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
  {Uncheck all siblings, check this one}
  for I := 0 to MI.Parent.Count - 1 do
    MI.Parent.Items[I].Checked := False;
  MI.Checked := True;

  FFrameView.ZoomMode := TZoomMode(MI.Tag);
  UpdateFrameViewSize;

  {Persist user preference}
  FSettings.ZoomMode := FFrameView.ZoomMode;
  FSettings.Save;
end;

procedure TPluginForm.WndProc(var Message: TMessage);
var
  Key: Word;
  Shift: TShiftState;
begin
  case Message.Msg of
    WM_DEFERRED_INIT:
      begin
        SetWindowSubclass(Handle, @FormSubclassProc, FORM_SUBCLASS_ID, DWORD_PTR(Self));
        Exit;
      end;
    WM_PLUGIN_FKEY:
      begin
        Key := Message.wParam;
        Shift := [];
        if (Message.lParam and FKEY_LPARAM_SHIFT) <> 0 then
          Include(Shift, ssShift);
        if (Message.lParam and FKEY_LPARAM_CTRL) <> 0 then
          Include(Shift, ssCtrl);
        if (Message.lParam and FKEY_LPARAM_ALT) <> 0 then
          Include(Shift, ssAlt);
        OnFormKeyDown(Self, Key, Shift);
        Exit;
      end;
  end;
  inherited;
  if csDestroying in ComponentState then
    Exit;
  {When any child control is clicked, reclaim focus for the form handle.
   TC subclasses this window to catch Lister hotkeys (N/P etc.); that
   subclass only sees WM_KEYDOWN when this window has Win32 focus.}
  if Message.Msg = WM_PARENTNOTIFY then
    case LOWORD(Message.wParam) of
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
  {VCL fires Resize during window creation, before CreateForPlugin finishes
   constructing sub-controls, so FFrameView may not exist yet}
  if not FUpdatingLayout and Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
  {Viewport width/height may have changed the MaxSide bucket; debounce and
   let the timer decide whether to refresh. ScheduleViewportRefresh is a
   no-op before the timer field is constructed, so calling during early
   VCL construction is safe.}
  if Assigned(FViewportRefreshTimer) then
    ScheduleViewportRefresh;
end;

function TPluginForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Msg: TWMMouseWheel;
begin
  {Ctrl+Wheel: continuous zoom}
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ZoomBy(ZOOM_IN_FACTOR)
    else
      ZoomBy(ZOOM_OUT_FACTOR);
    Result := True;
    Exit;
  end;

  {Forward to TFrameView so wheel logic lives in one place (WMMouseWheel).
   Guards needed: VCL fires DoMouseWheel before constructor finishes.}
  if Assigned(FFrameView) and Assigned(FScrollBox) and FScrollBox.Visible then
  begin
    ZeroMemory(@Msg, SizeOf(Msg));
    Msg.Msg := WM_MOUSEWHEEL;
    Msg.WheelDelta := WheelDelta;
    FFrameView.Perform(WM_MOUSEWHEEL, TMessage(Msg).wParam, TMessage(Msg).lParam);
    Result := True;
  end
  else
    Result := inherited;
end;

procedure TPluginForm.OnScrollBoxResize(Sender: TObject);
begin
  {Same VCL lifecycle guard as Resize: FFrameView may not exist yet}
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

  {Hit-test: which cell was right-clicked?}
  Pt := FFrameView.ScreenToClient(FContextMenu.PopupPoint);
  FContextCellIndex := FFrameView.CellIndexAt(Pt);
  HasClickedFrame := (FContextCellIndex >= 0) and (FFrameView.CellState(FContextCellIndex) = fcsLoaded);

  for I := 0 to FContextMenu.Items.Count - 1 do
  begin
    MI := FContextMenu.Items[I];
    case MI.Tag of
      CM_SAVE_FRAME:
        MI.Enabled := HasClickedFrame;
      CM_SAVE_COMBINED:
        MI.Enabled := HasFrames;
      CM_SAVE_ALL:
        MI.Enabled := HasFrames;
      CM_COPY_FRAME:
        MI.Enabled := HasClickedFrame;
      CM_COPY_ALL:
        MI.Enabled := HasFrames;
      CM_SAVE_SELECTED:
        begin
          SelCount := FFrameView.SelectedCount;
          MI.Visible := SelCount >= 2;
          if MI.Visible then
            MI.Caption := Format('Save selected (%d)...', [SelCount]);
        end;
      CM_SELECT_ALL:
        MI.Enabled := HasFrames;
      CM_DESELECT_ALL:
        MI.Enabled := FFrameView.SelectedCount > 0;
      CM_REFRESH:
        MI.Enabled := HasFrames;
      CM_SETTINGS:
        ; {always enabled}
    end;
  end;
end;

procedure TPluginForm.OnContextMenuClick(Sender: TObject);
begin
  DispatchCommand(TMenuItem(Sender).Tag);
end;

procedure TPluginForm.OnAnimTimer(Sender: TObject);
begin
  {Drain any frames that arrived since the last notification.
   Covers the case where PostMessage notifications miss the HWND.}
  if Assigned(FExtractCtrl) then
    FExtractCtrl.ProcessPendingFrames;
  {Timer fires during construction; FFrameView may not be ready yet}
  if Assigned(FFrameView) and FFrameView.Visible then
    FFrameView.AdvanceAnimation;
end;

procedure TPluginForm.OnFrameCountChange(Sender: TObject);
begin
  {VCL re-fires OnChange when a hidden TUpDown+TEdit pair becomes visible
   (handle recreation re-sends the position). Ignore if value unchanged.}
  if FUpDown.Position = FSettings.FramesCount then
    Exit;

  FSettings.FramesCount := FUpDown.Position;
  FSettings.Save;

  RefreshExtraction;
  {Status bar's frame-position cell reflects the new total immediately,
   before extraction finishes (which would also refresh it).}
  UpdateStatusBar;
end;

procedure TPluginForm.CommitSettingsChanges;
var
  Changes: TSettingsChanges;
begin
  FSettings.Save;
  ApplySettings;

  Changes := DetectSettingsChanges(FSettingsSnap, FSettings);

  {Refresh the rolling snapshot so the next Apply/OK only sees the delta
   since this commit. Done before the conditional side-effects below so
   the snapshot is stable even on the early-exit path}
  FSettingsSnap := TakeSettingsSnapshot(FSettings);

  {Recreate cache if cache settings changed}
  if scCacheChanged in Changes then
    FExtractCtrl.RecreateCache(FSettings.CacheEnabled, FSettings.CacheFolder, FSettings.CacheMaxSizeMB);

  {FFmpeg path changed: update and reload from scratch (LoadFile re-probes
   the video, which is needed when ffmpeg was previously missing)}
  if (scFFmpegPathChanged in Changes) and (FSettings.FFmpegExePath <> '') then
  begin
    FFFmpegPath := ExpandEnvVars(FSettings.FFmpegExePath);
    LoadFile(FFileName);
    Exit;
  end;

  {Re-extract if skip edges, scaled extraction, or keyframes settings changed}
  if (Changes * [scSkipEdgesChanged, scScaledExtractionChanged, scUseKeyframesChanged]) <> [] then
    RefreshExtraction;
end;

procedure TPluginForm.OnSettingsApply(Sender: TObject);
begin
  CommitSettingsChanges;
end;

procedure TPluginForm.ShowSettings;
begin
  FSettingsSnap := TakeSettingsSnapshot(FSettings);

  if not ShowSettingsDialog(FParentWnd, FSettings, FFFmpegPath, OnSettingsApply) then
    Exit;

  CommitSettingsChanges;
end;

procedure TPluginForm.NavigateToAdjacentFile(ADelta: Integer);
var
  Next: string;
begin
  if FQuickViewMode and FSettings.QVDisableNavigation then
    Exit;
  Next := FindAdjacentFile(FFileName, FSettings.ExtensionList, ADelta);
  if (Next <> '') and not SameText(Next, FFileName) then
    LoadFile(Next);
end;

procedure TPluginForm.RefreshExtraction;
begin
  if not FVideoInfo.IsValid then
    Exit;
  FExtractCtrl.Stop;
  FExtractCtrl.DrainPendingFrameMessages;
  FFrameView.ClearCells;
  SetupPlaceholders;
  StartExtraction(TBypassFrameCache.Create(FExtractCtrl.Cache));
end;

procedure TPluginForm.SoftRefreshExtraction;
begin
  {Like RefreshExtraction but keeps the current frames on screen: cells
   are NOT cleared, placeholders are NOT reset, and the cache is used
   normally so repeated grid<->single cycles hit cache entries from an
   earlier extraction at the same MaxSide. As new frames come in via
   OnFrameDelivered, TFrameView.SetFrame replaces the existing bitmap in
   place — the user just sees the image sharpen. Called from the debounce
   timer after a viewport-changing event settles.}
  if not FVideoInfo.IsValid then
    Exit;
  FExtractCtrl.Stop;
  FExtractCtrl.DrainPendingFrameMessages;
  StartExtraction(nil);
end;

procedure TPluginForm.ScheduleViewportRefresh;
begin
  {Kick (or re-kick) the debounce timer. Every viewport-changing event
   calls this; when the events stop arriving for VIEWPORT_REFRESH_DEBOUNCE_MS
   the timer fires OnViewportRefreshTimer, which does the actual comparison
   and (maybe) refresh. No-op when the user disabled the feature.}
  if FSettings = nil then
    Exit;
  if not FSettings.AutoRefreshOnViewportChange then
    Exit;
  {Restart the countdown by toggling Enabled — setting False then True
   resets the internal timer.}
  FViewportRefreshTimer.Enabled := False;
  FViewportRefreshTimer.Enabled := True;
end;

procedure TPluginForm.OnViewportRefreshTimer(Sender: TObject);
var
  NewMaxSide: Integer;
  ViewportFrames: Integer;
begin
  FViewportRefreshTimer.Enabled := False;
  {All of these can become false between the event that kicked the timer
   and the timer firing (user closed, disabled the feature, etc.), so
   re-check every precondition.}
  if FSettings = nil then Exit;
  if not FSettings.AutoRefreshOnViewportChange then Exit;
  if not FSettings.ScaledExtraction then Exit;
  if not FVideoInfo.IsValid then Exit;
  if FFileName = '' then Exit;
  if Length(FOffsets) = 0 then Exit;

  ViewportFrames := ViewportFrameCount(FFrameView.ViewMode, Length(FOffsets));
  NewMaxSide := CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight,
    ViewportFrames, FFrameView.AspectRatio, FVideoInfo.Width, FVideoInfo.Height,
    FSettings.MinFrameSide, FSettings.MaxFrameSide);

  {Same size bucket as the live extraction (viewport only jittered within
   one SCALE_BUCKET, or the view mode didn't actually change the divisor).
   Nothing to do — any cached frames are already at the right resolution.}
  if NewMaxSide = FLastExtractionMaxSide then
    Exit;

  SoftRefreshExtraction;
end;

end.
