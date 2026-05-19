{Tests for ExtractSeparateToCache and ExtractCombinedToCache. Both
 procedures write real files into a TWcxCacheExtractionSession-owned
 temp dir and record slot metadata back to the session. The full
 PreExtractFrames orchestration (which couples to the TWcxFrameCache
 singleton) is exercised indirectly via TestWcxArchiveCoordinator.}
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
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, Vcl.Graphics,
  Types, BitmapSaver, FrameExtractor, FrameOffsets, VideoInfo,
  WcxAPI, WcxSettings, WcxArchiveHandle,
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

initialization
  TDUnitX.RegisterTestFixture(TTestWcxExtractionController);

end.
