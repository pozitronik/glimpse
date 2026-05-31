{Pins the default chords, INI keys and captions for the Clear-selection
 and Invert-selection commands added as configurable hotkey actions. The
 generic iterate-all tests in TestHotkeys cover round-trip and uniqueness;
 these lock the specific chosen chords against accidental change.}
unit TestSelectionHotkeyDefaults;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSelectionHotkeyDefaults = class
  public
    [Test] procedure ClearSelection_DefaultIsCtrlD;
    [Test] procedure InvertSelection_DefaultIsCtrlShiftA;
    [Test] procedure ClearSelection_IniKeyAndCaption;
    [Test] procedure InvertSelection_IniKeyAndCaption;
  end;

implementation

uses
  System.Classes, System.SysUtils,
  Hotkeys;

procedure TTestSelectionHotkeyDefaults.ClearSelection_DefaultIsCtrlD;
var
  Chords: THotkeyChordArray;
  Count: Integer;
begin
  Chords := DefaultBinding(paClearSelection);
  Count := Length(Chords);
  Assert.AreEqual(1, Count, 'Clear selection should have one default chord');
  Assert.IsTrue(Chords[0].Equals(THotkeyChord.Make(Ord('D'), [ssCtrl])), 'default should be Ctrl+D');
end;

procedure TTestSelectionHotkeyDefaults.InvertSelection_DefaultIsCtrlShiftA;
var
  Chords: THotkeyChordArray;
  Count: Integer;
begin
  Chords := DefaultBinding(paInvertSelection);
  Count := Length(Chords);
  Assert.AreEqual(1, Count, 'Invert selection should have one default chord');
  Assert.IsTrue(Chords[0].Equals(THotkeyChord.Make(Ord('A'), [ssCtrl, ssShift])), 'default should be Ctrl+Shift+A');
end;

procedure TTestSelectionHotkeyDefaults.ClearSelection_IniKeyAndCaption;
begin
  Assert.AreEqual('ClearSelection', ActionIniKey(paClearSelection));
  Assert.AreEqual('Clear frame selection', ActionCaption(paClearSelection));
end;

procedure TTestSelectionHotkeyDefaults.InvertSelection_IniKeyAndCaption;
begin
  Assert.AreEqual('InvertSelection', ActionIniKey(paInvertSelection));
  Assert.AreEqual('Invert frame selection', ActionCaption(paInvertSelection));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSelectionHotkeyDefaults);

end.
