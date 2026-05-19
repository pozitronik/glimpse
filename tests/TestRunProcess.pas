unit TestRunProcess;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRunProcess = class
  public
    [Test] procedure CapturesStdOut;
    [Test] procedure CapturesStdErr;
    [Test] procedure ReturnsExitCode_Zero;
    [Test] procedure ReturnsExitCode_NonZero;
    [Test] procedure ReturnsMinusOne_ForNonExistentExe;
    [Test] procedure SimultaneousStdOutAndStdErr;
    [Test] procedure EmptyOutput_ProducesEmptyBytes;
    [Test] procedure LargeOutput_CapturedFully;
    {Wall-clock timeout: ATimeoutMs is the budget for total elapsed
     time, not just the post-output wait. Earlier the function blocked
     on ReadPipeToEnd until the child's stdout pipe closed, so a child
     that produced nothing for 30 seconds blocked the call for 30
     seconds regardless of the 500 ms timeout. The fix is a watcher
     thread that terminates the child once ATimeoutMs elapses,
     cascading through pipe closure.}
    [Test] procedure Timeout_TerminatesSlowChildWithinBudget;
    [Test] procedure BinaryOutput_PreservedExactly;
    { Cancellation contract: an optional cancel handle unblocks a long-running
      child by killing it, which cascades through pipe closure. }
    [Test] procedure CancelHandle_DefaultZeroPreservesBehavior;
    [Test] procedure CancelHandle_NotSignaledRunsToCompletion;
    [Test] procedure CancelHandle_SignaledTerminatesLongRunningChild;
    { Streaming overload: dispatches each stdout line as it arrives so callers
      can react to incremental progress (used by the WCX preset extractor). }
    [Test] procedure Streaming_DispatchesEachLineSeparately;
    [Test] procedure Streaming_StripsTrailingCarriageReturn;
    [Test] procedure Streaming_FinalLineWithoutTerminatorStillDispatched;
    [Test] procedure Streaming_EmptyLinesSwallowed;
    [Test] procedure Streaming_StderrStillBuffered;
    [Test] procedure Streaming_ReturnsExitCode;
    [Test] procedure Streaming_CancelHandleStopsLongRunningChild;
    {Exercises RunProcessCore directly with a custom consumer that reads
     the stdout pipe — pins the core contract (consumer runs on calling
     thread, pipe handle is valid for the call, exit code propagated,
     cleanup happens in finally even if the consumer raises).}
    [Test] procedure RunProcessCore_CustomConsumer_ReceivesPipeAndExitCode;
    [Test] procedure RunProcessCore_RaisingConsumer_StillCleansUpProcess;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, Winapi.Windows, uRunProcess;

procedure TTestRunProcess.CapturesStdOut;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  Output: string;
begin
  Code := RunProcess('cmd.exe /c echo hello', StdOut, StdErr);
  Assert.AreEqual(0, Code, 'Exit code');
  Output := TEncoding.Default.GetString(StdOut).Trim;
  Assert.AreEqual('hello', Output, 'StdOut content');
end;

procedure TTestRunProcess.CapturesStdErr;
var
  StdOut, StdErr: TBytes;
  Output: string;
begin
  { "echo text 1>&2" redirects to stderr }
  RunProcess('cmd.exe /c echo errmsg 1>&2', StdOut, StdErr);
  Output := TEncoding.Default.GetString(StdErr).Trim;
  Assert.AreEqual('errmsg', Output, 'StdErr content');
end;

procedure TTestRunProcess.ReturnsExitCode_Zero;
var
  StdOut, StdErr: TBytes;
begin
  Assert.AreEqual(0, RunProcess('cmd.exe /c exit 0', StdOut, StdErr));
end;

procedure TTestRunProcess.ReturnsExitCode_NonZero;
var
  StdOut, StdErr: TBytes;
begin
  Assert.AreEqual(42, RunProcess('cmd.exe /c exit 42', StdOut, StdErr));
end;

procedure TTestRunProcess.ReturnsMinusOne_ForNonExistentExe;
var
  StdOut, StdErr: TBytes;
begin
  Assert.AreEqual(-1, RunProcess('__nonexistent_binary_12345__.exe', StdOut, StdErr));
end;

procedure TTestRunProcess.SimultaneousStdOutAndStdErr;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  OutStr, ErrStr: string;
begin
  { Produces output on both streams in a single command }
  Code := RunProcess('cmd.exe /c echo stdout_msg && echo stderr_msg 1>&2',
    StdOut, StdErr);
  Assert.AreEqual(0, Code, 'Exit code');
  OutStr := TEncoding.Default.GetString(StdOut).Trim;
  ErrStr := TEncoding.Default.GetString(StdErr).Trim;
  Assert.AreEqual('stdout_msg', OutStr, 'StdOut');
  Assert.AreEqual('stderr_msg', ErrStr, 'StdErr');
end;

procedure TTestRunProcess.EmptyOutput_ProducesEmptyBytes;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
begin
  { cmd /c with no command produces minimal output }
  Code := RunProcess('cmd.exe /c exit 0', StdOut, StdErr);
  Assert.AreEqual(0, Code, 'Exit code');
  Assert.AreEqual(0, Integer(Length(StdOut)), 'StdOut should be empty');
  Assert.AreEqual(0, Integer(Length(StdErr)), 'StdErr should be empty');
end;

procedure TTestRunProcess.LargeOutput_CapturedFully;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  Output: string;
begin
  { Generate 1000 lines of output to stress pipe reading logic }
  Code := RunProcess(
    'cmd.exe /c "for /L %i in (1,1,1000) do @echo line_%i"',
    StdOut, StdErr);
  Assert.AreEqual(0, Code, 'Exit code');
  Output := TEncoding.Default.GetString(StdOut);
  Assert.IsTrue(Output.Contains('line_1'), 'Should contain first line');
  Assert.IsTrue(Output.Contains('line_1000'), 'Should contain last line');
end;

procedure TTestRunProcess.Timeout_TerminatesSlowChildWithinBudget;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  StartTick, Elapsed: Cardinal;
begin
  {Child sleeps 10 seconds with no output; without the watcher fix,
   ReadPipeToEnd blocks for the full 10 seconds because stdout never closes
   until the child exits. ATimeoutMs=500 must kill it well under that.
   PowerShell cold start can take ~2 seconds, so allow 5 seconds for the
   whole call.}
  StartTick := GetTickCount;
  Code := RunProcess(
    'powershell -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 10"',
    StdOut, StdErr, 500);
  Elapsed := GetTickCount - StartTick;
  Assert.AreEqual(-1, Code, 'Timed-out process must return -1');
  Assert.IsTrue(Elapsed < 5000,
    Format('Wall-clock budget broken; ATimeoutMs=500 elapsed=%dms', [Elapsed]));
end;

procedure TTestRunProcess.BinaryOutput_PreservedExactly;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  I: Integer;
  AllPresent: Boolean;
begin
  { Verify that binary-like output bytes survive pipe capture intact.
    "cmd /c type" on a small binary would work, but for simplicity
    we check that multi-line cmd output preserves CR/LF bytes. }
  Code := RunProcess('cmd.exe /c echo line1 && echo line2', StdOut, StdErr);
  Assert.AreEqual(0, Code, 'Exit code');
  { Raw output must contain CR+LF between lines }
  AllPresent := False;
  for I := 0 to Length(StdOut) - 2 do
    if (StdOut[I] = $0D) and (StdOut[I + 1] = $0A) then
    begin
      AllPresent := True;
      Break;
    end;
  Assert.IsTrue(AllPresent, 'Raw bytes should contain CR+LF');
end;

procedure TTestRunProcess.CancelHandle_DefaultZeroPreservesBehavior;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  Output: string;
begin
  { Passing 0 (default) for ACancelHandle must be indistinguishable from
    omitting the parameter entirely - no watcher thread, no behavior change. }
  Code := RunProcess('cmd.exe /c echo hello', StdOut, StdErr, 30000, 0);
  Assert.AreEqual(0, Code, 'Exit code');
  Output := TEncoding.Default.GetString(StdOut).Trim;
  Assert.AreEqual('hello', Output, 'StdOut content');
end;

procedure TTestRunProcess.CancelHandle_NotSignaledRunsToCompletion;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  Output: string;
  CancelEvent: TEvent;
begin
  { A real cancel handle that is never signaled must not disturb normal flow:
    the child runs to completion, the watcher wakes up on the process-exit
    signal, and it exits without killing anything. }
  CancelEvent := TEvent.Create(nil, True, False, '');
  try
    Code := RunProcess('cmd.exe /c echo hello', StdOut, StdErr, 30000,
      CancelEvent.Handle);
    Assert.AreEqual(0, Code, 'Exit code');
    Output := TEncoding.Default.GetString(StdOut).Trim;
    Assert.AreEqual('hello', Output, 'StdOut content');
  finally
    CancelEvent.Free;
  end;
end;

procedure TTestRunProcess.CancelHandle_SignaledTerminatesLongRunningChild;
var
  StdOut, StdErr: TBytes;
  Code: Integer;
  CancelEvent: TEvent;
  Signaler: TThread;
  StartTick, Elapsed: Cardinal;
  LocalEvent: TEvent;
begin
  { Signal cancel mid-run on a 30-second sleep. The watcher must kill the
    child quickly and let RunProcess return -1 in well under the child's
    natural duration. 5-second tolerance accounts for PowerShell startup
    (up to ~2s on cold runs) plus cancel propagation. }
  CancelEvent := TEvent.Create(nil, True, False, '');
  try
    LocalEvent := CancelEvent;
    Signaler := TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(300);
        LocalEvent.SetEvent;
      end);
    Signaler.FreeOnTerminate := False;
    Signaler.Start;
    try
      StartTick := GetTickCount;
      Code := RunProcess(
        'powershell -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"',
        StdOut, StdErr, 60000, CancelEvent.Handle);
      Elapsed := GetTickCount - StartTick;
    finally
      Signaler.WaitFor;
      Signaler.Free;
    end;
    Assert.AreEqual(-1, Code, 'Cancelled process should return -1');
    Assert.IsTrue(Elapsed < 5000,
      Format('Cancel should complete within 5s; elapsed=%dms', [Elapsed]));
  finally
    CancelEvent.Free;
  end;
end;

procedure TTestRunProcess.Streaming_DispatchesEachLineSeparately;
var
  StdErr: TBytes;
  Lines: TStringList;
  Code: Integer;
begin
  { Three echo commands chained produce three CRLF-terminated lines; the
    splitter must hand them back as three separate dispatches in order.
    cmd.exe's `echo X &&` form leaves trailing whitespace on each line, so
    Trim before asserting content — the splitter's contract is splitting,
    not whitespace normalisation. }
  Lines := TStringList.Create;
  try
    Code := RunProcess('cmd.exe /c "echo one && echo two && echo three"',
      procedure(L: string)
      begin
        Lines.Add(L.Trim);
      end, StdErr);
    Assert.AreEqual(0, Code);
    Assert.AreEqual(3, Lines.Count);
    Assert.AreEqual('one', Lines[0]);
    Assert.AreEqual('two', Lines[1]);
    Assert.AreEqual('three', Lines[2]);
  finally
    Lines.Free;
  end;
end;

procedure TTestRunProcess.Streaming_StripsTrailingCarriageReturn;
var
  StdErr: TBytes;
  CapturedLine: string;
begin
  { cmd.exe emits CRLF; the splitter must strip the CR so callers see a
    clean line. Without stripping, ffmpeg progress parsers would fail to
    match keys like "progress=end" because of the trailing #13. }
  CapturedLine := '__none__';
  RunProcess('cmd.exe /c echo hello',
    procedure(L: string)
    begin
      CapturedLine := L;
    end, StdErr);
  Assert.AreEqual('hello', CapturedLine);
end;

procedure TTestRunProcess.Streaming_FinalLineWithoutTerminatorStillDispatched;
var
  StdErr: TBytes;
  Lines: TStringList;
begin
  { `echo|set /p=` writes without a trailing newline. The Flush step at
    end-of-stream must still hand the tail to the callback so progress
    extractors do not lose the last status update. }
  Lines := TStringList.Create;
  try
    RunProcess('cmd.exe /c "<NUL set /p=tail"',
      procedure(L: string)
      begin
        Lines.Add(L);
      end, StdErr);
    Assert.AreEqual(1, Lines.Count, 'Tail without LF must still dispatch');
    Assert.AreEqual('tail', Lines[0]);
  finally
    Lines.Free;
  end;
end;

procedure TTestRunProcess.Streaming_EmptyLinesSwallowed;
var
  StdErr: TBytes;
  Lines: TStringList;
begin
  { Blank lines (CRLF with no content) carry no information and would only
    spam the callback; suppress them at the splitter. PowerShell gives a
    reliable empty-line emitter; cmd's `echo.` is too quirky across
    Windows builds. }
  Lines := TStringList.Create;
  try
    RunProcess(
      'powershell -NoProfile -NonInteractive -Command "''a''; ''''; ''b''"',
      procedure(L: string)
      begin
        Lines.Add(L);
      end, StdErr);
    Assert.AreEqual(2, Lines.Count, 'Blank line must not reach the callback');
    Assert.AreEqual('a', Lines[0]);
    Assert.AreEqual('b', Lines[1]);
  finally
    Lines.Free;
  end;
end;

procedure TTestRunProcess.Streaming_StderrStillBuffered;
var
  StdErr: TBytes;
  Lines: TStringList;
  ErrStr: string;
begin
  { Stderr keeps the buffered semantics so the caller can show the error
    message on failure. The line callback must not see stderr lines. Trim
    on the captured line accommodates cmd's trailing whitespace from `&&`. }
  Lines := TStringList.Create;
  try
    RunProcess('cmd.exe /c "echo good && echo bad 1>&2"',
      procedure(L: string)
      begin
        Lines.Add(L.Trim);
      end, StdErr);
    Assert.AreEqual(1, Lines.Count, 'Stderr must not flow into the line callback');
    Assert.AreEqual('good', Lines[0]);
    ErrStr := TEncoding.Default.GetString(StdErr).Trim;
    Assert.AreEqual('bad', ErrStr);
  finally
    Lines.Free;
  end;
end;

procedure TTestRunProcess.Streaming_ReturnsExitCode;
var
  StdErr: TBytes;
begin
  { Exit code propagation matches the buffered overload. }
  Assert.AreEqual(7, RunProcess('cmd.exe /c exit 7',
    procedure(L: string) begin end, StdErr));
end;

procedure TTestRunProcess.Streaming_CancelHandleStopsLongRunningChild;
var
  StdErr: TBytes;
  Code: Integer;
  CancelEvent: TEvent;
  Signaler: TThread;
  StartTick, Elapsed: Cardinal;
  LocalEvent: TEvent;
begin
  CancelEvent := TEvent.Create(nil, True, False, '');
  try
    LocalEvent := CancelEvent;
    Signaler := TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(300);
        LocalEvent.SetEvent;
      end);
    Signaler.FreeOnTerminate := False;
    Signaler.Start;
    try
      StartTick := GetTickCount;
      Code := RunProcess(
        'powershell -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"',
        procedure(L: string) begin end,
        StdErr, 60000, CancelEvent.Handle);
      Elapsed := GetTickCount - StartTick;
    finally
      Signaler.WaitFor;
      Signaler.Free;
    end;
    Assert.AreEqual(-1, Code, 'Cancelled streaming run must return -1');
    Assert.IsTrue(Elapsed < 5000,
      Format('Cancel must complete in <5s; elapsed=%dms', [Elapsed]));
  finally
    CancelEvent.Free;
  end;
end;

procedure TTestRunProcess.RunProcessCore_CustomConsumer_ReceivesPipeAndExitCode;
var
  StdErr: TBytes;
  Captured: TBytes;
  ConsumerInvoked: Boolean;
  ExitCode: Integer;
begin
  {The custom consumer drains stdout via ReadPipeToEnd (same primitive
   the public buffered overload uses). Verifies that the core delivers
   a valid pipe handle to the consumer and that the exit code returned
   by the core matches what the child process emitted.}
  Captured := nil;
  ConsumerInvoked := False;
  ExitCode := RunProcessCore('cmd.exe /c echo direct-core-test',
    procedure(AStdOutPipe: THandle)
    begin
      ConsumerInvoked := True;
      Assert.AreNotEqual(THandle(0), AStdOutPipe,
        'Consumer must receive a valid pipe handle');
      Captured := ReadPipeToEnd(AStdOutPipe);
    end,
    StdErr, 10000, 0);

  Assert.IsTrue(ConsumerInvoked, 'Consumer must be invoked exactly once');
  Assert.AreEqual<Integer>(0, ExitCode, 'cmd.exe echo must exit 0');
  Assert.IsTrue(Length(Captured) > 0, 'Captured stdout must be non-empty');
end;

procedure TTestRunProcess.RunProcessCore_RaisingConsumer_StillCleansUpProcess;
var
  StdErr: TBytes;
  Raised: Boolean;
begin
  {If the consumer raises mid-call, the core's try/finally must still
   drain the stderr thread, wait on the watcher, close every handle,
   and let the exception propagate. The test verifies the exception
   propagates and that a follow-up call works (which it would not if
   handles or threads leaked across the call boundary).}
  Raised := False;
  try
    RunProcessCore('cmd.exe /c echo will-be-ignored',
      procedure(AStdOutPipe: THandle)
      begin
        raise EAssertionFailed.Create('intentional consumer failure');
      end,
      StdErr, 10000, 0);
  except
    on E: EAssertionFailed do
      Raised := E.Message = 'intentional consumer failure';
  end;
  Assert.IsTrue(Raised, 'Consumer exception must propagate through the core');

  {A follow-up successful call proves no orphaned handles / threads
   from the raising call.}
  RunProcessCore('cmd.exe /c echo after-raise',
    procedure(AStdOutPipe: THandle)
    var
      Drained: TBytes;
    begin
      Drained := ReadPipeToEnd(AStdOutPipe);
      Assert.IsTrue(Length(Drained) > 0, 'Follow-up call must succeed');
    end,
    StdErr, 10000, 0);
end;

end.
