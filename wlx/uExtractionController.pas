{ Extraction worker lifecycle and pending frame queue management.
  Extracted from TPluginForm to isolate thread coordination from UI. }
unit uExtractionController;

interface

uses
  System.Classes, System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics,
  uFrameOffsets, uExtractionWorker, uFrameExtractor, uCache,
  uExtractionPlanner;

type
  { Callback: frame arrived from worker thread (ABitmap = nil signals error) }
  TFrameDeliveryEvent = procedure(AIndex: Integer; ABitmap: TBitmap) of object;

  { Manages extraction worker threads, pending frame queue, and cache. }
  TExtractionController = class
  strict private
    FWorkerThreads: TArray<TExtractionThread>;
    FActiveWorkerCount: Integer;
    FFramesLoaded: Integer;
    FTotalFrames: Integer;
    FPendingFrames: TList<TPendingFrame>;
    FPendingLock: TCriticalSection;
    FCache: IFrameCache;
    FFormHandle: HWND;
    FOnFrameDelivered: TFrameDeliveryEvent;
    FOnProgress: TNotifyEvent;
  public
    constructor Create(AFormHandle: HWND; const ACache: IFrameCache);
    destructor Destroy; override;
    procedure Start(const AExtractor: IFrameExtractor;
      const AFileName: string; const AOffsets: TFrameOffsetArray;
      AMaxWorkers, AMaxThreads: Integer; AUseBmpPipe: Boolean;
      const ACacheOverride: IFrameCache = nil);
    procedure Stop;
    { Drains the pending queue and delivers frames via OnFrameDelivered. }
    procedure ProcessPendingFrames;
    { Frees undelivered bitmaps and discards stale Win32 notifications. }
    procedure DrainPendingFrameMessages;
    { Replaces the active cache instance. }
    procedure RecreateCache(AEnabled: Boolean; const ACacheFolder: string;
      AMaxSizeMB: Integer);
    property FramesLoaded: Integer read FFramesLoaded;
    property TotalFrames: Integer read FTotalFrames;
    property Cache: IFrameCache read FCache;
    property OnFrameDelivered: TFrameDeliveryEvent
      read FOnFrameDelivered write FOnFrameDelivered;
    property OnProgress: TNotifyEvent read FOnProgress write FOnProgress;
  end;

implementation

uses
  System.SysUtils, uDebugLog, uSettings, uPathExpand;

procedure CtrlLog(const AMsg: string);
begin
  DebugLog('ExtCtrl', AMsg);
end;

{ TExtractionController }

constructor TExtractionController.Create(AFormHandle: HWND;
  const ACache: IFrameCache);
begin
  inherited Create;
  FFormHandle := AFormHandle;
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

procedure TExtractionController.Start(const AExtractor: IFrameExtractor;
  const AFileName: string; const AOffsets: TFrameOffsetArray;
  AMaxWorkers, AMaxThreads: Integer; AUseBmpPipe: Boolean;
  const ACacheOverride: IFrameCache);
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
    FWorkerThreads[W] := TExtractionThread.Create(AExtractor, AFileName,
      Chunk, FFormHandle, FPendingFrames, FPendingLock, ThreadCache,
      @FActiveWorkerCount, AUseBmpPipe);
  end;

  { Start all threads after creation to minimize scheduling skew }
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
      CtrlLog(Format('  Frame[%d] bmp=%dx%d empty=%s',
        [Snapshot[I].Index, Snapshot[I].Bitmap.Width,
         Snapshot[I].Bitmap.Height,
         BoolToStr(Snapshot[I].Bitmap.Empty, True)]))
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
  Msg: TMsg;
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
  if FFormHandle <> 0 then
  begin
    while PeekMessage(Msg, FFormHandle, WM_FRAME_READY, WM_FRAME_READY,
      PM_REMOVE) do
      ; { notifications carry no payload }
    PeekMessage(Msg, FFormHandle, WM_EXTRACTION_DONE, WM_EXTRACTION_DONE,
      PM_REMOVE);
  end;
end;

procedure TExtractionController.RecreateCache(AEnabled: Boolean;
  const ACacheFolder: string; AMaxSizeMB: Integer);
begin
  if AEnabled then
    FCache := TFrameCache.Create(
      EffectiveCacheFolder(ACacheFolder), AMaxSizeMB)
  else
    FCache := TNullFrameCache.Create;
end;

end.
