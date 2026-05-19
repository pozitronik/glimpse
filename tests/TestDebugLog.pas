unit TestDebugLog;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDebugLog = class
  private
    FTempDir: string;
    FLogPath: string;
    FSavedPath: string;

    { Returns all lines from the log file. }
    function ReadLogLines: TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestEmptyPathIsNoOp;
    [Test]
    procedure TestCreatesNewFile;
    [Test]
    procedure TestAppendsToExistingFile;
    [Test]
    procedure TestLineContainsTag;
    [Test]
    procedure TestLineContainsMessage;
    [Test]
    procedure TestLineContainsThreadId;
    [Test]
    procedure TestLineContainsTimestamp;
    [Test]
    procedure TestInvalidPathDoesNotRaise;
    [Test]
    procedure TestMultipleCallsAppend;
    [Test]
    procedure TestConcurrentWritesNoLoss;
    [Test]
    procedure TestDebugLoggerForwardsTagAndMessage;
    [Test]
    procedure TestDebugLoggerCapturesTagPerInstance;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.SyncObjs,
  uDebugLog;

procedure TTestDebugLog.Setup;
begin
  FSavedPath := TDebugLog.Instance.ActivePath;
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_LogTest_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FLogPath := TPath.Combine(FTempDir, 'test.log');
  {Setup does NOT Configure the singleton; tests needing a configured
   state call TDebugLog.Instance.Configure(FLogPath) themselves.
   "Starts unconfigured" tests (e.g. TestEmptyPathIsNoOp,
   TestCreatesNewFile) rely on the singleton not having created the
   file, since Configure opens it eagerly.}
end;

procedure TTestDebugLog.TearDown;
begin
  {Restore the prior path FIRST so the test's file is released, then
   try to delete the directory. Inverting this order would leave the
   TStreamWriter holding the test.log open and the directory delete
   would fail (or partially fail on the file-with-active-writer).}
  TDebugLog.Instance.Configure(FSavedPath);
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestDebugLog.ReadLogLines: TArray<string>;
var
  Stream: TFileStream;
  Reader: TStreamReader;
  Lines: TStringList;
begin
  Result := nil;
  if not TFile.Exists(FLogPath) then
    Exit;
  {TFile.ReadAllLines opens with fmShareDenyWrite which conflicts with
   our singleton's still-open writer. Open manually with fmShareDenyNone
   so the test can read while the writer is live.}
  Stream := TFileStream.Create(FLogPath, fmOpenRead or fmShareDenyNone);
  try
    Reader := TStreamReader.Create(Stream, TEncoding.UTF8, True);
    try
      Lines := TStringList.Create;
      try
        while not Reader.EndOfStream do
          Lines.Add(Reader.ReadLine);
        Result := Lines.ToStringArray;
      finally
        Lines.Free;
      end;
    finally
      Reader.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TTestDebugLog.TestEmptyPathIsNoOp;
begin
  TDebugLog.Instance.Configure('');
  DebugLog('Test', 'Should not be written');
  Assert.IsFalse(TFile.Exists(FLogPath),
    'No file must be created when Configure was called with empty path');
end;

procedure TTestDebugLog.TestCreatesNewFile;
begin
  Assert.IsFalse(TFile.Exists(FLogPath), 'Precondition: file must not exist');
  TDebugLog.Instance.Configure(FLogPath);
  Assert.IsTrue(TFile.Exists(FLogPath),
    'Configure must bring the log file into existence (eager open)');
end;

procedure TTestDebugLog.TestAppendsToExistingFile;
begin
  TFile.WriteAllText(FLogPath, 'existing line' + sLineBreak);
  TDebugLog.Instance.Configure(FLogPath);
  DebugLog('Test', 'appended');
  var Lines := ReadLogLines;
  Assert.IsTrue(Length(Lines) >= 2,
    'Must append to existing content, not overwrite');
  Assert.AreEqual('existing line', Lines[0],
    'Original content must be preserved');
end;

procedure TTestDebugLog.TestLineContainsTag;
begin
  TDebugLog.Instance.Configure(FLogPath);
  DebugLog('MySubsystem', 'hello');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('[MySubsystem]'),
    'Log line must contain the tag in brackets');
end;

procedure TTestDebugLog.TestLineContainsMessage;
begin
  TDebugLog.Instance.Configure(FLogPath);
  DebugLog('T', 'the actual message');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('the actual message'),
    'Log line must contain the message text');
end;

procedure TTestDebugLog.TestLineContainsThreadId;
begin
  TDebugLog.Instance.Configure(FLogPath);
  DebugLog('T', 'msg');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('[tid='),
    'Log line must contain thread ID marker');
end;

procedure TTestDebugLog.TestLineContainsTimestamp;
begin
  TDebugLog.Instance.Configure(FLogPath);
  DebugLog('T', 'msg');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  { Timestamp format: hh:nn:ss.zzz (12 chars with colons and dot) }
  Assert.IsTrue(Lines[0].Contains(':') and Lines[0].Contains('.'),
    'Log line must contain a timestamp with colons and dot');
end;

procedure TTestDebugLog.TestInvalidPathDoesNotRaise;
begin
  { Point to a path that cannot be written (non-existent deep directory).
    Configure must swallow the open failure; DebugLog must no-op cleanly. }
  TDebugLog.Instance.Configure('Z:\no\such\deep\path\log.txt');
  DebugLog('Fail', 'should not raise');
  Assert.Pass('Configure + DebugLog must never raise on an unwritable path');
end;

procedure TTestDebugLog.TestMultipleCallsAppend;
begin
  TDebugLog.Instance.Configure(FLogPath);
  DebugLog('A', 'first');
  DebugLog('B', 'second');
  DebugLog('C', 'third');
  var Lines := ReadLogLines;
  Assert.AreEqual(3, Integer(Length(Lines)), 'Each call must append one line');
  Assert.IsTrue(Lines[0].Contains('[A]'));
  Assert.IsTrue(Lines[1].Contains('[B]'));
  Assert.IsTrue(Lines[2].Contains('[C]'));
end;

type
  { Helper thread that writes a batch of log lines }
  TLogWriter = class(TThread)
  private
    FTag: string;
    FCount: Integer;
    FReady: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(const ATag: string; ACount: Integer; AReady: TEvent);
  end;

constructor TLogWriter.Create(const ATag: string; ACount: Integer; AReady: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FTag := ATag;
  FCount := ACount;
  FReady := AReady;
end;

procedure TLogWriter.Execute;
var
  I: Integer;
begin
  { Wait for the go signal so all threads start writing at the same time }
  FReady.WaitFor(5000);
  for I := 0 to FCount - 1 do
    DebugLog(FTag, Format('line_%d', [I]));
end;

procedure TTestDebugLog.TestConcurrentWritesNoLoss;
const
  THREAD_COUNT = 8;
  LINES_PER_THREAD = 50;
var
  Threads: array[0..THREAD_COUNT - 1] of TLogWriter;
  Ready: TEvent;
  I: Integer;
  Lines: TArray<string>;
begin
  TDebugLog.Instance.Configure(FLogPath);
  Ready := TEvent.Create(nil, True, False, '');
  try
    for I := 0 to THREAD_COUNT - 1 do
      Threads[I] := TLogWriter.Create(Format('T%d', [I]), LINES_PER_THREAD, Ready);

    { Start all threads, then signal them to write simultaneously }
    for I := 0 to THREAD_COUNT - 1 do
      Threads[I].Start;
    Ready.SetEvent;

    for I := 0 to THREAD_COUNT - 1 do
    begin
      Threads[I].WaitFor;
      Threads[I].Free;
    end;
  finally
    Ready.Free;
  end;

  Lines := ReadLogLines;
  Assert.AreEqual(THREAD_COUNT * LINES_PER_THREAD, Integer(Length(Lines)),
    'Every log line from every thread must be present');
end;

procedure TTestDebugLog.TestDebugLoggerForwardsTagAndMessage;
var
  Log: TProc<string>;
  Lines: TArray<string>;
begin
  {DebugLogger returns a closure that prepends the captured tag and
   forwards the message to DebugLog. The output line must contain both
   the tag (in [Tag] form) and the original message text.}
  TDebugLog.Instance.Configure(FLogPath);
  Log := DebugLogger('Closure1');
  Log('hello from closure');
  Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Pos('[Closure1]', Lines[0]) > 0, 'Line must contain the captured tag');
  Assert.IsTrue(Pos('hello from closure', Lines[0]) > 0, 'Line must contain the message');
end;

procedure TTestDebugLog.TestDebugLoggerCapturesTagPerInstance;
var
  LogA, LogB: TProc<string>;
  Lines: TArray<string>;
begin
  {Two closures created from different tags must each carry their own
   tag — pins the per-call-time capture so future closure-state bugs
   (shared mutable tag, broken capture) surface here.}
  TDebugLog.Instance.Configure(FLogPath);
  LogA := DebugLogger('TagA');
  LogB := DebugLogger('TagB');
  LogA('msg-a');
  LogB('msg-b');
  Lines := ReadLogLines;
  Assert.AreEqual(2, Integer(Length(Lines)));
  Assert.IsTrue(Pos('[TagA]', Lines[0]) > 0, 'First line must have TagA');
  Assert.IsTrue(Pos('[TagB]', Lines[1]) > 0, 'Second line must have TagB');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDebugLog);

end.
