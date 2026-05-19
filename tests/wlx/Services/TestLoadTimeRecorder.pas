{Tests for wlx/LoadTimeRecorder. Pins the contract bits that are
 independent of wall-clock timing: empty-before-Finalize, idempotent
 Finalize guard, and Start clears the previously formatted string.
 Avoids Sleep + tolerance bands since GetTickCount is the source.}
unit TestLoadTimeRecorder;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLoadTimeRecorder = class
  public
    [Test] procedure Formatted_BeforeFinalize_IsEmpty;
    [Test] procedure Finalize_AfterStart_PopulatesFormatted;
    [Test] procedure Finalize_BeforeStart_NoOp;
    [Test] procedure Finalize_Twice_IsIdempotent;
    [Test] procedure Start_ClearsPreviouslyFinalizedString;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  LoadTimeRecorder;

procedure TTestLoadTimeRecorder.Formatted_BeforeFinalize_IsEmpty;
var
  R: TLoadTimeRecorder;
begin
  R := TLoadTimeRecorder.Create;
  try
    Assert.AreEqual('', R.Formatted,
      'Formatted is empty until Finalize runs');
    R.Start;
    Assert.AreEqual('', R.Formatted,
      'Start alone does not produce a formatted string');
  finally
    R.Free;
  end;
end;

procedure TTestLoadTimeRecorder.Finalize_AfterStart_PopulatesFormatted;
var
  R: TLoadTimeRecorder;
begin
  R := TLoadTimeRecorder.Create;
  try
    R.Start;
    Sleep(10); {Tiny wait so elapsed > 0 ticks for a non-degenerate format}
    R.Finalize;
    Assert.AreNotEqual('', R.Formatted,
      'Finalize after Start produces a non-empty formatted string');
  finally
    R.Free;
  end;
end;

procedure TTestLoadTimeRecorder.Finalize_BeforeStart_NoOp;
var
  R: TLoadTimeRecorder;
begin
  R := TLoadTimeRecorder.Create;
  try
    R.Finalize;
    Assert.AreEqual('', R.Formatted,
      'Finalize without a prior Start is a no-op (Start tick is zero)');
  finally
    R.Free;
  end;
end;

procedure TTestLoadTimeRecorder.Finalize_Twice_IsIdempotent;
var
  R: TLoadTimeRecorder;
  AfterFirst: string;
begin
  R := TLoadTimeRecorder.Create;
  try
    R.Start;
    Sleep(10);
    R.Finalize;
    AfterFirst := R.Formatted;
    Sleep(50);
    R.Finalize;
    Assert.AreEqual(AfterFirst, R.Formatted,
      'Second Finalize must not overwrite the first formatted string (preserves the recorded duration)');
  finally
    R.Free;
  end;
end;

procedure TTestLoadTimeRecorder.Start_ClearsPreviouslyFinalizedString;
var
  R: TLoadTimeRecorder;
begin
  R := TLoadTimeRecorder.Create;
  try
    R.Start;
    Sleep(10);
    R.Finalize;
    Assert.AreNotEqual('', R.Formatted, 'Sanity: Finalize populated the string');
    R.Start;
    Assert.AreEqual('', R.Formatted,
      'Start clears any previously-formatted string so a second extraction begins fresh');
  finally
    R.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLoadTimeRecorder);

end.
