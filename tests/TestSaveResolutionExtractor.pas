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
    {Pin that ExtractAtTarget does not share the extractor's TBitmap with
     the cache: freeing the returned bitmap must not corrupt a subsequent
     TryGet. Production TFrameCache serialises to PNG and drops the ref.}
    [Test] procedure CacheDoesNotShareBitmapWithResult;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows, Vcl.Graphics,
  uTypes, uCache, uFrameOffsets, uFrameExtractor, uProgressReporter,
  uSaveResolutionExtractor;

type
  {Test-side IProgressReporter that records every lifecycle call so
   ProgressCallbacksFire / DoneCallbackFiresEvenOnEarlyExit can assert
   on them without wiring 4 separate anonymous methods.}
  TRecordingReporter = class(TInterfacedObject, IProgressReporter)
  strict private
    FStartCalled: Boolean;
    FCompleteCalled: Boolean;
    FAdvanceCount: Integer;
    FLastTotal: Integer;
  public
    procedure Start(const AStatusText: string; ATotalSteps: Integer);
    procedure Advance(AStepIndex: Integer);
    procedure Pump;
    procedure Complete;
    property StartCalled: Boolean read FStartCalled;
    property CompleteCalled: Boolean read FCompleteCalled;
    property AdvanceCount: Integer read FAdvanceCount;
    property LastTotal: Integer read FLastTotal;
  end;

procedure TRecordingReporter.Start(const AStatusText: string; ATotalSteps: Integer);
begin
  FStartCalled := True;
  FLastTotal := ATotalSteps;
end;

procedure TRecordingReporter.Advance(AStepIndex: Integer);
begin
  Inc(FAdvanceCount);
end;

procedure TRecordingReporter.Pump;
begin
end;

procedure TRecordingReporter.Complete;
begin
  FCompleteCalled := True;
end;

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
  {Live extracted with cap (e.g. 1920), save wants native (0):
   re-extract even though target seems "smaller". The cap selection
   is what matters to the cache key, and a fresh native extraction
   is required.}
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
  Reporter: TRecordingReporter;
  ReporterRef: IProgressReporter;
begin
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  Reporter := TRecordingReporter.Create;
  ReporterRef := Reporter;
  try
    Ctx := MakeContext(2);
    Canned := MakeBitmap(64, 64);
    TMockExtractor(Ext).SetCanned(Ctx.Offsets[0].TimeOffset, Canned);

    Sub.Reporter := ReporterRef;

    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    try
      Assert.IsTrue(Reporter.StartCalled, 'Reporter.Start must fire on entry');
      Assert.IsTrue(Reporter.CompleteCalled, 'Reporter.Complete must fire on exit');
      {One Advance per processed index; single-index extraction → 1 call.}
      Assert.AreEqual(1, Reporter.AdvanceCount);
      Assert.AreEqual(1, Reporter.LastTotal,
        'Start receives the total work count up front');
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
  Reporter: TRecordingReporter;
  ReporterRef: IProgressReporter;
begin
  {Early-exit guards (empty offsets / empty indices / empty filename)
   must not fire Reporter.Complete; Complete is paired with the work
   loop, which the early exits skip. Start does not fire either.}
  Cache := TMockCache.Create;
  Ext := TMockExtractor.Create;
  Sub := TSaveResolutionExtractor.Create(Cache, Ext);
  Reporter := TRecordingReporter.Create;
  ReporterRef := Reporter;
  try
    Sub.Reporter := ReporterRef;
    Ctx := MakeContext(0);
    Result := Sub.ExtractAtTarget(Ctx, 1920, [0]);
    Assert.IsFalse(Reporter.CompleteCalled,
      'Early exit (no offsets) must not fire Reporter.Complete; Start was never called');
    Assert.IsFalse(Reporter.StartCalled);
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
      try
        Assert.IsNotNull(First[0], 'First extraction (cache miss) must produce a bitmap');
        FirstPtr := NativeUInt(First[0]);
        FirstW := First[0].Width;
        FirstH := First[0].Height;
        {Keep First[0] alive across the second extraction so a heap-slot
         reuse by Delphi's allocator cannot mask a sharing bug. The
         contract under test is "cache returns separate TBitmap instances
         per call"; comparing two simultaneously-live pointers is the
         only way to assert that without depending on allocator behavior.}
        Second := Sub.ExtractAtTarget(Ctx, 1920, [0]);
        try
          Assert.IsNotNull(Second[0], 'Second extraction (cache hit) must produce a bitmap');
          SecondPtr := NativeUInt(Second[0]);
          Assert.AreNotEqual(FirstPtr, SecondPtr,
            'Cache must return a fresh bitmap instance, not share the one already in caller hands');
          Assert.AreEqual(FirstW, Second[0].Width);
          Assert.AreEqual(FirstH, Second[0].Height);
          Assert.AreEqual(1, TMockExtractor(Ext).CallCount,
            'Second call must hit cache; extractor stays at 1 call');
        finally
          Second[0].Free;
        end;
      finally
        First[0].Free;
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
