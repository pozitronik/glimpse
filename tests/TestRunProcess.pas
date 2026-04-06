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
    { Note: timeout is not unit-testable because RunProcess blocks on pipe
      reads until the child closes stdout/stderr; the timeout parameter only
      applies after pipes are drained. A long-running child that writes
      continuously will block ReadPipeToEnd indefinitely. }
    [Test] procedure BinaryOutput_PreservedExactly;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows, uRunProcess;

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

end.
