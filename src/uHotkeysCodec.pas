{INI codec for THotkeyChord values.

 Pure-Pascal serialiser/deserialiser pair separated out of uHotkeys so the
 core value type and its mutable binding collection don't carry the parser
 table or the VKToName / NameToVK helpers. The display formatter
 (uHotkeysDisplay) imports this unit for VKToName — VKToName / NameToVK
 are intentionally public here so the display path doesn't need a
 duplicate copy.

 Future-proofing: the chord-level functions (ChordToIniStr /
 ChordFromIniStr) are kept separate from the display equivalents even
 though they produce identical output today. A localised display string
 ('Strg+Umschalt+F1' for German UIs) would diverge from the INI form,
 and keeping the two formatters on independent code paths avoids that
 future change rippling through the codec.}
unit uHotkeysCodec;

interface

uses
  uHotkeys;

{Maps a VK_* code to the textual token used in INI / display strings.
 Returns '' for keys outside the curated set; callers treat that as
 "this chord has no representation" and skip rendering.}
function VKToName(AKey: Word): string;

{Inverse of VKToName: reads a token (case-insensitive, trimmed) and
 returns the VK_* code, or 0 when the token does not match any known
 key. Letter/digit one-char tokens are converted directly.}
function NameToVK(const AName: string): Word;

{Joins AChords with CHORD_SEPARATOR ('|') for INI storage. Empty chord
 list renders as ''. Skips unassigned chords so a sentinel
 THotkeyChord.None in the array does not produce an empty segment like
 'F2||F3' that would round-trip asymmetrically.}
function ChordsToIniStr(const AChords: THotkeyChordArray): string;

{Parses AValue ('|'-joined) into a list of chords. Unparseable segments
 are skipped rather than rejecting the whole value — partial-parse
 tolerance survives a hand-edited INI with one typo.}
function ChordsFromIniStr(const AValue: string): THotkeyChordArray;

{Converts a single chord to its INI form ('Ctrl+Shift+F1', 'F2', '+',
 ...). Unassigned chord renders as ''. Equivalent today to the chord's
 display string but kept on its own function so a future INI-vs-display
 divergence (e.g. localised display) doesn't churn the codec.}
function ChordToIniStr(const AChord: THotkeyChord): string;

{Parses a single INI-form chord. Returns THotkeyChord.None on empty or
 unparseable input. Order of modifier tokens does not matter; the
 'Shift++' / 'Ctrl++' / 'Alt++' tail trick recovers the OEM '+' key
 paired with a modifier.}
function ChordFromIniStr(const AValue: string): THotkeyChord;

implementation

uses
  System.Classes, System.SysUtils,
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

function ChordToIniStr(const AChord: THotkeyChord): string;
var
  KeyName: string;
begin
  if not AChord.IsAssigned then
    Exit('');
  KeyName := VKToName(AChord.Key);
  if KeyName = '' then
    Exit('');
  Result := '';
  if ssCtrl in AChord.Modifiers then
    Result := Result + 'Ctrl+';
  if ssShift in AChord.Modifiers then
    Result := Result + 'Shift+';
  if ssAlt in AChord.Modifiers then
    Result := Result + 'Alt+';
  Result := Result + KeyName;
end;

function ChordFromIniStr(const AValue: string): THotkeyChord;
var
  Parts: TArray<string>;
  I: Integer;
  Token, Body: string;
  Mods: TShiftState;
  KeyCode: Word;
begin
  Result := THotkeyChord.None;
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
    Result := Result + ChordToIniStr(AChords[I]);
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
    Parsed := ChordFromIniStr(Parts[I]);
    if Parsed.IsAssigned then
    begin
      Result[Count] := Parsed;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

end.
