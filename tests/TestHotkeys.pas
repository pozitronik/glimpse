{Unit tests for uHotkeys: chord parse/serialise, multi-chord storage,
 INI round-trip with '|' separator, lookup with alias normalisation,
 conflict detection, defaults integrity.}
unit TestHotkeys;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestHotkeyChord = class
  public
    [Test] procedure ToIniStr_F2_NoModifiers;
    [Test] procedure ToIniStr_CtrlShiftF1;
    [Test] procedure ToIniStr_AltEnter;
    [Test] procedure ToIniStr_OemPlus;
    [Test] procedure ToIniStr_Unassigned_Empty;
    [Test] procedure FromIniStr_F2;
    [Test] procedure FromIniStr_CtrlS;
    [Test] procedure FromIniStr_AltEnter;
    [Test] procedure FromIniStr_CtrlShiftAltF1_OrderIndependent;
    [Test] procedure FromIniStr_Empty_Unassigned;
    [Test] procedure FromIniStr_Nonsense_Unassigned;
    [Test] procedure FromIniStr_LowerCase_Accepted;
    [Test] procedure FromIniStr_PlusKey_Recovered;
    [Test] procedure Equals_SameFields_True;
    [Test] procedure Equals_DifferentKey_False;
    [Test] procedure Equals_DifferentModifiers_False;
    [Test] procedure RoundTrip_EveryDefaultBinding;
    {The next five tests pin down THotkeyChord.Make's normalisation contract
     for numpad and OEM alias keys handed in by the capture dialog. They guard
     the round-trip that kept captured numpad chords from surviving INI save.}
    [Test] procedure Make_NumpadDigit_NormalisesToTopRow;
    [Test] procedure Make_VKAdd_NormalisesToOemPlus;
    [Test] procedure Make_VKSubtract_NormalisesToOemMinus;
    [Test] procedure Make_VKDecimal_NormalisesToOemPeriod;
    [Test] procedure Make_CapturedNumpad_RoundTripsThroughIni;
  end;

  [TestFixture]
  TTestChordArrayHelpers = class
  public
    [Test] procedure ToIniStr_Empty;
    [Test] procedure ToIniStr_SingleChord_NoSeparator;
    [Test] procedure ToIniStr_MultipleChords_PipeSeparated;
    [Test] procedure FromIniStr_Empty_EmptyArray;
    [Test] procedure FromIniStr_MultipleChords_ParsedInOrder;
    [Test] procedure FromIniStr_OneGarbageAmongValid_GarbageSkipped;
    [Test] procedure RoundTrip_PrevFileDefaults;
    [Test] procedure ToDisplayStr_JoinsWithComma;
  end;

  [TestFixture]
  TTestHotkeyBindings = class
  private
    FTempDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Defaults_PaNoneIsEmpty;
    [Test] procedure Defaults_SaveSelectedIsUnbound;
    [Test] procedure Defaults_PrevFileHasThreeChords;
    [Test] procedure Defaults_NextFileHasTwoChords;
    [Test] procedure Defaults_PrevFrameHasBareAndCtrlLeft;
    [Test] procedure Defaults_NextFrameHasBareAndCtrlRight;
    [Test] procedure Lookup_Defaults_Resolve;
    [Test] procedure Lookup_PrevFile_EveryDefaultChord_ResolvesSameAction;
    [Test] procedure Lookup_BareLeft_IsFrameNavNotFileNav;
    [Test] procedure Lookup_BareRight_IsFrameNavNotFileNav;
    [Test] procedure Lookup_Numpad0_ResolvesAsDigit0;
    [Test] procedure Lookup_NumpadAdd_ResolvesAsOemPlus;
    [Test] procedure Lookup_NumpadSubtract_ResolvesAsOemMinus;
    [Test] procedure Lookup_Unknown_ReturnsNone;
    [Test] procedure Lookup_IgnoresMouseFlags;
    [Test] procedure AddChord_Unique_ReturnsTrue;
    [Test] procedure AddChord_Duplicate_ReturnsFalseSilently;
    [Test] procedure AddChord_Unassigned_ReturnsFalse;
    [Test] procedure RemoveChord_Present_ReturnsTrue;
    [Test] procedure RemoveChord_Absent_ReturnsFalse;
    [Test] procedure Put_ReplacesWholeList;
    [Test] procedure ResetToDefaults_ReplacesCustomBindings;
    [Test] procedure Assign_DeepCopies;
    [Test] procedure FindActionByChord_DetectsConflict;
    [Test] procedure FindActionByChord_ExcludesSelf;
    [Test] procedure IniRoundTrip_MultiChordPreserved;
    [Test] procedure IniLoad_EmptyValue_Unbinds;
    [Test] procedure IniLoad_MissingKey_KeepsDefault;
    [Test] procedure IniLoad_GarbageAmongValid_OtherChordsKept;
    [Test] procedure IniSave_SingleChord_NoSeparatorInOutput;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.IniFiles,
  Winapi.Windows, Vcl.Controls,
  uHotkeys;

{TTestHotkeyChord}

procedure TTestHotkeyChord.ToIniStr_F2_NoModifiers;
begin
  Assert.AreEqual('F2', THotkeyChord.Make(VK_F2, []).ToIniStr);
end;

procedure TTestHotkeyChord.ToIniStr_CtrlShiftF1;
begin
  Assert.AreEqual('Ctrl+Shift+F1', THotkeyChord.Make(VK_F1, [ssCtrl, ssShift]).ToIniStr);
end;

procedure TTestHotkeyChord.ToIniStr_AltEnter;
begin
  Assert.AreEqual('Alt+Enter', THotkeyChord.Make(VK_RETURN, [ssAlt]).ToIniStr);
end;

procedure TTestHotkeyChord.ToIniStr_OemPlus;
begin
  Assert.AreEqual('+', THotkeyChord.Make(VK_OEM_PLUS, []).ToIniStr);
end;

procedure TTestHotkeyChord.ToIniStr_Unassigned_Empty;
begin
  Assert.AreEqual('', THotkeyChord.None.ToIniStr);
end;

procedure TTestHotkeyChord.FromIniStr_F2;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.FromIniStr('F2');
  Assert.IsTrue(C.IsAssigned);
  Assert.AreEqual<Integer>(VK_F2, C.Key);
  Assert.IsTrue(C.Modifiers = []);
end;

procedure TTestHotkeyChord.FromIniStr_CtrlS;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.FromIniStr('Ctrl+S');
  Assert.AreEqual<Integer>(Ord('S'), C.Key);
  Assert.IsTrue(C.Modifiers = [ssCtrl]);
end;

procedure TTestHotkeyChord.FromIniStr_AltEnter;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.FromIniStr('Alt+Enter');
  Assert.AreEqual<Integer>(VK_RETURN, C.Key);
  Assert.IsTrue(C.Modifiers = [ssAlt]);
end;

procedure TTestHotkeyChord.FromIniStr_CtrlShiftAltF1_OrderIndependent;
var
  A, B: THotkeyChord;
begin
  A := THotkeyChord.FromIniStr('Ctrl+Shift+Alt+F1');
  B := THotkeyChord.FromIniStr('Alt+Shift+Ctrl+F1');
  Assert.AreEqual<Integer>(A.Key, B.Key);
  Assert.IsTrue(A.Modifiers = B.Modifiers);
  Assert.IsTrue(A.Modifiers = [ssCtrl, ssShift, ssAlt]);
end;

procedure TTestHotkeyChord.FromIniStr_Empty_Unassigned;
begin
  Assert.IsFalse(THotkeyChord.FromIniStr('').IsAssigned);
  Assert.IsFalse(THotkeyChord.FromIniStr('   ').IsAssigned);
end;

procedure TTestHotkeyChord.FromIniStr_Nonsense_Unassigned;
begin
  Assert.IsFalse(THotkeyChord.FromIniStr('ZZZZ').IsAssigned);
  Assert.IsFalse(THotkeyChord.FromIniStr('Ctrl+').IsAssigned);
  Assert.IsFalse(THotkeyChord.FromIniStr('Ctrl+Alt').IsAssigned);
end;

procedure TTestHotkeyChord.FromIniStr_LowerCase_Accepted;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.FromIniStr('ctrl+shift+f1');
  Assert.AreEqual<Integer>(VK_F1, C.Key);
  Assert.IsTrue(C.Modifiers = [ssCtrl, ssShift]);
end;

procedure TTestHotkeyChord.FromIniStr_PlusKey_Recovered;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.FromIniStr('+');
  Assert.IsTrue(C.IsAssigned);
  Assert.AreEqual<Integer>(VK_OEM_PLUS, C.Key);
end;

procedure TTestHotkeyChord.Equals_SameFields_True;
var
  A, B: THotkeyChord;
begin
  A := THotkeyChord.Make(VK_F1, [ssCtrl]);
  B := THotkeyChord.Make(VK_F1, [ssCtrl]);
  Assert.IsTrue(A.Equals(B));
end;

procedure TTestHotkeyChord.Equals_DifferentKey_False;
var
  A, B: THotkeyChord;
begin
  A := THotkeyChord.Make(VK_F1, [ssCtrl]);
  B := THotkeyChord.Make(VK_F2, [ssCtrl]);
  Assert.IsFalse(A.Equals(B));
end;

procedure TTestHotkeyChord.Equals_DifferentModifiers_False;
var
  A, B: THotkeyChord;
begin
  A := THotkeyChord.Make(VK_F1, [ssCtrl]);
  B := THotkeyChord.Make(VK_F1, [ssCtrl, ssShift]);
  Assert.IsFalse(A.Equals(B));
end;

procedure TTestHotkeyChord.Make_NumpadDigit_NormalisesToTopRow;
var
  C: THotkeyChord;
begin
  {When the shortcut editor captures a VK_NUMPAD0 press and calls
   THotkeyChord.Make, the resulting chord must carry the normalised
   Ord('0') — otherwise the chord has no display name (VKToName returns
   empty for VK_NUMPAD0..9), rendering as blank in the editor list box
   and failing to round-trip through the INI. Lookup already normalises
   at match time, so storing normalised is consistent with runtime.}
  C := THotkeyChord.Make(VK_NUMPAD0, []);
  Assert.AreEqual<Integer>(Ord('0'), C.Key,
    'Numpad 0 must be stored as Ord(''0'')');
  Assert.AreEqual('0', C.ToDisplayStr,
    'Display must show ''0'' rather than empty');
end;

procedure TTestHotkeyChord.Make_VKAdd_NormalisesToOemPlus;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.Make(VK_ADD, []);
  Assert.AreEqual<Integer>(VK_OEM_PLUS, C.Key,
    'Numpad + must be stored as VK_OEM_PLUS');
  Assert.AreEqual('+', C.ToDisplayStr);
end;

procedure TTestHotkeyChord.Make_VKSubtract_NormalisesToOemMinus;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.Make(VK_SUBTRACT, []);
  Assert.AreEqual<Integer>(VK_OEM_MINUS, C.Key);
  Assert.AreEqual('-', C.ToDisplayStr);
end;

procedure TTestHotkeyChord.Make_VKDecimal_NormalisesToOemPeriod;
var
  C: THotkeyChord;
begin
  C := THotkeyChord.Make(VK_DECIMAL, []);
  Assert.AreEqual<Integer>(VK_OEM_PERIOD, C.Key);
  Assert.AreEqual('.', C.ToDisplayStr);
end;

procedure TTestHotkeyChord.Make_CapturedNumpad_RoundTripsThroughIni;
var
  C, Back: THotkeyChord;
begin
  {End-to-end: a user presses Numpad 0 in the capture dialog, the chord
   is serialised to INI, reloaded on the next session. Without
   normalisation in Make the ToIniStr result is empty and the binding
   silently disappears.}
  C := THotkeyChord.Make(VK_NUMPAD0, [ssCtrl]);
  Assert.AreNotEqual('', C.ToIniStr,
    'Captured numpad key must produce a non-empty INI representation');
  Back := THotkeyChord.FromIniStr(C.ToIniStr);
  Assert.IsTrue(Back.IsAssigned);
  Assert.AreEqual<Integer>(Ord('0'), Back.Key);
  Assert.IsTrue(Back.Modifiers = [ssCtrl]);
end;

procedure TTestHotkeyChord.RoundTrip_EveryDefaultBinding;
var
  A: TPluginAction;
  Defaults: THotkeyChordArray;
  I: Integer;
  Parsed: THotkeyChord;
begin
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    Defaults := DefaultBinding(A);
    for I := 0 to High(Defaults) do
    begin
      Parsed := THotkeyChord.FromIniStr(Defaults[I].ToIniStr);
      Assert.IsTrue(Parsed.IsAssigned,
        Format('Default chord %d of %s failed to parse: %s',
          [I, ActionIniKey(A), Defaults[I].ToIniStr]));
      Assert.IsTrue(Parsed.Equals(Defaults[I]),
        Format('Round-trip diverged for %s chord %d', [ActionIniKey(A), I]));
    end;
  end;
end;

{TTestChordArrayHelpers}

procedure TTestChordArrayHelpers.ToIniStr_Empty;
var
  Empty: THotkeyChordArray;
begin
  SetLength(Empty, 0);
  Assert.AreEqual('', ChordsToIniStr(Empty));
end;

procedure TTestChordArrayHelpers.ToIniStr_SingleChord_NoSeparator;
var
  C: THotkeyChordArray;
begin
  SetLength(C, 1);
  C[0] := THotkeyChord.Make(VK_F2, []);
  Assert.AreEqual('F2', ChordsToIniStr(C));
end;

procedure TTestChordArrayHelpers.ToIniStr_MultipleChords_PipeSeparated;
var
  C: THotkeyChordArray;
begin
  SetLength(C, 3);
  C[0] := THotkeyChord.Make(VK_LEFT, []);
  C[1] := THotkeyChord.Make(VK_BACK, []);
  C[2] := THotkeyChord.Make(Ord('Z'), []);
  Assert.AreEqual('Left|Backspace|Z', ChordsToIniStr(C));
end;

procedure TTestChordArrayHelpers.FromIniStr_Empty_EmptyArray;
begin
  Assert.AreEqual<Integer>(0, Length(ChordsFromIniStr('')));
  Assert.AreEqual<Integer>(0, Length(ChordsFromIniStr('   ')));
end;

procedure TTestChordArrayHelpers.FromIniStr_MultipleChords_ParsedInOrder;
var
  C: THotkeyChordArray;
begin
  C := ChordsFromIniStr('Left|PageUp|Backspace|Z');
  Assert.AreEqual<Integer>(4, Length(C));
  Assert.AreEqual<Integer>(VK_LEFT, C[0].Key);
  Assert.AreEqual<Integer>(VK_PRIOR, C[1].Key);
  Assert.AreEqual<Integer>(VK_BACK, C[2].Key);
  Assert.AreEqual<Integer>(Ord('Z'), C[3].Key);
end;

procedure TTestChordArrayHelpers.FromIniStr_OneGarbageAmongValid_GarbageSkipped;
var
  C: THotkeyChordArray;
begin
  {Garbage segments are dropped so a single typo doesn't nuke a whole row.}
  C := ChordsFromIniStr('Left|NotAKey|PageUp');
  Assert.AreEqual<Integer>(2, Length(C));
  Assert.AreEqual<Integer>(VK_LEFT, C[0].Key);
  Assert.AreEqual<Integer>(VK_PRIOR, C[1].Key);
end;

procedure TTestChordArrayHelpers.RoundTrip_PrevFileDefaults;
var
  Orig, Back: THotkeyChordArray;
  I: Integer;
  Text: string;
begin
  Orig := DefaultBinding(paPrevFile);
  Text := ChordsToIniStr(Orig);
  Back := ChordsFromIniStr(Text);
  Assert.AreEqual<Integer>(Length(Orig), Length(Back));
  for I := 0 to High(Orig) do
    Assert.IsTrue(Orig[I].Equals(Back[I]),
      Format('paPrevFile chord %d diverged: %s != %s',
        [I, Orig[I].ToIniStr, Back[I].ToIniStr]));
end;

procedure TTestChordArrayHelpers.ToDisplayStr_JoinsWithComma;
var
  C: THotkeyChordArray;
begin
  SetLength(C, 3);
  C[0] := THotkeyChord.Make(VK_LEFT, []);
  C[1] := THotkeyChord.Make(VK_BACK, []);
  C[2] := THotkeyChord.Make(Ord('Z'), []);
  Assert.AreEqual('Left, Backspace, Z', ChordsToDisplayStr(C));
end;

{TTestHotkeyBindings}

procedure TTestHotkeyBindings.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_Hotkeys_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestHotkeyBindings.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestHotkeyBindings.Defaults_PaNoneIsEmpty;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual<Integer>(0, Length(B.Get(paNone)));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Defaults_SaveSelectedIsUnbound;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual<Integer>(0, Length(B.Get(paSaveSelected)));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Defaults_PrevFileHasThreeChords;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual<Integer>(3, Length(B.Get(paPrevFile)),
      'paPrevFile ships with PageUp, Backspace, Z (Left moved to paPrevFrame)');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Defaults_NextFileHasTwoChords;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual<Integer>(2, Length(B.Get(paNextFile)),
      'paNextFile ships with PageDown, Space (Right moved to paNextFrame)');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Defaults_PrevFrameHasBareAndCtrlLeft;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual<Integer>(2, Length(B.Get(paPrevFrame)),
      'paPrevFrame ships with bare Left and Ctrl+Left');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Defaults_NextFrameHasBareAndCtrlRight;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual<Integer>(2, Length(B.Get(paNextFrame)),
      'paNextFrame ships with bare Right and Ctrl+Right');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_Defaults_Resolve;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F2, [])));
    Assert.AreEqual(Ord(paToggleFullScreen), Ord(B.Lookup(VK_RETURN, [ssAlt])));
    Assert.AreEqual(Ord(paOpenInPlayer), Ord(B.Lookup(VK_RETURN, [])));
    Assert.AreEqual(Ord(paCloseLister), Ord(B.Lookup(VK_ESCAPE, [])));
    Assert.AreEqual(Ord(paZoomReset), Ord(B.Lookup(Ord('0'), [])));
    Assert.AreEqual(Ord(paViewModeGrid), Ord(B.Lookup(Ord('2'), [ssCtrl])));
    Assert.AreEqual(Ord(paPrevFrame), Ord(B.Lookup(VK_LEFT, [ssCtrl])));
    Assert.AreEqual(Ord(paFrameCountInc), Ord(B.Lookup(VK_UP, [ssCtrl])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_PrevFile_EveryDefaultChord_ResolvesSameAction;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    {All three default chords for paPrevFile must resolve to the same action.}
    Assert.AreEqual(Ord(paPrevFile), Ord(B.Lookup(VK_PRIOR, [])));
    Assert.AreEqual(Ord(paPrevFile), Ord(B.Lookup(VK_BACK, [])));
    Assert.AreEqual(Ord(paPrevFile), Ord(B.Lookup(Ord('Z'), [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_BareLeft_IsFrameNavNotFileNav;
var
  B: THotkeyBindings;
begin
  {Regression guard: bare Left is paPrevFrame, not paPrevFile, so single
   view acts as a frame slideshow with arrows. File nav falls to the
   other defaults (PageUp / Backspace / Z).}
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paPrevFrame), Ord(B.Lookup(VK_LEFT, [])));
    Assert.AreEqual(Ord(paPrevFrame), Ord(B.Lookup(VK_LEFT, [ssCtrl])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_BareRight_IsFrameNavNotFileNav;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paNextFrame), Ord(B.Lookup(VK_RIGHT, [])));
    Assert.AreEqual(Ord(paNextFrame), Ord(B.Lookup(VK_RIGHT, [ssCtrl])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_Numpad0_ResolvesAsDigit0;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paZoomReset), Ord(B.Lookup(VK_NUMPAD0, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_NumpadAdd_ResolvesAsOemPlus;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paZoomIn), Ord(B.Lookup(VK_ADD, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_NumpadSubtract_ResolvesAsOemMinus;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paZoomOut), Ord(B.Lookup(VK_SUBTRACT, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_Unknown_ReturnsNone;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F24, [])));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F2, [ssCtrl])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_IgnoresMouseFlags;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F2, [ssLeft])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.AddChord_Unique_ReturnsTrue;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.IsTrue(B.AddChord(paSaveSelected, THotkeyChord.Make(VK_F9, [ssCtrl])));
    Assert.AreEqual<Integer>(1, Length(B.Get(paSaveSelected)));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.AddChord_Duplicate_ReturnsFalseSilently;
var
  B: THotkeyBindings;
  Chord: THotkeyChord;
begin
  B := THotkeyBindings.Create;
  try
    {Adding the same chord twice is a no-op, not a conflict prompt.}
    Chord := THotkeyChord.Make(VK_F9, [ssCtrl]);
    Assert.IsTrue(B.AddChord(paSaveSelected, Chord));
    Assert.IsFalse(B.AddChord(paSaveSelected, Chord));
    Assert.AreEqual<Integer>(1, Length(B.Get(paSaveSelected)));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.AddChord_Unassigned_ReturnsFalse;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.IsFalse(B.AddChord(paSaveSelected, THotkeyChord.None));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.RemoveChord_Present_ReturnsTrue;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    {paPrevFile ships with PageUp; removing it leaves two chords (Backspace
     and Z), and PageUp stops resolving.}
    Assert.IsTrue(B.RemoveChord(paPrevFile, THotkeyChord.Make(VK_PRIOR, [])));
    Assert.AreEqual<Integer>(2, Length(B.Get(paPrevFile)));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_PRIOR, [])),
      'PageUp is no longer bound after removal');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.RemoveChord_Absent_ReturnsFalse;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.IsFalse(B.RemoveChord(paPrevFile, THotkeyChord.Make(VK_F24, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Put_ReplacesWholeList;
var
  B: THotkeyBindings;
  NewList: THotkeyChordArray;
begin
  B := THotkeyBindings.Create;
  try
    SetLength(NewList, 2);
    NewList[0] := THotkeyChord.Make(VK_F9, []);
    NewList[1] := THotkeyChord.Make(VK_F10, []);
    B.Put(paPrevFile, NewList);
    Assert.AreEqual<Integer>(2, Length(B.Get(paPrevFile)));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_PRIOR, [])),
      'After Put, the original PageUp chord is gone from paPrevFile');
    Assert.AreEqual(Ord(paPrevFile), Ord(B.Lookup(VK_F9, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.ResetToDefaults_ReplacesCustomBindings;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    B.Put(paSettings, [THotkeyChord.Make(VK_F9, [])]);
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F9, [])));
    B.ResetToDefaults;
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F2, [])));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F9, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Assign_DeepCopies;
var
  A, B: THotkeyBindings;
  List: THotkeyChordArray;
begin
  A := THotkeyBindings.Create;
  B := THotkeyBindings.Create;
  try
    A.Put(paPrevFile, [THotkeyChord.Make(VK_F9, [])]);
    B.Assign(A);
    {Mutating A after Assign must not affect B — proves we copied, not aliased.}
    A.Put(paPrevFile, [THotkeyChord.Make(VK_F10, [])]);
    List := B.Get(paPrevFile);
    Assert.AreEqual<Integer>(1, Length(List));
    Assert.AreEqual<Integer>(VK_F9, List[0].Key);
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.FindActionByChord_DetectsConflict;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    {F2 is assigned to paSettings by default; a fresh F2 chord searched
     globally should find paSettings.}
    Assert.AreEqual(Ord(paSettings),
      Ord(B.FindActionByChord(THotkeyChord.Make(VK_F2, []))));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.FindActionByChord_ExcludesSelf;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paNone),
      Ord(B.FindActionByChord(THotkeyChord.Make(VK_F2, []), paSettings)),
      'Self-binding must not count as a conflict');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniRoundTrip_MultiChordPreserved;
var
  A, B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
  Loaded: THotkeyChordArray;
begin
  Path := TPath.Combine(FTempDir, 'multi.ini');
  A := THotkeyBindings.Create;
  try
    {Put a custom 3-chord list on paSettings so we have something distinct to
     round-trip.}
    A.Put(paSettings, [THotkeyChord.Make(VK_F9, []),
                       THotkeyChord.Make(VK_F10, [ssCtrl]),
                       THotkeyChord.Make(VK_F11, [ssShift])]);
    Ini := TIniFile.Create(Path);
    try
      A.Save(Ini);
    finally
      Ini.Free;
    end;
  finally
    A.Free;
  end;

  B := THotkeyBindings.Create;
  try
    Ini := TIniFile.Create(Path);
    try
      B.Load(Ini);
    finally
      Ini.Free;
    end;
    Loaded := B.Get(paSettings);
    Assert.AreEqual<Integer>(3, Length(Loaded));
    Assert.AreEqual<Integer>(VK_F9, Loaded[0].Key);
    Assert.AreEqual<Integer>(VK_F10, Loaded[1].Key);
    Assert.IsTrue(Loaded[1].Modifiers = [ssCtrl]);
    Assert.AreEqual<Integer>(VK_F11, Loaded[2].Key);
    Assert.IsTrue(Loaded[2].Modifiers = [ssShift]);
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniLoad_EmptyValue_Unbinds;
var
  B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
begin
  Path := TPath.Combine(FTempDir, 'empty.ini');
  Ini := TIniFile.Create(Path);
  try
    Ini.WriteString(HOTKEYS_SECTION, 'Settings', '');
  finally
    Ini.Free;
  end;

  B := THotkeyBindings.Create;
  try
    Ini := TIniFile.Create(Path);
    try
      B.Load(Ini);
    finally
      Ini.Free;
    end;
    Assert.AreEqual<Integer>(0, Length(B.Get(paSettings)));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F2, [])));
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniLoad_MissingKey_KeepsDefault;
var
  B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
  List: THotkeyChordArray;
begin
  Path := TPath.Combine(FTempDir, 'missing.ini');
  Ini := TIniFile.Create(Path);
  try
    Ini.WriteString(HOTKEYS_SECTION, 'Settings', 'F9');
  finally
    Ini.Free;
  end;

  B := THotkeyBindings.Create;
  try
    Ini := TIniFile.Create(Path);
    try
      B.Load(Ini);
    finally
      Ini.Free;
    end;
    Assert.AreEqual<Integer>(VK_F9, B.Get(paSettings)[0].Key);
    List := B.Get(paToggleToolbar);
    Assert.AreEqual<Integer>(1, Length(List));
    Assert.AreEqual<Integer>(VK_F4, List[0].Key,
      'ToggleToolbar had no INI entry and must keep its F4 default');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniLoad_GarbageAmongValid_OtherChordsKept;
var
  B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
  List: THotkeyChordArray;
begin
  {"NotAKey" inside a pipe-joined list shouldn't kill the whole row.}
  Path := TPath.Combine(FTempDir, 'garbage.ini');
  Ini := TIniFile.Create(Path);
  try
    Ini.WriteString(HOTKEYS_SECTION, 'PrevFile', 'Left|NotAKey|PageUp');
  finally
    Ini.Free;
  end;

  B := THotkeyBindings.Create;
  try
    Ini := TIniFile.Create(Path);
    try
      B.Load(Ini);
    finally
      Ini.Free;
    end;
    List := B.Get(paPrevFile);
    Assert.AreEqual<Integer>(2, Length(List));
    Assert.AreEqual<Integer>(VK_LEFT, List[0].Key);
    Assert.AreEqual<Integer>(VK_PRIOR, List[1].Key);
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniSave_SingleChord_NoSeparatorInOutput;
var
  B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
begin
  {Regression guard: single-chord actions shouldn't write a trailing '|'.}
  Path := TPath.Combine(FTempDir, 'single.ini');
  B := THotkeyBindings.Create;
  try
    Ini := TIniFile.Create(Path);
    try
      B.Save(Ini);
    finally
      Ini.Free;
    end;

    Ini := TIniFile.Create(Path);
    try
      Assert.AreEqual('F2', Ini.ReadString(HOTKEYS_SECTION, 'Settings', ''));
      Assert.AreEqual('Alt+Enter', Ini.ReadString(HOTKEYS_SECTION, 'ToggleFullScreen', ''));
    finally
      Ini.Free;
    end;
  finally
    B.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHotkeyChord);
  TDUnitX.RegisterTestFixture(TTestChordArrayHelpers);
  TDUnitX.RegisterTestFixture(TTestHotkeyBindings);

end.
