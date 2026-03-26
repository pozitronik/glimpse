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
  end;

implementation

uses
  System.SysUtils, uFrameOffsets;

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
var
  Offsets: TFrameOffsetArray;
begin
  { SkipEdges=60 should be clamped to 49 }
  { EffStart=49, EffEnd=51, EffD=2 }
  { N=1: offset = 49 + 2*0.5 = 50.0 }
  Offsets := CalculateFrameOffsets(100.0, 1, 60);
  Assert.AreEqual(50.0, Offsets[0].TimeOffset, 0.001, 'Over-49 clamped to 49');
end;

procedure TTestFrameOffsets.TestNegativeEdgeGuardClamped;
var
  Offsets: TFrameOffsetArray;
begin
  { Negative skip should be clamped to 0 }
  Offsets := CalculateFrameOffsets(100.0, 1, -5);
  Assert.AreEqual(50.0, Offsets[0].TimeOffset, 0.001, 'Negative clamped to 0');
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

initialization
  TDUnitX.RegisterTestFixture(TTestFrameOffsets);

end.
