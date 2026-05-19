{Windows process execution with stdout/stderr capture.}
unit uRunProcess;

interface

uses
  System.SysUtils, Winapi.Windows;

type
  {Pipe handle is closed by the core after the callback returns or
   raises; the callback must NOT close it.}
  TStdOutConsumer = reference to procedure(AStdOutPipe: THandle);

{Returns -1 on launch failure, timeout, or cancellation. ACancelHandle
 signal terminates the child via a watcher thread.}
function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer; overload;

{Streaming overload: dispatches each line as it arrives. UTF-8 with
 replacement; stderr is buffered to completion. Callers signal cancel
 via ACancelHandle. Exceptions from AOnStdOutLine propagate after the
 child exits, so the process is never orphaned.}
function RunProcess(const ACommandLine: string; AOnStdOutLine: TProc<string>; out AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer; overload;

{Returns -1 on launch failure, timeout, or cancellation; otherwise the
 child's exit code.}
function RunProcessCore(const ACommandLine: string; AStdOutConsumer: TStdOutConsumer;
  out AStdErr: TBytes; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): Integer;

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
  {Integer (not Boolean) so InterlockedExchange is well-defined.}
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
  {Empty stdin so child does not attempt interactive reads.}
  if not CreatePipe(StdInRead, StdInWrite, @SA, 1) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    CloseHandle(StdErrRead);
    CloseHandle(StdErrWrite);
    Exit;
  end;
  CloseHandle(StdInWrite);

  {StdInRead stays inheritable so the child can inherit it via SI.hStdInput.}
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

  CloseHandle(StdOutWrite);
  CloseHandle(StdErrWrite);
  CloseHandle(StdInRead);

  {Background thread to prevent pipe deadlock if stderr fills first.}
  StdErrThread := TThread.CreateAnonymousThread(
    procedure
    begin
      CapturedStdErr := ReadPipeToEnd(StdErrRead);
    end);
  StdErrThread.FreeOnTerminate := False;
  StdErrThread.Start;

  {TerminateProcess closes the child's pipes; the blocking ReadPipeToEnd
   on the calling thread unblocks within the wall-clock budget.}
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
      end;
    end);
  Watcher.FreeOnTerminate := False;
  Watcher.Start;

  try
    AStdOutConsumer(StdOutRead);
  finally
    StdErrThread.WaitFor;
    AStdErr := CapturedStdErr;
    StdErrThread.Free;

    {Wait infinite — wall-clock budget enforced by the watcher already.}
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
