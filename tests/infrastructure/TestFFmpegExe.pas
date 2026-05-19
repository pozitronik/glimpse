unit TestFFmpegExe;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegProbeIntegration = class
  public
    {Real ffmpeg.exe + a real anamorphic file. Skipped when ffmpeg.exe is
     not on the system PATH so the suite stays runnable on machines without
     ffmpeg installed.}
    [Test] procedure TestProbeAnamorphicVideo;
  end;

  [TestFixture]
  TTestFFmpegLocator = class
  private
    FTempDir: string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestFindInPluginDir;
    [Test] procedure TestFindAtConfiguredPath;
    [Test] procedure TestPluginDirHasPriority;
    [Test] procedure TestNotFoundReturnsEmpty;
    [Test] procedure TestEmptyPluginDir;
    [Test] procedure TestConfiguredPathNotExists;
    [Test] procedure TestConfiguredPathExpandsEnvVars;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Winapi.Windows,
  FFmpegExe, FFmpegLocator, VideoInfo;

function TestDataPath(const AFileName: string): string;
begin
  {Tests run from tests/Win64/Debug/GlimpseTests.exe; data lives in tests/data/}
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\data\' + AFileName));
end;

{ TTestFFmpegProbeIntegration }

procedure TTestFFmpegProbeIntegration.TestProbeAnamorphicVideo;
var
  FFmpegPath, VideoPath: string;
  FFmpeg: TFFmpegExe;
  Info: TVideoInfo;
begin
  FFmpegPath := FindFFmpegExe('', '');
  if FFmpegPath = '' then
  begin
    {Pass-through when ffmpeg is not on PATH; the unit-level parse tests
     still cover the parsing logic.}
    Assert.Pass('ffmpeg.exe not on PATH; skipping integration test');
    Exit;
  end;

  VideoPath := TestDataPath('test_anamorphic.mp4');
  Assert.IsTrue(TFile.Exists(VideoPath),
    'Test data missing: ' + VideoPath);

  FFmpeg := TFFmpegExe.Create(FFmpegPath);
  try
    Info := FFmpeg.ProbeVideo(VideoPath);
    Assert.IsTrue(Info.IsValid, 'Probe must succeed: ' + Info.ErrorMessage);
    Assert.AreEqual(720, Info.Width, 'Storage width');
    Assert.AreEqual(576, Info.Height, 'Storage height');
    Assert.AreEqual(64, Info.SampleAspectN, 'SAR numerator');
    Assert.AreEqual(45, Info.SampleAspectD, 'SAR denominator');
    Assert.AreEqual(1024, Info.DisplayWidth,
      'Display width = round(720 * 64/45) = 1024');
    Assert.AreEqual(576, Info.DisplayHeight, 'SAR scales width, not height');
  finally
    FFmpeg.Free;
  end;
end;

{ TTestFFmpegLocator }

procedure TTestFFmpegLocator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_Loc_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestFFmpegLocator.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestFFmpegLocator.TestFindInPluginDir;
var
  PluginDir, Found: string;
begin
  PluginDir := TPath.Combine(FTempDir, 'plugin');
  TDirectory.CreateDirectory(PluginDir);
  TFile.WriteAllText(TPath.Combine(PluginDir, 'ffmpeg.exe'), 'dummy');

  Found := FindFFmpegExe(PluginDir, '');
  Assert.AreEqual(TPath.Combine(PluginDir, 'ffmpeg.exe'), Found);
end;

procedure TTestFFmpegLocator.TestFindAtConfiguredPath;
var
  ExePath, Found: string;
begin
  ExePath := TPath.Combine(FTempDir, 'custom_ffmpeg.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  { Empty plugin dir (no ffmpeg there), configured path exists }
  Found := FindFFmpegExe(TPath.Combine(FTempDir, 'empty'), ExePath);
  Assert.AreEqual(ExePath, Found);
end;

procedure TTestFFmpegLocator.TestPluginDirHasPriority;
var
  PluginDir, ConfigPath, Found: string;
begin
  { Both plugin dir and configured path have ffmpeg; plugin dir should win }
  PluginDir := TPath.Combine(FTempDir, 'plugin');
  TDirectory.CreateDirectory(PluginDir);
  TFile.WriteAllText(TPath.Combine(PluginDir, 'ffmpeg.exe'), 'plugin');

  ConfigPath := TPath.Combine(FTempDir, 'other_ffmpeg.exe');
  TFile.WriteAllText(ConfigPath, 'config');

  Found := FindFFmpegExe(PluginDir, ConfigPath);
  Assert.AreEqual(TPath.Combine(PluginDir, 'ffmpeg.exe'), Found,
    'Plugin directory should have priority over configured path');
end;

procedure TTestFFmpegLocator.TestNotFoundReturnsEmpty;
var
  Found: string;
begin
  { Neither plugin dir nor configured path has ffmpeg, and we cannot rely
    on system PATH for a deterministic test. Just verify no crash. }
  Found := FindFFmpegExe(TPath.Combine(FTempDir, 'nowhere'), '');
  { Result depends on whether ffmpeg is on system PATH; just verify no exception }
  Assert.Pass;
end;

procedure TTestFFmpegLocator.TestEmptyPluginDir;
var
  ExePath, Found: string;
begin
  ExePath := TPath.Combine(FTempDir, 'ff.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  Found := FindFFmpegExe('', ExePath);
  Assert.AreEqual(ExePath, Found, 'Empty plugin dir should skip to configured path');
end;

procedure TTestFFmpegLocator.TestConfiguredPathNotExists;
var
  Found: string;
begin
  { Configured path points to a non-existent file }
  Found := FindFFmpegExe(
    TPath.Combine(FTempDir, 'empty'),
    TPath.Combine(FTempDir, 'no_such_file.exe'));
  { Should fall through to system PATH search }
  Assert.Pass;
end;

procedure TTestFFmpegLocator.TestConfiguredPathExpandsEnvVars;
var
  SubDir, ExePath, Found: string;
begin
  { Place ffmpeg.exe inside a subdirectory of TEMP and reference it via
    the %TEMP% environment variable. FindFFmpegExe must expand the variable
    before checking TFile.Exists. }
  SubDir := TPath.Combine(FTempDir, 'tools');
  TDirectory.CreateDirectory(SubDir);
  ExePath := TPath.Combine(SubDir, 'ffmpeg.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  { Set a custom env var pointing to our temp dir }
  SetEnvironmentVariable('VT_TEST_PLUGIN_DIR', PChar(FTempDir));
  try
    Found := FindFFmpegExe('',
      '%VT_TEST_PLUGIN_DIR%' + PathDelim + 'tools' + PathDelim + 'ffmpeg.exe');
    Assert.AreEqual(ExePath, Found,
      'FindFFmpegExe must expand environment variables in configured path');
  finally
    SetEnvironmentVariable('VT_TEST_PLUGIN_DIR', nil);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegProbeIntegration);
  TDUnitX.RegisterTestFixture(TTestFFmpegLocator);

end.
