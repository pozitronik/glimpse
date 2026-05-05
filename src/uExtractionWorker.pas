{Worker thread that extracts video frames via ffmpeg.exe.
 Stores results in a thread-safe queue and posts WM notifications
 to the owner window for UI-thread pickup.}
unit uExtractionWorker;

interface

uses
  System.Classes, System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics,
  uFrameOffsets, uFrameExtractor, uCache, uTypes;

const
  WM_FRAME_READY = WM_USER + 100; {Notification: pending frames available in queue}
  WM_EXTRACTION_DONE = WM_USER + 101; {Extraction finished}

type
  {Extracted frame awaiting delivery to UI thread}
  TPendingFrame = record
    Index: Integer;
    Bitmap: TBitmap; {nil = extraction error}
  end;

  {Worker thread that extracts frames sequentially via ffmpeg.exe.
   Stores results in a thread-safe queue and posts notifications.}
  TExtractionThread = class(TThread)
  private
    FExtractor: IFrameExtractor;
    FFileName: string;
    FOffsets: TFrameOffsetArray;
    FNotifyWnd: HWND;
    FQueue: TList<TPendingFrame>;
    FQueueLock: TCriticalSection;
    FCache: IFrameCache;
    FActiveWorkerCount: PInteger; {shared counter; last thread posts WM_EXTRACTION_DONE}
    FOptions: TExtractionOptions;
    {Signaled from TerminatedSet so a blocking ffmpeg call inside RunProcess
     can be unblocked mid-run instead of waiting for the child to exit.}
    FCancelEvent: TEvent;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(const AExtractor: IFrameExtractor; const AFileName: string; const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND; AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection; const ACache: IFrameCache; AActiveWorkerCount: PInteger; const AOptions: TExtractionOptions);
    destructor Destroy; override;
  end;

  {Decision rule for posting WM_EXTRACTION_DONE from a worker's finally block.
   Returns True only for the last worker to decrement the active counter; the
   ATerminated flag is taken for documentation but is intentionally not used
   to suppress the post. Earlier the worker checked NOT Terminated before
   posting, which left the UI without a completion signal whenever all
   workers had been cancelled at the cancel-edge of natural completion. The
   controller already calls DrainPendingFrameMessages between extractions so
   a stale post is harmless; missing the post on the cancel path was the
   actual hazard.}
function ShouldPostDone(AIsLastWorker, ATerminated: Boolean): Boolean;

implementation

uses
  System.SysUtils, uDebugLog;

function ShouldPostDone(AIsLastWorker, ATerminated: Boolean): Boolean;
begin
  Result := AIsLastWorker;
end;

procedure ThreadLog(const AMsg: string);
begin
  DebugLog('Thread', AMsg);
end;

constructor TExtractionThread.Create(const AExtractor: IFrameExtractor; const AFileName: string; const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND; AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection; const ACache: IFrameCache; AActiveWorkerCount: PInteger; const AOptions: TExtractionOptions);
begin
  inherited Create(True); {suspended}
  FreeOnTerminate := False;
  FExtractor := AExtractor;
  FFileName := AFileName;
  FOffsets := Copy(AOffsets);
  FNotifyWnd := ANotifyWnd;
  FQueue := AQueue;
  FQueueLock := AQueueLock;
  FCache := ACache;
  FActiveWorkerCount := AActiveWorkerCount;
  FOptions := AOptions;
  {Manual-reset so a late check (after the first cancel) still sees it set}
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TExtractionThread.Destroy;
begin
  {inherited Destroy triggers Terminate+WaitFor which runs TerminatedSet and
   joins Execute; only after that is it safe to free the event.}
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
        Bmp := FCache.TryGet(CacheKey);
        if Bmp <> nil then
          Source := 'cache';

        {Cache miss: extract via extractor}
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

      {Enqueue frame for the UI thread; PostMessage is just a notification.
       Bitmap = nil signals an error placeholder to the UI.}
      Frame.Index := CellIdx;
      Frame.Bitmap := Bmp;
      FQueueLock.Enter;
      try
        FQueue.Add(Frame);
      finally
        FQueueLock.Leave;
      end;
      PostMessage(FNotifyWnd, WM_FRAME_READY, 0, 0);
    end;
  finally
    {Always decrement; last worker to finish notifies the UI.
     Post even when Terminated - the controller drains stale completion
     messages before each new extraction, so the UI is robust against
     that, and skipping the post on cancel left WMExtractionDone
     unsignalled in races between Terminate and natural completion.}
    IsLast := InterlockedDecrement(FActiveWorkerCount^) = 0;
    if ShouldPostDone(IsLast, Terminated) then
      PostMessage(FNotifyWnd, WM_EXTRACTION_DONE, 0, 0);
  end;
end;

end.
