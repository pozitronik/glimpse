unit TestExtractionController;

interface

uses
  DUnitX.TestFramework, Vcl.Graphics;

type
  [TestFixture]
  TTestExtractionController = class
  strict private
    FDeliveredIndices: array of Integer;
    FDeliveredCount: Integer;
    FNilBitmapDeliveries: Integer;
    FProgressCount: Integer;
    procedure HandleFrame(AIndex: Integer; ABitmap: TBitmap);
    procedure HandleProgress(Sender: TObject);
  public
    [Setup] procedure Setup;

    [Test] procedure TestCreateDestroy;
    [Test] procedure TestStopWhenNoThreads;
    [Test] procedure TestDrainWhenEmpty;
    [Test] procedure TestRecreateCacheEnabled;
    [Test] procedure TestRecreateCacheDisabled;
    [Test] procedure TestInitialFramesLoadedZero;
    [Test] procedure TestInitialTotalFramesZero;

    {Start + Stop + ProcessPendingFrames orchestration. Uses a stub
     IFrameExtractor that hands back canned pf24bit bitmaps; the real
     ffmpeg pipeline is exercised by TestRunProcess and the end-to-end
     extraction is verified by manual integration. These tests cover
     the controller's threading + queue mechanics without ffmpeg.}
    [Test] procedure TestStartSetsTotalFrames;
    [Test] procedure TestStartThenProcessDeliversEveryFrame;
    [Test] procedure TestStartThenProcessIncrementsFramesLoaded;
    [Test] procedure TestStartThenProcessFiresProgressOnce;
    [Test] procedure TestStartTwiceCleansUpFirstRun;
    [Test] procedure TestExtractorErrorDeliversNilBitmap;
    [Test] procedure TestStopBeforeProcessFreesQueuedBitmaps;
    {IFrameNotificationSink contract: capture sink records every signal
     so the worker -> sink wiring is observable headlessly.}
    [Test] procedure TestSinkReceivesFramesReadyDuringExtraction;
    [Test] procedure TestSinkReceivesExtractionDoneFromLastWorker;
    [Test] procedure TestDrainPendingDelegatesToSink;
  end;

implementation

uses
  System.SysUtils, System.SyncObjs, System.IOUtils, System.Math, System.Diagnostics,
  System.Generics.Collections,
  Types, FrameOffsets, FrameExtractor, Cache, ExtractionController,
  FrameNotificationSink;

type
  {Capture-only IFrameNotificationSink: tallies NotifyFramesReady,
   NotifyExtractionDone, and DrainPending calls. Tracked under a lock
   because NotifyFramesReady fires from worker threads.}
  TCaptureSink = class(TInterfacedObject, IFrameNotificationSink)
  strict private
    FLock: TCriticalSection;
    FFramesReadyCount: Integer;
    FExtractionDoneCount: Integer;
    FDrainCount: Integer;
    function ReadInt(var AField: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure NotifyFramesReady;
    procedure NotifyExtractionDone;
    procedure DrainPending;
    function FramesReadyCount: Integer;
    function ExtractionDoneCount: Integer;
    function DrainCount: Integer;
  end;

type
  {Stub frame extractor: returns a fresh 4x4 pf24bit bitmap for any
   offset, or nil for offsets explicitly marked as failures. Each
   ExtractFrame call increments a counter so tests can assert how many
   times ffmpeg would have been invoked. Workers free the returned
   bitmaps via the controller's queue, so each call must hand out a
   distinct instance.}
  TStubExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FCallCount: Integer;
    FFailOffsets: TList<Double>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure FailAt(AOffset: Double);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
    property CallCount: Integer read FCallCount;
  end;

constructor TStubExtractor.Create;
begin
  inherited Create;
  FFailOffsets := TList<Double>.Create;
end;

destructor TStubExtractor.Destroy;
begin
  FFailOffsets.Free;
  inherited;
end;

procedure TStubExtractor.FailAt(AOffset: Double);
begin
  FFailOffsets.Add(AOffset);
end;

function TStubExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
var
  I: Integer;
begin
  Inc(FCallCount);
  for I := 0 to FFailOffsets.Count - 1 do
    if SameValue(FFailOffsets[I], ATimeOffset) then
      Exit(nil);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(4, 4);
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

function DefaultOptions: TExtractionOptions;
begin
  Result := Default(TExtractionOptions);
  Result.UseBmpPipe := True;
end;

{Polls AStub.CallCount until it reaches AExpected or ATimeoutMs
 elapses, sleeping 5 ms between checks. Without this synchronisation,
 calling Stop right after Start can Terminate the workers before
 they have run their full chunk; they exit at the next Terminated
 check, leaving some offsets unenqueued. Once CallCount = expected,
 every offset has been pulled from the stub and the worker has
 already pushed the frame onto FPendingFrames; Stop after that
 point is a clean join.}
procedure WaitForExtractionCompletion(AStub: TStubExtractor; AExpected, ATimeoutMs: Integer);
var
  SW: TStopwatch;
begin
  SW := TStopwatch.StartNew;
  while AStub.CallCount < AExpected do
  begin
    if SW.ElapsedMilliseconds > ATimeoutMs then
      raise Exception.CreateFmt(
        'Extractor was called only %d/%d times within %d ms',
        [AStub.CallCount, AExpected, ATimeoutMs]);
    Sleep(5);
  end;
end;

{ TTestExtractionController }

procedure TTestExtractionController.Setup;
begin
  SetLength(FDeliveredIndices, 0);
  FDeliveredCount := 0;
  FNilBitmapDeliveries := 0;
  FProgressCount := 0;
end;

procedure TTestExtractionController.HandleFrame(AIndex: Integer; ABitmap: TBitmap);
begin
  SetLength(FDeliveredIndices, Length(FDeliveredIndices) + 1);
  FDeliveredIndices[High(FDeliveredIndices)] := AIndex;
  Inc(FDeliveredCount);
  if ABitmap = nil then
    Inc(FNilBitmapDeliveries)
  else
    {OnFrameDelivered receives ownership: production routes the bitmap to
     FFrameView.SetFrame, which copies and frees. The test has no view, so
     it frees here to satisfy DUnitX's leak detector.}
    ABitmap.Free;
end;

procedure TTestExtractionController.HandleProgress(Sender: TObject);
begin
  Inc(FProgressCount);
end;

procedure TTestExtractionController.TestCreateDestroy;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Assert.IsNotNull(Ctrl);
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStopWhenNoThreads;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    { Stop with no running threads must not crash }
    Ctrl.Stop;
    Ctrl.Stop;
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestDrainWhenEmpty;
var
  Ctrl: TExtractionController;
begin
  { FormHandle=0 skips PeekMessage calls }
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Ctrl.DrainPendingFrameMessages;
    Ctrl.DrainPendingFrameMessages;
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestRecreateCacheEnabled;
var
  Ctrl: TExtractionController;
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'glimpse_ctrl_test_' + IntToStr(Random(MaxInt)));
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Ctrl.RecreateCache(True, Dir, 100);
    { After recreation, cache should be functional (not null) }
    Assert.IsNotNull(Ctrl.Cache);
    { Put/TryGet round-trip is verified by TestCache, here just check
      the controller wired it correctly }
  finally
    Ctrl.Free;
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestExtractionController.TestRecreateCacheDisabled;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Ctrl.RecreateCache(False, '', 0);
    { Null cache always misses }
    Assert.IsNull(Ctrl.Cache.TryGet(TFrameCacheKey.Create('nonexistent.mp4', 1.0, 0, False)));
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestInitialFramesLoadedZero;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Assert.AreEqual(0, Ctrl.FramesLoaded);
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestInitialTotalFramesZero;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Assert.AreEqual(0, Ctrl.TotalFrames);
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStartSetsTotalFrames;
var
  Ctrl: TExtractionController;
  Stub: TStubExtractor;
  StubIface: IFrameExtractor;
begin
  Stub := TStubExtractor.Create;
  StubIface := Stub;
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Ctrl.Start(StubIface, 'fake.mp4', MakeOffsets(7), 2, 1, DefaultOptions);
    Assert.AreEqual(7, Ctrl.TotalFrames,
      'TotalFrames must reflect the offset array length');
    WaitForExtractionCompletion(Stub, 7, 5000);
    Ctrl.Stop;
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStartThenProcessDeliversEveryFrame;
var
  Ctrl: TExtractionController;
  Stub: TStubExtractor;
  StubIface: IFrameExtractor;
  Seen: array [0 .. 4] of Boolean;
  I: Integer;
begin
  Stub := TStubExtractor.Create;
  StubIface := Stub;
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  Ctrl.OnFrameDelivered := HandleFrame;
  try
    Ctrl.Start(StubIface, 'fake.mp4', MakeOffsets(5), 2, 1, DefaultOptions);
    WaitForExtractionCompletion(Stub, 5, 5000);
    Ctrl.Stop;
    Ctrl.ProcessPendingFrames;

    Assert.AreEqual(5, FDeliveredCount,
      'Every offset must have surfaced exactly once via OnFrameDelivered');
    {Workers map FOffsets[I].Index (1-based) -> CellIdx (0-based). Every
     0..4 must be present without duplicates regardless of worker order.}
    for I := Low(Seen) to High(Seen) do
      Seen[I] := False;
    for I := 0 to High(FDeliveredIndices) do
    begin
      Assert.IsTrue((FDeliveredIndices[I] >= 0) and (FDeliveredIndices[I] <= 4),
        Format('Delivered index %d out of range', [FDeliveredIndices[I]]));
      Assert.IsFalse(Seen[FDeliveredIndices[I]],
        Format('Index %d delivered twice', [FDeliveredIndices[I]]));
      Seen[FDeliveredIndices[I]] := True;
    end;
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStartThenProcessIncrementsFramesLoaded;
var
  Ctrl: TExtractionController;
  Stub: TStubExtractor;
  StubIface: IFrameExtractor;
begin
  Stub := TStubExtractor.Create;
  StubIface := Stub;
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  {OnFrameDelivered must be wired so HandleFrame can free each bitmap;
   without a consumer ProcessPendingFrames leaks every Snapshot entry.}
  Ctrl.OnFrameDelivered := HandleFrame;
  try
    Ctrl.Start(StubIface, 'fake.mp4', MakeOffsets(4), 2, 1, DefaultOptions);
    WaitForExtractionCompletion(Stub, 4, 5000);
    Ctrl.Stop;
    Assert.AreEqual(0, Ctrl.FramesLoaded,
      'FramesLoaded counts only delivered frames; ProcessPendingFrames pending');
    Ctrl.ProcessPendingFrames;
    Assert.AreEqual(4, Ctrl.FramesLoaded,
      'FramesLoaded must equal TotalFrames after the queue drains');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStartThenProcessFiresProgressOnce;
var
  Ctrl: TExtractionController;
  Stub: TStubExtractor;
  StubIface: IFrameExtractor;
begin
  Stub := TStubExtractor.Create;
  StubIface := Stub;
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  Ctrl.OnFrameDelivered := HandleFrame;
  Ctrl.OnProgress := HandleProgress;
  try
    Ctrl.Start(StubIface, 'fake.mp4', MakeOffsets(3), 2, 1, DefaultOptions);
    WaitForExtractionCompletion(Stub, 3, 5000);
    Ctrl.Stop;
    {Single drain delivers all frames in one batch -> one progress tick.
     A second drain on an empty queue must not fire OnProgress.}
    Ctrl.ProcessPendingFrames;
    Assert.AreEqual(1, FProgressCount, 'Progress must fire once per non-empty drain');
    Ctrl.ProcessPendingFrames;
    Assert.AreEqual(1, FProgressCount, 'Empty drain must not fire OnProgress');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStartTwiceCleansUpFirstRun;
var
  Ctrl: TExtractionController;
  Stub1, Stub2: TStubExtractor;
  StubIface1, StubIface2: IFrameExtractor;
begin
  Stub1 := TStubExtractor.Create;
  StubIface1 := Stub1;
  Stub2 := TStubExtractor.Create;
  StubIface2 := Stub2;
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  Ctrl.OnFrameDelivered := HandleFrame;
  try
    {Start internally calls Stop on any previous run. Two consecutive
     Start calls with different offset counts must end in the second
     run's TotalFrames; the first run's queued bitmaps are freed by
     Start's drain so no leak surfaces in DUnitX's leak detector.}
    Ctrl.Start(StubIface1, 'fake.mp4', MakeOffsets(3), 1, 1, DefaultOptions);
    WaitForExtractionCompletion(Stub1, 3, 5000);
    Ctrl.Stop;
    Ctrl.ProcessPendingFrames;
    SetLength(FDeliveredIndices, 0);
    FDeliveredCount := 0;

    Ctrl.Start(StubIface2, 'fake.mp4', MakeOffsets(2), 1, 1, DefaultOptions);
    Assert.AreEqual(2, Ctrl.TotalFrames);
    WaitForExtractionCompletion(Stub2, 2, 5000);
    Ctrl.Stop;
    Ctrl.ProcessPendingFrames;
    Assert.AreEqual(2, FDeliveredCount);
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestExtractorErrorDeliversNilBitmap;
var
  Ctrl: TExtractionController;
  Stub: TStubExtractor;
  StubIface: IFrameExtractor;
begin
  Stub := TStubExtractor.Create;
  StubIface := Stub;
  Stub.FailAt(2.0); {second offset's TimeOffset; see MakeOffsets}
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  Ctrl.OnFrameDelivered := HandleFrame;
  try
    Ctrl.Start(StubIface, 'fake.mp4', MakeOffsets(3), 1, 1, DefaultOptions);
    WaitForExtractionCompletion(Stub, 3, 5000);
    Ctrl.Stop;
    Ctrl.ProcessPendingFrames;

    {Worker enqueues every frame including failures (Bitmap=nil signals
     "extraction error" to the UI; renderer shows the error placeholder).}
    Assert.AreEqual(3, FDeliveredCount,
      'Worker must enqueue an entry per offset, even on extractor failure');
    Assert.AreEqual(1, FNilBitmapDeliveries,
      'The failing offset must surface as a nil-bitmap delivery (UI placeholder)');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStopBeforeProcessFreesQueuedBitmaps;
var
  Ctrl: TExtractionController;
  Stub: TStubExtractor;
  StubIface: IFrameExtractor;
begin
  {Without DrainPendingFrameMessages or ProcessPendingFrames, the queue
   would hold owned bitmaps until destructor. The destructor calls
   DrainPendingFrameMessages, freeing them. DUnitX's leak detector flags
   any surviving TBitmap, so a clean test run proves the cleanup path.}
  Stub := TStubExtractor.Create;
  StubIface := Stub;
  Ctrl := TExtractionController.Create(nil, TNullFrameCache.Create);
  try
    Ctrl.Start(StubIface, 'fake.mp4', MakeOffsets(4), 2, 1, DefaultOptions);
    WaitForExtractionCompletion(Stub, 4, 5000);
    Ctrl.Stop;
    {Intentionally skip ProcessPendingFrames to leave bitmaps queued.}
  finally
    Ctrl.Free;
  end;
  Assert.Pass('Destructor drained the queue without leaking bitmaps');
end;

{ TCaptureSink }

constructor TCaptureSink.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TCaptureSink.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TCaptureSink.NotifyFramesReady;
begin
  FLock.Enter;
  try
    Inc(FFramesReadyCount);
  finally
    FLock.Leave;
  end;
end;

procedure TCaptureSink.NotifyExtractionDone;
begin
  FLock.Enter;
  try
    Inc(FExtractionDoneCount);
  finally
    FLock.Leave;
  end;
end;

procedure TCaptureSink.DrainPending;
begin
  FLock.Enter;
  try
    Inc(FDrainCount);
  finally
    FLock.Leave;
  end;
end;

function TCaptureSink.ReadInt(var AField: Integer): Integer;
begin
  FLock.Enter;
  try
    Result := AField;
  finally
    FLock.Leave;
  end;
end;

function TCaptureSink.FramesReadyCount: Integer;
begin
  Result := ReadInt(FFramesReadyCount);
end;

function TCaptureSink.ExtractionDoneCount: Integer;
begin
  Result := ReadInt(FExtractionDoneCount);
end;

function TCaptureSink.DrainCount: Integer;
begin
  Result := ReadInt(FDrainCount);
end;

procedure TTestExtractionController.TestSinkReceivesFramesReadyDuringExtraction;
var
  Sink: TCaptureSink;
  SinkRef: IFrameNotificationSink;
  Ctrl: TExtractionController;
  Extractor: IFrameExtractor;
begin
  Sink := TCaptureSink.Create;
  SinkRef := Sink; {Hold interface ref for the duration of the test.}
  Extractor := TStubExtractor.Create;
  Ctrl := TExtractionController.Create(SinkRef, TNullFrameCache.Create);
  try
    Ctrl.Start(Extractor, 'anywhere.mp4', MakeOffsets(3), 1, 1, DefaultOptions);
    {Wait until the worker has signalled at least once or up to ~1s.}
    while (Sink.FramesReadyCount = 0) do
      Sleep(5);
    Ctrl.Stop;
    Assert.IsTrue(Sink.FramesReadyCount > 0,
      'Worker must call NotifyFramesReady at least once during extraction');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestSinkReceivesExtractionDoneFromLastWorker;
var
  Sink: TCaptureSink;
  SinkRef: IFrameNotificationSink;
  Ctrl: TExtractionController;
  Extractor: IFrameExtractor;
  Waited: Integer;
begin
  Sink := TCaptureSink.Create;
  SinkRef := Sink;
  Extractor := TStubExtractor.Create;
  Ctrl := TExtractionController.Create(SinkRef, TNullFrameCache.Create);
  try
    Ctrl.Start(Extractor, 'anywhere.mp4', MakeOffsets(2), 1, 1, DefaultOptions);
    {Poll for the signal up to ~1s. The worker thread races with the
     test thread; waiting on a deterministic signal is more reliable
     than calling Stop immediately and assuming WaitFor + finally
     ordering produced the call before the assertion ran.}
    Waited := 0;
    while (Sink.ExtractionDoneCount = 0) and (Waited < 1000) do
    begin
      Sleep(10);
      Inc(Waited, 10);
    end;
    Ctrl.Stop;
    Assert.AreEqual(1, Sink.ExtractionDoneCount,
      'Last worker must signal NotifyExtractionDone exactly once per extraction');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestDrainPendingDelegatesToSink;
var
  Sink: TCaptureSink;
  SinkRef: IFrameNotificationSink;
  Ctrl: TExtractionController;
begin
  Sink := TCaptureSink.Create;
  SinkRef := Sink;
  Ctrl := TExtractionController.Create(SinkRef, TNullFrameCache.Create);
  try
    Ctrl.DrainPendingFrameMessages;
    Assert.AreEqual(1, Sink.DrainCount,
      'DrainPendingFrameMessages must invoke ISink.DrainPending');
  finally
    Ctrl.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExtractionController);

end.
