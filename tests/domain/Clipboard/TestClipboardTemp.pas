{Tests for ClipboardTemp: the cleanup-strategy serializers, the
 seconds<->days/hours/minutes split the spin fields use, and the pure
 per-file sweep decision (boundaries, the min-age floor, and the ccsNone
 short-circuit).}
unit TestClipboardTemp;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardTemp = class
  public
    [Test] procedure Strategy_RoundTripsThroughTokens;
    [Test] procedure StrToStrategy_UnknownReturnsDefault;
    [Test] procedure StrToStrategy_IsCaseInsensitive;

    [Test] procedure SplitSecondsToDHM_24hIsOneDay;
    [Test] procedure SplitSecondsToDHM_DecomposesCompound;
    [Test] procedure SplitSecondsToDHM_NegativeClampsToZero;
    [Test] procedure SplitSecondsToDHM_DropsSubMinuteRemainder;

    [Test] procedure DHMToSeconds_RoundTripsWithSplit;
    [Test] procedure DHMToSeconds_NegativesClampToZero;

    [Test] procedure Sweep_None_NeverDeletes;
    [Test] procedure Sweep_All_DeletesAboveFloor;
    [Test] procedure Sweep_All_RespectsFloor;
    [Test] procedure Sweep_OlderThan_StrictlyGreaterBoundary;
    [Test] procedure Sweep_OlderThan_FloorWinsOverThreshold;
  end;

implementation

uses
  ClipboardTemp;

procedure TTestClipboardTemp.Strategy_RoundTripsThroughTokens;
var
  S: TClipboardCleanupStrategy;
begin
  for S := Low(TClipboardCleanupStrategy) to High(TClipboardCleanupStrategy) do
    Assert.AreEqual(Ord(S),
      Ord(StrToClipboardCleanupStrategy(ClipboardCleanupStrategyToStr(S), ccsNone)),
      'strategy must survive a token round-trip');
end;

procedure TTestClipboardTemp.StrToStrategy_UnknownReturnsDefault;
begin
  Assert.AreEqual(Ord(ccsOlderThan),
    Ord(StrToClipboardCleanupStrategy('garbage', ccsOlderThan)));
end;

procedure TTestClipboardTemp.StrToStrategy_IsCaseInsensitive;
begin
  Assert.AreEqual(Ord(ccsAll), Ord(StrToClipboardCleanupStrategy('ALL', ccsNone)));
  Assert.AreEqual(Ord(ccsOlderThan), Ord(StrToClipboardCleanupStrategy('OlderThan', ccsNone)));
end;

procedure TTestClipboardTemp.SplitSecondsToDHM_24hIsOneDay;
var
  D, H, M: Integer;
begin
  SplitSecondsToDHM(SECONDS_PER_DAY, D, H, M);
  Assert.AreEqual(1, D);
  Assert.AreEqual(0, H);
  Assert.AreEqual(0, M);
end;

procedure TTestClipboardTemp.SplitSecondsToDHM_DecomposesCompound;
var
  D, H, M: Integer;
begin
  SplitSecondsToDHM(2 * SECONDS_PER_DAY + 3 * SECONDS_PER_HOUR + 9 * SECONDS_PER_MINUTE, D, H, M);
  Assert.AreEqual(2, D);
  Assert.AreEqual(3, H);
  Assert.AreEqual(9, M);
end;

procedure TTestClipboardTemp.SplitSecondsToDHM_NegativeClampsToZero;
var
  D, H, M: Integer;
begin
  SplitSecondsToDHM(-500, D, H, M);
  Assert.AreEqual(0, D);
  Assert.AreEqual(0, H);
  Assert.AreEqual(0, M);
end;

procedure TTestClipboardTemp.SplitSecondsToDHM_DropsSubMinuteRemainder;
var
  D, H, M: Integer;
begin
  {90 seconds = 1 minute + 30s remainder; the sub-minute part is dropped.}
  SplitSecondsToDHM(90, D, H, M);
  Assert.AreEqual(0, D);
  Assert.AreEqual(0, H);
  Assert.AreEqual(1, M);
end;

procedure TTestClipboardTemp.DHMToSeconds_RoundTripsWithSplit;
var
  Secs, D, H, M: Integer;
begin
  Secs := 5 * SECONDS_PER_DAY + 11 * SECONDS_PER_HOUR + 42 * SECONDS_PER_MINUTE;
  SplitSecondsToDHM(Secs, D, H, M);
  Assert.AreEqual(Secs, DHMToSeconds(D, H, M));
end;

procedure TTestClipboardTemp.DHMToSeconds_NegativesClampToZero;
begin
  {Each negative component clamps independently, so only the valid parts
   contribute. (-1, 2, -3) -> 2 hours.}
  Assert.AreEqual(2 * SECONDS_PER_HOUR, DHMToSeconds(-1, 2, -3));
end;

procedure TTestClipboardTemp.Sweep_None_NeverDeletes;
begin
  {ccsNone short-circuits regardless of age or floor.}
  Assert.IsFalse(ShouldSweepClipboardTemp(ccsNone, 999999, 0, 0));
end;

procedure TTestClipboardTemp.Sweep_All_DeletesAboveFloor;
begin
  Assert.IsTrue(ShouldSweepClipboardTemp(ccsAll, 200, 0, 120));
end;

procedure TTestClipboardTemp.Sweep_All_RespectsFloor;
begin
  {A file younger than the floor is spared even by "clean everything", so a
   concurrent instance's just-written file is never destroyed mid-flight.}
  Assert.IsFalse(ShouldSweepClipboardTemp(ccsAll, 60, 0, 120));
end;

procedure TTestClipboardTemp.Sweep_OlderThan_StrictlyGreaterBoundary;
begin
  {Threshold is exclusive: a file exactly at the threshold is NOT swept;
   one second older is.}
  Assert.IsFalse(ShouldSweepClipboardTemp(ccsOlderThan, 3600, 3600, 0), 'at threshold');
  Assert.IsTrue(ShouldSweepClipboardTemp(ccsOlderThan, 3601, 3600, 0), 'past threshold');
end;

procedure TTestClipboardTemp.Sweep_OlderThan_FloorWinsOverThreshold;
begin
  {Even with a zero threshold (every aged file qualifies), the floor still
   protects a very fresh file.}
  Assert.IsFalse(ShouldSweepClipboardTemp(ccsOlderThan, 30, 0, 120));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardTemp);

end.
