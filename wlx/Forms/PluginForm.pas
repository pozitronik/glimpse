{Main plugin form: toolbar, frame display, and extraction coordination.
 The form is parented to TC's Lister window.}
unit PluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Menus, Vcl.Buttons, Vcl.ImgList,
  Types, StatusBarLayout, Settings, SettingsToggleService, Hotkeys, FrameOffsets, VideoInfo, Cache, WlxAPI, FrameNotificationSink,
  ZoomController,
  ExtractionPlanner, ToolbarLayout, ToolbarController, FrameView,
  ViewportRefreshDebouncer, LoadTimeRecorder, ProgressIndicator,
  FrameExport, ExtractionController, PluginServices,
  CommandDescriptors,
  StatusBarTokens, StatusBarTemplate, StatusBarFormatters, StatusBarRenderer;

type
  TPluginForm = class;

  {One named method per CM_* command in TPluginForm's dispatch table.
   Per-invocation context (right-click cell index) is threaded via
   FNextContextCellIndex so the Executor closures stay parameterless.}
  TPluginCommandHandlers = class
  strict private
    FForm: TPluginForm;
    {Only CopyFrame consults this; -1 = no context cell.}
    FNextContextCellIndex: Integer;
    function MakeReExtract: TReExtractAction;
  public
    constructor Create(AForm: TPluginForm);
    procedure SetContextCellIndex(AValue: Integer);
    procedure SaveFrame;
    procedure SaveFrames;
    procedure SaveView;
    procedure SaveViewLive;
    procedure SaveViewNative;
    procedure CopyFrame;
    procedure CopyView;
    procedure CopyViewLive;
    procedure CopyViewNative;
    procedure SelectAll;
    procedure DeselectAll;
    procedure Refresh;
    procedure Shuffle;
    procedure Settings;
    {Built programmatically (SetLength + index-assign), NOT as a const
     aggregate — Delphi hits a limit on anonymous-method fields inside
     array-literal rows.}
    function BuildTable: TCommandTable;
  end;

  {Plugin form created as a child of TC's Lister window.}
  TPluginForm = class(TForm)
  private
    FFileName: string;
    FSettings: TPluginSettings;
    FSettingsToggle: TSettingsToggleService;
    FFFmpegPath: string;
    FVideoInfo: TVideoInfo;
    FOffsets: TFrameOffsetArray;
    FParentWnd: HWND;
    {Widget fields below are non-owning aliases populated from
     FToolbarController.Build; widgets are owned by the form (TComponent).}
    FToolbarController: TToolbarController;
    FToolbar: TPanel;
    FLblFrames: TLabel;
    FEditFrameCount: TEdit;
    FUpDown: TUpDown;
    FModeButtons: array [TViewMode] of TButton;
    FModePopups: array [TViewMode] of TPopupMenu;
    FContextMenu: TPopupMenu;
    FBtnTimecode: TSpeedButton;
    FToolbarButtons: TArray<TButton>;
    FBtnHamburger: TButton;
    FHamburgerMenu: TPopupMenu;
    FRefreshPopup: TPopupMenu;
    FSaveViewPopup: TPopupMenu;
    FCopyViewPopup: TPopupMenu;
    {Alias of FToolbarController.GlyphLibrary.Images; image list is owned by the controller.}
    FToolbarImages: TImageList;
    FProgressIndicator: TProgressIndicator;
    {Alias of FProgressIndicator.ProgressBar so direct .Style/.Max/.Position writes keep working.}
    FProgressBar: TProgressBar;
    FStatusBar: TStatusBar;
    FStatusBarRenderer: TStatusBarRenderer;
    {Snapshot refreshed once per UpdateStatusBar so a render emits a
     coherent view instead of racing live changes mid-iteration.}
    FCachedStatusBarValues: TStatusBarValues;
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    FExporter: TFrameExporter;
    {Right-click cell index captured by OnContextMenuPopup so "Copy frame"
     acts on the right-clicked cell. Other entry points pass -1 to keep
     PickActionCell's selection-first fallback.}
    FContextCellIndex: Integer;
    FExtractCtrl: TExtractionController;
    {Form takes ownership of FServices.ProbeCache and frees it in Destroy.}
    FServices: TPluginServices;
    FAnimTimer: TTimer;
    FViewportRefreshDebouncer: TViewportRefreshDebouncer;
    {Drives cache-override selection so CacheRandomFrames=False suppresses
     writes for random extractions only.}
    FCurrentExtractionIsRandom: Boolean;
    {Re-entrancy guard against zoom-driven UpdateFrameViewSize.}
    FUpdatingLayout: Boolean;
    {Set True at the end of CreateForPlugin. Gates the VCL handlers
     (Resize, OnAnimTimer, DoMouseWheel, OnScrollBoxResize, LayoutToolbar)
     that Win32 / VCL fires synchronously during sub-control creation,
     before the form's fields finish wiring up.}
    FInitialized: Boolean;
    {True when hosted in TC's Quick View panel (Ctrl+Q).}
    FQuickViewMode: Boolean;
    {Suppresses WM_CHAR after OnKeyDown consumed the keystroke.}
    FKeyConsumed: Boolean;
    {Step 105 (C1, part 2): load-time bookkeeping lifted into
     TLoadTimeRecorder. Start in StartExtraction, Finalize in
     WMExtractionDone, formatted string read by BuildStatusBarValues.}
    FLoadTimer: TLoadTimeRecorder;
    {Rolling snapshot used by ShowSettings to detect what changed since the
     previous Apply/OK commit, so Apply can be pressed repeatedly and only
     trigger the side-effects (cache recreate, re-extract) that apply to the
     delta, not to the full original-to-current diff}
    FSettingsSnap: TSettingsSnapshot;
    {Command dispatch infrastructure: handlers + the table that pairs
     each CM_* tag with its enable policy + executor. Built once in
     CreateForPlugin, walked on every DispatchCommand /
     UpdateToolbarButtons / OnContextMenuPopup / hotkey dispatch.
     Replaces four parallel CM_* case ladders with one data table.}
    FCommandHandlers: TPluginCommandHandlers;
    FCommandTable: TCommandTable;

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
     FExporter / FLoadTimer.Formatted; safe to call any time, never mutates.}
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
    procedure UpdateResolutionMenuLabels(AMenu: TPopupMenu);
    procedure OnViewDropdownPopup(Sender: TObject);
    {Clamps requested zoom to zmFitWindow for modes with no zoom popup
     (vmGrid, vmSmartGrid) so persisted/Lister-supplied values cannot push
     the renderer into a degenerate branch.}
    function ResolveZoomModeForCurrentView(ARequestedZoom: TZoomMode): TZoomMode;
    procedure InitializeWindowing(AParentWin: HWND);
    procedure InitializeUI;
    procedure InitializeExtractionStack;
    procedure InitializeServices;
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
    {True only when the loaded set is stable and at least one cell is loaded.}
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
    {AForceRandom overrides Settings.RandomExtraction for this build only.
     Sets FCurrentExtractionIsRandom accordingly.}
    procedure RebuildFrameOffsets(AForceRandom: Boolean = False);
    {Returns TReadOnlyFrameCache for random extractions with
     CacheRandomFrames off; nil otherwise so the controller's normal cache applies.}
    function RandomCacheOverride: IFrameCache;
    {One-shot random reroll, independent of Settings.RandomExtraction; lasts
     until the next event triggering a deterministic rebuild.}
    procedure ShuffleExtraction;
    procedure StartExtraction(const ACacheOverride: IFrameCache = nil);
    {AIndices scopes re-extraction to cells the action will actually consume.}
    procedure WithReExtract(const AIndices: TArray<Integer>; AAction: TProc);
    procedure OnFrameDelivered(AIndex: Integer; ABitmap: TBitmap);
    procedure OnExtractionProgress(Sender: TObject);
    procedure UpdateProgress;
    {Computes whether the status bar should be visible after the
     progress indicator hides itself. Passed to TProgressIndicator's
     post-hide visibility callback so the indicator doesn't need to
     know about FSettings.ShowStatusBar or FQuickViewMode /
     QVHideStatusBar.}
    function ComputeStatusBarPostHideVisibility: Boolean;
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
    {Per-action handlers extracted from ExecuteHotkey's case body so
     ExecuteHotkey degenerates into a dispatch table over named methods.
     Procedures own actions whose contextual guards always allow firing;
     functions return False when a contextual guard blocks the action,
     letting the keystroke fall through to TC's same-key shortcut. See
     ExecuteHotkey's Result handling for the True/False contract.}
    {Toggles}
    procedure DoToggleToolbar;
    procedure DoToggleStatusBar;
    procedure DoToggleTimecode;
    procedure DoToggleMaximize;
    procedure DoToggleFullScreen;
    function DoHamburgerMenu: Boolean;
    procedure DoCloseLister;
    {Navigation}
    procedure DoPrevFile;
    procedure DoNextFile;
    function DoPrevFrame: Boolean;
    function DoNextFrame: Boolean;
    {Frame count}
    procedure DoFrameCountInc;
    procedure DoFrameCountDec;
    {Player}
    function DoOpenInPlayer: Boolean;
    {Single source of truth for "is this command's gate satisfied right
     now?". DispatchCommand, UpdateToolbarButtons, and OnContextMenuPopup
     all consult it so a policy change (e.g. moving Refresh from
     epRequiresLoadedCell to epAlways) only needs editing one descriptor
     row instead of three parallel case statements.}
    function PolicyAllows(APolicy: TCommandEnabledPolicy): Boolean;
    {Hotkey-side counterpart to DispatchCommand: looks up ATag, checks
     PolicyAllows, dispatches if allowed, returns whether the gate let
     it through. ExecuteHotkey returns this value so a blocked-gate
     keystroke falls through to TC's same-key shortcut (e.g. mid-extract
     Ctrl+S lets TC do its own Save instead of silently no-op'ing).
     Menu / button entry points use DispatchCommand instead, which
     simply skips when the gate is closed — they have no fall-through
     semantic to preserve.}
    function TryDispatchCommand(ATag: Integer; AContextCellIndex: Integer = -1): Boolean;
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
    constructor CreateForPlugin(AParentWin: HWND; const AFileName: string; ASettings: TPluginSettings; const AFFmpegPath: string; const AServices: TPluginServices);
    destructor Destroy; override;
    procedure LoadFile(const AFileName: string);
    procedure ApplyListerParams(AParams: Integer);
    {Single entrypoint for save/copy/select/refresh/settings commands.
     Hotkey actions, the right-click context menu, the toolbar buttons,
     and the TC lc_Copy lister command all route through here so the
     wrapping (WithReExtract on save/copy actions) lives in exactly one
     place. ATag accepts the CM_* constants from ToolbarLayout.}
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
  SettingsDlg, FileNavigator, Logging, PathExpand, BannerInfo, TimecodeOverlay,
  ProgressModalForm,
  PlatformDetect, Defaults,
  ToolbarBuilder, {still needed for the TToolbarHandles type alias used in CreateToolbar's local H}
  ProgressReporter, FormProgressReporter, OverrideFramesScope,
  ToolbarGlyphLibrary, SaveResolutionExtractor,
  HotkeysVcl, PluginAppearance, FFmpegExe,
  ExtractionWorker, ViewModeLogic, ViewModeLayout,
  FrameExtractor, ProbeCache,
  System.Math, Vcl.Clipbrd,
  StatusBarHostBar, KeyInterceptionSubclass;

{Embedded toolbar glyph resources; consumed by TToolbarGlyphLibrary. The
 .res is generated from icons.rc by cgrc as a pre-build step in build.bat
 and test.bat — brcc32 (the default $R 'foo.rc' compiler) emits 16-bit-
 format resources that the Win64 linker rejects. The $R directive must
 stay on PluginForm.pas because HInstance in ToolbarGlyphLibrary.pas
 resolves to the same DLL module; if the resource were attached to the
 glyph library unit instead the linker would still bundle it in the same
 module image and this comment block would not exist.}
{$R icons.res}

var
  {Subsystem logger; closure captures the 'Form' tag once at unit
   initialization.}
  FormLog: TProc<string>;

{Status bar panel widths are now driven by the template engine in
 StatusBarRenderer: each token's "width=auto" measurement uses the
 sample text registered in StatusBarTokens.StatusBarTokenSampleText,
 and explicit "width=N" overrides them per token in the user's
 template (DEF_STATUSBAR_TEMPLATE for the default layout).
 Command tags, mode captions, sizing labels, and toolbar actions are
 defined in ToolbarLayout.}

{TPluginForm}

procedure TPluginForm.OnFrameViewCtrlWheel(Sender: TObject; AWheelDelta: Integer);
begin
  if AWheelDelta > 0 then
    ZoomBy(ZOOM_IN_FACTOR)
  else
    ZoomBy(ZOOM_OUT_FACTOR);
end;

{ TPluginCommandHandlers }

constructor TPluginCommandHandlers.Create(AForm: TPluginForm);
begin
  inherited Create;
  FForm := AForm;
  FNextContextCellIndex := -1;
end;

procedure TPluginCommandHandlers.SetContextCellIndex(AValue: Integer);
begin
  FNextContextCellIndex := AValue;
end;

function TPluginCommandHandlers.MakeReExtract: TReExtractAction;
var
  Form: TPluginForm;
begin
  {Local alias captured by the anonymous method, so the closure holds
   the form reference by value instead of indirectly via Self (which
   would re-resolve through the handler instance on every invocation).}
  Form := FForm;
  Result := procedure(const AIndices: TArray<Integer>; AAction: TProc)
    begin
      Form.WithReExtract(AIndices, AAction);
    end;
end;

procedure TPluginCommandHandlers.SaveFrame;
var
  ResolvedIdx: Integer;
begin
  {Same selection-first picking the original CM_SAVE_FRAME branch did:
   PickActionCell consults the selection / focused cell / first cell in
   that order. -1 (no context cell) lets every entry path share the
   policy — only Copy frame forwards a context cell. Resolved once and
   passed straight through to SaveFrame so any subsequent state change
   while the dialog is open doesn't disagree with what was promised.}
  ResolvedIdx := FForm.FExporter.PickActionCell(-1);
  if ResolvedIdx >= 0 then
    FForm.FExporter.SaveFrame(FForm.FFileName, ResolvedIdx, MakeReExtract());
end;

procedure TPluginCommandHandlers.SaveFrames;
begin
  FForm.FExporter.SaveFrames(FForm.FFileName, MakeReExtract());
end;

procedure TPluginCommandHandlers.SaveView;
begin
  {Default Save view: seed the dialog with the persisted setting.}
  FForm.FExporter.SaveView(FForm.FFileName, FForm.FSettings.SaveAtLiveResolution, MakeReExtract());
end;

procedure TPluginCommandHandlers.SaveViewLive;
begin
  {Explicit "view resolution" variant from the Save view dropdown.}
  FForm.FExporter.SaveView(FForm.FFileName, True, MakeReExtract());
end;

procedure TPluginCommandHandlers.SaveViewNative;
begin
  {Explicit "native size" variant from the Save view dropdown.}
  FForm.FExporter.SaveView(FForm.FFileName, False, MakeReExtract());
end;

procedure TPluginCommandHandlers.CopyFrame;
var
  ResolvedIdx: Integer;
begin
  {Only Copy frame forwards FNextContextCellIndex to PickActionCell.
   The right-click context menu wires its captured cursor cell through
   SetContextCellIndex so a no-selection user gets the cell they
   clicked on; when a selection exists, PickActionCell's step 1 takes
   precedence and Copy frame acts on the first selected cell regardless
   of where the right-click landed (matches Save frame from the same
   menu and matches TC's "right-click anywhere acts on the selection"
   convention). The toolbar button, configurable hotkey, and TC lc_Copy
   all leave FNextContextCellIndex at -1 and so never reach the
   context-cell branch — selection-first behaves identically there.

   The re-extract gate lives inside CopyFrame (it temp-flips
   SaveAtLiveResolution := CopyAtLiveResolution and decides from
   there), so the dispatch just hands over the callback rather than
   wrapping the call in WithReExtract upfront. Mirrors the CopyView /
   SaveView pattern.}
  ResolvedIdx := FForm.FExporter.PickActionCell(FNextContextCellIndex);
  if ResolvedIdx >= 0 then
    FForm.FExporter.CopyFrame(ResolvedIdx, MakeReExtract());
end;

procedure TPluginCommandHandlers.CopyView;
begin
  {Default Copy view: honour the persisted CopyAtLiveResolution
   (separate setting from the save side since 1.1.3.4).}
  FForm.FExporter.CopyView(FForm.FSettings.CopyAtLiveResolution, MakeReExtract());
end;

procedure TPluginCommandHandlers.CopyViewLive;
begin
  {Explicit "view resolution" variant from the Copy view dropdown.}
  FForm.FExporter.CopyView(True, MakeReExtract());
end;

procedure TPluginCommandHandlers.CopyViewNative;
begin
  {Explicit "native size" variant from the Copy view dropdown.}
  FForm.FExporter.CopyView(False, MakeReExtract());
end;

procedure TPluginCommandHandlers.SelectAll;
begin
  FForm.FFrameView.SelectAll;
end;

procedure TPluginCommandHandlers.DeselectAll;
begin
  FForm.FFrameView.DeselectAll;
end;

procedure TPluginCommandHandlers.Refresh;
begin
  FForm.RefreshExtraction;
end;

procedure TPluginCommandHandlers.Shuffle;
begin
  FForm.ShuffleExtraction;
end;

procedure TPluginCommandHandlers.Settings;
begin
  FForm.ShowSettings;
end;

function TPluginCommandHandlers.BuildTable: TCommandTable;
var
  H: TPluginCommandHandlers;
begin
  {Local alias so the executor closures capture H (the typed handler
   reference) rather than via Self (which would round-trip through
   the captured closure environment on every invocation).}
  H := Self;
  SetLength(Result, 14);
  Result[0].Tag := CM_SAVE_FRAME;
  Result[0].ActionEnum := paSaveFrame;
  Result[0].EnabledPolicy := epRequiresExtract;
  Result[0].Executor := procedure begin H.SaveFrame end;
  Result[1].Tag := CM_SAVE_FRAMES;
  Result[1].ActionEnum := paSaveFrames;
  Result[1].EnabledPolicy := epRequiresExtract;
  Result[1].Executor := procedure begin H.SaveFrames end;
  Result[2].Tag := CM_SAVE_VIEW;
  Result[2].ActionEnum := paSaveView;
  Result[2].EnabledPolicy := epRequiresExtract;
  Result[2].Executor := procedure begin H.SaveView end;
  Result[3].Tag := CM_SAVE_VIEW_LIVE;
  Result[3].ActionEnum := paSaveViewLive;
  Result[3].EnabledPolicy := epRequiresExtract;
  Result[3].Executor := procedure begin H.SaveViewLive end;
  Result[4].Tag := CM_SAVE_VIEW_NATIVE;
  Result[4].ActionEnum := paSaveViewNative;
  Result[4].EnabledPolicy := epRequiresExtract;
  Result[4].Executor := procedure begin H.SaveViewNative end;
  Result[5].Tag := CM_COPY_FRAME;
  Result[5].ActionEnum := paCopyFrame;
  Result[5].EnabledPolicy := epRequiresExtract;
  Result[5].Executor := procedure begin H.CopyFrame end;
  Result[6].Tag := CM_COPY_VIEW;
  Result[6].ActionEnum := paCopyView;
  Result[6].EnabledPolicy := epRequiresExtract;
  Result[6].Executor := procedure begin H.CopyView end;
  Result[7].Tag := CM_COPY_VIEW_LIVE;
  Result[7].ActionEnum := paCopyViewLive;
  Result[7].EnabledPolicy := epRequiresExtract;
  Result[7].Executor := procedure begin H.CopyViewLive end;
  Result[8].Tag := CM_COPY_VIEW_NATIVE;
  Result[8].ActionEnum := paCopyViewNative;
  Result[8].EnabledPolicy := epRequiresExtract;
  Result[8].Executor := procedure begin H.CopyViewNative end;
  Result[9].Tag := CM_SELECT_ALL;
  Result[9].ActionEnum := paSelectAllFrames;
  Result[9].EnabledPolicy := epRequiresLoadedCell;
  Result[9].Executor := procedure begin H.SelectAll end;
  Result[10].Tag := CM_DESELECT_ALL;
  {DeselectAll has no configurable hotkey today — paNone is the sentinel
   and FindCommandByAction filters it so ExecuteHotkey can never reach
   here through an unbound keystroke.}
  Result[10].ActionEnum := paNone;
  Result[10].EnabledPolicy := epRequiresSelection;
  Result[10].Executor := procedure begin H.DeselectAll end;
  Result[11].Tag := CM_REFRESH;
  Result[11].ActionEnum := paRefreshExtraction;
  Result[11].EnabledPolicy := epRequiresLoadedCell;
  Result[11].Executor := procedure begin H.Refresh end;
  Result[12].Tag := CM_SHUFFLE;
  Result[12].ActionEnum := paShuffleExtraction;
  Result[12].EnabledPolicy := epAlways;
  Result[12].Executor := procedure begin H.Shuffle end;
  Result[13].Tag := CM_SETTINGS;
  Result[13].ActionEnum := paSettings;
  Result[13].EnabledPolicy := epAlways;
  Result[13].Executor := procedure begin H.Settings end;
end;

{ TPluginForm }

constructor TPluginForm.CreateForPlugin(AParentWin: HWND; const AFileName: string; ASettings: TPluginSettings; const AFFmpegPath: string; const AServices: TPluginServices);
begin
  CreateNew(nil);
  {Null placeholder; CreateStatusBar swaps in the real indicator. Assigned
   here so InitializeWindowing's handle-creation Resize has a non-nil target.}
  FProgressIndicator := TProgressIndicator.Create;
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

  {Capture caller-provided dependencies before the Initialize phases
   start reading them. FServices owns its ProbeCache from this assignment
   onward; the destructor frees it. Factory interface fields are
   refcount-managed by the record copy.}
  FSettings := ASettings;
  FFFmpegPath := AFFmpegPath;
  FServices := AServices;

  InitializeWindowing(AParentWin);
  InitializeUI;

  {TDebugLog.Configure is called once at TC startup by ListSetDefaultParams (which
   honours [debug] LogEnabled in release builds and forces the log on in
   DEBUG builds). Re-applying it here would override that decision per
   file open, which is unwanted: the user's toggle is supposed to be
   process-wide, and the DEBUG-build path is supposed to stay verbose
   regardless of any user setting.}
  FormLog(Format('CreateForPlugin: file=%s handle=$%s', [AFileName, IntToHex(Handle)]));

  InitializeExtractionStack;
  InitializeServices;

  LoadFile(AFileName);

  FInitialized := True;
end;

procedure TPluginForm.InitializeWindowing(AParentWin: HWND);
var
  R: TRect;
begin
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
end;

procedure TPluginForm.InitializeUI;
begin
  {Step 105 (C1, partial): toolbar orchestration moved into
   TToolbarController. The controller owns FGlyphLibrary + layout state
   + the build/layout/hamburger-click/button-enable methods; the form
   keeps non-owning widget pointer-cache fields populated from the
   controller's Build result.}
  FToolbarController := TToolbarController.Create(Self);
  CreateToolbar;
  CreateStatusBar;
  CreateFrameView;
  CreateContextMenu;
  CreateErrorLabel;
  ApplySettings;

  {Wire OnChange after ApplySettings so initial Position assignment doesn't
   trigger a save that overwrites the loaded FramesCount}
  FEditFrameCount.OnChange := OnFrameCountChange;
end;

procedure TPluginForm.InitializeExtractionStack;
begin
  {ProbeCache lives in the services container; form took ownership at
   construction (FServices := AServices in CreateForPlugin), so the
   destructor is responsible for freeing it.

   Create extraction controller with the cache produced by the injected
   factory. The TWindowMessageSink wraps the form's HWND so worker
   threads can post WM_FRAME_READY / WM_EXTRACTION_DONE without needing
   the HWND directly. The cache-vs-null choice that used to live in an
   inline if FSettings.CacheEnabled branch now lives inside
   TProductionFrameCacheFactory.CreateCache, keeping this site agnostic
   of the concrete cache class so tests can wire a fake factory.}
  FExtractCtrl := TExtractionController.Create(TWindowMessageSink.Create(Handle),
    FServices.FrameCacheFactory.CreateCache(FSettings));
  FExtractCtrl.OnFrameDelivered := OnFrameDelivered;
  FExtractCtrl.OnProgress := OnExtractionProgress;

  FExporter := TFrameExporter.Create(FFrameView, FSettings);
  {Run the file-reference clipboard PNG encode inside a modal "please
   wait" dialog parented to this form. The modal blocks UI re-entry,
   navigation, and accidental re-clicks while the worker thread runs.
   Cancellation detaches the thread (it cleans up after itself). See
   ProgressModalForm for the thread-completion mechanism (PostMessage
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
      FProgressIndicator.Show;
      try
        Result := RunWithProgress(Self, AThread, AText);
      finally
        FProgressIndicator.Hide;
        FProgressBar.Style := pbstNormal;
      end;
    end;
end;

procedure TPluginForm.InitializeServices;
begin
  FSettingsToggle := TSettingsToggleService.Create(FSettings);

  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := ANIM_INTERVAL_MS;
  FAnimTimer.OnTimer := OnAnimTimer;
  FAnimTimer.Enabled := True;

  {Step 105 (C1, part 2): TViewportRefreshDebouncer owns the timer + the
   last-extraction-max-side memo + the precondition / fire logic. The
   form supplies 3 callbacks: should-refresh (combined preconditions),
   compute-current-max-side, and the action (SoftRefreshExtraction).}
  FViewportRefreshDebouncer := TViewportRefreshDebouncer.Create(Self,
    VIEWPORT_REFRESH_DEBOUNCE_MS,
    function: Boolean
    begin
      Result := (FSettings <> nil) and FSettings.AutoRefreshOnViewportChange
        and FSettings.ScaledExtraction and FVideoInfo.IsValid
        and (FFileName <> '') and (Length(FOffsets) > 0);
    end,
    function: Integer
    var
      ViewportFrames: Integer;
    begin
      ViewportFrames := ViewportFrameCount(FFrameView.ViewMode, Length(FOffsets));
      Result := CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight,
        ViewportFrames, FFrameView.AspectRatio,
        FVideoInfo.Width, FVideoInfo.Height,
        FSettings.MinFrameSide, FSettings.MaxFrameSide);
    end,
    procedure
    begin
      SoftRefreshExtraction;
    end);

  FLoadTimer := TLoadTimeRecorder.Create;

  {Build the command dispatch table after every collaborator the
   handlers read from (FExporter, FFrameView, FSettings, FFileName)
   has been constructed. The handlers capture FForm = Self, so the
   closures inside FCommandTable indirectly hold those collaborators
   through Self — that's fine because the form outlives the table by
   construction.}
  FCommandHandlers := TPluginCommandHandlers.Create(Self);
  FCommandTable := FCommandHandlers.BuildTable;
end;

destructor TPluginForm.Destroy;
begin
  {Release the table's executor closures BEFORE freeing the handler
   instance they captured. Each closure holds a reference to
   FCommandHandlers via the H local in BuildTable; nilling the table
   drops that reference so the FreeAndNil below is the last owner.
   Without this ordering the closures would outlive their captured
   Self briefly during finalization.}
  FCommandTable := nil;
  FreeAndNil(FCommandHandlers);
  FreeAndNil(FSettingsToggle);
  if HandleAllocated then
    RemoveWindowSubclass(Handle, @FormSubclassProc, FORM_SUBCLASS_ID);
  if FParentWnd <> 0 then
    RemoveWindowSubclass(FParentWnd, @ParentSubclassProc, 1);
  {FAnimTimer may not exist yet if destructor runs during CreateForPlugin
   (VCL can destroy a windowed control before the constructor finishes)}
  if Assigned(FAnimTimer) then
    FAnimTimer.Enabled := False;
  FExtractCtrl.Free;
  {ProbeCache ownership was transferred from DoListLoad into FServices
   at construction; this is the matching release.}
  FServices.ProbeCache.Free;
  FServices.ProbeCache := nil;
  if Assigned(FFrameView) then
    FFrameView.ClearCells;
  FExporter.Free;
  {Step 105: FToolbarController owns no widget components (those are
   Self-owned via TComponent), only the build state + the FGlyphLibrary
   reference. Its destructor is intentionally empty wrt FGlyphLibrary
   — the glyph library is also Self-owned and freed by inherited
   destructor. Free the controller before inherited so its destructor
   runs while form fields are still alive.}
  FreeAndNil(FToolbarController);
  FreeAndNil(FViewportRefreshDebouncer);
  FreeAndNil(FLoadTimer);
  FreeAndNil(FProgressIndicator);
  {FStatusBarRenderer is owned by Self (step 59) — inherited TForm.Destroy
   iterates FComponents and frees it. The resolver method-reference
   captures Self; release happens during the inherited pass while
   Self's fields are still memory-valid.}
  inherited;
end;

procedure TPluginForm.CreateToolbar;
var
  H: TToolbarHandles;
  VM: TViewMode;
begin
  {Step 105 (C1): TToolbarController owns the glyph library + the
   TToolbarBuilder invocation + the per-build layout state. The form
   caches the widget pointer handles below so the ~90 existing
   FToolbar / FToolbarButtons / etc. reads across the form keep
   compiling without churn.}
  H := FToolbarController.Build(
    OnModeButtonClick, OnSizingMenuClick, OnTimecodeButtonClick,
    OnToolbarButtonClick, OnContextMenuClick, OnViewDropdownPopup,
    OnHamburgerClick, OnHamburgerMenuPopup);
  FToolbarImages := FToolbarController.GlyphLibrary.Images;
  FToolbar := H.Toolbar;
  FEditFrameCount := H.EditFrameCount;
  FUpDown := H.UpDown;
  FLblFrames := H.LblFrames;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    FModeButtons[VM] := H.ModeButtons[VM];
    FModePopups[VM] := H.ModePopups[VM];
  end;
  FBtnTimecode := H.BtnTimecode;
  FToolbarButtons := H.ToolbarButtons;
  FRefreshPopup := H.RefreshPopup;
  FSaveViewPopup := H.SaveViewPopup;
  FCopyViewPopup := H.CopyViewPopup;
  FBtnHamburger := H.BtnHamburger;
  FHamburgerMenu := H.HamburgerMenu;
end;

procedure TPluginForm.LayoutToolbar;
const
  CTRL_GAP = 8;
begin
  if not FInitialized then
    Exit;
  FToolbarController.Layout(FToolbar.ClientWidth, CTRL_GAP);
end;

procedure TPluginForm.OnHamburgerClick(Sender: TObject);
begin
  FToolbarController.HamburgerClick;
end;

procedure TPluginForm.OnHamburgerMenuPopup(Sender: TObject);
var
  State: THamburgerMenuState;
  VM: TViewMode;
begin
  State.VisibleCount := FToolbarController.VisibleElementCount;
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

  FreeAndNil(FProgressIndicator);
  FProgressIndicator := TStatusBarProgressIndicator.Create(FStatusBar,
    ComputeStatusBarPostHideVisibility,
    function(out AStretch: Boolean; out ALayout: TProgressBarLayout): Boolean
    begin
      Result := FSettings <> nil;
      if Result then
      begin
        AStretch := FSettings.StatusBarStretchPanels;
        ALayout := FSettings.ProgressBarLayout;
      end;
    end);
  FProgressBar := FProgressIndicator.ProgressBar;

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
   used to call PlatformDetect itself, but lifting the dependency to
   the call site keeps StatusBarFormatters truly pure.}
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
  FProgressIndicator.Reposition;
end;

function TPluginForm.ResolveStatusBarHeight(ATextHeight: Integer): Integer;
begin
  {VCL-bound wrapper: hands the form state to the pure resolver in
   Types so the policy stays unit-testable. FStatusBar.CurrentPPI
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

  AValues.LoadTimeText := FLoadTimer.Formatted;
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
  {OR with FProgressIndicator.Visible so an in-flight progress display
   does not get cancelled when the user opens / accepts the settings
   dialog mid-extraction. The bar is shown by FProgressIndicator.Show
   (which forces the status bar visible regardless of the user's
   persisted preference) and only hidden by FProgressIndicator.Hide
   when the run finishes; without this guard, accepting the dialog
   would force the bar back to its persisted "off" state and the
   still-running progress would vanish.}
  FStatusBar.Visible := FProgressIndicator.Visible or ComputeStatusBarPostHideVisibility;
  {Pick up any change to the progress bar layout setting on the fly,
   so the user sees the new layout before the current run completes
   instead of having to wait for the next extraction.}
  if FProgressIndicator.Visible then
    FProgressIndicator.Reposition;
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
  FViewportRefreshDebouncer.Schedule;
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
  FLoadTimer.Start;
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

  FVideoInfo := FServices.ProbeCache.TryGetOrProbe(FFileName, FFFmpegPath);

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
  FLoadTimer.Start;
  UpdateToolbarButtons;

  FProgressBar.Style := pbstMarquee;
  FProgressIndicator.Show;
  FAnimTimer.Enabled := True;

  if FSettings.ScaledExtraction then
  begin
    ViewportFrames := ViewportFrameCount(FFrameView.ViewMode, Length(FOffsets));
    Options := FSettings.Extraction.ToExtractionOptions(
      CalcExtractionMaxSide(FScrollBox.ClientWidth, FScrollBox.ClientHeight, ViewportFrames, FFrameView.AspectRatio, FVideoInfo.Width, FVideoInfo.Height, FSettings.MinFrameSide, FSettings.MaxFrameSide));
  end
  else
    Options := FSettings.Extraction.ToExtractionOptions;

  {Remember the extraction size so the debouncer's fire-time compare
   can decide whether the next viewport-change event actually changed
   anything.}
  FViewportRefreshDebouncer.RecordExtractionMaxSide(Options.MaxSide);

  Extractor := FServices.FrameExtractorFactory.CreateExtractor(FFFmpegPath);
  FExtractCtrl.Start(Extractor, FFileName, FOffsets, FSettings.MaxWorkers, FSettings.MaxThreads, Options, ACacheOverride);
end;

procedure TPluginForm.WithReExtract(const AIndices: TArray<Integer>; AAction: TProc);
var
  Target: Integer;
  Ctx: TSaveResolutionContext;
  Reextractor: TSaveResolutionExtractor;
  Frames: TArray<TBitmap>;
  Scope: IOverrideFramesScope;
begin
  {Step 107 (N1): WithReExtract used to mix 3 concerns inline (bitmap
   lifetime + exporter override-frames cycle + 4-callback progress
   wiring). The 3 helpers — TFormProgressReporter, TSaveResolutionExtractor's
   new IProgressReporter, TOverrideFramesScope RAII — separate them.}
  Target := PickSaveMaxSide(FVideoInfo.Width, FVideoInfo.Height, FSettings.ScaledExtraction, FSettings.MaxFrameSide);
  if not NeedsReExtractForSave(FSettings.SaveAtLiveResolution, Length(AIndices), Target, FViewportRefreshDebouncer.LastExtractionMaxSide) then
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

  FormLog(Format('WithReExtract: starting target=%d cells indices=%d', [Target, Length(AIndices)]));
  Reextractor := TSaveResolutionExtractor.Create(FExtractCtrl.Cache, FServices.FrameExtractorFactory.CreateExtractor(FFFmpegPath));
  try
    Reextractor.Reporter := TFormProgressReporter.Create(FProgressIndicator);
    Frames := Reextractor.ExtractAtTarget(Ctx, Target, AIndices);
  finally
    Reextractor.Free;
  end;
  FormLog(Format('WithReExtract: re-extract finished, Frames length=%d', [Length(Frames)]));

  {Scope takes ownership of Frames + manages the exporter override-frames
   cycle. Auto-released at proc end: clears override THEN frees bitmaps
   so the exporter never sees freed memory. Replaces two nested
   try-finally blocks.}
  Scope := TOverrideFramesScope.Create(FExporter, Frames);
  AAction;
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

function TPluginForm.ComputeStatusBarPostHideVisibility: Boolean;
begin
  Result := FSettings.ShowStatusBar and not(FQuickViewMode and FSettings.QVHideStatusBar);
end;

procedure TPluginForm.UpdateProgress;
begin
  UpdateToolbarButtons;
  if FExtractCtrl.FramesLoaded >= FExtractCtrl.TotalFrames then
  begin
    FLoadTimer.Finalize;
    UpdateStatusBar;
    FProgressIndicator.Hide;
    FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  end else if (FExtractCtrl.FramesLoaded > 0) and FProgressIndicator.Visible then
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
  FLoadTimer.Finalize;
  UpdateStatusBar;
  FProgressIndicator.Hide;
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

function TPluginForm.PolicyAllows(APolicy: TCommandEnabledPolicy): Boolean;
begin
  {Mirrors the gate logic that used to live inline in DispatchCommand /
   UpdateToolbarButtons / OnContextMenuPopup. Each policy maps to the
   exact same predicate those ladders evaluated, so behavior is
   preserved bit-for-bit while the rule itself lives in one place.}
  case APolicy of
    epAlways:
      Result := True;
    {Save / Copy must wait until extraction settles. PickActionCell
     would otherwise return -1 (or a stale cell that just got reset
     to a placeholder by a Refresh) and the action would silently
     no-op, which reads as a broken button / hotkey.}
    epRequiresExtract:
      Result := CanExportFrames;
    {Refresh / SelectAll. Refresh stays clickable during extraction so
     the user can cancel and restart with new settings without waiting
     for the current run to finish.}
    epRequiresLoadedCell:
      Result := Assigned(FFrameView) and FFrameView.HasLoadedCells;
    epRequiresSelection:
      Result := Assigned(FFrameView) and (FFrameView.SelectedCount > 0);
  else
    Result := False;
  end;
end;

function TPluginForm.TryDispatchCommand(ATag: Integer; AContextCellIndex: Integer = -1): Boolean;
var
  Desc: TCommandDescriptor;
begin
  if not FindCommandByTag(FCommandTable, Cardinal(ATag), Desc) then
    Exit(False);
  Result := PolicyAllows(Desc.EnabledPolicy);
  if not Result then
    Exit;
  FCommandHandlers.SetContextCellIndex(AContextCellIndex);
  Desc.Executor();
end;

function TPluginForm.ExecuteHotkey(AAction: TPluginAction): Boolean;
var
  Desc: TCommandDescriptor;
begin
  Result := True;
  case AAction of
    paToggleToolbar:     DoToggleToolbar;
    paToggleStatusBar:   DoToggleStatusBar;
    paToggleTimecode:    DoToggleTimecode;
    paToggleMaximize:    DoToggleMaximize;
    paToggleFullScreen:  DoToggleFullScreen;
    paHamburgerMenu:     Result := DoHamburgerMenu;
    paCloseLister:       DoCloseLister;
    paPrevFile:          DoPrevFile;
    paNextFile:          DoNextFile;
    paPrevFrame:         Result := DoPrevFrame;
    paNextFrame:         Result := DoNextFrame;
    paFrameCountInc:     DoFrameCountInc;
    paFrameCountDec:     DoFrameCountDec;
    paOpenInPlayer:      Result := DoOpenInPlayer;
    paZoomIn:            ZoomBy(ZOOM_IN_FACTOR);
    paZoomOut:           ZoomBy(ZOOM_OUT_FACTOR);
    paZoomReset:         ResetZoom;
    {View-mode actions pass the canonical digit to SwitchOrCycleMode so the
     cycle-submodes logic keeps working regardless of what key the user
     bound the action to.}
    paViewModeSmartGrid: SwitchOrCycleMode(Ord('1'));
    paViewModeGrid:      SwitchOrCycleMode(Ord('2'));
    paViewModeScroll:    SwitchOrCycleMode(Ord('3'));
    paViewModeFilmstrip: SwitchOrCycleMode(Ord('4'));
    paViewModeSingle:    SwitchOrCycleMode(Ord('5'));
  else
    {Table-routed fallback: any remaining TPluginAction maps to a CM_*
     descriptor (Save / Copy / Refresh / Shuffle / Settings /
     SelectAll). TryDispatchCommand checks the descriptor's enable
     policy and dispatches; a mid-extraction keystroke falls through
     (Result := False) instead of acting on an unstable cell set,
     matching the toolbar / context-menu visual lock and TC's
     same-key shortcut takes over.

     paNone never reaches here — FindCommandByAction filters it so
     DeselectAll's slot (the only descriptor with ActionEnum=paNone)
     can't false-match an unbound keystroke.}
    if FindCommandByAction(FCommandTable, AAction, Desc) then
      Result := TryDispatchCommand(Integer(Desc.Tag))
    else
      Result := False;
  end;
end;

{Toggles}

procedure TPluginForm.DoToggleToolbar;
begin
  FToolbar.Visible := not FToolbar.Visible;
  {Reclaim focus so TC's subclass sees keystrokes again}
  if not FToolbar.Visible then
    Winapi.Windows.SetFocus(Handle);
  if not FQuickViewMode then
    FSettingsToggle.PersistToolbarVisible(FToolbar.Visible);
end;

procedure TPluginForm.DoToggleStatusBar;
begin
  FStatusBar.Visible := not FStatusBar.Visible;
  if not FQuickViewMode then
    FSettingsToggle.PersistStatusBarVisible(FStatusBar.Visible);
end;

procedure TPluginForm.DoToggleTimecode;
begin
  OnTimecodeButtonClick(nil);
end;

procedure TPluginForm.DoToggleMaximize;
begin
  ForwardKeyToLister(VK_F11, False);
end;

procedure TPluginForm.DoToggleFullScreen;
begin
  ForwardKeyToLister(VK_RETURN, True);
end;

function TPluginForm.DoHamburgerMenu: Boolean;
begin
  if FBtnHamburger.Visible then
  begin
    OnHamburgerClick(FBtnHamburger);
    Result := True;
  end
  else
    Result := False;
end;

procedure TPluginForm.DoCloseLister;
begin
  ForwardKeyToLister(VK_ESCAPE, False);
end;

{Navigation}

procedure TPluginForm.DoPrevFile;
begin
  NavigateToAdjacentFile(-1);
end;

procedure TPluginForm.DoNextFile;
begin
  NavigateToAdjacentFile(1);
end;

function TPluginForm.DoPrevFrame: Boolean;
begin
  {Frame navigation is only meaningful in single-view mode. Returning
   False when the guard fails lets the keystroke fall through to any
   edit that had focus (same as the pre-refactor behaviour).}
  if FFrameView.ViewMode = vmSingle then
  begin
    FFrameView.NavigateFrame(-1);
    UpdateStatusBar;
    Result := True;
  end
  else
    Result := False;
end;

function TPluginForm.DoNextFrame: Boolean;
begin
  if FFrameView.ViewMode = vmSingle then
  begin
    FFrameView.NavigateFrame(1);
    UpdateStatusBar;
    Result := True;
  end
  else
    Result := False;
end;

{Frame count}

procedure TPluginForm.DoFrameCountInc;
begin
  FUpDown.Position := FUpDown.Position + 1;
end;

procedure TPluginForm.DoFrameCountDec;
begin
  FUpDown.Position := FUpDown.Position - 1;
end;

{Player}

function TPluginForm.DoOpenInPlayer: Boolean;
begin
  {Don't consume Enter while the frame-count edit has focus — the
   edit-focus fallback below commits the value. No file loaded is also
   a valid no-op: let the key pass through.}
  if (GetFocus <> FEditFrameCount.Handle) and (FFileName <> '') then
  begin
    ShellExecute(Handle, 'open', PChar(FFileName), nil, nil, SW_SHOWNORMAL);
    Result := True;
  end
  else
    Result := False;
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
  FProgressIndicator.Hide;
end;

procedure TPluginForm.HideError;
begin
  FLblError.Visible := False;
  FFrameView.Visible := True;
  FAnimTimer.Enabled := True;
end;

procedure TPluginForm.UpdateFrameViewSize;
var
  VW, VH: Integer;
  Zoomed: Boolean;
  ScrollPolicy: TScrollbarPolicy;
begin
  Zoomed := not SameValue(FFrameView.ZoomFactor, 1.0, ZOOM_EPSILON);

  {Configure scrollbox FIRST so ClientWidth/ClientHeight reflect scrollbar state.
   Per-mode visibility rule lives in ViewModeLayout (Information Expert).}
  ScrollPolicy := GetScrollbarPolicy(FFrameView.ViewMode, FFrameView.ZoomMode, Zoomed);
  FScrollBox.HorzScrollBar.Visible := ScrollPolicy.HorzVisible;
  FScrollBox.VertScrollBar.Visible := ScrollPolicy.VertVisible;

  {Read viewport after scrollbar config}
  VW := FScrollBox.ClientWidth;
  VH := FScrollBox.ClientHeight;
  FFrameView.SetViewport(VW, VH);

  {Calculate column count for grid mode (use frozen base when zoomed).
   Non-grid modes pass 0 so the layout strategy auto-decides.}
  if FFrameView.ViewMode = vmGrid then
    FFrameView.ColumnCount := GridColumnCountFor(FFrameView.ZoomMode,
      FFrameView.CalcFitColumns(FFrameView.BaseW, FFrameView.BaseH),
      FFrameView.DefaultColumnCount)
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
  FSettingsToggle.PersistTimecodeVisible(FFrameView.ShowTimecode);
end;

procedure TPluginForm.DispatchCommand(ATag: Integer; AContextCellIndex: Integer = -1);
begin
  {Single entry point for the right-click context menu, the toolbar
   buttons, and TC's lc_Copy. Walks FCommandTable once, evaluates the
   matched descriptor's enable policy via PolicyAllows, and invokes
   the executor closure. The closure does the same work the original
   CM_* case branches did (see TPluginCommandHandlers in this unit)
   — the table is just data, the policy decision lives in PolicyAllows,
   and the per-command logic lives in the handler class. Three
   responsibilities, three locations, no four-way parallel ladder.

   Selection-first picking for the singular Save / Copy frame variants
   lives inside the handlers (SaveFrame / CopyFrame call PickActionCell)
   — the resolved index is computed once and reused so a user
   selection change while WithReExtract pumps the message loop can't
   make the saved cell disagree with the dialog's promise.

   Singular Copy frame is the only command that consults
   AContextCellIndex (the right-click cell): handlers read it via
   FCommandHandlers.FNextContextCellIndex which we prime here before
   invoking the executor. Other handlers ignore the field so toolbar /
   hotkey / lc_Copy entry points (which pass -1) behave identically.

   Save methods receive a re-extract callback (via
   TPluginCommandHandlers.MakeReExtract) so the dialog opens
   immediately and re-extract runs only after the user commits. The
   alternative (wrapping the dialog in WithReExtract upfront) blocked
   TC for seconds before the dialog appeared and re-extracted even
   when the user then cancelled.

   Menu / button entry points discard the gate result: a blocked
   command silently no-ops (UpdateToolbarButtons / OnContextMenuPopup
   already greyed out the affordance, so this is just defense in
   depth). Hotkey callers use TryDispatchCommand instead — they need
   the False-return for TC fall-through semantics.}
  TryDispatchCommand(ATag, AContextCellIndex);
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
begin
  {Step 105: the per-button enable policy lookup moved into
   TToolbarController.UpdateButtonEnables; the form supplies a
   callback that maps a button tag to "is this enabled right now?"
   via the command-descriptor table + PolicyAllows. The save/copy
   buttons wait until extraction settles (epRequiresExtract ->
   CanExportFrames) so the action doesn't silently no-op; refresh
   stays clickable during extraction (epRequiresLoadedCell) so the
   user can cancel and restart; settings is always enabled (epAlways).
   Buttons whose tag has no descriptor default to True via the
   controller's fallback path (defense in depth for future toolbar
   items).}
  FToolbarController.UpdateButtonEnables(
    function(ATag: Integer): Boolean
    var
      Desc: TCommandDescriptor;
    begin
      if FindCommandByTag(FCommandTable, Cardinal(ATag), Desc) then
        Result := PolicyAllows(Desc.EnabledPolicy)
      else
        Result := True;
    end);
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
  if not FInitialized then
    Exit;
  Realign;
  LayoutToolbar;
  FProgressIndicator.Reposition;
  if not FUpdatingLayout and FFrameView.Visible then
    UpdateFrameViewSize;
  {Status bar's predicted Save / Copy view dimensions depend on cell
   sizes and viewport — both change with the lister window. Refresh
   after the layout pass.}
  UpdateStatusBar;
  {Viewport width/height may have changed the MaxSide bucket; debounce
   and let the timer decide whether to refresh.}
  FViewportRefreshDebouncer.Schedule;
end;

function TPluginForm.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Msg: TWMMouseWheel;
begin
  if not FInitialized then
    Exit(inherited);

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

  {Forward to TFrameView so wheel logic lives in one place (WMMouseWheel).}
  if FScrollBox.Visible then
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
  if not FInitialized then
    Exit;
  if not FUpdatingLayout and FFrameView.Visible then
    UpdateFrameViewSize;
end;

procedure TPluginForm.OnContextMenuPopup(Sender: TObject);
var
  I, SelCount: Integer;
  MI: TMenuItem;
  Desc: TCommandDescriptor;
begin
  {Capture the cell under the cursor so OnContextMenuClick can route
   the right-clicked cell through DispatchCommand for Copy frame.
   CellIndexAt returns -1 when the cursor isn't over a real cell;
   PickActionCell's downstream loaded-state check filters placeholders.}
  FContextCellIndex := FFrameView.CellIndexAt(FFrameView.ScreenToClient(Mouse.CursorPos));

  {Each menu item's enable state comes from the descriptor table's
   policy — same rules UpdateToolbarButtons applies. Save / copy wait
   until extraction settles (epRequiresExtract) so the action sees a
   consistent set: mid-extraction the loaded set is unstable (cells
   flip from placeholder to loaded as workers finish, and Refresh
   resets every cell back to placeholder).

   The Save frames caption is selection-aware and lives outside the
   policy table: when frames are selected the action saves only those,
   otherwise it saves all loaded frames. The caption echoes the
   selected count so the user knows which set is about to be written
   before the file dialog opens. Caption code stays here because it's
   not an enable-state concern — the policy table only owns the
   Enabled flag.}
  for I := 0 to FContextMenu.Items.Count - 1 do
  begin
    MI := FContextMenu.Items[I];
    if FindCommandByTag(FCommandTable, Cardinal(MI.Tag), Desc) then
      MI.Enabled := PolicyAllows(Desc.EnabledPolicy);
    if MI.Tag = CM_SAVE_FRAMES then
    begin
      SelCount := FFrameView.SelectedCount;
      if SelCount > 0 then
        MI.Caption := Format('Save frames (%d selected)...'#9'Ctrl+Alt+Shift+S', [SelCount])
      else
        MI.Caption := 'Save frames (all)...'#9'Ctrl+Alt+Shift+S';
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
  if not FInitialized then
    Exit;
  {Drain any frames that arrived since the last notification — covers
   the case where PostMessage notifications miss the HWND.}
  FExtractCtrl.ProcessPendingFrames;
  if FFrameView.Visible then
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

initialization
  FormLog := DebugLogger('Form');

end.
