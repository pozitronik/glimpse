{General-purpose Windows process execution with stdout/stderr capture.
 No application-specific logic.}
unit uRunProcess;

interface

uses
  System.SysUtils, Winapi.Windows;

type
  {Callback the core invokes on the calling thread once the child
   process is running. The callback owns the stdout-pipe-reading
   strategy: drain-all into a byte buffer, stream lines via a splitter,
   tee to a file, etc. The pipe handle is closed by the core after the
   callback returns (or raises). The callback must NOT close it.}
  TStdOutConsumer = reference to procedure(AStdOutPipe: THandle);

{Runs a process with redirected stdout/stderr, captures both outputs.
 Returns the process exit code, or -1 on launch failure, timeout, or cancellation.
 ACancelHandle is an optional Win32 waitable handle (typically TEvent.Handle). When
 signaled mid-run, a watcher thread terminates the child process, which cascades
 through pipe closure and unblocks the otherwise-blocking ReadFile calls.}
function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer; overload;

{Streaming overload: dispatches each stdout line to AOnStdOutLine as it
 arrives instead of buffering the full output. Lines are decoded as UTF-8
 with replacement (matches uFFmpegExe's lenient policy) and trailing CR
 is stripped. AStdErr is still buffered to completion so callers can show
 the error message on failure. Cancel/timeout semantics match the buffered
 overload; AOnStdOutLine has no return value, so callers signal cancel by
 setting ACancelHandle externally (typically via the WCX progress bridge).
 Exceptions raised inside AOnStdOutLine propagate up after the watcher
 wakes and the child exits, so the process is never orphaned.}
function RunProcess(const ACommandLine: string; AOnStdOutLine: TProc<string>; out AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer; overload;

{Shared core that the two public overloads (and any third-party caller
 with a custom stdout-reading strategy) delegate to. Handles pipe
 creation, CreateProcess, the stderr-reader thread, the timeout +
 cancel watcher thread, exit-code resolution, and full handle cleanup
 (even if AStdOutConsumer raises). Stderr is always buffered to a TBytes
 — the overloads' shapes only differ in how stdout is consumed, so
 that's the only seam.

 Returns -1 on launch failure, timeout, or cancellation; otherwise
 the child's exit code. AStdErr receives the full stderr bytes; the
 caller chooses whether to decode them.}
function RunProcessCore(const ACommandLine: string; AStdOutConsumer: TStdOutConsumer;
  out AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer;

{Drain helper exposed for callers that want to assemble their own
 buffered TStdOutConsumer or post-process the stderr bytes in a thread.
 Reads APipe until EOF / failure and returns the accumulated bytes.}
function ReadPipeToEnd(APipe: THandle): TBytes;

implementation

uses
  System.Classes,
  uLineSplitter;

function ReadPipeToEnd(APipe: THandle): TBytes;
var
  Buffer: array [0 .. 4095] of Byte;
  BytesRead: DWORD;
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create;
  try
    repeat
      BytesRead := 0;
      if not ReadFile(APipe, Buffer, SizeOf(Buffer), BytesRead, nil) then
        Break;
      if BytesRead > 0 then
        Stream.WriteBuffer(Buffer, BytesRead);
    until BytesRead = 0;
    Result := Copy(Stream.Bytes, 0, Stream.Size);
  finally
    Stream.Free;
  end;
end;

function RunProcessCore(const ACommandLine: string; AStdOutConsumer: TStdOutConsumer;
  out AStdErr: TBytes; ATimeoutMs: DWORD; ACancelHandle: THandle): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  StdOutRead, StdOutWrite: THandle;
  StdErrRead, StdErrWrite: THandle;
  StdInRead, StdInWrite: THandle;
  CmdLine: string;
  StdErrThread: TThread;
  CapturedStdErr: TBytes;
  ExitCode: DWORD;
  Watcher: TThread;
  ProcessHandleRef: THandle;
  {Set by the watcher when it terminates the child due to ATimeoutMs.
   Integer rather than Boolean so InterlockedExchange is well-defined.}
  TimedOutFlag: Integer;
begin
  Result := -1;
  AStdErr := nil;

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(StdOutRead, StdOutWrite, @SA, 0) then
    Exit;
  if not CreatePipe(StdErrRead, StdErrWrite, @SA, 0) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    Exit;
  end;
  {Empty stdin so child does not attempt interactive reads}
  if not CreatePipe(StdInRead, StdInWrite, @SA, 1) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    CloseHandle(StdErrRead);
    CloseHandle(StdErrWrite);
    Exit;
  end;
  CloseHandle(StdInWrite);

  {Parent-side read handles must not be inherited.
   StdInRead is intentionally NOT cleared here - it stays inheritable
   so CreateProcess passes it to the child via SI.hStdInput. The parent
   closes its own copy immediately after CreateProcess (line below the
   call), so the inheritable flag is harmless. Symmetric clearing was
   considered but would break the child's inheritance of stdin.}
  SetHandleInformation(StdOutRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(StdErrRead, HANDLE_FLAG_INHERIT, 0);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  SI.hStdInput := StdInRead;
  SI.hStdOutput := StdOutWrite;
  SI.hStdError := StdErrWrite;
  SI.wShowWindow := SW_HIDE;

  ZeroMemory(@PI, SizeOf(PI));

  CmdLine := ACommandLine;
  UniqueString(CmdLine);

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    CloseHandle(StdErrRead);
    CloseHandle(StdErrWrite);
    CloseHandle(StdInRead);
    Exit;
  end;

  {Child now owns the write ends; close them in parent}
  CloseHandle(StdOutWrite);
  CloseHandle(StdErrWrite);
  CloseHandle(StdInRead);

  {Read stderr on a background thread to prevent pipe deadlock}
  StdErrThread := TThread.CreateAnonymousThread(
    procedure
    begin
      CapturedStdErr := ReadPipeToEnd(StdErrRead);
    end);
  StdErrThread.FreeOnTerminate := False;
  StdErrThread.Start;

  {Single watcher handles both wall-clock timeout and optional caller cancel.
   It waits on the process handle (and the cancel event when supplied) with
   ATimeoutMs as the upper bound:
   - WAIT_OBJECT_0 (process exited): no action.
   - WAIT_OBJECT_0 + 1 (cancel signalled): TerminateProcess.
   - WAIT_TIMEOUT: TerminateProcess and flag the timeout.
   In every case TerminateProcess closes the child's pipe ends, so the
   blocking ReadPipeToEnd on the calling thread unblocks within the
   wall-clock budget instead of waiting for the child to drain stdout.}
  TimedOutFlag := 0;
  ProcessHandleRef := PI.hProcess;
  Watcher := TThread.CreateAnonymousThread(
    procedure
    var
      Handles: array [0 .. 1] of THandle;
      Count: DWORD;
    begin
      Handles[0] := ProcessHandleRef;
      Count := 1;
      if ACancelHandle <> 0 then
      begin
        Handles[1] := ACancelHandle;
        Count := 2;
      end;
      case WaitForMultipleObjects(Count, @Handles[0], False, ATimeoutMs) of
        WAIT_OBJECT_0 + 1:
          TerminateProcess(ProcessHandleRef, 1);
        WAIT_TIMEOUT:
          begin
            InterlockedExchange(TimedOutFlag, 1);
            TerminateProcess(ProcessHandleRef, 1);
          end;
        {WAIT_OBJECT_0 (process exited naturally) and any failure value:
         no further action required.}
      end;
    end);
  Watcher.FreeOnTerminate := False;
  Watcher.Start;

  try
    {Caller-supplied stdout reader runs on the calling thread. The
     pipe stays open through the call; closing happens in the finally
     block. If the consumer raises (e.g. a line callback exception in
     the streaming overload), the finally still drains the stderr
     thread and the watcher, closes every handle, and computes the
     exit code so the child is never orphaned.}
    AStdOutConsumer(StdOutRead);
  finally
    StdErrThread.WaitFor;
    AStdErr := CapturedStdErr;
    StdErrThread.Free;

    {Streams have closed, which means the child has exited (either naturally,
     or because the watcher terminated it). Wait infinite - the wall-clock
     budget has already been enforced by the watcher.}
    WaitForSingleObject(PI.hProcess, INFINITE);

    Watcher.WaitFor;
    Watcher.Free;

    if TimedOutFlag <> 0 then
      Result := -1
    else if (ACancelHandle <> 0) and (WaitForSingleObject(ACancelHandle, 0) = WAIT_OBJECT_0) then
      Result := -1
    else
    begin
      GetExitCodeProcess(PI.hProcess, ExitCode);
      Result := Integer(ExitCode);
    end;

    CloseHandle(StdOutRead);
    CloseHandle(StdErrRead);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;
end;

function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes;
  ATimeoutMs: DWORD; ACancelHandle: THandle): Integer;
var
  CapturedStdOut: TBytes;
begin
  AStdOut := nil;
  Result := RunProcessCore(ACommandLine,
    procedure(AStdOutPipe: THandle)
    begin
      CapturedStdOut := ReadPipeToEnd(AStdOutPipe);
    end,
    AStdErr, ATimeoutMs, ACancelHandle);
  AStdOut := CapturedStdOut;
end;

function RunProcess(const ACommandLine: string; AOnStdOutLine: TProc<string>;
  out AStdErr: TBytes; ATimeoutMs: DWORD; ACancelHandle: THandle): Integer;
begin
  Result := RunProcessCore(ACommandLine,
    procedure(AStdOutPipe: THandle)
    var
      Buffer: array [0 .. 4095] of Byte;
      BytesRead: DWORD;
      Splitter: TLineSplitter;
      ReadOk: Boolean;
    begin
      {Streaming stdout: read in chunks, dispatch complete lines, hold the
       trailing partial across reads. ReadFile blocks until at least one byte
       arrives or the pipe closes (which happens when the child exits or the
       watcher terminates it).}
      Splitter := Default(TLineSplitter);
      repeat
        BytesRead := 0;
        ReadOk := ReadFile(AStdOutPipe, Buffer, SizeOf(Buffer), BytesRead, nil);
        if not ReadOk then
          Break;
        if BytesRead > 0 then
          Splitter.Feed(Buffer, Integer(BytesRead), AOnStdOutLine);
      until BytesRead = 0;
      Splitter.Flush(AOnStdOutLine);
    end,
    AStdErr, ATimeoutMs, ACancelHandle);
end;

end.
