unit TestWcxSettings;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxSettings = class
  private
    FTempDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestDefaultValues;
    [Test] procedure TestLoadNonExistentFile;
    [Test] procedure TestSaveAndLoad;
    [Test] procedure TestFramesCountClamped;
    [Test] procedure TestSkipEdgesClamped;
    [Test] procedure TestJpegQualityClamped;
    [Test] procedure TestPngCompressionClamped;
    [Test] procedure TestSaveFormatJPEG;
    [Test] procedure TestSaveFormatPNG;
    [Test] procedure TestMaxWorkersClamped;
    [Test] procedure TestMaxThreadsClamped;
    [Test] procedure TestDefaultOutputMode;
    [Test] procedure TestOutputModeCombinedRoundTrip;
    [Test] procedure TestCombinedColumnsDefault;
    [Test] procedure TestCombinedColumnsClamped;
    [Test] procedure TestShowTimestampDefault;
    [Test] procedure TestShowTimestampRoundTrip;
    [Test] procedure TestBackgroundDefault;
    [Test] procedure TestBackgroundRoundTrip;
    [Test] procedure TestCellGapDefault;
    [Test] procedure TestCellGapClamped;
    [Test] procedure TestShowFileSizesDefault;
    [Test] procedure TestShowFileSizesRoundTrip;
    { Timestamp font }
    [Test] procedure TestTimestampFontDefaults;
    [Test] procedure TestTimestampFontRoundTrip;
    [Test] procedure TestTimestampFontSizeClamped;
    [Test] procedure TestTimestampFontEmptyFallback;
    { Banner }
    [Test] procedure TestShowBannerDefault;
    [Test] procedure TestShowBannerRoundTrip;
    [Test] procedure TestBannerStyleDefaults;
    [Test] procedure TestBannerStyleRoundTrip;
    [Test] procedure TestBannerPositionUnknownFallsBackToDefault;
    [Test] procedure TestBannerFontSizeClampedToRange;
    { Lower bound clamping }
    [Test] procedure TestFramesCountClampedLower;
    [Test] procedure TestSkipEdgesClampedLower;
    [Test] procedure TestPngCompressionClampedLower;
    [Test] procedure TestCombinedColumnsClampedLower;
    [Test] procedure TestCellGapClampedLower;
    { Special valid values for workers/threads }
    [Test] procedure TestMaxWorkersZeroRoundTrip;
    [Test] procedure TestMaxThreadsMinusOneRoundTrip;
    [Test] procedure TestMaxThreadsZeroRoundTrip;
    { FFmpeg path }
    [Test] procedure TestFFmpegExePathDefault;
    [Test] procedure TestFFmpegExePathRoundTrip;
    { Save edge cases }
    [Test] procedure TestSaveEmptyPathNoError;
    { Unknown INI values fall back to safe defaults }
    [Test] procedure TestUnknownOutputModeDefaultsToSeparate;
    [Test] procedure TestUnknownFormatDefaultsToPNG;
    { Partial INI with missing sections }
    [Test] procedure TestPartialIniUsesDefaults;
    { UseBmpPipe / HwAccel / UseKeyframes round-trip }
    [Test] procedure TestUseBmpPipeRoundTrip;
    [Test] procedure TestHwAccelRoundTrip;
    [Test] procedure TestUseKeyframesRoundTrip;
    { Output size limits }
    [Test] procedure TestOutputSizeLimitsDefault;
    [Test] procedure TestFrameMaxSideRoundTrip;
    [Test] procedure TestCombinedMaxSideRoundTrip;
    [Test] procedure TestFrameMaxSideClampedUpper;
    [Test] procedure TestCombinedMaxSideClampedLower;
    { Appearance parity with WLX }
    [Test] procedure TestAppearanceDefaults;
    [Test] procedure TestCombinedBorderRoundTrip;
    [Test] procedure TestCombinedBorderClampedUpper;
    [Test] procedure TestCombinedBorderClampedLower;
    [Test] procedure TestTimestampCornerRoundTripAllCorners;
    [Test] procedure TestUnknownTimestampCornerDefaults;
    [Test] procedure TestTimecodeBackColorAlphaRoundTrip;
    [Test] procedure TestTimestampTextColorRoundTrip;
    [Test] procedure TestTimestampTextAlphaRoundTrip;
    [Test] procedure TestTimestampTextAlphaClampedUpper;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.IniFiles, System.UITypes,
  uWcxSettings, uBitmapSaver, uDefaults, uTypes;

{ TTestWcxSettings }

procedure TTestWcxSettings.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'glimpse_wcx_test_' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWcxSettings.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestWcxSettings.TestDefaultValues;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual(DEF_FRAMES_COUNT, S.FramesCount);
    Assert.AreEqual(DEF_SKIP_EDGES, S.SkipEdgesPercent);
    Assert.AreEqual(DEF_MAX_WORKERS, S.MaxWorkers);
    Assert.AreEqual(DEF_MAX_THREADS, S.MaxThreads);
    Assert.AreEqual(True, S.UseBmpPipe);
    Assert.IsTrue(S.SaveFormat = sfPNG);
    Assert.AreEqual(DEF_JPEG_QUALITY, S.JpegQuality);
    Assert.AreEqual(DEF_PNG_COMPRESSION, S.PngCompression);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestLoadNonExistentFile;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'missing.ini'));
  try
    S.Load;
    { Defaults remain intact when file does not exist }
    Assert.AreEqual(DEF_FRAMES_COUNT, S.FramesCount);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestSaveAndLoad;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'roundtrip.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.FramesCount := 12;
    S1.SkipEdgesPercent := 5;
    S1.MaxWorkers := 4;
    S1.MaxThreads := 8;
    S1.UseBmpPipe := False;
    S1.SaveFormat := sfJPEG;
    S1.JpegQuality := 75;
    S1.PngCompression := 3;
    S1.FFmpegExePath := 'C:\tools\ffmpeg.exe';
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(12, S2.FramesCount);
    Assert.AreEqual(5, S2.SkipEdgesPercent);
    Assert.AreEqual(4, S2.MaxWorkers);
    Assert.AreEqual(8, S2.MaxThreads);
    Assert.AreEqual(False, S2.UseBmpPipe);
    Assert.IsTrue(S2.SaveFormat = sfJPEG);
    Assert.AreEqual(75, S2.JpegQuality);
    Assert.AreEqual(3, S2.PngCompression);
    Assert.AreEqual('C:\tools\ffmpeg.exe', S2.FFmpegExePath);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestFramesCountClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'clamp.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 999);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(99, S.FramesCount);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestSkipEdgesClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'clamp2.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'SkipEdges', 80);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(49, S.SkipEdgesPercent);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestJpegQualityClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'jpeg.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('output', 'JpegQuality', 0);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(1, S.JpegQuality);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestPngCompressionClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'png.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('output', 'PngCompression', 15);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(9, S.PngCompression);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestSaveFormatJPEG;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'fmt.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('output', 'Format', 'JPEG');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.IsTrue(S.SaveFormat = sfJPEG);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestSaveFormatPNG;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'fmt2.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('output', 'Format', 'PNG');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.IsTrue(S.SaveFormat = sfPNG);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestMaxWorkersClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'workers.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'MaxWorkers', 50);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(16, S.MaxWorkers);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestMaxThreadsClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'threads.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'MaxThreads', 100);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(64, S.MaxThreads);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestDefaultOutputMode;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.IsTrue(S.OutputMode = womSeparate);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestOutputModeCombinedRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'mode.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.OutputMode := womCombined;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.IsTrue(S2.OutputMode = womCombined);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedColumnsDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual(WCX_DEF_COMBINED_COLS, S.CombinedColumns);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedColumnsClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'cols.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'Columns', 50);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(20, S.CombinedColumns);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestShowTimestampDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual(WCX_DEF_SHOW_TIMESTAMP, S.ShowTimestamp);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestShowTimestampRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'ts.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.ShowTimestamp := False;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(False, S2.ShowTimestamp);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestBackgroundDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual(Integer(WCX_DEF_BACKGROUND), Integer(S.Background));
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestBackgroundRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'bg.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.Background := TColor($00FF8040);
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(Integer(TColor($00FF8040)), Integer(S2.Background));
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestCellGapDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual(WCX_DEF_CELL_GAP, S.CellGap);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCellGapClamped;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'gap.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'CellGap', 99);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(20, S.CellGap);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestShowFileSizesDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual(False, S.ShowFileSizes);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestShowFileSizesRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'sizes.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.ShowFileSizes := True;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(True, S2.ShowFileSizes);
  finally
    S2.Free;
  end;
end;

{ Timestamp font }

procedure TTestWcxSettings.TestTimestampFontDefaults;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'fontdef.ini'));
  try
    Assert.AreEqual(WCX_DEF_TIMESTAMP_FONT, S.TimestampFontName);
    Assert.AreEqual(WCX_DEF_TIMESTAMP_FONT_SIZE, S.TimestampFontSize);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampFontRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'fontrt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.TimestampFontName := 'Arial';
    S1.TimestampFontSize := 14;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual('Arial', S2.TimestampFontName);
    Assert.AreEqual(14, S2.TimestampFontSize);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampFontSizeClamped;
var
  S: TWcxSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'fontclamp.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'TimestampFontSize', 2);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_TIMESTAMP_FONT_SIZE, S.TimestampFontSize);
  finally
    S.Free;
  end;

  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'TimestampFontSize', 200);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_TIMESTAMP_FONT_SIZE, S.TimestampFontSize);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampFontEmptyFallback;
var
  S: TWcxSettings;
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'fontempty.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('combined', 'TimestampFont', '   ');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(WCX_DEF_TIMESTAMP_FONT, S.TimestampFontName);
  finally
    S.Free;
  end;
end;

{ Banner }

procedure TTestWcxSettings.TestShowBannerDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create('');
  try
    Assert.IsFalse(S.ShowBanner, 'ShowBanner should default to False');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestShowBannerRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'banner.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.ShowBanner := True;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.IsTrue(S2.ShowBanner, 'ShowBanner should persist as True');
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestBannerStyleDefaults;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create('');
  try
    Assert.AreEqual(Integer(DEF_BANNER_BACKGROUND), Integer(S.BannerBackground),
      'BannerBackground default');
    Assert.AreEqual(Integer(DEF_BANNER_TEXT_COLOR), Integer(S.BannerTextColor),
      'BannerTextColor default');
    Assert.AreEqual(DEF_BANNER_FONT_NAME, S.BannerFontName,
      'BannerFontName default');
    Assert.AreEqual(DEF_BANNER_FONT_SIZE, S.BannerFontSize,
      'BannerFontSize default');
    Assert.AreEqual(DEF_BANNER_FONT_AUTO_SIZE, S.BannerFontAutoSize,
      'BannerFontAutoSize default');
    Assert.AreEqual(Ord(DEF_BANNER_POSITION), Ord(S.BannerPosition),
      'BannerPosition default');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestBannerStyleRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'wcx_banner_style.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.BannerBackground := TColor($00112233);
    S1.BannerTextColor := TColor($00AABBCC);
    S1.BannerFontName := 'Verdana';
    S1.BannerFontSize := 14;
    S1.BannerFontAutoSize := False;
    S1.BannerPosition := bpBottom;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(Integer(TColor($00112233)), Integer(S2.BannerBackground),
      'BannerBackground round-trip');
    Assert.AreEqual(Integer(TColor($00AABBCC)), Integer(S2.BannerTextColor),
      'BannerTextColor round-trip');
    Assert.AreEqual('Verdana', S2.BannerFontName, 'BannerFontName round-trip');
    Assert.AreEqual(14, S2.BannerFontSize, 'BannerFontSize round-trip');
    Assert.IsFalse(S2.BannerFontAutoSize, 'BannerFontAutoSize round-trip');
    Assert.AreEqual(Ord(bpBottom), Ord(S2.BannerPosition), 'BannerPosition round-trip');
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestBannerPositionUnknownFallsBackToDefault;
var
  Ini: TIniFile;
  S: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'wcx_banner_pos_unknown.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('combined', 'BannerPosition', 'nonsense');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(Ord(DEF_BANNER_POSITION), Ord(S.BannerPosition),
      'Unknown banner position should fall back to default');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestBannerFontSizeClampedToRange;
var
  Ini: TIniFile;
  S: TWcxSettings;
  IniPath: string;
begin
  { Values outside [MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE] must clamp. }
  IniPath := TPath.Combine(FTempDir, 'wcx_banner_size_clamp.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'BannerFontSize', 999);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_BANNER_FONT_SIZE, S.BannerFontSize,
      'Oversized font size should clamp to MAX_BANNER_FONT_SIZE');
  finally
    S.Free;
  end;

  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'BannerFontSize', -5);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_BANNER_FONT_SIZE, S.BannerFontSize,
      'Negative font size should clamp to MIN_BANNER_FONT_SIZE');
  finally
    S.Free;
  end;
end;

{ Lower bound clamping: values below minimum are clamped up }

procedure TTestWcxSettings.TestFramesCountClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'fc_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 0);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(1, S.FramesCount, 'FramesCount=0 must clamp to 1');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestSkipEdgesClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'se_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'SkipEdges', -5);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(0, S.SkipEdgesPercent, 'Negative SkipEdges must clamp to 0');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestPngCompressionClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'png_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('output', 'PngCompression', -1);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(0, S.PngCompression, 'Negative PngCompression must clamp to 0');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedColumnsClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'cols_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'Columns', -3);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(0, S.CombinedColumns, 'Negative Columns must clamp to 0');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCellGapClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'gap_low.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'CellGap', -1);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(0, S.CellGap, 'Negative CellGap must clamp to 0');
  finally
    S.Free;
  end;
end;

{ Special valid boundary values for workers/threads }

procedure TTestWcxSettings.TestMaxWorkersZeroRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  { MaxWorkers=0 means "one per frame" (auto), must survive save/load }
  IniPath := TPath.Combine(FTempDir, 'w0.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.MaxWorkers := 0;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(0, S2.MaxWorkers);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestMaxThreadsMinusOneRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  { MaxThreads=-1 means "no limit", must survive save/load }
  IniPath := TPath.Combine(FTempDir, 'tm1.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.MaxThreads := -1;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(-1, S2.MaxThreads);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestMaxThreadsZeroRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  { MaxThreads=0 means "auto (CPU count)", must survive save/load }
  IniPath := TPath.Combine(FTempDir, 't0.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.MaxThreads := 0;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(0, S2.MaxThreads);
  finally
    S2.Free;
  end;
end;

{ FFmpeg path }

procedure TTestWcxSettings.TestFFmpegExePathDefault;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'test.ini'));
  try
    Assert.AreEqual('', S.FFmpegExePath);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestFFmpegExePathRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'ffpath.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.FFmpegExePath := '%ProgramFiles%\ffmpeg\bin\ffmpeg.exe';
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual('%ProgramFiles%\ffmpeg\bin\ffmpeg.exe', S2.FFmpegExePath);
  finally
    S2.Free;
  end;
end;

{ Save edge cases }

procedure TTestWcxSettings.TestSaveEmptyPathNoError;
var
  S: TWcxSettings;
begin
  { TWcxSettings.Save exits silently when IniPath is empty }
  S := TWcxSettings.Create('');
  try
    S.FramesCount := 10;
    S.Save; { Must not raise }
  finally
    S.Free;
  end;
end;

{ Unknown INI values }

procedure TTestWcxSettings.TestUnknownOutputModeDefaultsToSeparate;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'mode_unk.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('output', 'Mode', 'nonsense_value');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.IsTrue(S.OutputMode = womSeparate,
      'Unrecognized mode string must default to womSeparate');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestUnknownFormatDefaultsToPNG;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'fmt_unk.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('output', 'Format', 'BMP');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.IsTrue(S.SaveFormat = sfPNG,
      'Unrecognized format string must default to sfPNG');
  finally
    S.Free;
  end;
end;

{ Partial INI: only one section present, all others use defaults }

procedure TTestWcxSettings.TestPartialIniUsesDefaults;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'partial.ini');
  Ini := TIniFile.Create(IniPath);
  try
    { Write only one section }
    Ini.WriteInteger('extraction', 'FramesCount', 8);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    { Explicit value loaded }
    Assert.AreEqual(8, S.FramesCount);
    { All other settings fall back to defaults }
    Assert.AreEqual(DEF_SKIP_EDGES, S.SkipEdgesPercent);
    Assert.AreEqual(DEF_JPEG_QUALITY, S.JpegQuality);
    Assert.AreEqual(DEF_PNG_COMPRESSION, S.PngCompression);
    Assert.AreEqual(WCX_DEF_COMBINED_COLS, S.CombinedColumns);
    Assert.AreEqual(WCX_DEF_SHOW_TIMESTAMP, S.ShowTimestamp);
    Assert.AreEqual(WCX_DEF_CELL_GAP, S.CellGap);
    Assert.AreEqual(WCX_DEF_SHOW_FILE_SIZES, S.ShowFileSizes);
    Assert.IsTrue(S.SaveFormat = DEF_SAVE_FORMAT);
    Assert.IsTrue(S.OutputMode = WCX_DEF_OUTPUT_MODE);
  finally
    S.Free;
  end;
end;

{ UseBmpPipe }

procedure TTestWcxSettings.TestUseBmpPipeRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'bmp.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.UseBmpPipe := False;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(False, S2.UseBmpPipe);
  finally
    S2.Free;
  end;
end;

{ HwAccel / UseKeyframes — gap-fill ahead of the settings group-record
  refactor so Load/Save behaviour is pinned before the fields move
  behind a record-delegation property. }

procedure TTestWcxSettings.TestHwAccelRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'hwaccel.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.HwAccel := not DEF_HW_ACCEL;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(not DEF_HW_ACCEL, S2.HwAccel,
      'Flipped HwAccel must round-trip through INI');
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestUseKeyframesRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'keyframes.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.UseKeyframes := not DEF_USE_KEYFRAMES;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(not DEF_USE_KEYFRAMES, S2.UseKeyframes,
      'Flipped UseKeyframes must round-trip through INI');
  finally
    S2.Free;
  end;
end;

{ Output size limits }

procedure TTestWcxSettings.TestOutputSizeLimitsDefault;
var
  S: TWcxSettings;
begin
  { Both size limits default to 0 (no constraint) }
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'sz_def.ini'));
  try
    Assert.AreEqual(0, S.FrameMaxSide);
    Assert.AreEqual(0, S.CombinedMaxSide);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestFrameMaxSideRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'fms_rt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.FrameMaxSide := 1280;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(1280, S2.FrameMaxSide);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedMaxSideRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'cms_rt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.CombinedMaxSide := 1920;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(1920, S2.CombinedMaxSide);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestFrameMaxSideClampedUpper;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  { Values larger than 8K must be clamped down }
  IniPath := TPath.Combine(FTempDir, 'fms_hi.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('output', 'FrameMaxSide', 999999);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(WCX_MAX_OUTPUT_SIDE, S.FrameMaxSide);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedMaxSideClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  { Negative values must clamp up to 0 }
  IniPath := TPath.Combine(FTempDir, 'cms_lo.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'CombinedMaxSide', -1);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(0, S.CombinedMaxSide);
  finally
    S.Free;
  end;
end;

{ Appearance parity with WLX: WCX gained Border, TimestampCorner, timecode bg
  color+alpha, and timestamp text color+alpha. Defaults must match the shared
  WLX defaults so both plugins render the combined image identically when run
  with fresh configs. }

procedure TTestWcxSettings.TestAppearanceDefaults;
var
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(TPath.Combine(FTempDir, 'appdef.ini'));
  try
    Assert.AreEqual(DEF_COMBINED_BORDER, S.CombinedBorder);
    Assert.IsTrue(S.TimestampCorner = DEF_TIMESTAMP_CORNER);
    Assert.AreEqual(Integer(DEF_TC_BACK_COLOR), Integer(S.TimecodeBackColor));
    Assert.AreEqual(Integer(DEF_TC_BACK_ALPHA), Integer(S.TimecodeBackAlpha));
    Assert.AreEqual(Integer(DEF_TIMESTAMP_TEXT_COLOR), Integer(S.TimestampTextColor));
    Assert.AreEqual(Integer(DEF_TIMESTAMP_TEXT_ALPHA), Integer(S.TimestampTextAlpha));
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedBorderRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'border_rt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.CombinedBorder := 24;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(24, S2.CombinedBorder);
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedBorderClampedUpper;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'border_hi.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'CombinedBorder', 99999);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MAX_COMBINED_BORDER, S.CombinedBorder);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestCombinedBorderClampedLower;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'border_lo.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'CombinedBorder', -5);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(MIN_COMBINED_BORDER, S.CombinedBorder);
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampCornerRoundTripAllCorners;
var
  S1, S2: TWcxSettings;
  IniPath: string;
  Corner: TTimestampCorner;
begin
  { Every defined enum value must survive save+load. tcNone is a legacy value
    still supported at the settings layer for backward compatibility with old
    INI files, even though the dialog no longer offers it. }
  for Corner := Low(TTimestampCorner) to High(TTimestampCorner) do
  begin
    IniPath := TPath.Combine(FTempDir, 'corner_' + IntToStr(Ord(Corner)) + '.ini');
    S1 := TWcxSettings.Create(IniPath);
    try
      S1.TimestampCorner := Corner;
      S1.Save;
    finally
      S1.Free;
    end;

    S2 := TWcxSettings.Create(IniPath);
    try
      S2.Load;
      Assert.IsTrue(S2.TimestampCorner = Corner,
        Format('Corner %d failed round-trip', [Ord(Corner)]));
    finally
      S2.Free;
    end;
  end;
end;

procedure TTestWcxSettings.TestUnknownTimestampCornerDefaults;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'corner_unk.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('combined', 'TimestampCorner', 'garbage');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.IsTrue(S.TimestampCorner = DEF_TIMESTAMP_CORNER,
      'Unknown corner string must fall back to DEF_TIMESTAMP_CORNER');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettings.TestTimecodeBackColorAlphaRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  { Background color + alpha share one INI key using the #RRGGBBAA encoding,
    so a single round-trip must preserve both components independently. }
  IniPath := TPath.Combine(FTempDir, 'tcback_rt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.TimecodeBackColor := TColor($00112233);
    S1.TimecodeBackAlpha := 123;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(Integer(TColor($00112233)), Integer(S2.TimecodeBackColor));
    Assert.AreEqual(123, Integer(S2.TimecodeBackAlpha));
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampTextColorRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'tctext_rt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.TimestampTextColor := TColor($0044AA88);
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(Integer(TColor($0044AA88)), Integer(S2.TimestampTextColor));
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampTextAlphaRoundTrip;
var
  S1, S2: TWcxSettings;
  IniPath: string;
begin
  IniPath := TPath.Combine(FTempDir, 'txtalpha_rt.ini');
  S1 := TWcxSettings.Create(IniPath);
  try
    S1.TimestampTextAlpha := 64;
    S1.Save;
  finally
    S1.Free;
  end;

  S2 := TWcxSettings.Create(IniPath);
  try
    S2.Load;
    Assert.AreEqual(64, Integer(S2.TimestampTextAlpha));
  finally
    S2.Free;
  end;
end;

procedure TTestWcxSettings.TestTimestampTextAlphaClampedUpper;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'txtalpha_hi.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('combined', 'TimestampTextAlpha', 500);
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(Integer(MAX_TIMESTAMP_TEXT_ALPHA), Integer(S.TimestampTextAlpha));
  finally
    S.Free;
  end;
end;

end.

