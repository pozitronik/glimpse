{Tests for FrameCountPolicy: verifies the [MIN_FRAMES_COUNT,
 MAX_FRAMES_COUNT] clamping rule across mid-range, both saturation
 directions and the exact boundaries, since both the settings UI and
 the lister menu rely on it.}
unit FrameCountPolicyTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFrameCountPolicyTests = class
  public
    [Test]
    [TestCase('MidRange', '9,9')]
    [TestCase('LowerBoundaryStays', '1,1')]
    [TestCase('UpperBoundaryStays', '99,99')]
    [TestCase('OverflowFromMax', '109,99')]
    [TestCase('OverflowNearMax', '105,99')]
    [TestCase('UnderflowFromMin', '-4,1')]
    [TestCase('UnderflowNearMin', '-2,1')]
    procedure Clamp_KeepsValueInRange(const AInput, AExpected: Integer);
  end;

implementation

uses
  FrameCountPolicy;

procedure TFrameCountPolicyTests.Clamp_KeepsValueInRange(const AInput, AExpected: Integer);
begin
  Assert.AreEqual(AExpected, TFrameCountPolicy.Clamp(AInput));
end;

initialization
  TDUnitX.RegisterTestFixture(TFrameCountPolicyTests);

end.
