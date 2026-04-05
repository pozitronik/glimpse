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
    [Test] procedure TestEmptyExtensionListGetsDefault;
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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.IniFiles, System.UITypes,
  uWcxSettings, uBitmapSaver;

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
    Assert.AreEqual(WCX_DEF_FRAMES_COUNT, S.FramesCount);
    Assert.AreEqual(WCX_DEF_SKIP_EDGES, S.SkipEdgesPercent);
    Assert.AreEqual(WCX_DEF_MAX_WORKERS, S.MaxWorkers);
    Assert.AreEqual(WCX_DEF_MAX_THREADS, S.MaxThreads);
    Assert.AreEqual(True, S.UseBmpPipe);
    Assert.IsTrue(S.SaveFormat = sfPNG);
    Assert.AreEqual(WCX_DEF_JPEG_QUALITY, S.JpegQuality);
    Assert.AreEqual(WCX_DEF_PNG_COMPRESSION, S.PngCompression);
    Assert.AreEqual(WCX_DEF_EXTENSION_LIST, S.ExtensionList);
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
    Assert.AreEqual(WCX_DEF_FRAMES_COUNT, S.FramesCount);
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
    S1.ExtensionList := 'mp4,mkv';
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
    Assert.AreEqual('mp4,mkv', S2.ExtensionList);
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

procedure TTestWcxSettings.TestEmptyExtensionListGetsDefault;
var
  S: TWcxSettings;
  IniPath: string;
  Ini: TIniFile;
begin
  IniPath := TPath.Combine(FTempDir, 'ext.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('extensions', 'List', '   ');
  finally
    Ini.Free;
  end;

  S := TWcxSettings.Create(IniPath);
  try
    S.Load;
    Assert.AreEqual(WCX_DEF_EXTENSION_LIST, S.ExtensionList);
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

end.
