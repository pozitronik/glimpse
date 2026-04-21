unit TestSettings;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginSettings = class
  private
    FTempDir: string;
    FTempIniPath: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDefaultValues;
    [Test]
    procedure TestSaveAndReload;
    [Test]
    procedure TestInvalidIniValues;
    [Test]
    procedure TestFFmpegModeRoundTrip;
    [Test]
    procedure TestViewModeRoundTrip;
    [Test]
    procedure TestZoomModeRoundTrip;
    [Test]
    procedure TestSaveFormatRoundTrip;
    [Test]
    procedure TestColorRoundTrip;
    [Test]
    procedure TestBoundaryValues;
    [Test]
    procedure TestClampOutOfRange;
    [Test]
    procedure TestEmptyExtensionListFallback;
    [Test]
    procedure TestMissingIniFileUsesDefaults;
    [Test]
    procedure TestResetDefaults;
    [Test]
    procedure TestPerModeZoomIndependence;
    [Test]
    procedure TestPerModeZoomRoundTrip;
    [Test]
    procedure TestPerModeZoomDefaultsAllModes;
    [Test]
    procedure TestPerModeZoomOldIniBackwardCompat;
    [Test]
    procedure TestActiveZoomDelegatesToViewMode;
    [Test]
    procedure TestSaveOverwritesPreviousValues;
    [Test]
    procedure TestMaxWorkersBoundaryValues;
    [Test]
    procedure TestPartialIniPreservesDefaults;
    [Test]
    procedure TestDefaultCacheFolderNonEmpty;
    [Test]
    procedure TestEffectiveCacheFolderReturnsConfigured;
    [Test]
    procedure TestEffectiveCacheFolderReturnsDefaultWhenEmpty;
    [Test]
    procedure TestTimecodeBackColorAlphaRoundTrip;
    [Test]
    procedure TestTimecodeBackColorAlphaMalformedFallback;
    [Test]
    procedure TestTimecodeBackColorAlphaEdgeCases;
    [Test]
    procedure TestTimestampTextAlphaDefault;
    [Test]
    procedure TestTimestampTextAlphaRoundTrip;
    [Test]
    procedure TestTimestampTextAlphaClampedHigh;
    [Test]
    procedure TestTimestampTextAlphaClampedLow;
    [Test]
    procedure TestTimestampFontDefaults;
    [Test]
    procedure TestTimestampFontRoundTrip;
    [Test]
    procedure TestTimestampFontSizeClamped;
    [Test]
    procedure TestTimestampFontEmptyFallback;
    [Test]
    procedure TestCellGapDefault;
    [Test]
    procedure TestCellGapRoundTrip;
    [Test]
    procedure TestCellGapClampedHigh;
    [Test]
    procedure TestCellGapClampedLow;
    [Test]
    procedure TestCombinedBorderDefault;
    [Test]
    procedure TestCombinedBorderRoundTrip;
    [Test]
    procedure TestCombinedBorderClampedHigh;
    [Test]
    procedure TestCombinedBorderClampedLow;
    [Test]
    procedure TestTimestampCornerDefault;
    [Test]
    procedure TestTimestampCornerRoundTripAllValues;
    [Test]
    procedure TestTimestampCornerUnknownFallsBackToDefault;
    [Test]
    procedure TestShowBannerDefault;
    [Test]
    procedure TestShowBannerRoundTrip;
    [Test]
    procedure TestCacheMaxSizeBoundaries;
    [Test]
    procedure TestTryParseHexRGBValid;
    [Test]
    procedure TestTryParseHexRGBInvalid;

    { EffectiveCacheFolder + env var integration }
    [Test]
    procedure TestEffectiveCacheFolderExpandsEnvVars;

    { Quick View settings }
    [Test]
    procedure TestQVSettingsDefaultsAllTrue;
    [Test]
    procedure TestQVSettingsRoundTrip;
    [Test]
    procedure TestQVSettingsMissingInIniUsesDefaults;

    { Thumbnail settings }
    [Test]
    procedure TestThumbnailSettingsDefaults;
    [Test]
    procedure TestThumbnailSettingsRoundTrip;
    [Test]
    procedure TestThumbnailSettingsMissingInIniUsesDefaults;
    [Test]
    procedure TestThumbnailPositionClampedHigh;
    [Test]
    procedure TestThumbnailPositionClampedLow;
    [Test]
    procedure TestThumbnailGridFramesClampedHigh;
    [Test]
    procedure TestThumbnailGridFramesClampedLow;
    [Test]
    procedure TestThumbnailModeUnknownStringFallsBackToSingle;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.IniFiles, System.UITypes,
  uTypes, uSettings, uDefaults, uBitmapSaver, uPathExpand, uColorConv;

procedure TTestPluginSettings.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_Test_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FTempIniPath := TPath.Combine(FTempDir, 'test.ini');
end;

procedure TTestPluginSettings.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestPluginSettings.TestDefaultValues;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load; { INI does not exist, so all values should be defaults }

    Assert.AreEqual(Ord(DEF_FFMPEG_MODE), Ord(S.FFmpegMode));
    Assert.AreEqual(DEF_FFMPEG_EXE_PATH, S.FFmpegExePath);
    Assert.AreEqual(DEF_FFMPEG_AUTO_DL, S.FFmpegAutoDownloaded);
    Assert.AreEqual(DEF_FRAMES_COUNT, S.FramesCount);
    Assert.AreEqual(DEF_SKIP_EDGES_PERCENT, S.SkipEdgesPercent);
    Assert.AreEqual(DEF_MAX_WORKERS, S.MaxWorkers);
    Assert.AreEqual(Ord(DEF_VIEW_MODE), Ord(S.ViewMode));
    Assert.AreEqual(Ord(DEF_ZOOM_MODE), Ord(S.ZoomMode));
    Assert.AreEqual(Integer(DEF_BACKGROUND), Integer(S.Background));
    Assert.AreEqual(DEF_SHOW_TIMECODE, S.ShowTimecode);
    Assert.AreEqual(DEF_SHOW_TOOLBAR, S.ShowToolbar);
    Assert.AreEqual(DEF_SHOW_STATUS_BAR, S.ShowStatusBar);
    Assert.AreEqual(DEF_EXTENSION_LIST, S.ExtensionList);
    Assert.AreEqual(Ord(DEF_SAVE_FORMAT), Ord(S.SaveFormat));
    Assert.AreEqual(DEF_JPEG_QUALITY, S.JpegQuality);
    Assert.AreEqual(DEF_PNG_COMPRESSION, S.PngCompression);
    Assert.AreEqual(DEF_SAVE_FOLDER, S.SaveFolder);
    Assert.AreEqual(DEF_CACHE_ENABLED, S.CacheEnabled);
    Assert.AreEqual(DEF_CACHE_FOLDER, S.CacheFolder);
    Assert.AreEqual(DEF_CACHE_MAX_SIZE_MB, S.CacheMaxSizeMB);
    Assert.AreEqual(DEF_QV_DISABLE_NAV, S.QVDisableNavigation);
    Assert.AreEqual(DEF_QV_HIDE_TOOLBAR, S.QVHideToolbar);
    Assert.AreEqual(DEF_QV_HIDE_STATUSBAR, S.QVHideStatusBar);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestSaveAndReload;
var
  S1, S2: TPluginSettings;
begin
  S1 := TPluginSettings.Create(FTempIniPath);
  try
    S1.FFmpegMode := fmExe;
    S1.FFmpegExePath := 'C:\ffmpeg\ffmpeg.exe';
    S1.FFmpegAutoDownloaded := True;
    S1.FramesCount := 8;
    S1.SkipEdgesPercent := 5;
    S1.MaxWorkers := 4;
    S1.ViewMode := vmScroll;
    S1.ZoomMode := zmActual;
    S1.Background := TColor($00FF8040);
    S1.ShowTimecode := False;
    S1.ShowToolbar := False;
    S1.ShowStatusBar := False;
    S1.TimecodeBackColor := TColor($0055AA00);
    S1.TimecodeBackAlpha := 200;
    S1.TimestampTextAlpha := 128;
    S1.ExtensionList := 'mp4,mkv,avi';
    S1.SaveFormat := sfJPEG;
    S1.JpegQuality := 75;
    S1.PngCompression := 9;
    S1.SaveFolder := 'D:\Screenshots';
    S1.CacheEnabled := True;
    S1.CacheFolder := 'C:\Cache';
    S1.CacheMaxSizeMB := 1000;
    S1.QVDisableNavigation := False;
    S1.QVHideToolbar := False;
    S1.QVHideStatusBar := False;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.AreEqual(Ord(fmExe), Ord(S2.FFmpegMode));
    Assert.AreEqual('C:\ffmpeg\ffmpeg.exe', S2.FFmpegExePath);
    Assert.IsTrue(S2.FFmpegAutoDownloaded);
    Assert.AreEqual(8, S2.FramesCount);
    Assert.AreEqual(5, S2.SkipEdgesPercent);
    Assert.AreEqual(4, S2.MaxWorkers);
    Assert.AreEqual(Ord(vmScroll), Ord(S2.ViewMode));
    Assert.AreEqual(Ord(zmActual), Ord(S2.ZoomMode));
    Assert.AreEqual(Integer(TColor($00FF8040)), Integer(S2.Background));
    Assert.IsFalse(S2.ShowTimecode);
    Assert.IsFalse(S2.ShowToolbar);
    Assert.IsFalse(S2.ShowStatusBar);
    Assert.AreEqual(Integer(TColor($0055AA00)), Integer(S2.TimecodeBackColor));
    Assert.AreEqual(200, Integer(S2.TimecodeBackAlpha));
    Assert.AreEqual(128, Integer(S2.TimestampTextAlpha));
    Assert.AreEqual('mp4,mkv,avi', S2.ExtensionList);
    Assert.AreEqual(Ord(sfJPEG), Ord(S2.SaveFormat));
    Assert.AreEqual(75, S2.JpegQuality);
    Assert.AreEqual(9, S2.PngCompression);
    Assert.AreEqual('D:\Screenshots', S2.SaveFolder);
    Assert.IsTrue(S2.CacheEnabled);
    Assert.AreEqual('C:\Cache', S2.CacheFolder);
    Assert.AreEqual(1000, S2.CacheMaxSizeMB);
    Assert.IsFalse(S2.QVDisableNavigation);
    Assert.IsFalse(S2.QVHideToolbar);
    Assert.IsFalse(S2.QVHideStatusBar);
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestInvalidIniValues;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { Write intentionally broken values }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('ffmpeg', 'Mode', 'INVALID');
    Ini.WriteString('view', 'Mode', 'unknown');
    Ini.WriteString('view', 'ZoomMode', 'WRONG');
    Ini.WriteString('view', 'Background', 'not_a_color');
    Ini.WriteString('save', 'Format', 'BMP');
    Ini.WriteInteger('save', 'JpegQuality', 999);
    Ini.WriteInteger('save', 'PngCompression', -1);
    Ini.WriteInteger('cache', 'MaxSizeMB', 5);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Ord(DEF_FFMPEG_MODE), Ord(S.FFmpegMode), 'Invalid ffmpeg mode should fall back to default');
    Assert.AreEqual(Ord(DEF_VIEW_MODE), Ord(S.ViewMode), 'Invalid view mode should fall back to default');
    Assert.AreEqual(Ord(DEF_ZOOM_MODE), Ord(S.ZoomMode), 'Invalid zoom mode should fall back to default');
    Assert.AreEqual(Integer(DEF_BACKGROUND), Integer(S.Background), 'Invalid color should fall back to default');
    Assert.AreEqual(Ord(DEF_SAVE_FORMAT), Ord(S.SaveFormat), 'Unknown format should fall back to default');
    Assert.AreEqual(100, S.JpegQuality, 'Out-of-range quality should be clamped to 100');
    Assert.AreEqual(0, S.PngCompression, 'Negative compression should be clamped to 0');
    Assert.AreEqual(10, S.CacheMaxSizeMB, 'Below-minimum cache size should be clamped to 10');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestFFmpegModeRoundTrip;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.FFmpegMode := fmAuto;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(fmAuto), Ord(S.FFmpegMode));

    S.FFmpegMode := fmExe;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(fmExe), Ord(S.FFmpegMode));
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestViewModeRoundTrip;
var
  S: TPluginSettings;

  procedure Check(AMode: TViewMode; const ALabel: string);
  begin
    S.ViewMode := AMode;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(AMode), Ord(S.ViewMode), ALabel);
  end;

begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Check(vmGrid, 'Grid');
    Check(vmScroll, 'Scroll');
    Check(vmSmartGrid, 'SmartGrid');
    Check(vmFilmstrip, 'Filmstrip');
    Check(vmSingle, 'Single');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestZoomModeRoundTrip;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.ZoomMode := zmFitWindow;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(zmFitWindow), Ord(S.ZoomMode));

    S.ZoomMode := zmFitIfLarger;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(zmFitIfLarger), Ord(S.ZoomMode));

    S.ZoomMode := zmActual;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(zmActual), Ord(S.ZoomMode));
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestSaveFormatRoundTrip;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.SaveFormat := sfPNG;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(sfPNG), Ord(S.SaveFormat));

    S.SaveFormat := sfJPEG;
    S.Save;
    S.Load;
    Assert.AreEqual(Ord(sfJPEG), Ord(S.SaveFormat));
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestColorRoundTrip;
var
  S: TPluginSettings;

  procedure CheckColor(AColor: TColor; const ALabel: string);
  begin
    S.Background := AColor;
    S.Save;
    S.Load;
    Assert.AreEqual(Integer(AColor), Integer(S.Background), ALabel);
  end;

begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    CheckColor(TColor($001E1E1E), 'Near-black (#1E1E1E)');
    CheckColor(TColor($00000000), 'Black (#000000)');
    CheckColor(TColor($00FFFFFF), 'White (#FFFFFF)');
    CheckColor(TColor($00FF0000), 'Pure red (#0000FF in HTML, stored as $00FF0000)');
    CheckColor(TColor($000000FF), 'Pure blue (#FF0000 in HTML, stored as $000000FF)');
    CheckColor(TColor($00F7C34F), 'Arbitrary color');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestBoundaryValues;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    { Test minimum N }
    S.FramesCount := 1;
    S.Save;
    S.Load;
    Assert.AreEqual(1, S.FramesCount);

    { Test maximum N }
    S.FramesCount := 99;
    S.Save;
    S.Load;
    Assert.AreEqual(99, S.FramesCount);

    { Test JPEG quality boundaries }
    S.JpegQuality := 1;
    S.Save;
    S.Load;
    Assert.AreEqual(1, S.JpegQuality);

    S.JpegQuality := 100;
    S.Save;
    S.Load;
    Assert.AreEqual(100, S.JpegQuality);

    { Test PNG compression boundaries }
    S.PngCompression := 0;
    S.Save;
    S.Load;
    Assert.AreEqual(0, S.PngCompression);

    S.PngCompression := 9;
    S.Save;
    S.Load;
    Assert.AreEqual(9, S.PngCompression);

    { Test SkipEdges boundaries }
    S.SkipEdgesPercent := 0;
    S.Save;
    S.Load;
    Assert.AreEqual(0, S.SkipEdgesPercent);

    S.SkipEdgesPercent := 49;
    S.Save;
    S.Load;
    Assert.AreEqual(49, S.SkipEdgesPercent);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestClampOutOfRange;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 0);
    Ini.WriteInteger('extraction', 'SkipEdges', 50);
    Ini.WriteInteger('extraction', 'MaxWorkers', 100);
    Ini.WriteInteger('save', 'JpegQuality', 0);
    Ini.WriteInteger('save', 'PngCompression', 10);
    Ini.WriteInteger('cache', 'MaxSizeMB', 99999);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(1, S.FramesCount, 'N below 1 clamped to 1');
    Assert.AreEqual(49, S.SkipEdgesPercent, 'SkipEdges above 49 clamped to 49');
    Assert.AreEqual(16, S.MaxWorkers, 'MaxWorkers above 16 clamped to 16');
    Assert.AreEqual(1, S.JpegQuality, 'Quality below 1 clamped to 1');
    Assert.AreEqual(9, S.PngCompression, 'Compression above 9 clamped to 9');
    Assert.AreEqual(10000, S.CacheMaxSizeMB, 'Cache size above 10000 clamped to 10000');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestEmptyExtensionListFallback;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('extensions', 'List', '   ');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(DEF_EXTENSION_LIST, S.ExtensionList,
      'Whitespace-only extension list should fall back to default');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestMissingIniFileUsesDefaults;
var
  S: TPluginSettings;
begin
  { Point to a path that definitely does not exist }
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    S.Load;
    Assert.AreEqual(DEF_FRAMES_COUNT, S.FramesCount);
    Assert.AreEqual(Ord(DEF_VIEW_MODE), Ord(S.ViewMode));
    Assert.AreEqual(Ord(DEF_ZOOM_MODE), Ord(S.ZoomMode));
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestResetDefaults;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.FramesCount := 42;
    S.ViewMode := vmScroll;
    S.JpegQuality := 10;

    S.ResetDefaults;

    Assert.AreEqual(DEF_FRAMES_COUNT, S.FramesCount);
    Assert.AreEqual(Ord(DEF_VIEW_MODE), Ord(S.ViewMode));
    Assert.AreEqual(DEF_JPEG_QUALITY, S.JpegQuality);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestPerModeZoomIndependence;
var
  S: TPluginSettings;
begin
  { Setting zoom for one view mode must not affect another }
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.ModeZoom[vmScroll] := zmActual;
    S.ModeZoom[vmFilmstrip] := zmFitIfLarger;
    S.ModeZoom[vmSingle] := zmFitWindow;

    Assert.AreEqual(Ord(zmActual), Ord(S.ModeZoom[vmScroll]), 'Scroll');
    Assert.AreEqual(Ord(zmFitIfLarger), Ord(S.ModeZoom[vmFilmstrip]), 'Filmstrip');
    Assert.AreEqual(Ord(zmFitWindow), Ord(S.ModeZoom[vmSingle]), 'Single');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestPerModeZoomRoundTrip;
var
  S1, S2: TPluginSettings;
begin
  { Each mode gets a distinct zoom; verify all survive save/load }
  S1 := TPluginSettings.Create(FTempIniPath);
  try
    S1.ModeZoom[vmSmartGrid] := zmFitWindow;
    S1.ModeZoom[vmGrid] := zmFitWindow;
    S1.ModeZoom[vmScroll] := zmActual;
    S1.ModeZoom[vmFilmstrip] := zmFitIfLarger;
    S1.ModeZoom[vmSingle] := zmActual;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.AreEqual(Ord(zmFitWindow), Ord(S2.ModeZoom[vmSmartGrid]), 'SmartGrid');
    Assert.AreEqual(Ord(zmFitWindow), Ord(S2.ModeZoom[vmGrid]), 'Grid');
    Assert.AreEqual(Ord(zmActual), Ord(S2.ModeZoom[vmScroll]), 'Scroll');
    Assert.AreEqual(Ord(zmFitIfLarger), Ord(S2.ModeZoom[vmFilmstrip]), 'Filmstrip');
    Assert.AreEqual(Ord(zmActual), Ord(S2.ModeZoom[vmSingle]), 'Single');
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestPerModeZoomDefaultsAllModes;
var
  S: TPluginSettings;
  VM: TViewMode;
begin
  { After Load with missing INI, every mode should have default zoom }
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    for VM := Low(TViewMode) to High(TViewMode) do
      Assert.AreEqual(Ord(DEF_ZOOM_MODE), Ord(S.ModeZoom[VM]),
        'Mode ' + IntToStr(Ord(VM)) + ' should default to DEF_ZOOM_MODE');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestPerModeZoomOldIniBackwardCompat;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { Old INI files have no per-mode zoom sections; all modes should get defaults }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('view', 'Mode', 'scroll');
    { No [view.scroll], [view.filmstrip] etc. sections }
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Ord(vmScroll), Ord(S.ViewMode), 'ViewMode should load');
    Assert.AreEqual(Ord(DEF_ZOOM_MODE), Ord(S.ModeZoom[vmScroll]),
      'Missing per-mode section should fall back to default');
    Assert.AreEqual(Ord(DEF_ZOOM_MODE), Ord(S.ModeZoom[vmFilmstrip]),
      'Missing per-mode section should fall back to default');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestActiveZoomDelegatesToViewMode;
var
  S: TPluginSettings;
begin
  { ZoomMode property should read/write through current ViewMode }
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.ViewMode := vmScroll;
    S.ZoomMode := zmActual;
    Assert.AreEqual(Ord(zmActual), Ord(S.ModeZoom[vmScroll]),
      'Writing ZoomMode should update ModeZoom for current ViewMode');

    S.ViewMode := vmFilmstrip;
    S.ZoomMode := zmFitIfLarger;
    { Scroll zoom should be unchanged }
    Assert.AreEqual(Ord(zmActual), Ord(S.ModeZoom[vmScroll]),
      'Changing mode and zoom should not affect other modes');
    Assert.AreEqual(Ord(zmFitIfLarger), Ord(S.ModeZoom[vmFilmstrip]),
      'Filmstrip should have its own zoom');

    { Reading ZoomMode returns zoom for current ViewMode }
    S.ViewMode := vmScroll;
    Assert.AreEqual(Ord(zmActual), Ord(S.ZoomMode),
      'Reading ZoomMode should return ModeZoom for current ViewMode');
  finally
    S.Free;
  end;
end;



procedure TTestPluginSettings.TestSaveOverwritesPreviousValues;
var
  S: TPluginSettings;
begin
  { Save twice with different values; second values should persist }
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.FramesCount := 10;
    S.ViewMode := vmGrid;
    S.Save;

    S.FramesCount := 20;
    S.ViewMode := vmFilmstrip;
    S.Save;
  finally
    S.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(20, S.FramesCount, 'Second save should overwrite first');
    Assert.AreEqual(Ord(vmFilmstrip), Ord(S.ViewMode),
      'Second save should overwrite first');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestMaxWorkersBoundaryValues;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    { Zero = one per frame mode }
    S.MaxWorkers := 0;
    S.Save;
    S.Load;
    Assert.AreEqual(0, S.MaxWorkers, 'Zero (one per frame) should round-trip');

    { Minimum fixed boundary }
    S.MaxWorkers := 1;
    S.Save;
    S.Load;
    Assert.AreEqual(1, S.MaxWorkers, 'Min boundary (1) should round-trip');

    { Maximum boundary }
    S.MaxWorkers := 16;
    S.Save;
    S.Load;
    Assert.AreEqual(16, S.MaxWorkers, 'Max boundary (16) should round-trip');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestPartialIniPreservesDefaults;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { INI with only [view] section; other sections should get defaults }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('view', 'Mode', 'filmstrip');
    Ini.WriteBool('view', 'ShowTimecode', False);
    { No [ffmpeg], [extraction], [save], [cache] sections }
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    { Explicit values should load }
    Assert.AreEqual(Ord(vmFilmstrip), Ord(S.ViewMode), 'ViewMode should load');
    Assert.IsFalse(S.ShowTimecode, 'ShowTimecode should load');
    { Missing sections should use defaults }
    Assert.AreEqual(Ord(DEF_FFMPEG_MODE), Ord(S.FFmpegMode), 'Missing ffmpeg section');
    Assert.AreEqual(DEF_FRAMES_COUNT, S.FramesCount, 'Missing extraction section');
    Assert.AreEqual(Ord(DEF_SAVE_FORMAT), Ord(S.SaveFormat), 'Missing save section');
    Assert.AreEqual(DEF_CACHE_ENABLED, S.CacheEnabled, 'Missing cache section');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestDefaultCacheFolderNonEmpty;
var
  Path: string;
begin
  Path := DefaultCacheFolder;
  Assert.IsNotEmpty(Path, 'DefaultCacheFolder should return a non-empty path');
  Assert.IsTrue(Path.EndsWith('cache'), 'DefaultCacheFolder should end with "cache"');
  Assert.IsTrue(Path.Contains('Glimpse'), 'DefaultCacheFolder should contain "Glimpse"');
end;

procedure TTestPluginSettings.TestEffectiveCacheFolderReturnsConfigured;
begin
  Assert.AreEqual('C:\MyCache', EffectiveCacheFolder('C:\MyCache'), 'Should return configured path when non-empty');
end;

procedure TTestPluginSettings.TestEffectiveCacheFolderReturnsDefaultWhenEmpty;
begin
  Assert.AreEqual(DefaultCacheFolder, EffectiveCacheFolder(''), 'Should return DefaultCacheFolder when empty');
end;

procedure TTestPluginSettings.TestTimecodeBackColorAlphaRoundTrip;
var
  S1, S2: TPluginSettings;

  procedure CheckRoundTrip(AColor: TColor; AAlpha: Byte; const ALabel: string);
  begin
    S1.TimecodeBackColor := AColor;
    S1.TimecodeBackAlpha := AAlpha;
    S1.Save;
    S2.Load;
    Assert.AreEqual(Integer(AColor), Integer(S2.TimecodeBackColor), ALabel + ' color');
    Assert.AreEqual(Integer(AAlpha), Integer(S2.TimecodeBackAlpha), ALabel + ' alpha');
  end;

begin
  S1 := TPluginSettings.Create(FTempIniPath);
  S2 := TPluginSettings.Create(FTempIniPath);
  try
    CheckRoundTrip(TColor($002D2D2D), 180, 'Default-like');
    CheckRoundTrip(TColor($00000000), 0, 'Black fully transparent');
    CheckRoundTrip(TColor($00FFFFFF), 255, 'White fully opaque');
    CheckRoundTrip(TColor($00FF0000), 128, 'Red half-transparent');
    CheckRoundTrip(TColor($000000FF), 1, 'Blue near-transparent');
  finally
    S2.Free;
    S1.Free;
  end;
end;

procedure TTestPluginSettings.TestTimecodeBackColorAlphaMalformedFallback;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { Write various malformed RGBA values; all should fall back to defaults }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('view', 'TimecodeBackground', 'not_a_color');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Integer(DEF_TC_BACK_COLOR), Integer(S.TimecodeBackColor),
      'Malformed string should fall back to default color');
    Assert.AreEqual(Integer(DEF_TC_BACK_ALPHA), Integer(S.TimecodeBackAlpha),
      'Malformed string should fall back to default alpha');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimecodeBackColorAlphaEdgeCases;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { 7-char hex (no alpha component) should fall back to defaults }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('view', 'TimecodeBackground', '#FF8040');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Integer(DEF_TC_BACK_COLOR), Integer(S.TimecodeBackColor),
      '7-char hex (missing alpha) should fall back to default color');
    Assert.AreEqual(Integer(DEF_TC_BACK_ALPHA), Integer(S.TimecodeBackAlpha),
      '7-char hex (missing alpha) should fall back to default alpha');
  finally
    S.Free;
  end;

  { Empty string should fall back to defaults }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('view', 'TimecodeBackground', '');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Integer(DEF_TC_BACK_COLOR), Integer(S.TimecodeBackColor),
      'Empty string should fall back to default color');
    Assert.AreEqual(Integer(DEF_TC_BACK_ALPHA), Integer(S.TimecodeBackAlpha),
      'Empty string should fall back to default alpha');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampTextAlphaDefault;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    Assert.AreEqual(Integer(DEF_TIMESTAMP_TEXT_ALPHA), Integer(S.TimestampTextAlpha),
      'Fresh settings should carry the text alpha default');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampTextAlphaRoundTrip;
var
  S1, S2: TPluginSettings;
begin
  S1 := TPluginSettings.Create(FTempIniPath);
  try
    S1.TimestampTextAlpha := 64;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.AreEqual(64, Integer(S2.TimestampTextAlpha),
      'Text alpha should survive save/load round trip');
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampTextAlphaClampedHigh;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('view', 'TimestampTextAlpha', 999);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Integer(MAX_TIMESTAMP_TEXT_ALPHA), Integer(S.TimestampTextAlpha),
      'Out-of-range high value should clamp to MAX_TIMESTAMP_TEXT_ALPHA');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampTextAlphaClampedLow;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('view', 'TimestampTextAlpha', -10);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(Integer(MIN_TIMESTAMP_TEXT_ALPHA), Integer(S.TimestampTextAlpha),
      'Negative value should clamp to MIN_TIMESTAMP_TEXT_ALPHA');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampFontDefaults;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    Assert.AreEqual(DEF_TIMESTAMP_FONT, S.TimestampFontName);
    Assert.AreEqual(DEF_TIMESTAMP_FONT_SIZE, S.TimestampFontSize);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampFontRoundTrip;
var
  S1, S2: TPluginSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'font.ini');
  S1 := TPluginSettings.Create(IniPath);
  try
    S1.TimestampFontName := 'Consolas';
    S1.TimestampFontSize := 12;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual('Consolas', S2.TimestampFontName);
    Assert.AreEqual(12, S2.TimestampFontSize);
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampFontSizeClamped;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'fontclamp.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'TimestampFontSize', 2);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_TIMESTAMP_FONT_SIZE, S.TimestampFontSize,
      'Font size below minimum should be clamped');
  finally
    S.Free;
  end;

  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'TimestampFontSize', 200);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_TIMESTAMP_FONT_SIZE, S.TimestampFontSize,
      'Font size above maximum should be clamped');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampFontEmptyFallback;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'fontempty.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('view', 'TimestampFont', '   ');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(DEF_TIMESTAMP_FONT, S.TimestampFontName,
      'Empty/whitespace font name should fall back to default');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestCellGapDefault;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    Assert.AreEqual(DEF_CELL_GAP, S.CellGap);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestCellGapRoundTrip;
var
  S1, S2: TPluginSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'cellgap.ini');
  S1 := TPluginSettings.Create(IniPath);
  try
    S1.CellGap := 12;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(12, S2.CellGap);
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestCellGapClampedHigh;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'cellgap_high.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'CellGap', 999);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_CELL_GAP, S.CellGap,
      'CellGap above maximum should be clamped');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestCellGapClampedLow;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'cellgap_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'CellGap', -5);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_CELL_GAP, S.CellGap,
      'Negative CellGap should be clamped to 0');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestCombinedBorderDefault;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    Assert.AreEqual(DEF_COMBINED_BORDER, S.CombinedBorder);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestCombinedBorderRoundTrip;
var
  S1, S2: TPluginSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'border.ini');
  S1 := TPluginSettings.Create(IniPath);
  try
    S1.CombinedBorder := 42;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(42, S2.CombinedBorder);
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestCombinedBorderClampedHigh;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'border_high.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'CombinedBorder', 9999);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_COMBINED_BORDER, S.CombinedBorder,
      'CombinedBorder above maximum should be clamped');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestCombinedBorderClampedLow;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'border_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'CombinedBorder', -100);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_COMBINED_BORDER, S.CombinedBorder,
      'Negative CombinedBorder should be clamped to 0');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampCornerDefault;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    Assert.AreEqual(Ord(DEF_TIMESTAMP_CORNER), Ord(S.TimestampCorner));
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTimestampCornerRoundTripAllValues;
var
  S1, S2: TPluginSettings;
  IniPath: string;
  Corner: TTimestampCorner;
begin
  {Every enum value must survive an INI round-trip; covers all four string
   codes written by TimestampCornerToStr and parsed by StrToTimestampCorner}
  for Corner := Low(TTimestampCorner) to High(TTimestampCorner) do
  begin
    IniPath := TPath.Combine(FTempDir, Format('corner_%d.ini', [Ord(Corner)]));
    S1 := TPluginSettings.Create(IniPath);
    try
      S1.TimestampCorner := Corner;
      S1.Save;
    finally
      S1.Free;
    end;

    S2 := TPluginSettings.Create(IniPath);
    try
      S2.Load;
      Assert.AreEqual(Ord(Corner), Ord(S2.TimestampCorner),
        Format('Corner %d did not round-trip', [Ord(Corner)]));
    finally
      S2.Free;
    end;
  end;
end;

procedure TTestPluginSettings.TestTimestampCornerUnknownFallsBackToDefault;
var
  S: TPluginSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  {Unknown string in INI must fall back to the default rather than throw
   or produce an undefined enum value}
  IniPath := TPath.Combine(FTempDir, 'corner_bad.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('view', 'TimestampCorner', 'nonsense');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(Ord(DEF_TIMESTAMP_CORNER), Ord(S.TimestampCorner),
      'Unknown corner string should fall back to default');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestShowBannerDefault;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(TPath.Combine(FTempDir, 'nonexistent.ini'));
  try
    Assert.IsFalse(S.ShowBanner, 'ShowBanner should default to False');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestShowBannerRoundTrip;
var
  S1, S2: TPluginSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'banner.ini');
  S1 := TPluginSettings.Create(IniPath);
  try
    S1.ShowBanner := True;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(IniPath);
  try
    S2.Load;
    Assert.IsTrue(S2.ShowBanner, 'ShowBanner should persist as True');
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestCacheMaxSizeBoundaries;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { At minimum boundary (10 MB) }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('cache', 'MaxSizeMB', 10);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(10, S.CacheMaxSizeMB, 'Min boundary 10 preserved');
  finally
    S.Free;
  end;

  { At maximum boundary (10000 MB) }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('cache', 'MaxSizeMB', 10000);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(10000, S.CacheMaxSizeMB, 'Max boundary 10000 preserved');
  finally
    S.Free;
  end;

  { Below minimum (9) clamped to 10 }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('cache', 'MaxSizeMB', 9);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(10, S.CacheMaxSizeMB, 'Below min clamped to 10');
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestTryParseHexRGBValid;
var
  C: TColor;
begin
  { Standard 6-digit hex with # prefix }
  Assert.IsTrue(TryParseHexRGB('#FF0000', C), '#FF0000 should parse');
  Assert.AreEqual(Integer($000000FF), Integer(C), 'Red channel');

  Assert.IsTrue(TryParseHexRGB('#00FF00', C), '#00FF00 should parse');
  Assert.AreEqual(Integer($0000FF00), Integer(C), 'Green channel');

  Assert.IsTrue(TryParseHexRGB('#0000FF', C), '#0000FF should parse');
  Assert.AreEqual(Integer($00FF0000), Integer(C), 'Blue channel');

  Assert.IsTrue(TryParseHexRGB('#000000', C), '#000000 should parse');
  Assert.AreEqual(Integer($00000000), Integer(C), 'Black');

  Assert.IsTrue(TryParseHexRGB('#FFFFFF', C), '#FFFFFF should parse');
  Assert.AreEqual(Integer($00FFFFFF), Integer(C), 'White');
end;

procedure TTestPluginSettings.TestTryParseHexRGBInvalid;
var
  C: TColor;
begin
  { Empty string }
  Assert.IsFalse(TryParseHexRGB('', C), 'Empty string');
  { Too short }
  Assert.IsFalse(TryParseHexRGB('#FF00', C), 'Too short');
  { Non-hex characters }
  Assert.IsFalse(TryParseHexRGB('#GGHHII', C), 'Non-hex chars');
  { Single character }
  Assert.IsFalse(TryParseHexRGB('#', C), 'Just hash');
end;

procedure TTestPluginSettings.TestEffectiveCacheFolderExpandsEnvVars;
var
  Result: string;
begin
  Result := EffectiveCacheFolder('%TEMP%\GlimpseTest');
  Assert.IsFalse(Result.Contains('%TEMP%'),
    'EffectiveCacheFolder must expand environment variables');
  Assert.IsTrue(Result.EndsWith('\GlimpseTest'),
    'Folder name must be preserved after expansion');
end;

procedure TTestPluginSettings.TestQVSettingsDefaultsAllTrue;
var
  S: TPluginSettings;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    { Defaults without loading: all QV overrides should be active }
    Assert.IsTrue(S.QVDisableNavigation);
    Assert.IsTrue(S.QVHideToolbar);
    Assert.IsTrue(S.QVHideStatusBar);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestQVSettingsRoundTrip;
var
  S1, S2: TPluginSettings;
begin
  S1 := TPluginSettings.Create(FTempIniPath);
  try
    S1.QVDisableNavigation := False;
    S1.QVHideToolbar := False;
    S1.QVHideStatusBar := True;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.IsFalse(S2.QVDisableNavigation);
    Assert.IsFalse(S2.QVHideToolbar);
    Assert.IsTrue(S2.QVHideStatusBar);
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestQVSettingsMissingInIniUsesDefaults;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { Write an INI with no [quickview] section }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 10);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(DEF_QV_DISABLE_NAV, S.QVDisableNavigation);
    Assert.AreEqual(DEF_QV_HIDE_TOOLBAR, S.QVHideToolbar);
    Assert.AreEqual(DEF_QV_HIDE_STATUSBAR, S.QVHideStatusBar);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailSettingsDefaults;
var
  S: TPluginSettings;
begin
  { Fresh instance must match the DEF_* constants — no Load needed }
  S := TPluginSettings.Create(FTempIniPath);
  try
    Assert.AreEqual(DEF_THUMBNAILS_ENABLED, S.ThumbnailsEnabled);
    Assert.IsTrue(S.ThumbnailMode = DEF_THUMBNAIL_MODE,
      'ThumbnailMode default mismatch');
    Assert.AreEqual(DEF_THUMBNAIL_POSITION, S.ThumbnailPosition);
    Assert.AreEqual(DEF_THUMBNAIL_GRID_FRAMES, S.ThumbnailGridFrames);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailSettingsRoundTrip;
var
  S1, S2: TPluginSettings;
begin
  { Mutate every field, save, reload, verify each value survived }
  S1 := TPluginSettings.Create(FTempIniPath);
  try
    S1.ThumbnailsEnabled := False;
    S1.ThumbnailMode := tnmGrid;
    S1.ThumbnailPosition := 25;
    S1.ThumbnailGridFrames := 9;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.IsFalse(S2.ThumbnailsEnabled);
    Assert.IsTrue(S2.ThumbnailMode = tnmGrid, 'Mode did not round-trip');
    Assert.AreEqual(25, S2.ThumbnailPosition);
    Assert.AreEqual(9, S2.ThumbnailGridFrames);
  finally
    S2.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailSettingsMissingInIniUsesDefaults;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { An INI without a [thumbnails] section must yield default values for
    every thumbnail field — no exceptions, no zeroed numerics. }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 10);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(DEF_THUMBNAILS_ENABLED, S.ThumbnailsEnabled);
    Assert.IsTrue(S.ThumbnailMode = DEF_THUMBNAIL_MODE,
      'Default ThumbnailMode mismatch on missing section');
    Assert.AreEqual(DEF_THUMBNAIL_POSITION, S.ThumbnailPosition);
    Assert.AreEqual(DEF_THUMBNAIL_GRID_FRAMES, S.ThumbnailGridFrames);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailPositionClampedHigh;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { A hand-edited INI could supply nonsense like 9999. Load must clamp,
    not propagate the bad value into the renderer. }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('thumbnails', 'Position', 9999);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_THUMBNAIL_POSITION, S.ThumbnailPosition);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailPositionClampedLow;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('thumbnails', 'Position', -50);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_THUMBNAIL_POSITION, S.ThumbnailPosition);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailGridFramesClampedHigh;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { Ridiculous frame counts would create absurd extraction work; clamp
    to MAX so we can never spend minutes on a single thumbnail. }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('thumbnails', 'GridFrames', 9999);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_THUMBNAIL_GRID_FRAMES, S.ThumbnailGridFrames);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailGridFramesClampedLow;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { GridFrames < MIN would produce a degenerate grid (1 cell or empty).
    Clamp upward to keep grid mode meaningful. }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteInteger('thumbnails', 'GridFrames', 0);
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_THUMBNAIL_GRID_FRAMES, S.ThumbnailGridFrames);
  finally
    S.Free;
  end;
end;

procedure TTestPluginSettings.TestThumbnailModeUnknownStringFallsBackToSingle;
var
  Ini: TIniFile;
  S: TPluginSettings;
begin
  { An unknown / corrupted Mode value must fall back to single (the
    safest mode), not raise. Mirrors the StrToThumbnailMode contract. }
  Ini := TIniFile.Create(FTempIniPath);
  try
    Ini.WriteString('thumbnails', 'Mode', 'banana');
  finally
    Ini.Free;
  end;

  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Assert.IsTrue(S.ThumbnailMode = tnmSingle,
      'Unknown Mode string should fall back to tnmSingle');
  finally
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginSettings);

end.
