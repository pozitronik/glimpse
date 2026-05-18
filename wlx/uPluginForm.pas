{Main plugin form: toolbar, frame display, and extraction coordination.
 The form is parented to TC's Lister window.}
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Clipbrd, Vcl.Buttons, Vcl.ImgList,
  uTypes, uStatusBarLayout, uSettings, uHotkeys, uHotkeysVcl, uPluginAppearance, uFrameOffsets, uFFmpegExe, uVideoInfo, uCache, uWlxAPI, uFrameNotificationSink,
  uZoomController, uViewModeLogic,
  uExtractionPlanner, uToolbarLayout, uFrameView, uViewModeLayout, uExtractionWorker,
  uFrameExtractor, uFrameExport, uExtractionController, uProbeCache,
  uSaveResolutionExtractor,
  uStatusBarTokens, uStatusBarTemplate, uStatusBarFormatters, uStatusBarRenderer;

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
    FBtnTimecode: TSpeedButton;
    FToolbarButtons: array of TButton;
    FBtnHamburger: TButton;
    FHamburgerMenu: TPopupMenu;
    {Drop-down attached to the Refresh toolbar button: offers
     "Refresh" (same as primary click) and "Shuffle" items so the
     random-extraction trigger has a visible affordance, mirroring the
     view-mode split-button pattern.}
    FRefreshPopup: TPopupMenu;
    FSaveViewPopup: TPopupMenu;
    FCopyViewPopup: TPopupMenu;
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
    {Owns parsing of the user template, panel build-out, and per-panel
     hint lookup. Lives for the form's lifetime; ApplyTemplate /
     SetFont / Refresh drive it. The bar's panels are written through
     this object exclusively.}
    FStatusBarRenderer: TStatusBarRenderer;
    {Snapshot of plugin state, refreshed once per UpdateStatusBar call.
     The renderer's resolver lambda reads this rather than hitting
     collaborators per-token, so a Refresh emits a coherent view of
     state instead of racing changes mid-iteration.}
    FCachedStatusBarValues: TStatusBarValues;
    {Content}
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    {Export}
    FExporter: TFrameExporter;
    {Cell index under the cursor at the moment the right-click context
     menu opens; -1 when the cursor wasn't over a cell. Captured in
     OnContextMenuPopup and consumed by OnContextMenuClick to give the
     "Copy frame" item context-cell semantics (the item copies the cell
     the user right-clicked, not the selected one). Other entry points
     for Copy frame (toolbar button, hotkey, TC lc_Copy) deliberately do
     not pass a context cell, so they keep the selection-first rule that
     PickActionCell falls back to.}
    FContextCellIndex: Integer;
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
    {True when FOffsets currently holds randomly-picked positions (either
     because Settings.RandomExtraction was on at build time, or the user
     invoked Shuffle as a one-shot override). Drives cache-override
     selection so CacheRandomFrames=False suppresses cache writes only
     for the random path, leaving deterministic extractions cacheable.}
    FCurrentExtractionIsRandom: Boolean;
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
    procedure OnHamburgerActionClick(Sender: TObject);
    procedure CreateFrameView;
    procedure OnFrameViewCtrlWheel(Sender: TObject; AWheelDelta: Integer);
    procedure CreateStatusBar;
    procedure UpdateStatusBar;
    {Snapshot every datum the status-bar formatter consumes. Reads
     FFileName / FSettings / FOffsets / FFrameView / FVideoInfo /
     FExporter / FLoadTimeStr; safe to call any time, never mutates.}
    procedure BuildStatusBarValues(out AValues: TStatusBarValues);
    {Pushes the four status-bar settings (template, font name + size,
     auto-width-live flag) into the renderer. Triggers a re-parse +
     re-measure + Refresh so panel widths and panel set track the new
     template / font on the next paint cycle. No-op when the renderer
     is not yet constructed (defensive — settings can be loaded before
     CreateStatusBar in some lifecycle paths).}
    procedure ApplyStatusBarSettings;
    {Named replacements for the three anonymous lambdas CreateStatusBar
     used to construct inline. Same behaviour as the inline closures;
     extracting them lets the renderer be owned by the form (TComponent)
     without losing readability — the Self-capture is explicit at the
     method-name site instead of hidden in a lambda body.}
    function ResolveStatusBarToken(const AToken: TStatusBarToken): string;
    function GetStatusBarPanelHint(APanelIndex: Integer): string;
    function GetStatusBarPanelKind(APanelIndex: Integer): TStatusBarTokenKind;
    {Resolves the pixel height for the status bar given the current
     font's TextHeight, the persisted StatusBarHeight + apply-mode
     settings, and the bar's CurrentPPI. Auto path returns
     TextHeight + 6 px padding; explicit path scales the saved logical
     value and silently bumps below-font values so text never clips.}
    function ResolveStatusBarHeight(ATextHeight: Integer): Integer;
    {Double-click handler: when the cursor is over a panel whose backing
     token is interactive (Save / Copy predicted-dimension), flip the
     corresponding persisted *AtLiveResolution toggle, save settings,
     and refresh the bar so the new prediction is visible immediately.
     Non-interactive panels swallow the double-click silently. Single
     clicks (without Ctrl) are NOT bound — they would race the flip in
     the double-click sequence (OnClick fires before OnDblClick).}
    procedure OnStatusBarDblClick(Sender: TObject);
    {Mouse-up handler reserved for Ctrl+Click: copies the panel text
     under the cursor to the clipboard. Inspecting Shift here (instead
     of OnClick) gives access to the modifier state without a separate
     GetKeyState round-trip; firing on MouseUp keeps the gesture cheap
     and idempotent in the double-click case.}
    procedure OnStatusBarMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure CreateContextMenu;
    procedure CreateErrorLabel;
    function CreateModePopup(AMode: TViewMode): TPopupMenu;
    {Builds the dropdown menu attached to the Refresh toolbar button:
     "Refresh" item (same as primary click) and "Shuffle" (random
     positions). Both items dispatch through the existing OnContextMenuClick
     so the keyboard hotkeys stay the single source of truth.}
    function CreateRefreshPopup: TPopupMenu;
    function CreateSaveViewPopup: TPopupMenu;
    function CreateCopyViewPopup: TPopupMenu;
    {Walks the items of the given popup and rewrites Save/Copy view
     dropdown captions with their current predicted-size suffix. Called
     from each popup's OnPopup so the suffix tracks live cell size,
     view-mode changes, and CombinedMaxSide edits without per-event
     wiring.}
    procedure UpdateResolutionMenuLabels(AMenu: TPopupMenu);
    procedure OnViewDropdownPopup(Sender: TObject);
    {Returns the zoom mode that should actually be applied for the
     current FFrameView.ViewMode. View modes that have no zoom-selector
     popup (vmGrid, vmSmartGrid - see CreateModePopup) are always-fit
     by design, so any requested zoom is clamped to zmFitWindow. Use
     this anywhere external state (persisted settings, TC's lister
     params) tries to push a zoom mode onto FFrameView, otherwise the
     unsupported value sticks and the renderer enters a degenerate
     branch (e.g. vmGrid+zmActual+NativeW>=BaseW collapses to 1 column,
     visually identical to vmScroll).}
    function ResolveZoomModeForCurrentView(ARequestedZoom: TZoomMode): TZoomMode;
    procedure ApplySettings;
    procedure ApplyVideoDimsToFrameView;
    procedure SetupPlaceholders;
    procedure ShowError(const AMessage: string);
    procedure HideError;
    procedure UpdateFrameViewSize;
    procedure UpdateViewModeButtons;
    procedure SyncZoomMenuChecks(AMode: TViewMode; AZoom: TZoomMode);
    procedure UpdateTimecodeButton;
    procedure UpdateToolbarButtons;
    {True only when the loaded set is stable (no placeholders) and at
     least one cell is actually loaded. Save / copy entry points (toolbar,
     context menu, hotkeys) gate on this so they cannot fire against an
     in-flight extraction or an empty / all-errored result.}
    function CanExportFrames: Boolean;
    procedure OnToolbarButtonClick(Sender: TObject);
    procedure ActivateMode(AMode: TViewMode);
    procedure ZoomBy(AFactor: Double);
    procedure ResetZoom;
    procedure SwitchOrCycleMode(AKey: Word);
    procedure ShowSettings;
    procedure CommitSettingsChanges;
    procedure NavigateToAdjacentFile(ADelta: Integer);
    procedure RefreshExtraction;
    procedure SoftRefreshExtraction;
    procedure ScheduleViewportRefresh;
    procedure OnViewportRefreshTimer(Sender: TObject);
    {Builds FOffsets from the current FVideoInfo.Duration / frame count /
     skip-edges. AForceRandom = True overrides Settings.RandomExtraction
     for the current build only (used by Shuffle); otherwise the
     setting decides between deterministic midpoints and per-slice
     random picks. Sets FCurrentExtractionIsRandom accordingly.}
    procedure RebuildFrameOffsets(AForceRandom: Boolean = False);
    {Cache override appropriate for the current extraction. Returns
     TReadOnlyFrameCache when extracting random offsets with
     CacheRandomFrames disabled (read existing entries, drop new
     writes); nil otherwise so the controller's normal cache applies.}
    function RandomCacheOverride: IFrameCache;
    {Re-rolls FOffsets with random positions and starts a fresh
     extraction immediately. Independent of Settings.RandomExtraction:
     when "Start from random positions" is off, this is a one-shot
     override that lasts until the next event triggering a deterministic
     rebuild (file reload, frame-count change, settings re-apply).}
    procedure ShuffleExtraction;
    procedure StartExtraction(const ACacheOverride: IFrameCache = nil);
    {Wraps an exporter save/copy action with re-extraction at save
     resolution when the live-resolution toggle is off and the live
     cells are not already at the desired size. Delegates the heavy
     lifting (cache lookup + ffmpeg) to TSaveResolutionExtractor; this
     method only owns the policy gate, the override-frame plumbing on
     FExporter, and the bitmap-cleanup. AIndices lists cells the action
     will actually consume, so re-extraction is scoped to what is needed.}
    procedure WithReExtract(const AIndices: TArray<Integer>; AAction: TProc);
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
    {Common gate+dispatch shared by every Save/Copy hotkey branch in
     ExecuteHotkey. Returns False (without dispatching) when extraction
     is in flight so the caller falls through to TC's same-key shortcut
     instead of acting on an unstable cell set.}
    function TryExecuteExportCommand(ACommandTag: Integer): Boolean;
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
    procedure ApplyListerParams(AParams: Integer);
    {Single entrypoint for save/copy/select/refresh/settings commands.
     Hotkey actions, the right-click context menu, the toolbar buttons,
     and the TC lc_Copy lister command all route through here so the
     wrapping (WithReExtract on save/copy actions) lives in exactly one
     place. ATag accepts the CM_* constants from uToolbarLayout.}
    {Routes a tagged action to its implementation. The singular
     Save / Copy frame branches consult PickActionCell, which picks the
     selected cell (or falls back to the focused / first cell) — every
     entry path (toolbar, context menu, hotkey, TC lc_Copy) shares this
     rule so the right-click position never overrides the visible
     selection.}
    procedure DispatchCommand(ATag: Integer; AContextCellIndex: Integer = -1);
  end;

implementation

uses
  System.IOUtils, Winapi.ShellAPI,
  uSettingsDlg, uFileNavigator, uDebugLog, uPathExpand, uBannerInfo, uTimecodeOverlay,
  uProgressModalForm,
  uPlatformDetect, uDefaults;

type
  {Per-panel hint provider used by TGlimpseStatusBar. APanelIndex is the
   0-based index of the panel under the cursor, or -1 when the cursor is
   past the last panel.}
  TStatusBarHintProvider = reference to function(APanelIndex: Integer): string;

  {Callback the host form supplies so the status bar can ask "what kind
   of token does the panel at APanelIndex render?" without coupling the
   subclass to the renderer. Returns tkUnknown for unmapped indices,
   which the cursor logic treats as "not interactive".}
  TStatusBarPanelKindProvider = reference to function(APanelIndex: Integer): TStatusBarTokenKind;

  {TStatusBar specialisation that surfaces a per-panel hint instead of a
   single per-control Hint. Drives the hint mechanism via CMHintShow's
   CursorRect: setting CursorRect to the panel under the cursor makes the
   VCL re-issue CMHintShow when the cursor crosses into a different panel,
   which in turn lets us swap HintStr without the brittle
   "set Hint + CancelHint" dance that does not always re-pop on the same
   control. Also intercepts WM_SETCURSOR to paint the hand cursor over
   panels whose backing token kind is interactive (Save / Copy dim).}
  TGlimpseStatusBar = class(TStatusBar)
  private
    FOnGetPanelHint: TStatusBarHintProvider;
    FOnQueryPanelKind: TStatusBarPanelKindProvider;
    procedure CMHintShow(var Msg: TCMHintShow); message CM_HINTSHOW;
    procedure WMSetCursor(var Msg: TWMSetCursor); message WM_SETCURSOR;
  public
    property OnGetPanelHint: TStatusBarHintProvider read FOnGetPanelHint write FOnGetPanelHint;
    property OnQueryPanelKind: TStatusBarPanelKindProvider read FOnQueryPanelKind write FOnQueryPanelKind;
  end;

{Walks AStatusBar's panels left-to-right; returns the index of the panel
 under the X coord, or -1 when AX is past the last panel. APanelLeft is
 set to the left edge of the matched panel; when -1 (past-end) it is set
 to the right edge of the last panel so callers can compose a "trailing
 dead zone" rect. Returns -1 for an empty status bar (APanelLeft=0).
 Centralises the arithmetic shared by OnStatusBarDblClick and the per-
 panel hint dispatch in TGlimpseStatusBar.CMHintShow.}
function StatusBarPanelHitTest(AStatusBar: TStatusBar; AX: Integer; out APanelLeft: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  APanelLeft := 0;
  for I := 0 to AStatusBar.Panels.Count - 1 do
  begin
    if AX < APanelLeft + AStatusBar.Panels[I].Width then
      Exit(I);
    Inc(APanelLeft, AStatusBar.Panels[I].Width);
  end;
end;

procedure TGlimpseStatusBar.CMHintShow(var Msg: TCMHintShow);
var
  PanelLeft, HitIdx: Integer;
  HintText: string;
begin
  if not Assigned(FOnGetPanelHint) then
  begin
    inherited;
    Exit;
  end;

  HitIdx := StatusBarPanelHitTest(Self, Msg.HintInfo.CursorPos.X, PanelLeft);

  HintText := FOnGetPanelHint(HitIdx);
  if HintText = '' then
  begin
    {No hint for this region. Suppress the popup but still set a tight
     CursorRect so the next cross-panel move re-queries us.}
    Msg.Result := 1;
  end else begin
    Msg.HintInfo.HintStr := HintText;
    Msg.Result := 0;
  end;

  if HitIdx >= 0 then
    Msg.HintInfo.CursorRect := Rect(PanelLeft, 0, PanelLeft + Panels[HitIdx].Width, Height)
  else
    {Past the last panel: cursor rect is the trailing dead zone, so we
     stay quiet until the cursor enters a real panel.}
    Msg.HintInfo.CursorRect := Rect(PanelLeft, 0, ClientWidth, Height);
end;

procedure TGlimpseStatusBar.WMSetCursor(var Msg: TWMSetCursor);
var
  Pt: TPoint;
  PanelLeft, HitIdx: Integer;
  Kind: TStatusBarTokenKind;
begin
  {Paint the hand cursor over panels whose backing token is interactive.
   Only intercept hits on the bar's client area — child controls (the
   embedded TProgressBar) keep their default cursor. We can't rely on
   Cursor := crHandPoint at the control level because that would apply
   the cursor uniformly across every panel.}
  if (Msg.HitTest = HTCLIENT) and Assigned(FOnQueryPanelKind) then
  begin
    GetCursorPos(Pt);
    Pt := ScreenToClient(Pt);
    HitIdx := StatusBarPanelHitTest(Self, Pt.X, PanelLeft);
    if HitIdx >= 0 then
    begin
      Kind := FOnQueryPanelKind(HitIdx);
      if Kind in [tkSaveDimension, tkCopyDimension] then
      begin
        Winapi.Windows.SetCursor(LoadCursor(0, IDC_HAND));
        Msg.Result := 1;
        Exit;
      end;
    end;
  end;
  inherited;
end;

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

var
  {Subsystem logger; closure captures the 'Form' tag once at unit
   initialization.}
  FormLog: TProc<string>;

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
    VK_TAB, VK_SHIFT, VK_CONTROL, VK_MENU, VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU:
      Exit(True);
  end;
  {Alt+F4 is a system close shortcut — let the OS deliver its SC_CLOSE.}
  if (AKey = VK_F4) and (GetKeyState(VK_MENU) < 0) then
    Exit(True);
  Result := False;
end;

{Packs the live modifier-key state into a single LPARAM value so the
 repost target can rebuild TShiftState without another GetKeyState call.}
function PackShiftIntoLParam: lParam;
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
  {Upper limit for the frame-count spin edit. Data-validation constant,
   not a layout pixel — stays in uPluginForm because FUpDown.Max is the
   only consumer and the value is product policy, not visual styling.}
  MAX_FRAME_COUNT = 99;

  {Status bar panel widths are now driven by the template engine in
   uStatusBarRenderer: each token's "width=auto" measurement uses the
   sample text registered in uStatusBarTokens.StatusBarTokenSampleText,
   and explicit "width=N" overrides them per token in the user's
   template (DEF_STATUSBAR_TEMPLATE for the default layout).}

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
  FContextCellIndex := -1;
  BorderStyle := bsNone;
  KeyPreview := True;
  {Form-level ShowHint cascades through ParentShowHint (default True) so every
   toolbar button picks up its Hint without needing per-control opt-in.}
  ShowHint := True;
  {Keep tooltips visible as long as the cursor stays over the control.
   Application is per-DLL, so this only affects hints shown by our forms;
   TC's own UI uses its own (non-VCL) tooltip mechanism.}
  Application.HintHidePause := MaxInt;
  OnKeyDown := OnFormKeyDown;
  OnKeyPress := OnFormKeyPress;

  {Seed the global Random once per plugin instance. CalculateRandomFrameOffsets
   reads from this RNG; without seeding, every plugin lifecycle would emit the
   same "random" sequence, defeating the user's expectation of fresh frames
   on each open / Shuffle.}
  Randomize;

  FSettings := ASettings;
  FFFmpegPath := AFFmpegPath;

  Winapi.Windows.GetClientRect(AParentWin, R);
  SetBounds(0, 0, R.Right, R.Bottom);

  {Quick View panel is a child window; Lister is a top-level window.
   Must be set before ApplySettings so QV defaults take effect.
   Heuristic: TC's WLX SDK does not expose a "quick view vs lister"
   flag, so we infer from the parent window style. If a future TC
   release changes its window hierarchy this detection would silently
   misclassify - there is no better signal at this layer, and the
   misclassification only affects which user-facing defaults apply,
   not correctness of frame rendering.}
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

  {GDebugLogPath is set once at TC startup by ListSetDefaultParams (which
   honours [debug] LogEnabled in release builds and forces the log on in
   DEBUG builds). Re-applying it here would override that decision per
   file open, which is unwanted: the user's toggle is supposed to be
   process-wide, and the DEBUG-build path is supposed to stay verbose
   regardless of any user setting.}

  FormLog(Format('CreateForPlugin: file=%s handle=$%s', [AFileName, IntToHex(Handle)]));

  FProbeCache := TProbeCache.Create(DefaultProbeCacheDir);

  {Create extraction controller with appropriate cache. The
   TWindowMessageSink wraps the form's HWND so worker threads can post
   WM_FRAME_READY / WM_EXTRACTION_DONE without needing the HWND directly.}
  if FSettings.CacheEnabled then
    FExtractCtrl := TExtractionController.Create(TWindowMessageSink.Create(Handle),
      TFrameCache.Create(EffectiveCacheFolder(FSettings.CacheFolder), FSettings.CacheMaxSizeMB))
  else
    FExtractCtrl := TExtractionController.Create(TWindowMessageSink.Create(Handle),
      TNullFrameCache.Create);
  FExtractCtrl.OnFrameDelivered := OnFrameDelivered;
  FExtractCtrl.OnProgress := OnExtractionProgress;

  FExporter := TFrameExporter.Create(FFrameView, FSettings);
  {Run the file-reference clipboard PNG encode inside a modal "please
   wait" dialog parented to this form. The modal blocks UI re-entry,
   navigation, and accidental re-clicks while the worker thread runs.
   Cancellation detaches the thread (it cleans up after itself). See
   uProgressModalForm for the thread-completion mechanism (PostMessage
   to a value-captured HWND, no polling timer).}
  FExporter.OnAsyncTaskRun :=
    function(AThread: TThread; const AText: string): Boolean
    begin
      {Surface the work on BOTH the in-form status-bar progress
       widget AND the modal dialog: the status bar marquee gives a
       visual cue that the lister itself is busy (the modal blocks
       form input but doesn't paint the status bar), the modal
       provides the Cancel button and the central indication.}
      FProgressBar.Style := pbstMarquee;
      FProgressBar.MarqueeInterval := 30;
      ShowProgress(AText);
      try
        Result := RunWithProgress(Self, AThread, AText);
      finally
        HideProgress;
        FProgressBar.Style := pbstNormal;
      end;
    end;

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
  {FStatusBarRenderer is owned by Self (step 59) — inherited TForm.Destroy
   iterates FComponents and frees it. The resolver method-reference
   captures Self; release happens during the inherited pass while
   Self's fields are still memory-valid.}
  inherited;
end;

procedure TPluginForm.CreateToolbar;
const
  TB_PAD = 4; {Vertical padding above and below controls}
  CTRL_GAP = 8; {Gap between control groups}
  BTN_GAP = 2; {Gap between adjacent buttons in a group}
  BTN_PAD = 16; {Horizontal text padding inside button (both sides)}
  {Extra horizontal width reserved for the dropdown arrow on the
   Refresh split button. The view-mode buttons use the same allowance
   by virtue of the IDX_ICON_ARROW glyph; Refresh has no glyph so the
   space is added explicitly to match the visual weight.}
  REFRESH_DROPDOWN_EXTRA = 14;
  {Save view / Copy view captions are longer than Refresh, so the
   bsSplitButton arrow pinches the rendered text when only
   REFRESH_DROPDOWN_EXTRA is reserved. Add a small buffer on top so the
   full caption stays visible.}
  VIEW_DROPDOWN_EXTRA = REFRESH_DROPDOWN_EXTRA + 6;
  SPLIT_ARROW_W = 20; {Extra width for split button dropdown arrow}
  PB_H = 16; {Progress bar height}
  ICON_W = 16; {Toolbar icon width}
  ICON_GAP = 4; {Space between icon and caption on icon-bearing buttons}
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
  FEditFrameCount.Hint := 'Number of frames to extract from the video.';

  FUpDown := TUpDown.Create(FToolbar);
  FUpDown.Parent := FToolbar;
  FUpDown.Associate := FEditFrameCount;
  FUpDown.Min := 1;
  FUpDown.Max := MAX_FRAME_COUNT;
  FUpDown.Hint := 'Number of frames to extract from the video.';
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
     caption. The split-arrow reservation is skipped on legacy Windows
     (XP/2003) because BS_SPLITBUTTON does not render there — keeping
     the extra width would leave a dead gap between the caption and the
     iaRight icon.}
    BW := Canvas.TextWidth(MODE_CAPTIONS[VM]) + BTN_PAD;
    if (FModePopups[VM] <> nil) and not IsLegacyWindows then
      Inc(BW, SPLIT_ARROW_W);
    if VM in [vmScroll, vmFilmstrip] then
      Inc(BW, ICON_W + ICON_GAP);

    FModeButtons[VM].SetBounds(X, CY, BW, CtrlH);
    FModeButtons[VM].Caption := MODE_CAPTIONS[VM];
    FModeButtons[VM].Hint := MODE_HINTS[VM];
    FModeButtons[VM].Tag := Ord(VM);
    FModeButtons[VM].TabOrder := TabIdx;
    FModeButtons[VM].OnClick := OnModeButtonClick;

    if MODE_GLYPH_INDEX[VM] >= 0 then
    begin
      FModeButtons[VM].Images := FToolbarImages;
      FModeButtons[VM].ImageIndex := MODE_GLYPH_INDEX[VM];
      {Qualified — TIconArrangement (Vcl.ComCtrls) also defines iaRight.
       Icon sits to the right of the caption, matching the original ↕/↔
       glyph position.}
      FModeButtons[VM].ImageAlignment := Vcl.StdCtrls.iaRight;
    end;

    {Legacy Windows pulls the iaRight icon flush against the button's
     right edge; modern Windows leaves a small visual margin courtesy of
     the themed button paint. Add the missing inset manually on XP so the
     glyph doesn't touch the border.}
    if (VM in [vmScroll, vmFilmstrip]) and IsLegacyWindows then
      FModeButtons[VM].ImageMargins.Right := 2;

    {Split button: click activates mode, arrow shows submodes. PopupMenu
     duplicates the same menu on right-click for every OS so the submodes
     stay reachable on legacy Windows (where the split arrow does not
     render) and gives modern users a discoverable alternative to the
     small arrow glyph.}
    if FModePopups[VM] <> nil then
    begin
      FModeButtons[VM].Style := bsSplitButton;
      FModeButtons[VM].DropDownMenu := FModePopups[VM];
      FModeButtons[VM].PopupMenu := FModePopups[VM];
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
  FBtnTimecode.Hint := 'Toggle timecode overlay on each frame (F2).';
  FBtnTimecode.GroupIndex := 1;
  FBtnTimecode.AllowAllUp := True;
  FBtnTimecode.OnClick := OnTimecodeButtonClick;
  FElementRights[ELEM_TIMECODE_INDEX] := X + BW;
  Inc(X, BW + CTRL_GAP);

  {Action buttons matching context menu (except selection-dependent commands).
   The Refresh button is upgraded to a split button so the dropdown
   exposes Shuffle as a peer action (primary click stays Refresh).}
  SetLength(FToolbarButtons, 0);
  FRefreshPopup := nil;
  FSaveViewPopup := nil;
  FCopyViewPopup := nil;
  for I := 0 to High(TB_ACTIONS) do
  begin
    Btn := TButton.Create(FToolbar);
    Btn.Parent := FToolbar;
    BW := Canvas.TextWidth(TB_ACTIONS[I].Caption) + BTN_PAD;
    {Skip the dropdown-arrow reservation on legacy Windows for the same
     reason as the mode buttons above: BS_SPLITBUTTON does not render on
     XP/2003 and the spare width would leave a dead gap.}
    if not IsLegacyWindows then
      case TB_ACTIONS[I].Tag of
        CM_REFRESH:
          Inc(BW, REFRESH_DROPDOWN_EXTRA);
        CM_SAVE_VIEW, CM_COPY_VIEW:
          Inc(BW, VIEW_DROPDOWN_EXTRA);
      end;
    Btn.SetBounds(X, CY, BW, CtrlH);
    Btn.Caption := TB_ACTIONS[I].Caption;
    Btn.Hint := TB_ACTIONS[I].Hint;
    Btn.Tag := TB_ACTIONS[I].Tag;
    Btn.Enabled := False;
    Btn.OnClick := OnToolbarButtonClick;
    if TB_ACTIONS[I].Tag = CM_REFRESH then
    begin
      FRefreshPopup := CreateRefreshPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := FRefreshPopup;
      {Right-click pops the same Refresh / Shuffle menu — see the mode
       buttons above for why this duplicates DropDownMenu.}
      Btn.PopupMenu := FRefreshPopup;
    end
    else if TB_ACTIONS[I].Tag = CM_SAVE_VIEW then
    begin
      {Save view dropdown: explicit "...at view resolution" and "...at
       native size" entry points. On modern Windows the file dialog's
       checkbox is still authoritative; on legacy Windows (no checkbox)
       this is the only way to pick the resolution per save without
       opening the settings dialog first.}
      FSaveViewPopup := CreateSaveViewPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := FSaveViewPopup;
      Btn.PopupMenu := FSaveViewPopup;
    end
    else if TB_ACTIONS[I].Tag = CM_COPY_VIEW then
    begin
      {Copy view dropdown: same idea as Save view but commits immediately
       (no dialog), so the variants are the only way to override the
       persisted SaveAtLiveResolution setting for a single Copy view.
       The native variant also re-extracts at native resolution before
       publishing to the clipboard, which the default Copy view used to
       skip - the dropdown thus also fixes the long-standing "Copy view
       at native resolution copies low-res cells" surprise.}
      FCopyViewPopup := CreateCopyViewPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := FCopyViewPopup;
      Btn.PopupMenu := FCopyViewPopup;
    end;
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
  FBtnHamburger.Hint := 'More commands (toolbar buttons that did not fit).';
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
    State.ModeImageIndex[VM] := MODE_GLYPH_INDEX[VM];
  end;

  PopulateHamburgerMenu(FHamburgerMenu, State, OnHamburgerModeClick, OnHamburgerZoomClick, OnTimecodeButtonClick, OnHamburgerActionClick);
  UpdateResolutionMenuLabels(FHamburgerMenu);
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

function TPluginForm.CreateRefreshPopup: TPopupMenu;
var
  MI: TMenuItem;
begin
  Result := TPopupMenu.Create(Self);

  MI := TMenuItem.Create(Result);
  MI.Caption := 'Refresh'#9'R';
  MI.Tag := CM_REFRESH;
  MI.OnClick := OnContextMenuClick;
  Result.Items.Add(MI);

  MI := TMenuItem.Create(Result);
  MI.Caption := 'Shuffle'#9'Ctrl+R';
  MI.Tag := CM_SHUFFLE;
  MI.OnClick := OnContextMenuClick;
  Result.Items.Add(MI);
end;

function TPluginForm.CreateSaveViewPopup: TPopupMenu;
begin
  {Two explicit-resolution Save view variants. Their job is mainly to
   give legacy Windows users a way to pick the resolution at all (the
   modern file dialog's checkbox is unavailable on XP), but they also
   work as a faster path on modern Windows: one click chooses the
   resolution and opens the dialog with that as the seed. The item set
   lives in uToolbarLayout.SAVE_VIEW_VARIANTS so the hamburger overflow
   and the resolution-suffix updater stay in lockstep with this menu.}
  Result := BuildViewVariantsMenu(Self, SAVE_VIEW_VARIANTS,
    OnViewDropdownPopup, OnContextMenuClick);
end;

function TPluginForm.CreateCopyViewPopup: TPopupMenu;
begin
  {Mirror of CreateSaveViewPopup. No dialog follows so the COPY captions
   omit the trailing ellipsis - the action commits immediately.}
  Result := BuildViewVariantsMenu(Self, COPY_VIEW_VARIANTS,
    OnViewDropdownPopup, OnContextMenuClick);
end;

procedure TPluginForm.UpdateResolutionMenuLabels(AMenu: TPopupMenu);
var
  I: Integer;
  MI: TMenuItem;
  Def: TViewVariantDef;
  PersistedLive: Boolean;
  Chords: THotkeyChordArray;
begin
  if AMenu = nil then
    Exit;
  for I := 0 to AMenu.Items.Count - 1 do
  begin
    MI := AMenu.Items[I];
    if not FindViewVariantByTag(MI.Tag, Def) then
      Continue;
    if FExporter <> nil then
      MI.Caption := Def.Caption + FExporter.FormatPredictedSize(Def.ForceLive)
    else
      MI.Caption := Def.Caption;
    {Mark the item that matches the persisted setting for the corresponding
     surface as the current default with a radio bullet. Save items track
     SaveAtLiveResolution, copy items track CopyAtLiveResolution — the two
     settings can diverge so the bullets must too. RadioItem groups
     Live/Native into a mutually-exclusive pair so only one bullet shows
     per pair.}
    if Def.IsCopy then
      PersistedLive := FSettings.CopyAtLiveResolution
    else
      PersistedLive := FSettings.SaveAtLiveResolution;
    MI.RadioItem := True;
    MI.Checked := Def.ForceLive = PersistedLive;
    {Mirror the first configured chord (THotkeyBindings allows several
     per action; the first one is the canonical "primary") onto the menu
     item so VCL renders it in the standard "Caption    Ctrl+Shift+L"
     two-column layout. Unbound action -> ShortCut = 0 -> VCL hides the
     suffix entirely.}
    Chords := FSettings.Hotkeys.Get(Def.Action);
    if Length(Chords) > 0 then
      MI.ShortCut := ToShortCut(Chords[0])
    else
      MI.ShortCut := 0;
  end;
end;

procedure TPluginForm.OnViewDropdownPopup(Sender: TObject);
begin
  UpdateResolutionMenuLabels(Sender as TPopupMenu);
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
  AddItem('Save view...'#9'Ctrl+Shift+S', CM_SAVE_VIEW);
  AddItem('Save frames...'#9'Ctrl+Alt+Shift+S', CM_SAVE_FRAMES);
  AddSeparator;
  AddItem('Copy frame'#9'Ctrl+C', CM_COPY_FRAME);
  AddItem('Copy view'#9'Ctrl+Shift+C', CM_COPY_VIEW);
  AddSeparator;
  AddItem('Select all'#9'Ctrl+A', CM_SELECT_ALL);
  AddItem('Deselect all', CM_DESELECT_ALL);
  AddSeparator;
  AddItem('Refresh'#9'R', CM_REFRESH);
  AddItem('Shuffle'#9'Ctrl+R', CM_SHUFFLE);
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
var
  Bar: TGlimpseStatusBar;
begin
  Bar := TGlimpseStatusBar.Create(Self);
  FStatusBar := Bar;
  FStatusBar.Parent := Self;
  {Initial Height is set by ApplyStatusBarSettings (called below) once
   the configured font has been measured — no point picking a number
   that the same paint cycle will overwrite.}
  FStatusBar.SimplePanel := False;
  FStatusBar.SizeGrip := False;
  FStatusBar.OnDblClick := OnStatusBarDblClick;
  FStatusBar.OnMouseUp := OnStatusBarMouseUp;
  {Per-panel hints come from CMHintShow inside TGlimpseStatusBar; the
   ShowHint flag still has to be on so the VCL routes hint messages to
   the control in the first place.}
  FStatusBar.ShowHint := True;
  FStatusBar.Visible := False;

  FProgressBar := TProgressBar.Create(FStatusBar);
  FProgressBar.Parent := FStatusBar;
  FProgressBar.Visible := False;

  {Renderer owns the status bar's panels from here on. The resolver
   reads from FCachedStatusBarValues which UpdateStatusBar refreshes
   once per call — guarantees a coherent snapshot across all tokens
   in a single Refresh. Self is passed as the renderer's owner so the
   form's inherited Destroy frees the renderer automatically; no manual
   FStatusBarRenderer.Free needed.}
  FStatusBarRenderer := TStatusBarRenderer.Create(Self, FStatusBar, ResolveStatusBarToken);

  Bar.OnGetPanelHint := GetStatusBarPanelHint;
  Bar.OnQueryPanelKind := GetStatusBarPanelKind;

  {FSettings is populated before CreateStatusBar (see SetParentAndLoad),
   so push the user's saved template / font / measurement policy in.
   Initial Refresh runs against an empty FCachedStatusBarValues so the
   bar is empty until UpdateStatusBar fires for the first opened
   file — matching the pre-template behaviour.}
  ApplyStatusBarSettings;
end;

function TPluginForm.ResolveStatusBarToken(const AToken: TStatusBarToken): string;
begin
  {Resolve the platform-specific glyph once per token; the formatter
   used to call uPlatformDetect itself, but lifting the dependency to
   the call site keeps uStatusBarFormatters truly pure.}
  Result := FormatStatusBarToken(AToken, FCachedStatusBarValues,
    ResolutionTransformGlyph);
end;

function TPluginForm.GetStatusBarPanelHint(APanelIndex: Integer): string;
begin
  Result := FStatusBarRenderer.HintForPanel(APanelIndex);
end;

function TPluginForm.GetStatusBarPanelKind(APanelIndex: Integer): TStatusBarTokenKind;
begin
  Result := FStatusBarRenderer.KindForPanel(APanelIndex);
end;

procedure TPluginForm.ApplyStatusBarSettings;
var
  Bmp: TBitmap;
  TextH: Integer;
begin
  if FStatusBarRenderer = nil then
    Exit;
  FStatusBarRenderer.SetFont(FSettings.StatusBarFontName, FSettings.StatusBarFontSize);
  FStatusBarRenderer.SetAutoWidthLive(FSettings.StatusBarAutoWidthLive);
  FStatusBarRenderer.SetStretchPanels(FSettings.StatusBarStretchPanels);
  FStatusBarRenderer.ApplyTemplate(FSettings.StatusBarTemplate);

  {Resize the bar. Auto path uses font-derived height (TextHeight + a
   small padding), explicit path scales the user's logical pixel value
   to the bar's CurrentPPI and silently bumps up to the font minimum
   so text never clips. Apply-mode gate honours the lister/quickview
   selection (sbhamBoth always applies; sbhamLister/QuickView skip the
   override when running in the other window mode and fall back to
   auto). Progress bar fills ClientHeight so it follows automatically
   once the bar resizes.}
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(FStatusBar.Font);
    {'Hg' is the standard ascender + descender pair used to measure a
     font's true vertical reach (matches GDI's GetTextMetrics output).}
    TextH := Bmp.Canvas.TextHeight('Hg');
  finally
    Bmp.Free;
  end;
  FStatusBar.Height := ResolveStatusBarHeight(TextH);
  RepositionProgressBar;
end;

function TPluginForm.ResolveStatusBarHeight(ATextHeight: Integer): Integer;
begin
  {VCL-bound wrapper: hands the form state to the pure resolver in
   uTypes so the policy stays unit-testable. FStatusBar.CurrentPPI
   returns 0 in some pre-paint states; the pure helper normalises
   that to 96.}
  Result := ResolveStatusBarHeightPixels(ATextHeight,
    FSettings.StatusBarHeight,
    FSettings.StatusBarHeightApplyMode,
    FQuickViewMode,
    FStatusBar.CurrentPPI);
end;

procedure TPluginForm.BuildStatusBarValues(out AValues: TStatusBarValues);
var
  PredW, PredH, PredCappedW, PredCappedH: Integer;
begin
  AValues := Default(TStatusBarValues);
  {Pre-template behaviour: the bar showed nothing until video info was
   probed. Preserved here so panels stay hidden until extraction starts
   filling them in.}
  if not FVideoInfo.IsValid then
    Exit;
  AValues.VideoInfoValid := True;

  AValues.Filename := FFileName;

  AValues.FilePositionAvailable := GetFilePosition(FFileName,
    FSettings.ExtensionList, AValues.FilePositionIndex, AValues.FilePositionTotal);

  AValues.FramesAvailable := Length(FOffsets) > 0;
  AValues.FramesTotal := Length(FOffsets);
  if FFrameView <> nil then
  begin
    AValues.CurrentFrameIndex := FFrameView.CurrentFrameIndex;
    AValues.IsSingleViewMode := FFrameView.ViewMode = vmSingle;
    AValues.ViewModeName := ViewModeDisplayName(FFrameView.ViewMode);
    AValues.ZoomModeName := ZoomModeDisplayName(FFrameView.ZoomMode);
  end;

  AValues.SourceWidth := FVideoInfo.Width;
  AValues.SourceHeight := FVideoInfo.Height;
  AValues.SourceFps := FVideoInfo.Fps;
  AValues.SourceDurationSec := FVideoInfo.Duration;
  AValues.SourceBitrateKbps := FVideoInfo.Bitrate;
  AValues.SourceVideoCodec := FVideoInfo.VideoCodec;

  AValues.SourceAudioCodec := FVideoInfo.AudioCodec;
  AValues.SourceAudioSampleRate := FVideoInfo.AudioSampleRate;
  AValues.SourceAudioChannels := FVideoInfo.AudioChannels;
  AValues.SourceAudioBitrateKbps := FVideoInfo.AudioBitrateKbps;

  if FExporter <> nil then
  begin
    AValues.SaveDimAvailable := FExporter.PredictDisplayedSize(
      FSettings.SaveAtLiveResolution, PredW, PredH, PredCappedW, PredCappedH);
    if AValues.SaveDimAvailable then
    begin
      AValues.SaveDimW := PredW;
      AValues.SaveDimH := PredH;
      AValues.SaveDimCappedW := PredCappedW;
      AValues.SaveDimCappedH := PredCappedH;
    end;
    AValues.CopyDimAvailable := FExporter.PredictDisplayedSize(
      FSettings.CopyAtLiveResolution, PredW, PredH, PredCappedW, PredCappedH);
    if AValues.CopyDimAvailable then
    begin
      AValues.CopyDimW := PredW;
      AValues.CopyDimH := PredH;
      AValues.CopyDimCappedW := PredCappedW;
      AValues.CopyDimCappedH := PredCappedH;
    end;
  end;

  AValues.LoadTimeText := FLoadTimeStr;
end;

procedure TPluginForm.UpdateStatusBar;
var
  Last: Integer;
  Dummy: TStatusPanel;
begin
  if FStatusBarRenderer = nil then
    Exit;
  BuildStatusBarValues(FCachedStatusBarValues);
  FStatusBarRenderer.Refresh;
  {Append a 0-width dummy panel only when the last visible panel has
   non-default alignment. Without it the common control lets the last
   panel stretch to fill remaining width, defeating the right- or
   center-justify the user asked for. Other panels can stretch
   harmlessly (left-justified text just leaves blank space on the
   right), so the dummy is only added when it would actually matter —
   matches the pre-template behaviour for the load_time panel.}
  Last := FStatusBar.Panels.Count - 1;
  if (Last >= 0) and (FStatusBar.Panels[Last].Alignment <> taLeftJustify) then
  begin
    Dummy := FStatusBar.Panels.Add;
    Dummy.Width := 0;
    Dummy.Text := '';
  end;
end;

procedure TPluginForm.OnStatusBarDblClick(Sender: TObject);
var
  Pt: TPoint;
  HitIdx, PanelLeft: Integer;
  Kind: TStatusBarTokenKind;
begin
  if (FStatusBar.Panels.Count = 0) or (FStatusBarRenderer = nil) then
    Exit;
  Pt := FStatusBar.ScreenToClient(Mouse.CursorPos);
  HitIdx := StatusBarPanelHitTest(FStatusBar, Pt.X, PanelLeft);
  if HitIdx < 0 then
    Exit;
  Kind := FStatusBarRenderer.KindForPanel(HitIdx);
  case Kind of
    tkSaveDimension:
      FSettings.SaveAtLiveResolution := not FSettings.SaveAtLiveResolution;
    tkCopyDimension:
      FSettings.CopyAtLiveResolution := not FSettings.CopyAtLiveResolution;
  else
    Exit;
  end;
  {Persist so a TC restart preserves the flip — same contract the
   settings dialog has. UpdateStatusBar recomputes the predicted-size
   panels against the new toggle so the visible text changes on the
   next paint, giving the user immediate feedback.}
  FSettings.Save;
  UpdateStatusBar;
end;

procedure TPluginForm.OnStatusBarMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  HitIdx, PanelLeft: Integer;
begin
  {Only Ctrl+left-click copies. Other modifier combinations and right /
   middle clicks fall through to default (no-op for status bar).}
  if (Button <> mbLeft) or (Shift * [ssCtrl, ssShift, ssAlt] <> [ssCtrl]) then
    Exit;
  if FStatusBar.Panels.Count = 0 then
    Exit;
  HitIdx := StatusBarPanelHitTest(FStatusBar, X, PanelLeft);
  {Click past last panel: copy last panel (matches pre-change behaviour
   when double-click did the copying).}
  if HitIdx < 0 then
    HitIdx := FStatusBar.Panels.Count - 1;
  Clipboard.AsText := FStatusBar.Panels[HitIdx].Text;
end;

function TPluginForm.ResolveZoomModeForCurrentView(ARequestedZoom: TZoomMode): TZoomMode;
begin
  if FModePopups[FFrameView.ViewMode] = nil then
    Result := zmFitWindow
  else
    Result := ARequestedZoom;
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
  FFrameView.ZoomMode := ResolveZoomModeForCurrentView(FSettings.ZoomMode);

  {Restore per-mode zoom selections in all popup menus}
  for VM := Low(TViewMode) to High(TViewMode) do
    SyncZoomMenuChecks(VM, FSettings.ModeZoom[VM]);

  UpdateViewModeButtons;
  FToolbar.Visible := FSettings.ShowToolbar and not(FQuickViewMode and FSettings.QVHideToolbar);
  {OR with FProgressVisible so an in-flight progress display does not get
   cancelled when the user opens / accepts the settings dialog mid-
   extraction. The bar is shown by ShowProgress (which sets the status
   bar visible regardless of the user's persisted preference) and only
   hidden by HideProgress when the run finishes; without this guard,
   accepting the dialog would force the bar back to its persisted
   "off" state and the still-running progress would vanish.}
  FStatusBar.Visible := FProgressVisible or (FSettings.ShowStatusBar and not(FQuickViewMode and FSettings.QVHideStatusBar));
  {Pick up any change to the progress bar layout setting on the fly,
   so the user sees the new layout before the current run completes
   instead of having to wait for the next extraction.}
  if FProgressVisible then
    RepositionProgressBar;
  Style := TTimestampStyle.FromSettings(FSettings.Timestamp);
  {Live view always renders with the modern rect painter regardless of
   the persisted BackAlpha sentinel — legacy mode is a combined-image-
   only concern. Pinning this here keeps ApplySettings from accidentally
   inheriting the BackAlpha=0 -> tsmLegacy fallback that FromSettings
   uses for combined-sheet renders.}
  Style.Mode := tsmModern;
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
  FFrameView.ApplyZoom(1.0);
  FFrameView.ViewMode := AMode;
  {Mode change might have altered the effective per-frame viewport
   (grid<->single), so kick the debounce timer; the actual refresh only
   fires if the computed MaxSide actually changes.}
  ScheduleViewportRefresh;
  {Status bar's frame-position panel switches between "N / Total" and
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
    FFrameView.ApplyZoom(NewF);
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
  FFrameView.ApplyZoom(1.0);
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

procedure TPluginForm.ApplyListerParams(AParams: Integer);
var
  NewZM: TZoomMode;
begin
  {TC's ShowFlags carry no view-mode semantics; the lcp_FitToWindow /
   lcp_FitLargerOnly bits are about TEXT viewer fit. Translating them to
   our zoom enum yields zmActual when neither bit is set (TC default),
   which would push always-fit modes (vmGrid, vmSmartGrid) into a
   degenerate 1-column rendering. Clamp to the supported set first.}
  NewZM := ResolveZoomModeForCurrentView(ListerParamsToZoomMode(AParams));
  if FFrameView.ZoomMode = NewZM then
    Exit;

  FFrameView.ApplyZoom(1.0);
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

  {Set actual dimensions and aspect ratio from video metadata.}
  ApplyVideoDimsToFrameView;

  SetupPlaceholders;
  HideError;
  StartExtraction(RandomCacheOverride);
end;

{Pushes FVideoInfo's pixel dimensions to the frame view. RespectAnamorphic
 selects between storage and display pixel grids for the live-view aspect
 ratio so cells match the actually-extracted frame proportions.}
procedure TPluginForm.ApplyVideoDimsToFrameView;
begin
  if (FVideoInfo.Width > 0) and (FVideoInfo.Height > 0) then
  begin
    FFrameView.NativeW := FVideoInfo.Width;
    FFrameView.NativeH := FVideoInfo.Height;
    if FSettings.RespectAnamorphic and (FVideoInfo.DisplayWidth > 0) and (FVideoInfo.DisplayHeight > 0) then
      FFrameView.AspectRatio := FVideoInfo.DisplayHeight / FVideoInfo.DisplayWidth
    else
      FFrameView.AspectRatio := FVideoInfo.Height / FVideoInfo.Width;
  end else begin
    FFrameView.NativeW := 0;
    FFrameView.NativeH := 0;
    FFrameView.AspectRatio := DEF_ASPECT_RATIO;
  end;
end;

procedure TPluginForm.SetupPlaceholders;
begin
  RebuildFrameOffsets;

  FFrameView.SetCellCount(Length(FOffsets), FOffsets);
  UpdateFrameViewSize;
end;

procedure TPluginForm.RebuildFrameOffsets(AForceRandom: Boolean);
var
  UseRandom: Boolean;
begin
  UseRandom := AForceRandom or FSettings.RandomExtraction;
  if (FVideoInfo.Duration > 0) and (FUpDown.Position > 0) then
    FOffsets := BuildFrameOffsets(FVideoInfo.Duration, FUpDown.Position, FSettings.SkipEdgesPercent, FSettings.RandomPercent, UseRandom)
  else
    SetLength(FOffsets, 0);
  FCurrentExtractionIsRandom := UseRandom and (Length(FOffsets) > 0);
end;

function TPluginForm.RandomCacheOverride: IFrameCache;
begin
  if FCurrentExtractionIsRandom and not FSettings.CacheRandomFrames then
    Result := TReadOnlyFrameCache.Create(FExtractCtrl.Cache)
  else
    Result := nil;
end;

procedure TPluginForm.ShuffleExtraction;
begin
  if (FFileName = '') or (FVideoInfo.Duration <= 0) then
    Exit;
  FExtractCtrl.Stop;
  FExtractCtrl.DrainPendingFrameMessages;
  RebuildFrameOffsets(True);
  FFrameView.SetCellCount(Length(FOffsets), FOffsets);
  UpdateFrameViewSize;
  StartExtraction(RandomCacheOverride);
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

  if FSettings.ScaledExtraction then
  begin
    ViewportFrames := ViewportFrameCount(FFrameView.ViewMode, Length(FOffsets));
    Options := FSettings.Extraction.ToExtractionOptions(
      CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight, ViewportFrames, FFrameView.AspectRatio, FVideoInfo.Width, FVideoInfo.Height, FSettings.MinFrameSide, FSettings.MaxFrameSide));
  end
  else
    Options := FSettings.Extraction.ToExtractionOptions;

  {Remember the extraction size so OnViewportRefreshTimer can decide
   whether the next viewport-change event actually changed anything.}
  FLastExtractionMaxSide := Options.MaxSide;

  Extractor := TFFmpegFrameExtractor.Create(FFFmpegPath);
  FExtractCtrl.Start(Extractor, FFileName, FOffsets, FSettings.MaxWorkers, FSettings.MaxThreads, Options, ACacheOverride);
end;

procedure TPluginForm.WithReExtract(const AIndices: TArray<Integer>; AAction: TProc);
var
  Target: Integer;
  Ctx: TSaveResolutionContext;
  Reextractor: TSaveResolutionExtractor;
  Frames: TArray<TBitmap>;
  Total, I: Integer;
begin
  Target := PickSaveMaxSide(FVideoInfo.Width, FVideoInfo.Height, FSettings.ScaledExtraction, FSettings.MaxFrameSide);
  if not NeedsReExtractForSave(FSettings.SaveAtLiveResolution, Length(AIndices), Target, FLastExtractionMaxSide) then
  begin
    AAction;
    Exit;
  end;

  if (Length(FOffsets) = 0) or (FFileName = '') or (FFFmpegPath = '') then
  begin
    AAction;
    Exit;
  end;

  Ctx.FileName := FFileName;
  Ctx.Offsets := FOffsets;
  Ctx.CellCount := FFrameView.CellCount;
  Ctx.UseBmpPipe := FSettings.UseBmpPipe;
  Ctx.HwAccel := FSettings.HwAccel;
  Ctx.UseKeyframes := FSettings.UseKeyframes;
  Ctx.RespectAnamorphic := FSettings.RespectAnamorphic;
  Total := Length(AIndices);

  FormLog(Format('WithReExtract: starting target=%d cells indices=%d', [Target, Total]));
  Reextractor := TSaveResolutionExtractor.Create(FExtractCtrl.Cache, TFFmpegFrameExtractor.Create(FFFmpegPath));
  try
    Reextractor.OnLabel := procedure(const AText: string)
      begin
        FormLog(Format('WithReExtract: OnLabel - showing progress (%s)', [AText]));
        FProgressBar.Style := pbstNormal;
        FProgressBar.Min := 0;
        FProgressBar.Max := Total;
        FProgressBar.Position := 0;
        ShowProgress(AText);
      end;
    Reextractor.OnProgress := procedure(ACurrent, ATotal: Integer)
      begin
        FProgressBar.Position := ACurrent;
      end;
    Reextractor.OnPump := procedure
      begin
        Application.ProcessMessages;
      end;
    Reextractor.OnDone := procedure
      begin
        FormLog('WithReExtract: OnDone - hiding progress');
        HideProgress;
      end;

    Frames := Reextractor.ExtractAtTarget(Ctx, Target, AIndices);
  finally
    Reextractor.Free;
  end;
  FormLog(Format('WithReExtract: re-extract finished, Frames length=%d', [Length(Frames)]));

  try
    FExporter.SetOverrideFrames(Frames);
    try
      AAction;
    finally
      FExporter.ClearOverrideFrames;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
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
begin
  if FLoadStartTick = 0 then
    Exit;
  if FLoadTimeStr <> '' then
    Exit; {already finalized}

  {Cast guards correct unsigned wraparound; GetTickCount avoids the Vista+
   GetTickCount64 dependency that crashes on XP via delay-load.}
  ElapsedMs := Cardinal(GetTickCount - FLoadStartTick);
  FLoadTimeStr := FormatLoadTimeMs(ElapsedMs);
  UpdateStatusBar;
end;

procedure TPluginForm.RepositionProgressBar;
const
  {Tiny inset so the bar doesn't touch the status bar's borders.}
  Margin = 1;
var
  PanelsRight, I: Integer;
  Bounds: TProgressBarBounds;
begin
  if not FProgressVisible then
    Exit;

  {Right edge of the last panel — the boundary the AfterPanels layout
   needs to clear. Computed from the live panel widths so adding or
   removing an SBP_*_W panel in UpdateStatusBar requires no separate
   bookkeeping here.}
  PanelsRight := 0;
  for I := 0 to FStatusBar.Panels.Count - 1 do
    Inc(PanelsRight, FStatusBar.Panels[I].Width);

  Bounds := ResolveProgressBarBounds(FStatusBar.ClientWidth, FStatusBar.ClientHeight,
    PanelsRight, FSettings.StatusBarStretchPanels, FSettings.ProgressBarLayout,
    PROGRESSBAR_MIN_W, Margin);
  FProgressBar.SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
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
  end else begin
    PostMessage(GetParent(Handle), WM_KEYDOWN, AKey, 0);
    PostMessage(GetParent(Handle), WM_KEYUP, AKey, 0);
  end;
end;

function TPluginForm.TryExecuteExportCommand(ACommandTag: Integer): Boolean;
begin
  Result := CanExportFrames;
  if Result then
    DispatchCommand(ACommandTag);
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
    paShuffleExtraction:
      ShuffleExtraction;
    {Save / copy hotkey actions dispatch through PickActionCell, which
     picks the selected cell first and falls back to the focused / first
     cell. Each routes through TryExecuteExportCommand so the
     CanExportFrames gate is centralised — a mid-extraction keystroke
     falls through (Result := False) instead of dispatching against an
     unstable cell set, matching the toolbar / context-menu visual lock.}
    paSaveFrame:      Result := TryExecuteExportCommand(CM_SAVE_FRAME);
    paSaveFrames:     Result := TryExecuteExportCommand(CM_SAVE_FRAMES);
    paSaveView:       Result := TryExecuteExportCommand(CM_SAVE_VIEW);
    paSaveViewLive:   Result := TryExecuteExportCommand(CM_SAVE_VIEW_LIVE);
    paSaveViewNative: Result := TryExecuteExportCommand(CM_SAVE_VIEW_NATIVE);
    paSelectAllFrames:
      FFrameView.SelectAll;
    paCopyFrame:      Result := TryExecuteExportCommand(CM_COPY_FRAME);
    paCopyView:       Result := TryExecuteExportCommand(CM_COPY_VIEW);
    paCopyViewLive:   Result := TryExecuteExportCommand(CM_COPY_VIEW_LIVE);
    paCopyViewNative: Result := TryExecuteExportCommand(CM_COPY_VIEW_NATIVE);
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
      Ord('0') .. Ord('9'), VK_NUMPAD0 .. VK_NUMPAD9, VK_BACK, VK_DELETE, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_UP, VK_DOWN:
        Exit;
    end;

  {Configurable hotkeys. ExecuteHotkey returns False when the action's
   contextual guards say "not applicable right now" (e.g. paPrevFrame when
   not in single-view mode, or paOpenInPlayer with no file), in which case
   the key falls through to the Lister forward below — letting TC's own
   built-in shortcut on the same key fire as a fallback.}
  Action := FSettings.Hotkeys.Lookup(Key, Shift);
  if (Action <> paNone) and ExecuteHotkey(Action) then
    Key := 0;

  {Post-dispatch edit-focus fallback: any keystroke that the edit wasn't
   allowed to handle above AND wasn't consumed by a hotkey is mopped up
   here. Enter is allowed to commit the value; everything else reclaims
   form focus so TC's subclass sees subsequent keystrokes. Runs before
   the Lister forward so editing keys never leak out to TC.}
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

  {Anything still unconsumed gets handed back to TC's Lister window.
   FormSubclassProc claims every key off TC's wndproc so the plugin's
   binding dispatcher always sees keys first; without this forward TC's
   built-in shortcuts (N/P navigation, F2 reload, Backspace to parent,
   letter-key mode toggles, etc.) would be permanently dead while the
   plugin is the active view — fatal in Quick View, which has no window
   menu fallback. Alt+letter forwards as a SysKey so TC's menu mnemonics
   still resolve correctly in regular Lister mode.}
  if Key <> 0 then
  begin
    ForwardKeyToLister(Key, ssAlt in Shift);
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
  {Two competing constraints:

   - TC subclasses THIS window to catch N/P and other Lister hotkeys;
     that subclass only sees WM_KEYDOWN while THIS HWND holds Win32
     focus. If VCL's inherited WMSetFocus redirects focus to a child
     (which it does when ActiveControl is set), TC's hotkey
     interception silently stops working.

   - The earlier fix was to skip inherited entirely. That blocked the
     focus redirect but also suppressed every other side effect VCL's
     focus machinery runs at this point: CM_FOCUSCHANGED broadcast,
     OnActivate, accessibility hooks, IME activation. Skipping
     inherited is an LSP violation — any listener attached through
     normal VCL channels is silently broken.

   Clearing ActiveControl removes the redirect target; inherited then
   runs the rest of its work with focus correctly staying on the form
   HWND. Both constraints are honoured.}
  ActiveControl := nil;
  inherited;
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

procedure TPluginForm.DispatchCommand(ATag: Integer; AContextCellIndex: Integer = -1);
var
  ResolvedIdx: Integer;
  ReExtract: TReExtractAction;
begin
  {Singular Save / Copy frame routes through PickActionCell so the same
   selection-first policy drives every entry point: context menu,
   toolbar button, configurable hotkey, TC lc_Copy. PickActionCell
   returns -1 when no loaded cell is reachable; the dispatch then
   silently skips the action.

   The resolved index is computed once and reused: WithReExtract pumps
   the message loop while it re-extracts, so reading FFrameView state
   twice could disagree if the user selects a different cell in between.

   Plural / view-level actions (Save frames, Save view, Copy view)
   always act on the full loaded set or the selection set; PickActionCell
   does not apply.

   Save methods receive a re-extract callback so the dialog opens
   immediately and re-extract runs only after the user commits. The
   alternative (wrapping the dialog in WithReExtract upfront) blocked
   TC for seconds before the dialog appeared and re-extracted even when
   the user then cancelled.}
  case ATag of
    CM_SAVE_FRAME, CM_SAVE_FRAMES, CM_SAVE_VIEW, CM_SAVE_VIEW_LIVE, CM_SAVE_VIEW_NATIVE,
    CM_COPY_FRAME, CM_COPY_VIEW, CM_COPY_VIEW_LIVE, CM_COPY_VIEW_NATIVE:
      if not CanExportFrames then
        Exit;
  end;
  ReExtract := procedure(const AIndices: TArray<Integer>; AAction: TProc)
    begin
      WithReExtract(AIndices, AAction);
    end;
  case ATag of
    CM_SAVE_FRAME:
      begin
        ResolvedIdx := FExporter.PickActionCell(-1);
        if ResolvedIdx >= 0 then
          FExporter.SaveFrame(FFileName, ResolvedIdx, ReExtract);
      end;
    CM_SAVE_FRAMES:
      FExporter.SaveFrames(FFileName, ReExtract);
    CM_SAVE_VIEW:
      {Default Save view: seed the dialog with the persisted setting.}
      FExporter.SaveView(FFileName, FSettings.SaveAtLiveResolution, ReExtract);
    CM_SAVE_VIEW_LIVE:
      {Explicit "view resolution" variant from the Save view dropdown.}
      FExporter.SaveView(FFileName, True, ReExtract);
    CM_SAVE_VIEW_NATIVE:
      {Explicit "native size" variant from the Save view dropdown.}
      FExporter.SaveView(FFileName, False, ReExtract);
    CM_COPY_FRAME:
      begin
        {Only Copy frame forwards AContextCellIndex to PickActionCell.
         The right-click context menu wires its captured cursor cell
         through here so a no-selection user gets the cell they clicked
         on; when a selection exists, PickActionCell's step 1 takes
         precedence and Copy frame acts on the first selected cell
         regardless of where the right-click landed (matches Save frame
         from the same menu and matches TC's "right-click anywhere acts
         on the selection" convention). The toolbar button, configurable
         hotkey, and TC lc_Copy all pass -1 and so never reach the
         context-cell branch — selection-first behaves identically there.

         The re-extract gate now lives inside CopyFrame (it temp-flips
         SaveAtLiveResolution := CopyAtLiveResolution and decides from
         there), so the dispatch just hands over the callback rather
         than wrapping the call in WithReExtract upfront. Mirrors the
         CopyView / SaveView pattern.}
        ResolvedIdx := FExporter.PickActionCell(AContextCellIndex);
        if ResolvedIdx >= 0 then
          FExporter.CopyFrame(ResolvedIdx, ReExtract);
      end;
    CM_COPY_VIEW:
      {Default Copy view: honour the persisted CopyAtLiveResolution
       (separate setting from the save side since 1.1.3.4).}
      FExporter.CopyView(FSettings.CopyAtLiveResolution, ReExtract);
    CM_COPY_VIEW_LIVE:
      {Explicit "view resolution" variant from the Copy view dropdown.}
      FExporter.CopyView(True, ReExtract);
    CM_COPY_VIEW_NATIVE:
      {Explicit "native size" variant from the Copy view dropdown.}
      FExporter.CopyView(False, ReExtract);
    CM_SELECT_ALL:
      FFrameView.SelectAll;
    CM_DESELECT_ALL:
      FFrameView.DeselectAll;
    CM_REFRESH:
      RefreshExtraction;
    CM_SHUFFLE:
      ShuffleExtraction;
    CM_SETTINGS:
      ShowSettings;
  end;
end;

procedure TPluginForm.OnToolbarButtonClick(Sender: TObject);
begin
  DispatchCommand(TButton(Sender).Tag);
end;

function TPluginForm.CanExportFrames: Boolean;
begin
  Result := Assigned(FFrameView) and FFrameView.HasLoadedCells and not FFrameView.HasPlaceholders;
end;

procedure TPluginForm.UpdateToolbarButtons;
var
  I: Integer;
  HasFrames, CanExport: Boolean;
begin
  HasFrames := Assigned(FFrameView) and FFrameView.HasLoadedCells;
  {Save / copy must wait until extraction settles. PickActionCell would
   otherwise return -1 (or a stale cell that just got reset to a
   placeholder by a Refresh) and the action would silently no-op, which
   reads as a broken button. Locking the buttons visually surfaces the
   state to the user instead.}
  CanExport := CanExportFrames;
  for I := 0 to High(FToolbarButtons) do
    case FToolbarButtons[I].Tag of
      CM_SETTINGS:
        FToolbarButtons[I].Enabled := True;
      CM_REFRESH:
        {Refresh stays clickable during extraction so the user can cancel
         and restart with new settings without waiting for the current
         run to finish.}
        FToolbarButtons[I].Enabled := HasFrames;
      else
        FToolbarButtons[I].Enabled := CanExport;
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
  {Status bar's predicted Save / Copy view dimensions depend on cell sizes
   and viewport - both change with the lister window. Refresh after the
   layout pass; safe before FStatusBar exists since it is created in
   CreateStatusBar (called before the first user-triggered Resize).}
  if Assigned(FStatusBar) then
    UpdateStatusBar;
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
  HasFrames, CanExport: Boolean;
begin
  {Capture the cell under the cursor so OnContextMenuClick can route
   the right-clicked cell through DispatchCommand for Copy frame.
   CellIndexAt returns -1 when the cursor isn't over a real cell;
   PickActionCell's downstream loaded-state check filters placeholders.}
  FContextCellIndex := FFrameView.CellIndexAt(FFrameView.ScreenToClient(Mouse.CursorPos));

  HasFrames := FFrameView.CellCount > 0;
  {Mid-extraction the loaded set is unstable (cells flip from placeholder
   to loaded as workers finish, and Refresh resets every cell back to
   placeholder). Save / copy wait until extraction settles so the action
   sees a consistent set.}
  CanExport := CanExportFrames;

  for I := 0 to FContextMenu.Items.Count - 1 do
  begin
    MI := FContextMenu.Items[I];
    case MI.Tag of
      CM_SAVE_FRAME, CM_SAVE_VIEW, CM_COPY_FRAME, CM_COPY_VIEW:
        MI.Enabled := CanExport;
      CM_SAVE_FRAMES:
        begin
          {Selection-aware caption: when frames are selected the action
           saves only those, otherwise it saves all loaded frames. The
           caption echoes the selected count so the user knows which set
           is about to be written before the file dialog opens.}
          MI.Enabled := CanExport;
          SelCount := FFrameView.SelectedCount;
          if SelCount > 0 then
            MI.Caption := Format('Save frames (%d selected)...'#9'Ctrl+Alt+Shift+S', [SelCount])
          else
            MI.Caption := 'Save frames (all)...'#9'Ctrl+Alt+Shift+S';
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
  {Pass the captured right-click cell through so DispatchCommand's
   Copy frame branch can prefer it over the selection. Save frame and
   the view-level actions deliberately ignore the parameter and keep
   the selection-first rule (see DispatchCommand).}
  DispatchCommand(TMenuItem(Sender).Tag, FContextCellIndex);
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
  {Status bar's frame-position panel reflects the new total immediately,
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

  {Toggling RespectAnamorphic changes the live-view cell aspect ratio; do
   it before the re-extract so SetupPlaceholders sees the new aspect.}
  if scRespectAnamorphicChanged in Changes then
    ApplyVideoDimsToFrameView;

  {Re-extract if skip edges, scaled extraction, keyframes, anamorphic, or
   the random-extraction settings changed. scRandomExtractionChanged fires
   only when toggling RandomExtraction or moving the slider while it is
   on; CacheRandomFrames toggles by themselves do not re-extract (they
   only change which cache wrapper future random extractions use).}
  if (Changes * [scSkipEdgesChanged, scScaledExtractionChanged, scUseKeyframesChanged, scRespectAnamorphicChanged, scRandomExtractionChanged]) <> [] then
    RefreshExtraction;

  {Status-bar template / font / measurement policy may have changed
   on this Apply. ApplyStatusBarSettings re-pushes them to the renderer
   and runs a Refresh internally; the explicit UpdateStatusBar that
   follows is a no-op for template/font but reseats panel TEXT against
   the freshly-snapshotted values (predicted dims react to several
   knobs that do not trigger RefreshExtraction).}
  ApplyStatusBarSettings;
  UpdateStatusBar;
end;

procedure TPluginForm.ShowSettings;
begin
  FSettingsSnap := TakeSettingsSnapshot(FSettings);

  if not ShowSettingsDialog(FParentWnd, FSettings, FFFmpegPath, CommitSettingsChanges) then
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
  {TBypassFrameCache skips reads (forces ffmpeg re-extraction) but still
   delegates writes to the inner cache, so refresh DOES update the cache
   with fresh frames. TestBypassCachePutDelegates pins that contract.
   Comment is here so a quick read does not assume "bypass" means write-
   skip too - the decorator is read-only-bypass.}
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
  StartExtraction(RandomCacheOverride);
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
  if FSettings = nil then
    Exit;
  if not FSettings.AutoRefreshOnViewportChange then
    Exit;
  if not FSettings.ScaledExtraction then
    Exit;
  if not FVideoInfo.IsValid then
    Exit;
  if FFileName = '' then
    Exit;
  if Length(FOffsets) = 0 then
    Exit;

  ViewportFrames := ViewportFrameCount(FFrameView.ViewMode, Length(FOffsets));
  NewMaxSide := CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight, ViewportFrames, FFrameView.AspectRatio, FVideoInfo.Width, FVideoInfo.Height, FSettings.MinFrameSide, FSettings.MaxFrameSide);

  {Same size bucket as the live extraction (viewport only jittered within
   one SCALE_BUCKET, or the view mode didn't actually change the divisor).
   Nothing to do — any cached frames are already at the right resolution.}
  if NewMaxSide = FLastExtractionMaxSide then
    Exit;

  SoftRefreshExtraction;
end;

initialization
  FormLog := DebugLogger('Form');

end.
