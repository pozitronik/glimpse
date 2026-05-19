{VCL adapter for THotkeyChord — keeps the pure Hotkeys unit free of VCL deps.}
unit HotkeysVcl;

interface

uses
  System.Classes,
  Vcl.Menus,
  Hotkeys;

{Returns 0 for unassigned chords; TMenuItem renders 0 as "no shortcut",
 so callers can assign unconditionally without guarding.}
function ToShortCut(const AChord: THotkeyChord): TShortCut;

implementation

function ToShortCut(const AChord: THotkeyChord): TShortCut;
begin
  if not AChord.IsAssigned then
    Exit(0);
  Result := Vcl.Menus.ShortCut(AChord.Key, AChord.Modifiers);
end;

end.
