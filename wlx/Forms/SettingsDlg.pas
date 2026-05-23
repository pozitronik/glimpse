{Settings dialog for configuring plugin behavior.
 Works on TPluginSettings directly; changes take effect only when OK is pressed.}
unit SettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  Winapi.Windows,
  Types, StatusBarLayout, Settings, Hotkeys, EnableRules,
  SettingsControlsBundles, SettingsPresenters, HotkeyUIPresenter;

type
  TSettingsForm = class(TForm)
    PageControl: TPageControl;
    TshGeneral: TTabSheet;
    LblMaxWorkers: TLabel;
    EdtMaxWorkers: TEdit;
    UdMaxWorkers: TUpDown;
    ChkMaxWorkersAuto: TCheckBox;
    LblMaxThreads: TLabel;
    EdtMaxThreads: TEdit;
    UdMaxThreads: TUpDown;
    LblMaxThreadsAuto: TLabel;
    ChkUseBmpPipe: TCheckBox;
    ChkHwAccel: TCheckBox;
    ChkUseKeyframes: TCheckBox;
    ChkRespectAnamorphic: TCheckBox;
    ChkScaledExtraction: TCheckBox;
    LblScaleTarget: TLabel;
    EdtMinFrameSide: TEdit;
    UdMinFrameSide: TUpDown;
    LblScaleSep: TLabel;
    EdtMaxFrameSide: TEdit;
    UdMaxFrameSide: TUpDown;
    LblScaleUnit: TLabel;
    ChkAutoRefreshViewport: TCheckBox;
    LblExtensions: TLabel;
    EdtExtensions: TEdit;
    LblFFmpegPath: TLabel;
    EdtFFmpegPath: TEdit;
    BtnFFmpegPath: TButton;
    LblFFmpegInfo: TLabel;
    EdtFFmpegInfo: TEdit;
    TshAppearance: TTabSheet;
    LblBackground: TLabel;
    PnlBackground: TPanel;
    BtnBackground: TButton;
    LblTCBack: TLabel;
    PnlTCBack: TPanel;
    BtnTCBack: TButton;
    LblTCAlpha: TLabel;
    EdtTCAlpha: TEdit;
    UdTCAlpha: TUpDown;
    LblTCTextAlpha: TLabel;
    EdtTCTextAlpha: TEdit;
    UdTCTextAlpha: TUpDown;
    LblTCTextColor: TLabel;
    PnlTCTextColor: TPanel;
    BtnTCTextColor: TButton;
    LblTimestampFont: TLabel;
    EdtTimestampFont: TEdit;
    BtnTimestampFont: TButton;
    LblCellGap: TLabel;
    EdtCellGap: TEdit;
    UdCellGap: TUpDown;
    LblBorder: TLabel;
    EdtBorder: TEdit;
    UdBorder: TUpDown;
    ChkShowTimecode: TCheckBox;
    CbxTimestampCorner: TComboBox;
    ChkShowToolbar: TCheckBox;
    ChkShowStatusBar: TCheckBox;
    LblProgressBarLayout: TLabel;
    CbxProgressBarLayout: TComboBox;
    LblStatusBarTemplate: TLabel;
    EdtStatusBarTemplate: TEdit;
    MemStatusBarLegend: TMemo;
    LblStatusBarFont: TLabel;
    EdtStatusBarFont: TEdit;
    BtnStatusBarFont: TButton;
    ChkStatusBarAutoWidthLive: TCheckBox;
    ChkStatusBarStretchPanels: TCheckBox;
    LblStatusBarHeight: TLabel;
    EdtStatusBarHeight: TEdit;
    UdStatusBarHeight: TUpDown;
    LblStatusBarHeightApply: TLabel;
    CbxStatusBarHeightApply: TComboBox;
    TshSave: TTabSheet;
    LblSaveFormat: TLabel;
    CbxSaveFormat: TComboBox;
    LblJpegQuality: TLabel;
    EdtJpegQuality: TEdit;
    UdJpegQuality: TUpDown;
    LblPngCompression: TLabel;
    EdtPngCompression: TEdit;
    UdPngCompression: TUpDown;
    LblBackgroundAlpha: TLabel;
    EdtBackgroundAlpha: TEdit;
    UdBackgroundAlpha: TUpDown;
    LblSaveFolder: TLabel;
    EdtSaveFolder: TEdit;
    BtnSaveFolder: TButton;
    ChkShowBanner: TCheckBox;
    LblBannerBackground: TLabel;
    PnlBannerBackground: TPanel;
    BtnBannerBackground: TButton;
    LblBannerTextColor: TLabel;
    PnlBannerTextColor: TPanel;
    BtnBannerTextColor: TButton;
    LblBannerFont: TLabel;
    EdtBannerFont: TEdit;
    BtnBannerFont: TButton;
    ChkBannerAutoSize: TCheckBox;
    LblBannerPosition: TLabel;
    CbxBannerPosition: TComboBox;
    ChkSaveAtLiveResolution: TCheckBox;
    ChkCopyAtLiveResolution: TCheckBox;
    LblCombinedMaxSide: TLabel;
    EdtCombinedMaxSide: TEdit;
    UdCombinedMaxSide: TUpDown;
    LblCombinedMaxSideUnit: TLabel;
    TshClipboard: TTabSheet;
    LblClipboardFormatsHeader: TLabel;
    ChkPublishAlphaAwareBitmap: TCheckBox;
    ChkPublishCompressedPng: TCheckBox;
    ChkPublishFlattenedBitmap: TCheckBox;
    ChkPublishBitmapHandle: TCheckBox;
    ChkClipboardAsFileReference: TCheckBox;
    TshCache: TTabSheet;
    ChkCacheEnabled: TCheckBox;
    BtnClearCache: TButton;
    LblCacheFolder: TLabel;
    EdtCacheFolder: TEdit;
    BtnCacheFolder: TButton;
    LblCacheFolderInfo: TLabel;
    EdtCacheFolderInfo: TEdit;
    LblCacheMaxSize: TLabel;
    EdtCacheMaxSize: TEdit;
    UdCacheMaxSize: TUpDown;
    LblCacheMaxSizeUnit: TLabel;
    LblCacheSizeInfo: TLabel;
    TshThumbnails: TTabSheet;
    ChkThumbnailsEnabled: TCheckBox;
    LblThumbnailMode: TLabel;
    CbxThumbnailMode: TComboBox;
    LblThumbnailPosition: TLabel;
    EdtThumbnailPosition: TEdit;
    UdThumbnailPosition: TUpDown;
    LblThumbnailPositionUnit: TLabel;
    LblThumbnailGridFrames: TLabel;
    EdtThumbnailGridFrames: TEdit;
    UdThumbnailGridFrames: TUpDown;
    TshQuickView: TTabSheet;
    ChkQVDisableNavigation: TCheckBox;
    ChkQVHideToolbar: TCheckBox;
    ChkQVHideStatusBar: TCheckBox;
    ChkShowListerMenu: TCheckBox;
    ChkListerMenuFlat: TCheckBox;
    TshHotkeys: TTabSheet;
    LvwHotkeys: TListView;
    BtnHotkeyClear: TButton;
    BtnHotkeyAssign: TButton;
    BtnHotkeyResetAll: TButton;
    PnlButtons: TPanel;
    BtnDefaults: TButton;
    BtnApply: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    ColorDlg: TColorDialog;
    FontDlg: TFontDialog;
    TshSampling: TTabSheet;
    EdtSkipEdges: TEdit;
    LblSkipEdges: TLabel;
    UdSkipEdges: TUpDown;
    LblSkipEdgesUnit: TLabel;
    ChkRandomExtraction: TCheckBox;
    LblRandomPercent: TLabel;
    TrkRandomPercent: TTrackBar;
    ChkCacheRandomFrames: TCheckBox;
    LblRandomPercentValue: TLabel;
    {Unified click handler for every colour-swatch panel and its
     companion "..." open-dialog button. Sender identifies the surface:
     a TPanel acts on itself, a TButton looks up its sibling panel via
     the BtnXxx/PnlXxx naming convention (see DeriveColorPanelNameForButton).
     Wired to ten DFM entries (5 panels + 5 buttons).}
    procedure OnColorSwatchClick(Sender: TObject);
    procedure ChkClipboardAsFileReferenceClick(Sender: TObject);
    procedure ChkShowListerMenuClick(Sender: TObject);
    procedure ChkShowBannerClick(Sender: TObject);
    procedure ChkBannerAutoSizeClick(Sender: TObject);
    procedure BtnTimestampFontClick(Sender: TObject);
    procedure BtnBannerFontClick(Sender: TObject);
    procedure BtnStatusBarFontClick(Sender: TObject);
    procedure ChkStatusBarStretchPanelsClick(Sender: TObject);
    procedure CbxSaveFormatChange(Sender: TObject);
    procedure BtnSaveFolderClick(Sender: TObject);
    procedure ChkMaxWorkersAutoClick(Sender: TObject);
    procedure ChkCacheEnabledClick(Sender: TObject);
    procedure BtnCacheFolderClick(Sender: TObject);
    procedure BtnFFmpegPathClick(Sender: TObject);
    procedure EdtFFmpegPathChange(Sender: TObject);
    procedure EdtMaxThreadsChange(Sender: TObject);
    procedure ChkScaledExtractionClick(Sender: TObject);
    procedure TrkRandomPercentChange(Sender: TObject);
    procedure EdtCacheFolderChange(Sender: TObject);
    procedure BtnClearCacheClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
    procedure ChkThumbnailsEnabledClick(Sender: TObject);
    procedure CbxThumbnailModeChange(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure LvwHotkeysDblClick(Sender: TObject);
    procedure BtnHotkeyClearClick(Sender: TObject);
    procedure BtnHotkeyAssignClick(Sender: TObject);
    procedure BtnHotkeyResetAllClick(Sender: TObject);
  private
    FOwnerWnd: HWND;
    FResolvedFFmpegPath: string;
    FSettings: TPluginSettings;
    FOnApply: TProc;
    {Per-cluster presenters (step 84). Each owns its bundle(s),
     its event handlers, its update helpers, and (for Appearance)
     its dialog-local font shadow fields. The form delegates DFM-
     wired handlers to them and collapses SettingsToControls /
     ControlsToSettings into a sequence of LoadFrom / SaveTo calls.
     Constructed in CreateWithOwner after InitControlsBundles,
     freed in Destroy.}
    FExtractionPresenter: TExtractionPresenter;
    FStoragePresenter: TStoragePresenter;
    FAppearancePresenter: TAppearancePresenter;
    FHotkeyPresenter: THotkeyUIPresenter;
    {Local snapshot of the bindings so the live table isn't mutated unless
     the user confirms with OK/Apply. Owned by the form; the hotkey
     presenter borrows it.}
    FHotkeys: Hotkeys.THotkeyBindings;
    {Declarative table of (predicate, controls) tuples that replaces the
     former cluster of seven UpdateXxxControls methods. Built once during
     construction and recomputed by RecomputeEnables on every relevant
     user-driven change. Closures capture the form's control fields by
     reference; the table lives for the form's lifetime so there are no
     dangling-reference concerns.}
    FEnableRules: TEnableRules;
    {Per-group control bundles. Populated once after the DFM has
     instantiated every control referenced (see InitControlsBundles
     called from CreateWithOwner). Each bundle is consumed by the
     paired BindXxx free procedures in SettingsControlsBundles —
     SettingsToControls / ControlsToSettings dispatch through them.}
    FExtractionControls: TExtractionControls;
    FSaveControls: TSaveControls;
    FCacheControls: TCacheControls;
    FFFmpegControls: TFFmpegControls;
    FViewControls: TViewControls;
    FTimestampControls: TTimestampControls;
    FBannerControls: TBannerControls;
    FClipboardFormatsControls: TClipboardFormatsControls;
    FStatusBarControls: TStatusBarControls;
    FQuickViewControls: TQuickViewControls;
    FThumbnailsControls: TThumbnailsControls;
    procedure InitControlsBundles;
    procedure SettingsToControls(ASettings: TPluginSettings);
    procedure ControlsToSettings(ASettings: TPluginSettings);
    {Populates FEnableRules. Called once after the DFM-defined controls
     exist (so the closures can safely reference them). Note: the
     ClipboardAsFileReference rule subsumes the old UpdateClipboardFormat
     ControlsEnabled — file-reference path bypasses the strategy
     orchestrator entirely, so the per-format toggles have no effect
     while the override is on; greying them out makes the override
     visible without reading the hint text.}
    procedure BuildEnableRules;
    {Single entry point for all "refresh enable state" call sites. Evaluates
     every rule unconditionally (one VCL property read per predicate) and
     then performs the only non-enable side effect: refreshing the
     MaxThreadsAuto caption to track UdMaxThreads.Position.}
    procedure RecomputeEnables;
    procedure PickColor(APanel: TPanel);
    procedure PopulateStatusBarLegend;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor CreateWithOwner(AOwnerWnd: HWND);
    destructor Destroy; override;
  end;

  {Shows the settings dialog.
   AResolvedFFmpegPath is the currently active ffmpeg path (may differ from settings
   when auto-detected). Shown as informational text when the explicit path is empty.
   AOnApply is invoked whenever the user presses the Apply button, after the dialog
   has pushed current control values into ASettings. Pass nil to disable live-apply.
   Returns True if the user pressed OK (ASettings is updated on top of any prior Apply).
   Returns False if dismissed. NOTE: an earlier Apply is not rolled back on Cancel.}
function ShowSettingsDialog(AParentWnd: HWND; ASettings: TPluginSettings; const AResolvedFFmpegPath: string; AOnApply: TProc = nil): Boolean;

implementation

{$R *.dfm}

uses
  System.IOUtils, System.Math,
  Defaults, FFmpegExe, FFmpegCmdLine, CacheMaintenance, BitmapSaver, PathExpand,
  SettingsDlgLogic, SettingsDlgUI, StatusBarTokens;

procedure TSettingsForm.InitControlsBundles;
begin
  {Populates the per-group control bundles with their DFM components.
   Called once from CreateWithOwner after `inherited Create(nil)` has
   loaded the DFM. The bundles are consumed by the BindXxx free
   procedures in SettingsControlsBundles. Adding a control to a group
   means three edits: DFM, bundle record (in SettingsControlsBundles),
   and this method. The dialog's SettingsToControls / ControlsToSettings
   methods stay unchanged.}
  FExtractionControls.UdSkipEdges := UdSkipEdges;
  FExtractionControls.ChkMaxWorkersAuto := ChkMaxWorkersAuto;
  FExtractionControls.UdMaxWorkers := UdMaxWorkers;
  FExtractionControls.UdMaxThreads := UdMaxThreads;
  FExtractionControls.ChkUseBmpPipe := ChkUseBmpPipe;
  FExtractionControls.ChkHwAccel := ChkHwAccel;
  FExtractionControls.ChkUseKeyframes := ChkUseKeyframes;
  FExtractionControls.ChkRespectAnamorphic := ChkRespectAnamorphic;

  FSaveControls.CbxSaveFormat := CbxSaveFormat;
  FSaveControls.UdJpegQuality := UdJpegQuality;
  FSaveControls.UdPngCompression := UdPngCompression;
  FSaveControls.UdBackgroundAlpha := UdBackgroundAlpha;
  FSaveControls.EdtSaveFolder := EdtSaveFolder;
  FSaveControls.ChkSaveAtLiveResolution := ChkSaveAtLiveResolution;
  FSaveControls.ChkCopyAtLiveResolution := ChkCopyAtLiveResolution;
  FSaveControls.ChkClipboardAsFileReference := ChkClipboardAsFileReference;
  FSaveControls.UdCombinedMaxSide := UdCombinedMaxSide;
  FSaveControls.ChkScaledExtraction := ChkScaledExtraction;
  FSaveControls.UdMinFrameSide := UdMinFrameSide;
  FSaveControls.UdMaxFrameSide := UdMaxFrameSide;
  FSaveControls.ChkAutoRefreshViewport := ChkAutoRefreshViewport;
  FSaveControls.EdtExtensions := EdtExtensions;

  FCacheControls.ChkCacheEnabled := ChkCacheEnabled;
  FCacheControls.EdtCacheFolder := EdtCacheFolder;
  FCacheControls.UdCacheMaxSize := UdCacheMaxSize;
  FCacheControls.ChkRandomExtraction := ChkRandomExtraction;
  FCacheControls.TrkRandomPercent := TrkRandomPercent;
  FCacheControls.ChkCacheRandomFrames := ChkCacheRandomFrames;

  FFFmpegControls.EdtFFmpegPath := EdtFFmpegPath;

  FViewControls.PnlBackground := PnlBackground;
  FViewControls.ChkShowToolbar := ChkShowToolbar;
  FViewControls.ChkShowStatusBar := ChkShowStatusBar;
  FViewControls.UdCellGap := UdCellGap;
  FViewControls.UdBorder := UdBorder;
  FViewControls.CbxProgressBarLayout := CbxProgressBarLayout;
  FViewControls.ChkShowListerMenu := ChkShowListerMenu;
  FViewControls.ChkListerMenuFlat := ChkListerMenuFlat;

  FTimestampControls.ChkShowTimecode := ChkShowTimecode;
  FTimestampControls.CbxTimestampCorner := CbxTimestampCorner;
  FTimestampControls.PnlTCBack := PnlTCBack;
  FTimestampControls.UdTCAlpha := UdTCAlpha;
  FTimestampControls.PnlTCTextColor := PnlTCTextColor;
  FTimestampControls.UdTCTextAlpha := UdTCTextAlpha;

  FBannerControls.ChkShowBanner := ChkShowBanner;
  FBannerControls.PnlBannerBackground := PnlBannerBackground;
  FBannerControls.PnlBannerTextColor := PnlBannerTextColor;
  FBannerControls.ChkBannerAutoSize := ChkBannerAutoSize;
  FBannerControls.CbxBannerPosition := CbxBannerPosition;

  FClipboardFormatsControls.ChkPublishAlphaAwareBitmap := ChkPublishAlphaAwareBitmap;
  FClipboardFormatsControls.ChkPublishCompressedPng := ChkPublishCompressedPng;
  FClipboardFormatsControls.ChkPublishFlattenedBitmap := ChkPublishFlattenedBitmap;
  FClipboardFormatsControls.ChkPublishBitmapHandle := ChkPublishBitmapHandle;

  FStatusBarControls.EdtStatusBarTemplate := EdtStatusBarTemplate;
  FStatusBarControls.ChkStatusBarAutoWidthLive := ChkStatusBarAutoWidthLive;
  FStatusBarControls.ChkStatusBarStretchPanels := ChkStatusBarStretchPanels;
  FStatusBarControls.UdStatusBarHeight := UdStatusBarHeight;
  FStatusBarControls.CbxStatusBarHeightApply := CbxStatusBarHeightApply;

  FQuickViewControls.ChkQVDisableNavigation := ChkQVDisableNavigation;
  FQuickViewControls.ChkQVHideToolbar := ChkQVHideToolbar;
  FQuickViewControls.ChkQVHideStatusBar := ChkQVHideStatusBar;

  FThumbnailsControls.ChkThumbnailsEnabled := ChkThumbnailsEnabled;
  FThumbnailsControls.CbxThumbnailMode := CbxThumbnailMode;
  FThumbnailsControls.UdThumbnailPosition := UdThumbnailPosition;
  FThumbnailsControls.UdThumbnailGridFrames := UdThumbnailGridFrames;
end;

procedure TSettingsForm.SettingsToControls(ASettings: TPluginSettings);
begin
  {Delegates per-cluster bundle binds + font shadow fields + update
   helpers to the three presenters. Each presenter's LoadFrom is
   self-contained for its tab cluster. The early RecomputeEnables sits
   between Extraction (workers/scaled rules) and Appearance (banner
   rule) so the workers/scaled groups visually reflect just-loaded
   values before later tabs paint. The final RecomputeEnables picks
   up the rest.}
  FExtractionPresenter.LoadFrom(ASettings);
  RecomputeEnables;
  FAppearancePresenter.LoadFrom(ASettings);
  FStoragePresenter.LoadFrom(ASettings);

  {Clipboard-formats bundle is the only one not owned by a presenter
   (5 checkboxes; no event-handler-bearing logic justifies its own
   class).}
  BindClipboardFormatsToControls(ASettings, FClipboardFormatsControls);

  {Snapshot the bindings into our local copy so edits here only commit on
   OK/Apply via ControlsToSettings.}
  FHotkeys.Assign(ASettings.Hotkeys);
  FHotkeyPresenter.Populate;

  RecomputeEnables;
end;

procedure TSettingsForm.ControlsToSettings(ASettings: TPluginSettings);
begin
  {Per-cluster SaveTo (symmetric with SettingsToControls). The
   Extraction presenter owns the cache-bundle save (shared bundle —
   Storage's SaveTo deliberately skips re-binding it).}
  FExtractionPresenter.SaveTo(ASettings);
  FAppearancePresenter.SaveTo(ASettings);
  FStoragePresenter.SaveTo(ASettings);

  BindClipboardFormatsFromControls(ASettings, FClipboardFormatsControls);

  {Hotkeys were edited into our local snapshot; push the whole table back.}
  ASettings.Hotkeys.Assign(FHotkeys);

  {Cross-field invariants (Min/Max frame side swap) — the dialog's
   spin controls cannot prevent the user from typing Min > Max, so a
   final normalisation is the safety net. Save calls Validate too;
   this one keeps the in-memory state consistent for callers (like the
   in-flight preview) that read settings before Save runs.}
  ASettings.Validate;
end;

procedure TSettingsForm.PickColor(APanel: TPanel);
begin
  PickColorForPanel(APanel, ColorDlg);
end;

procedure TSettingsForm.BtnTimestampFontClick(Sender: TObject);
begin
  FAppearancePresenter.OnTimestampFontClick;
end;

procedure TSettingsForm.BtnBannerFontClick(Sender: TObject);
begin
  FAppearancePresenter.OnBannerFontClick;
end;

procedure TSettingsForm.BtnStatusBarFontClick(Sender: TObject);
begin
  FAppearancePresenter.OnStatusBarFontClick;
end;

procedure TSettingsForm.ChkStatusBarStretchPanelsClick(Sender: TObject);
begin
  FAppearancePresenter.UpdateStretchLockState;
end;

procedure TSettingsForm.PopulateStatusBarLegend;
var
  K: TStatusBarTokenKind;
  Lines: TStringList;
begin
  {One line per token: "%name% — description". Fed verbatim into the
   read-only memo on the Appearance tab. Built from the canonical
   catalogue so adding a new token automatically shows up here on the
   next dialog open — no risk of legend drift against tkUnknown.}
  Lines := TStringList.Create;
  try
    for K in AllStatusBarTokenKinds do
      Lines.Add(Format('%%%s%% - %s',
        [StatusBarTokenName(K), StatusBarTokenHint(K)]));
    Lines.Add('');
    Lines.Add('Attributes: width=auto|N (default auto), align=left|right|center, ' +
      'cap=true|false (save_dimension and copy_dimension only).');
    Lines.Add('All-uppercase token name (e.g. %VIEW_MODE%) uppercases its rendered text.');
    MemStatusBarLegend.Lines.Assign(Lines);
  finally
    Lines.Free;
  end;
end;

procedure TSettingsForm.ChkBannerAutoSizeClick(Sender: TObject);
begin
  FAppearancePresenter.UpdateBannerFontDisplay;
end;

procedure TSettingsForm.OnColorSwatchClick(Sender: TObject);
var
  PanelName: string;
  Comp: TComponent;
begin
  if Sender is TPanel then
    PickColor(TPanel(Sender))
  else if Sender is TButton then
  begin
    PanelName := DeriveColorPanelNameForButton(TButton(Sender).Name);
    if PanelName = '' then
      Exit;
    Comp := FindComponent(PanelName);
    if Comp is TPanel then
      PickColor(TPanel(Comp));
  end;
end;

procedure TSettingsForm.ChkShowBannerClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.ChkClipboardAsFileReferenceClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.ChkShowListerMenuClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.BtnSaveFolderClick(Sender: TObject);
begin
  FAppearancePresenter.OnSaveFolderClick;
end;

procedure TSettingsForm.BtnCacheFolderClick(Sender: TObject);
begin
  FStoragePresenter.OnCacheFolderClick;
end;

procedure TSettingsForm.BtnFFmpegPathClick(Sender: TObject);
begin
  FExtractionPresenter.OnFFmpegPathClick;
end;

procedure TSettingsForm.EdtFFmpegPathChange(Sender: TObject);
begin
  FExtractionPresenter.OnFFmpegPathChange;
end;

procedure TSettingsForm.EdtMaxThreadsChange(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.EdtCacheFolderChange(Sender: TObject);
begin
  FStoragePresenter.OnCacheFolderChange;
end;

procedure TSettingsForm.BtnClearCacheClick(Sender: TObject);
begin
  FStoragePresenter.OnClearCacheClick;
end;

procedure TSettingsForm.BtnDefaultsClick(Sender: TObject);
var
  Defaults: TPluginSettings;
begin
  Defaults := TPluginSettings.CreateDefaults;
  try
    SettingsToControls(Defaults);
  finally
    Defaults.Free;
  end;
end;

procedure TSettingsForm.CbxSaveFormatChange(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.ChkMaxWorkersAutoClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.ChkScaledExtractionClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.TrkRandomPercentChange(Sender: TObject);
begin
  FExtractionPresenter.OnRandomPercentChange;
end;

procedure TSettingsForm.ChkCacheEnabledClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.ChkThumbnailsEnabledClick(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.CbxThumbnailModeChange(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.BtnApplyClick(Sender: TObject);
begin
  {Apply commits current control values to the live settings immediately,
   allowing the host view to act as a preview. The dialog stays open so
   the user can continue adjusting. Cancel afterwards cannot roll back.}
  if FSettings = nil then
    Exit;
  ControlsToSettings(FSettings);
  if Assigned(FOnApply) then
    FOnApply();
end;

{Hotkeys tab — DFM event handlers forward to FHotkeyPresenter so the
 form keeps its DFM-bound method names while THotkeyUIPresenter owns
 the actual UI logic.}

procedure TSettingsForm.LvwHotkeysDblClick(Sender: TObject);
begin
  FHotkeyPresenter.HandleListDblClick(Sender);
end;

procedure TSettingsForm.BtnHotkeyAssignClick(Sender: TObject);
begin
  FHotkeyPresenter.HandleAssignClick(Sender);
end;

procedure TSettingsForm.BtnHotkeyClearClick(Sender: TObject);
begin
  FHotkeyPresenter.HandleClearClick(Sender);
end;

procedure TSettingsForm.BtnHotkeyResetAllClick(Sender: TObject);
begin
  FHotkeyPresenter.HandleResetAllClick(Sender);
end;

procedure TSettingsForm.BuildEnableRules;
begin
  SetLength(FEnableRules, 12);

  {Max workers / max threads — auto mode swaps which of the two
   workers/threads pairs is editable. Limit workers count is only
   relevant in one-per-frame mode; in single-worker mode the per-frame
   thread cap is what the user can tune.}
  FEnableRules[0].Predicate := function: Boolean begin Result := not ChkMaxWorkersAuto.Checked end;
  FEnableRules[0].Controls := [LblMaxWorkers, EdtMaxWorkers, UdMaxWorkers];

  FEnableRules[1].Predicate := function: Boolean begin Result := ChkMaxWorkersAuto.Checked end;
  FEnableRules[1].Controls := [LblMaxThreads, EdtMaxThreads, UdMaxThreads];

  {Save format — JPEG quality vs PNG compression/alpha are mutually
   exclusive; the toggle is the format combo's item index.}
  FEnableRules[2].Predicate := function: Boolean begin Result := CbxSaveFormat.ItemIndex <> Ord(sfPNG) end;
  FEnableRules[2].Controls := [LblJpegQuality, EdtJpegQuality, UdJpegQuality];

  FEnableRules[3].Predicate := function: Boolean begin Result := CbxSaveFormat.ItemIndex = Ord(sfPNG) end;
  FEnableRules[3].Controls := [LblPngCompression, EdtPngCompression, UdPngCompression,
                               LblBackgroundAlpha, EdtBackgroundAlpha, UdBackgroundAlpha];

  {Banner style is only meaningful when the banner is actually drawn.}
  FEnableRules[4].Predicate := function: Boolean begin Result := ChkShowBanner.Checked end;
  FEnableRules[4].Controls := [LblBannerBackground, PnlBannerBackground, BtnBannerBackground,
                               LblBannerTextColor, PnlBannerTextColor, BtnBannerTextColor,
                               LblBannerFont, EdtBannerFont, BtnBannerFont,
                               ChkBannerAutoSize, LblBannerPosition, CbxBannerPosition];

  {File-reference path bypasses the strategy orchestrator entirely, so
   the four per-format toggles have no effect while the override is on.
   Grey them out (and the group header label) so the override is
   visible to the user without reading the hint text.}
  FEnableRules[5].Predicate := function: Boolean begin Result := not ChkClipboardAsFileReference.Checked end;
  FEnableRules[5].Controls := [LblClipboardFormatsHeader, ChkPublishAlphaAwareBitmap,
                               ChkPublishCompressedPng, ChkPublishFlattenedBitmap, ChkPublishBitmapHandle];

  {Cache folder + size cap are dead controls while the cache is off.}
  FEnableRules[6].Predicate := function: Boolean begin Result := ChkCacheEnabled.Checked end;
  FEnableRules[6].Controls := [LblCacheFolder, EdtCacheFolder, BtnCacheFolder,
                               LblCacheMaxSize, EdtCacheMaxSize, UdCacheMaxSize, LblCacheMaxSizeUnit];

  {Scaled extraction — Min/Max frame side bounds plus the auto-refresh
   toggle, which has no effect when scaling is off (no MaxSide to
   compare against).}
  FEnableRules[7].Predicate := function: Boolean begin Result := ChkScaledExtraction.Checked end;
  FEnableRules[7].Controls := [LblScaleTarget, EdtMinFrameSide, UdMinFrameSide,
                               LblScaleSep, EdtMaxFrameSide, UdMaxFrameSide, LblScaleUnit,
                               ChkAutoRefreshViewport];

  {Thumbnails — three rules: the master toggle gates the mode combo,
   then within an enabled group Single mode shows position controls and
   Grid mode shows grid-frame count. Disabling avoids the user editing
   fields that won't be used.}
  FEnableRules[8].Predicate := function: Boolean begin Result := ChkThumbnailsEnabled.Checked end;
  FEnableRules[8].Controls := [LblThumbnailMode, CbxThumbnailMode];

  FEnableRules[9].Predicate := function: Boolean
    begin
      Result := ChkThumbnailsEnabled.Checked
                and (CbxThumbnailMode.ItemIndex = Ord(tnmSingle));
    end;
  FEnableRules[9].Controls := [LblThumbnailPosition, EdtThumbnailPosition,
                               UdThumbnailPosition, LblThumbnailPositionUnit];

  FEnableRules[10].Predicate := function: Boolean
    begin
      Result := ChkThumbnailsEnabled.Checked
                and (CbxThumbnailMode.ItemIndex = Ord(tnmGrid));
    end;
  FEnableRules[10].Controls := [LblThumbnailGridFrames, EdtThumbnailGridFrames, UdThumbnailGridFrames];

  {Flat-layout choice is meaningless when the lister menu is disabled.}
  FEnableRules[11].Predicate := function: Boolean begin Result := ChkShowListerMenu.Checked end;
  FEnableRules[11].Controls := [ChkListerMenuFlat];
end;

procedure TSettingsForm.RecomputeEnables;
begin
  ApplyEnableRules(FEnableRules);
  {Caption update is the one non-enable mutation the former UpdateMax
   WorkersControls method performed; keep it adjacent to its rule's
   evaluation so the two stay coupled.}
  LblMaxThreadsAuto.Caption := MaxThreadsAutoLabel(
    ChkMaxWorkersAuto.Checked, UdMaxThreads.Position, CPUCount);
end;

constructor TSettingsForm.CreateWithOwner(AOwnerWnd: HWND);
begin
  {Must be set before inherited: DFM loading may force handle creation,
   and CreateParams needs the value at that point}
  FOwnerWnd := AOwnerWnd;
  inherited Create(nil);
  FHotkeys := Hotkeys.THotkeyBindings.Create;
  {Both InitControlsBundles and BuildEnableRules need the DFM-defined
   controls to exist (the bundles capture VCL references; the rule
   closures read VCL state). Init order is bundles first because the
   rules don't depend on them but a future migration of rule predicates
   to bundles would. Both live for the form's lifetime.}
  InitControlsBundles;
  BuildEnableRules;
  {Presenters built after the bundles + rule table. Each owns its
   slice of behaviour (handlers + helpers); the form delegates DFM
   handlers to them via thin forwarders. FResolvedFFmpegPath is set
   by ShowSettingsDialog right after CreateWithOwner returns; the
   Extraction presenter reads it at UpdateFFmpegInfo time, so the
   value handed in here doesn't need to be final.}
  FExtractionPresenter := TExtractionPresenter.Create(
    FExtractionControls, FFFmpegControls, FCacheControls,
    LblFFmpegInfo, EdtFFmpegInfo, LblRandomPercentValue,
    FResolvedFFmpegPath, FOwnerWnd);
  FStoragePresenter := TStoragePresenter.Create(
    FCacheControls, FThumbnailsControls, FQuickViewControls,
    LblCacheFolderInfo, EdtCacheFolderInfo, LblCacheSizeInfo,
    Self, FOwnerWnd);
  FAppearancePresenter := TAppearancePresenter.Create(
    FViewControls, FTimestampControls, FStatusBarControls,
    FBannerControls, FSaveControls,
    EdtTimestampFont, EdtBannerFont, EdtStatusBarFont,
    ChkBannerAutoSize, FontDlg, CbxProgressBarLayout,
    Self, FOwnerWnd);
  FHotkeyPresenter := THotkeyUIPresenter.Create(Self, LvwHotkeys, FHotkeys);
  {Keep tooltips visible as long as the cursor stays over the control.
   Application is per-DLL, so this only affects hints shown by our forms;
   TC's own UI uses its own (non-VCL) tooltip mechanism.}
  Application.HintHidePause := MaxInt;
  PopulateStatusBarLegend;
end;

destructor TSettingsForm.Destroy;
begin
  FHotkeyPresenter.Free;
  FAppearancePresenter.Free;
  FStoragePresenter.Free;
  FExtractionPresenter.Free;
  FHotkeys.Free;
  inherited;
end;

procedure TSettingsForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if FOwnerWnd <> 0 then
    Params.WndParent := FOwnerWnd;
end;

function ShowSettingsDialog(AParentWnd: HWND; ASettings: TPluginSettings; const AResolvedFFmpegPath: string; AOnApply: TProc): Boolean;
var
  Form: TSettingsForm;
begin
  Result := False;
  Form := TSettingsForm.CreateWithOwner(AParentWnd);
  try
    Form.FResolvedFFmpegPath := AResolvedFFmpegPath;
    Form.FExtractionPresenter.SetResolvedFFmpegPath(AResolvedFFmpegPath);
    Form.FSettings := ASettings;
    Form.FOnApply := AOnApply;
    Form.SettingsToControls(ASettings);
    if Form.ShowModal = mrOK then
    begin
      Form.ControlsToSettings(ASettings);
      Result := True;
    end;
  finally
    Form.Free;
  end;
end;

end.
