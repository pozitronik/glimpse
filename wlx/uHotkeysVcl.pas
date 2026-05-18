{VCL adapter for THotkeyChord. uHotkeys advertises itself as pure
 Pascal (no VCL); the chord-to-TShortCut conversion needed for
 TMenuItem.ShortCut wiring lives here so the pure unit stays pure.

 Single consumer today is uPluginForm.PopulateHamburgerMenu, which
 mirrors the user-configured chord onto each menu item.}
unit uHotkeysVcl;

interface

uses
  System.Classes,
  Vcl.Menus,
  uHotkeys;

{Converts AChord to a VCL TShortCut Word suitable for TMenuItem.ShortCut.
 Returns 0 when the chord is unbound, which TMenuItem renders as "no
 shortcut" — so callers can assign unconditionally without guarding.}
function ToShortCut(const AChord: THotkeyChord): TShortCut;

implementation

function ToShortCut(const AChord: THotkeyChord): TShortCut;
begin
  if not AChord.IsAssigned then
    Exit(0);
  Result := Vcl.Menus.ShortCut(AChord.Key, AChord.Modifiers);
end;

end.
