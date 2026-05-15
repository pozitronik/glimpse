{Single source of truth for "is this Windows old enough to need a
 fallback path". Used at the few sites where the modern Vista+ behaviour
 (BS_SPLITBUTTON, themed split-button rendering, etc.) silently fails on
 XP / 2003 and we have to wire an alternative.

 Kept deliberately minimal — one inlineable function. If we ever decide
 to also treat Vista as legacy, change the threshold here once.}
unit uPlatformDetect;

interface

{Returns True on Windows XP / Server 2003 (NT 5.x) and earlier. False on
 Vista / Server 2008 and later, where modern comctl32 features are
 reliably available.}
function IsLegacyWindows: Boolean;

{Returns a "X transforms into Y" connective with surrounding spaces baked
 in. Modern Windows gets the typographic right-arrow U+2192; XP falls
 back to ASCII " -> " because Tahoma's Arrows-block coverage is patchy
 across XP service-pack levels and the missing-glyph box is jarring.
 Used by the status-bar predicted-size panel and by the dropdown menu
 captions that show pre-cap -> post-cap dimensions.}
function ResolutionTransformGlyph: string;

implementation

uses
  System.SysUtils;

function IsLegacyWindows: Boolean;
begin
  Result := TOSVersion.Major < 6;
end;

function ResolutionTransformGlyph: string;
begin
  if IsLegacyWindows then
    Result := ' -> '
  else
    {Pascal Unicode escape rather than the literal '→' character: the
     project's .pas files are saved as UTF-8 without BOM, which Delphi
     reads as ANSI, so a literal U+2192 in source ends up as the three
     CP-1251 bytes 0xE2 0x86 0x92 ('†' + ''') instead of an arrow.
     #$2192 is encoding-agnostic and round-trips reliably.}
    Result := ' ' + #$2192 + ' ';
end;

end.
