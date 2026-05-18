{Tests for the uHotkeysCodec free functions. The existing TestHotkeys
 fixture indirectly covers the codec by going through THotkeyChord's
 shim methods; this fixture pins the free-function entry points
 directly so a future change to the chord shims can't hide a regression
 in the codec layer.}
unit TestHotkeysCodec;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHotkeysCodec = class
  public
    [Test] procedure ChordToIniStr_F2_RoundTripsThroughChordFromIniStr;
    [Test] procedure ChordFromIniStr_Empty_ReturnsUnassigned;
    [Test] procedure ChordsToIniStr_TwoChords_JoinedByPipe;
    [Test] procedure ChordsFromIniStr_OneGarbageAmongValid_GarbageSkipped;
  end;

implementation

uses
  System.Classes, Winapi.Windows,
  uHotkeys, uHotkeysCodec;

procedure TTestHotkeysCodec.ChordToIniStr_F2_RoundTripsThroughChordFromIniStr;
var
  Source, Parsed: THotkeyChord;
  Text: string;
begin
  {The free-function pair is the authoritative codec. Pin the round-trip
   here so a future change to the chord shims (e.g. caching) doesn't
   silently break the underlying parser.}
  Source := THotkeyChord.Make(VK_F2, [ssCtrl, ssShift]);
  Text := ChordToIniStr(Source);
  Assert.AreEqual('Ctrl+Shift+F2', Text);
  Parsed := ChordFromIniStr(Text);
  Assert.IsTrue(Parsed.IsAssigned);
  Assert.IsTrue(Parsed.Equals(Source));
end;

procedure TTestHotkeysCodec.ChordFromIniStr_Empty_ReturnsUnassigned;
begin
  {Empty input must return THotkeyChord.None — Load relies on this
   to treat 'Settings=' as an explicit unbinding rather than a parse
   error.}
  Assert.IsFalse(ChordFromIniStr('').IsAssigned);
  Assert.IsFalse(ChordFromIniStr('   ').IsAssigned);
end;

procedure TTestHotkeysCodec.ChordsToIniStr_TwoChords_JoinedByPipe;
var
  C: THotkeyChordArray;
begin
  {CHORD_SEPARATOR is the single source of truth for the join character;
   this test pins the visible '|' so changing the constant to anything
   else without updating callers fails the test loudly.}
  SetLength(C, 2);
  C[0] := THotkeyChord.Make(VK_F2, []);
  C[1] := THotkeyChord.Make(VK_F3, [ssCtrl]);
  Assert.AreEqual('F2|Ctrl+F3', ChordsToIniStr(C));
end;

procedure TTestHotkeysCodec.ChordsFromIniStr_OneGarbageAmongValid_GarbageSkipped;
var
  C: THotkeyChordArray;
begin
  {Partial-parse tolerance: a single unparseable segment in a pipe-joined
   value must not nuke the surrounding valid chords. Pinned here at the
   codec layer because the THotkeyBindings.Load path depends on it for
   hand-edited-INI survival.}
  C := ChordsFromIniStr('F2|NotAKey|F3');
  Assert.AreEqual<Integer>(2, Length(C));
  Assert.AreEqual<Integer>(VK_F2, C[0].Key);
  Assert.AreEqual<Integer>(VK_F3, C[1].Key);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHotkeysCodec);

end.
