{Configurable-hotkey machinery for the WLX plugin.

 Each plugin action can be bound to any number of chords (a "chord" is a
 VK_* key plus a modifier set). Multiple chords let a single action — say
 "previous file" — be invoked by several shorthand keys at once: Left,
 PageUp, Backspace, Z all navigate backward out of the box.

 Numpad digits and symbol aliases (VK_NUMPAD0..9, VK_ADD, VK_SUBTRACT,
 VK_DECIMAL) are collapsed to their letter-row equivalents at Lookup
 time so a single binding "Zoom reset = 0" matches both top-row 0 and
 numpad 0 without the UI having to show two entries.

 Pure: no VCL, no form references. TestHotkeys covers the record, the
 binding table, and the INI round-trip end-to-end.}
unit uHotkeys;

interface

uses
  System.Classes, System.SysUtils, System.IniFiles;

type
  {Command-style actions the user can assign hotkeys to. Tab (VCL focus
   cycling) is intentionally not listed — it's a system-level shortcut
   that isn't user-configurable.}
  TPluginAction = (paNone,
    {Window / view}
    paSettings, paToggleToolbar, paToggleStatusBar, paToggleTimecode,
    paToggleMaximize, paToggleFullScreen, paHamburgerMenu, paCloseLister,
    {File}
    paPrevFile, paNextFile,
    paOpenInPlayer, paRefreshExtraction, paShuffleExtraction,
    {Frame}
    paPrevFrame, paNextFrame,
    paFrameCountInc, paFrameCountDec,
    {Frame output}
    paSaveFrame, paSaveFrames, paSaveView,
    paSelectAllFrames, paCopyFrame, paCopyView,
    {Zoom}
    paZoomIn, paZoomOut, paZoomReset,
    {View mode}
    paViewModeSmartGrid, paViewModeGrid, paViewModeScroll,
    paViewModeFilmstrip, paViewModeSingle);

  THotkeyChord = record
    Key: Word;               {VK_* code; 0 means unbound}
    Modifiers: TShiftState;  {subset of [ssCtrl, ssShift, ssAlt]}
    function IsAssigned: Boolean;
    function Matches(AKey: Word; AShift: TShiftState): Boolean;
    function Equals(const AOther: THotkeyChord): Boolean;
    function ToDisplayStr: string;
    function ToIniStr: string;
    class function Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord; static;
    class function None: THotkeyChord; static;
    class function FromIniStr(const AValue: string): THotkeyChord; static;
  end;

  THotkeyChordArray = TArray<THotkeyChord>;

  THotkeyBindings = class
  private
    FBindings: array [TPluginAction] of THotkeyChordArray;
  public
    constructor Create;
    {Returns a copy of the chord list for AAction; callers mutate through
     the Put / Add / Remove API rather than editing the returned array.}
    function Get(AAction: TPluginAction): THotkeyChordArray;
    {Replaces the chord list for AAction wholesale. Empty list means unbound.}
    procedure Put(AAction: TPluginAction; const AChords: THotkeyChordArray);
    {Appends AChord to AAction's list if it's not already present (silent
     no-op on duplicate). Returns True when a new chord was actually added.}
    function AddChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
    {Removes the first chord equal to AChord from AAction's list. Returns
     True when a chord was removed.}
    function RemoveChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
    {Scans every action's chord list and returns the first action whose
     chord matches the incoming key + modifiers. Numpad aliases are
     normalised before matching. Returns paNone on no match.}
    function Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
    {Load / Save read and write the [hotkeys] section with '|' as the
     between-chords separator, e.g. PrevFile=Left|PageUp|Backspace|Z.}
    procedure Load(AIni: TIniFile);
    procedure Save(AIni: TIniFile);
    procedure ResetToDefaults;
    {Overwrites every action's chord list with AOther's (deep copy of the
     arrays). Used by the settings dialog to snapshot/restore.}
    procedure Assign(const AOther: THotkeyBindings);
    {First action (other than AExcept) that contains a chord equal to
     AChord. Returns paNone when no conflict.}
    function FindActionByChord(const AChord: THotkeyChord;
      AExcept: TPluginAction = paNone): TPluginAction;
  end;

const
  HOTKEYS_SECTION = 'hotkeys';
  CHORD_SEPARATOR = '|';

{Default chord list (possibly empty) for an action.}
function DefaultBinding(AAction: TPluginAction): THotkeyChordArray;

{Short INI key used to serialise the action (without the 'pa' enum prefix).}
function ActionIniKey(AAction: TPluginAction): string;

{Human-readable caption for the action, used by the settings dialog UI.}
function ActionCaption(AAction: TPluginAction): string;

{Joins AChords with CHORD_SEPARATOR for INI storage.}
function ChordsToIniStr(const AChords: THotkeyChordArray): string;

{Parses AValue (CHORD_SEPARATOR-joined) into a list of chords. Unparseable
 segments are skipped rather than causing the whole value to be rejected.}
function ChordsFromIniStr(const AValue: string): THotkeyChordArray;

{Joins AChords with ', ' for on-screen display. Empty chord list renders
 as '' so the listview's Shortcut column is simply blank.}
function ChordsToDisplayStr(const AChords: THotkeyChordArray): string;

implementation

uses
  Winapi.Windows;

type
  TKeyName = record
    Key: Word;
    Name: string;
  end;

const
  {Fixed named keys. Letter/digit keys are handled separately (single char).}
  KEY_NAMES: array [0 .. 20] of TKeyName = (
    (Key: VK_RETURN; Name: 'Enter'),
    (Key: VK_ESCAPE; Name: 'Escape'),
    (Key: VK_SPACE; Name: 'Space'),
    (Key: VK_TAB; Name: 'Tab'),
    (Key: VK_BACK; Name: 'Backspace'),
    (Key: VK_DELETE; Name: 'Delete'),
    (Key: VK_INSERT; Name: 'Insert'),
    (Key: VK_HOME; Name: 'Home'),
    (Key: VK_END; Name: 'End'),
    (Key: VK_PRIOR; Name: 'PageUp'),
    (Key: VK_NEXT; Name: 'PageDown'),
    (Key: VK_LEFT; Name: 'Left'),
    (Key: VK_RIGHT; Name: 'Right'),
    (Key: VK_UP; Name: 'Up'),
    (Key: VK_DOWN; Name: 'Down'),
    (Key: VK_OEM_PLUS; Name: '+'),
    (Key: VK_OEM_MINUS; Name: '-'),
    (Key: VK_OEM_COMMA; Name: ','),
    (Key: VK_OEM_PERIOD; Name: '.'),
    (Key: VK_OEM_3; Name: '`'),
    (Key: VK_OEM_2; Name: '/'));

function VKToName(AKey: Word): string;
var
  I: Integer;
begin
  if (AKey >= VK_F1) and (AKey <= VK_F12) then
    Exit(Format('F%d', [AKey - VK_F1 + 1]));
  if (AKey >= Ord('0')) and (AKey <= Ord('9')) then
    Exit(Chr(AKey));
  if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
    Exit(Chr(AKey));
  for I := Low(KEY_NAMES) to High(KEY_NAMES) do
    if KEY_NAMES[I].Key = AKey then
      Exit(KEY_NAMES[I].Name);
  Result := '';
end;

function NameToVK(const AName: string): Word;
var
  S: string;
  I, N: Integer;
begin
  S := AName.Trim;
  if S = '' then
    Exit(0);
  if (Length(S) >= 2) and ((S[1] = 'F') or (S[1] = 'f')) then
  begin
    if TryStrToInt(Copy(S, 2, Length(S) - 1), N) and (N >= 1) and (N <= 12) then
      Exit(VK_F1 + N - 1);
  end;
  if Length(S) = 1 then
  begin
    if CharInSet(S[1], ['0' .. '9']) then
      Exit(Ord(S[1]));
    if CharInSet(S[1], ['A' .. 'Z', 'a' .. 'z']) then
      Exit(Ord(UpCase(S[1])));
  end;
  for I := Low(KEY_NAMES) to High(KEY_NAMES) do
    if SameText(KEY_NAMES[I].Name, S) then
      Exit(KEY_NAMES[I].Key);
  Result := 0;
end;

function NormalizeKey(AKey: Word): Word;
begin
  case AKey of
    VK_NUMPAD0 .. VK_NUMPAD9:
      Result := AKey - VK_NUMPAD0 + Ord('0');
    VK_ADD:
      Result := VK_OEM_PLUS;
    VK_SUBTRACT:
      Result := VK_OEM_MINUS;
    VK_DECIMAL:
      Result := VK_OEM_PERIOD;
  else
    Result := AKey;
  end;
end;

function NormalizeShift(const AShift: TShiftState): TShiftState;
begin
  Result := AShift * [ssShift, ssAlt, ssCtrl];
end;

{THotkeyChord}

function THotkeyChord.IsAssigned: Boolean;
begin
  Result := Key <> 0;
end;

function THotkeyChord.Matches(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := IsAssigned and (Key = AKey) and (Modifiers = AShift);
end;

function THotkeyChord.Equals(const AOther: THotkeyChord): Boolean;
begin
  Result := (Key = AOther.Key) and (Modifiers = AOther.Modifiers);
end;

function THotkeyChord.ToDisplayStr: string;
var
  KeyName: string;
begin
  if not IsAssigned then
    Exit('');
  KeyName := VKToName(Key);
  if KeyName = '' then
    Exit('');
  Result := '';
  if ssCtrl in Modifiers then
    Result := Result + 'Ctrl+';
  if ssShift in Modifiers then
    Result := Result + 'Shift+';
  if ssAlt in Modifiers then
    Result := Result + 'Alt+';
  Result := Result + KeyName;
end;

function THotkeyChord.ToIniStr: string;
begin
  Result := ToDisplayStr;
end;

class function THotkeyChord.Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord;
begin
  {Normalise at construction so numpad/OEM aliases captured from the shortcut
   editor round-trip through INI. Without this, VK_NUMPAD0..9 and VK_ADD /
   VK_SUBTRACT / VK_DECIMAL would hit VKToName as unknown and serialise empty.}
  Result.Key := NormalizeKey(AKey);
  Result.Modifiers := NormalizeShift(AModifiers);
end;

class function THotkeyChord.None: THotkeyChord;
begin
  Result.Key := 0;
  Result.Modifiers := [];
end;

class function THotkeyChord.FromIniStr(const AValue: string): THotkeyChord;
var
  Parts: TArray<string>;
  I: Integer;
  Token, Body: string;
  Mods: TShiftState;
  KeyCode: Word;
begin
  Result := None;
  Body := AValue.Trim;
  if Body = '' then
    Exit;
  KeyCode := 0;
  {OEM '+' key paired with modifiers serialises as 'Shift++' / 'Ctrl++' /
   'Alt++'. Splitting on '+' would yield two empty trailing tokens and the
   chord would silently disappear on round-trip. Strip the '++' tail here so
   the modifier prefix can be parsed normally. Single trailing '+' without a
   preceding one (e.g. 'Ctrl+') is still a broken input that returns None.}
  if (Length(Body) >= 2)
    and (Body[Length(Body)] = '+')
    and (Body[Length(Body) - 1] = '+') then
  begin
    KeyCode := VK_OEM_PLUS;
    Body := Copy(Body, 1, Length(Body) - 2);
  end;
  Parts := Body.Split(['+']);
  Mods := [];
  for I := 0 to High(Parts) do
  begin
    Token := Parts[I].Trim;
    if SameText(Token, 'Ctrl') then
      Include(Mods, ssCtrl)
    else if SameText(Token, 'Shift') then
      Include(Mods, ssShift)
    else if SameText(Token, 'Alt') then
      Include(Mods, ssAlt)
    else if (Token <> '') and (KeyCode = 0) then
      KeyCode := NameToVK(Token);
  end;
  {Bare '+' gets split into two empty tokens; recover it from the raw input.}
  if (KeyCode = 0) and (AValue.Trim = '+') then
    KeyCode := VK_OEM_PLUS;
  if KeyCode = 0 then
    Exit;
  Result.Key := KeyCode;
  Result.Modifiers := Mods;
end;

{THotkeyBindings}

constructor THotkeyBindings.Create;
begin
  inherited;
  ResetToDefaults;
end;

function THotkeyBindings.Get(AAction: TPluginAction): THotkeyChordArray;
var
  I: Integer;
begin
  SetLength(Result, Length(FBindings[AAction]));
  for I := 0 to High(FBindings[AAction]) do
    Result[I] := FBindings[AAction][I];
end;

procedure THotkeyBindings.Put(AAction: TPluginAction; const AChords: THotkeyChordArray);
var
  I: Integer;
begin
  SetLength(FBindings[AAction], Length(AChords));
  for I := 0 to High(AChords) do
    FBindings[AAction][I] := AChords[I];
end;

function THotkeyBindings.AddChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
var
  I, N: Integer;
begin
  if not AChord.IsAssigned then
    Exit(False);
  for I := 0 to High(FBindings[AAction]) do
    if FBindings[AAction][I].Equals(AChord) then
      Exit(False);
  N := Length(FBindings[AAction]);
  SetLength(FBindings[AAction], N + 1);
  FBindings[AAction][N] := AChord;
  Result := True;
end;

function THotkeyBindings.RemoveChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  for I := 0 to High(FBindings[AAction]) do
    if FBindings[AAction][I].Equals(AChord) then
    begin
      for J := I to High(FBindings[AAction]) - 1 do
        FBindings[AAction][J] := FBindings[AAction][J + 1];
      SetLength(FBindings[AAction], Length(FBindings[AAction]) - 1);
      Exit(True);
    end;
end;

function THotkeyBindings.Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
var
  NormKey: Word;
  NormShift: TShiftState;
  A: TPluginAction;
  I: Integer;
begin
  NormKey := NormalizeKey(AKey);
  NormShift := NormalizeShift(AShift);
  for A := Succ(paNone) to High(TPluginAction) do
    for I := 0 to High(FBindings[A]) do
      if FBindings[A][I].Matches(NormKey, NormShift) then
        Exit(A);
  Result := paNone;
end;

procedure THotkeyBindings.Load(AIni: TIniFile);
var
  A: TPluginAction;
  Raw: string;
begin
  {Start from defaults so any key missing from the INI retains its default
   binding rather than becoming unbound. Users can explicitly disable a
   default by writing an empty value (e.g. "Settings=").}
  ResetToDefaults;
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    if not AIni.ValueExists(HOTKEYS_SECTION, ActionIniKey(A)) then
      Continue;
    Raw := AIni.ReadString(HOTKEYS_SECTION, ActionIniKey(A), '');
    if Raw.Trim = '' then
      FBindings[A] := nil
    else
      FBindings[A] := ChordsFromIniStr(Raw);
  end;
end;

procedure THotkeyBindings.Save(AIni: TIniFile);
var
  A: TPluginAction;
begin
  for A := Succ(paNone) to High(TPluginAction) do
    AIni.WriteString(HOTKEYS_SECTION, ActionIniKey(A), ChordsToIniStr(FBindings[A]));
end;

procedure THotkeyBindings.ResetToDefaults;
var
  A: TPluginAction;
begin
  for A := Low(TPluginAction) to High(TPluginAction) do
    FBindings[A] := DefaultBinding(A);
end;

procedure THotkeyBindings.Assign(const AOther: THotkeyBindings);
var
  A: TPluginAction;
  I: Integer;
begin
  if AOther = nil then
    Exit;
  for A := Low(TPluginAction) to High(TPluginAction) do
  begin
    SetLength(FBindings[A], Length(AOther.FBindings[A]));
    for I := 0 to High(AOther.FBindings[A]) do
      FBindings[A][I] := AOther.FBindings[A][I];
  end;
end;

function THotkeyBindings.FindActionByChord(const AChord: THotkeyChord;
  AExcept: TPluginAction): TPluginAction;
var
  A: TPluginAction;
  I: Integer;
begin
  if not AChord.IsAssigned then
    Exit(paNone);
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    if A = AExcept then
      Continue;
    for I := 0 to High(FBindings[A]) do
      if FBindings[A][I].Equals(AChord) then
        Exit(A);
  end;
  Result := paNone;
end;

{Unit-level helpers}

function DefaultBinding(AAction: TPluginAction): THotkeyChordArray;
begin
  case AAction of
    paSettings:
      Result := [THotkeyChord.Make(VK_F2, [])];
    paToggleToolbar:
      Result := [THotkeyChord.Make(VK_F4, [])];
    paToggleStatusBar:
      Result := [THotkeyChord.Make(VK_F3, [])];
    paToggleTimecode:
      Result := [THotkeyChord.Make(Ord('T'), [])];
    paToggleMaximize:
      Result := [THotkeyChord.Make(VK_F11, [])];
    paToggleFullScreen:
      Result := [THotkeyChord.Make(VK_RETURN, [ssAlt])];
    paHamburgerMenu:
      Result := [THotkeyChord.Make(VK_OEM_3, [])];
    paCloseLister:
      Result := [THotkeyChord.Make(VK_ESCAPE, [])];
    paPrevFile:
      Result := [THotkeyChord.Make(VK_PRIOR, []),
                 THotkeyChord.Make(VK_BACK, []),
                 THotkeyChord.Make(Ord('Z'), [])];
    paNextFile:
      Result := [THotkeyChord.Make(VK_NEXT, []),
                 THotkeyChord.Make(VK_SPACE, [])];
    paOpenInPlayer:
      Result := [THotkeyChord.Make(VK_RETURN, [])];
    paRefreshExtraction:
      Result := [THotkeyChord.Make(Ord('R'), [])];
    paShuffleExtraction:
      Result := [THotkeyChord.Make(Ord('R'), [ssCtrl])];
    {Bare Left/Right bind to frame navigation so the single-view "slideshow"
     feel is the default. paPrevFrame/paNextFrame have a vmSingle guard in
     the dispatcher — in other modes the action's ExecuteHotkey returns
     False and the keystroke quietly does nothing (matching "no natural
     arrow action in grid"). Ctrl+Left/Ctrl+Right are kept as a
     modifier-qualified alias.}
    paPrevFrame:
      Result := [THotkeyChord.Make(VK_LEFT, []),
                 THotkeyChord.Make(VK_LEFT, [ssCtrl])];
    paNextFrame:
      Result := [THotkeyChord.Make(VK_RIGHT, []),
                 THotkeyChord.Make(VK_RIGHT, [ssCtrl])];
    paFrameCountInc:
      Result := [THotkeyChord.Make(VK_UP, [ssCtrl])];
    paFrameCountDec:
      Result := [THotkeyChord.Make(VK_DOWN, [ssCtrl])];
    paSaveFrame:
      Result := [THotkeyChord.Make(Ord('S'), [ssCtrl])];
    paSaveView:
      Result := [THotkeyChord.Make(Ord('S'), [ssCtrl, ssShift])];
    paSaveFrames:
      Result := [THotkeyChord.Make(Ord('S'), [ssCtrl, ssAlt, ssShift])];
    paSelectAllFrames:
      Result := [THotkeyChord.Make(Ord('A'), [ssCtrl])];
    paCopyFrame:
      Result := [THotkeyChord.Make(Ord('C'), [ssCtrl])];
    paCopyView:
      Result := [THotkeyChord.Make(Ord('C'), [ssCtrl, ssShift])];
    paZoomIn:
      Result := [THotkeyChord.Make(VK_OEM_PLUS, [])];
    paZoomOut:
      Result := [THotkeyChord.Make(VK_OEM_MINUS, [])];
    paZoomReset:
      Result := [THotkeyChord.Make(Ord('0'), [])];
    paViewModeSmartGrid:
      Result := [THotkeyChord.Make(Ord('1'), [ssCtrl])];
    paViewModeGrid:
      Result := [THotkeyChord.Make(Ord('2'), [ssCtrl])];
    paViewModeScroll:
      Result := [THotkeyChord.Make(Ord('3'), [ssCtrl])];
    paViewModeFilmstrip:
      Result := [THotkeyChord.Make(Ord('4'), [ssCtrl])];
    paViewModeSingle:
      Result := [THotkeyChord.Make(Ord('5'), [ssCtrl])];
  else
    Result := nil;
  end;
end;

function ActionIniKey(AAction: TPluginAction): string;
begin
  case AAction of
    paSettings: Result := 'Settings';
    paToggleToolbar: Result := 'ToggleToolbar';
    paToggleStatusBar: Result := 'ToggleStatusBar';
    paToggleTimecode: Result := 'ToggleTimecode';
    paToggleMaximize: Result := 'ToggleMaximize';
    paToggleFullScreen: Result := 'ToggleFullScreen';
    paHamburgerMenu: Result := 'HamburgerMenu';
    paCloseLister: Result := 'CloseLister';
    paPrevFile: Result := 'PrevFile';
    paNextFile: Result := 'NextFile';
    paOpenInPlayer: Result := 'OpenInPlayer';
    paRefreshExtraction: Result := 'RefreshExtraction';
    paShuffleExtraction: Result := 'ShuffleExtraction';
    paPrevFrame: Result := 'PrevFrame';
    paNextFrame: Result := 'NextFrame';
    paFrameCountInc: Result := 'FrameCountInc';
    paFrameCountDec: Result := 'FrameCountDec';
    paSaveFrame: Result := 'SaveFrame';
    paSaveFrames: Result := 'SaveFrames';
    paSaveView: Result := 'SaveView';
    paSelectAllFrames: Result := 'SelectAllFrames';
    paCopyFrame: Result := 'CopyFrame';
    paCopyView: Result := 'CopyView';
    paZoomIn: Result := 'ZoomIn';
    paZoomOut: Result := 'ZoomOut';
    paZoomReset: Result := 'ZoomReset';
    paViewModeSmartGrid: Result := 'ViewModeSmartGrid';
    paViewModeGrid: Result := 'ViewModeGrid';
    paViewModeScroll: Result := 'ViewModeScroll';
    paViewModeFilmstrip: Result := 'ViewModeFilmstrip';
    paViewModeSingle: Result := 'ViewModeSingle';
  else
    Result := '';
  end;
end;

function ActionCaption(AAction: TPluginAction): string;
begin
  case AAction of
    paSettings: Result := 'Settings';
    paToggleToolbar: Result := 'Toggle toolbar';
    paToggleStatusBar: Result := 'Toggle statusbar';
    paToggleTimecode: Result := 'Toggle timecode overlay';
    paToggleMaximize: Result := 'Toggle maximize';
    paToggleFullScreen: Result := 'Toggle full-screen';
    paHamburgerMenu: Result := 'Open hamburger menu';
    paCloseLister: Result := 'Close viewer';
    paPrevFile: Result := 'Previous file';
    paNextFile: Result := 'Next file';
    paOpenInPlayer: Result := 'Open in default player';
    paRefreshExtraction: Result := 'Refresh frames';
    paShuffleExtraction: Result := 'Shuffle frames (random positions)';
    paPrevFrame: Result := 'Previous frame (single view)';
    paNextFrame: Result := 'Next frame (single view)';
    paFrameCountInc: Result := 'Increase frame count';
    paFrameCountDec: Result := 'Decrease frame count';
    paSaveFrame: Result := 'Save frame';
    paSaveFrames: Result := 'Save frames';
    paSaveView: Result := 'Save view';
    paSelectAllFrames: Result := 'Select all frames';
    paCopyFrame: Result := 'Copy frame to clipboard';
    paCopyView: Result := 'Copy view to clipboard';
    paZoomIn: Result := 'Zoom in';
    paZoomOut: Result := 'Zoom out';
    paZoomReset: Result := 'Reset zoom';
    paViewModeSmartGrid: Result := 'View mode: Smart grid';
    paViewModeGrid: Result := 'View mode: Grid';
    paViewModeScroll: Result := 'View mode: Scroll';
    paViewModeFilmstrip: Result := 'View mode: Filmstrip';
    paViewModeSingle: Result := 'View mode: Single frame';
  else
    Result := '';
  end;
end;

function ChordsToIniStr(const AChords: THotkeyChordArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AChords) do
  begin
    if not AChords[I].IsAssigned then
      Continue;
    if Result <> '' then
      Result := Result + CHORD_SEPARATOR;
    Result := Result + AChords[I].ToIniStr;
  end;
end;

function ChordsFromIniStr(const AValue: string): THotkeyChordArray;
var
  Parts: TArray<string>;
  I, Count: Integer;
  Parsed: THotkeyChord;
begin
  Result := nil;
  if AValue.Trim = '' then
    Exit;
  Parts := AValue.Split([CHORD_SEPARATOR]);
  SetLength(Result, Length(Parts));
  Count := 0;
  for I := 0 to High(Parts) do
  begin
    Parsed := THotkeyChord.FromIniStr(Parts[I]);
    if Parsed.IsAssigned then
    begin
      Result[Count] := Parsed;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function ChordsToDisplayStr(const AChords: THotkeyChordArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AChords) do
  begin
    if not AChords[I].IsAssigned then
      Continue;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + AChords[I].ToDisplayStr;
  end;
end;

end.
