{Settings dialog for configuring plugin behavior.
 Works on TPluginSettings directly; changes take effect only when OK is pressed.}
unit uSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  Winapi.Windows,
  uTypes, uStatusBarLayout, uSettings, uHotkeys, uEnableRules,
  uSettingsControlsBundles;

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
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBannerFontName: string;
    FBannerFontSize: Integer;
    FStatusBarFontName: string;
    FStatusBarFontSize: Integer;
    {Local snapshot of the bindings so the live table isn't mutated unless
     the user confirms with OK/Apply. Mirrors the per-row listview rows.}
    FHotkeys: uHotkeys.THotkeyBindings;
    {Parallel to LvwHotkeys.Items, indexed by Item.Index. Replaces the
     earlier Item.Data := Pointer(NativeInt(Ord(A))) type-pun. The
     listview is not sorted (SortType=stNone in the DFM), so insertion
     order matches Item.Index; if sort is ever enabled this needs to
     become a TDictionary<TListItem, TPluginAction>.}
    FHotkeyRowActions: TArray<uHotkeys.TPluginAction>;
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
     paired BindXxx free procedures in uSettingsControlsBundles —
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
    procedure UpdateFFmpegInfo;
    procedure UpdateCacheFolderInfo;
    procedure UpdateCacheSizeInfo;
    procedure PickColor(APanel: TPanel);
    procedure PickTimestampFont;
    procedure PickBannerFont;
    procedure PickStatusBarFont;
    procedure UpdateTimestampFontDisplay;
    procedure UpdateBannerFontDisplay;
    procedure UpdateStatusBarFontDisplay;
    procedure PopulateStatusBarLegend;
    {Enforces the rule that stretch panels mode implies progress-bar
     Over panels: when the stretch checkbox is on, the progress bar
     combo is forced to "Over panels" and disabled (the runtime will
     override anyway, surface the override in the UI so the user
     understands what they will get). When stretch is off, the combo
     re-enables with whatever value it currently holds.}
    procedure UpdateStretchLockState;
    procedure PopulateHotkeyList;
    procedure RefreshHotkeyRow(AAction: uHotkeys.TPluginAction);
    function SelectedHotkeyAction: uHotkeys.TPluginAction;
    procedure CaptureAndAssignHotkey(AAction: uHotkeys.TPluginAction);
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
  uDefaults, uFFmpegExe, uFFmpegCmdLine, uCacheMaintenance, uBitmapSaver, uPathExpand,
  uSettingsDlgLogic, uSettingsDlgUI, uPluginMessages, uCaptureShortcutDlg,
  uStatusBarTokens, uHotkeysDisplay;

procedure TSettingsForm.InitControlsBundles;
begin
  {Populates the per-group control bundles with their DFM components.
   Called once from CreateWithOwner after `inherited Create(nil)` has
   loaded the DFM. The bundles are consumed by the BindXxx free
   procedures in uSettingsControlsBundles. Adding a control to a group
   means three edits: DFM, bundle record (in uSettingsControlsBundles),
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
  {Per-group bundle binds. Order matches the visual tab order
   (General -> Sampling -> Appearance -> Save -> Clipboard -> Cache ->
   QuickView -> Thumbnails). Extraction first because the early
   RecomputeEnables right after lets the workers/scaled enable rules
   see the just-loaded values before later tabs paint.}
  BindExtractionToControls(ASettings, FExtractionControls);
  BindFFmpegToControls(ASettings, FFFmpegControls);
  BindSaveToControls(ASettings, FSaveControls);
  BindCacheToControls(ASettings, FCacheControls);
  {Random-percent live readout (label, not a control bound by the
   bundle). Pinned right after the Cache bind so the label tracks the
   trackbar value the bundle just wrote.}
  LblRandomPercentValue.Caption := IntToStr(ASettings.RandomPercent) + '%';
  {Early enable-rule sweep so the workers/scaled groups visually reflect
   the just-loaded values before subsequent setters paint the remaining
   tabs. A final RecomputeEnables at the bottom of this method picks up
   the controls whose values are set further down (banner, cache, etc).}
  RecomputeEnables;

  BindViewToControls(ASettings, FViewControls);
  BindTimestampToControls(ASettings, FTimestampControls);
  {Font shadow fields are dialog-local state, not VCL controls; the
   bundle deliberately omits them. The UpdateXxxFontDisplay calls
   refresh the read-only EdtXxxFont label after the shadow fields are
   set.}
  FTimestampFontName := ASettings.TimestampFontName;
  FTimestampFontSize := ASettings.TimestampFontSize;
  UpdateTimestampFontDisplay;

  BindStatusBarToControls(ASettings, FStatusBarControls);
  FStatusBarFontName := ASettings.StatusBarFontName;
  FStatusBarFontSize := ASettings.StatusBarFontSize;
  UpdateStatusBarFontDisplay;
  UpdateStretchLockState;

  BindBannerToControls(ASettings, FBannerControls);
  FBannerFontName := ASettings.BannerFontName;
  FBannerFontSize := ASettings.BannerFontSize;
  UpdateBannerFontDisplay;

  BindClipboardFormatsToControls(ASettings, FClipboardFormatsControls);
  BindQuickViewToControls(ASettings, FQuickViewControls);
  BindThumbnailsToControls(ASettings, FThumbnailsControls);

  {Snapshot the bindings into our local copy so edits here only commit on
   OK/Apply via ControlsToSettings.}
  FHotkeys.Assign(ASettings.Hotkeys);
  PopulateHotkeyList;

  RecomputeEnables;
  UpdateFFmpegInfo;
  UpdateCacheFolderInfo;
  UpdateCacheSizeInfo;
end;

procedure TSettingsForm.ControlsToSettings(ASettings: TPluginSettings);
begin
  {Per-group bundle binds (symmetric with SettingsToControls). Order
   matches the visual tab order; bundles cover all model fields except
   the font shadow fields + hotkey collection (handled inline below).}
  BindExtractionFromControls(ASettings, FExtractionControls);
  BindFFmpegFromControls(ASettings, FFFmpegControls);
  BindSaveFromControls(ASettings, FSaveControls);
  BindCacheFromControls(ASettings, FCacheControls);

  BindViewFromControls(ASettings, FViewControls);
  BindTimestampFromControls(ASettings, FTimestampControls);
  {Font shadow fields are dialog-local state, not VCL controls; the
   bundle deliberately omits them. The shadow values are the source of
   truth at this point (set by PickXxxFont or BindXxxToControls).}
  ASettings.TimestampFontName := FTimestampFontName;
  ASettings.TimestampFontSize := FTimestampFontSize;

  BindStatusBarFromControls(ASettings, FStatusBarControls);
  ASettings.StatusBarFontName := FStatusBarFontName;
  ASettings.StatusBarFontSize := FStatusBarFontSize;

  BindBannerFromControls(ASettings, FBannerControls);
  ASettings.BannerFontName := FBannerFontName;
  ASettings.BannerFontSize := FBannerFontSize;

  BindClipboardFormatsFromControls(ASettings, FClipboardFormatsControls);
  BindQuickViewFromControls(ASettings, FQuickViewControls);
  BindThumbnailsFromControls(ASettings, FThumbnailsControls);

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

procedure TSettingsForm.UpdateTimestampFontDisplay;
begin
  RefreshFontEdit(EdtTimestampFont, FTimestampFontName, FTimestampFontSize);
end;

procedure TSettingsForm.UpdateBannerFontDisplay;
begin
  RefreshBannerFontEdit(EdtBannerFont, ChkBannerAutoSize.Checked, FBannerFontName, FBannerFontSize);
end;

procedure TSettingsForm.PickTimestampFont;
begin
  PickFontInto(FontDlg, EdtTimestampFont, FTimestampFontName, FTimestampFontSize, MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
end;

procedure TSettingsForm.PickBannerFont;
var
  AutoSize: Boolean;
begin
  AutoSize := ChkBannerAutoSize.Checked;
  PickBannerFontInto(FontDlg, EdtBannerFont, AutoSize, FBannerFontName, FBannerFontSize, MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE, DEF_BANNER_FONT_SIZE);
  ChkBannerAutoSize.Checked := AutoSize;
end;

procedure TSettingsForm.BtnTimestampFontClick(Sender: TObject);
begin
  PickTimestampFont;
end;

procedure TSettingsForm.BtnBannerFontClick(Sender: TObject);
begin
  PickBannerFont;
end;

procedure TSettingsForm.UpdateStatusBarFontDisplay;
begin
  RefreshFontEdit(EdtStatusBarFont, FStatusBarFontName, FStatusBarFontSize);
end;

procedure TSettingsForm.PickStatusBarFont;
begin
  PickFontInto(FontDlg, EdtStatusBarFont, FStatusBarFontName, FStatusBarFontSize,
    MIN_STATUSBAR_FONT_SIZE, MAX_STATUSBAR_FONT_SIZE);
end;

procedure TSettingsForm.BtnStatusBarFontClick(Sender: TObject);
begin
  PickStatusBarFont;
end;

procedure TSettingsForm.UpdateStretchLockState;
begin
  if ChkStatusBarStretchPanels.Checked then
  begin
    CbxProgressBarLayout.ItemIndex := Ord(pblOverPanels);
    CbxProgressBarLayout.Enabled := False;
  end
  else
    CbxProgressBarLayout.Enabled := True;
end;

procedure TSettingsForm.ChkStatusBarStretchPanelsClick(Sender: TObject);
begin
  UpdateStretchLockState;
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
  UpdateBannerFontDisplay;
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

procedure TSettingsForm.BtnSaveFolderClick(Sender: TObject);
begin
  BrowseFolderInto(EdtSaveFolder, Self);
end;

procedure TSettingsForm.BtnCacheFolderClick(Sender: TObject);
begin
  BrowseFolderInto(EdtCacheFolder, Self);
end;

procedure TSettingsForm.BtnFFmpegPathClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if EdtFFmpegPath.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(EdtFFmpegPath.Text));
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      if ValidateFFmpeg(Dlg.FileName) = '' then
      begin
        ShowPluginMessage(Handle, 'The selected file is not a valid ffmpeg executable.', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      EdtFFmpegPath.Text := Dlg.FileName;
      {OnChange fires automatically and updates the info label}
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TSettingsForm.EdtFFmpegPathChange(Sender: TObject);
begin
  UpdateFFmpegInfo;
end;

procedure TSettingsForm.EdtMaxThreadsChange(Sender: TObject);
begin
  RecomputeEnables;
end;

procedure TSettingsForm.EdtCacheFolderChange(Sender: TObject);
begin
  UpdateCacheFolderInfo;
end;

procedure TSettingsForm.BtnClearCacheClick(Sender: TObject);
begin
  if ShowPluginMessage(Handle, 'Delete all cached frames and probe metadata?', MB_OKCANCEL or MB_ICONQUESTION) <> IDOK then
    Exit;
  ClearAllGlimpseCaches(EffectiveCacheFolder(EdtCacheFolder.Text));
  UpdateCacheSizeInfo;
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
  LblRandomPercentValue.Caption := IntToStr(TrkRandomPercent.Position) + '%';
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

{Hotkeys tab}

procedure TSettingsForm.PopulateHotkeyList;
var
  A: uHotkeys.TPluginAction;
  Item: TListItem;
begin
  SetLength(FHotkeyRowActions, 0);
  LvwHotkeys.Items.BeginUpdate;
  try
    LvwHotkeys.Items.Clear;
    for A := Succ(uHotkeys.paNone) to High(uHotkeys.TPluginAction) do
    begin
      Item := LvwHotkeys.Items.Add;
      Item.Caption := uHotkeys.ActionCaption(A);
      SetLength(FHotkeyRowActions, Length(FHotkeyRowActions) + 1);
      FHotkeyRowActions[High(FHotkeyRowActions)] := A;
      Item.SubItems.Add(ChordsToDisplayStr(FHotkeys.Get(A)));
    end;
  finally
    LvwHotkeys.Items.EndUpdate;
  end;
end;

procedure TSettingsForm.RefreshHotkeyRow(AAction: uHotkeys.TPluginAction);
var
  I: Integer;
  Item: TListItem;
  Display: string;
begin
  Display := ChordsToDisplayStr(FHotkeys.Get(AAction));
  for I := 0 to LvwHotkeys.Items.Count - 1 do
  begin
    if (I < Length(FHotkeyRowActions)) and (FHotkeyRowActions[I] = AAction) then
    begin
      Item := LvwHotkeys.Items[I];
      if Item.SubItems.Count = 0 then
        Item.SubItems.Add(Display)
      else
        Item.SubItems[0] := Display;
      Exit;
    end;
  end;
end;

function TSettingsForm.SelectedHotkeyAction: uHotkeys.TPluginAction;
var
  Item: TListItem;
begin
  Item := LvwHotkeys.Selected;
  if Item = nil then
    Exit(uHotkeys.paNone);
  if (Item.Index < 0) or (Item.Index >= Length(FHotkeyRowActions)) then
    Exit(uHotkeys.paNone);
  Result := FHotkeyRowActions[Item.Index];
end;

procedure TSettingsForm.CaptureAndAssignHotkey(AAction: uHotkeys.TPluginAction);
var
  NewChords: uHotkeys.THotkeyChordArray;
  EvictedActions: TArray<uHotkeys.TPluginAction>;
  Evicted: uHotkeys.TPluginAction;
begin
  if AAction = uHotkeys.paNone then
    Exit;
  if not EditShortcuts(Self, AAction, FHotkeys, NewChords) then
    Exit;

  {ReassignExclusive removes NewChords from any other action that owned
   them (the editor already prompted the user and they said "Yes,
   reassign") and Puts NewChords on AAction. Returns the list of actions
   whose rows need a UI refresh.}
  EvictedActions := FHotkeys.ReassignExclusive(AAction, NewChords);
  for Evicted in EvictedActions do
    RefreshHotkeyRow(Evicted);
  RefreshHotkeyRow(AAction);
end;

procedure TSettingsForm.LvwHotkeysDblClick(Sender: TObject);
begin
  CaptureAndAssignHotkey(SelectedHotkeyAction);
end;

procedure TSettingsForm.BtnHotkeyAssignClick(Sender: TObject);
begin
  CaptureAndAssignHotkey(SelectedHotkeyAction);
end;

procedure TSettingsForm.BtnHotkeyClearClick(Sender: TObject);
var
  A: uHotkeys.TPluginAction;
begin
  A := SelectedHotkeyAction;
  if A = uHotkeys.paNone then
    Exit;
  FHotkeys.Put(A, nil);
  RefreshHotkeyRow(A);
end;

procedure TSettingsForm.BtnHotkeyResetAllClick(Sender: TObject);
begin
  if ShowPluginMessage(Handle, 'Reset every hotkey to its default? Unsaved changes in this tab will be lost.', MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  FHotkeys.ResetToDefaults;
  PopulateHotkeyList;
end;

procedure TSettingsForm.BuildEnableRules;
begin
  SetLength(FEnableRules, 11);

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

procedure TSettingsForm.UpdateFFmpegInfo;
var
  Input, Path, Ver, Prefix, Value: string;
  State: TFFmpegProbeState;
begin
  Input := EdtFFmpegPath.Text;
  if Input <> '' then
    Path := ExpandEnvVars(Input)
  else
    Path := FResolvedFFmpegPath;

  Ver := '';
  if Path = '' then
    State := fpsNoPath
  else if not FileExists(Path) then
    State := fpsFileMissing
  else
  begin
    Ver := ValidateFFmpeg(Path);
    if Ver = '' then
      State := fpsInvalid
    else
      State := fpsValid;
  end;

  FFmpegInfoLabelParts(State, Path, Ver, Input = '', Prefix, Value);
  ApplyInfoParts(LblFFmpegInfo, EdtFFmpegInfo, Prefix, Value);
end;

procedure TSettingsForm.UpdateCacheFolderInfo;
begin
  if EdtCacheFolder.Text = '' then
    ApplyInfoParts(LblCacheFolderInfo, EdtCacheFolderInfo, 'Default:', DefaultCacheFolder)
  else
    ApplyInfoParts(LblCacheFolderInfo, EdtCacheFolderInfo, '', '');
end;

procedure TSettingsForm.UpdateCacheSizeInfo;
var
  Total: Int64;
begin
  Total := TotalGlimpseCacheBytes(EffectiveCacheFolder(EdtCacheFolder.Text));
  if Total > 0 then
    LblCacheSizeInfo.Caption := Format('(current: %.1f MB)', [Total / (1024 * 1024)])
  else
    LblCacheSizeInfo.Caption := '(current: empty)';
end;

constructor TSettingsForm.CreateWithOwner(AOwnerWnd: HWND);
begin
  {Must be set before inherited: DFM loading may force handle creation,
   and CreateParams needs the value at that point}
  FOwnerWnd := AOwnerWnd;
  inherited Create(nil);
  FHotkeys := uHotkeys.THotkeyBindings.Create;
  {Both InitControlsBundles and BuildEnableRules need the DFM-defined
   controls to exist (the bundles capture VCL references; the rule
   closures read VCL state). Init order is bundles first because the
   rules don't depend on them but a future migration of rule predicates
   to bundles would. Both live for the form's lifetime.}
  InitControlsBundles;
  BuildEnableRules;
  {Keep tooltips visible as long as the cursor stays over the control.
   Application is per-DLL, so this only affects hints shown by our forms;
   TC's own UI uses its own (non-VCL) tooltip mechanism.}
  Application.HintHidePause := MaxInt;
  PopulateStatusBarLegend;
end;

destructor TSettingsForm.Destroy;
begin
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
