{Adapts internal percent-based progress reports onto TC's WCX progress
 callback, handling both ANSI and Wide variants, and surfaces a Win32
 cancel handle that uRunProcess.RunProcess can wait on to terminate the
 child process when the user cancels.
 TC's spec accepts both negative-percent and positive-delta forms for
 Size, but the negative-percent form does not animate the progress bar
 in many TC builds — empirically only the positive-delta form is
 universally rendered, and only when the listing reports UnpSize>0.
 The bridge therefore emits positive deltas computed against a caller-
 supplied total (typically the source video size, so TC's listing shows
 a believable byte count instead of a synthetic placeholder). Sum of
 deltas across a complete run equals the total. Return value:
 1=continue, 0=abort. Callers use ReportPercent for the metered case
 and Ping when no real progress is available yet.}
unit uWcxProgressBridge;

interface

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows,
  uWcxAPI, uWcxProgressCallback;

type
  TWcxProgressBridge = class
  strict private
    FProc: IProcessDataProc;
    FCancelEvent: TEvent;
    FCancelled: Boolean;
    FLastPercent: Integer;
    {Total bytes the listing layer reports as UnpSize for this entry;
     deltas are scaled so their sum equals this value when the run hits
     100%. Stored as Int64 even though TC's Size param is Int32 so we
     can safely scale large source files; per-tick deltas are clamped
     into Int32 range before the callback.}
    FTotalBytes: Int64;
    {Bytes already attributed via callback calls; used to compute the
     next delta as (target - reported).}
    FReportedBytes: Int64;
    function InvokeCallback(APayload: Integer): Integer;
  public
    {Primary constructor. AProc must be non-nil; pass a TWcxProcessDataProc
     with nil inner pointers when no real callback is wired (its Notify
     returns 1 unconditionally). ATotalBytes is the denominator deltas
     are scaled against — typically the source video size so TC's
     listing column matches what was advertised in ReadHeaderExW. A zero
     or negative total degrades to silent (no callbacks emitted), which
     is harmless when TC is not displaying a progress bar anyway.}
    constructor Create(ATotalBytes: Int64; const AProc: IProcessDataProc); overload;
    {Back-compat constructor used by DoExtractPreset and the existing
     bridge tests: builds a TWcxProcessDataProc from the supplied
     ANSI/Wide pair and delegates to the primary constructor.}
    constructor Create(const AFileName: string; ATotalBytes: Int64;
      ACallbackA: TProcessDataProc; ACallbackW: TProcessDataProcW); overload;
    destructor Destroy; override;
    {Reports a progress percentage in [0, 100]. Values outside the range
     clamp silently so a transient ffmpeg out_time glitch does not crash
     the extractor. Returns False (and signals the cancel event) when
     the user cancelled. Repeated calls with the same clamped percent
     short-circuit to avoid spamming TC.}
    function ReportPercent(APercent: Integer): Boolean;
    {Pings the callback with Size=0 so cancel detection runs even when
     no progress info is available yet. Returns False on cancel.}
    function Ping: Boolean;
    {Win32 waitable handle that RunProcess waits on; signals when the
     user cancelled, which terminates the child process via the existing
     RunProcess watcher.}
    function CancelHandle: THandle;
    property Cancelled: Boolean read FCancelled;
    property LastPercent: Integer read FLastPercent;
  end;

implementation

constructor TWcxProgressBridge.Create(ATotalBytes: Int64; const AProc: IProcessDataProc);
begin
  inherited Create;
  FProc := AProc;
  {Manual-reset event so RunProcess's WaitForMultipleObjects observes
   the cancel state across multiple polls; auto-reset would clear after
   the first waiter wakes and miss subsequent checks during the same
   extract.}
  FCancelEvent := TEvent.Create(nil, True, False, '');
  FCancelled := False;
  {-1 sentinel so the first ReportPercent(0) is not short-circuited
   against the no-call-yet state.}
  FLastPercent := -1;
  if ATotalBytes < 0 then
    FTotalBytes := 0
  else
    FTotalBytes := ATotalBytes;
  FReportedBytes := 0;
end;

constructor TWcxProgressBridge.Create(const AFileName: string; ATotalBytes: Int64;
  ACallbackA: TProcessDataProc; ACallbackW: TProcessDataProcW);
var
  Wrapper: IProcessDataProc;
begin
  Wrapper := TWcxProcessDataProc.Create(AFileName, ACallbackA, ACallbackW);
  Create(ATotalBytes, Wrapper);
end;

destructor TWcxProgressBridge.Destroy;
begin
  FCancelEvent.Free;
  inherited;
end;

function TWcxProgressBridge.CancelHandle: THandle;
begin
  Result := FCancelEvent.Handle;
end;

function TWcxProgressBridge.InvokeCallback(APayload: Integer): Integer;
begin
  Result := FProc.Notify(APayload);
end;

function TWcxProgressBridge.ReportPercent(APercent: Integer): Boolean;
var
  Clamped: Integer;
  TargetBytes, Delta: Int64;
  ClampedDelta: Integer;
begin
  if FCancelled then
    Exit(False);

  Clamped := APercent;
  if Clamped < 0 then
    Clamped := 0;
  if Clamped > 100 then
    Clamped := 100;

  if Clamped = FLastPercent then
    Exit(True);

  FLastPercent := Clamped;

  if FTotalBytes <= 0 then
  begin
    {No total to scale against — emit a Ping-equivalent so cancel detection
     still works but the bar cannot animate (TC's denominator is zero too).}
    if InvokeCallback(0) = 0 then
    begin
      FCancelled := True;
      FCancelEvent.SetEvent;
      Exit(False);
    end;
    Exit(True);
  end;

  {Compute the cumulative byte target for this percent and emit the gap
   from what was already reported. Negative gap (ffmpeg clock jittered
   backward) clamps to 0 — TC's bar can only fill, never retreat. The
   per-tick clamp at MaxInt protects against pathological multi-GB
   single-step jumps; the running FReportedBytes catches up on later
   ticks so the run still completes at FTotalBytes.}
  TargetBytes := Clamped * FTotalBytes div 100;
  Delta := TargetBytes - FReportedBytes;
  if Delta < 0 then
    Delta := 0;
  if Delta > MaxInt then
    Delta := MaxInt;
  ClampedDelta := Integer(Delta);
  Inc(FReportedBytes, ClampedDelta);

  if InvokeCallback(ClampedDelta) = 0 then
  begin
    FCancelled := True;
    FCancelEvent.SetEvent;
    Exit(False);
  end;
  Result := True;
end;

function TWcxProgressBridge.Ping: Boolean;
begin
  if FCancelled then
    Exit(False);
  if InvokeCallback(0) = 0 then
  begin
    FCancelled := True;
    FCancelEvent.SetEvent;
    Exit(False);
  end;
  Result := True;
end;

end.
