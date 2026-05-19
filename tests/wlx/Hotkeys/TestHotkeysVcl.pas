unit TestHotkeysVcl;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHotkeysVcl = class
  public
    {Pins the chord-to-TShortCut conversion. Verified against
     Vcl.Menus.ShortCut output for the same inputs so a future Delphi
     change to that helper's encoding fails loudly here instead of
     silently breaking menu shortcuts at runtime.}
    [Test] procedure ToShortCut_UnboundChord_ReturnsZero;
    [Test] procedure ToShortCut_PlainKey_MatchesVclShortCut;
    [Test] procedure ToShortCut_CtrlModifier_MatchesVclShortCut;
    [Test] procedure ToShortCut_ShiftAltCtrl_MatchesVclShortCut;
  end;

implementation

uses
  System.Classes, Vcl.Menus, Winapi.Windows,
  Hotkeys, HotkeysVcl;

procedure TTestHotkeysVcl.ToShortCut_UnboundChord_ReturnsZero;
begin
  {THotkeyChord.None has Key=0; the converter must yield 0 so callers
   can assign to TMenuItem.ShortCut unconditionally and the menu
   renders as "no shortcut".}
  Assert.AreEqual<Integer>(0, Integer(ToShortCut(THotkeyChord.None)));
end;

procedure TTestHotkeysVcl.ToShortCut_PlainKey_MatchesVclShortCut;
var
  Chord: THotkeyChord;
begin
  Chord := THotkeyChord.Make(Ord('A'), []);
  Assert.AreEqual<Integer>(
    Integer(Vcl.Menus.ShortCut(Ord('A'), [])),
    Integer(ToShortCut(Chord)));
end;

procedure TTestHotkeysVcl.ToShortCut_CtrlModifier_MatchesVclShortCut;
var
  Chord: THotkeyChord;
begin
  Chord := THotkeyChord.Make(VK_F2, [ssCtrl]);
  Assert.AreEqual<Integer>(
    Integer(Vcl.Menus.ShortCut(VK_F2, [ssCtrl])),
    Integer(ToShortCut(Chord)));
end;

procedure TTestHotkeysVcl.ToShortCut_ShiftAltCtrl_MatchesVclShortCut;
var
  Chord: THotkeyChord;
begin
  Chord := THotkeyChord.Make(VK_DELETE, [ssShift, ssCtrl, ssAlt]);
  Assert.AreEqual<Integer>(
    Integer(Vcl.Menus.ShortCut(VK_DELETE, [ssShift, ssCtrl, ssAlt])),
    Integer(ToShortCut(Chord)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHotkeysVcl);

end.
