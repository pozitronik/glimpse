{On-screen display formatter for THotkeyChord. Reads VKToName from
 HotkeysCodec; no reverse dependency.}
unit HotkeysDisplay;

interface

uses
  Hotkeys;

function ChordsToDisplayStr(const AChords: THotkeyChordArray): string;

function ChordToDisplayStr(const AChord: THotkeyChord): string;

implementation

uses
  System.Classes,
  HotkeysCodec;

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
