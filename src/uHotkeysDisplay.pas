{On-screen display formatter for THotkeyChord values.

 Pure-Pascal: the settings dialog listview, the hamburger menu caption
 strip, and any future UI surface read chord text from here. Kept
 separate from the INI codec so a future localised display
 ('Strg+Umschalt+F1' for German UIs) wouldn't churn the INI on-disk
 format that the user's settings depend on.

 Pulls VKToName from uHotkeysCodec so the name table lives in exactly
 one place. uHotkeysCodec deliberately has no reverse dependency on
 this unit — display imports codec, never the other way round.}
unit uHotkeysDisplay;

interface

uses
  uHotkeys;

{Joins AChords with ', ' for on-screen display. Empty chord list renders
 as '' so the listview's Shortcut column is simply blank. Skips
 unassigned chords so a sentinel THotkeyChord.None in the array does
 not produce an empty token between commas.}
function ChordsToDisplayStr(const AChords: THotkeyChordArray): string;

{Converts a single chord to its on-screen display form. Unassigned chord
 renders as ''. Today identical to ChordToIniStr; kept separate so a
 localised display ('Strg+Umschalt+F1' for German UIs) wouldn't churn
 the INI codec.}
function ChordToDisplayStr(const AChord: THotkeyChord): string;

implementation

uses
  System.Classes,
  uHotkeysCodec;

function ChordToDisplayStr(const AChord: THotkeyChord): string;
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
    Result := Result + ChordToDisplayStr(AChords[I]);
  end;
end;

end.
