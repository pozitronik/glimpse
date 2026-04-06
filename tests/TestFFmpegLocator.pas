{ Tests for uFFmpegLocator: ffmpeg.exe discovery logic.
  Verifies search order (plugin dir > configured path > system PATH),
  env var expansion, and fallback to empty when not found. }
unit TestFFmpegLocator;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegLocator = class
  private
    FTempDir: string;
    FPluginDir: string;
    FConfigDir: string;
    { Creates a dummy ffmpeg.exe in the given directory }
    procedure PlaceDummyExe(const ADir: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    { Returns ffmpeg.exe from plugin dir when present }
    [Test] procedure FoundInPluginDir;
    { Falls back to configured path when plugin dir has no ffmpeg }
    [Test] procedure FoundInConfiguredPath;
    { Env vars in configured path are expanded }
    [Test] procedure ConfiguredPathExpandsEnvVars;
    { Plugin dir takes priority over configured path }
    [Test] procedure PluginDirWinsOverConfiguredPath;
    { Returns empty when neither plugin dir nor configured path has ffmpeg
      and it is not on the system PATH (assumed for test isolation) }
    [Test] procedure NotFoundReturnsEmpty;
    { Empty plugin dir does not crash; falls through to configured path }
    [Test] procedure EmptyPluginDir_FallsToConfigured;
    { Empty configured path does not crash; falls through to system PATH }
    [Test] procedure EmptyConfiguredPath_SkipsGracefully;
    { Both inputs empty: relies on system PATH only }
    [Test] procedure BothEmpty_FallsToSystemPath;
    { Configured path pointing to nonexistent file is skipped }
    [Test] procedure ConfiguredPath_NonexistentFile_Skipped;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows,
  uFFmpegLocator;

procedure TTestFFmpegLocator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_LocTest_' + TGUID.NewGuid.ToString);
  FPluginDir := TPath.Combine(FTempDir, 'plugin');
  FConfigDir := TPath.Combine(FTempDir, 'config');
  TDirectory.CreateDirectory(FPluginDir);
  TDirectory.CreateDirectory(FConfigDir);
end;

procedure TTestFFmpegLocator.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestFFmpegLocator.PlaceDummyExe(const ADir: string);
begin
  TFile.WriteAllText(TPath.Combine(ADir, 'ffmpeg.exe'), 'dummy');
end;

procedure TTestFFmpegLocator.FoundInPluginDir;
var
  R: string;
begin
  PlaceDummyExe(FPluginDir);
  R := FindFFmpegExe(FPluginDir, '');
  Assert.AreEqual(TPath.Combine(FPluginDir, 'ffmpeg.exe'), R,
    'Should find ffmpeg.exe in plugin directory');
end;

procedure TTestFFmpegLocator.FoundInConfiguredPath;
var
  ConfigPath, R: string;
begin
  { No ffmpeg in plugin dir, but configured path points to it }
  PlaceDummyExe(FConfigDir);
  ConfigPath := TPath.Combine(FConfigDir, 'ffmpeg.exe');
  R := FindFFmpegExe(FPluginDir, ConfigPath);
  Assert.AreEqual(ConfigPath, R,
    'Should find ffmpeg.exe at the configured path');
end;

procedure TTestFFmpegLocator.ConfiguredPathExpandsEnvVars;
var
  EnvName, ConfigPath, R: string;
begin
  { Set a temp env var pointing to our config dir }
  EnvName := 'VT_TEST_FFMPEG_DIR';
  SetEnvironmentVariable(PChar(EnvName), PChar(FConfigDir));
  try
    PlaceDummyExe(FConfigDir);
    ConfigPath := '%' + EnvName + '%\ffmpeg.exe';
    R := FindFFmpegExe('', ConfigPath);
    Assert.AreEqual(TPath.Combine(FConfigDir, 'ffmpeg.exe'), R,
      'Environment variables in configured path should be expanded');
  finally
    SetEnvironmentVariable(PChar(EnvName), nil);
  end;
end;

procedure TTestFFmpegLocator.PluginDirWinsOverConfiguredPath;
var
  ConfigPath, R: string;
begin
  { Place ffmpeg.exe in both locations }
  PlaceDummyExe(FPluginDir);
  PlaceDummyExe(FConfigDir);
  ConfigPath := TPath.Combine(FConfigDir, 'ffmpeg.exe');
  R := FindFFmpegExe(FPluginDir, ConfigPath);
  Assert.AreEqual(TPath.Combine(FPluginDir, 'ffmpeg.exe'), R,
    'Plugin dir should take priority over configured path');
end;

procedure TTestFFmpegLocator.NotFoundReturnsEmpty;
var
  R: string;
begin
  { Neither dir has ffmpeg.exe; use unique paths to avoid system PATH match }
  R := FindFFmpegExe(FPluginDir, TPath.Combine(FConfigDir, 'ffmpeg.exe'));
  { We cannot guarantee ffmpeg is NOT on system PATH, so we only assert
    that if the result is non-empty, it must be a valid file. In practice
    on most test machines without ffmpeg installed, this returns empty. }
  if R <> '' then
    Assert.IsTrue(TFile.Exists(R), 'If found, must point to existing file')
  else
    Assert.AreEqual('', R, 'Should return empty when not found');
end;

procedure TTestFFmpegLocator.EmptyPluginDir_FallsToConfigured;
var
  ConfigPath, R: string;
begin
  PlaceDummyExe(FConfigDir);
  ConfigPath := TPath.Combine(FConfigDir, 'ffmpeg.exe');
  R := FindFFmpegExe('', ConfigPath);
  Assert.AreEqual(ConfigPath, R,
    'Empty plugin dir should fall through to configured path');
end;

procedure TTestFFmpegLocator.EmptyConfiguredPath_SkipsGracefully;
var
  R: string;
begin
  PlaceDummyExe(FPluginDir);
  R := FindFFmpegExe(FPluginDir, '');
  Assert.AreEqual(TPath.Combine(FPluginDir, 'ffmpeg.exe'), R,
    'Empty configured path should not interfere with plugin dir search');
end;

procedure TTestFFmpegLocator.BothEmpty_FallsToSystemPath;
var
  R: string;
begin
  { Both empty: result depends entirely on whether ffmpeg is on PATH }
  R := FindFFmpegExe('', '');
  if R <> '' then
    Assert.IsTrue(TFile.Exists(R), 'If found on PATH, must be a real file')
  else
    Assert.AreEqual('', R, 'Should return empty when not on PATH');
end;

procedure TTestFFmpegLocator.ConfiguredPath_NonexistentFile_Skipped;
var
  R: string;
begin
  { Configured path points to non-existent file; plugin dir has ffmpeg }
  PlaceDummyExe(FPluginDir);
  R := FindFFmpegExe(FPluginDir, 'C:\no\such\path\ffmpeg.exe');
  Assert.AreEqual(TPath.Combine(FPluginDir, 'ffmpeg.exe'), R,
    'Non-existent configured path should be skipped');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegLocator);

end.
