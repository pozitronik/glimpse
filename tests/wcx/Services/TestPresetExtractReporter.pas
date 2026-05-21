unit TestPresetExtractReporter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSummarizeFFmpegError = class
  public
    {Multi-line stderr: the LAST non-empty line wins because ffmpeg
     typically emits the immediate cause at the end of its output, after
     any preamble about format/codec autodetection.}
    [Test] procedure TestPicksLastNonEmptyLineFromMultilineStderr;
    [Test] procedure TestTrimsLeadingAndTrailingWhitespace;
    {Empty stderr is the dominant case for "ffmpeg failed but said
     nothing" — codec resolution failures, missing input files, etc.
     The exit code is the only signal left, so it goes into the
     fallback message.}
    [Test] procedure TestEmptyStderrFallsBackToExitCode;
    [Test] procedure TestWhitespaceOnlyStderrFallsBackToExitCode;
  end;

  [TestFixture]
  TTestMakeFailureMessage = class
  public
    {Format contract: the user sees "Preset \"X\" could not produce
     \"Y\":\n\n<summary>". The filename — not the full path — is
     embedded so the dialog stays readable when TC's destination is
     deeply nested.}
    [Test] procedure TestContainsPresetName;
    [Test] procedure TestContainsBaseFilenameNotFullPath;
    [Test] procedure TestContainsSummarizedFFmpegError;
    [Test] procedure TestEmbedsExitCodeWhenStderrEmpty;
  end;

  [TestFixture]
  TTestCapturingFailureReporter = class
  public
    {The capturing reporter is the test-double pattern this step
     unlocks. Pinning its contract here keeps later tests of
     DoExtractPreset (when that wiring lands) from rediscovering the
     same shape.}
    [Test] procedure TestCapturesSingleMessage;
    [Test] procedure TestCapturesMultipleMessagesInOrder;
    [Test] procedure TestStartsEmpty;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  WcxPresetExtractor, PresetExtractReporter;

type
  {Test-double reporter: records every message it receives so a test
   can assert what the production code would have shown the user. Made
   available to fixtures across the suite by interface composition.}
  TCapturingFailureReporter = class(TInterfacedObject, IPresetExtractFailureReporter)
  strict private
    FMessages: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Report(const AMsg: string);
    function Count: Integer;
    function Item(AIndex: Integer): string;
  end;

constructor TCapturingFailureReporter.Create;
begin
  inherited Create;
  FMessages := TList<string>.Create;
end;

destructor TCapturingFailureReporter.Destroy;
begin
  FMessages.Free;
  inherited;
end;

procedure TCapturingFailureReporter.Report(const AMsg: string);
begin
  FMessages.Add(AMsg);
end;

function TCapturingFailureReporter.Count: Integer;
begin
  Result := FMessages.Count;
end;

function TCapturingFailureReporter.Item(AIndex: Integer): string;
begin
  Result := FMessages[AIndex];
end;

function MakeCannedResult(const AStderr: string; AExitCode: Integer): TPresetExtractResult;
begin
  Result := Default(TPresetExtractResult);
  Result.Success := False;
  Result.Cancelled := False;
  Result.ExitCode := AExitCode;
  Result.ErrorMessage := AStderr;
end;

{ TTestSummarizeFFmpegError }

procedure TTestSummarizeFFmpegError.TestPicksLastNonEmptyLineFromMultilineStderr;
const
  Stderr =
    'ffmpeg version 6.0' + sLineBreak +
    '  Stream #0:0: Video: h264' + sLineBreak +
    'Output file does not contain any stream';
begin
  Assert.AreEqual('Output file does not contain any stream',
    SummarizeFFmpegError(Stderr, 1));
end;

procedure TTestSummarizeFFmpegError.TestTrimsLeadingAndTrailingWhitespace;
const
  Stderr = '   ' + sLineBreak + '  unknown encoder: libfoo  ' + sLineBreak + '';
begin
  Assert.AreEqual('unknown encoder: libfoo',
    SummarizeFFmpegError(Stderr, 1));
end;

procedure TTestSummarizeFFmpegError.TestEmptyStderrFallsBackToExitCode;
begin
  Assert.AreEqual('ffmpeg exited with code 137 (no stderr captured)',
    SummarizeFFmpegError('', 137));
end;

procedure TTestSummarizeFFmpegError.TestWhitespaceOnlyStderrFallsBackToExitCode;
begin
  Assert.AreEqual('ffmpeg exited with code 2 (no stderr captured)',
    SummarizeFFmpegError('   ' + sLineBreak + #9, 2));
end;

{ TTestMakeFailureMessage }

procedure TTestMakeFailureMessage.TestContainsPresetName;
var
  R: TPresetExtractResult;
  Msg: string;
begin
  R := MakeCannedResult('out of memory', 1);
  Msg := MakeFailureMessage('Convert to 480p', 'C:\out\video.mp4', R);
  Assert.IsTrue(Pos('Convert to 480p', Msg) > 0,
    'Composed message must surface the preset name');
end;

procedure TTestMakeFailureMessage.TestContainsBaseFilenameNotFullPath;
var
  R: TPresetExtractResult;
  Msg: string;
begin
  R := MakeCannedResult('codec not found', 1);
  Msg := MakeFailureMessage('Any', 'C:\Users\me\deeply\nested\out.mp4', R);
  Assert.IsTrue(Pos('out.mp4', Msg) > 0, 'Filename must be present');
  Assert.IsTrue(Pos('C:\Users\me\deeply\nested', Msg) = 0,
    'Directory path must NOT be embedded (keeps the dialog readable)');
end;

procedure TTestMakeFailureMessage.TestContainsSummarizedFFmpegError;
var
  R: TPresetExtractResult;
  Msg: string;
begin
  R := MakeCannedResult('preamble' + sLineBreak + 'Invalid argument', 1);
  Msg := MakeFailureMessage('Any', 'x.mp4', R);
  Assert.IsTrue(Pos('Invalid argument', Msg) > 0,
    'Last non-empty stderr line must reach the user');
end;

procedure TTestMakeFailureMessage.TestEmbedsExitCodeWhenStderrEmpty;
var
  R: TPresetExtractResult;
  Msg: string;
begin
  R := MakeCannedResult('', 42);
  Msg := MakeFailureMessage('Any', 'x.mp4', R);
  Assert.IsTrue(Pos('exited with code 42', Msg) > 0,
    'Exit code must be present in the fallback path');
end;

{ TTestCapturingFailureReporter }

procedure TTestCapturingFailureReporter.TestCapturesSingleMessage;
var
  Reporter: TCapturingFailureReporter;
  Iface: IPresetExtractFailureReporter;
begin
  Reporter := TCapturingFailureReporter.Create;
  Iface := Reporter;
  try
    Iface.Report('hello world');
    Assert.AreEqual<Integer>(1, Reporter.Count);
    Assert.AreEqual('hello world', Reporter.Item(0));
  finally
    Iface := nil;
  end;
end;

procedure TTestCapturingFailureReporter.TestCapturesMultipleMessagesInOrder;
var
  Reporter: TCapturingFailureReporter;
  Iface: IPresetExtractFailureReporter;
begin
  Reporter := TCapturingFailureReporter.Create;
  Iface := Reporter;
  try
    Iface.Report('first');
    Iface.Report('second');
    Iface.Report('third');
    Assert.AreEqual<Integer>(3, Reporter.Count);
    Assert.AreEqual('first', Reporter.Item(0));
    Assert.AreEqual('second', Reporter.Item(1));
    Assert.AreEqual('third', Reporter.Item(2));
  finally
    Iface := nil;
  end;
end;

procedure TTestCapturingFailureReporter.TestStartsEmpty;
var
  Reporter: TCapturingFailureReporter;
  Iface: IPresetExtractFailureReporter;
begin
  Reporter := TCapturingFailureReporter.Create;
  Iface := Reporter;
  try
    Assert.AreEqual<Integer>(0, Reporter.Count);
  finally
    Iface := nil;
  end;
end;

end.
