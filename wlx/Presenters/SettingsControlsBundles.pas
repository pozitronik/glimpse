{Per-group control bundles + bind helpers for the WLX settings dialog.
 Each bundle pairs the VCL controls for one TXxxSettingsGroup with paired
 BindXxxToControls / BindXxxFromControls free procedures.

 NOT covered (stays inline in the dialog): font fields, the Hotkeys
 collection, cross-field invariants (ASettings.Validate), the enable-rule
 sweep, and dialog-side UI refresh side effects (UpdateFFmpegInfo etc.).

 Lives under wlx/ rather than src/SettingsGroups.pas so the
 shared-with-WCX groups unit stays VCL-free.}
unit SettingsControlsBundles;

interface

uses
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Settings;

type
  {MaxWorkers/MaxThreads are encoded across an auto-checkbox + spin pair
   via SettingsDlgLogic.}
  TExtractionControls = record
    UdSkipEdges: TUpDown;
    ChkMaxWorkersAuto: TCheckBox;
    UdMaxWorkers: TUpDown;
    UdMaxThreads: TUpDown;
    ChkUseBmpPipe: TCheckBox;
    ChkHwAccel: TCheckBox;
    ChkUseKeyframes: TCheckBox;
    ChkRespectAnamorphic: TCheckBox;
  end;

  TSaveControls = record
    CbxSaveFormat: TComboBox;
    UdJpegQuality: TUpDown;
    UdPngCompression: TUpDown;
    UdBackgroundAlpha: TUpDown;
    EdtSaveFolder: TEdit;
    ChkSaveAtLiveResolution: TCheckBox;
    ChkCopyAtLiveResolution: TCheckBox;
    ChkClipboardAsFileReference: TCheckBox;
    UdCombinedMaxSide: TUpDown;
    ChkScaledExtraction: TCheckBox;
    UdMinFrameSide: TUpDown;
    UdMaxFrameSide: TUpDown;
    ChkAutoRefreshViewport: TCheckBox;
    EdtExtensions: TEdit;
  end;

  {Cache + the random trio (RandomExtraction lives under [extraction] in
   the INI but is read/written by the cache group).}
  TCacheControls = record
    ChkCacheEnabled: TCheckBox;
    EdtCacheFolder: TEdit;
    UdCacheMaxSize: TUpDown;
    ChkRandomExtraction: TCheckBox;
    TrkRandomPercent: TTrackBar;
    ChkCacheRandomFrames: TCheckBox;
  end;

  {Bind-from uses ASettings.SetFFmpegPath (not direct assignment) so the
   setter's validation/normalisation runs.}
  TFFmpegControls = record
    EdtFFmpegPath: TEdit;
  end;

  TViewControls = record
    PnlBackground: TPanel;
    ChkShowToolbar: TCheckBox;
    ChkShowStatusBar: TCheckBox;
    UdCellGap: TUpDown;
    UdBorder: TUpDown;
    CbxProgressBarLayout: TComboBox;
  end;

  {Show + Corner are encoded across ChkShowTimecode + CbxTimestampCorner via SettingsDlgLogic.}
  TTimestampControls = record
    ChkShowTimecode: TCheckBox;
    CbxTimestampCorner: TComboBox;
    PnlTCBack: TPanel;
    UdTCAlpha: TUpDown;
    PnlTCTextColor: TPanel;
    UdTCTextAlpha: TUpDown;
  end;

  TBannerControls = record
    ChkShowBanner: TCheckBox;
    PnlBannerBackground: TPanel;
    PnlBannerTextColor: TPanel;
    ChkBannerAutoSize: TCheckBox;
    CbxBannerPosition: TComboBox;
  end;

  TClipboardFormatsControls = record
    ChkPublishAlphaAwareBitmap: TCheckBox;
    ChkPublishCompressedPng: TCheckBox;
    ChkPublishFlattenedBitmap: TCheckBox;
    ChkPublishBitmapHandle: TCheckBox;
  end;

  {HeightApplyMode is encoded via ord/cast against the combo's ItemIndex.}
  TStatusBarControls = record
    EdtStatusBarTemplate: TEdit;
    ChkStatusBarAutoWidthLive: TCheckBox;
    ChkStatusBarStretchPanels: TCheckBox;
    UdStatusBarHeight: TUpDown;
    CbxStatusBarHeightApply: TComboBox;
  end;

  TQuickViewControls = record
    ChkQVDisableNavigation: TCheckBox;
    ChkQVHideToolbar: TCheckBox;
    ChkQVHideStatusBar: TCheckBox;
  end;

  TThumbnailsControls = record
    ChkThumbnailsEnabled: TCheckBox;
    CbxThumbnailMode: TComboBox;
    UdThumbnailPosition: TUpDown;
    UdThumbnailGridFrames: TUpDown;
  end;

{Settings -> controls. Dialog runs RecomputeEnables / UpdateFFmpegInfo
 / etc. AFTER the binds — these procedures only write VCL properties.}
procedure BindExtractionToControls(ASettings: TPluginSettings; const AControls: TExtractionControls);
procedure BindSaveToControls(ASettings: TPluginSettings; const AControls: TSaveControls);
procedure BindCacheToControls(ASettings: TPluginSettings; const AControls: TCacheControls);
procedure BindFFmpegToControls(ASettings: TPluginSettings; const AControls: TFFmpegControls);
procedure BindViewToControls(ASettings: TPluginSettings; const AControls: TViewControls);
procedure BindTimestampToControls(ASettings: TPluginSettings; const AControls: TTimestampControls);
procedure BindBannerToControls(ASettings: TPluginSettings; const AControls: TBannerControls);
procedure BindClipboardFormatsToControls(ASettings: TPluginSettings; const AControls: TClipboardFormatsControls);
procedure BindStatusBarToControls(ASettings: TPluginSettings; const AControls: TStatusBarControls);
procedure BindQuickViewToControls(ASettings: TPluginSettings; const AControls: TQuickViewControls);
procedure BindThumbnailsToControls(ASettings: TPluginSettings; const AControls: TThumbnailsControls);

{Controls -> settings, symmetric. FFmpeg variant uses SetFFmpegPath
 for normalisation.}
procedure BindExtractionFromControls(ASettings: TPluginSettings; const AControls: TExtractionControls);
procedure BindSaveFromControls(ASettings: TPluginSettings; const AControls: TSaveControls);
procedure BindCacheFromControls(ASettings: TPluginSettings; const AControls: TCacheControls);
procedure BindFFmpegFromControls(ASettings: TPluginSettings; const AControls: TFFmpegControls);
procedure BindViewFromControls(ASettings: TPluginSettings; const AControls: TViewControls);
procedure BindTimestampFromControls(ASettings: TPluginSettings; const AControls: TTimestampControls);
procedure BindBannerFromControls(ASettings: TPluginSettings; const AControls: TBannerControls);
procedure BindClipboardFormatsFromControls(ASettings: TPluginSettings; const AControls: TClipboardFormatsControls);
procedure BindStatusBarFromControls(ASettings: TPluginSettings; const AControls: TStatusBarControls);
procedure BindQuickViewFromControls(ASettings: TPluginSettings; const AControls: TQuickViewControls);
procedure BindThumbnailsFromControls(ASettings: TPluginSettings; const AControls: TThumbnailsControls);

implementation

uses
  System.SysUtils,
  Types, StatusBarLayout, BitmapSaver,
  SettingsDlgLogic;

{Extraction}

procedure BindExtractionToControls(ASettings: TPluginSettings; const AControls: TExtractionControls);
var
  AutoChecked: Boolean;
  UdPos: Integer;
begin
  AControls.UdSkipEdges.Position := ASettings.SkipEdgesPercent;
  DecodeMaxWorkersControls(ASettings.MaxWorkers, AutoChecked, UdPos);
  AControls.ChkMaxWorkersAuto.Checked := AutoChecked;
  AControls.UdMaxWorkers.Position := UdPos;
  AControls.UdMaxThreads.Position := DecodeMaxThreadsControl(ASettings.MaxThreads);
  AControls.ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  AControls.ChkHwAccel.Checked := ASettings.HwAccel;
  AControls.ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  AControls.ChkRespectAnamorphic.Checked := ASettings.RespectAnamorphic;
end;

procedure BindExtractionFromControls(ASettings: TPluginSettings; const AControls: TExtractionControls);
begin
  ASettings.SkipEdgesPercent := AControls.UdSkipEdges.Position;
  ASettings.MaxWorkers := EncodeMaxWorkersControls(AControls.ChkMaxWorkersAuto.Checked, AControls.UdMaxWorkers.Position);
  ASettings.MaxThreads := AControls.UdMaxThreads.Position;
  ASettings.UseBmpPipe := AControls.ChkUseBmpPipe.Checked;
  ASettings.HwAccel := AControls.ChkHwAccel.Checked;
  ASettings.UseKeyframes := AControls.ChkUseKeyframes.Checked;
  ASettings.RespectAnamorphic := AControls.ChkRespectAnamorphic.Checked;
end;

{Save}

procedure BindSaveToControls(ASettings: TPluginSettings; const AControls: TSaveControls);
begin
  AControls.CbxSaveFormat.ItemIndex := Ord(ASettings.SaveFormat);
  AControls.UdJpegQuality.Position := ASettings.JpegQuality;
  AControls.UdPngCompression.Position := ASettings.PngCompression;
  AControls.UdBackgroundAlpha.Position := ASettings.BackgroundAlpha;
  AControls.EdtSaveFolder.Text := ASettings.SaveFolder;
  AControls.ChkSaveAtLiveResolution.Checked := ASettings.SaveAtLiveResolution;
  AControls.ChkCopyAtLiveResolution.Checked := ASettings.CopyAtLiveResolution;
  AControls.ChkClipboardAsFileReference.Checked := ASettings.ClipboardAsFileReference;
  AControls.UdCombinedMaxSide.Position := ASettings.CombinedMaxSide;
  AControls.ChkScaledExtraction.Checked := ASettings.ScaledExtraction;
  AControls.UdMinFrameSide.Position := ASettings.MinFrameSide;
  AControls.UdMaxFrameSide.Position := ASettings.MaxFrameSide;
  AControls.ChkAutoRefreshViewport.Checked := ASettings.AutoRefreshOnViewportChange;
  AControls.EdtExtensions.Text := ASettings.ExtensionList;
end;

procedure BindSaveFromControls(ASettings: TPluginSettings; const AControls: TSaveControls);
begin
  ASettings.SaveFormat := TSaveFormat(AControls.CbxSaveFormat.ItemIndex);
  ASettings.JpegQuality := AControls.UdJpegQuality.Position;
  ASettings.PngCompression := AControls.UdPngCompression.Position;
  ASettings.BackgroundAlpha := AControls.UdBackgroundAlpha.Position;
  ASettings.SaveFolder := AControls.EdtSaveFolder.Text;
  ASettings.SaveAtLiveResolution := AControls.ChkSaveAtLiveResolution.Checked;
  ASettings.CopyAtLiveResolution := AControls.ChkCopyAtLiveResolution.Checked;
  ASettings.ClipboardAsFileReference := AControls.ChkClipboardAsFileReference.Checked;
  ASettings.CombinedMaxSide := AControls.UdCombinedMaxSide.Position;
  ASettings.ScaledExtraction := AControls.ChkScaledExtraction.Checked;
  ASettings.MinFrameSide := AControls.UdMinFrameSide.Position;
  ASettings.MaxFrameSide := AControls.UdMaxFrameSide.Position;
  ASettings.AutoRefreshOnViewportChange := AControls.ChkAutoRefreshViewport.Checked;
  ASettings.ExtensionList := AControls.EdtExtensions.Text;
end;

{Cache}

procedure BindCacheToControls(ASettings: TPluginSettings; const AControls: TCacheControls);
begin
  AControls.ChkCacheEnabled.Checked := ASettings.CacheEnabled;
  AControls.EdtCacheFolder.Text := ASettings.CacheFolder;
  AControls.UdCacheMaxSize.Position := ASettings.CacheMaxSizeMB;
  AControls.ChkRandomExtraction.Checked := ASettings.RandomExtraction;
  AControls.TrkRandomPercent.Position := ASettings.RandomPercent;
  AControls.ChkCacheRandomFrames.Checked := ASettings.CacheRandomFrames;
end;

procedure BindCacheFromControls(ASettings: TPluginSettings; const AControls: TCacheControls);
begin
  ASettings.CacheEnabled := AControls.ChkCacheEnabled.Checked;
  ASettings.CacheFolder := AControls.EdtCacheFolder.Text;
  ASettings.CacheMaxSizeMB := AControls.UdCacheMaxSize.Position;
  ASettings.RandomExtraction := AControls.ChkRandomExtraction.Checked;
  ASettings.RandomPercent := AControls.TrkRandomPercent.Position;
  ASettings.CacheRandomFrames := AControls.ChkCacheRandomFrames.Checked;
end;

{FFmpeg}

procedure BindFFmpegToControls(ASettings: TPluginSettings; const AControls: TFFmpegControls);
begin
  AControls.EdtFFmpegPath.Text := ASettings.FFmpegExePath;
end;

procedure BindFFmpegFromControls(ASettings: TPluginSettings; const AControls: TFFmpegControls);
begin
  ASettings.SetFFmpegPath(AControls.EdtFFmpegPath.Text);
end;

{View}

procedure BindViewToControls(ASettings: TPluginSettings; const AControls: TViewControls);
begin
  AControls.PnlBackground.Color := ASettings.Background;
  AControls.ChkShowToolbar.Checked := ASettings.ShowToolbar;
  AControls.ChkShowStatusBar.Checked := ASettings.ShowStatusBar;
  AControls.UdCellGap.Position := ASettings.CellGap;
  AControls.UdBorder.Position := ASettings.CombinedBorder;
  AControls.CbxProgressBarLayout.ItemIndex := Ord(ASettings.ProgressBarLayout);
end;

procedure BindViewFromControls(ASettings: TPluginSettings; const AControls: TViewControls);
begin
  ASettings.Background := AControls.PnlBackground.Color;
  ASettings.ShowToolbar := AControls.ChkShowToolbar.Checked;
  ASettings.ShowStatusBar := AControls.ChkShowStatusBar.Checked;
  ASettings.CellGap := AControls.UdCellGap.Position;
  ASettings.CombinedBorder := AControls.UdBorder.Position;
  ASettings.ProgressBarLayout := TProgressBarLayout(AControls.CbxProgressBarLayout.ItemIndex);
end;

{Timestamp}

procedure BindTimestampToControls(ASettings: TPluginSettings; const AControls: TTimestampControls);
var
  ShowChecked: Boolean;
  ComboIdx: Integer;
begin
  DecodeTimestampCornerControls(ASettings.ShowTimecode, ASettings.TimestampCorner, ShowChecked, ComboIdx);
  AControls.ChkShowTimecode.Checked := ShowChecked;
  AControls.CbxTimestampCorner.ItemIndex := ComboIdx;
  AControls.PnlTCBack.Color := ASettings.TimecodeBackColor;
  AControls.UdTCAlpha.Position := ASettings.TimecodeBackAlpha;
  AControls.PnlTCTextColor.Color := ASettings.TimestampTextColor;
  AControls.UdTCTextAlpha.Position := ASettings.TimestampTextAlpha;
end;

procedure BindTimestampFromControls(ASettings: TPluginSettings; const AControls: TTimestampControls);
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  EncodeTimestampCornerControls(AControls.ChkShowTimecode.Checked, AControls.CbxTimestampCorner.ItemIndex, Show, Corner);
  ASettings.ShowTimecode := Show;
  ASettings.TimestampCorner := Corner;
  ASettings.TimecodeBackColor := AControls.PnlTCBack.Color;
  ASettings.TimecodeBackAlpha := AControls.UdTCAlpha.Position;
  ASettings.TimestampTextColor := AControls.PnlTCTextColor.Color;
  ASettings.TimestampTextAlpha := AControls.UdTCTextAlpha.Position;
end;

{Banner}

procedure BindBannerToControls(ASettings: TPluginSettings; const AControls: TBannerControls);
begin
  AControls.ChkShowBanner.Checked := ASettings.ShowBanner;
  AControls.PnlBannerBackground.Color := ASettings.BannerBackground;
  AControls.PnlBannerTextColor.Color := ASettings.BannerTextColor;
  AControls.ChkBannerAutoSize.Checked := ASettings.BannerFontAutoSize;
  AControls.CbxBannerPosition.ItemIndex := Ord(ASettings.BannerPosition);
end;

procedure BindBannerFromControls(ASettings: TPluginSettings; const AControls: TBannerControls);
begin
  ASettings.ShowBanner := AControls.ChkShowBanner.Checked;
  ASettings.BannerBackground := AControls.PnlBannerBackground.Color;
  ASettings.BannerTextColor := AControls.PnlBannerTextColor.Color;
  ASettings.BannerFontAutoSize := AControls.ChkBannerAutoSize.Checked;
  ASettings.BannerPosition := TBannerPosition(AControls.CbxBannerPosition.ItemIndex);
end;

{Clipboard formats}

procedure BindClipboardFormatsToControls(ASettings: TPluginSettings; const AControls: TClipboardFormatsControls);
begin
  AControls.ChkPublishAlphaAwareBitmap.Checked := ASettings.PublishAlphaAwareBitmap;
  AControls.ChkPublishCompressedPng.Checked := ASettings.PublishCompressedPng;
  AControls.ChkPublishFlattenedBitmap.Checked := ASettings.PublishFlattenedBitmap;
  AControls.ChkPublishBitmapHandle.Checked := ASettings.PublishBitmapHandle;
end;

procedure BindClipboardFormatsFromControls(ASettings: TPluginSettings; const AControls: TClipboardFormatsControls);
begin
  ASettings.PublishAlphaAwareBitmap := AControls.ChkPublishAlphaAwareBitmap.Checked;
  ASettings.PublishCompressedPng := AControls.ChkPublishCompressedPng.Checked;
  ASettings.PublishFlattenedBitmap := AControls.ChkPublishFlattenedBitmap.Checked;
  ASettings.PublishBitmapHandle := AControls.ChkPublishBitmapHandle.Checked;
end;

{Status bar}

procedure BindStatusBarToControls(ASettings: TPluginSettings; const AControls: TStatusBarControls);
begin
  AControls.EdtStatusBarTemplate.Text := ASettings.StatusBarTemplate;
  AControls.ChkStatusBarAutoWidthLive.Checked := ASettings.StatusBarAutoWidthLive;
  AControls.ChkStatusBarStretchPanels.Checked := ASettings.StatusBarStretchPanels;
  AControls.UdStatusBarHeight.Position := ASettings.StatusBarHeight;
  AControls.CbxStatusBarHeightApply.ItemIndex := Ord(ASettings.StatusBarHeightApplyMode);
end;

procedure BindStatusBarFromControls(ASettings: TPluginSettings; const AControls: TStatusBarControls);
begin
  ASettings.StatusBarTemplate := AControls.EdtStatusBarTemplate.Text;
  ASettings.StatusBarAutoWidthLive := AControls.ChkStatusBarAutoWidthLive.Checked;
  ASettings.StatusBarStretchPanels := AControls.ChkStatusBarStretchPanels.Checked;
  ASettings.StatusBarHeight := AControls.UdStatusBarHeight.Position;
  ASettings.StatusBarHeightApplyMode := TStatusBarHeightApplyMode(AControls.CbxStatusBarHeightApply.ItemIndex);
end;

{Quick view}

procedure BindQuickViewToControls(ASettings: TPluginSettings; const AControls: TQuickViewControls);
begin
  AControls.ChkQVDisableNavigation.Checked := ASettings.QVDisableNavigation;
  AControls.ChkQVHideToolbar.Checked := ASettings.QVHideToolbar;
  AControls.ChkQVHideStatusBar.Checked := ASettings.QVHideStatusBar;
end;

procedure BindQuickViewFromControls(ASettings: TPluginSettings; const AControls: TQuickViewControls);
begin
  ASettings.QVDisableNavigation := AControls.ChkQVDisableNavigation.Checked;
  ASettings.QVHideToolbar := AControls.ChkQVHideToolbar.Checked;
  ASettings.QVHideStatusBar := AControls.ChkQVHideStatusBar.Checked;
end;

{Thumbnails}

procedure BindThumbnailsToControls(ASettings: TPluginSettings; const AControls: TThumbnailsControls);
begin
  AControls.ChkThumbnailsEnabled.Checked := ASettings.ThumbnailsEnabled;
  AControls.CbxThumbnailMode.ItemIndex := Ord(ASettings.ThumbnailMode);
  AControls.UdThumbnailPosition.Position := ASettings.ThumbnailPosition;
  AControls.UdThumbnailGridFrames.Position := ASettings.ThumbnailGridFrames;
end;

procedure BindThumbnailsFromControls(ASettings: TPluginSettings; const AControls: TThumbnailsControls);
begin
  ASettings.ThumbnailsEnabled := AControls.ChkThumbnailsEnabled.Checked;
  ASettings.ThumbnailMode := TThumbnailMode(AControls.CbxThumbnailMode.ItemIndex);
  ASettings.ThumbnailPosition := AControls.UdThumbnailPosition.Position;
  ASettings.ThumbnailGridFrames := AControls.UdThumbnailGridFrames.Position;
end;

end.
