unit TestTypes;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTypes = class
  public
    { Enum ordering is load-bearing: used as array indices in uToolbarLayout }
    [Test] procedure ViewModeOrdinals;
    [Test] procedure ViewModeRange;
    [Test] procedure ZoomModeOrdinals;
    [Test] procedure ZoomModeRange;
    [Test] procedure FFmpegModeOrdinals;
  end;

implementation

uses
  uTypes;

procedure TTestTypes.ViewModeOrdinals;
begin
  Assert.AreEqual(0, Ord(vmSmartGrid));
  Assert.AreEqual(1, Ord(vmGrid));
  Assert.AreEqual(2, Ord(vmScroll));
  Assert.AreEqual(3, Ord(vmFilmstrip));
  Assert.AreEqual(4, Ord(vmSingle));
end;

procedure TTestTypes.ViewModeRange;
begin
  Assert.AreEqual(vmSmartGrid, Low(TViewMode));
  Assert.AreEqual(vmSingle, High(TViewMode));
end;

procedure TTestTypes.ZoomModeOrdinals;
begin
  Assert.AreEqual(0, Ord(zmFitWindow));
  Assert.AreEqual(1, Ord(zmFitIfLarger));
  Assert.AreEqual(2, Ord(zmActual));
end;

procedure TTestTypes.ZoomModeRange;
begin
  Assert.AreEqual(zmFitWindow, Low(TZoomMode));
  Assert.AreEqual(zmActual, High(TZoomMode));
end;

procedure TTestTypes.FFmpegModeOrdinals;
begin
  Assert.AreEqual(0, Ord(fmAuto));
  Assert.AreEqual(1, Ord(fmExe));
end;

end.
