{Tests for TExtractionThread.
 The thread orchestrates frame extraction through the IFrameExtractor +
 IFrameCache contract and publishes results into a shared queue. Tests
 here inject fake implementations of both interfaces so the orchestration
 is exercised without touching ffmpeg or the disk cache.

 Fakes are deliberately minimal: in-memory canned bitmaps keyed by time
 offset, plus Put/TryGet call counters that the test thread reads only
 after Thread.WaitFor (which provides the necessary memory barrier).}
unit TestExtractionWorker;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExtractionThread = class
  public
    [Test] procedure PlainFlow_DeliversFramesInOrder;
    [Test] procedure PlainFlow_MapsIndexOneBasedToCellIndexZeroBased;
    [Test] procedure CacheHit_SkipsExtractor;
    [Test] procedure CacheHit_DoesNotCallPut;
    [Test] procedure CacheMiss_CallsExtractorAndPutsResult;
    [Test] procedure ExtractorException_EnqueuesNilBitmap;
    [Test] procedure ActiveWorkerCount_DecrementsToZero;
    [Test] procedure TerminateBeforeStart_ProducesEmptyQueue;
  end;

implementation

uses
  System.Classes, System.SysUtils, System.Math, System.SyncObjs,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Graphics,
  uTypes, uFrameOffsets, uFrameExtractor, uCache, uExtractionWorker;

type
  {In-memory fake extractor. Returns a fresh bitmap per call (caller owns).
   Canned frames are keyed by exact time offset; offsets the test didn't
   seed trigger ERROR_NOT_SEEDED or an optional exception.}
  TFakeExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FColorByOffset: TDictionary<Double, TColor>;
    FThrowAtOffset: Double;
    FShouldThrow: Boolean;
    FCallCount: Integer;
    FSeenOffsets: TList<Double>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddFrame(AOffset: Double; AColor: TColor);
    procedure ThrowAt(AOffset: Double);
    property CallCount: Integer read FCallCount;
    function SeenOffsets: TArray<Double>;
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  {In-memory fake cache. Seeded offsets return a clone on TryGet; everything
   else misses. Put calls are counted for cache-miss-writes assertions.}
  TFakeCache = class(TFrameCacheBase)
  strict private
    FSeeded: TDictionary<Double, TColor>;
    FGetCalls: Integer;
    FPutCalls: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Seed(AOffset: Double; AColor: TColor);
    property GetCalls: Integer read FGetCalls;
    property PutCalls: Integer read FPutCalls;
    function TryGet(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer; AUseKeyframes: Boolean): TBitmap; override;
    procedure Put(const AFilePath: string; ATimeOffset: Double; ABitmap: TBitmap;
      AMaxSide: Integer; AUseKeyframes: Boolean); override;
  end;

function MakeSolidBitmap(AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(8, 8);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(Rect(0, 0, 8, 8));
end;

{TFakeExtractor}

constructor TFakeExtractor.Create;
begin
  inherited;
  FColorByOffset := TDictionary<Double, TColor>.Create;
  FSeenOffsets := TList<Double>.Create;
  FShouldThrow := False;
end;

destructor TFakeExtractor.Destroy;
begin
  FColorByOffset.Free;
  FSeenOffsets.Free;
  inherited;
end;

procedure TFakeExtractor.AddFrame(AOffset: Double; AColor: TColor);
begin
  FColorByOffset.AddOrSetValue(AOffset, AColor);
end;

procedure TFakeExtractor.ThrowAt(AOffset: Double);
begin
  FThrowAtOffset := AOffset;
  FShouldThrow := True;
end;

function TFakeExtractor.SeenOffsets: TArray<Double>;
begin
  Result := FSeenOffsets.ToArray;
end;

function TFakeExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
var
  Color: TColor;
begin
  Inc(FCallCount);
  FSeenOffsets.Add(ATimeOffset);
  if FShouldThrow and SameValue(ATimeOffset, FThrowAtOffset) then
    raise Exception.CreateFmt('Simulated failure at offset %f', [ATimeOffset]);
  if FColorByOffset.TryGetValue(ATimeOffset, Color) then
    Result := MakeSolidBitmap(Color)
  else
    Result := nil;
end;

{TFakeCache}

constructor TFakeCache.Create;
begin
  inherited;
  FSeeded := TDictionary<Double, TColor>.Create;
end;

destructor TFakeCache.Destroy;
begin
  FSeeded.Free;
  inherited;
end;

procedure TFakeCache.Seed(AOffset: Double; AColor: TColor);
begin
  FSeeded.AddOrSetValue(AOffset, AColor);
end;

function TFakeCache.TryGet(const AFilePath: string; ATimeOffset: Double;
  AMaxSide: Integer; AUseKeyframes: Boolean): TBitmap;
var
  Color: TColor;
begin
  Inc(FGetCalls);
  if FSeeded.TryGetValue(ATimeOffset, Color) then
    Result := MakeSolidBitmap(Color)
  else
    Result := nil;
end;

procedure TFakeCache.Put(const AFilePath: string; ATimeOffset: Double;
  ABitmap: TBitmap; AMaxSide: Integer; AUseKeyframes: Boolean);
begin
  Inc(FPutCalls);
  {Fake does not retain the bitmap — ownership stays with the worker,
   which passes the same reference on to the queue.}
end;

function DefaultOptions: TExtractionOptions;
begin
  Result := Default(TExtractionOptions);
  Result.UseBmpPipe := True;
end;

function BuildOffsets(const ATimes: array of Double): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, Length(ATimes));
  for I := 0 to High(ATimes) do
  begin
    {Index is 1-based in TFrameOffset — the worker normalises to 0-based
     CellIdx via "Index - 1". Pass indices here so the mapping is visible
     in the test, not assumed.}
    Result[I].Index := I + 1;
    Result[I].TimeOffset := ATimes[I];
  end;
end;

{Runs a single TExtractionThread to completion. Returns the frames
 collected in the queue, the extractor's call count, and the final
 ActiveWorkerCount value. Caller owns the returned bitmaps.}
procedure RunWorker(const AExtractor: IFrameExtractor; const ACache: IFrameCache;
  const AOffsets: TFrameOffsetArray; out AFrames: TArray<TPendingFrame>;
  out AFinalActiveCount: Integer);
var
  Queue: TList<TPendingFrame>;
  Lock: TCriticalSection;
  Thread: TExtractionThread;
  ActiveCount: Integer;
  I: Integer;
begin
  Queue := TList<TPendingFrame>.Create;
  Lock := TCriticalSection.Create;
  try
    ActiveCount := 1;
    Thread := TExtractionThread.Create(AExtractor, 'anywhere.mp4',
      AOffsets, 0, Queue, Lock, ACache, @ActiveCount, DefaultOptions);
    try
      Thread.Start;
      Thread.WaitFor;
    finally
      Thread.Free;
    end;
    AFinalActiveCount := ActiveCount;
    SetLength(AFrames, Queue.Count);
    for I := 0 to Queue.Count - 1 do
      AFrames[I] := Queue[I];
  finally
    Queue.Free;
    Lock.Free;
  end;
end;

procedure FreeFrames(const AFrames: TArray<TPendingFrame>);
var
  I: Integer;
begin
  for I := 0 to High(AFrames) do
    AFrames[I].Bitmap.Free;
end;

{TTestExtractionThread}

procedure TTestExtractionThread.PlainFlow_DeliversFramesInOrder;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: IFrameCache;
  Frames: TArray<TPendingFrame>;
  ActiveCount: Integer;
begin
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.AddFrame(0.0, clRed);
  Extractor.AddFrame(1.5, clGreen);
  Extractor.AddFrame(3.0, clBlue);
  Cache := TNullFrameCache.Create;

  RunWorker(ExtractorRef, Cache, BuildOffsets([0.0, 1.5, 3.0]),
    Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(3, Length(Frames),
      'All three offsets must land in the queue');
    Assert.AreEqual<Integer>(0, Frames[0].Index);
    Assert.AreEqual<Integer>(1, Frames[1].Index);
    Assert.AreEqual<Integer>(2, Frames[2].Index);
    Assert.IsNotNull(Frames[0].Bitmap, 'Frame 0 must be non-nil on happy path');
    Assert.IsNotNull(Frames[1].Bitmap);
    Assert.IsNotNull(Frames[2].Bitmap);
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.PlainFlow_MapsIndexOneBasedToCellIndexZeroBased;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: IFrameCache;
  Frames: TArray<TPendingFrame>;
  Offsets: TFrameOffsetArray;
  ActiveCount: Integer;
begin
  {Regression guard: FOffsets[I].Index is 1-based by convention (matches the
   planner output) but the queue uses 0-based cell indices. An accidental
   removal of the "- 1" in Execute would put frames into the wrong cells.}
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.AddFrame(10.0, clRed);
  Extractor.AddFrame(20.0, clGreen);
  Cache := TNullFrameCache.Create;

  Offsets := BuildOffsets([10.0, 20.0]);
  Offsets[0].Index := 7;  {non-sequential 1-based index}
  Offsets[1].Index := 9;
  RunWorker(ExtractorRef, Cache, Offsets, Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(6, Frames[0].Index, 'Index 7 must map to cell 6');
    Assert.AreEqual<Integer>(8, Frames[1].Index, 'Index 9 must map to cell 8');
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.CacheHit_SkipsExtractor;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: TFakeCache;
  CacheRef: IFrameCache;
  Frames: TArray<TPendingFrame>;
  ActiveCount: Integer;
begin
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Cache := TFakeCache.Create;
  CacheRef := Cache;
  Cache.Seed(0.0, clYellow);
  Cache.Seed(5.0, clLime);

  RunWorker(ExtractorRef, CacheRef, BuildOffsets([0.0, 5.0]),
    Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(2, Length(Frames));
    Assert.AreEqual<Integer>(0, Extractor.CallCount,
      'Extractor must not be called on cache hits');
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.CacheHit_DoesNotCallPut;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: TFakeCache;
  CacheRef: IFrameCache;
  Frames: TArray<TPendingFrame>;
  ActiveCount: Integer;
begin
  {When the cache hits we must not re-Put the frame we just read — that
   would pointlessly rewrite an identical entry and, for a real disk
   cache, re-touch its LRU timestamp on reads rather than writes.}
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Cache := TFakeCache.Create;
  CacheRef := Cache;
  Cache.Seed(0.0, clAqua);

  RunWorker(ExtractorRef, CacheRef, BuildOffsets([0.0]),
    Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(0, Cache.PutCalls,
      'Cache hits must not trigger Put');
    Assert.AreEqual<Integer>(1, Cache.GetCalls,
      'TryGet must still be called on cache hits');
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.CacheMiss_CallsExtractorAndPutsResult;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: TFakeCache;
  CacheRef: IFrameCache;
  Frames: TArray<TPendingFrame>;
  ActiveCount: Integer;
begin
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.AddFrame(2.0, clRed);
  Cache := TFakeCache.Create;
  CacheRef := Cache;
  {No seed: TryGet returns nil for all offsets.}

  RunWorker(ExtractorRef, CacheRef, BuildOffsets([2.0]),
    Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(1, Extractor.CallCount);
    Assert.AreEqual<Integer>(1, Cache.PutCalls,
      'Successful extraction must be written back to the cache');
    Assert.IsNotNull(Frames[0].Bitmap);
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.ExtractorException_EnqueuesNilBitmap;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: TFakeCache;
  CacheRef: IFrameCache;
  Frames: TArray<TPendingFrame>;
  ActiveCount: Integer;
begin
  {The worker's except block swallows the error and enqueues a nil bitmap
   as an error sentinel. Siblings must continue to be processed. If that
   behaviour ever changes to "stop on first error", this test flags it.}
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.AddFrame(0.0, clRed);
  Extractor.AddFrame(2.0, clBlue);
  Extractor.ThrowAt(1.0);
  Cache := TFakeCache.Create;
  CacheRef := Cache;

  RunWorker(ExtractorRef, CacheRef, BuildOffsets([0.0, 1.0, 2.0]),
    Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(3, Length(Frames),
      'All three offsets must still reach the queue — error becomes a nil sentinel');
    Assert.IsNotNull(Frames[0].Bitmap, 'Offset 0.0 must succeed');
    Assert.IsNull(Frames[1].Bitmap, 'Offset 1.0 threw and must enqueue nil');
    Assert.IsNotNull(Frames[2].Bitmap, 'Offset 2.0 must succeed after the error');
    Assert.AreEqual<Integer>(2, Cache.PutCalls,
      'Only the two successful extractions must be cached');
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.ActiveWorkerCount_DecrementsToZero;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: IFrameCache;
  Frames: TArray<TPendingFrame>;
  ActiveCount: Integer;
begin
  {The shared ActiveWorkerCount is how the form knows when every worker
   has finished. A leaked increment would mean the "extraction done"
   notification never fires.}
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.AddFrame(0.0, clRed);
  Cache := TNullFrameCache.Create;

  RunWorker(ExtractorRef, Cache, BuildOffsets([0.0]),
    Frames, ActiveCount);
  try
    Assert.AreEqual<Integer>(0, ActiveCount,
      'Single-worker run must leave ActiveCount at zero');
  finally
    FreeFrames(Frames);
  end;
end;

procedure TTestExtractionThread.TerminateBeforeStart_ProducesEmptyQueue;
var
  Extractor: TFakeExtractor;
  ExtractorRef: IFrameExtractor;
  Cache: IFrameCache;
  Queue: TList<TPendingFrame>;
  Lock: TCriticalSection;
  Thread: TExtractionThread;
  ActiveCount: Integer;
  I: Integer;
begin
  {Calling Terminate on a suspended thread sets FTerminated; when Start
   resumes execution, the main loop's "if Terminated then Exit" check
   short-circuits immediately. The queue must stay empty and the
   extractor must never be called.

   Note on ActiveWorkerCount: whether Execute runs at all in the
   Terminate-before-Start case is an RTL implementation detail (Delphi's
   TThread may short-circuit resumption). If Execute never runs, the
   finally block never runs either and the caller is responsible for
   reconciling ActiveCount. This is acceptable in production because
   the plugin never calls Terminate on a thread that hasn't been
   Start-ed — so we don't assert on ActiveCount here.}
  Extractor := TFakeExtractor.Create;
  ExtractorRef := Extractor;
  Extractor.AddFrame(0.0, clRed);
  Extractor.AddFrame(1.0, clBlue);
  Cache := TNullFrameCache.Create;

  Queue := TList<TPendingFrame>.Create;
  Lock := TCriticalSection.Create;
  try
    ActiveCount := 1;
    Thread := TExtractionThread.Create(ExtractorRef, 'anywhere.mp4',
      BuildOffsets([0.0, 1.0]), 0, Queue, Lock, Cache, @ActiveCount,
      DefaultOptions);
    try
      Thread.Terminate;
      Thread.Start;
      Thread.WaitFor;
    finally
      Thread.Free;
    end;
    Assert.AreEqual<Integer>(0, Queue.Count,
      'Early terminate must leave the queue empty');
    Assert.AreEqual<Integer>(0, Extractor.CallCount,
      'Extractor must not be called when the thread starts already terminated');
  finally
    for I := 0 to Queue.Count - 1 do
      Queue[I].Bitmap.Free;
    Queue.Free;
    Lock.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExtractionThread);

end.
