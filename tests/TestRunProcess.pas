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

end.
