unit TestProbeCache;

interface

uses
  DUnitX.TestFramework;

type
  {TProbeCache policy tests. Storage and source-file stat are injected as
   fakes, so every test runs without touching the real filesystem. The
   disk-layer behaviour (sharding, atomic writes, missing directories) is
   TDiskCacheStorage's and is covered by TestCache.}
  [TestFixture]
  TTestProbeCache = class
  public
    [Test] procedure TestMissOnEmptyStorage;
    [Test] procedure TestPutThenGet;
    [Test] procedure TestAllFieldsRoundTrip;
    [Test] procedure TestInvalidResultNotCached;
    [Test] procedure TestForeignContentRejected;
    [Test] procedure TestMissWhenFileCannotBeStatted;
    [Test] procedure TestStaleAfterFileIdentityChanges;
    [Test] procedure TestFloatLocaleIndependence;
    [Test] procedure TestPutOverwritesPreviousEntry;
    [Test] procedure TestTryGetOrProbeHitsCache;
    [Test] procedure TestTryGetOrProbeMissInvalidNotCached;
    [Test] procedure TestTryGetOrProbeMissProbesAndCaches;
    [Test] procedure TestGetTotalSizeEmpty;
    [Test] procedure TestGetTotalSizeAfterPut;
    [Test] procedure TestClearWipesEntries;
    [Test] procedure TestDefaultProbeCacheDir;
  end;

implementation

uses
  System.SysUtils, System.DateUtils, System.Generics.Collections,
  CacheContracts, VideoProbing, VideoInfo, ProbeCache, ProbeCacheFactory;

type
  {In-memory ICacheStorage: lets TProbeCache's policy be exercised with no
   real disk.}
  TFakeProbeStorage = class(TInterfacedObject, ICacheStorage)
  strict private
    FEntries: TDictionary<string, TBytes>;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(const AKey: string): TBytes;
    procedure Write(const AKey: string; const AData: TBytes);
    procedure Delete(const AKey: string);
    procedure Clear;
    procedure Touch(const AKey: string);
    function List: TArray<TCacheEntryInfo>;
  end;

  {IFileStat stub with canned size/mtime. Size is mutable so a test can
   simulate the source file changing under the cache. AOk=False models a
   file that cannot be stat'd.}
  TStubFileStat = class(TInterfacedObject, IFileStat)
  strict private
    FSize: Int64;
    FModified: TDateTime;
    FOk: Boolean;
  public
    constructor Create(AOk: Boolean = True);
    function TryStat(const APath: string; out ASize: Int64; out AModified: TDateTime): Boolean;
    property Size: Int64 read FSize write FSize;
  end;

  {Stub IVideoProber: returns a canned TVideoInfo and counts calls so the
   cache's miss-vs-hit dispatch can be observed without ffmpeg.}
  TStubProber = class(TInterfacedObject, IVideoProber)
  strict private
    FInfo: TVideoInfo;
    FCallCount: Integer;
  public
    constructor Create(const AInfo: TVideoInfo);
    function ProbeVideo(const AFilePath: string): TVideoInfo;
    property CallCount: Integer read FCallCount;
  end;

{ TFakeProbeStorage }

constructor TFakeProbeStorage.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TBytes>.Create;
end;

destructor TFakeProbeStorage.Destroy;
begin
  FEntries.Free;
  inherited;
end;

function TFakeProbeStorage.Read(const AKey: string): TBytes;
begin
  if not FEntries.TryGetValue(AKey, Result) then
    Result := nil;
end;

procedure TFakeProbeStorage.Write(const AKey: string; const AData: TBytes);
begin
  FEntries.AddOrSetValue(AKey, AData);
end;

procedure TFakeProbeStorage.Delete(const AKey: string);
begin
  FEntries.Remove(AKey);
end;

procedure TFakeProbeStorage.Clear;
begin
  FEntries.Clear;
end;

procedure TFakeProbeStorage.Touch(const AKey: string);
begin
  {Probe cache never touches; ICacheStorage still requires the method.}
end;

function TFakeProbeStorage.List: TArray<TCacheEntryInfo>;
var
  Pair: TPair<string, TBytes>;
  Info: TCacheEntryInfo;
  I: Integer;
begin
  SetLength(Result, FEntries.Count);
  I := 0;
  for Pair in FEntries do
  begin
    Info.Key := Pair.Key;
    Info.Size := Length(Pair.Value);
    Info.AccessTime := 0;
    Result[I] := Info;
    Inc(I);
  end;
end;

{ TStubFileStat }

constructor TStubFileStat.Create(AOk: Boolean);
begin
  inherited Create;
  FOk := AOk;
  FSize := 1024;
  FModified := EncodeDate(2025, 1, 1);
end;

function TStubFileStat.TryStat(const APath: string; out ASize: Int64;
  out AModified: TDateTime): Boolean;
begin
  ASize := FSize;
  AModified := FModified;
  Result := FOk;
end;

{ TStubProber }

constructor TStubProber.Create(const AInfo: TVideoInfo);
begin
  inherited Create;
  FInfo := AInfo;
end;

function TStubProber.ProbeVideo(const AFilePath: string): TVideoInfo;
begin
  Inc(FCallCount);
  Result := FInfo;
end;

{Builds a valid TVideoInfo carrying the given duration.}
function MakeInfo(ADuration: Double): TVideoInfo;
begin
  Result := Default(TVideoInfo);
  Result.Duration := ADuration;
  Result.Width := 1920;
  Result.Height := 1080;
end;

{ TTestProbeCache }

procedure TTestProbeCache.TestMissOnEmptyStorage;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Assert.IsFalse(Cache.TryGet('movie.mp4', Info), 'Empty storage must miss');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestPutThenGet;
var
  Cache: TProbeCache;
  Retrieved: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Cache.Put('movie.mp4', MakeInfo(120.5));
    Assert.IsTrue(Cache.TryGet('movie.mp4', Retrieved), 'A put entry must round-trip');
    Assert.AreEqual(Double(120.5), Retrieved.Duration, 0.001);
    Assert.AreEqual(1920, Retrieved.Width);
    Assert.AreEqual(1080, Retrieved.Height);
    Assert.IsTrue(Retrieved.IsValid);
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestAllFieldsRoundTrip;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Info := Default(TVideoInfo);
    Info.Duration := 3661.123;
    Info.Width := 720;
    Info.Height := 576;
    Info.SampleAspectN := 64;
    Info.SampleAspectD := 45;
    Info.DisplayWidth := 1024;
    Info.DisplayHeight := 576;
    Info.VideoCodec := 'h264';
    Info.VideoBitrateKbps := 5000;
    Info.Fps := 23.976;
    Info.Bitrate := 5500;
    Info.AudioCodec := 'aac';
    Info.AudioSampleRate := 48000;
    Info.AudioChannels := '5.1';
    Info.AudioBitrateKbps := 192;

    Cache.Put('movie.mkv', Info);
    Assert.IsTrue(Cache.TryGet('movie.mkv', Retrieved));

    Assert.AreEqual(Double(3661.123), Retrieved.Duration, 0.001);
    Assert.AreEqual(720, Retrieved.Width);
    Assert.AreEqual(576, Retrieved.Height);
    Assert.AreEqual(64, Retrieved.SampleAspectN, 'SAR numerator must round-trip');
    Assert.AreEqual(45, Retrieved.SampleAspectD, 'SAR denominator must round-trip');
    Assert.AreEqual(1024, Retrieved.DisplayWidth, 'Display width must round-trip');
    Assert.AreEqual(576, Retrieved.DisplayHeight, 'Display height must round-trip');
    Assert.AreEqual('h264', Retrieved.VideoCodec);
    Assert.AreEqual(5000, Retrieved.VideoBitrateKbps);
    Assert.AreEqual(Double(23.976), Retrieved.Fps, 0.001);
    Assert.AreEqual(5500, Retrieved.Bitrate);
    Assert.AreEqual('aac', Retrieved.AudioCodec);
    Assert.AreEqual(48000, Retrieved.AudioSampleRate);
    Assert.AreEqual('5.1', Retrieved.AudioChannels);
    Assert.AreEqual(192, Retrieved.AudioBitrateKbps);
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestInvalidResultNotCached;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Info := Default(TVideoInfo);
    Info.Duration := -1;
    Info.ErrorMessage := 'Could not parse';
    Cache.Put('movie.mp4', Info);
    Assert.IsFalse(Cache.TryGet('movie.mp4', Retrieved),
      'Put must refuse to persist an invalid result');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestForeignContentRejected;
var
  Storage: ICacheStorage;
  Cache: TProbeCache;
  Retrieved: TVideoInfo;
  StoredKey: string;
begin
  {An entry lacking the GlimpseProbe format marker (a foreign blob, or one
   from before format versioning) must be treated as a miss, never
   deserialised into a fabricated TVideoInfo.}
  Storage := TFakeProbeStorage.Create;
  Cache := TProbeCache.Create(Storage, TStubFileStat.Create);
  try
    Cache.Put('movie.mp4', MakeInfo(120.5));
    Assert.AreEqual<Integer>(1, Length(Storage.List), 'Put must have stored one entry');

    StoredKey := Storage.List[0].Key;
    Storage.Write(StoredKey,
      TEncoding.UTF8.GetBytes('Duration=999'#13#10'Width=640'#13#10));

    Assert.IsFalse(Cache.TryGet('movie.mp4', Retrieved),
      'An entry without the format marker must be rejected');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestMissWhenFileCannotBeStatted;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
begin
  {A source file that cannot be stat'd yields an empty key; TryGet must
   miss rather than trap.}
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create(False));
  try
    Assert.IsFalse(Cache.TryGet('movie.mp4', Info));
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestStaleAfterFileIdentityChanges;
var
  Stat: TStubFileStat;
  Cache: TProbeCache;
  Retrieved: TVideoInfo;
begin
  {The cache key folds in the source file's size; a stat reporting a
   different size produces a different key and so a miss.}
  Stat := TStubFileStat.Create;
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, Stat);
  try
    Cache.Put('movie.mp4', MakeInfo(60.0));
    Assert.IsTrue(Cache.TryGet('movie.mp4', Retrieved), 'Pre-condition: cached');

    Stat.Size := 999999;
    Assert.IsFalse(Cache.TryGet('movie.mp4', Retrieved),
      'A changed source-file identity must invalidate the cached entry');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestFloatLocaleIndependence;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  SavedSep: Char;
begin
  {Floats are serialised with the invariant format; writing under a comma
   decimal separator must still be readable under a period.}
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    SavedSep := FormatSettings.DecimalSeparator;
    try
      FormatSettings.DecimalSeparator := ',';
      Info := Default(TVideoInfo);
      Info.Duration := 123.456;
      Info.Width := 640;
      Info.Height := 360;
      Info.Fps := 29.97;
      Cache.Put('movie.mp4', Info);

      FormatSettings.DecimalSeparator := '.';
      Assert.IsTrue(Cache.TryGet('movie.mp4', Retrieved));
      Assert.AreEqual(Double(123.456), Retrieved.Duration, 0.001);
      Assert.AreEqual(Double(29.97), Retrieved.Fps, 0.001);
    finally
      FormatSettings.DecimalSeparator := SavedSep;
    end;
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestPutOverwritesPreviousEntry;
var
  Cache: TProbeCache;
  Retrieved: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Cache.Put('movie.mp4', MakeInfo(30.0));
    Cache.Put('movie.mp4', MakeInfo(90.0));
    Assert.IsTrue(Cache.TryGet('movie.mp4', Retrieved));
    Assert.AreEqual(Double(90.0), Retrieved.Duration, 0.001,
      'A second Put must overwrite the first entry');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestTryGetOrProbeHitsCache;
var
  Cache: TProbeCache;
  Stub: TStubProber;
  Prober: IVideoProber;
  Retrieved: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Cache.Put('movie.mp4', MakeInfo(42.5));
    Stub := TStubProber.Create(Default(TVideoInfo));
    Prober := Stub;

    Retrieved := Cache.TryGetOrProbe('movie.mp4', Prober);
    Assert.IsTrue(Retrieved.IsValid, 'Cached entry must be returned');
    Assert.AreEqual(Double(42.5), Retrieved.Duration, 0.001);
    Assert.AreEqual(0, Stub.CallCount,
      'Prober must not be invoked when the entry is already cached');
  finally
    Cache.Free;
    Prober := nil;
  end;
end;

procedure TTestProbeCache.TestTryGetOrProbeMissInvalidNotCached;
var
  Cache: TProbeCache;
  Stub: TStubProber;
  Prober: IVideoProber;
  Invalid, Retrieved, Check: TVideoInfo;
begin
  {On a miss with a prober that reports failure, the invalid result is
   returned but not persisted; the next TryGet must still miss.}
  Invalid := Default(TVideoInfo);
  Invalid.Duration := -1;
  Stub := TStubProber.Create(Invalid);
  Prober := Stub;
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Retrieved := Cache.TryGetOrProbe('movie.mp4', Prober);
    Assert.IsFalse(Retrieved.IsValid, 'Invalid probe result expected');
    Assert.AreEqual(1, Stub.CallCount, 'Prober invoked once on the cache miss');
    Assert.IsFalse(Cache.TryGet('movie.mp4', Check),
      'An invalid result must not have been cached');
  finally
    Cache.Free;
    Prober := nil;
  end;
end;

procedure TTestProbeCache.TestTryGetOrProbeMissProbesAndCaches;
var
  Cache: TProbeCache;
  Stub: TStubProber;
  Prober: IVideoProber;
  First, Second: TVideoInfo;
begin
  {First call misses, delegates to the prober and persists the valid
   result; the second call is served from cache without re-probing.}
  Stub := TStubProber.Create(MakeInfo(12.5));
  Prober := Stub;
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    First := Cache.TryGetOrProbe('movie.mp4', Prober);
    Assert.IsTrue(First.IsValid, 'First call must return the probed info');
    Assert.AreEqual(1, Stub.CallCount, 'Prober invoked once on the first miss');

    Second := Cache.TryGetOrProbe('movie.mp4', Prober);
    Assert.IsTrue(Second.IsValid, 'Second call must hit the cache');
    Assert.AreEqual(1, Stub.CallCount, 'Prober must not be re-invoked on a cache hit');
  finally
    Cache.Free;
    Prober := nil;
  end;
end;

procedure TTestProbeCache.TestGetTotalSizeEmpty;
var
  Cache: TProbeCache;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Assert.AreEqual<Int64>(0, Cache.GetTotalSize, 'Empty cache totals to zero');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestGetTotalSizeAfterPut;
var
  Cache: TProbeCache;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Cache.Put('movie.mp4', MakeInfo(60.0));
    Assert.IsTrue(Cache.GetTotalSize > 0,
      'After a Put the total size must be non-zero');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestClearWipesEntries;
var
  Cache: TProbeCache;
  Retrieved: TVideoInfo;
begin
  Cache := TProbeCache.Create(TFakeProbeStorage.Create, TStubFileStat.Create);
  try
    Cache.Put('movie.mp4', MakeInfo(60.0));
    Assert.IsTrue(Cache.TryGet('movie.mp4', Retrieved), 'Pre-condition: cache hit');

    Cache.Clear;
    Assert.AreEqual<Int64>(0, Cache.GetTotalSize, 'Total size zero after Clear');
    Assert.IsFalse(Cache.TryGet('movie.mp4', Retrieved), 'Cache must miss after Clear');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestDefaultProbeCacheDir;
var
  Dir: string;
begin
  Dir := DefaultProbeCacheDir;
  Assert.IsTrue(Dir.Contains('Glimpse'), 'Default dir must be under Glimpse');
  Assert.IsTrue(Dir.Contains('probes'), 'Default dir must be the probes folder');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestProbeCache);

end.
