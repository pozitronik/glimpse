{Tests for FFmpegLocator: the ffmpeg.exe search-order policy (plugin
 dir > configured path > system PATH) and env-var expansion, driven
 through a fake IExecutableLocatorIO so no ffmpeg.exe is needed on
 disk or PATH.}
unit TestFFmpegLocator;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegLocator = class
  public
    [Test] procedure PluginDir_ExeExists_ReturnsPluginCandidate;
    [Test] procedure PluginDir_NoExe_FallsToConfiguredPath;
    [Test] procedure PluginDir_WinsOverConfiguredPath;
    [Test] procedure EmptyPluginDir_FallsToConfiguredPath;
    [Test] procedure ConfiguredPath_NonexistentFile_FallsToSystemPath;
    [Test] procedure BothCandidatesMissing_ReturnsSystemPathResult;
    [Test] procedure NothingFoundAnywhere_ReturnsEmptyString;
    [Test] procedure ConfiguredPath_EnvVarsExpandedBeforeProbe;
    [Test] procedure EmptyConfiguredPath_IsNotProbed;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.IOUtils, Winapi.Windows,
  FFmpegLocator;

type
  {Controllable IExecutableLocatorIO: the test states which paths
   "exist" and what a PATH search yields, and records which paths
   were probed.}
  TFakeLocatorIO = class(TInterfacedObject, IExecutableLocatorIO)
  private
    FExisting: TArray<string>;
    FSystemPathResult: string;
    FExistsQueries: TArray<string>;
  public
    procedure AddExisting(const APath: string);
    procedure SetSystemPathResult(const AResult: string);
    function ExistsWasQueried(const APath: string): Boolean;
    function FileExists(const APath: string): Boolean;
    function FindOnSystemPath(const AFileName: string): string;
  end;

procedure TFakeLocatorIO.AddExisting(const APath: string);
begin
  FExisting := FExisting + [APath];
end;

procedure TFakeLocatorIO.SetSystemPathResult(const AResult: string);
begin
  FSystemPathResult := AResult;
end;

function TFakeLocatorIO.ExistsWasQueried(const APath: string): Boolean;
begin
  Result := IndexStr(APath, FExistsQueries) >= 0;
end;

function TFakeLocatorIO.FileExists(const APath: string): Boolean;
begin
  FExistsQueries := FExistsQueries + [APath];
  Result := IndexStr(APath, FExisting) >= 0;
end;

function TFakeLocatorIO.FindOnSystemPath(const AFileName: string): string;
begin
  Result := FSystemPathResult;
end;

procedure TTestFFmpegLocator.PluginDir_ExeExists_ReturnsPluginCandidate;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
  Candidate: string;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  Candidate := TPath.Combine('C:\plugin', 'ffmpeg.exe');
  Fake.AddExisting(Candidate);
  Assert.AreEqual(Candidate, FindFFmpegExe('C:\plugin', '', IO),
    'ffmpeg.exe in the plugin dir must be returned first');
end;

procedure TTestFFmpegLocator.PluginDir_NoExe_FallsToConfiguredPath;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  {Plugin dir given but holds no ffmpeg.exe; the configured path does.}
  Fake.AddExisting('C:\cfg\ffmpeg.exe');
  Assert.AreEqual('C:\cfg\ffmpeg.exe',
    FindFFmpegExe('C:\plugin', 'C:\cfg\ffmpeg.exe', IO),
    'A missing plugin-dir exe must fall through to the configured path');
end;

procedure TTestFFmpegLocator.PluginDir_WinsOverConfiguredPath;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
  PluginCandidate: string;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  PluginCandidate := TPath.Combine('C:\plugin', 'ffmpeg.exe');
  {Both locations have ffmpeg.exe.}
  Fake.AddExisting(PluginCandidate);
  Fake.AddExisting('C:\cfg\ffmpeg.exe');
  Assert.AreEqual(PluginCandidate,
    FindFFmpegExe('C:\plugin', 'C:\cfg\ffmpeg.exe', IO),
    'The plugin dir must win when both candidates exist');
end;

procedure TTestFFmpegLocator.EmptyPluginDir_FallsToConfiguredPath;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  Fake.AddExisting('C:\cfg\ffmpeg.exe');
  Assert.AreEqual('C:\cfg\ffmpeg.exe',
    FindFFmpegExe('', 'C:\cfg\ffmpeg.exe', IO),
    'An empty plugin dir must be skipped, not treated as a candidate');
end;

procedure TTestFFmpegLocator.ConfiguredPath_NonexistentFile_FallsToSystemPath;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  {Configured path is set but the file is not there.}
  Fake.SetSystemPathResult('C:\windows\ffmpeg.exe');
  Assert.AreEqual('C:\windows\ffmpeg.exe',
    FindFFmpegExe('C:\plugin', 'C:\cfg\ffmpeg.exe', IO),
    'A configured path that does not exist must fall through to the system PATH');
end;

procedure TTestFFmpegLocator.BothCandidatesMissing_ReturnsSystemPathResult;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  Fake.SetSystemPathResult('C:\windows\ffmpeg.exe');
  Assert.AreEqual('C:\windows\ffmpeg.exe', FindFFmpegExe('C:\plugin', '', IO),
    'With no plugin-dir or configured exe, the system PATH result is used');
end;

procedure TTestFFmpegLocator.NothingFoundAnywhere_ReturnsEmptyString;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  {Nothing exists and the PATH search yields nothing.}
  Fake.SetSystemPathResult('');
  Assert.AreEqual('', FindFFmpegExe('C:\plugin', 'C:\cfg\ffmpeg.exe', IO),
    'When ffmpeg.exe is nowhere, the result must be the empty string');
end;

procedure TTestFFmpegLocator.ConfiguredPath_EnvVarsExpandedBeforeProbe;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  {The configured path uses an env var; the expanded path is what must
   be probed and returned.}
  SetEnvironmentVariable('VT_FFLOC_TEST', 'C:\tools');
  try
    Fake.AddExisting('C:\tools\ffmpeg.exe');
    Assert.AreEqual('C:\tools\ffmpeg.exe',
      FindFFmpegExe('', '%VT_FFLOC_TEST%\ffmpeg.exe', IO),
      'Environment variables in the configured path must be expanded before probing');
  finally
    SetEnvironmentVariable('VT_FFLOC_TEST', nil);
  end;
end;

procedure TTestFFmpegLocator.EmptyConfiguredPath_IsNotProbed;
var
  Fake: TFakeLocatorIO;
  IO: IExecutableLocatorIO;
begin
  Fake := TFakeLocatorIO.Create;
  IO := Fake;
  Fake.SetSystemPathResult('C:\windows\ffmpeg.exe');
  FindFFmpegExe('C:\plugin', '', IO);
  Assert.IsTrue(Fake.ExistsWasQueried(TPath.Combine('C:\plugin', 'ffmpeg.exe')),
    'The plugin-dir candidate must be probed');
  Assert.IsFalse(Fake.ExistsWasQueried(''),
    'An empty configured path must be skipped, never probed');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegLocator);

end.
