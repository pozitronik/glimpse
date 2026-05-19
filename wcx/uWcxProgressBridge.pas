{Adapts percent-based progress onto TC's WCX callback and exposes a
 Win32 cancel handle that uRunProcess.RunProcess waits on.

 Emits POSITIVE DELTAS rather than negative percentages: empirically
 only the positive-delta form animates the bar in all TC builds, and
 only when the listing reports UnpSize > 0. Deltas sum to the caller-
 supplied total (typically the source file size). Callback returns
 1=continue, 0=abort.}
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
    {Int64 even though TC's Size is Int32, so large source files scale
     safely; per-tick deltas clamp to Int32 before the callback.}
    FTotalBytes: Int64;
    FReportedBytes: Int64;
    function InvokeCallback(APayload: Integer): Integer;
  public
    {AProc must be non-nil; ATotalBytes <= 0 degrades to silent (no
     callbacks emitted) since TC's denominator would be zero too.}
    constructor Create(ATotalBytes: Int64; const AProc: IProcessDataProc); overload;
    constructor Create(const AFileName: string; ATotalBytes: Int64;
      ACallbackA: TProcessDataProc; ACallbackW: TProcessDataProcW); overload;
    destructor Destroy; override;
    {Clamps APercent to [0, 100] so a transient ffmpeg glitch is
     harmless. Same-percent calls short-circuit to avoid spamming TC.
     Returns False and signals CancelHandle on user cancel.}
    function ReportPercent(APercent: Integer): Boolean;
    {Size=0 callback so cancel detection runs before any progress data
     is available.}
    function Ping: Boolean;
    function CancelHandle: THandle;
    property Cancelled: Boolean read FCancelled;
    property LastPercent: Integer read FLastPercent;
  end;

implementation

constructor TWcxProgressBridge.Create(ATotalBytes: Int64; const AProc: IProcessDataProc);
begin
  inherited Create;
  FProc := AProc;
  {Manual-reset so multiple WaitForMultipleObjects polls observe the
   cancel state; auto-reset would clear after the first waiter wakes.}
  FCancelEvent := TEvent.Create(nil, True, False, '');
  FCancelled := False;
  {-1 sentinel so the first ReportPercent(0) is not short-circuited.}
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
    {Ping-equivalent: cancel detection still works but the bar cannot
     animate since TC's denominator is zero.}
    if InvokeCallback(0) = 0 then
    begin
      FCancelled := True;
      FCancelEvent.SetEvent;
      Exit(False);
    end;
    Exit(True);
  end;

  {Negative gap (ffmpeg clock jittered backward) clamps to 0 — TC's bar
   can only fill. Per-tick MaxInt clamp protects against pathological
   multi-GB jumps; FReportedBytes catches up on later ticks.}
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
