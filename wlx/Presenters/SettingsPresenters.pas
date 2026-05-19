{Tab-cluster presenters for the WLX settings dialog, split by domain:
   - TExtractionPresenter: General + Sampling tabs
   - TStoragePresenter:    Cache + Thumbnails + QuickView tabs
   - TAppearancePresenter: Appearance + Save tabs (incl. font shadow fields)

 Stays on the form: enable rules table, Hotkeys cluster, generic
 OnColorSwatchClick, OK/Apply/Cancel orchestration, single-line
 handlers that only call RecomputeEnables.}
unit SettingsPresenters;

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Forms, Vcl.Controls, Vcl.Dialogs,
  Settings, SettingsControlsBundles;

type
  {The cache bundle is shared with TStoragePresenter (Random* on Sampling,
   CacheEnabled/Folder/MaxSize on Cache).}
  TExtractionPresenter = class
  strict private
    FExtractionControls: TExtractionControls;
    FFFmpegControls: TFFmpegControls;
    FCacheControls: TCacheControls;
    FLblFFmpegInfo: TLabel;
    FEdtFFmpegInfo: TEdit;
    FLblRandomPercentValue: TLabel;
    FResolvedFFmpegPath: string;
    FParentWnd: HWND;
  public
    constructor Create(const AExtractionControls: TExtractionControls;
      const AFFmpegControls: TFFmpegControls;
      const ACacheControls: TCacheControls;
      ALblFFmpegInfo: TLabel; AEdtFFmpegInfo: TEdit;
      ALblRandomPercentValue: TLabel;
      const AResolvedFFmpegPath: string; AParentWnd: HWND);
    procedure LoadFrom(ASettings: TPluginSettings);
    procedure SaveTo(ASettings: TPluginSettings);
    procedure UpdateFFmpegInfo;
    procedure UpdateRandomPercentLabel;
    {Push the resolved ffmpeg path so UpdateFFmpegInfo's "input empty falls
     back to resolved" branch sees the right value.}
    procedure SetResolvedFFmpegPath(const AValue: string);
    procedure OnFFmpegPathClick;
    procedure OnFFmpegPathChange;
    procedure OnRandomPercentChange;
  end;

  TStoragePresenter = class
  strict private
    FCacheControls: TCacheControls;
    FThumbnailsControls: TThumbnailsControls;
    FQuickViewControls: TQuickViewControls;
    FLblCacheFolderInfo: TLabel;
    FEdtCacheFolderInfo: TEdit;
    FLblCacheSizeInfo: TLabel;
    FBrowseParent: TWinControl;
    FParentWnd: HWND;
  public
    constructor Create(const ACacheControls: TCacheControls;
      const AThumbnailsControls: TThumbnailsControls;
      const AQuickViewControls: TQuickViewControls;
      ALblCacheFolderInfo: TLabel; AEdtCacheFolderInfo: TEdit;
      ALblCacheSizeInfo: TLabel;
      ABrowseParent: TWinControl; AParentWnd: HWND);
    procedure LoadFrom(ASettings: TPluginSettings);
    procedure SaveTo(ASettings: TPluginSettings);
    procedure UpdateCacheFolderInfo;
    procedure UpdateCacheSizeInfo;
    procedure OnCacheFolderClick;
    procedure OnCacheFolderChange;
    procedure OnClearCacheClick;
  end;

  TAppearancePresenter = class
  strict private
    FViewControls: TViewControls;
    FTimestampControls: TTimestampControls;
    FStatusBarControls: TStatusBarControls;
    FBannerControls: TBannerControls;
    FSaveControls: TSaveControls;
    FEdtTimestampFont: TEdit;
    FEdtBannerFont: TEdit;
    FEdtStatusBarFont: TEdit;
    FBtnAutoSizeCheckBox: TCheckBox;
    FFontDlg: TFontDialog;
    FCbxProgressBarLayout: TComboBox;
    FBrowseParent: TWinControl;
    FParentWnd: HWND;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBannerFontName: string;
    FBannerFontSize: Integer;
    FStatusBarFontName: string;
    FStatusBarFontSize: Integer;
  public
    constructor Create(const AViewControls: TViewControls;
      const ATimestampControls: TTimestampControls;
      const AStatusBarControls: TStatusBarControls;
      const ABannerControls: TBannerControls;
      const ASaveControls: TSaveControls;
      AEdtTimestampFont: TEdit;
      AEdtBannerFont: TEdit;
      AEdtStatusBarFont: TEdit;
      ABtnAutoSizeCheckBox: TCheckBox;
      AFontDlg: TFontDialog;
      ACbxProgressBarLayout: TComboBox;
      ABrowseParent: TWinControl; AParentWnd: HWND);
    procedure LoadFrom(ASettings: TPluginSettings);
    procedure SaveTo(ASettings: TPluginSettings);
    procedure UpdateTimestampFontDisplay;
    procedure UpdateBannerFontDisplay;
    procedure UpdateStatusBarFontDisplay;
    {Stretch-panels forces "Over panels" — runtime would override anyway,
     surfacing it visually keeps the user expectation aligned.}
    procedure UpdateStretchLockState;
    procedure OnTimestampFontClick;
    procedure OnBannerFontClick;
    procedure OnStatusBarFontClick;
    procedure OnSaveFolderClick;
  end;

implementation

uses
  System.IOUtils,
  Types, StatusBarLayout, BitmapSaver, Defaults,
  PluginMessages, CacheMaintenance,
  SettingsDlgLogic, SettingsDlgUI, SettingsDialogHelpers;

{TExtractionPresenter}

constructor TExtractionPresenter.Create(const AExtractionControls: TExtractionControls;
  const AFFmpegControls: TFFmpegControls;
  const ACacheControls: TCacheControls;
  ALblFFmpegInfo: TLabel; AEdtFFmpegInfo: TEdit;
  ALblRandomPercentValue: TLabel;
  const AResolvedFFmpegPath: string; AParentWnd: HWND);
begin
  inherited Create;
  FExtractionControls := AExtractionControls;
  FFFmpegControls := AFFmpegControls;
  FCacheControls := ACacheControls;
  FLblFFmpegInfo := ALblFFmpegInfo;
  FEdtFFmpegInfo := AEdtFFmpegInfo;
  FLblRandomPercentValue := ALblRandomPercentValue;
  FResolvedFFmpegPath := AResolvedFFmpegPath;
  FParentWnd := AParentWnd;
end;

procedure TExtractionPresenter.LoadFrom(ASettings: TPluginSettings);
begin
  BindExtractionToControls(ASettings, FExtractionControls);
  BindFFmpegToControls(ASettings, FFFmpegControls);
  BindCacheToControls(ASettings, FCacheControls);
  UpdateRandomPercentLabel;
  UpdateFFmpegInfo;
end;

procedure TExtractionPresenter.SaveTo(ASettings: TPluginSettings);
begin
  BindExtractionFromControls(ASettings, FExtractionControls);
  BindFFmpegFromControls(ASettings, FFFmpegControls);
  BindCacheFromControls(ASettings, FCacheControls);
end;

procedure TExtractionPresenter.UpdateFFmpegInfo;
begin
  DisplayFFmpegInfo(FFFmpegControls.EdtFFmpegPath.Text, FResolvedFFmpegPath,
    FLblFFmpegInfo, FEdtFFmpegInfo);
end;

procedure TExtractionPresenter.UpdateRandomPercentLabel;
begin
  FLblRandomPercentValue.Caption := IntToStr(FCacheControls.TrkRandomPercent.Position) + '%';
end;

procedure TExtractionPresenter.SetResolvedFFmpegPath(const AValue: string);
begin
  FResolvedFFmpegPath := AValue;
end;

procedure TExtractionPresenter.OnFFmpegPathClick;
begin
  BrowseForFFmpegExe(FFFmpegControls.EdtFFmpegPath, FParentWnd);
end;

procedure TExtractionPresenter.OnFFmpegPathChange;
begin
  UpdateFFmpegInfo;
end;

procedure TExtractionPresenter.OnRandomPercentChange;
begin
  UpdateRandomPercentLabel;
end;

{TStoragePresenter}

constructor TStoragePresenter.Create(const ACacheControls: TCacheControls;
  const AThumbnailsControls: TThumbnailsControls;
  const AQuickViewControls: TQuickViewControls;
  ALblCacheFolderInfo: TLabel; AEdtCacheFolderInfo: TEdit;
  ALblCacheSizeInfo: TLabel;
  ABrowseParent: TWinControl; AParentWnd: HWND);
begin
  inherited Create;
  FCacheControls := ACacheControls;
  FThumbnailsControls := AThumbnailsControls;
  FQuickViewControls := AQuickViewControls;
  FLblCacheFolderInfo := ALblCacheFolderInfo;
  FEdtCacheFolderInfo := AEdtCacheFolderInfo;
  FLblCacheSizeInfo := ALblCacheSizeInfo;
  FBrowseParent := ABrowseParent;
  FParentWnd := AParentWnd;
end;

procedure TStoragePresenter.LoadFrom(ASettings: TPluginSettings);
begin
  {Cache bundle is loaded by Extraction; skip to avoid double-bind.}
  BindThumbnailsToControls(ASettings, FThumbnailsControls);
  BindQuickViewToControls(ASettings, FQuickViewControls);
  UpdateCacheFolderInfo;
  UpdateCacheSizeInfo;
end;

procedure TStoragePresenter.SaveTo(ASettings: TPluginSettings);
begin
  BindThumbnailsFromControls(ASettings, FThumbnailsControls);
  BindQuickViewFromControls(ASettings, FQuickViewControls);
  {Cache saved by Extraction's SaveTo via the shared bundle.}
end;

procedure TStoragePresenter.UpdateCacheFolderInfo;
begin
  if FCacheControls.EdtCacheFolder.Text = '' then
    ApplyInfoParts(FLblCacheFolderInfo, FEdtCacheFolderInfo, 'Default:', DefaultCacheFolder)
  else
    ApplyInfoParts(FLblCacheFolderInfo, FEdtCacheFolderInfo, '', '');
end;

procedure TStoragePresenter.UpdateCacheSizeInfo;
var
  Total: Int64;
begin
  Total := TotalGlimpseCacheBytes(EffectiveCacheFolder(FCacheControls.EdtCacheFolder.Text));
  if Total > 0 then
    FLblCacheSizeInfo.Caption := Format('(current: %.1f MB)', [Total / (1024 * 1024)])
  else
    FLblCacheSizeInfo.Caption := '(current: empty)';
end;

procedure TStoragePresenter.OnCacheFolderClick;
begin
  BrowseFolderInto(FCacheControls.EdtCacheFolder, FBrowseParent);
end;

procedure TStoragePresenter.OnCacheFolderChange;
begin
  UpdateCacheFolderInfo;
end;

procedure TStoragePresenter.OnClearCacheClick;
begin
  if ShowPluginMessage(FParentWnd, 'Delete all cached frames and probe metadata?', MB_OKCANCEL or MB_ICONQUESTION) <> IDOK then
    Exit;
  ClearAllGlimpseCaches(EffectiveCacheFolder(FCacheControls.EdtCacheFolder.Text));
  UpdateCacheSizeInfo;
end;

{TAppearancePresenter}

constructor TAppearancePresenter.Create(const AViewControls: TViewControls;
  const ATimestampControls: TTimestampControls;
  const AStatusBarControls: TStatusBarControls;
  const ABannerControls: TBannerControls;
  const ASaveControls: TSaveControls;
  AEdtTimestampFont: TEdit;
  AEdtBannerFont: TEdit;
  AEdtStatusBarFont: TEdit;
  ABtnAutoSizeCheckBox: TCheckBox;
  AFontDlg: TFontDialog;
  ACbxProgressBarLayout: TComboBox;
  ABrowseParent: TWinControl; AParentWnd: HWND);
begin
  inherited Create;
  FViewControls := AViewControls;
  FTimestampControls := ATimestampControls;
  FStatusBarControls := AStatusBarControls;
  FBannerControls := ABannerControls;
  FSaveControls := ASaveControls;
  FEdtTimestampFont := AEdtTimestampFont;
  FEdtBannerFont := AEdtBannerFont;
  FEdtStatusBarFont := AEdtStatusBarFont;
  FBtnAutoSizeCheckBox := ABtnAutoSizeCheckBox;
  FFontDlg := AFontDlg;
  FCbxProgressBarLayout := ACbxProgressBarLayout;
  FBrowseParent := ABrowseParent;
  FParentWnd := AParentWnd;
end;

procedure TAppearancePresenter.LoadFrom(ASettings: TPluginSettings);
begin
  BindViewToControls(ASettings, FViewControls);
  BindTimestampToControls(ASettings, FTimestampControls);
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
  BindSaveToControls(ASettings, FSaveControls);
end;

procedure TAppearancePresenter.SaveTo(ASettings: TPluginSettings);
begin
  BindViewFromControls(ASettings, FViewControls);
  BindTimestampFromControls(ASettings, FTimestampControls);
  ASettings.TimestampFontName := FTimestampFontName;
  ASettings.TimestampFontSize := FTimestampFontSize;
  BindStatusBarFromControls(ASettings, FStatusBarControls);
  ASettings.StatusBarFontName := FStatusBarFontName;
  ASettings.StatusBarFontSize := FStatusBarFontSize;
  BindBannerFromControls(ASettings, FBannerControls);
  ASettings.BannerFontName := FBannerFontName;
  ASettings.BannerFontSize := FBannerFontSize;
  BindSaveFromControls(ASettings, FSaveControls);
end;

procedure TAppearancePresenter.UpdateTimestampFontDisplay;
begin
  RefreshFontEdit(FEdtTimestampFont, FTimestampFontName, FTimestampFontSize);
end;

procedure TAppearancePresenter.UpdateBannerFontDisplay;
begin
  RefreshBannerFontEdit(FEdtBannerFont, FBtnAutoSizeCheckBox.Checked, FBannerFontName, FBannerFontSize);
end;

procedure TAppearancePresenter.UpdateStatusBarFontDisplay;
begin
  RefreshFontEdit(FEdtStatusBarFont, FStatusBarFontName, FStatusBarFontSize);
end;

procedure TAppearancePresenter.UpdateStretchLockState;
begin
  if FStatusBarControls.ChkStatusBarStretchPanels.Checked then
  begin
    FCbxProgressBarLayout.ItemIndex := Ord(pblOverPanels);
    FCbxProgressBarLayout.Enabled := False;
  end
  else
    FCbxProgressBarLayout.Enabled := True;
end;

procedure TAppearancePresenter.OnTimestampFontClick;
begin
  PickFontInto(FFontDlg, FEdtTimestampFont, FTimestampFontName, FTimestampFontSize,
    MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
end;

procedure TAppearancePresenter.OnBannerFontClick;
var
  AutoSize: Boolean;
begin
  AutoSize := FBtnAutoSizeCheckBox.Checked;
  PickBannerFontInto(FFontDlg, FEdtBannerFont, AutoSize, FBannerFontName, FBannerFontSize,
    MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE, DEF_BANNER_FONT_SIZE);
end;

procedure TAppearancePresenter.OnStatusBarFontClick;
begin
  PickFontInto(FFontDlg, FEdtStatusBarFont, FStatusBarFontName, FStatusBarFontSize,
    MIN_STATUSBAR_FONT_SIZE, MAX_STATUSBAR_FONT_SIZE);
end;

procedure TAppearancePresenter.OnSaveFolderClick;
begin
  BrowseFolderInto(FSaveControls.EdtSaveFolder, FBrowseParent);
end;

end.
