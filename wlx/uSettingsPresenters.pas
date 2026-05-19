{Tab-cluster presenters for the WLX settings dialog.

 Step 84 (C5): the settings form historically owned every event
 handler, update helper, font shadow field, and bundle-binding sequence
 for every tab. This unit splits that ownership into 3 cohesive
 presenters by domain:

   - TExtractionPresenter   General + Sampling tabs (extraction,
                            ffmpeg path, random sampling)
   - TStoragePresenter      Cache + Thumbnails + QuickView tabs
                            (cache folder + size, thumbnails,
                            quickview chrome)
   - TAppearancePresenter   Appearance + Save tabs (view chrome,
                            timestamp/banner/statusbar fonts +
                            colors, save format + banner)

 Each presenter owns: its bundle(s) (referenced, not owned), its
 update helpers, its event-handler methods, and its share of the
 dialog-local font shadow fields (FBannerFontName/Size etc., which
 are not VCL controls and not in any bundle — see uSettingsControlsBundles
 docstring). The form keeps:

   - Enable rules table (BuildEnableRules / RecomputeEnables): a
     single declarative table that step 82 carefully designed; rules
     touch labels and group-mates that aren't in any bundle, and
     splitting them would require additional plumbing for unclear win.
     Rules stay on the form by deliberate choice.
   - Hotkeys cluster (the TListView pattern is structurally different
     from the other tabs).
   - Generic OnColorSwatchClick (cross-cluster: touches Appearance
     panels, Save banner panels, etc.).
   - BtnDefaults, BtnApply, BtnOK, BtnCancel (form-level orchestration).
   - One-liner handlers that only call RecomputeEnables (the rule
     adjacency keeps them on the form).

 DFM event wiring: the form's published handlers stay (DFM-wired)
 and become one-line forwarders to the matching presenter method.}
unit uSettingsPresenters;

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Forms, Vcl.Controls, Vcl.Dialogs,
  uSettings, uSettingsControlsBundles;

type
  {General + Sampling tab logic. Owns the extraction + ffmpeg + cache
   bundles' Sampling-side controls, the ffmpeg-info update helper,
   the random-percent live readout label, and the BtnFFmpegPathClick
   browse dialog.

   The cache bundle is shared with TStoragePresenter (TCacheControls
   spans both tabs: Random* on Sampling, CacheEnabled/Folder/MaxSize
   on Cache). Both presenters hold the same bundle reference — only
   the methods they call on it differ.}
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
    {Pushes ASettings into the bundles this presenter owns, refreshes
     the live percent label and the ffmpeg info panel. Symmetric with
     SaveTo. The form's SettingsToControls calls this once.}
    procedure LoadFrom(ASettings: TPluginSettings);
    {Pulls bundle values back into ASettings. Symmetric with LoadFrom.}
    procedure SaveTo(ASettings: TPluginSettings);
    procedure UpdateFFmpegInfo;
    procedure UpdateRandomPercentLabel;
    {ShowSettingsDialog discovers the live ffmpeg path after the form
     is constructed. The form pushes it here before calling LoadFrom
     so UpdateFFmpegInfo's "Input empty falls back to resolved" branch
     sees the right value.}
    procedure SetResolvedFFmpegPath(const AValue: string);
    {Browses for ffmpeg.exe, validates it via ValidateFFmpeg, and on
     success writes the path into FFFmpegControls.EdtFFmpegPath (the
     EdtFFmpegPath OnChange fires UpdateFFmpegInfo via the form's
     forwarder).}
    procedure OnFFmpegPathClick;
    procedure OnFFmpegPathChange;
    procedure OnRandomPercentChange;
  end;

  {Cache + Thumbnails + QuickView tab logic. Owns the cache + thumbnails
   + quickview bundles, the cache-folder browse + cache-size info
   helpers, and the BtnClearCacheClick deletion confirmation.}
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

  {Appearance + Save tab logic. Owns the view + timestamp + statusbar +
   banner + save bundles, all three font-shadow field pairs (these are
   dialog-local state, not VCL controls, see uSettingsControlsBundles
   docstring), the three Update*FontDisplay helpers, the UpdateStretchLock
   State helper, the three BtnXxxFontClick handlers, and the BtnSaveFolderClick
   browse handler.}
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
    {Enforces the rule that stretch-panels mode implies progress-bar
     Over panels: when the stretch checkbox is on, the progress bar
     combo is forced to "Over panels" and disabled (the runtime would
     override anyway; surfacing the override in the UI lets the user
     understand what they will get).}
    procedure UpdateStretchLockState;
    procedure OnTimestampFontClick;
    procedure OnBannerFontClick;
    procedure OnStatusBarFontClick;
    procedure OnSaveFolderClick;
  end;

implementation

uses
  System.IOUtils,
  uTypes, uStatusBarLayout, uBitmapSaver, uDefaults,
  uFFmpegExe, uFFmpegCmdLine, uPathExpand, uPluginMessages, uCacheMaintenance,
  uSettingsDlgLogic, uSettingsDlgUI;

{Helper: the BtnSaveFolderClick and BtnCacheFolderClick paths both
 use BrowseFolderInto. Free function in uSettingsDlgUI; presenters
 just call it.}

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
var
  Input, Path, Ver, Prefix, Value: string;
  State: TFFmpegProbeState;
begin
  Input := FFFmpegControls.EdtFFmpegPath.Text;
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
  ApplyInfoParts(FLblFFmpegInfo, FEdtFFmpegInfo, Prefix, Value);
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
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if FFFmpegControls.EdtFFmpegPath.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(FFFmpegControls.EdtFFmpegPath.Text));
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      if ValidateFFmpeg(Dlg.FileName) = '' then
      begin
        ShowPluginMessage(FParentWnd, 'The selected file is not a valid ffmpeg executable.', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      FFFmpegControls.EdtFFmpegPath.Text := Dlg.FileName;
      {OnChange fires automatically and updates the info label via the
       form's forwarder -> OnFFmpegPathChange.}
    end;
  finally
    Dlg.Free;
  end;
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
  {Cache is also loaded by Extraction (shared bundle); avoid double-bind
   noise by not re-binding here. Bind only the bundles we exclusively
   own.}
  BindThumbnailsToControls(ASettings, FThumbnailsControls);
  BindQuickViewToControls(ASettings, FQuickViewControls);
  UpdateCacheFolderInfo;
  UpdateCacheSizeInfo;
end;

procedure TStoragePresenter.SaveTo(ASettings: TPluginSettings);
begin
  BindThumbnailsFromControls(ASettings, FThumbnailsControls);
  BindQuickViewFromControls(ASettings, FQuickViewControls);
  {Cache save is performed by Extraction's SaveTo via the shared bundle.}
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
  {Stretch panels forces "Over panels" progress bar layout; runtime
   would override otherwise, surface the override visually.}
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
