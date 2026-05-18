{Extraction worker lifecycle and pending frame queue management.
 Extracted from TPluginForm to isolate thread coordination from UI.}
unit uExtractionController;

interface

uses
  System.Classes, System.SyncObjs, System.Generics.Collections,
  Vcl.Graphics,
  uFrameOffsets, uExtractionWorker, uFrameExtractor, uCache,
  uExtractionPlanner, uTypes, uFrameNotificationSink;

type
  {Callback: frame arrived from worker thread (ABitmap = nil signals error)}
  TFrameDeliveryEvent = procedure(AIndex: Integer; ABitmap: TBitmap) of object;

  {Manages extraction worker threads, pending frame queue, and cache.}
  TExtractionController = class
  strict private
    FWorkerThreads: TArray<TExtractionThread>;
    FActiveWorkerCount: Integer;
    FFramesLoaded: Integer;
    FTotalFrames: Integer;
    FPendingFrames: TList<TPendingFrame>;
    FPendingLock: TCriticalSection;
    FCache: IFrameCache;
    {Injected notification sink — production wires TWindowMessageSink
     wrapping the form HWND; tests inject an in-memory capture sink.
     Shared with every worker thread so the controller and worker
     speak the same transport abstraction.}
    FSink: IFrameNotificationSink;
    FOnFrameDelivered: TFrameDeliveryEvent;
    FOnProgress: TNotifyEvent;
  public
    constructor Create(const ASink: IFrameNotificationSink; const ACache: IFrameCache);
    destructor Destroy; override;
    procedure Start(const AExtractor: IFrameExtractor; const AFileName: string; const AOffsets: TFrameOffsetArray; AMaxWorkers, AMaxThreads: Integer; const AOptions: TExtractionOptions; const ACacheOverride: IFrameCache = nil);
    procedure Stop;
    {Drains the pending queue and delivers frames via OnFrameDelivered.}
    procedure ProcessPendingFrames;
    {Frees undelivered bitmaps and discards stale Win32 notifications.}
    procedure DrainPendingFrameMessages;
    {Replaces the active cache instance.}
    procedure RecreateCache(AEnabled: Boolean; const ACacheFolder: string; AMaxSizeMB: Integer);
    property FramesLoaded: Integer read FFramesLoaded;
    property TotalFrames: Integer read FTotalFrames;
    property Cache: IFrameCache read FCache;
    property OnFrameDelivered: TFrameDeliveryEvent read FOnFrameDelivered write FOnFrameDelivered;
    property OnProgress: TNotifyEvent read FOnProgress write FOnProgress;
  end;

const
  {Resize-drag debounce for the background viewport-refresh timer. Long
   enough that mid-drag pixel deltas don't trigger ffmpeg spawns, short
   enough that the user sees the high-res refresh promptly after release.
   Lives here next to the extraction-pipeline policy it gates; the form
   wires its FViewportRefreshTimer.Interval from this constant.}
  VIEWPORT_REFRESH_DEBOUNCE_MS = 500;

implementation

uses
  System.SysUtils, uDebugLog, uSettings, uPathExpand;

var
  {Subsystem logger; closure captures the 'ExtCtrl' tag once at unit
   initialization so call sites read as plain CtrlLog('msg') without
   the tag literal duplicated everywhere.}
  CtrlLog: TProc<string>;

{TExtractionController}

constructor TExtractionController.Create(const ASink: IFrameNotificationSink; const ACache: IFrameCache);
begin
  inherited Create;
  FSink := ASink;
  FCache := ACache;
  FPendingFrames := TList<TPendingFrame>.Create;
  FPendingLock := TCriticalSection.Create;
end;

destructor TExtractionController.Destroy;
begin
  Stop;
  if Assigned(FPendingLock) then
    DrainPendingFrameMessages;
  FPendingLock.Free;
  FPendingFrames.Free;
  inherited;
end;

procedure TExtractionController.Start(const AExtractor: IFrameExtractor; const AFileName: string; const AOffsets: TFrameOffsetArray; AMaxWorkers, AMaxThreads: Integer; const AOptions: TExtractionOptions; const ACacheOverride: IFrameCache);
var
  ThreadCache: IFrameCache;
  Chunks: TArray<TWorkerChunk>;
  W: Integer;
  Chunk: TFrameOffsetArray;
begin
  Stop;
  FFramesLoaded := 0;
  FTotalFrames := Length(AOffsets);

  if ACacheOverride <> nil then
    ThreadCache := ACacheOverride
  else
    ThreadCache := FCache;

  Chunks := PlanWorkerChunks(Length(AOffsets), AMaxWorkers, AMaxThreads);
  FActiveWorkerCount := Length(Chunks);
  SetLength(FWorkerThreads, Length(Chunks));

  for W := 0 to High(Chunks) do
  begin
    Chunk := Copy(AOffsets, Chunks[W].Start, Chunks[W].Len);
    FWorkerThreads[W] := TExtractionThread.Create(AExtractor, AFileName, Chunk, FSink, FPendingFrames, FPendingLock, ThreadCache, @FActiveWorkerCount, AOptions);
  end;

  {Start all threads after creation to minimize scheduling skew}
  for W := 0 to High(Chunks) do
    FWorkerThreads[W].Start;
end;

procedure TExtractionController.Stop;
var
  W: Integer;
begin
  for W := 0 to High(FWorkerThreads) do
    if Assigned(FWorkerThreads[W]) then
      FWorkerThreads[W].Terminate;
  for W := 0 to High(FWorkerThreads) do
    if Assigned(FWorkerThreads[W]) then
    begin
      FWorkerThreads[W].WaitFor;
      FreeAndNil(FWorkerThreads[W]);
    end;
  FWorkerThreads := nil;
end;

procedure TExtractionController.ProcessPendingFrames;
var
  Snapshot: TArray<TPendingFrame>;
  I: Integer;
begin
  FPendingLock.Enter;
  try
    if FPendingFrames.Count = 0 then
      Exit;
    Snapshot := FPendingFrames.ToArray;
    FPendingFrames.Clear;
  finally
    FPendingLock.Leave;
  end;

  if Length(Snapshot) > 0 then
    CtrlLog(Format('ProcessPending: count=%d', [Length(Snapshot)]));

  for I := 0 to High(Snapshot) do
  begin
    if Snapshot[I].Bitmap <> nil then
      CtrlLog(Format('  Frame[%d] bmp=%dx%d empty=%s', [Snapshot[I].Index, Snapshot[I].Bitmap.Width, Snapshot[I].Bitmap.Height, BoolToStr(Snapshot[I].Bitmap.Empty, True)]))
    else
      CtrlLog(Format('  FrameError[%d]', [Snapshot[I].Index]));

    if Assigned(FOnFrameDelivered) then
      FOnFrameDelivered(Snapshot[I].Index, Snapshot[I].Bitmap);
    Inc(FFramesLoaded);
  end;

  if (Length(Snapshot) > 0) and Assigned(FOnProgress) then
    FOnProgress(Self);
end;

procedure TExtractionController.DrainPendingFrameMessages;
var
  I: Integer;
begin
  FPendingLock.Enter;
  try
    for I := 0 to FPendingFrames.Count - 1 do
      FPendingFrames[I].Bitmap.Free;
    FPendingFrames.Clear;
  finally
    FPendingLock.Leave;
  end;
  if FSink <> nil then
    FSink.DrainPending;
end;

procedure TExtractionController.RecreateCache(AEnabled: Boolean; const ACacheFolder: string; AMaxSizeMB: Integer);
begin
  if AEnabled then
    FCache := TFrameCache.Create(EffectiveCacheFolder(ACacheFolder), AMaxSizeMB)
  else
    FCache := TNullFrameCache.Create;
end;

initialization
  CtrlLog := DebugLogger('ExtCtrl');

end.
