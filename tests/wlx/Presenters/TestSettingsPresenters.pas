{Tests for wlx/SettingsPresenters. Per-presenter LoadFrom / SaveTo
 round-trip through real VCL controls + selected event-handler
 behaviours. Full per-rule coverage lives in TestEnableRules and
 per-bundle coverage in TestSettingsControlsBundles; this fixture
 pins the presenter as a cohesive owner of its slice.

 Each test owns a hidden TForm.CreateNew to give every VCL control a
 parent window — TComboBox.ItemIndex / TUpDown.Position need
 HandleAllocated to apply.}
unit TestSettingsPresenters;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsPresenters = class
  public
    [Test] procedure Extraction_LoadFrom_BindsControls_AndPercentLabel;
    [Test] procedure Extraction_SaveTo_RoundTripsBackToSettings;
    [Test] procedure Extraction_RandomPercentChange_UpdatesLiveLabel;
    [Test] procedure Storage_LoadFrom_BindsThumbnailsAndQuickView_NotCache;
    [Test] procedure Storage_CacheFolderChange_UpdatesFolderInfo;
    [Test] procedure Appearance_LoadFrom_BindsAndRoundTripsFontShadows;
    [Test] procedure Appearance_SaveTo_PushesFontShadowsBackToSettings;
    [Test] procedure Appearance_StretchOn_ForcesProgressBarOverPanelsAndDisables;
    [Test] procedure Appearance_StretchOff_ReEnablesProgressBarLayout;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Controls, Vcl.Dialogs,
  Types, StatusBarLayout, BitmapSaver, Defaults,
  Settings,
  SettingsControlsBundles,
  SettingsPresenters;

{Helpers: same factory pattern as TestSettingsControlsBundles. Each
 control gets the form as both owner (lifetime) and parent (handle).
 Each presenter test constructs its own form so failures don't
 cross-contaminate.}

function MakeCheckBox(AParent: TWinControl): TCheckBox;
begin
  Result := TCheckBox.Create(AParent);
  Result.Parent := AParent;
end;

function MakeEdit(AParent: TWinControl): TEdit;
begin
  Result := TEdit.Create(AParent);
  Result.Parent := AParent;
end;

function MakeLabel(AParent: TWinControl): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
end;

function MakeUpDown(AParent: TWinControl; AMin, AMax: Integer): TUpDown;
begin
  Result := TUpDown.Create(AParent);
  Result.Parent := AParent;
  Result.Min := AMin;
  Result.Max := AMax;
end;

function MakePanel(AParent: TWinControl): TPanel;
begin
  Result := TPanel.Create(AParent);
  Result.Parent := AParent;
end;

function MakeComboBox(AParent: TWinControl; ANumItems: Integer): TComboBox;
var
  I: Integer;
begin
  Result := TComboBox.Create(AParent);
  Result.Parent := AParent;
  for I := 0 to ANumItems - 1 do
    Result.Items.Add(IntToStr(I));
end;

function MakeTrackBar(AParent: TWinControl; AMin, AMax: Integer): TTrackBar;
begin
  Result := TTrackBar.Create(AParent);
  Result.Parent := AParent;
  Result.Min := AMin;
  Result.Max := AMax;
end;

{Builds a full TExtractionControls bundle with the controls a test needs.}
procedure BuildExtractionControls(AParent: TWinControl; out AControls: TExtractionControls);
begin
  AControls.UdSkipEdges := MakeUpDown(AParent, 0, 100);
  AControls.ChkMaxWorkersAuto := MakeCheckBox(AParent);
  AControls.UdMaxWorkers := MakeUpDown(AParent, 1, 32);
  AControls.UdMaxThreads := MakeUpDown(AParent, 0, 64);
  AControls.ChkUseBmpPipe := MakeCheckBox(AParent);
  AControls.ChkHwAccel := MakeCheckBox(AParent);
  AControls.ChkUseKeyframes := MakeCheckBox(AParent);
  AControls.ChkRespectAnamorphic := MakeCheckBox(AParent);
end;

procedure BuildFFmpegControls(AParent: TWinControl; out AControls: TFFmpegControls);
begin
  AControls.EdtFFmpegPath := MakeEdit(AParent);
end;

procedure BuildCacheControls(AParent: TWinControl; out AControls: TCacheControls);
begin
  AControls.ChkCacheEnabled := MakeCheckBox(AParent);
  AControls.EdtCacheFolder := MakeEdit(AParent);
  AControls.UdCacheMaxSize := MakeUpDown(AParent, 0, 100000);
  AControls.ChkRandomExtraction := MakeCheckBox(AParent);
  AControls.TrkRandomPercent := MakeTrackBar(AParent, 0, 100);
  AControls.ChkCacheRandomFrames := MakeCheckBox(AParent);
end;

procedure BuildThumbnailsControls(AParent: TWinControl; out AControls: TThumbnailsControls);
begin
  AControls.ChkThumbnailsEnabled := MakeCheckBox(AParent);
  AControls.CbxThumbnailMode := MakeComboBox(AParent, 2);
  AControls.UdThumbnailPosition := MakeUpDown(AParent, 0, 100);
  AControls.UdThumbnailGridFrames := MakeUpDown(AParent, 1, 64);
end;

procedure BuildQuickViewControls(AParent: TWinControl; out AControls: TQuickViewControls);
begin
  AControls.ChkQVDisableNavigation := MakeCheckBox(AParent);
  AControls.ChkQVHideToolbar := MakeCheckBox(AParent);
  AControls.ChkQVHideStatusBar := MakeCheckBox(AParent);
  AControls.ChkQVEscClearsSelection := MakeCheckBox(AParent);
end;

procedure BuildViewControls(AParent: TWinControl; out AControls: TViewControls);
begin
  AControls.PnlBackground := MakePanel(AParent);
  AControls.ChkShowToolbar := MakeCheckBox(AParent);
  AControls.ChkShowStatusBar := MakeCheckBox(AParent);
  AControls.UdCellGap := MakeUpDown(AParent, 0, 100);
  AControls.UdBorder := MakeUpDown(AParent, 0, 100);
  AControls.CbxProgressBarLayout := MakeComboBox(AParent, 3);
  AControls.ChkShowListerMenu := MakeCheckBox(AParent);
end;

procedure BuildTimestampControls(AParent: TWinControl; out AControls: TTimestampControls);
begin
  AControls.ChkShowTimecode := MakeCheckBox(AParent);
  AControls.CbxTimestampCorner := MakeComboBox(AParent, 4);
  AControls.PnlTCBack := MakePanel(AParent);
  AControls.UdTCAlpha := MakeUpDown(AParent, 0, 255);
  AControls.PnlTCTextColor := MakePanel(AParent);
  AControls.UdTCTextAlpha := MakeUpDown(AParent, 0, 255);
end;

procedure BuildStatusBarControls(AParent: TWinControl; out AControls: TStatusBarControls);
begin
  AControls.EdtStatusBarTemplate := MakeEdit(AParent);
  AControls.ChkStatusBarAutoWidthLive := MakeCheckBox(AParent);
  AControls.ChkStatusBarStretchPanels := MakeCheckBox(AParent);
  AControls.UdStatusBarHeight := MakeUpDown(AParent, 0, 200);
  AControls.CbxStatusBarHeightApply := MakeComboBox(AParent, 3);
  AControls.CbxStatusBarDimensionClick := MakeComboBox(AParent, 2);
end;

procedure BuildBannerControls(AParent: TWinControl; out AControls: TBannerControls);
begin
  AControls.ChkShowBanner := MakeCheckBox(AParent);
  AControls.PnlBannerBackground := MakePanel(AParent);
  AControls.PnlBannerTextColor := MakePanel(AParent);
  AControls.ChkBannerAutoSize := MakeCheckBox(AParent);
  AControls.CbxBannerPosition := MakeComboBox(AParent, 2);
end;

procedure BuildSaveControls(AParent: TWinControl; out AControls: TSaveControls);
begin
  AControls.CbxSaveFormat := MakeComboBox(AParent, 2);
  AControls.UdJpegQuality := MakeUpDown(AParent, 1, 100);
  AControls.UdPngCompression := MakeUpDown(AParent, 0, 9);
  AControls.UdBackgroundAlpha := MakeUpDown(AParent, 0, 255);
  AControls.EdtSaveFolder := MakeEdit(AParent);
  AControls.ChkSaveAtLiveResolution := MakeCheckBox(AParent);
  AControls.ChkCopyAtLiveResolution := MakeCheckBox(AParent);
  AControls.ChkClipboardAsFileReference := MakeCheckBox(AParent);
  AControls.UdCombinedMaxSide := MakeUpDown(AParent, 0, 16384);
  AControls.ChkScaledExtraction := MakeCheckBox(AParent);
  AControls.UdMinFrameSide := MakeUpDown(AParent, 0, 4096);
  AControls.UdMaxFrameSide := MakeUpDown(AParent, 0, 4096);
  AControls.ChkAutoRefreshViewport := MakeCheckBox(AParent);
  AControls.EdtExtensions := MakeEdit(AParent);
end;

{TExtractionPresenter}

procedure TTestSettingsPresenters.Extraction_LoadFrom_BindsControls_AndPercentLabel;
var
  Form: TForm;
  Extraction: TExtractionControls;
  FFmpeg: TFFmpegControls;
  Cache: TCacheControls;
  LblFFmpegInfo, LblPercent: TLabel;
  EdtFFmpegInfo: TEdit;
  Presenter: TExtractionPresenter;
  Settings: TPluginSettings;
begin
  Form := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    BuildExtractionControls(Form, Extraction);
    BuildFFmpegControls(Form, FFmpeg);
    BuildCacheControls(Form, Cache);
    LblFFmpegInfo := MakeLabel(Form);
    LblPercent := MakeLabel(Form);
    EdtFFmpegInfo := MakeEdit(Form);

    Presenter := TExtractionPresenter.Create(Extraction, FFmpeg, Cache,
      LblFFmpegInfo, EdtFFmpegInfo, LblPercent, '', 0);
    try
      Settings.SkipEdgesPercent := 23;
      Settings.UseBmpPipe := True;
      Settings.RandomPercent := 42;
      Presenter.LoadFrom(Settings);
      Assert.AreEqual(23, Extraction.UdSkipEdges.Position,
        'Extraction bundle bound');
      Assert.IsTrue(Extraction.ChkUseBmpPipe.Checked,
        'Extraction-side toggle reflects settings');
      Assert.AreEqual(42, Cache.TrkRandomPercent.Position,
        'Cache bundle (random subset) also bound by Extraction presenter');
      Assert.AreEqual('42%', LblPercent.Caption,
        'Random-percent live label updated by LoadFrom');
    finally
      Presenter.Free;
    end;
  finally
    Settings.Free;
    Form.Free;
  end;
end;

procedure TTestSettingsPresenters.Extraction_SaveTo_RoundTripsBackToSettings;
var
  Form: TForm;
  Extraction: TExtractionControls;
  FFmpeg: TFFmpegControls;
  Cache: TCacheControls;
  LblFFmpegInfo, LblPercent: TLabel;
  EdtFFmpegInfo: TEdit;
  Presenter: TExtractionPresenter;
  Source, Reloaded: TPluginSettings;
begin
  Form := TForm.CreateNew(nil);
  Source := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    BuildExtractionControls(Form, Extraction);
    BuildFFmpegControls(Form, FFmpeg);
    BuildCacheControls(Form, Cache);
    LblFFmpegInfo := MakeLabel(Form);
    LblPercent := MakeLabel(Form);
    EdtFFmpegInfo := MakeEdit(Form);

    Presenter := TExtractionPresenter.Create(Extraction, FFmpeg, Cache,
      LblFFmpegInfo, EdtFFmpegInfo, LblPercent, '', 0);
    try
      Source.SkipEdgesPercent := 9;
      Source.UseBmpPipe := True;
      Source.HwAccel := False;
      Source.UseKeyframes := True;
      Source.RandomExtraction := True;
      Source.RandomPercent := 31;
      Source.CacheRandomFrames := True;
      Source.SetFFmpegPath('C:\bin\ffmpeg.exe');
      Presenter.LoadFrom(Source);

      Presenter.SaveTo(Reloaded);
      Assert.AreEqual(9, Reloaded.SkipEdgesPercent);
      Assert.IsTrue(Reloaded.UseBmpPipe);
      Assert.IsTrue(Reloaded.UseKeyframes);
      Assert.IsTrue(Reloaded.RandomExtraction,
        'Cache-bundle save round-trips through Extraction.SaveTo (shared bundle)');
      Assert.AreEqual(31, Reloaded.RandomPercent);
      Assert.AreEqual('C:\bin\ffmpeg.exe', Reloaded.FFmpegExePath);
    finally
      Presenter.Free;
    end;
  finally
    Reloaded.Free;
    Source.Free;
    Form.Free;
  end;
end;

procedure TTestSettingsPresenters.Extraction_RandomPercentChange_UpdatesLiveLabel;
var
  Form: TForm;
  Extraction: TExtractionControls;
  FFmpeg: TFFmpegControls;
  Cache: TCacheControls;
  LblFFmpegInfo, LblPercent: TLabel;
  EdtFFmpegInfo: TEdit;
  Presenter: TExtractionPresenter;
begin
  Form := TForm.CreateNew(nil);
  try
    BuildExtractionControls(Form, Extraction);
    BuildFFmpegControls(Form, FFmpeg);
    BuildCacheControls(Form, Cache);
    LblFFmpegInfo := MakeLabel(Form);
    LblPercent := MakeLabel(Form);
    EdtFFmpegInfo := MakeEdit(Form);

    Presenter := TExtractionPresenter.Create(Extraction, FFmpeg, Cache,
      LblFFmpegInfo, EdtFFmpegInfo, LblPercent, '', 0);
    try
      Cache.TrkRandomPercent.Position := 77;
      Presenter.OnRandomPercentChange;
      Assert.AreEqual('77%', LblPercent.Caption,
        'OnRandomPercentChange reads the trackbar and rewrites the label');
    finally
      Presenter.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TStoragePresenter}

procedure TTestSettingsPresenters.Storage_LoadFrom_BindsThumbnailsAndQuickView_NotCache;
var
  Form: TForm;
  Cache: TCacheControls;
  Thumbnails: TThumbnailsControls;
  QuickView: TQuickViewControls;
  LblFolderInfo, LblSizeInfo: TLabel;
  EdtFolderInfo: TEdit;
  Presenter: TStoragePresenter;
  Settings: TPluginSettings;
begin
  Form := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    BuildCacheControls(Form, Cache);
    BuildThumbnailsControls(Form, Thumbnails);
    BuildQuickViewControls(Form, QuickView);
    LblFolderInfo := MakeLabel(Form);
    LblSizeInfo := MakeLabel(Form);
    EdtFolderInfo := MakeEdit(Form);

    Presenter := TStoragePresenter.Create(Cache, Thumbnails, QuickView,
      LblFolderInfo, EdtFolderInfo, LblSizeInfo, Form, 0);
    try
      Settings.ThumbnailsEnabled := True;
      Settings.ThumbnailGridFrames := 7;
      Settings.QVHideToolbar := True;
      {Cache fields too - we pin that Storage's LoadFrom does NOT bind
       them (it's the Extraction presenter's responsibility via the
       shared bundle).}
      Settings.CacheEnabled := True;
      Settings.CacheMaxSizeMB := 5000;
      Presenter.LoadFrom(Settings);

      Assert.IsTrue(Thumbnails.ChkThumbnailsEnabled.Checked,
        'Thumbnails bundle bound');
      Assert.AreEqual(7, Thumbnails.UdThumbnailGridFrames.Position);
      Assert.IsTrue(QuickView.ChkQVHideToolbar.Checked, 'QuickView bundle bound');
      Assert.IsFalse(Cache.ChkCacheEnabled.Checked,
        'Cache bundle is NOT re-bound by Storage.LoadFrom (Extraction owns the bind)');
      Assert.AreEqual(0, Cache.UdCacheMaxSize.Position,
        'Cache bundle MaxSize untouched by Storage.LoadFrom');
    finally
      Presenter.Free;
    end;
  finally
    Settings.Free;
    Form.Free;
  end;
end;

procedure TTestSettingsPresenters.Storage_CacheFolderChange_UpdatesFolderInfo;
var
  Form: TForm;
  Cache: TCacheControls;
  Thumbnails: TThumbnailsControls;
  QuickView: TQuickViewControls;
  LblFolderInfo, LblSizeInfo: TLabel;
  EdtFolderInfo: TEdit;
  Presenter: TStoragePresenter;
  CaptionWhenEmpty, CaptionWhenSet: string;
begin
  Form := TForm.CreateNew(nil);
  try
    BuildCacheControls(Form, Cache);
    BuildThumbnailsControls(Form, Thumbnails);
    BuildQuickViewControls(Form, QuickView);
    LblFolderInfo := MakeLabel(Form);
    LblSizeInfo := MakeLabel(Form);
    EdtFolderInfo := MakeEdit(Form);

    Presenter := TStoragePresenter.Create(Cache, Thumbnails, QuickView,
      LblFolderInfo, EdtFolderInfo, LblSizeInfo, Form, 0);
    try
      Cache.EdtCacheFolder.Text := '';
      Presenter.OnCacheFolderChange;
      CaptionWhenEmpty := LblFolderInfo.Caption;
      Cache.EdtCacheFolder.Text := 'D:\custom\cache';
      Presenter.OnCacheFolderChange;
      CaptionWhenSet := LblFolderInfo.Caption;

      Assert.AreNotEqual(CaptionWhenEmpty, CaptionWhenSet,
        'Empty folder shows default-path hint; non-empty hides the hint');
    finally
      Presenter.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TAppearancePresenter}

procedure TTestSettingsPresenters.Appearance_LoadFrom_BindsAndRoundTripsFontShadows;
var
  Form: TForm;
  View: TViewControls;
  Timestamp: TTimestampControls;
  StatusBar: TStatusBarControls;
  Banner: TBannerControls;
  Save: TSaveControls;
  EdtTSFont, EdtBnFont, EdtSBFont: TEdit;
  FontDlg: TFontDialog;
  Presenter: TAppearancePresenter;
  Settings: TPluginSettings;
begin
  Form := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  FontDlg := TFontDialog.Create(Form);
  try
    BuildViewControls(Form, View);
    BuildTimestampControls(Form, Timestamp);
    BuildStatusBarControls(Form, StatusBar);
    BuildBannerControls(Form, Banner);
    BuildSaveControls(Form, Save);
    EdtTSFont := MakeEdit(Form);
    EdtBnFont := MakeEdit(Form);
    EdtSBFont := MakeEdit(Form);

    Presenter := TAppearancePresenter.Create(View, Timestamp, StatusBar,
      Banner, Save, EdtTSFont, EdtBnFont, EdtSBFont,
      Banner.ChkBannerAutoSize, FontDlg, View.CbxProgressBarLayout, Form, 0);
    try
      Settings.Background := clNavy;
      Settings.TimecodeBackColor := clRed;
      Settings.TimestampFontName := 'Arial';
      Settings.TimestampFontSize := 14;
      Settings.BannerFontName := 'Verdana';
      Settings.BannerFontSize := 11;
      Settings.StatusBarFontName := 'Tahoma';
      Settings.StatusBarFontSize := 8;
      Settings.ShowBanner := True;
      Settings.SaveFolder := 'C:\frames';

      Presenter.LoadFrom(Settings);
      Assert.IsTrue(View.PnlBackground.Color = clNavy, 'View bundle bound');
      Assert.IsTrue(Timestamp.PnlTCBack.Color = clRed, 'Timestamp bundle bound');
      Assert.IsTrue(Banner.ChkShowBanner.Checked, 'Banner bundle bound');
      Assert.AreEqual('C:\frames', Save.EdtSaveFolder.Text, 'Save bundle bound');
      {Font display labels are formatted as "FontName, Npt"; just pin
       that something containing the font name landed there.}
      Assert.IsTrue(Pos('Arial', EdtTSFont.Text) > 0,
        'UpdateTimestampFontDisplay fired with shadow value');
      Assert.IsTrue(Pos('Verdana', EdtBnFont.Text) > 0);
      Assert.IsTrue(Pos('Tahoma', EdtSBFont.Text) > 0);
    finally
      Presenter.Free;
    end;
  finally
    Settings.Free;
    Form.Free;
  end;
end;

procedure TTestSettingsPresenters.Appearance_SaveTo_PushesFontShadowsBackToSettings;
var
  Form: TForm;
  View: TViewControls;
  Timestamp: TTimestampControls;
  StatusBar: TStatusBarControls;
  Banner: TBannerControls;
  Save: TSaveControls;
  EdtTSFont, EdtBnFont, EdtSBFont: TEdit;
  FontDlg: TFontDialog;
  Presenter: TAppearancePresenter;
  Source, Reloaded: TPluginSettings;
begin
  Form := TForm.CreateNew(nil);
  Source := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  FontDlg := TFontDialog.Create(Form);
  try
    BuildViewControls(Form, View);
    BuildTimestampControls(Form, Timestamp);
    BuildStatusBarControls(Form, StatusBar);
    BuildBannerControls(Form, Banner);
    BuildSaveControls(Form, Save);
    EdtTSFont := MakeEdit(Form);
    EdtBnFont := MakeEdit(Form);
    EdtSBFont := MakeEdit(Form);

    Presenter := TAppearancePresenter.Create(View, Timestamp, StatusBar,
      Banner, Save, EdtTSFont, EdtBnFont, EdtSBFont,
      Banner.ChkBannerAutoSize, FontDlg, View.CbxProgressBarLayout, Form, 0);
    try
      Source.TimestampFontName := 'Consolas';
      Source.TimestampFontSize := 13;
      Source.BannerFontName := 'Segoe UI';
      Source.BannerFontSize := 16;
      Source.StatusBarFontName := 'Courier New';
      Source.StatusBarFontSize := 10;
      Presenter.LoadFrom(Source);

      Presenter.SaveTo(Reloaded);
      Assert.AreEqual('Consolas', Reloaded.TimestampFontName,
        'Timestamp font shadow round-trips via SaveTo');
      Assert.AreEqual(13, Reloaded.TimestampFontSize);
      Assert.AreEqual('Segoe UI', Reloaded.BannerFontName);
      Assert.AreEqual(16, Reloaded.BannerFontSize);
      Assert.AreEqual('Courier New', Reloaded.StatusBarFontName);
      Assert.AreEqual(10, Reloaded.StatusBarFontSize);
    finally
      Presenter.Free;
    end;
  finally
    Reloaded.Free;
    Source.Free;
    Form.Free;
  end;
end;

procedure TTestSettingsPresenters.Appearance_StretchOn_ForcesProgressBarOverPanelsAndDisables;
var
  Form: TForm;
  View: TViewControls;
  Timestamp: TTimestampControls;
  StatusBar: TStatusBarControls;
  Banner: TBannerControls;
  Save: TSaveControls;
  EdtTSFont, EdtBnFont, EdtSBFont: TEdit;
  FontDlg: TFontDialog;
  Presenter: TAppearancePresenter;
begin
  Form := TForm.CreateNew(nil);
  FontDlg := TFontDialog.Create(Form);
  try
    BuildViewControls(Form, View);
    BuildTimestampControls(Form, Timestamp);
    BuildStatusBarControls(Form, StatusBar);
    BuildBannerControls(Form, Banner);
    BuildSaveControls(Form, Save);
    EdtTSFont := MakeEdit(Form);
    EdtBnFont := MakeEdit(Form);
    EdtSBFont := MakeEdit(Form);

    Presenter := TAppearancePresenter.Create(View, Timestamp, StatusBar,
      Banner, Save, EdtTSFont, EdtBnFont, EdtSBFont,
      Banner.ChkBannerAutoSize, FontDlg, View.CbxProgressBarLayout, Form, 0);
    try
      View.CbxProgressBarLayout.ItemIndex := Ord(pblAfterPanels);
      View.CbxProgressBarLayout.Enabled := True;
      StatusBar.ChkStatusBarStretchPanels.Checked := True;
      Presenter.UpdateStretchLockState;
      Assert.AreEqual(Ord(pblOverPanels), View.CbxProgressBarLayout.ItemIndex,
        'Stretch on forces Over panels');
      Assert.IsFalse(View.CbxProgressBarLayout.Enabled,
        'Stretch on disables the combo so the user sees the runtime override');
    finally
      Presenter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsPresenters.Appearance_StretchOff_ReEnablesProgressBarLayout;
var
  Form: TForm;
  View: TViewControls;
  Timestamp: TTimestampControls;
  StatusBar: TStatusBarControls;
  Banner: TBannerControls;
  Save: TSaveControls;
  EdtTSFont, EdtBnFont, EdtSBFont: TEdit;
  FontDlg: TFontDialog;
  Presenter: TAppearancePresenter;
begin
  Form := TForm.CreateNew(nil);
  FontDlg := TFontDialog.Create(Form);
  try
    BuildViewControls(Form, View);
    BuildTimestampControls(Form, Timestamp);
    BuildStatusBarControls(Form, StatusBar);
    BuildBannerControls(Form, Banner);
    BuildSaveControls(Form, Save);
    EdtTSFont := MakeEdit(Form);
    EdtBnFont := MakeEdit(Form);
    EdtSBFont := MakeEdit(Form);

    Presenter := TAppearancePresenter.Create(View, Timestamp, StatusBar,
      Banner, Save, EdtTSFont, EdtBnFont, EdtSBFont,
      Banner.ChkBannerAutoSize, FontDlg, View.CbxProgressBarLayout, Form, 0);
    try
      View.CbxProgressBarLayout.Enabled := False;
      StatusBar.ChkStatusBarStretchPanels.Checked := False;
      Presenter.UpdateStretchLockState;
      Assert.IsTrue(View.CbxProgressBarLayout.Enabled,
        'Stretch off re-enables the combo');
    finally
      Presenter.Free;
    end;
  finally
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsPresenters);

end.
