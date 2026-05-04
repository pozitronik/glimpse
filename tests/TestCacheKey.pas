unit TestCacheKey;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCacheKey = class
  public
    [Test]
    procedure TestCacheHashKeyDeterministic;
    [Test]
    procedure TestCacheHashKeyLength;
    [Test]
    procedure TestCacheHashKeyDifferentInputs;
    [Test]
    procedure TestShardedKeyPathStructure;
    [Test]
    procedure TestShardedKeyPathExtension;
    [Test]
    procedure TestInvFmtDecimalSeparator;
    {Pins the lowercase-output contract. Earlier CacheHashKey ended in
     a redundant .ToLower; THashMD5.GetHashString already returns
     lowercase hex, so the call was a no-op string scan. The test makes
     the contract explicit so a future RTL change that returned uppercase
     hex (or removal of ToLower regressing the contract) is caught.}
    [Test]
    procedure TestCacheHashKeyAlwaysLowercase;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uCacheKey;

procedure TTestCacheKey.TestCacheHashKeyDeterministic;
var
  K1, K2: string;
begin
  K1 := CacheHashKey('test|input|string');
  K2 := CacheHashKey('test|input|string');
  Assert.AreEqual(K1, K2, 'Same input must produce identical hash');
end;

procedure TTestCacheKey.TestCacheHashKeyLength;
begin
  Assert.AreEqual(32, Length(CacheHashKey('anything')),
    'MD5 hex string must be 32 characters');
end;

procedure TTestCacheKey.TestCacheHashKeyDifferentInputs;
var
  K1, K2: string;
begin
  K1 := CacheHashKey('input_a');
  K2 := CacheHashKey('input_b');
  Assert.AreNotEqual(K1, K2,
    'Different inputs must produce different hashes');
end;

procedure TTestCacheKey.TestShardedKeyPathStructure;
var
  Path, Key: string;
begin
  Key := 'abcdef1234567890abcdef1234567890';
  Path := ShardedKeyPath('C:\cache', Key, '.png');
  { Path must contain the shard prefix directory }
  Assert.IsTrue(Pos(Copy(Key, 1, SHARD_PREFIX_LEN), Path) > 0,
    'Path must include shard prefix subdirectory');
  Assert.IsTrue(Path.EndsWith(Key + '.png'),
    'Path must end with key + extension');
end;

procedure TTestCacheKey.TestShardedKeyPathExtension;
var
  PngPath, ProbePath: string;
  Key: string;
begin
  Key := 'abcdef1234567890abcdef1234567890';
  PngPath := ShardedKeyPath('C:\cache', Key, '.png');
  ProbePath := ShardedKeyPath('C:\cache', Key, '.probe');
  Assert.IsTrue(PngPath.EndsWith('.png'), 'PNG path must end with .png');
  Assert.IsTrue(ProbePath.EndsWith('.probe'), 'Probe path must end with .probe');
  Assert.AreNotEqual(PngPath, ProbePath,
    'Different extensions must produce different paths');
end;

procedure TTestCacheKey.TestInvFmtDecimalSeparator;
begin
  Assert.AreEqual('.', InvFmt.DecimalSeparator,
    'InvFmt must use dot as decimal separator for deterministic keys');
end;

procedure TTestCacheKey.TestCacheHashKeyAlwaysLowercase;
var
  Key: string;
  C: Char;
begin
  {Try several inputs likely to surface different hash byte patterns.}
  for var Input in TArray<string>.Create('abc', 'C:\Some\Path|123|0.500',
    'video.mp4|1024|x|s320|kf', '') do
  begin
    Key := CacheHashKey(Input);
    for C in Key do
      Assert.IsFalse(CharInSet(C, ['A'..'Z']),
        Format('Hex output must be lowercase; got %s for %s', [Key, Input]));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCacheKey);

end.
