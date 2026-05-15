unit TestStatusBarTokens;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStatusBarTokens = class
  public
    {Metadata invariants}
    [Test]
    procedure TestEveryKindHasName;
    [Test]
    procedure TestEveryKindHasHint;
    [Test]
    procedure TestEveryKindHasSampleText;
    [Test]
    procedure TestUnknownHasEmptyName;
    [Test]
    procedure TestUnknownHasEmptyHint;
    [Test]
    procedure TestNamesAreUnique;
    [Test]
    procedure TestNamesAreLowercase;

    {Lookup}
    [Test]
    procedure TestLookupRoundTrip;
    [Test]
    procedure TestLookupCaseInsensitive;
    [Test]
    procedure TestLookupUnknownReturnsFalse;
    [Test]
    procedure TestLookupEmptyReturnsFalse;

    {Enumeration}
    [Test]
    procedure TestAllKindsCountMatchesEnum;
    [Test]
    procedure TestAllKindsExcludesUnknown;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uStatusBarTokens;

procedure TTestStatusBarTokens.TestEveryKindHasName;
var
  K: TStatusBarTokenKind;
begin
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
    Assert.IsNotEmpty(StatusBarTokenName(K),
      Format('Kind %d has empty canonical name', [Ord(K)]));
end;

procedure TTestStatusBarTokens.TestEveryKindHasHint;
var
  K: TStatusBarTokenKind;
begin
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
    Assert.IsNotEmpty(StatusBarTokenHint(K),
      Format('Kind %d has empty hint', [Ord(K)]));
end;

procedure TTestStatusBarTokens.TestEveryKindHasSampleText;
var
  K: TStatusBarTokenKind;
begin
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
    Assert.IsNotEmpty(StatusBarTokenSampleText(K),
      Format('Kind %d has empty sample text (auto-width would size to zero)',
        [Ord(K)]));
end;

procedure TTestStatusBarTokens.TestUnknownHasEmptyName;
begin
  Assert.AreEqual('', StatusBarTokenName(tkUnknown));
end;

procedure TTestStatusBarTokens.TestUnknownHasEmptyHint;
begin
  Assert.AreEqual('', StatusBarTokenHint(tkUnknown));
end;

procedure TTestStatusBarTokens.TestNamesAreUnique;
var
  K: TStatusBarTokenKind;
  Seen: TDictionary<string, TStatusBarTokenKind>;
  Name: string;
begin
  Seen := TDictionary<string, TStatusBarTokenKind>.Create;
  try
    for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
    begin
      Name := StatusBarTokenName(K);
      Assert.IsFalse(Seen.ContainsKey(Name),
        Format('Duplicate canonical name "%s" at kind ord %d', [Name, Ord(K)]));
      Seen.Add(Name, K);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TTestStatusBarTokens.TestNamesAreLowercase;
var
  K: TStatusBarTokenKind;
  Name: string;
begin
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
  begin
    Name := StatusBarTokenName(K);
    Assert.AreEqual(LowerCase(Name), Name,
      Format('Canonical name "%s" must be lowercase', [Name]));
  end;
end;

procedure TTestStatusBarTokens.TestLookupRoundTrip;
var
  K, Found: TStatusBarTokenKind;
begin
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
  begin
    Assert.IsTrue(StatusBarTokenKindByName(StatusBarTokenName(K), Found),
      Format('Kind %d did not round-trip via canonical name', [Ord(K)]));
    Assert.AreEqual(Ord(K), Ord(Found));
  end;
end;

procedure TTestStatusBarTokens.TestLookupCaseInsensitive;
var
  K: TStatusBarTokenKind;
begin
  Assert.IsTrue(StatusBarTokenKindByName('RESOLUTION', K));
  Assert.AreEqual(Ord(tkResolution), Ord(K));
  Assert.IsTrue(StatusBarTokenKindByName('Resolution', K));
  Assert.AreEqual(Ord(tkResolution), Ord(K));
  Assert.IsTrue(StatusBarTokenKindByName('SAVE_dimension', K));
  Assert.AreEqual(Ord(tkSaveDimension), Ord(K));
end;

procedure TTestStatusBarTokens.TestLookupUnknownReturnsFalse;
var
  K: TStatusBarTokenKind;
begin
  K := tkResolution;
  Assert.IsFalse(StatusBarTokenKindByName('not_a_real_token_xyz', K));
  Assert.AreEqual(Ord(tkUnknown), Ord(K),
    'Out param must be reset to tkUnknown on miss');
end;

procedure TTestStatusBarTokens.TestLookupEmptyReturnsFalse;
var
  K: TStatusBarTokenKind;
begin
  K := tkResolution;
  Assert.IsFalse(StatusBarTokenKindByName('', K));
  Assert.AreEqual(Ord(tkUnknown), Ord(K));
end;

procedure TTestStatusBarTokens.TestAllKindsCountMatchesEnum;
var
  Kinds: TArray<TStatusBarTokenKind>;
  Expected: Integer;
begin
  Kinds := AllStatusBarTokenKinds;
  Expected := Ord(High(TStatusBarTokenKind)) - Ord(tkUnknown);
  Assert.AreEqual<Integer>(Expected, Length(Kinds),
    'AllStatusBarTokenKinds count must match enum size minus tkUnknown');
end;

procedure TTestStatusBarTokens.TestAllKindsExcludesUnknown;
var
  K: TStatusBarTokenKind;
begin
  for K in AllStatusBarTokenKinds do
    Assert.IsFalse(K = tkUnknown,
      'tkUnknown must not appear in the enumerated catalogue');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStatusBarTokens);

end.
