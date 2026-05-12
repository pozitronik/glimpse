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

implementation

uses
  System.SysUtils;

function IsLegacyWindows: Boolean;
begin
  Result := TOSVersion.Major < 6;
end;

end.
