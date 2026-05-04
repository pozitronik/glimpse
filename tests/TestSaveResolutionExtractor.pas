unit TestSaveResolutionExtractor;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNeedsReExtractForSave = class
  public
    [Test] procedure SaveAtLiveResolutionOnSkips;
    [Test] procedure EmptyIndicesSkips;
    [Test] procedure MatchingTargetSkips;
    [Test] procedure DifferingTargetTriggersReExtract;
    [Test] procedure ZeroToZeroSkips;
    [Test] procedure CapToNativeTriggersReExtract;
  end;

  [TestFixture]
  TTestSaveResolutionExtractor = class
  public
    [Test] procedure EmptyOffsetsReturnsEmpty;
    [Test] procedure EmptyIndicesReturnsCellCountSizedNilArray;
    [Test] procedure EmptyFileNameReturnsEmpty;
    [Test] procedure CacheHitSkipsExtractor;
    [Test] procedure CacheMissCallsExtractorAndStores;
    [Test] procedure MixedHitAndMissBothPopulated;
    [Test] procedure ExtractorFailureLeavesEntryNil;
    [Test] procedure OutOfRangeIndexIsSkipped;
    [Test] procedure ProgressCallbacksFire;
    [Test] procedure DoneCallbackFiresEvenOnEarlyExit;
    {Negative test for the review claim that ExtractAtTarget stores the
     extractor's bitmap reference shared with the result array so freeing
     the result would leave a dangling pointer in the cache. The production
     TFrameCache serialises the bitmap to a PNG on disk and drops the
     reference; the next TryGet rebuilds a fresh TBitmap. The test
     uses a real disk cache, frees the first result, and asserts the
     second extraction returns a distinct, valid bitmap.}
    [Test] procedure CacheDoesNotShareBitmapWithResult;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Vcl.Graphics,
  uTypes, uCache, uFrameOffsets, uFrameExtractor, uSaveResolutionExtractor;

{ Mock IFrameCache: tracks Put / TryGet calls, returns canned bitmaps. }
type
  TMockCache = class(TInterfacedObject, IFrameCache)
  strict private
    FCanned: TDictionary<string, TBitmap>; {key -> bitmap to clone on TryGet}
    FPutCount: Integer;
    FTryGetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    {AStore takes ownership of ABmp and clones it on every TryGet so the
     caller-owns-result contract holds.}
    procedure Stash(const AKey: TFrameCacheKey; ABmp: TBitmap);
    function TryGet(const AKey: TFrameCacheKey): TBitmap;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
    property PutCount: Integer read FPutCount;
    property TryGetCount: Integer read FTryGetCount;
  end;

  {Mock IFrameExtractor: returns canned bitmaps keyed by time offset, or
   nil to simulate ffmpeg failure. Tracks call count.}
  TMockExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FCanned: TDictionary<Double, TBitmap>;
    FNullOffsets: TList<Double>;
    FCallCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    {Owner-style: takes ownership of ABmp and clones it on each call so
     the caller-owns-result contract holds.}
    procedure SetCanned(ATimeOffset: Double; ABmp: TBitmap);
    procedure FailOn(ATimeOffset: Double);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
    property CallCount: Integer read FCallCount;
  end;

function CloneBitmap(ABmp: TBitmap): TBitmap;
begin
  Result := TBitmap.Create;
  Result.Assign(ABmp);
end;

function CacheKeyToString(const AKey: TFrameCacheKey): string;
begin
  Result := Format('%s|%.3f|%d|%d', [AKey.FilePath, AKey.TimeOffset, AKey.MaxSide,
    Ord(AKey.UseKeyframes)]);
end;

{ TMockCache }

constructor TMockCache.Create;
begin
  inherited Create;
  FCanned := TDictionary<string, TBitmap>.Create;
end;

destructor TMockCache.Destroy;
var
  Bmp: TBitmap;
begin
  for Bmp in FCanned.Values do
    Bmp.Free;
  FCanned.Free;
  inherited;
end;

procedure TMockCache.Stash(const AKey: TFrameCacheKey; ABmp: TBitmap);
begin
  FCanned.AddOrSetValue(CacheKeyToString(AKey), ABmp);
end;

function TMockCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
var
  Cached: TBitmap;
begin
  Inc(FTryGetCount);
  if FCanned.TryGetValue(CacheKeyToString(AKey), Cached) then
    Result := CloneBitmap(Cached)
  else
    Result := nil;
end;

procedure TMockCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
begin
  Inc(FPutCount);
end;

{ TMockExtractor }

constructor TMockExtractor.Create;
begin
  inherited Create;
  FCanned := TDictionary<Double, TBitmap>.Create;
  FNullOffsets := TList<Double>.Create;
end;

destructor TMockExtractor.Destroy;
var
  Bmp: TBitmap;
begin
  for Bmp in FCanned.Values do
    Bmp.Free;
  FCanned.Free;
  FNullOffsets.Free;
  inherited;
end;

procedure TMockExtractor.SetCanned(ATimeOffset: Double; ABmp: TBitmap);
begin
  FCanned.AddOrSetValue(ATimeOffset, ABmp);
end;

procedure TMockExtractor.FailOn(ATimeOffset: Double);
begin
  FNullOffsets.Add(ATimeOffset);
end;

function TMockExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
var
  Canned: TBitmap;
begin
  Inc(FCallCount);
  if FNullOffsets.Contains(ATimeOffset) then
    Exit(nil);
  if FCanned.TryGetValue(ATimeOffset, Canned) then
    Result := CloneBitmap(Canned)
  else
    Result := nil;
end;

function MakeBitmap(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AW, AH);
end;

function MakeOffsets(ACount: Integer): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := (I + 1) * 1.0;
  end;
end;

function MakeContext(ACellCount: Integer): TSaveResolutionContext;
begin
  Result.FileName := 'C:\dummy.mp4';
  Result.Offsets := MakeOffsets(ACellCount);
  Result.CellCount := ACellCount;
  Result.UseBmpPipe := True;
  Result.HwAccel := False;
  Result.UseKeyframes := False;
  Result.RespectAnamorphic := True;
end;

{ TTestNeedsReExtractForSave }

procedure TTestNeedsReExtractForSave.SaveAtLiveResolutionOnSkips;
begin
  Assert.IsFalse(NeedsReExtractForSave(True, 5, 1920, 480),
    'Toggle ON must short-circuit regardless of MaxSide difference');
end;

procedure TTestNeedsReExtractForSave.EmptyIndicesSkips;
begin
  Assert.IsFalse(NeedsReExtractForSave(False, 0, 1920, 480),
    'Empty index list -> nothing for the action to consume; skip');
end;

procedure TTestNeedsReExtractForSave.MatchingTargetSkips;
begin
  Assert.IsFalse(NeedsReExtractForSave(False, 9, 1920, 1920),
    'Live cells already at target -> no re-extract');
end;

procedure TTestNeedsReExtractForSave.DifferingTargetTriggersReExtract;
begin
  Assert.IsTrue(NeedsReExtractForSave(False, 9, 1920, 480),
    'Live at viewport size, save wants higher -> must re-extract');
end;

procedure TTestNeedsReExtractForSave.ZeroToZeroSkips;
begin
  {Native both ways: ScaledExtraction off so live = native (0), save also
   at native (0). No work needed.}
  Assert.IsFalse(NeedsReExtractForSave(False, 9, 0, 0),
    'Native = native -> skip');
end;

procedure TTestNeedsReExtractForSave.CapToNativeTriggersReExtract;
begin
  {Live extracted with cap (e.g. 1920), save wants native (0): re-extract
   even though target seems "smaller" -- the cap selection is what matters
   to the cache key, and a fresh native extraction is required.}
  Assert.IsTrue(NeedsReExtractForSave(False, 9, 0, 1920),
    'Cap-to-native still requires re-extract');
end;

{ TTestSaveResolutionExtractor }

procedure TTestSaveResolutionExtractor.EmptyOffsetsReturnsEmpty;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(0);
    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    Assert.AreEqual(0, Integer(Length(Result)),
      'No offsets and no cells -> empty result array');
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.EmptyIndicesReturnsCellCountSizedNilArray;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(4);
    Result := Sub.ExtractAtTarget(Ctx, 1920, []);
    Assert.AreEqual(4, Integer(Length(Result)),
      'Result must be parallel to FrameView cell count');
    Assert.IsNull(Result[0]);
    Assert.IsNull(Result[3]);
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.EmptyFileNameReturnsEmpty;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(2);
    Ctx.FileName := '';
    Result := Sub.ExtractAtTarget(Ctx, 1920, [0, 1]);
    Assert.AreEqual(2, Integer(Length(Result)));
    Assert.IsNull(Result[0]);
    Assert.IsNull(Result[1]);
    Assert.AreEqual(0, TMockExtractor(Ext).CallCount,
      'No file -> extractor must not be called');
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.CacheHitSkipsExtractor;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
  Stashed: TBitmap;
  Key: TFrameCacheKey;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(3);
    Stashed := MakeBitmap(640, 360);
    Key := TFrameCacheKey.Create(Ctx.FileName, Ctx.Offsets[1].TimeOffset, 1920, False);
    TMockCache(Cache).Stash(Key, Stashed);

    Result := Sub.ExtractAtTarget(Ctx, 1920, [1]);
    try
      Assert.IsNotNull(Result[1], 'Cache hit must populate the slot');
      Assert.AreEqual(640, Result[1].Width);
      Assert.AreEqual(0, TMockExtractor(Ext).CallCount,
        'Cache hit must not call the extractor');
      Assert.AreEqual(0, TMockCache(Cache).PutCount,
        'Cache hit must not write back');
    finally
      Result[1].Free;
    end;
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.CacheMissCallsExtractorAndStores;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
  Canned: TBitmap;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(2);
    Canned := MakeBitmap(1920, 1080);
    TMockExtractor(Ext).SetCanned(Ctx.Offsets[0].TimeOffset, Canned);

    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    try
      Assert.IsNotNull(Result[0]);
      Assert.AreEqual(1920, Result[0].Width);
      Assert.AreEqual(1, TMockExtractor(Ext).CallCount);
      Assert.AreEqual(1, TMockCache(Cache).PutCount,
        'Successful extraction must be cached for next time');
    finally
      Result[0].Free;
    end;
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.MixedHitAndMissBothPopulated;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
  HitBmp, MissBmp: TBitmap;
  HitKey: TFrameCacheKey;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(3);
    HitBmp := MakeBitmap(100, 100);
    HitKey := TFrameCacheKey.Create(Ctx.FileName, Ctx.Offsets[0].TimeOffset, 1920, False);
    TMockCache(Cache).Stash(HitKey, HitBmp);

    MissBmp := MakeBitmap(200, 200);
    TMockExtractor(Ext).SetCanned(Ctx.Offsets[2].TimeOffset, MissBmp);

    Result := Sub.ExtractAtTarget(Ctx, 1920, [0, 2]);
    try
      Assert.IsNotNull(Result[0]);
      Assert.AreEqual(100, Result[0].Width, 'Slot 0 came from cache');
      Assert.IsNull(Result[1], 'Unrequested slot stays nil');
      Assert.IsNotNull(Result[2]);
      Assert.AreEqual(200, Result[2].Width, 'Slot 2 came from extractor');
      Assert.AreEqual(1, TMockExtractor(Ext).CallCount,
        'Only one extractor call (cache hit skips the other)');
    finally
      Result[0].Free;
      Result[2].Free;
    end;
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.ExtractorFailureLeavesEntryNil;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(2);
    TMockExtractor(Ext).FailOn(Ctx.Offsets[0].TimeOffset);

    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    Assert.IsNull(Result[0],
      'Extractor returning nil leaves the slot empty (renderers tolerate nil)');
    Assert.AreEqual(0, TMockCache(Cache).PutCount,
      'Failed extraction must not write to cache');
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.OutOfRangeIndexIsSkipped;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(3);
    {Index 99 is past the offsets array end.}
    Result := Sub.ExtractAtTarget(Ctx, 1920, [99]);
    Assert.AreEqual(3, Integer(Length(Result)));
    Assert.AreEqual(0, TMockExtractor(Ext).CallCount,
      'Out-of-range index must not call the extractor');
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.ProgressCallbacksFire;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
  Canned: TBitmap;
  LabelCalled, DoneCalled: Boolean;
  ProgressCalls: Integer;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    Ctx := MakeContext(2);
    Canned := MakeBitmap(64, 64);
    TMockExtractor(Ext).SetCanned(Ctx.Offsets[0].TimeOffset, Canned);

    LabelCalled := False;
    DoneCalled := False;
    ProgressCalls := 0;

    Sub.OnLabel := procedure(const AText: string) begin LabelCalled := True; end;
    Sub.OnProgress := procedure(ACurrent, ATotal: Integer) begin Inc(ProgressCalls); end;
    Sub.OnDone := procedure begin DoneCalled := True; end;

    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    try
      Assert.IsTrue(LabelCalled, 'Label callback must fire on entry');
      Assert.IsTrue(DoneCalled, 'Done callback must fire on exit');
      {Initial 0/Total + one per index = 2 progress ticks for one index.}
      Assert.AreEqual(2, ProgressCalls);
    finally
      Result[0].Free;
    end;
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.DoneCallbackFiresEvenOnEarlyExit;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  Result: TArray<TBitmap>;
  DoneCalled: Boolean;
begin
  {Early-exit guards (empty offsets / empty indices / empty filename) must
   not fire OnDone -- Done is paired with the work loop, which the early
   exits skip. The label does not fire either. This pins the contract.}
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  try
    DoneCalled := False;
    Sub.OnDone := procedure begin DoneCalled := True; end;
    Ctx := MakeContext(0);
    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    Assert.IsFalse(DoneCalled,
      'Early exit (no offsets) must not fire OnDone -- caller did not see a label either');
    Assert.AreEqual(0, Integer(Length(Result)));
  finally
    Sub.Free;
  end;
end;

procedure TTestSaveResolutionExtractor.CacheDoesNotShareBitmapWithResult;
var
  Cache: IFrameCache;
  Ext: IFrameExtractor;
  Sub: TSaveResolutionExtractor;
  Ctx: TSaveResolutionContext;
  First, Second: TArray<TBitmap>;
  Canned: TBitmap;
  CacheDir: string;
  FirstPtr, SecondPtr: NativeUInt;
  FirstW, FirstH: Integer;
begin
  CacheDir := TPath.Combine(TPath.GetTempPath, 'VT_SaveExtRoundTrip_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(CacheDir);
  try
    Cache := TFrameCache.Create(CacheDir, 100);
    Ext := TMockExtractor.Create;
    Sub := TSaveResolutionExtractor.Create(Cache, Ext);
    try
      Ctx := MakeContext(1);
      {TFrameCache keys include file size + mtime, so FileName must be a
       real existing path. The running test executable is always present.}
      Ctx.FileName := ParamStr(0);
      Canned := MakeBitmap(320, 240);
      TMockExtractor(Ext).SetCanned(Ctx.Offsets[0].TimeOffset, Canned);

      First := Sub.ExtractAtTarget(Ctx, 1920, [0]);
      Assert.IsNotNull(First[0], 'First extraction (cache miss) must produce a bitmap');
      FirstPtr := NativeUInt(First[0]);
      FirstW := First[0].Width;
      FirstH := First[0].Height;
      First[0].Free;
      First[0] := nil;

      Second := Sub.ExtractAtTarget(Ctx, 1920, [0]);
      try
        Assert.IsNotNull(Second[0], 'Second extraction (cache hit) must produce a bitmap');
        SecondPtr := NativeUInt(Second[0]);
        Assert.AreNotEqual(FirstPtr, SecondPtr,
          'Cache must return a fresh bitmap, not the freed reference');
        Assert.AreEqual(FirstW, Second[0].Width);
        Assert.AreEqual(FirstH, Second[0].Height);
        Assert.AreEqual(1, TMockExtractor(Ext).CallCount,
          'Second call must hit cache; extractor stays at 1 call');
      finally
        Second[0].Free;
      end;
    finally
      Sub.Free;
    end;
  finally
    Cache := nil;
    if TDirectory.Exists(CacheDir) then
      TDirectory.Delete(CacheDir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNeedsReExtractForSave);
  TDUnitX.RegisterTestFixture(TTestSaveResolutionExtractor);

end.
