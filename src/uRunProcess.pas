{General-purpose Windows process execution with stdout/stderr capture.
 No application-specific logic.}
unit uRunProcess;

interface

uses
  System.SysUtils, Winapi.Windows;

{Runs a process with redirected stdout/stderr, captures both outputs.
 Returns the process exit code, or -1 on launch failure or timeout.}
function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes; ATimeoutMs: DWORD = 30000): Integer;

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

function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes; ATimeoutMs: DWORD = 30000): Integer;
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

  {Read stdout on the calling thread}
  AStdOut := ReadPipeToEnd(StdOutRead);

  StdErrThread.WaitFor;
  AStdErr := CapturedStdErr;
  StdErrThread.Free;

  if WaitForSingleObject(PI.hProcess, ATimeoutMs) = WAIT_OBJECT_0 then
  begin
    GetExitCodeProcess(PI.hProcess, ExitCode);
    Result := Integer(ExitCode);
  end else begin
    TerminateProcess(PI.hProcess, 1);
    Result := -1;
  end;

  CloseHandle(StdOutRead);
  CloseHandle(StdErrRead);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
end;

end.
