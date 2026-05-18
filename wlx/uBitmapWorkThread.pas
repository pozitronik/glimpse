{Generic worker thread for bitmap operations that must run off the main
 thread (PNG encode, large HGLOBAL allocations etc.) while a modal
 progress dialog keeps the lister responsive.

 Previously two near-identical thread classes lived inside uFrameExport
 (TFileWriteThread + TClipboardWriteThread). Their bodies turned out to
 be byte-identical except for the work payload and one auxiliary field,
 so they collapsed into this single class. The work payload is supplied
 as an anonymous method.

 Cancellation contract — the awkward bit, preserved from the originals:
 RequestCancel pins this DLL via an extra LoadLibrary refcount and then
 detaches the thread (FreeOnTerminate). The worker runs to natural
 completion on its own; TC can FreeLibrary us a moment later (closing
 the lister) and the still-running code stays mapped because of the pin.
 The pin is never released — the OS reclaims the handle on TC exit. One
 leaked handle per cancellation, which is negligible. See the inline
 comment in RequestCancel for the long version.

 Threading: the work proc and post-work hook run on the worker thread.
 The completion callback (set via the IModalThreadCompletion interface
 and wired by uProgressModalForm.RunWithProgress to a PostMessage to the
 modal's HWND) also runs on the worker thread; it must use thread-safe
 APIs only.}
unit uBitmapWorkThread;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Graphics,
  uProgressModalForm;

type
  {Outcome the work proc reports back. Defaults to (Success=False,
   ErrorMsg='') so the failure path doesn't depend on the proc remembering
   to initialise.}
  TBitmapWorkOutcome = record
    Success: Boolean;
    ErrorMsg: string;
  end;

  {Work payload. Receives the owned bitmap; must NOT free it (the thread
   owns it and frees in its destructor). Sets AOutcome to record the
   result. An uncaught exception leaving this proc is caught at the
   thread level, marks AOutcome.Success := False and records E.Message
   into AOutcome.ErrorMsg.}
  TBitmapWorkProc = reference to procedure(ABmp: Vcl.Graphics.TBitmap;
    var AOutcome: TBitmapWorkOutcome);

  {Optional post-work hook. Runs after the work proc returns (or raises
   and got caught). Used by the file-write path to delete the temp file
   when the user cancelled mid-encode (the file got written but nobody
   will paste it). The clipboard path leaves this nil. Exceptions inside
   the post-work proc are swallowed: cleanup must never bring down the
   thread.}
  TBitmapWorkPostProc = reference to procedure(const AOutcome: TBitmapWorkOutcome;
    ACancelled: Boolean);

  TBitmapWorkThread = class(TThread, IModalThreadCompletion)
  private
    FBmp: Vcl.Graphics.TBitmap;
    FWork: TBitmapWorkProc;
    FPostWork: TBitmapWorkPostProc;
    FOutcome: TBitmapWorkOutcome;
    {Set by RequestCancel on the main thread, read by Execute on the
     worker thread. Boolean writes are atomic on word-aligned storage so
     no critical section is needed.}
    FCancelled: Boolean;
    FOnComplete: TProc;
    procedure SetCompletionCallback(ACallback: TProc);
    {Non-refcounted IInterface implementation. The thread's lifetime is
     managed explicitly by the caller (Free or FreeOnTerminate), not by
     reference counting on interface variables. Returning -1 from
     _AddRef/_Release is the conventional "ref counting disabled" marker.}
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  protected
    procedure Execute; override;
  public
    {Takes ownership of ABmp regardless of outcome. Destructor frees it
     whether or not Execute ran (e.g. the caller can construct, decide
     not to start, and Free — bitmap still gets cleaned up).}
    constructor Create(ABmp: Vcl.Graphics.TBitmap;
      const AWork: TBitmapWorkProc;
      const APostWork: TBitmapWorkPostProc = nil); reintroduce;
    destructor Destroy; override;
    {Marks the operation cancelled, pins the DLL, switches to
     FreeOnTerminate. After calling, the caller MUST NOT touch the
     thread reference — it will be freed asynchronously.}
    procedure RequestCancel;
    {Read-only after Execute completes (or after WaitFor returns).
     Defined as a property so tests can read without needing to know
     the field name.}
    property Outcome: TBitmapWorkOutcome read FOutcome;
    property Cancelled: Boolean read FCancelled;
  end;

implementation

uses
  uPluginDllPin;

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
      {Intentionally swallowed. Cleanup failure must not propagate — the
       previous bespoke implementations used SysUtils.DeleteFile which
       never raises, but a future caller could supply something that
       does, and the worker thread is not a place where an unhandled
       exception can be inspected. Anything serious is surfaced via the
       primary outcome path.}
    end;

  if Assigned(FOnComplete) then
    {Runs on worker thread. uProgressModalForm.RunWithProgress wires
     this to a PostMessage on the modal's HWND — thread-safe; the
     message routes back to the main thread's loop.}
    FOnComplete;
end;

procedure TBitmapWorkThread.RequestCancel;
begin
  {Pin the DLL so this worker can run to completion even if TC unloads
   the plugin the instant the user closed the Lister. See uPluginDllPin
   for the full rationale.}
  TPluginDllPin.Acquire;
  FCancelled := True;
  {FreeOnTerminate hands the thread's lifetime to the thread itself:
   when Execute returns, TThread.AfterTerminate frees us, our destructor
   frees the owned bitmap. Main thread doesn't wait.}
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
