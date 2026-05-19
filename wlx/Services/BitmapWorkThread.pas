{Generic worker thread for off-main-thread bitmap operations.

 Cancellation contract: RequestCancel pins the DLL (LoadLibrary refcount)
 then sets FreeOnTerminate. The worker runs to natural completion; if TC
 unloads the plugin a moment later, the pin keeps the code mapped. The
 pin is never released — one leaked handle per cancellation, negligible.

 Work proc, post-work hook and completion callback all run on the worker
 thread and must use thread-safe APIs only.}
unit BitmapWorkThread;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Graphics,
  ProgressModalForm;

type
  TBitmapWorkOutcome = record
    Success: Boolean;
    ErrorMsg: string;
  end;

  TClipboardPublishResult = (cprSuccess, cprFailed, cprCancelled);

  {Production wires to ProgressModalForm.RunWithProgress; tests pass nil for sync.}
  TAsyncTaskRunner = reference to function(AThread: TThread;
    const AText: string): Boolean;

  {Receives the owned bitmap — MUST NOT free it (thread owns and frees).
   Uncaught exceptions land in AOutcome.ErrorMsg.}
  TBitmapWorkProc = reference to procedure(ABmp: Vcl.Graphics.TBitmap;
    var AOutcome: TBitmapWorkOutcome);

  {Used e.g. by the file-write path to delete the temp file on cancel.
   Exceptions are swallowed — cleanup must never bring down the thread.}
  TBitmapWorkPostProc = reference to procedure(const AOutcome: TBitmapWorkOutcome;
    ACancelled: Boolean);

  TBitmapWorkThread = class(TThread, IModalThreadCompletion)
  private
    FBmp: Vcl.Graphics.TBitmap;
    FWork: TBitmapWorkProc;
    FPostWork: TBitmapWorkPostProc;
    FOutcome: TBitmapWorkOutcome;
    {Aligned Boolean writes are atomic; no critical section needed.}
    FCancelled: Boolean;
    FOnComplete: TProc;
    procedure SetCompletionCallback(ACallback: TProc);
    {Non-refcounted IInterface: thread lifetime is explicit (Free or
     FreeOnTerminate), not via interface refcount. _AddRef/_Release
     return -1 (standard "refcounting disabled" marker).}
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  protected
    procedure Execute; override;
  public
    {Takes ownership of ABmp regardless of outcome — destructor frees
     it even if Execute never ran.}
    constructor Create(ABmp: Vcl.Graphics.TBitmap;
      const AWork: TBitmapWorkProc;
      const APostWork: TBitmapWorkPostProc = nil); reintroduce;
    destructor Destroy; override;
    {After this call the caller MUST NOT touch the thread reference —
     it is freed asynchronously.}
    procedure RequestCancel;
    property Outcome: TBitmapWorkOutcome read FOutcome;
    property Cancelled: Boolean read FCancelled;
  end;

{OWNERSHIP: takes ABitmap unconditionally (var, set to nil on entry) — the
 thread frees it.

 Returns cprCancelled when ARunner reports user-cancel: the thread is then
 detached + DLL-pinned and the main thread does NOT wait — callers MUST
 treat cprCancelled as "thread is gone, results unreliable".

 ARunner=nil = synchronous (tests / standalone); cancellation impossible.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;

implementation

uses
  PluginDllPin;

function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;
var
  TakenBmp: Vcl.Graphics.TBitmap;
  Thread: TBitmapWorkThread;
  TaskOk: Boolean;
begin
  Result := cprFailed;
  AOutcome := Default(TBitmapWorkOutcome);
  {Take ownership up front so the caller's trailing Bmp.Free is a no-op.}
  TakenBmp := ABitmap;
  ABitmap := nil;
  if TakenBmp = nil then
    Exit;

  Thread := TBitmapWorkThread.Create(TakenBmp, AWork, APostWork);
  try
    if Assigned(ARunner) then
      TaskOk := ARunner(Thread, AStatusText)
    else
    begin
      {Synchronous fallback — cannot be cancelled in this mode.}
      Thread.Start;
      Thread.WaitFor;
      TaskOk := True;
    end;

    if not TaskOk then
    begin
      {RequestCancel detaches via FreeOnTerminate; null the local so the
       finally block does not double-free.}
      Thread.RequestCancel;
      Thread := nil;
      Exit(cprCancelled);
    end;

    AOutcome := Thread.Outcome;
    if AOutcome.Success then
      Result := cprSuccess
    else
      Result := cprFailed;
  finally
    Thread.Free;
  end;
end;

constructor TBitmapWorkThread.Create(ABmp: Vcl.Graphics.TBitmap;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc);
begin
  inherited Create(True);
  FBmp := ABmp;
  FWork := AWork;
  FPostWork := APostWork;
end;

destructor TBitmapWorkThread.Destroy;
begin
  FBmp.Free;
  inherited;
end;

procedure TBitmapWorkThread.Execute;
begin
  try
    if Assigned(FWork) then
      FWork(FBmp, FOutcome);
  except
    on E: Exception do
    begin
      FOutcome.Success := False;
      FOutcome.ErrorMsg := E.Message;
    end;
  end;

  if Assigned(FPostWork) then
    try
      FPostWork(FOutcome, FCancelled);
    except
      {Intentionally swallowed — cleanup must never bring down the thread.}
    end;

  if Assigned(FOnComplete) then
    {Runs on the worker thread; production callback PostMessages back to main.}
    FOnComplete;
end;

procedure TBitmapWorkThread.RequestCancel;
begin
  {Pin keeps the code mapped if TC unloads the plugin while we run.}
  TPluginDllPin.Acquire;
  FCancelled := True;
  {Hand lifetime to the thread; main does not wait.}
  FreeOnTerminate := True;
end;

procedure TBitmapWorkThread.SetCompletionCallback(ACallback: TProc);
begin
  FOnComplete := ACallback;
end;

function TBitmapWorkThread.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TBitmapWorkThread._AddRef: Integer;
begin
  Result := -1;
end;

function TBitmapWorkThread._Release: Integer;
begin
  Result := -1;
end;

end.
