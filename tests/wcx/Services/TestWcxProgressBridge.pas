unit TestWcxProgressBridge;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxProgressBridge = class
  public
    [Setup] procedure Setup;

    { Dispatch routing }
    [Test] procedure TestPrefersWideCallbackWhenBothSet;
    [Test] procedure TestFallsBackToAnsiWhenWideUnset;
    [Test] procedure TestNoCallbacksReturnsTrueAndDoesNotCancel;

    { Percent payload encoding (positive-delta against an assumed UnpSize) }
    [Test] procedure TestFirstReportSendsPercentAsDelta;
    [Test] procedure TestSubsequentReportSendsDeltaFromPrevious;
    [Test] procedure TestDeltaSumAcrossRunReachesOneHundred;
    [Test] procedure TestBackwardPercentClampsDeltaToZero;
    [Test] procedure TestReportPercentClampsBelowZero;
    [Test] procedure TestReportPercentClampsAboveOneHundred;

    { Throttling }
    [Test] procedure TestRepeatedSamePercentInvokesOnce;
    [Test] procedure TestFirstZeroPercentDoesFire;
    [Test] procedure TestPercentChangesEmitDistinctCalls;

    { Cancellation }
    [Test] procedure TestCancelFlagSetWhenCallbackReturnsZero;
    [Test] procedure TestCancelHandleSignalsForRunProcessWatcher;
    [Test] procedure TestPostCancelReportsShortCircuit;
    [Test] procedure TestPostCancelDoesNotCallCallbackAgain;

    { Filename plumbing }
    [Test] procedure TestFileNamePassedToWideCallback;
    [Test] procedure TestFileNamePassedToAnsiCallback;

    { Ping }
    [Test] procedure TestPingInvokesCallbackWithZero;
    [Test] procedure TestPingHonoursCancel;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows,
  WcxAPI, WcxProgressBridge;

{ Module-level capture state for fake callbacks. The stdcall calling
  convention rules out anonymous methods, so the tests record into globals
  and Setup resets them. Two parallel slots keep ANSI and Wide independent
  so the dispatch tests can detect a misroute. }

type
  TCallSlot = record
    InvokeCount: Integer;
    LastSize: Integer;
    LastFileNameW: string;
    LastFileNameA: AnsiString;
    NextReturn: Integer;
  end;

var
  GSlotA: TCallSlot;
  GSlotW: TCallSlot;
  {Separate accumulator for the delta-sum test; isolating it keeps the
   regular fakes' counters readable.}
  GSumW: Integer;

procedure ResetSlot(var ASlot: TCallSlot);
begin
  ASlot.InvokeCount := 0;
  ASlot.LastSize := 0;
  ASlot.LastFileNameW := '';
  ASlot.LastFileNameA := '';
  ASlot.NextReturn := 1;
end;

function FakeCallbackA(FileName: PAnsiChar; Size: Integer): Integer; stdcall;
begin
  Inc(GSlotA.InvokeCount);
  GSlotA.LastSize := Size;
  if FileName <> nil then
    GSlotA.LastFileNameA := AnsiString(FileName)
  else
    GSlotA.LastFileNameA := '';
  Result := GSlotA.NextReturn;
end;

function FakeCallbackW(FileName: PWideChar; Size: Integer): Integer; stdcall;
begin
  Inc(GSlotW.InvokeCount);
  GSlotW.LastSize := Size;
  if FileName <> nil then
    GSlotW.LastFileNameW := FileName
  else
    GSlotW.LastFileNameW := '';
  Result := GSlotW.NextReturn;
end;

function SumCallbackW(FileName: PWideChar; Size: Integer): Integer; stdcall;
begin
  Inc(GSumW, Size);
  Result := 1;
end;

{ TTestWcxProgressBridge }

procedure TTestWcxProgressBridge.Setup;
begin
  ResetSlot(GSlotA);
  ResetSlot(GSlotW);
end;

{ Dispatch routing }

procedure TTestWcxProgressBridge.TestPrefersWideCallbackWhenBothSet;
var
  B: TWcxProgressBridge;
begin
  { Modern TC always wires SetProcessDataProcW; routing through ANSI when
    both are set would lose information on non-CP_ACP filenames. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, FakeCallbackA, FakeCallbackW);
  try
    B.ReportPercent(50);
    Assert.AreEqual(1, GSlotW.InvokeCount, 'Wide callback should be invoked');
    Assert.AreEqual(0, GSlotA.InvokeCount, 'ANSI callback must not fire when Wide is set');
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestFallsBackToAnsiWhenWideUnset;
var
  B: TWcxProgressBridge;
begin
  B := TWcxProgressBridge.Create('Movie.mp3', 100, FakeCallbackA, nil);
  try
    B.ReportPercent(50);
    Assert.AreEqual(0, GSlotW.InvokeCount);
    Assert.AreEqual(1, GSlotA.InvokeCount);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestNoCallbacksReturnsTrueAndDoesNotCancel;
var
  B: TWcxProgressBridge;
begin
  { Some TC builds may extract without ever calling SetProcessDataProc*.
    The bridge must not crash and must not spuriously cancel. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, nil);
  try
    Assert.IsTrue(B.ReportPercent(25));
    Assert.IsFalse(B.Cancelled);
    Assert.IsTrue(B.Ping);
  finally
    B.Free;
  end;
end;

{ Percent payload encoding — positive-delta against UnpSize=100 }

procedure TTestWcxProgressBridge.TestFirstReportSendsPercentAsDelta;
var
  B: TWcxProgressBridge;
begin
  { The very first report has no previous value to subtract against, so
    the delta IS the absolute percent — TC's bar advances by exactly that
    amount on the first tick. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(42);
    Assert.AreEqual(42, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestSubsequentReportSendsDeltaFromPrevious;
var
  B: TWcxProgressBridge;
begin
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(20);
    B.ReportPercent(35);
    Assert.AreEqual(15, GSlotW.LastSize, 'Second report sends 35-20=15');
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestDeltaSumAcrossRunReachesOneHundred;
var
  B: TWcxProgressBridge;
  P: Integer;
begin
  { Property the listing layer relies on: delta sum equals 100 when a
    run completes. Without this the synthetic UnpSize=100 would never
    fill, leaving the bar stuck. }
  GSumW := 0;
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, SumCallbackW);
  try
    for P := 0 to 100 do
      B.ReportPercent(P);
    Assert.AreEqual(100, GSumW);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestBackwardPercentClampsDeltaToZero;
var
  B: TWcxProgressBridge;
begin
  { ffmpeg's clock can stutter backward briefly under odd seeks. The bar
    can only fill, never retreat, so a regression must clamp the delta
    to 0 (still triggers a callback so cancel detection works). }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(50);
    B.ReportPercent(40);
    Assert.AreEqual(0, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestReportPercentClampsBelowZero;
var
  B: TWcxProgressBridge;
begin
  { Negative input clamps to 0 before delta computation, so first call
    reports a delta of 0 (the bar stays put). }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(-7);
    Assert.AreEqual(0, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestReportPercentClampsAboveOneHundred;
var
  B: TWcxProgressBridge;
begin
  { Over-100 caps to 100 — the bar fills once and stays. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(150);
    Assert.AreEqual(100, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

{ Throttling }

procedure TTestWcxProgressBridge.TestRepeatedSamePercentInvokesOnce;
var
  B: TWcxProgressBridge;
begin
  { ffmpeg can emit several -progress ticks within the same percent bucket.
    Without throttling we would spam TC's progress UI for no UX gain. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(33);
    B.ReportPercent(33);
    B.ReportPercent(33);
    Assert.AreEqual(1, GSlotW.InvokeCount);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestFirstZeroPercentDoesFire;
var
  B: TWcxProgressBridge;
begin
  { The throttle uses a -1 sentinel for "no call yet", so the first
    legitimate 0% report must reach the callback even though the visible
    payload happens to look identical to a Ping. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(0);
    Assert.AreEqual(1, GSlotW.InvokeCount);
    Assert.AreEqual(0, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestPercentChangesEmitDistinctCalls;
var
  B: TWcxProgressBridge;
begin
  { Three distinct percent steps emit three callback calls; the last
    delta is 30-20=10 under the positive-delta encoding. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(10);
    B.ReportPercent(20);
    B.ReportPercent(30);
    Assert.AreEqual(3, GSlotW.InvokeCount);
    Assert.AreEqual(10, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

{ Cancellation }

procedure TTestWcxProgressBridge.TestCancelFlagSetWhenCallbackReturnsZero;
var
  B: TWcxProgressBridge;
begin
  GSlotW.NextReturn := 0;
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    Assert.IsFalse(B.ReportPercent(50));
    Assert.IsTrue(B.Cancelled);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestCancelHandleSignalsForRunProcessWatcher;
var
  B: TWcxProgressBridge;
begin
  { RunProcess waits on this handle; signalled state is what makes the
    watcher terminate the ffmpeg child. Use a 0-ms wait — signalled
    handles return WAIT_OBJECT_0 immediately. }
  GSlotW.NextReturn := 0;
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(50);
    Assert.AreEqual(WAIT_OBJECT_0, WaitForSingleObject(B.CancelHandle, 0),
      'Cancel handle must be signalled so RunProcess wakes its watcher');
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestPostCancelReportsShortCircuit;
var
  B: TWcxProgressBridge;
begin
  GSlotW.NextReturn := 0;
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(50);
    Assert.IsFalse(B.ReportPercent(60));
    Assert.IsFalse(B.Ping);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestPostCancelDoesNotCallCallbackAgain;
var
  B: TWcxProgressBridge;
begin
  { Once cancelled, every report should short-circuit before reaching the
    callback. Otherwise late ticks could spuriously flip-flop the cancel
    flag (the fake's NextReturn might be set to 1 by then). }
  GSlotW.NextReturn := 0;
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(50);
    GSlotW.NextReturn := 1;
    B.ReportPercent(60);
    B.Ping;
    Assert.AreEqual(1, GSlotW.InvokeCount);
  finally
    B.Free;
  end;
end;

{ Filename plumbing }

procedure TTestWcxProgressBridge.TestFileNamePassedToWideCallback;
var
  B: TWcxProgressBridge;
begin
  B := TWcxProgressBridge.Create('фильм.mp3', 100, nil, FakeCallbackW);
  try
    B.ReportPercent(10);
    Assert.AreEqual('фильм.mp3', GSlotW.LastFileNameW);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestFileNamePassedToAnsiCallback;
var
  B: TWcxProgressBridge;
begin
  { ANSI conversion is best-effort; ASCII filename round-trips losslessly. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, FakeCallbackA, nil);
  try
    B.ReportPercent(10);
    Assert.AreEqual(AnsiString('Movie.mp3'), GSlotA.LastFileNameA);
  finally
    B.Free;
  end;
end;

{ Ping }

procedure TTestWcxProgressBridge.TestPingInvokesCallbackWithZero;
var
  B: TWcxProgressBridge;
begin
  { Ping is the cancel-poll affordance for use before the first real
    progress tick is available. }
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    B.Ping;
    Assert.AreEqual(1, GSlotW.InvokeCount);
    Assert.AreEqual(0, GSlotW.LastSize);
  finally
    B.Free;
  end;
end;

procedure TTestWcxProgressBridge.TestPingHonoursCancel;
var
  B: TWcxProgressBridge;
begin
  GSlotW.NextReturn := 0;
  B := TWcxProgressBridge.Create('Movie.mp3', 100, nil, FakeCallbackW);
  try
    Assert.IsFalse(B.Ping);
    Assert.IsTrue(B.Cancelled);
  finally
    B.Free;
  end;
end;

end.
