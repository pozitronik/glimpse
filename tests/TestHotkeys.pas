{Unit tests for uHotkeys: chord parse/serialise round-trip, defaults
 integrity, lookup with alias normalisation, INI load/save.}
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
    [Test] procedure RoundTrip_EveryDefaultBinding;
  end;

  [TestFixture]
  TTestHotkeyBindings = class
  private
    FTempDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Defaults_NoneForAllUnspecified;
    [Test] procedure Defaults_EveryActionHasExpected;
    [Test] procedure Lookup_Defaults_Resolve;
    [Test] procedure Lookup_Numpad0_ResolvesAsDigit0;
    [Test] procedure Lookup_NumpadAdd_ResolvesAsOemPlus;
    [Test] procedure Lookup_NumpadSubtract_ResolvesAsOemMinus;
    [Test] procedure Lookup_Unknown_ReturnsNone;
    [Test] procedure Lookup_IgnoresNonStandardModifiers;
    [Test] procedure Put_Lookup_SeesNewBinding;
    [Test] procedure ResetToDefaults_ReplacesCustomBindings;
    [Test] procedure IniRoundTrip_CustomBindingsPreserved;
    [Test] procedure IniLoad_EmptyValue_Unbinds;
    [Test] procedure IniLoad_MissingKey_KeepsDefault;
    [Test] procedure IniLoad_UnparseableValue_KeepsDefault;
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
  Assert.IsFalse(THotkeyChord.FromIniStr('Ctrl+Alt').IsAssigned,
    'Modifiers without a key must not parse');
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
  {The '+' character is the delimiter; parsing the single-char key '+' must
   still recover it so the serialisation round-trips.}
  C := THotkeyChord.FromIniStr('+');
  Assert.IsTrue(C.IsAssigned);
  Assert.AreEqual<Integer>(VK_OEM_PLUS, C.Key);
end;

procedure TTestHotkeyChord.RoundTrip_EveryDefaultBinding;
var
  A: TPluginAction;
  Orig, Parsed: THotkeyChord;
begin
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    Orig := DefaultBinding(A);
    if not Orig.IsAssigned then
      Continue;
    Parsed := THotkeyChord.FromIniStr(Orig.ToIniStr);
    Assert.IsTrue(Parsed.IsAssigned,
      Format('Default for %s failed to parse: %s', [ActionIniKey(A), Orig.ToIniStr]));
    Assert.AreEqual<Integer>(Orig.Key, Parsed.Key,
      Format('Key mismatch for %s', [ActionIniKey(A)]));
    Assert.IsTrue(Orig.Modifiers = Parsed.Modifiers,
      Format('Modifier mismatch for %s', [ActionIniKey(A)]));
  end;
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

procedure TTestHotkeyBindings.Defaults_NoneForAllUnspecified;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    {paNone is the sentinel and never has a chord.}
    Assert.IsFalse(B.Get(paNone).IsAssigned);
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Defaults_EveryActionHasExpected;
var
  B: THotkeyBindings;
  C: THotkeyChord;
begin
  B := THotkeyBindings.Create;
  try
    C := B.Get(paSettings);
    Assert.IsTrue(C.IsAssigned);
    Assert.AreEqual<Integer>(VK_F2, C.Key);

    C := B.Get(paToggleFullScreen);
    Assert.AreEqual<Integer>(VK_RETURN, C.Key);
    Assert.IsTrue(C.Modifiers = [ssAlt]);

    C := B.Get(paOpenInPlayer);
    Assert.AreEqual<Integer>(VK_RETURN, C.Key);
    Assert.IsTrue(C.Modifiers = []);

    C := B.Get(paSaveSelected);
    Assert.IsFalse(C.IsAssigned, 'paSaveSelected ships unbound by design');
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
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_Numpad0_ResolvesAsDigit0;
var
  B: THotkeyBindings;
begin
  {Numpad digit normalisation: pressing numpad 0 must resolve the same
   binding as top-row 0, so the user gets one logical entry for Zoom reset.}
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
    {A random VK that no default maps to, with no modifiers.}
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F24, [])));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F2, [ssCtrl])),
      'F2 is bare-only; Ctrl+F2 must not match paSettings');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Lookup_IgnoresNonStandardModifiers;
var
  B: THotkeyBindings;
begin
  {Some hosts deliver TShiftState including mouse buttons. Lookup must
   only consider ssCtrl/ssShift/ssAlt.}
  B := THotkeyBindings.Create;
  try
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F2, [ssLeft])),
      'Mouse flags in the shift set must not block a keyboard-only match');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.Put_Lookup_SeesNewBinding;
var
  B: THotkeyBindings;
begin
  B := THotkeyBindings.Create;
  try
    B.Put(paSaveSelected, THotkeyChord.Make(VK_F9, [ssCtrl]));
    Assert.AreEqual(Ord(paSaveSelected), Ord(B.Lookup(VK_F9, [ssCtrl])));
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
    B.Put(paSettings, THotkeyChord.Make(VK_F9, []));
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F9, [])));
    B.ResetToDefaults;
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F2, [])),
      'After reset, F2 must resolve to paSettings again');
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F9, [])),
      'After reset, the custom F9 binding must be gone');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniRoundTrip_CustomBindingsPreserved;
var
  A, B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
begin
  Path := TPath.Combine(FTempDir, 'hotkeys.ini');
  A := THotkeyBindings.Create;
  try
    A.Put(paSaveSelected, THotkeyChord.Make(VK_F9, [ssCtrl, ssShift]));
    A.Put(paSettings, THotkeyChord.Make(VK_F12, []));
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
    Assert.AreEqual(Ord(paSaveSelected), Ord(B.Lookup(VK_F9, [ssCtrl, ssShift])));
    Assert.AreEqual(Ord(paSettings), Ord(B.Lookup(VK_F12, [])));
    Assert.AreEqual(Ord(paNone), Ord(B.Lookup(VK_F2, [])),
      'The default F2 binding was overwritten in memory and on disk');
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
  {An empty value is the user's explicit way to disable a default hotkey
   without deleting the line. It must unbind, not fall back to the default.}
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
    Assert.IsFalse(B.Get(paSettings).IsAssigned,
      'Empty string in INI should unbind, not restore default');
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
begin
  {An INI file that omits an action should leave that action at its
   default. Only explicit empty strings unbind.}
  Path := TPath.Combine(FTempDir, 'missing.ini');
  Ini := TIniFile.Create(Path);
  try
    Ini.WriteString(HOTKEYS_SECTION, 'Settings', 'F9');
    {Deliberately do not write anything for ToggleToolbar}
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
    Assert.AreEqual<Integer>(VK_F9, B.Get(paSettings).Key);
    Assert.AreEqual<Integer>(VK_F4, B.Get(paToggleToolbar).Key,
      'ToggleToolbar had no INI entry and must keep its F4 default');
  finally
    B.Free;
  end;
end;

procedure TTestHotkeyBindings.IniLoad_UnparseableValue_KeepsDefault;
var
  B: THotkeyBindings;
  Ini: TIniFile;
  Path: string;
begin
  {Garbage values should be treated as "couldn't decide" and keep the
   default, not unbind silently. Typos shouldn't disable features.}
  Path := TPath.Combine(FTempDir, 'garbage.ini');
  Ini := TIniFile.Create(Path);
  try
    Ini.WriteString(HOTKEYS_SECTION, 'Settings', 'Ctrl+NotAKey');
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
    Assert.AreEqual<Integer>(VK_F2, B.Get(paSettings).Key);
  finally
    B.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHotkeyChord);
  TDUnitX.RegisterTestFixture(TTestHotkeyBindings);

end.
