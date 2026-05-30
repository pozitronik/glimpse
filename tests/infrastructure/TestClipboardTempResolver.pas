{Tests for ClipboardTempResolver. The pure pick (ChooseClipboardTempFolder)
 is exercised exhaustively without disk; ResolveClipboardTempFolder is
 checked for the on-disk paths (empty -> system temp, existing folder used,
 missing-but-creatable folder created) and the always-trailing-delimiter
 contract.}
unit TestClipboardTempResolver;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardTempResolver = class
  strict private
    FTempDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Choose_EmptyConfigured_PicksSystem;
    [Test] procedure Choose_WhitespaceConfigured_PicksSystem;
    [Test] procedure Choose_UsableExpanded_PicksExpanded;
    [Test] procedure Choose_UnusableExpanded_FallsBackToSystem;

    [Test] procedure Resolve_Empty_ReturnsSystemTemp;
    [Test] procedure Resolve_ExistingFolder_ReturnsIt;
    [Test] procedure Resolve_MissingButCreatable_CreatesAndReturnsIt;
    [Test] procedure Resolve_AlwaysHasTrailingDelimiter;

    [Test] procedure Display_Empty_ReturnsSystemTemp;
    [Test] procedure Display_NonEmpty_ReturnsExpandedTrailingDelim;
    [Test] procedure Display_MissingPath_DoesNotCreateDirectory;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  ClipboardTempResolver;

procedure TTestClipboardTempResolver.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_ResolverTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestClipboardTempResolver.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestClipboardTempResolver.Choose_EmptyConfigured_PicksSystem;
begin
  Assert.AreEqual('C:\sys',
    ChooseClipboardTempFolder('', 'C:\expanded', 'C:\sys', True));
end;

procedure TTestClipboardTempResolver.Choose_WhitespaceConfigured_PicksSystem;
begin
  {A blank-but-spaces configured value is still "system temp".}
  Assert.AreEqual('C:\sys',
    ChooseClipboardTempFolder('   ', 'C:\expanded', 'C:\sys', True));
end;

procedure TTestClipboardTempResolver.Choose_UsableExpanded_PicksExpanded;
begin
  Assert.AreEqual('C:\expanded',
    ChooseClipboardTempFolder('%VAR%\x', 'C:\expanded', 'C:\sys', True));
end;

procedure TTestClipboardTempResolver.Choose_UnusableExpanded_FallsBackToSystem;
begin
  Assert.AreEqual('C:\sys',
    ChooseClipboardTempFolder('%VAR%\x', 'C:\expanded', 'C:\sys', False));
end;

procedure TTestClipboardTempResolver.Resolve_Empty_ReturnsSystemTemp;
var
  Resolved: string;
begin
  Resolved := ResolveClipboardTempFolder('');
  Assert.AreEqual(
    IncludeTrailingPathDelimiter(TPath.GetTempPath),
    Resolved);
end;

procedure TTestClipboardTempResolver.Resolve_ExistingFolder_ReturnsIt;
var
  Resolved: string;
begin
  Resolved := ResolveClipboardTempFolder(FTempDir);
  Assert.AreEqual(IncludeTrailingPathDelimiter(FTempDir), Resolved);
end;

procedure TTestClipboardTempResolver.Resolve_MissingButCreatable_CreatesAndReturnsIt;
var
  Target, Resolved: string;
begin
  {A configured folder that does not yet exist is created so pointing at a
   fresh TC temp subtree just works.}
  Target := TPath.Combine(FTempDir, 'new_sub');
  Assert.IsFalse(TDirectory.Exists(Target), 'precondition: target absent');

  Resolved := ResolveClipboardTempFolder(Target);
  Assert.AreEqual(IncludeTrailingPathDelimiter(Target), Resolved);
  Assert.IsTrue(TDirectory.Exists(Target), 'resolver must have created the folder');
end;

procedure TTestClipboardTempResolver.Resolve_AlwaysHasTrailingDelimiter;
var
  Resolved: string;
begin
  Resolved := ResolveClipboardTempFolder(FTempDir);
  Assert.AreEqual(PathDelim, Resolved[Length(Resolved)],
    'resolved folder must end with a path delimiter so the caller can ' +
    'concatenate the file name directly');
end;

procedure TTestClipboardTempResolver.Display_Empty_ReturnsSystemTemp;
begin
  Assert.AreEqual(
    IncludeTrailingPathDelimiter(TPath.GetTempPath),
    DisplayClipboardTempFolder(''));
end;

procedure TTestClipboardTempResolver.Display_NonEmpty_ReturnsExpandedTrailingDelim;
begin
  {No env vars here, so the path passes through verbatim but gains the
   trailing delimiter the caller relies on.}
  Assert.AreEqual(IncludeTrailingPathDelimiter(FTempDir),
    DisplayClipboardTempFolder(FTempDir));
end;

procedure TTestClipboardTempResolver.Display_MissingPath_DoesNotCreateDirectory;
var
  Target: string;
begin
  {Display is called on every keystroke, so it must never touch disk — a
   folder named in the edit but not yet created stays absent.}
  Target := TPath.Combine(FTempDir, 'display_only');
  Assert.IsFalse(TDirectory.Exists(Target), 'precondition: target absent');
  DisplayClipboardTempFolder(Target);
  Assert.IsFalse(TDirectory.Exists(Target),
    'Display must not create the directory the way Resolve does');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardTempResolver);

end.
