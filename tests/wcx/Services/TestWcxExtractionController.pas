{Tests for the WCX pre-extraction controller. ExtractSeparateToCache /
 ExtractCombinedToCache write real files into a session-owned temp dir
 and record slot metadata back to the session. The PreExtract* tests
 drive the full PreExtractFrames orchestration against the real
 TWcxFrameCache singleton (reset per test): cache-miss publish, cache-hit
 short-circuit, and the slot layout per ShowFrames/ShowCombined.}
unit TestWcxExtractionController;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxExtractionController = class
  public
    [Setup] procedure SetUp;
    [TearDown] procedure TearDown;

    [Test] procedure TestExtractCombinedToCacheHappyPathFramesOnSlotAfterFrames;
    [Test] procedure TestExtractCombinedToCacheFramesOffSlotZero;
    [Test] procedure TestExtractCombinedToCacheNoOffsetsIsNoOp;

    [Test] procedure TestExtractSeparateToCacheHappyPathWritesEachFrame;
    [Test] procedure TestExtractSeparateToCacheSkipsNilFrames;
    [Test] procedure TestExtractSeparateToCacheRoutesThroughInjectedRouter;

    [Test] procedure PreExtract_CacheMiss_PublishesAllSlotsToHandle;
    [Test] procedure PreExtract_CacheHit_ServesCachedPathsWithoutExtraction;
    [Test] procedure PreExtract_FramesOnly_PublishesFrameSlots;
    [Test] procedure PreExtract_CombinedOnly_PublishesSingleSlot;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, Vcl.Graphics,
  Types, BitmapSaver, FrameExtractor, FrameOffsets, VideoInfo,
  WcxAPI, WcxSettings, WcxArchiveHandle, WcxEntryExtractors,
  WcxFrameCache, WcxExtractionController;

type
  {Returns a fresh 8x8 bitmap per call. When AReturnNilOnIndex >= 0,
   the matching CallCount yields nil so the "no frame" branch in
   ExtractSeparateToCache runs.}
  TFakeExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FCallCount: Integer;
    FReturnNilOnIndex: Integer;
  public
    constructor Create(AReturnNilOnIndex: Integer = -1);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
    property CallCount: Integer read FCallCount;
  end;

  {Records Save calls without encoding a real image; writes a 1-byte
   placeholder so the controller's TFile.GetSize readback still
   succeeds. Pins that the controller routes through H.BitmapSaver.}
  TFakeBitmapSaverRouter = class(TInterfacedObject, IBitmapSaverRouter)
  strict private
    FSaveCallCount: Integer;
  public
    procedure Save(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions);
    property SaveCallCount: Integer read FSaveCallCount;
  end;

constructor TFakeExtractor.Create(AReturnNilOnIndex: Integer);
begin
  inherited Create;
  FReturnNilOnIndex := AReturnNilOnIndex;
end;

function TFakeExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
begin
  if FCallCount = FReturnNilOnIndex then
  begin
    Inc(FCallCount);
    Exit(nil);
  end;
  Inc(FCallCount);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(8, 8);
end;

procedure TFakeBitmapSaverRouter.Save(ABitmap: TBitmap; const APath: string;
  const AOptions: TSaveOptions);
begin
  Inc(FSaveCallCount);
  {Placeholder file so the extract-to-cache TFile.GetSize readback succeeds.}
  TFile.WriteAllText(APath, 'x');
end;

function MakeOffsets(ACount: Integer): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := (I + 1) * 2.0;
  end;
end;

{Builds a TArchiveHandle with the fields ExtractCombinedToCache and
 ExtractSeparateToCache read. Caller owns the returned handle AND the
 nested TWcxSettings — the cleanup helper frees both.}
function MakeHandle(AFrameCount: Integer; AShowFrames, AShowCombined: Boolean): TArchiveHandle;
var
  Settings: TWcxSettings;
begin
  Settings := TWcxSettings.Create('');
  Settings.ResetDefaults;
  Settings.FramesCount := AFrameCount;
  Settings.ShowFrames := AShowFrames;
  Settings.ShowCombined := AShowCombined;
  Settings.SaveFormat := sfPNG;

  Result := TArchiveHandle.Create;
  Result.FileName := 'C:\v\sample.mkv';
  Result.Settings := Settings;
  Result.Offsets := MakeOffsets(AFrameCount);
  {Production wiring sets this in OpenArchive before PreExtractFrames;
   the extract-to-cache procedures write each bitmap through it.}
  Result.BitmapSaver := TVclBitmapSaverRouter.Create;
end;

procedure FreeHandleAndSettings(AHandle: TArchiveHandle);
begin
  if AHandle <> nil then
  begin
    if AHandle.Settings <> nil then
      AHandle.Settings.Free;
    AHandle.Free;
  end;
end;

{Single-test session lifecycle: acquire the singleton lock, allocate a
 fresh temp dir keyed by the handle's filename. Caller frees the
 returned Session (which releases the lock); the temp dir is wiped on
 the test's TearDown via Instance.Invalidate.}
function BeginPreparedSession(const AVideoName: string; AEntryCount: Integer): TWcxCacheExtractionSession;
begin
  Result := TWcxFrameCache.Instance.BeginExtractionSession;
  Result.PrepareFresh(AVideoName, AEntryCount);
end;

procedure TTestWcxExtractionController.SetUp;
begin
  TWcxFrameCache.ReleaseInstance;
end;

procedure TTestWcxExtractionController.TearDown;
begin
  TWcxFrameCache.Instance.Invalidate;
  TWcxFrameCache.ReleaseInstance;
end;

procedure TTestWcxExtractionController.TestExtractCombinedToCacheHappyPathFramesOnSlotAfterFrames;
var
  H: TArchiveHandle;
  Extractor: IFrameExtractor;
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
  CombinedSlot: Integer;
begin
  {ShowFrames=True puts the combined image AT slot Length(Offsets) —
   i.e., immediately after the per-frame slots. This contract is what
   TCombinedEntry depends on when looking up the cached path.}
  H := MakeHandle(2, True, True);
  try
    Extractor := TFakeExtractor.Create;
    Session := BeginPreparedSession(H.FileName, 3);
    try
      ExtractCombinedToCache(H, Extractor, Session);
      Session.PublishTo(Paths, Sizes);
      CombinedSlot := Length(H.Offsets);
      Assert.AreEqual(3, Integer(Length(Paths)));
      Assert.IsTrue(Paths[CombinedSlot] <> '', 'combined slot must be populated');
      Assert.IsTrue(Sizes[CombinedSlot] > 0, 'combined slot must record size');
      Assert.IsTrue(TFile.Exists(Paths[CombinedSlot]), 'combined file must exist on disk');
    finally
      Session.Free;
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.TestExtractCombinedToCacheFramesOffSlotZero;
var
  H: TArchiveHandle;
  Extractor: IFrameExtractor;
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
begin
  {With ShowFrames=False the combined image is the ONLY entry and
   lives at slot 0.}
  H := MakeHandle(2, False, True);
  try
    Extractor := TFakeExtractor.Create;
    Session := BeginPreparedSession(H.FileName, 1);
    try
      ExtractCombinedToCache(H, Extractor, Session);
      Session.PublishTo(Paths, Sizes);
      Assert.AreEqual(1, Integer(Length(Paths)));
      Assert.IsTrue(Paths[0] <> '');
      Assert.IsTrue(Sizes[0] > 0);
    finally
      Session.Free;
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.TestExtractCombinedToCacheNoOffsetsIsNoOp;
var
  H: TArchiveHandle;
  Extractor: TFakeExtractor;
  IExtractor: IFrameExtractor;
  Session: TWcxCacheExtractionSession;
begin
  {Empty offsets means RenderCombinedBitmap returns nil; the procedure
   must exit without recording any slot or writing any file.}
  H := MakeHandle(0, True, True);
  try
    Extractor := TFakeExtractor.Create;
    IExtractor := Extractor;
    Session := BeginPreparedSession(H.FileName, 1);
    try
      ExtractCombinedToCache(H, IExtractor, Session);
      Assert.AreEqual(0, Extractor.CallCount,
        'extractor must not be called when no offsets');
    finally
      Session.Free;
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.TestExtractSeparateToCacheHappyPathWritesEachFrame;
var
  H: TArchiveHandle;
  Extractor: TFakeExtractor;
  IExtractor: IFrameExtractor;
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
  I: Integer;
begin
  H := MakeHandle(3, True, False);
  try
    Extractor := TFakeExtractor.Create;
    IExtractor := Extractor;
    Session := BeginPreparedSession(H.FileName, 3);
    try
      ExtractSeparateToCache(H, IExtractor, Session);
      Session.PublishTo(Paths, Sizes);
      Assert.AreEqual(3, Extractor.CallCount, 'one extract call per offset');
      Assert.AreEqual(3, Integer(Length(Paths)));
      for I := 0 to 2 do
      begin
        Assert.IsTrue(Paths[I] <> '', Format('slot %d must be populated', [I]));
        Assert.IsTrue(Sizes[I] > 0, Format('slot %d must record size > 0', [I]));
        Assert.IsTrue(TFile.Exists(Paths[I]), Format('file for slot %d must exist', [I]));
      end;
    finally
      Session.Free;
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.TestExtractSeparateToCacheSkipsNilFrames;
var
  H: TArchiveHandle;
  Extractor: TFakeExtractor;
  IExtractor: IFrameExtractor;
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
begin
  {When the extractor returns nil for an offset, the procedure must
   continue to the next offset and leave the slot empty rather than
   crashing on the nil bitmap.}
  H := MakeHandle(2, True, False);
  try
    Extractor := TFakeExtractor.Create(0); {0 = return nil for first offset}
    IExtractor := Extractor;
    Session := BeginPreparedSession(H.FileName, 2);
    try
      ExtractSeparateToCache(H, IExtractor, Session);
      Session.PublishTo(Paths, Sizes);
      Assert.AreEqual(2, Extractor.CallCount);
      Assert.AreEqual('', Paths[0], 'nil-frame slot must stay empty');
      Assert.AreEqual(Int64(0), Sizes[0]);
      Assert.IsTrue(Paths[1] <> '', 'second slot still populated');
      Assert.IsTrue(Sizes[1] > 0);
    finally
      Session.Free;
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.TestExtractSeparateToCacheRoutesThroughInjectedRouter;
var
  H: TArchiveHandle;
  Extractor: IFrameExtractor;
  Router: TFakeBitmapSaverRouter;
  Session: TWcxCacheExtractionSession;
begin
  {Pins DIP-2: ExtractSeparateToCache must write through H.BitmapSaver,
   not the BitmapSaver.SaveBitmapToFile free function. A reverted
   controller would leave the fake's call count at zero.}
  H := MakeHandle(2, True, False);
  try
    Router := TFakeBitmapSaverRouter.Create;
    {Replaces the real router MakeHandle installs; the handle field then
     owns the fake via interface refcount.}
    H.BitmapSaver := Router;
    Extractor := TFakeExtractor.Create;
    Session := BeginPreparedSession(H.FileName, 2);
    try
      ExtractSeparateToCache(H, Extractor, Session);
      Assert.AreEqual(2, Router.SaveCallCount,
        'each frame must be written through the injected IBitmapSaverRouter');
    finally
      Session.Free;
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.PreExtract_CacheMiss_PublishesAllSlotsToHandle;
var
  H: TArchiveHandle;
  I: Integer;
begin
  {Frames + combined: LegacyEntryCount = 2 frame slots + 1 combined slot.
   A miss must extract everything and publish paths + sizes back onto
   the handle for ReadHeaderExW / ProcessFile to consume.}
  H := MakeHandle(2, True, True);
  try
    H.FrameExtractor := TFakeExtractor.Create;
    PreExtractFrames(H, TWcxFrameCache.Instance);
    Assert.AreEqual(3, Integer(Length(H.TempPaths)));
    Assert.AreEqual(3, Integer(Length(H.EntrySizes)));
    for I := 0 to 2 do
    begin
      Assert.IsTrue(H.TempPaths[I] <> '', Format('slot %d must be populated', [I]));
      Assert.IsTrue(H.EntrySizes[I] > 0, Format('slot %d must record size > 0', [I]));
      Assert.IsTrue(TFile.Exists(H.TempPaths[I]), Format('file for slot %d must exist', [I]));
    end;
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.PreExtract_CacheHit_ServesCachedPathsWithoutExtraction;
var
  H1, H2: TArchiveHandle;
  Extractor2: TFakeExtractor;
begin
  {Second open of the same video must take the cache-hit branch: the
   cached paths land on the new handle and the extractor is never asked
   for a single frame.}
  H1 := MakeHandle(2, True, True);
  try
    H1.FrameExtractor := TFakeExtractor.Create;
    PreExtractFrames(H1, TWcxFrameCache.Instance);
    Assert.IsTrue(H1.TempPaths[0] <> '', 'sanity: first open populated the cache');

    H2 := MakeHandle(2, True, True);
    try
      Extractor2 := TFakeExtractor.Create;
      H2.FrameExtractor := Extractor2;
      PreExtractFrames(H2, TWcxFrameCache.Instance);
      Assert.AreEqual(0, Extractor2.CallCount, 'cache hit must not re-extract');
      Assert.AreEqual(3, Integer(Length(H2.TempPaths)));
      Assert.AreEqual(H1.TempPaths[0], H2.TempPaths[0], 'hit must serve the cached paths');
      Assert.AreEqual(H1.TempPaths[2], H2.TempPaths[2]);
    finally
      FreeHandleAndSettings(H2);
    end;
  finally
    FreeHandleAndSettings(H1);
  end;
end;

procedure TTestWcxExtractionController.PreExtract_FramesOnly_PublishesFrameSlots;
var
  H: TArchiveHandle;
begin
  H := MakeHandle(2, True, False);
  try
    H.FrameExtractor := TFakeExtractor.Create;
    PreExtractFrames(H, TWcxFrameCache.Instance);
    Assert.AreEqual(2, Integer(Length(H.TempPaths)), 'no combined slot when ShowCombined=False');
    Assert.IsTrue(TFile.Exists(H.TempPaths[0]));
    Assert.IsTrue(TFile.Exists(H.TempPaths[1]));
  finally
    FreeHandleAndSettings(H);
  end;
end;

procedure TTestWcxExtractionController.PreExtract_CombinedOnly_PublishesSingleSlot;
var
  H: TArchiveHandle;
begin
  {ShowFrames=False: the combined image is the only entry, at slot 0.}
  H := MakeHandle(2, False, True);
  try
    H.FrameExtractor := TFakeExtractor.Create;
    PreExtractFrames(H, TWcxFrameCache.Instance);
    Assert.AreEqual(1, Integer(Length(H.TempPaths)));
    Assert.IsTrue(H.TempPaths[0] <> '', 'combined-only entry must land at slot 0');
    Assert.IsTrue(H.EntrySizes[0] > 0);
    Assert.IsTrue(TFile.Exists(H.TempPaths[0]));
  finally
    FreeHandleAndSettings(H);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxExtractionController);

end.
