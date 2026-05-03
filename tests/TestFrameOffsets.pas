unit TestFrameOffsets;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFrameOffsets = class
  public
    [Test]
    procedure TestSingleFrameMidpoint;
    [Test]
    procedure TestTwoFramesQuartiles;
    [Test]
    procedure TestFourFramesEighths;
    [Test]
    procedure TestEdgeGuard2Percent;
    [Test]
    procedure TestEdgeGuard10Percent;
    [Test]
    procedure TestEdgeGuardZeroDisabled;
    [Test]
    procedure TestEdgeGuardMaxClamped;
    [Test]
    procedure TestNegativeEdgeGuardClamped;
    [Test]
    procedure TestVeryShortVideo;
    [Test]
    procedure TestLargeFrameCount;
    [Test]
    procedure TestIndicesAreOneBased;
    [Test]
    procedure TestNegativeDurationRaises;
    [Test]
    procedure TestZeroDurationRaises;
    [Test]
    procedure TestZeroFrameCountRaises;
    [Test]
    procedure TestFormatTimecodeZero;
    [Test]
    procedure TestFormatTimecodeSeconds;
    [Test]
    procedure TestFormatTimecodeMinutes;
    [Test]
    procedure TestFormatTimecodeHours;
    [Test]
    procedure TestFormatTimecodeForFilename;
    [Test]
    procedure TestFormatTimecodeNegative;
    { Additional edge cases }
    [Test]
    procedure TestNegativeFrameCountRaises;
    [Test]
    procedure TestOffsetsEvenlySpaced;
    [Test]
    procedure TestMaxEdgeGuardMinimalRange;
    [Test]
    procedure TestNaNDurationRaises;
    [Test]
    procedure TestInfinityDurationRaises;
    [Test]
    procedure TestNegativeInfinityDurationRaises;
    [Test]
    procedure TestFormatTimecodeLargeHours;
    [Test]
    procedure TestFormatTimecodeSubMillisecondRounding;
    [Test]
    procedure TestSingleFrameWithEdgeGuard;
    [Test]
    procedure TestEdgeGuard50Raises;
    { FormatDurationHMS tests }
    [Test]
    procedure TestDurationHMS_Zero;
    [Test]
    procedure TestDurationHMS_Negative;
    [Test]
    procedure TestDurationHMS_SecondsOnly;
    [Test]
    procedure TestDurationHMS_MinutesAndSeconds;
    [Test]
    procedure TestDurationHMS_Hours;
    [Test]
    procedure TestDurationHMS_Rounding;
    { CalculateRandomFrameOffsets tests }
    [Test]
    procedure TestRandomOffsetsCountMatches;
    [Test]
    procedure TestRandomOffsetsIndicesOneBased;
    [Test]
    procedure TestRandomOffsetsAtP1IsNearMidpoint;
    [Test]
    procedure TestRandomOffsetsAtP100StaysInsideSlice;
    [Test]
    procedure TestRandomOffsetsAreMonotonic;
    [Test]
    procedure TestRandomOffsetsRespectSkipEdges;
    [Test]
    procedure TestRandomOffsetsClampsHighRandomness;
    [Test]
    procedure TestRandomOffsetsClampsLowRandomness;
    [Test]
    procedure TestRandomOffsetsZeroDurationRaises;
    [Test]
    procedure TestRandomOffsetsZeroFrameCountRaises;
    [Test]
    procedure TestRandomOffsetsReproducibleWithSeed;
  end;

implementation

uses
  System.SysUtils, System.Math, uFrameOffsets;

{ Offset tests }

procedure TTestFrameOffsets.TestSingleFrameMidpoint;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalculateFrameOffsets(100.0, 1, 0);
  Assert.AreEqual(1, Integer(Length(Offsets)));
  Assert.AreEqual(50.0, Offsets[0].TimeOffset, 0.001, 'N=1 should return midpoint');
end;

procedure TTestFrameOffsets.TestTwoFramesQuartiles;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalculateFrameOffsets(100.0, 2, 0);
  Assert.AreEqual(2, Integer(Length(Offsets)));
  Assert.AreEqual(25.0, Offsets[0].TimeOffset, 0.001, 'First of 2 at 25%');
  Assert.AreEqual(75.0, Offsets[1].TimeOffset, 0.001, 'Second of 2 at 75%');
end;

procedure TTestFrameOffsets.TestFourFramesEighths;
var
  Offsets: TFrameOffsetArray;
begin
  { Design example: N=4 gives 0.125D, 0.375D, 0.625D, 0.875D }
  Offsets := CalculateFrameOffsets(100.0, 4, 0);
  Assert.AreEqual(4, Integer(Length(Offsets)));
  Assert.AreEqual(12.5, Offsets[0].TimeOffset, 0.001);
  Assert.AreEqual(37.5, Offsets[1].TimeOffset, 0.001);
  Assert.AreEqual(62.5, Offsets[2].TimeOffset, 0.001);
  Assert.AreEqual(87.5, Offsets[3].TimeOffset, 0.001);
end;

procedure TTestFrameOffsets.TestEdgeGuard2Percent;
var
  Offsets: TFrameOffsetArray;
begin
  { N=2, D=100, skip 2%: EffStart=2, EffEnd=98, EffD=96 }
  { Offset[0] = 2 + 96*1/4 = 26.0 }
  { Offset[1] = 2 + 96*3/4 = 74.0 }
  Offsets := CalculateFrameOffsets(100.0, 2, 2);
  Assert.AreEqual(2, Integer(Length(Offsets)));
  Assert.AreEqual(26.0, Offsets[0].TimeOffset, 0.001);
  Assert.AreEqual(74.0, Offsets[1].TimeOffset, 0.001);
end;

procedure TTestFrameOffsets.TestEdgeGuard10Percent;
var
  Offsets: TFrameOffsetArray;
begin
  { N=4, D=100, skip 10%: EffStart=10, EffEnd=90, EffD=80 }
  Offsets := CalculateFrameOffsets(100.0, 4, 10);
  Assert.AreEqual(4, Integer(Length(Offsets)));
  Assert.AreEqual(20.0, Offsets[0].TimeOffset, 0.001);
  Assert.AreEqual(40.0, Offsets[1].TimeOffset, 0.001);
  Assert.AreEqual(60.0, Offsets[2].TimeOffset, 0.001);
  Assert.AreEqual(80.0, Offsets[3].TimeOffset, 0.001);
end;

procedure TTestFrameOffsets.TestEdgeGuardZeroDisabled;
var
  Offsets: TFrameOffsetArray;
begin
  { SkipEdges=0 should use full duration (same as no edge guard) }
  Offsets := CalculateFrameOffsets(100.0, 1, 0);
  Assert.AreEqual(50.0, Offsets[0].TimeOffset, 0.001);
end;

procedure TTestFrameOffsets.TestEdgeGuardMaxClamped;
begin
  { SkipEdges above 49 must raise }
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(100.0, 1, 60) end,
    EArgumentException);
end;

procedure TTestFrameOffsets.TestNegativeEdgeGuardClamped;
begin
  { Negative skip must raise }
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(100.0, 1, -5) end,
    EArgumentException);
end;

procedure TTestFrameOffsets.TestVeryShortVideo;
var
  Offsets: TFrameOffsetArray;
begin
  { 0.1 second video, N=4, SkipEdges=2 }
  { EffStart=0.002, EffEnd=0.098, EffD=0.096 }
  Offsets := CalculateFrameOffsets(0.1, 4, 2);
  Assert.AreEqual(4, Integer(Length(Offsets)));
  { All offsets must be within [0, 0.1] }
  Assert.IsTrue(Offsets[0].TimeOffset >= 0);
  Assert.IsTrue(Offsets[3].TimeOffset <= 0.1);
  { Offsets must be strictly ascending }
  Assert.IsTrue(Offsets[0].TimeOffset < Offsets[1].TimeOffset);
  Assert.IsTrue(Offsets[1].TimeOffset < Offsets[2].TimeOffset);
  Assert.IsTrue(Offsets[2].TimeOffset < Offsets[3].TimeOffset);
end;

procedure TTestFrameOffsets.TestLargeFrameCount;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
begin
  { 99 frames (max allowed by UI), verify ascending order and bounds }
  Offsets := CalculateFrameOffsets(3600.0, 99, 2);
  Assert.AreEqual(99, Integer(Length(Offsets)));
  for I := 0 to 97 do
    Assert.IsTrue(Offsets[I].TimeOffset < Offsets[I + 1].TimeOffset,
      Format('Frame %d must precede frame %d', [I + 1, I + 2]));
  { All within effective range: [2%*3600, 98%*3600] = [72, 3528] }
  Assert.IsTrue(Offsets[0].TimeOffset >= 72.0);
  Assert.IsTrue(Offsets[98].TimeOffset <= 3528.0);
end;

procedure TTestFrameOffsets.TestIndicesAreOneBased;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
begin
  Offsets := CalculateFrameOffsets(100.0, 5, 0);
  for I := 0 to 4 do
    Assert.AreEqual(I + 1, Offsets[I].Index, Format('Index at position %d should be %d', [I, I + 1]));
end;

procedure TTestFrameOffsets.TestNegativeDurationRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(-10.0, 4, 0); end,
    EArgumentException
  );
end;

procedure TTestFrameOffsets.TestZeroDurationRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(0.0, 4, 0); end,
    EArgumentException
  );
end;

procedure TTestFrameOffsets.TestZeroFrameCountRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(100.0, 0, 0); end,
    EArgumentException
  );
end;

{ Timecode formatting tests }

procedure TTestFrameOffsets.TestFormatTimecodeZero;
begin
  Assert.AreEqual('00:00:00.000', FormatTimecode(0.0));
end;

procedure TTestFrameOffsets.TestFormatTimecodeSeconds;
begin
  Assert.AreEqual('00:00:01.500', FormatTimecode(1.5));
  Assert.AreEqual('00:00:30.000', FormatTimecode(30.0));
  Assert.AreEqual('00:00:59.999', FormatTimecode(59.999));
end;

procedure TTestFrameOffsets.TestFormatTimecodeMinutes;
begin
  Assert.AreEqual('00:01:01.123', FormatTimecode(61.123));
  Assert.AreEqual('00:10:00.000', FormatTimecode(600.0));
end;

procedure TTestFrameOffsets.TestFormatTimecodeHours;
begin
  Assert.AreEqual('01:00:00.000', FormatTimecode(3600.0));
  Assert.AreEqual('01:01:01.999', FormatTimecode(3661.999));
  Assert.AreEqual('02:30:00.000', FormatTimecode(9000.0));
end;

procedure TTestFrameOffsets.TestFormatTimecodeForFilename;
begin
  { Colons replaced with dashes }
  Assert.AreEqual('01-01-01.123', FormatTimecodeForFilename(3661.123));
  Assert.AreEqual('00-00-00.000', FormatTimecodeForFilename(0.0));
end;

procedure TTestFrameOffsets.TestFormatTimecodeNegative;
begin
  { Negative time should be treated as zero }
  Assert.AreEqual('00:00:00.000', FormatTimecode(-5.0));
end;

{ Additional edge cases }

procedure TTestFrameOffsets.TestNegativeFrameCountRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(100.0, -5, 0); end,
    EArgumentException,
    'Negative frame count should raise'
  );
end;

procedure TTestFrameOffsets.TestOffsetsEvenlySpaced;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
  ExpectedSpacing, ActualSpacing: Double;
begin
  { With no edge guard, spacing between consecutive frames should be D/N }
  Offsets := CalculateFrameOffsets(120.0, 6, 0);
  ExpectedSpacing := 120.0 / 6; { = 20.0 }
  for I := 0 to 4 do
  begin
    ActualSpacing := Offsets[I + 1].TimeOffset - Offsets[I].TimeOffset;
    Assert.AreEqual(ExpectedSpacing, ActualSpacing, 0.001,
      Format('Spacing between frames %d and %d should be %.1f', [I + 1, I + 2, ExpectedSpacing]));
  end;
end;

procedure TTestFrameOffsets.TestMaxEdgeGuardMinimalRange;
var
  Offsets: TFrameOffsetArray;
begin
  { 49% edge guard: effective range is 49%..51% = 2% of duration }
  { With D=1000, EffStart=490, EffEnd=510, EffDuration=20 }
  Offsets := CalculateFrameOffsets(1000.0, 3, 49);
  Assert.AreEqual(3, Integer(Length(Offsets)));
  { All offsets should fall within [490, 510] }
  Assert.IsTrue(Offsets[0].TimeOffset >= 490.0,
    Format('First offset %.3f should be >= 490', [Offsets[0].TimeOffset]));
  Assert.IsTrue(Offsets[2].TimeOffset <= 510.0,
    Format('Last offset %.3f should be <= 510', [Offsets[2].TimeOffset]));
  { Offsets should still be ascending }
  Assert.IsTrue(Offsets[0].TimeOffset < Offsets[1].TimeOffset, 'Must be ascending');
  Assert.IsTrue(Offsets[1].TimeOffset < Offsets[2].TimeOffset, 'Must be ascending');
end;

procedure TTestFrameOffsets.TestNaNDurationRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(NaN, 4, 0); end,
    EArgumentException, 'NaN duration must raise');
end;

procedure TTestFrameOffsets.TestInfinityDurationRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(Infinity, 4, 0); end,
    EArgumentException, 'Infinity duration must raise');
end;

procedure TTestFrameOffsets.TestNegativeInfinityDurationRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(NegInfinity, 4, 0); end,
    EArgumentException, 'NegInfinity duration must raise');
end;

procedure TTestFrameOffsets.TestFormatTimecodeLargeHours;
begin
  { 24-hour video: 86400 seconds }
  Assert.AreEqual('24:00:00.000', FormatTimecode(86400.0));
  { 100-hour video: 360000 seconds }
  Assert.AreEqual('100:00:00.000', FormatTimecode(360000.0));
  { 27h46m40s = 100000 seconds }
  Assert.AreEqual('27:46:40.000', FormatTimecode(100000.0));
end;

procedure TTestFrameOffsets.TestFormatTimecodeSubMillisecondRounding;
begin
  { 1.9999s rounds to 2000ms }
  Assert.AreEqual('00:00:02.000', FormatTimecode(1.9999));
  { 0.0004s rounds to 0ms }
  Assert.AreEqual('00:00:00.000', FormatTimecode(0.0004));
  { 59.9995s rounds to 60000ms = 1:00 }
  Assert.AreEqual('00:01:00.000', FormatTimecode(59.9995));
end;

procedure TTestFrameOffsets.TestSingleFrameWithEdgeGuard;
var
  Offsets: TFrameOffsetArray;
begin
  { N=1, 10% edge guard on 100s video: midpoint of [10..90] = 50 }
  Offsets := CalculateFrameOffsets(100.0, 1, 10);
  Assert.AreEqual(1, Integer(Length(Offsets)));
  Assert.AreEqual(50.0, Offsets[0].TimeOffset, 0.001,
    'Single frame with edge guard should be at midpoint of effective range');
end;

procedure TTestFrameOffsets.TestEdgeGuard50Raises;
begin
  { SkipEdgesPercent must be 0..49; 50 leaves zero effective duration }
  Assert.WillRaise(
    procedure begin CalculateFrameOffsets(100.0, 4, 50); end,
    EArgumentException, 'SkipEdgesPercent=50 must raise');
end;

{ FormatDurationHMS tests }

procedure TTestFrameOffsets.TestDurationHMS_Zero;
begin
  Assert.AreEqual('?', FormatDurationHMS(0));
end;

procedure TTestFrameOffsets.TestDurationHMS_Negative;
begin
  Assert.AreEqual('?', FormatDurationHMS(-10));
end;

procedure TTestFrameOffsets.TestDurationHMS_SecondsOnly;
begin
  Assert.AreEqual('0:05', FormatDurationHMS(5));
  Assert.AreEqual('0:59', FormatDurationHMS(59));
end;

procedure TTestFrameOffsets.TestDurationHMS_MinutesAndSeconds;
begin
  Assert.AreEqual('1:00', FormatDurationHMS(60));
  Assert.AreEqual('1:01', FormatDurationHMS(61));
  Assert.AreEqual('59:59', FormatDurationHMS(3599));
end;

procedure TTestFrameOffsets.TestDurationHMS_Hours;
begin
  Assert.AreEqual('1:00:00', FormatDurationHMS(3600));
  Assert.AreEqual('1:01:01', FormatDurationHMS(3661));
  Assert.AreEqual('25:00:00', FormatDurationHMS(90000));
end;

procedure TTestFrameOffsets.TestDurationHMS_Rounding;
begin
  { 90.6 rounds to 91 = 1:31 }
  Assert.AreEqual('1:31', FormatDurationHMS(90.6));
  { 59.5 rounds to 60 = 1:00 }
  Assert.AreEqual('1:00', FormatDurationHMS(59.5));
end;

{ CalculateRandomFrameOffsets tests }

procedure TTestFrameOffsets.TestRandomOffsetsCountMatches;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalculateRandomFrameOffsets(100.0, 9, 0, 50);
  Assert.AreEqual(9, Integer(Length(Offsets)));
end;

procedure TTestFrameOffsets.TestRandomOffsetsIndicesOneBased;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
begin
  Offsets := CalculateRandomFrameOffsets(100.0, 5, 0, 50);
  for I := 0 to High(Offsets) do
    Assert.AreEqual(I + 1, Offsets[I].Index);
end;

procedure TTestFrameOffsets.TestRandomOffsetsAtP1IsNearMidpoint;
var
  Offsets: TFrameOffsetArray;
  Slice, Midpoint, Window, T: Double;
  I: Integer;
begin
  {At P=1, jitter window is 1% of slice length around the midpoint.
   Even with worst-case Random outputs, every offset must stay within
   one window-half of its midpoint.}
  Offsets := CalculateRandomFrameOffsets(100.0, 4, 0, 1);
  Slice := 100.0 / 4.0;
  Window := Slice / 2.0 * 0.01;
  for I := 0 to High(Offsets) do
  begin
    Midpoint := (I + 0.5) * Slice;
    T := Offsets[I].TimeOffset;
    Assert.IsTrue(Abs(T - Midpoint) <= Window + 1e-9,
      Format('Frame %d offset %.6f outside +/- %.6f of midpoint %.6f', [I, T, Window, Midpoint]));
  end;
end;

procedure TTestFrameOffsets.TestRandomOffsetsAtP100StaysInsideSlice;
var
  Offsets: TFrameOffsetArray;
  Slice, SliceStart, SliceEnd, T: Double;
  I, K: Integer;
begin
  {At P=100, the jitter window equals the full slice. Repeat the call
   many times to exercise the Random distribution; every chosen offset
   must still land inside its own slice (so frame ordering is preserved
   no matter what Random returns).}
  for K := 1 to 50 do
  begin
    Offsets := CalculateRandomFrameOffsets(100.0, 9, 0, 100);
    Slice := 100.0 / 9.0;
    for I := 0 to High(Offsets) do
    begin
      SliceStart := I * Slice;
      SliceEnd := (I + 1) * Slice;
      T := Offsets[I].TimeOffset;
      Assert.IsTrue((T >= SliceStart - 1e-9) and (T <= SliceEnd + 1e-9),
        Format('Frame %d offset %.6f escaped slice [%.6f, %.6f] on iter %d', [I, T, SliceStart, SliceEnd, K]));
    end;
  end;
end;

procedure TTestFrameOffsets.TestRandomOffsetsAreMonotonic;
var
  Offsets: TFrameOffsetArray;
  I, K: Integer;
begin
  {Frame ordering invariant: t_1 < t_2 < ... < t_N. With per-slice
   jitter capped at slice/2 (P=100 means window=slice/2 each side, so
   the bound is exactly slice/2 from midpoint = slice edge), adjacent
   offsets cannot cross. Repeat many times to flush flakiness.}
  for K := 1 to 50 do
  begin
    Offsets := CalculateRandomFrameOffsets(100.0, 12, 0, 100);
    for I := 1 to High(Offsets) do
      Assert.IsTrue(Offsets[I].TimeOffset >= Offsets[I - 1].TimeOffset - 1e-9,
        Format('Non-monotonic at i=%d on iter %d: %.6f < %.6f', [I, K, Offsets[I].TimeOffset, Offsets[I - 1].TimeOffset]));
  end;
end;

procedure TTestFrameOffsets.TestRandomOffsetsRespectSkipEdges;
var
  Offsets: TFrameOffsetArray;
  EffStart, EffEnd: Double;
  I, K: Integer;
begin
  {With 10% skip, all offsets must be inside [10, 90] regardless of
   randomness. Tests the boundary behaviour: even at P=100 the
   slice layout starts inside the skipped zone.}
  for K := 1 to 50 do
  begin
    Offsets := CalculateRandomFrameOffsets(100.0, 6, 10, 100);
    EffStart := 10.0;
    EffEnd := 90.0;
    for I := 0 to High(Offsets) do
    begin
      Assert.IsTrue(Offsets[I].TimeOffset >= EffStart - 1e-9,
        Format('Offset %.6f below EffStart %.6f', [Offsets[I].TimeOffset, EffStart]));
      Assert.IsTrue(Offsets[I].TimeOffset <= EffEnd + 1e-9,
        Format('Offset %.6f above EffEnd %.6f', [Offsets[I].TimeOffset, EffEnd]));
    end;
  end;
end;

procedure TTestFrameOffsets.TestRandomOffsetsClampsHighRandomness;
var
  OffsetsAt100, OffsetsAt9999: TFrameOffsetArray;
  I: Integer;
begin
  {RandomnessPercent above 100 must clamp to 100 silently. Easiest
   check: with the same RandSeed, P=100 and P=9999 produce identical
   sequences (same effective jitter window).}
  RandSeed := 123;
  OffsetsAt100 := CalculateRandomFrameOffsets(100.0, 5, 0, 100);
  RandSeed := 123;
  OffsetsAt9999 := CalculateRandomFrameOffsets(100.0, 5, 0, 9999);
  for I := 0 to High(OffsetsAt100) do
    Assert.AreEqual(OffsetsAt100[I].TimeOffset, OffsetsAt9999[I].TimeOffset, 1e-9,
      Format('Offset %d differed between P=100 and P=9999', [I]));
end;

procedure TTestFrameOffsets.TestRandomOffsetsClampsLowRandomness;
var
  OffsetsAt1, OffsetsAt0, OffsetsAtNeg: TFrameOffsetArray;
  I: Integer;
begin
  {RandomnessPercent below 1 must clamp to 1: the slider's UI floor.}
  RandSeed := 456;
  OffsetsAt1 := CalculateRandomFrameOffsets(100.0, 5, 0, 1);
  RandSeed := 456;
  OffsetsAt0 := CalculateRandomFrameOffsets(100.0, 5, 0, 0);
  RandSeed := 456;
  OffsetsAtNeg := CalculateRandomFrameOffsets(100.0, 5, 0, -100);
  for I := 0 to High(OffsetsAt1) do
  begin
    Assert.AreEqual(OffsetsAt1[I].TimeOffset, OffsetsAt0[I].TimeOffset, 1e-9,
      'P=0 must clamp to 1');
    Assert.AreEqual(OffsetsAt1[I].TimeOffset, OffsetsAtNeg[I].TimeOffset, 1e-9,
      'Negative P must clamp to 1');
  end;
end;

procedure TTestFrameOffsets.TestRandomOffsetsZeroDurationRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateRandomFrameOffsets(0.0, 4, 0, 50); end,
    EArgumentException
  );
end;

procedure TTestFrameOffsets.TestRandomOffsetsZeroFrameCountRaises;
begin
  Assert.WillRaise(
    procedure begin CalculateRandomFrameOffsets(100.0, 0, 0, 50); end,
    EArgumentException
  );
end;

procedure TTestFrameOffsets.TestRandomOffsetsReproducibleWithSeed;
var
  A, B: TFrameOffsetArray;
  I: Integer;
begin
  {Same RandSeed -> identical sequences. Confirms the function reads
   from the global RNG and is therefore reproducible in tests by
   pinning RandSeed before the call.}
  RandSeed := 42;
  A := CalculateRandomFrameOffsets(100.0, 9, 5, 50);
  RandSeed := 42;
  B := CalculateRandomFrameOffsets(100.0, 9, 5, 50);
  Assert.AreEqual(Integer(Length(A)), Integer(Length(B)));
  for I := 0 to High(A) do
    Assert.AreEqual(A[I].TimeOffset, B[I].TimeOffset, 1e-12);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameOffsets);

end.
