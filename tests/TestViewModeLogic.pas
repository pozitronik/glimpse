unit TestViewModeLogic;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestViewModeLogic = class
  public
    [Test] procedure TestKeyToViewModeDigit1;
    [Test] procedure TestKeyToViewModeDigit5;
    [Test] procedure TestKeyToViewModeNumpad1;
    [Test] procedure TestKeyToViewModeNumpad5;
    [Test] procedure TestKeyToViewModeInvalidKey;
    [Test] procedure TestKeyToViewModeLetterKey;
    [Test] procedure TestNextZoomModeFitWindow;
    [Test] procedure TestNextZoomModeFitIfLarger;
    [Test] procedure TestNextZoomModeActual;
    [Test] procedure TestModeHasZoomSubmodesSmartGrid;
    [Test] procedure TestModeHasZoomSubmodesGrid;
    [Test] procedure TestModeHasZoomSubmodesScroll;
    [Test] procedure TestModeHasZoomSubmodesFilmstrip;
    [Test] procedure TestModeHasZoomSubmodesSingle;
    [Test] procedure TestListerParamsToZoomModeFitToWindow;
    [Test] procedure TestListerParamsToZoomModeFitLarger;
    [Test] procedure TestListerParamsToZoomModeActual;
  end;

implementation

uses
  Winapi.Windows, uSettings, uWlxAPI, uViewModeLogic;

procedure TTestViewModeLogic.TestKeyToViewModeDigit1;
var M: TViewMode;
begin
  Assert.IsTrue(KeyToViewMode(Ord('1'), M));
  Assert.AreEqual(Ord(vmSmartGrid), Ord(M));
end;

procedure TTestViewModeLogic.TestKeyToViewModeDigit5;
var M: TViewMode;
begin
  Assert.IsTrue(KeyToViewMode(Ord('5'), M));
  Assert.AreEqual(Ord(vmSingle), Ord(M));
end;

procedure TTestViewModeLogic.TestKeyToViewModeNumpad1;
var M: TViewMode;
begin
  Assert.IsTrue(KeyToViewMode(VK_NUMPAD1, M));
  Assert.AreEqual(Ord(vmSmartGrid), Ord(M));
end;

procedure TTestViewModeLogic.TestKeyToViewModeNumpad5;
var M: TViewMode;
begin
  Assert.IsTrue(KeyToViewMode(VK_NUMPAD5, M));
  Assert.AreEqual(Ord(vmSingle), Ord(M));
end;

procedure TTestViewModeLogic.TestKeyToViewModeInvalidKey;
var M: TViewMode;
begin
  Assert.IsFalse(KeyToViewMode(Ord('0'), M), '0 is not a valid mode key');
end;

procedure TTestViewModeLogic.TestKeyToViewModeLetterKey;
var M: TViewMode;
begin
  Assert.IsFalse(KeyToViewMode(Ord('A'), M), 'Letter key is not valid');
end;

procedure TTestViewModeLogic.TestNextZoomModeFitWindow;
begin
  Assert.AreEqual(Ord(zmFitIfLarger), Ord(NextZoomMode(zmFitWindow)));
end;

procedure TTestViewModeLogic.TestNextZoomModeFitIfLarger;
begin
  Assert.AreEqual(Ord(zmActual), Ord(NextZoomMode(zmFitIfLarger)));
end;

procedure TTestViewModeLogic.TestNextZoomModeActual;
begin
  Assert.AreEqual(Ord(zmFitWindow), Ord(NextZoomMode(zmActual)),
    'Should wrap around to FitWindow');
end;

procedure TTestViewModeLogic.TestModeHasZoomSubmodesSmartGrid;
begin
  Assert.IsFalse(ModeHasZoomSubmodes(vmSmartGrid));
end;

procedure TTestViewModeLogic.TestModeHasZoomSubmodesGrid;
begin
  Assert.IsFalse(ModeHasZoomSubmodes(vmGrid));
end;

procedure TTestViewModeLogic.TestModeHasZoomSubmodesScroll;
begin
  Assert.IsTrue(ModeHasZoomSubmodes(vmScroll));
end;

procedure TTestViewModeLogic.TestModeHasZoomSubmodesFilmstrip;
begin
  Assert.IsTrue(ModeHasZoomSubmodes(vmFilmstrip));
end;

procedure TTestViewModeLogic.TestModeHasZoomSubmodesSingle;
begin
  Assert.IsTrue(ModeHasZoomSubmodes(vmSingle));
end;

procedure TTestViewModeLogic.TestListerParamsToZoomModeFitToWindow;
begin
  Assert.AreEqual(Ord(zmFitWindow),
    Ord(ListerParamsToZoomMode(lcp_FitToWindow)));
end;

procedure TTestViewModeLogic.TestListerParamsToZoomModeFitLarger;
begin
  Assert.AreEqual(Ord(zmFitIfLarger),
    Ord(ListerParamsToZoomMode(lcp_FitToWindow or lcp_FitLargerOnly)));
end;

procedure TTestViewModeLogic.TestListerParamsToZoomModeActual;
begin
  Assert.AreEqual(Ord(zmActual), Ord(ListerParamsToZoomMode(0)),
    'No fit flags should mean actual/original size');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestViewModeLogic);

end.
