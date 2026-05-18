{Tests for the uHotkeysDisplay free functions. Mirrors the codec test
 fixture: the on-screen formatter is exercised indirectly through
 THotkeyChord.ToDisplayStr in TestHotkeys, but pinning the free-function
 entry points here protects the display path from a future divergence
 between INI and display (e.g. a localised display string).}
unit TestHotkeysDisplay;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHotkeysDisplay = class
  public
    [Test] procedure ChordToDisplayStr_CtrlShiftF1_RendersAllModifiers;
    [Test] procedure ChordsToDisplayStr_TwoChords_JoinedByCommaSpace;
    [Test] procedure ChordToDisplayStr_Unassigned_RendersEmpty;
  end;

implementation

uses
  System.Classes, Winapi.Windows,
  uHotkeys, uHotkeysDisplay;

procedure TTestHotkeysDisplay.ChordToDisplayStr_CtrlShiftF1_RendersAllModifiers;
var
  Chord: THotkeyChord;
begin
  {Pin the modifier-prefix order (Ctrl+Shift+Alt+Key). The settings
   dialog's user-visible Shortcut column depends on this layout.}
  Chord := THotkeyChord.Make(VK_F1, [ssCtrl, ssShift]);
  Assert.AreEqual('Ctrl+Shift+F1', ChordToDisplayStr(Chord));
end;

procedure TTestHotkeysDisplay.ChordsToDisplayStr_TwoChords_JoinedByCommaSpace;
var
  C: THotkeyChordArray;
begin
  {', ' is the user-visible separator — comma + space. Pinned here so a
   future change to a different separator (e.g. ' | ' for compactness)
   surfaces in the test rather than silently in the dialog.}
  SetLength(C, 2);
  C[0] := THotkeyChord.Make(VK_LEFT, []);
  C[1] := THotkeyChord.Make(VK_BACK, []);
  Assert.AreEqual('Left, Backspace', ChordsToDisplayStr(C));
end;

procedure TTestHotkeysDisplay.ChordToDisplayStr_Unassigned_RendersEmpty;
begin
  {Unassigned chord must render '' so the settings dialog's Shortcut
   column for an unbound action is simply blank, not a token like 'None'
   that would suggest a special key.}
  Assert.AreEqual('', ChordToDisplayStr(THotkeyChord.None));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHotkeysDisplay);

end.
