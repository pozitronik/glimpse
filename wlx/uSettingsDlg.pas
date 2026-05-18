{Settings dialog for configuring plugin behavior.
 Works on TPluginSettings directly; changes take effect only when OK is pressed.}
unit uSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  Winapi.Windows,
  uTypes, uStatusBarLayout, uSettings, uHotkeys;

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
    procedure SettingsToControls(ASettings: TPluginSettings);
    procedure ControlsToSettings(ASettings: TPluginSettings);
    procedure UpdateMaxWorkersControls;
    procedure UpdateSaveFormatControls;
    procedure UpdateBannerControls;
    {Greys out the four per-format publish checkboxes (and their group
     header label) when ChkClipboardAsFileReference is checked, since
     the file-reference path overrides the format toggles. Wired both
     to the override toggle's OnClick and called from SettingsToControls
     after loading so the initial state matches the persisted value.}
    procedure UpdateClipboardFormatControlsEnabled;
    procedure UpdateCacheControls;
    procedure UpdateScaledExtractionControls;
    procedure UpdateThumbnailControls;
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
  uDefaults, uFFmpegExe, uFFmpegCmdLine, uCache, uProbeCache, uBitmapSaver, uPathExpand,
  uSettingsDlgLogic, uSettingsDlgUI, uPluginMessages, uCaptureShortcutDlg,
  uStatusBarTokens;

procedure TSettingsForm.SettingsToControls(ASettings: TPluginSettings);
var
  AutoChecked, ShowChecked: Boolean;
  UdPos, ComboIdx: Integer;
begin
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;
  DecodeMaxWorkersControls(ASettings.MaxWorkers, AutoChecked, UdPos);
  ChkMaxWorkersAuto.Checked := AutoChecked;
  UdMaxWorkers.Position := UdPos;
  ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  ChkHwAccel.Checked := ASettings.HwAccel;
  ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  ChkRespectAnamorphic.Checked := ASettings.RespectAnamorphic;
  UdMaxThreads.Position := DecodeMaxThreadsControl(ASettings.MaxThreads);
  ChkScaledExtraction.Checked := ASettings.ScaledExtraction;
  UdMinFrameSide.Position := ASettings.MinFrameSide;
  UdMaxFrameSide.Position := ASettings.MaxFrameSide;
  ChkAutoRefreshViewport.Checked := ASettings.AutoRefreshOnViewportChange;
  ChkRandomExtraction.Checked := ASettings.RandomExtraction;
  TrkRandomPercent.Position := ASettings.RandomPercent;
  LblRandomPercentValue.Caption := IntToStr(ASettings.RandomPercent) + '%';
  ChkCacheRandomFrames.Checked := ASettings.CacheRandomFrames;
  UpdateMaxWorkersControls;
  UpdateScaledExtractionControls;
  EdtExtensions.Text := ASettings.ExtensionList;
  EdtFFmpegPath.Text := ASettings.FFmpegExePath;

  PnlBackground.Color := ASettings.Background;
  PnlTCBack.Color := ASettings.TimecodeBackColor;
  UdTCAlpha.Position := ASettings.TimecodeBackAlpha;
  UdTCTextAlpha.Position := ASettings.TimestampTextAlpha;
  PnlTCTextColor.Color := ASettings.TimestampTextColor;
  FTimestampFontName := ASettings.TimestampFontName;
  FTimestampFontSize := ASettings.TimestampFontSize;
  UpdateTimestampFontDisplay;
  UdCellGap.Position := ASettings.CellGap;
  UdBorder.Position := ASettings.CombinedBorder;
  DecodeTimestampCornerControls(ASettings.ShowTimecode, ASettings.TimestampCorner, ShowChecked, ComboIdx);
  ChkShowTimecode.Checked := ShowChecked;
  CbxTimestampCorner.ItemIndex := ComboIdx;
  ChkShowToolbar.Checked := ASettings.ShowToolbar;
  ChkShowStatusBar.Checked := ASettings.ShowStatusBar;
  CbxProgressBarLayout.ItemIndex := Ord(ASettings.ProgressBarLayout);
  EdtStatusBarTemplate.Text := ASettings.StatusBarTemplate;
  FStatusBarFontName := ASettings.StatusBarFontName;
  FStatusBarFontSize := ASettings.StatusBarFontSize;
  UpdateStatusBarFontDisplay;
  ChkStatusBarAutoWidthLive.Checked := ASettings.StatusBarAutoWidthLive;
  ChkStatusBarStretchPanels.Checked := ASettings.StatusBarStretchPanels;
  UdStatusBarHeight.Position := ASettings.StatusBarHeight;
  CbxStatusBarHeightApply.ItemIndex := Ord(ASettings.StatusBarHeightApplyMode);
  UpdateStretchLockState;

  CbxSaveFormat.ItemIndex := Ord(ASettings.SaveFormat);
  UdJpegQuality.Position := ASettings.JpegQuality;
  UdPngCompression.Position := ASettings.PngCompression;
  UdBackgroundAlpha.Position := ASettings.BackgroundAlpha;
  EdtSaveFolder.Text := ASettings.SaveFolder;
  ChkShowBanner.Checked := ASettings.ShowBanner;
  PnlBannerBackground.Color := ASettings.BannerBackground;
  PnlBannerTextColor.Color := ASettings.BannerTextColor;
  FBannerFontName := ASettings.BannerFontName;
  FBannerFontSize := ASettings.BannerFontSize;
  ChkBannerAutoSize.Checked := ASettings.BannerFontAutoSize;
  UpdateBannerFontDisplay;
  CbxBannerPosition.ItemIndex := Ord(ASettings.BannerPosition);
  ChkSaveAtLiveResolution.Checked := ASettings.SaveAtLiveResolution;
  ChkCopyAtLiveResolution.Checked := ASettings.CopyAtLiveResolution;
  UdCombinedMaxSide.Position := ASettings.CombinedMaxSide;

  {[Clipboard tab] — per-format publish toggles + the file-reference
   override. Order matches the visual layout: alpha-aware first, then
   PNG, then the legacy variants, then the override.}
  ChkPublishAlphaAwareBitmap.Checked := ASettings.PublishAlphaAwareBitmap;
  ChkPublishCompressedPng.Checked := ASettings.PublishCompressedPng;
  ChkPublishFlattenedBitmap.Checked := ASettings.PublishFlattenedBitmap;
  ChkPublishBitmapHandle.Checked := ASettings.PublishBitmapHandle;
  ChkClipboardAsFileReference.Checked := ASettings.ClipboardAsFileReference;

  ChkCacheEnabled.Checked := ASettings.CacheEnabled;
  EdtCacheFolder.Text := ASettings.CacheFolder;
  UdCacheMaxSize.Position := ASettings.CacheMaxSizeMB;

  ChkQVDisableNavigation.Checked := ASettings.QVDisableNavigation;
  ChkQVHideToolbar.Checked := ASettings.QVHideToolbar;
  ChkQVHideStatusBar.Checked := ASettings.QVHideStatusBar;

  ChkThumbnailsEnabled.Checked := ASettings.ThumbnailsEnabled;
  CbxThumbnailMode.ItemIndex := Ord(ASettings.ThumbnailMode);
  UdThumbnailPosition.Position := ASettings.ThumbnailPosition;
  UdThumbnailGridFrames.Position := ASettings.ThumbnailGridFrames;

  {Snapshot the bindings into our local copy so edits here only commit on
   OK/Apply via ControlsToSettings.}
  FHotkeys.Assign(ASettings.Hotkeys);
  PopulateHotkeyList;

  UpdateSaveFormatControls;
  UpdateBannerControls;
  UpdateCacheControls;
  UpdateThumbnailControls;
  UpdateClipboardFormatControlsEnabled;
  UpdateFFmpegInfo;
  UpdateCacheFolderInfo;
  UpdateCacheSizeInfo;
end;

procedure TSettingsForm.ControlsToSettings(ASettings: TPluginSettings);
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;
  ASettings.MaxWorkers := EncodeMaxWorkersControls(ChkMaxWorkersAuto.Checked, UdMaxWorkers.Position);
  ASettings.UseBmpPipe := ChkUseBmpPipe.Checked;
  ASettings.HwAccel := ChkHwAccel.Checked;
  ASettings.UseKeyframes := ChkUseKeyframes.Checked;
  ASettings.RespectAnamorphic := ChkRespectAnamorphic.Checked;
  ASettings.ScaledExtraction := ChkScaledExtraction.Checked;
  ASettings.MinFrameSide := UdMinFrameSide.Position;
  ASettings.MaxFrameSide := UdMaxFrameSide.Position;
  ASettings.AutoRefreshOnViewportChange := ChkAutoRefreshViewport.Checked;
  ASettings.RandomExtraction := ChkRandomExtraction.Checked;
  ASettings.RandomPercent := TrkRandomPercent.Position;
  ASettings.CacheRandomFrames := ChkCacheRandomFrames.Checked;
  ASettings.MaxThreads := UdMaxThreads.Position;
  ASettings.ExtensionList := EdtExtensions.Text;

  ASettings.SetFFmpegPath(EdtFFmpegPath.Text);

  ASettings.Background := PnlBackground.Color;
  ASettings.TimecodeBackColor := PnlTCBack.Color;
  ASettings.TimecodeBackAlpha := UdTCAlpha.Position;
  ASettings.TimestampTextAlpha := UdTCTextAlpha.Position;
  ASettings.TimestampTextColor := PnlTCTextColor.Color;
  ASettings.TimestampFontName := FTimestampFontName;
  ASettings.TimestampFontSize := FTimestampFontSize;
  ASettings.CellGap := UdCellGap.Position;
  ASettings.CombinedBorder := UdBorder.Position;
  EncodeTimestampCornerControls(ChkShowTimecode.Checked, CbxTimestampCorner.ItemIndex, Show, Corner);
  ASettings.ShowTimecode := Show;
  ASettings.TimestampCorner := Corner;
  ASettings.ShowToolbar := ChkShowToolbar.Checked;
  ASettings.ShowStatusBar := ChkShowStatusBar.Checked;
  ASettings.ProgressBarLayout := TProgressBarLayout(CbxProgressBarLayout.ItemIndex);
  ASettings.StatusBarTemplate := EdtStatusBarTemplate.Text;
  ASettings.StatusBarFontName := FStatusBarFontName;
  ASettings.StatusBarFontSize := FStatusBarFontSize;
  ASettings.StatusBarAutoWidthLive := ChkStatusBarAutoWidthLive.Checked;
  ASettings.StatusBarStretchPanels := ChkStatusBarStretchPanels.Checked;
  ASettings.StatusBarHeight := UdStatusBarHeight.Position;
  ASettings.StatusBarHeightApplyMode := TStatusBarHeightApplyMode(CbxStatusBarHeightApply.ItemIndex);

  ASettings.SaveFormat := TSaveFormat(CbxSaveFormat.ItemIndex);
  ASettings.JpegQuality := UdJpegQuality.Position;
  ASettings.PngCompression := UdPngCompression.Position;
  ASettings.BackgroundAlpha := UdBackgroundAlpha.Position;
  ASettings.SaveFolder := EdtSaveFolder.Text;
  ASettings.ShowBanner := ChkShowBanner.Checked;
  ASettings.BannerBackground := PnlBannerBackground.Color;
  ASettings.BannerTextColor := PnlBannerTextColor.Color;
  ASettings.BannerFontName := FBannerFontName;
  ASettings.BannerFontSize := FBannerFontSize;
  ASettings.BannerFontAutoSize := ChkBannerAutoSize.Checked;
  ASettings.BannerPosition := TBannerPosition(CbxBannerPosition.ItemIndex);
  ASettings.SaveAtLiveResolution := ChkSaveAtLiveResolution.Checked;
  ASettings.CopyAtLiveResolution := ChkCopyAtLiveResolution.Checked;
  ASettings.CombinedMaxSide := UdCombinedMaxSide.Position;

  {[Clipboard tab] — symmetric with SettingsToControls; same field order.}
  ASettings.PublishAlphaAwareBitmap := ChkPublishAlphaAwareBitmap.Checked;
  ASettings.PublishCompressedPng := ChkPublishCompressedPng.Checked;
  ASettings.PublishFlattenedBitmap := ChkPublishFlattenedBitmap.Checked;
  ASettings.PublishBitmapHandle := ChkPublishBitmapHandle.Checked;
  ASettings.ClipboardAsFileReference := ChkClipboardAsFileReference.Checked;

  ASettings.CacheEnabled := ChkCacheEnabled.Checked;
  ASettings.CacheFolder := EdtCacheFolder.Text;
  ASettings.CacheMaxSizeMB := UdCacheMaxSize.Position;

  ASettings.QVDisableNavigation := ChkQVDisableNavigation.Checked;
  ASettings.QVHideToolbar := ChkQVHideToolbar.Checked;
  ASettings.QVHideStatusBar := ChkQVHideStatusBar.Checked;

  ASettings.ThumbnailsEnabled := ChkThumbnailsEnabled.Checked;
  ASettings.ThumbnailMode := TThumbnailMode(CbxThumbnailMode.ItemIndex);
  ASettings.ThumbnailPosition := UdThumbnailPosition.Position;
  ASettings.ThumbnailGridFrames := UdThumbnailGridFrames.Position;

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
  UpdateBannerControls;
end;

procedure TSettingsForm.ChkClipboardAsFileReferenceClick(Sender: TObject);
begin
  UpdateClipboardFormatControlsEnabled;
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
  UpdateMaxWorkersControls;
end;

procedure TSettingsForm.EdtCacheFolderChange(Sender: TObject);
begin
  UpdateCacheFolderInfo;
end;

procedure TSettingsForm.BtnClearCacheClick(Sender: TObject);
var
  Dir: string;
  Mgr: ICacheManager;
  ProbeC: TProbeCache;
begin
  Dir := EffectiveCacheFolder(EdtCacheFolder.Text);

  if ShowPluginMessage(Handle, 'Delete all cached frames and probe metadata?', MB_OKCANCEL or MB_ICONQUESTION) <> IDOK then
    Exit;

  if TDirectory.Exists(Dir) then
  begin
    Mgr := CreateCacheManager(Dir, 0);
    Mgr.Clear;
  end;

  {Probe cache lives outside the user-configurable cache folder, in
   %TEMP%\Glimpse\probes. Wiping it alongside the frame cache matches
   user intent (one Cache button = all of Glimpse's on-disk caches).}
  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    ProbeC.Clear;
  finally
    ProbeC.Free;
  end;

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
  UpdateSaveFormatControls;
end;

procedure TSettingsForm.ChkMaxWorkersAutoClick(Sender: TObject);
begin
  UpdateMaxWorkersControls;
end;

procedure TSettingsForm.ChkScaledExtractionClick(Sender: TObject);
begin
  UpdateScaledExtractionControls;
end;

procedure TSettingsForm.TrkRandomPercentChange(Sender: TObject);
begin
  LblRandomPercentValue.Caption := IntToStr(TrkRandomPercent.Position) + '%';
end;

procedure TSettingsForm.ChkCacheEnabledClick(Sender: TObject);
begin
  UpdateCacheControls;
end;

procedure TSettingsForm.ChkThumbnailsEnabledClick(Sender: TObject);
begin
  UpdateThumbnailControls;
end;

procedure TSettingsForm.CbxThumbnailModeChange(Sender: TObject);
begin
  UpdateThumbnailControls;
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
      Item.SubItems.Add(uHotkeys.ChordsToDisplayStr(FHotkeys.Get(A)));
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
  Display := uHotkeys.ChordsToDisplayStr(FHotkeys.Get(AAction));
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

procedure TSettingsForm.UpdateMaxWorkersControls;
var
  OnePerFrame: Boolean;
begin
  OnePerFrame := ChkMaxWorkersAuto.Checked;
  LblMaxWorkers.Enabled := not OnePerFrame;
  EdtMaxWorkers.Enabled := not OnePerFrame;
  UdMaxWorkers.Enabled := not OnePerFrame;
  {Limit workers count is only relevant in one-per-frame mode}
  LblMaxThreads.Enabled := OnePerFrame;
  EdtMaxThreads.Enabled := OnePerFrame;
  UdMaxThreads.Enabled := OnePerFrame;
  LblMaxThreadsAuto.Caption := MaxThreadsAutoLabel(OnePerFrame, UdMaxThreads.Position, CPUCount);
end;

procedure TSettingsForm.UpdateSaveFormatControls;
var
  IsPNG: Boolean;
begin
  IsPNG := CbxSaveFormat.ItemIndex = Ord(sfPNG);
  LblJpegQuality.Enabled := not IsPNG;
  EdtJpegQuality.Enabled := not IsPNG;
  UdJpegQuality.Enabled := not IsPNG;
  LblPngCompression.Enabled := IsPNG;
  EdtPngCompression.Enabled := IsPNG;
  UdPngCompression.Enabled := IsPNG;
  LblBackgroundAlpha.Enabled := IsPNG;
  EdtBackgroundAlpha.Enabled := IsPNG;
  UdBackgroundAlpha.Enabled := IsPNG;
end;

procedure TSettingsForm.UpdateBannerControls;
var
  Enabled: Boolean;
begin
  {Banner style is only meaningful when the banner is actually drawn}
  Enabled := ChkShowBanner.Checked;
  LblBannerBackground.Enabled := Enabled;
  PnlBannerBackground.Enabled := Enabled;
  BtnBannerBackground.Enabled := Enabled;
  LblBannerTextColor.Enabled := Enabled;
  PnlBannerTextColor.Enabled := Enabled;
  BtnBannerTextColor.Enabled := Enabled;
  LblBannerFont.Enabled := Enabled;
  EdtBannerFont.Enabled := Enabled;
  BtnBannerFont.Enabled := Enabled;
  ChkBannerAutoSize.Enabled := Enabled;
  LblBannerPosition.Enabled := Enabled;
  CbxBannerPosition.Enabled := Enabled;
end;

procedure TSettingsForm.UpdateClipboardFormatControlsEnabled;
var
  Enabled: Boolean;
begin
  {File-reference path bypasses the strategy orchestrator entirely, so
   the four per-format toggles have no effect while the override is on.
   Grey them out (and the group header label) so the override is
   visible to the user without reading the hint text.}
  Enabled := not ChkClipboardAsFileReference.Checked;
  LblClipboardFormatsHeader.Enabled := Enabled;
  ChkPublishAlphaAwareBitmap.Enabled := Enabled;
  ChkPublishCompressedPng.Enabled := Enabled;
  ChkPublishFlattenedBitmap.Enabled := Enabled;
  ChkPublishBitmapHandle.Enabled := Enabled;
end;

procedure TSettingsForm.UpdateCacheControls;
var
  CacheOn: Boolean;
begin
  CacheOn := ChkCacheEnabled.Checked;
  LblCacheFolder.Enabled := CacheOn;
  EdtCacheFolder.Enabled := CacheOn;
  BtnCacheFolder.Enabled := CacheOn;
  LblCacheMaxSize.Enabled := CacheOn;
  EdtCacheMaxSize.Enabled := CacheOn;
  UdCacheMaxSize.Enabled := CacheOn;
  LblCacheMaxSizeUnit.Enabled := CacheOn;
end;

procedure TSettingsForm.UpdateScaledExtractionControls;
var
  Enabled: Boolean;
begin
  Enabled := ChkScaledExtraction.Checked;
  LblScaleTarget.Enabled := Enabled;
  EdtMinFrameSide.Enabled := Enabled;
  UdMinFrameSide.Enabled := Enabled;
  LblScaleSep.Enabled := Enabled;
  EdtMaxFrameSide.Enabled := Enabled;
  UdMaxFrameSide.Enabled := Enabled;
  LblScaleUnit.Enabled := Enabled;
  {Auto-refresh has no effect when scaling is off (no MaxSide to compare).}
  ChkAutoRefreshViewport.Enabled := Enabled;
end;

procedure TSettingsForm.UpdateThumbnailControls;
var
  GroupOn, IsSingle, IsGrid: Boolean;
begin
  GroupOn := ChkThumbnailsEnabled.Checked;
  LblThumbnailMode.Enabled := GroupOn;
  CbxThumbnailMode.Enabled := GroupOn;

  {Position controls only meaningful in Single mode; grid frames only in
   Grid mode. Disabling avoids the user editing fields that won't be used.}
  IsSingle := GroupOn and (CbxThumbnailMode.ItemIndex = Ord(tnmSingle));
  IsGrid := GroupOn and (CbxThumbnailMode.ItemIndex = Ord(tnmGrid));

  LblThumbnailPosition.Enabled := IsSingle;
  EdtThumbnailPosition.Enabled := IsSingle;
  UdThumbnailPosition.Enabled := IsSingle;
  LblThumbnailPositionUnit.Enabled := IsSingle;

  LblThumbnailGridFrames.Enabled := IsGrid;
  EdtThumbnailGridFrames.Enabled := IsGrid;
  UdThumbnailGridFrames.Enabled := IsGrid;
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
  Dir: string;
  Mgr: ICacheManager;
  ProbeC: TProbeCache;
  Total: Int64;
begin
  Total := 0;

  Dir := EffectiveCacheFolder(EdtCacheFolder.Text);
  if TDirectory.Exists(Dir) then
  begin
    Mgr := CreateCacheManager(Dir, 0);
    Total := Total + Mgr.GetTotalSize;
  end;

  {Probe cache lives in a separate fixed directory; fold it into the total
   so the readout reflects every byte the plugin keeps on disk.}
  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    Total := Total + ProbeC.GetTotalSize;
  finally
    ProbeC.Free;
  end;

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
