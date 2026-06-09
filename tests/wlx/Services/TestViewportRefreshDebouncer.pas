{Tests for wlx/ViewportRefreshDebouncer. Synchronous tests cover the
 Schedule-path precondition short-circuit, the max-side memo round-trip
 and nil-callback safety. The TimerFire_* tests drive the real VCL
 TTimer with a short interval and pump the message queue until the
 handler runs, covering the debounce-fire logic itself: precondition
 re-check, same-size-bucket short-circuit and refresh invocation.}
unit TestViewportRefreshDebouncer;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  ViewportRefreshDebouncer;

type
  [TestFixture]
  TTestViewportRefreshDebouncer = class
  strict private
    FOwner: TComponent;
    FDebouncer: TViewportRefreshDebouncer;
    FShouldResult: Boolean;
    FShouldCalls: Integer;
    FComputeValue: Integer;
    FComputeCalls: Integer;
    FRefreshCalls: Integer;
    {Counting debouncer with a 20 ms interval; callbacks bump the
     fixture counters so the pump loop can observe TimerFired progress.}
    procedure BuildCountingDebouncer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Schedule_PreconditionFalse_DoesNotEnableTimer;
    [Test] procedure RecordExtractionMaxSide_RoundTripsThroughProperty;
    [Test] procedure NilCallbacks_SafeOnTimerFire;
    [Test] procedure TimerFire_SizeChanged_InvokesRefresh;
    [Test] procedure TimerFire_SameSizeBucket_SkipsRefresh;
    [Test] procedure TimerFire_PreconditionFlippedFalse_SkipsComputeAndRefresh;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms;

{Pumps the message queue until APredicate holds or ATimeoutMs elapses.
 Needed because WM_TIMER only dispatches through a message loop, which
 the console test runner does not spin on its own.}
function PumpUntil(const APredicate: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  Deadline: UInt64;
begin
  Deadline := GetTickCount64 + ATimeoutMs;
  while not APredicate() and (GetTickCount64 < Deadline) do
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;
  Result := APredicate();
end;

procedure TTestViewportRefreshDebouncer.Schedule_PreconditionFalse_DoesNotEnableTimer;
var
  Owner: TComponent;
  D: TViewportRefreshDebouncer;
  PreconditionCalled, ComputeCalled, RefreshCalled: Boolean;
begin
  PreconditionCalled := False;
  ComputeCalled := False;
  RefreshCalled := False;
  Owner := TComponent.Create(nil);
  D := nil;
  try
    D := TViewportRefreshDebouncer.Create(Owner, 200,
      function: Boolean
      begin
        PreconditionCalled := True;
        Result := False;
      end,
      function: Integer
      begin
        ComputeCalled := True;
        Result := 0;
      end,
      procedure
      begin
        RefreshCalled := True;
      end);
    D.Schedule;
    Assert.IsTrue(PreconditionCalled,
      'Schedule must consult the precondition callback');
    Assert.IsFalse(ComputeCalled,
      'False precondition short-circuits before the timer fires; computer not invoked');
    Assert.IsFalse(RefreshCalled,
      'False precondition short-circuits before the timer fires; refresh not invoked');
  finally
    D.Free;
    Owner.Free;
  end;
end;

procedure TTestViewportRefreshDebouncer.RecordExtractionMaxSide_RoundTripsThroughProperty;
var
  Owner: TComponent;
  D: TViewportRefreshDebouncer;
begin
  Owner := TComponent.Create(nil);
  D := nil;
  try
    D := TViewportRefreshDebouncer.Create(Owner, 200,
      nil, nil, nil);
    Assert.AreEqual(0, D.LastExtractionMaxSide,
      'Initial value is zero');
    D.RecordExtractionMaxSide(720);
    Assert.AreEqual(720, D.LastExtractionMaxSide,
      'Recorded value is readable via the property');
    D.RecordExtractionMaxSide(1080);
    Assert.AreEqual(1080, D.LastExtractionMaxSide,
      'Second record overwrites the first');
  finally
    D.Free;
    Owner.Free;
  end;
end;

procedure TTestViewportRefreshDebouncer.NilCallbacks_SafeOnTimerFire;
var
  Owner: TComponent;
  D: TViewportRefreshDebouncer;
begin
  {Pin the contract: even if all 3 callbacks are nil (degenerate
   construction), Schedule must not raise. The TimerFired short-
   circuits at the nil-precondition check; this test exercises only
   the Schedule path.}
  Owner := TComponent.Create(nil);
  D := nil;
  try
    D := TViewportRefreshDebouncer.Create(Owner, 200, nil, nil, nil);
    D.Schedule;
    Assert.Pass('Schedule with nil precondition is a no-op, not a crash');
  finally
    D.Free;
    Owner.Free;
  end;
end;

procedure TTestViewportRefreshDebouncer.Setup;
begin
  FOwner := TComponent.Create(nil);
  FDebouncer := nil;
  FShouldResult := True;
  FShouldCalls := 0;
  FComputeValue := 500;
  FComputeCalls := 0;
  FRefreshCalls := 0;
end;

procedure TTestViewportRefreshDebouncer.TearDown;
begin
  FreeAndNil(FDebouncer);
  FreeAndNil(FOwner);
end;

procedure TTestViewportRefreshDebouncer.BuildCountingDebouncer;
begin
  FDebouncer := TViewportRefreshDebouncer.Create(FOwner, 20,
    function: Boolean
    begin
      Inc(FShouldCalls);
      Result := FShouldResult;
    end,
    function: Integer
    begin
      Inc(FComputeCalls);
      Result := FComputeValue;
    end,
    procedure
    begin
      Inc(FRefreshCalls);
    end);
end;

procedure TTestViewportRefreshDebouncer.TimerFire_SizeChanged_InvokesRefresh;
begin
  BuildCountingDebouncer;
  FDebouncer.RecordExtractionMaxSide(100); {baseline differs from computed 500}
  FDebouncer.Schedule;
  Assert.IsTrue(
    PumpUntil(function: Boolean begin Result := FRefreshCalls >= 1 end, 2000),
    'changed size bucket must trigger the refresh callback');
  Assert.AreEqual(1, FRefreshCalls, 'one Schedule = one debounced refresh');
end;

procedure TTestViewportRefreshDebouncer.TimerFire_SameSizeBucket_SkipsRefresh;
begin
  BuildCountingDebouncer;
  FDebouncer.RecordExtractionMaxSide(500); {baseline equals computed 500}
  FDebouncer.Schedule;
  {ComputeCalls rising proves TimerFired ran past the precondition and
   reached the bucket compare — only then is asserting "no refresh"
   meaningful.}
  Assert.IsTrue(
    PumpUntil(function: Boolean begin Result := FComputeCalls >= 1 end, 2000),
    'timer must have fired and computed the new size');
  Assert.AreEqual(0, FRefreshCalls,
    'same size bucket: cached frames already match, refresh must be skipped');
end;

procedure TTestViewportRefreshDebouncer.TimerFire_PreconditionFlippedFalse_SkipsComputeAndRefresh;
begin
  BuildCountingDebouncer;
  FDebouncer.RecordExtractionMaxSide(100);
  FDebouncer.Schedule; {gate check consumes the first precondition call}
  FShouldResult := False;
  {The second precondition call can only come from TimerFired's re-check.}
  Assert.IsTrue(
    PumpUntil(function: Boolean begin Result := FShouldCalls >= 2 end, 2000),
    'timer must have fired and re-checked the precondition');
  Assert.AreEqual(0, FComputeCalls,
    'precondition flipped between trigger and fire: no compute');
  Assert.AreEqual(0, FRefreshCalls,
    'precondition flipped between trigger and fire: no refresh');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestViewportRefreshDebouncer);

end.
