{Worker thread that extracts video frames via ffmpeg.exe. Results go to
 a thread-safe queue; an injected sink decides how to notify (Win32
 PostMessage in production, in-memory capture in tests).}
unit ExtractionWorker;

interface

uses
  System.Classes, System.SyncObjs, System.Generics.Collections,
  Vcl.Graphics,
  FrameOffsets, FrameExtractor, Cache, Types,
  FrameNotificationSink;

type
  {A frame result passed from a worker thread to TExtractionController
   through the shared pending-frame queue.}
  TPendingFrame = record
    Index: Integer;
    {Heap bitmap (nil signals an extraction error). On enqueue, ownership
     passes to TExtractionController: ProcessPendingFrames transfers it to
     OnFrameDelivered, DrainPendingFrameMessages frees any left undelivered.
     A worker frees Bitmap itself only when it cannot enqueue (cancel or
     exception before FQueue.Add).}
    Bitmap: TBitmap;
  end;

  TExtractionThread = class(TThread)
  private
    FExtractor: IFrameExtractor;
    FFileName: string;
    FOffsets: TFrameOffsetArray;
    FSink: IFrameNotificationSink;
    {Shared pending-frame queue and its lock, both owned by
     TExtractionController. The worker only appends; the controller drains
     the queue and frees the queued bitmaps, so TExtractionThread.Destroy
     must not touch FQueue.}
    FQueue: TList<TPendingFrame>;
    FQueueLock: TCriticalSection;
    FCache: IFrameCache;
    {Shared counter; last thread to decrement calls NotifyExtractionDone.}
    FActiveWorkerCount: PInteger;
    FOptions: TExtractionOptions;
    {Signalled from TerminatedSet so a blocking ffmpeg call can be
     unblocked mid-run.}
    FCancelEvent: TEvent;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(const AExtractor: IFrameExtractor; const AFileName: string; const AOffsets: TFrameOffsetArray; const ASink: IFrameNotificationSink; AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection; const ACache: IFrameCache; AActiveWorkerCount: PInteger; const AOptions: TExtractionOptions);
    destructor Destroy; override;
  end;

{Returns True for the last worker. ATerminated is documentation only:
 even cancelled runs must signal completion because the controller
 drains stale signals on the next extraction, but missing the signal
 on cancel would hang the UI.}
function ShouldPostDone(AIsLastWorker, ATerminated: Boolean): Boolean;

implementation

uses
  System.SysUtils, Logging;

function ShouldPostDone(AIsLastWorker, ATerminated: Boolean): Boolean;
begin
  Result := AIsLastWorker;
end;

procedure ThreadLog(const AMsg: string);
begin
  DebugLog('Thread', AMsg);
end;

constructor TExtractionThread.Create(const AExtractor: IFrameExtractor; const AFileName: string; const AOffsets: TFrameOffsetArray; const ASink: IFrameNotificationSink; AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection; const ACache: IFrameCache; AActiveWorkerCount: PInteger; const AOptions: TExtractionOptions);
begin
  inherited Create(True); {suspended}
  FreeOnTerminate := False;
  FExtractor := AExtractor;
  FFileName := AFileName;
  FOffsets := Copy(AOffsets);
  FSink := ASink;
  FQueue := AQueue;
  FQueueLock := AQueueLock;
  FCache := ACache;
  FActiveWorkerCount := AActiveWorkerCount;
  FOptions := AOptions;
  {Manual-reset so late checks (after the first cancel) still see it set.}
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TExtractionThread.Destroy;
begin
  {inherited runs Terminate+WaitFor and joins Execute; freeing the event
   any earlier would race with workers reading FCancelEvent.Handle.}
  inherited;
  FCancelEvent.Free;
end;

procedure TExtractionThread.TerminatedSet;
begin
  inherited;
  FCancelEvent.SetEvent;
end;

procedure TExtractionThread.Execute;
var
  Bmp: TBitmap;
  Frame: TPendingFrame;
  I, CellIdx: Integer;
  Source: string;
  CacheKey: TFrameCacheKey;
  IsLast: Boolean;
begin
  ThreadLog(Format('Execute START frames=%d', [Length(FOffsets)]));
  try
    for I := 0 to High(FOffsets) do
    begin
      if Terminated then
      begin
        ThreadLog(Format('Execute TERMINATED at i=%d', [I]));
        Exit;
      end;

      CellIdx := FOffsets[I].Index - 1; {1-based offset index to 0-based cell index}
      Bmp := nil;

      try
        Source := 'none';

        CacheKey := TFrameCacheKey.Create(FFileName, FOffsets[I].TimeOffset, FOptions.MaxSide, FOptions.UseKeyframes);
        {Bmp is a fresh, worker-owned bitmap either way: TryGet decodes a
         new copy per call (it never shares a cached instance) and Put only
         encodes Bmp without retaining it, so enqueuing Bmp cannot
         double-free a cache entry.}
        Bmp := FCache.TryGet(CacheKey);
        if Bmp <> nil then
          Source := 'cache';

        if Bmp = nil then
        begin
          Bmp := FExtractor.ExtractFrame(FFileName, FOffsets[I].TimeOffset, FOptions, FCancelEvent.Handle);
          if Bmp <> nil then
          begin
            Source := 'extract';
            FCache.Put(CacheKey, Bmp);
          end;
        end;

        if Bmp <> nil then
          ThreadLog(Format('Frame[%d] source=%s size=%dx%d empty=%s', [CellIdx, Source, Bmp.Width, Bmp.Height, BoolToStr(Bmp.Empty, True)]))
        else
          ThreadLog(Format('Frame[%d] source=%s Bmp=NIL', [CellIdx, Source]));
      except
        on E: Exception do
        begin
          ThreadLog(Format('Frame[%d] EXCEPTION: %s: %s', [CellIdx, E.ClassName, E.Message]));
          FreeAndNil(Bmp);
        end;
      end;

      if Terminated then
      begin
        Bmp.Free;
        Exit;
      end;

      {nil Bitmap signals an error placeholder to the UI.}
      Frame.Index := CellIdx;
      Frame.Bitmap := Bmp;
      FQueueLock.Enter;
      try
        FQueue.Add(Frame);
      finally
        FQueueLock.Leave;
      end;
      if FSink <> nil then
        FSink.NotifyFramesReady;
    end;
  finally
    {Signal even when Terminated; skipping on cancel left WMExtractionDone
     unsignalled in races between Terminate and natural completion. The
     controller drains stale signals before each new extraction.}
    IsLast := AtomicDecrement(FActiveWorkerCount^) = 0;
    if ShouldPostDone(IsLast, Terminated) and (FSink <> nil) then
      FSink.NotifyExtractionDone;
  end;
end;

end.
