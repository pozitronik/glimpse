{Adapts internal percent-based progress reports onto TC's WCX progress
 callback, handling both ANSI and Wide variants, and surfaces a Win32
 cancel handle that uRunProcess.RunProcess can wait on to terminate the
 child process when the user cancels.
 Per TC's Packer Plugin spec: ProcessDataProc(FileName, Size) interprets
 a negative Size in [-1, -100] as a percentage (1..100%), positive as
 a delta byte count, zero as a "cancel poll only" ping. Return value
 1=continue, 0=abort. Callers use ReportPercent for the metered case
 and Ping when no real progress is available yet (e.g. before ffmpeg
 emits its first -progress tick).}
unit uWcxProgressBridge;

interface

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows,
  uWcxAPI;

type
  TWcxProgressBridge = class
  strict private
    FCallbackA: TProcessDataProc;
    FCallbackW: TProcessDataProcW;
    FFileNameW: string;
    FFileNameA: AnsiString;
    FCancelEvent: TEvent;
    FCancelled: Boolean;
    FLastPercent: Integer;
    {Picks the modern Wide callback when available, falls back to the
     ANSI variant. When neither is set, returns 1 so the extractor runs
     without surfacing progress (TC may not have wired the callback yet).}
    function InvokeCallback(APayload: Integer): Integer;
  public
    {ACallbackA / ACallbackW are captured by reference; either or both may
     be nil. The destination filename is held in both encodings so the
     per-tick Invoke does not allocate.}
    constructor Create(const AFileName: string; ACallbackA: TProcessDataProc; ACallbackW: TProcessDataProcW);
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

constructor TWcxProgressBridge.Create(const AFileName: string; ACallbackA: TProcessDataProc; ACallbackW: TProcessDataProcW);
begin
  inherited Create;
  FCallbackA := ACallbackA;
  FCallbackW := ACallbackW;
  FFileNameW := AFileName;
  {Single ANSI conversion at construction; per-tick callbacks must not
   allocate. Non-CP_ACP characters degrade silently here — modern TC
   calls SetProcessDataProcW so the ANSI path is a fallback.}
  FFileNameA := AnsiString(AFileName);
  {Manual-reset event so RunProcess's WaitForMultipleObjects observes
   the cancel state across multiple polls; auto-reset would clear after
   the first waiter wakes and miss subsequent checks during the same
   extract.}
  FCancelEvent := TEvent.Create(nil, True, False, '');
  FCancelled := False;
  {-1 sentinel so the first ReportPercent(0) is not short-circuited
   against the no-call-yet state.}
  FLastPercent := -1;
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
  if Assigned(FCallbackW) then
    Result := FCallbackW(PWideChar(FFileNameW), APayload)
  else if Assigned(FCallbackA) then
    Result := FCallbackA(PAnsiChar(FFileNameA), APayload)
  else
    Result := 1;
end;

function TWcxProgressBridge.ReportPercent(APercent: Integer): Boolean;
var
  Clamped: Integer;
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

  if InvokeCallback(-Clamped) = 0 then
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
