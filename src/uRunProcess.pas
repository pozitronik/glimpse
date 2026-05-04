{General-purpose Windows process execution with stdout/stderr capture.
 No application-specific logic.}
unit uRunProcess;

interface

uses
  System.SysUtils, Winapi.Windows;

{Runs a process with redirected stdout/stderr, captures both outputs.
 Returns the process exit code, or -1 on launch failure, timeout, or cancellation.
 ACancelHandle is an optional Win32 waitable handle (typically TEvent.Handle). When
 signaled mid-run, a watcher thread terminates the child process, which cascades
 through pipe closure and unblocks the otherwise-blocking ReadFile calls.}
function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer;

implementation

uses
  System.Classes;

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

function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer;
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
  AStdOut := nil;
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

  {Parent-side read handles must not be inherited}
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
      Handles: array[0..1] of THandle;
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

  {Read stdout on the calling thread. If the watcher terminates the child,
   pipe closure unblocks this read.}
  AStdOut := ReadPipeToEnd(StdOutRead);

  StdErrThread.WaitFor;
  AStdErr := CapturedStdErr;
  StdErrThread.Free;

  {Streams have closed, which means the child has exited (either naturally,
   or because the watcher terminated it). Wait infinite -- the wall-clock
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

end.
