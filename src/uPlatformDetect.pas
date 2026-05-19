{Legacy-Windows detector for sites needing XP/2003 fallback paths.}
unit uPlatformDetect;

interface

{True on NT 5.x and earlier; False on Vista+.}
function IsLegacyWindows: Boolean;

{Connective for "pre-cap (arrow) post-cap" dimensions. XP gets ASCII
 fallback because Tahoma's Arrows-block coverage is patchy.}
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
    {#$2192 escape, not literal: .pas files are UTF-8 without BOM and
     Delphi reads them as ANSI; a literal arrow ends up as three CP-1251
     bytes instead.}
    Result := ' ' + #$2192 + ' ';
end;

end.
