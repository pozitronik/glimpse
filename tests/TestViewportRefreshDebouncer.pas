{Tests for wlx/uViewportRefreshDebouncer. The debouncer uses TTimer
 so timer firing is not covered here — only what is verifiable
 synchronously: precondition short-circuit on Schedule, max-side memo
 round-trip, and no-callback safety.}
unit TestViewportRefreshDebouncer;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestViewportRefreshDebouncer = class
  public
    [Test] procedure Schedule_PreconditionFalse_DoesNotEnableTimer;
    [Test] procedure RecordExtractionMaxSide_RoundTripsThroughProperty;
    [Test] procedure NilCallbacks_SafeOnTimerFire;
  end;

implementation

uses
  System.Classes,
  Vcl.Forms,
  uViewportRefreshDebouncer;

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

initialization
  TDUnitX.RegisterTestFixture(TTestViewportRefreshDebouncer);

end.
