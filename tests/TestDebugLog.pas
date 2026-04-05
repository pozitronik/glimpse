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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.SyncObjs,
  uDebugLog;

procedure TTestDebugLog.Setup;
begin
  FSavedPath := GDebugLogPath;
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_LogTest_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FLogPath := TPath.Combine(FTempDir, 'test.log');
  GDebugLogPath := FLogPath;
end;

procedure TTestDebugLog.TearDown;
begin
  GDebugLogPath := FSavedPath;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestDebugLog.ReadLogLines: TArray<string>;
begin
  if TFile.Exists(FLogPath) then
    Result := TFile.ReadAllLines(FLogPath)
  else
    Result := nil;
end;

procedure TTestDebugLog.TestEmptyPathIsNoOp;
begin
  GDebugLogPath := '';
  DebugLog('Test', 'Should not be written');
  Assert.IsFalse(TFile.Exists(FLogPath),
    'No file must be created when GDebugLogPath is empty');
end;

procedure TTestDebugLog.TestCreatesNewFile;
begin
  Assert.IsFalse(TFile.Exists(FLogPath), 'Precondition: file must not exist');
  DebugLog('Init', 'first entry');
  Assert.IsTrue(TFile.Exists(FLogPath),
    'Log file must be created on first write');
end;

procedure TTestDebugLog.TestAppendsToExistingFile;
begin
  TFile.WriteAllText(FLogPath, 'existing line' + sLineBreak);
  DebugLog('Test', 'appended');
  var Lines := ReadLogLines;
  Assert.IsTrue(Length(Lines) >= 2,
    'Must append to existing content, not overwrite');
  Assert.AreEqual('existing line', Lines[0],
    'Original content must be preserved');
end;

procedure TTestDebugLog.TestLineContainsTag;
begin
  DebugLog('MySubsystem', 'hello');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('[MySubsystem]'),
    'Log line must contain the tag in brackets');
end;

procedure TTestDebugLog.TestLineContainsMessage;
begin
  DebugLog('T', 'the actual message');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('the actual message'),
    'Log line must contain the message text');
end;

procedure TTestDebugLog.TestLineContainsThreadId;
begin
  DebugLog('T', 'msg');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('[tid='),
    'Log line must contain thread ID marker');
end;

procedure TTestDebugLog.TestLineContainsTimestamp;
begin
  DebugLog('T', 'msg');
  var Lines := ReadLogLines;
  Assert.AreEqual(1, Integer(Length(Lines)));
  { Timestamp format: hh:nn:ss.zzz (12 chars with colons and dot) }
  Assert.IsTrue(Lines[0].Contains(':') and Lines[0].Contains('.'),
    'Log line must contain a timestamp with colons and dot');
end;

procedure TTestDebugLog.TestInvalidPathDoesNotRaise;
begin
  { Point to a path that cannot be written (non-existent deep directory) }
  GDebugLogPath := 'Z:\no\such\deep\path\log.txt';
  DebugLog('Fail', 'should not raise');
  { If we reach here, the swallowed exception worked }
  Assert.Pass('DebugLog must never raise');
end;

procedure TTestDebugLog.TestMultipleCallsAppend;
begin
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

initialization
  TDUnitX.RegisterTestFixture(TTestDebugLog);

end.
