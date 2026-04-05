unit TestPathExpand;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPathExpand = class
  public
    { Core behavior }
    [Test]
    procedure TestEmptyReturnsEmpty;
    [Test]
    procedure TestNoVarsPassesThrough;
    [Test]
    procedure TestExpandsSystemVar;
    [Test]
    procedure TestExpandsMultipleVars;
    [Test]
    procedure TestUnknownVarLeftAsIs;

    { Edge cases }
    [Test]
    procedure TestSinglePercentSign;
    [Test]
    procedure TestOnlyPercentSigns;
    [Test]
    procedure TestVarAtStart;
    [Test]
    procedure TestVarAtEnd;
    [Test]
    procedure TestVarInMiddle;
    [Test]
    procedure TestAdjacentVars;
    [Test]
    procedure TestCustomEnvVar;
    [Test]
    procedure TestEmptyVarName;
    [Test]
    procedure TestUNCPath;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  uPathExpand;

procedure TTestPathExpand.TestEmptyReturnsEmpty;
begin
  Assert.AreEqual('', ExpandEnvVars(''));
end;

procedure TTestPathExpand.TestNoVarsPassesThrough;
begin
  Assert.AreEqual('C:\Temp\test.txt', ExpandEnvVars('C:\Temp\test.txt'));
  Assert.AreEqual('relative\path', ExpandEnvVars('relative\path'));
  Assert.AreEqual('plain', ExpandEnvVars('plain'));
end;

procedure TTestPathExpand.TestExpandsSystemVar;
var
  Expanded: string;
begin
  Expanded := ExpandEnvVars('%TEMP%\Glimpse');
  Assert.IsFalse(Expanded.Contains('%TEMP%'),
    'Variable must be expanded');
  Assert.IsTrue(Expanded.EndsWith('\Glimpse'),
    'Suffix after variable must be preserved');
  Assert.IsTrue(Length(Expanded) > Length('\Glimpse'),
    'Expanded path must be longer than just the suffix');
end;

procedure TTestPathExpand.TestExpandsMultipleVars;
var
  Expanded: string;
begin
  Expanded := ExpandEnvVars('%TEMP%\%USERNAME%\test');
  Assert.IsFalse(Expanded.Contains('%TEMP%'), 'TEMP must be expanded');
  Assert.IsFalse(Expanded.Contains('%USERNAME%'), 'USERNAME must be expanded');
  Assert.IsTrue(Expanded.EndsWith('\test'), 'Tail must be preserved');
end;

procedure TTestPathExpand.TestUnknownVarLeftAsIs;
begin
  Assert.AreEqual('%UNLIKELY_VAR_XYZ_99%\sub',
    ExpandEnvVars('%UNLIKELY_VAR_XYZ_99%\sub'),
    'Unknown variable must remain unexpanded');
end;

procedure TTestPathExpand.TestSinglePercentSign;
begin
  { A lone % without a closing % is not a variable reference }
  Assert.AreEqual('50% done', ExpandEnvVars('50% done'));
end;

procedure TTestPathExpand.TestOnlyPercentSigns;
begin
  Assert.AreEqual('%%', ExpandEnvVars('%%'),
    'Two adjacent percent signs expand to empty-name var (no-op)');
end;

procedure TTestPathExpand.TestVarAtStart;
var
  Expanded: string;
begin
  Expanded := ExpandEnvVars('%TEMP%');
  Assert.IsFalse(Expanded.Contains('%'), 'Must expand to a plain path');
  Assert.IsTrue(Length(Expanded) > 0, 'Must not be empty');
end;

procedure TTestPathExpand.TestVarAtEnd;
var
  Expanded: string;
begin
  Expanded := ExpandEnvVars('prefix\%TEMP%');
  Assert.IsTrue(Expanded.StartsWith('prefix\'), 'Prefix must be preserved');
  Assert.IsFalse(Expanded.Contains('%TEMP%'), 'Variable must be expanded');
end;

procedure TTestPathExpand.TestVarInMiddle;
var
  Expanded: string;
begin
  Expanded := ExpandEnvVars('C:\%USERNAME%\data');
  Assert.IsTrue(Expanded.StartsWith('C:\'), 'Prefix');
  Assert.IsTrue(Expanded.EndsWith('\data'), 'Suffix');
  Assert.IsFalse(Expanded.Contains('%USERNAME%'), 'Variable must be expanded');
end;

procedure TTestPathExpand.TestAdjacentVars;
var
  Expanded: string;
begin
  { Two variables back-to-back with no separator }
  Expanded := ExpandEnvVars('%HOMEDRIVE%%HOMEPATH%');
  Assert.IsFalse(Expanded.Contains('%'), 'Both variables must be expanded');
  Assert.IsTrue(Length(Expanded) >= 3, 'Must resolve to a real path');
end;

procedure TTestPathExpand.TestCustomEnvVar;
begin
  { Set a process-local env var, verify it expands, clean up }
  SetEnvironmentVariable('VT_TEST_EXPAND', PChar('resolved_value'));
  try
    Assert.AreEqual('prefix\resolved_value\suffix',
      ExpandEnvVars('prefix\%VT_TEST_EXPAND%\suffix'));
  finally
    SetEnvironmentVariable('VT_TEST_EXPAND', nil);
  end;
end;

procedure TTestPathExpand.TestEmptyVarName;
begin
  { %% is an empty variable name; ExpandEnvironmentStrings leaves it as-is }
  var Result := ExpandEnvVars('before%%after');
  { Exact behavior is Windows-version-dependent; just verify no crash }
  Assert.IsNotEmpty(Result, 'Must return something');
end;

procedure TTestPathExpand.TestUNCPath;
begin
  { UNC paths must pass through unchanged (no variables) }
  Assert.AreEqual('\\server\share\folder',
    ExpandEnvVars('\\server\share\folder'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPathExpand);

end.
