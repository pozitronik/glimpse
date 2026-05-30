{Clipboard temp-file cleanup policy: the leftover-sweep strategy enum, its
 INI serializers, the seconds<->days/hours/minutes split the dialog's spin
 fields use, and the pure per-file sweep decision. No filesystem or VCL here
 so the decision stays unit-testable; the actual enumeration/deletion lives
 in ClipboardTempSweeper.}
unit ClipboardTemp;

interface

uses
  System.SysUtils;

type
  {How the plugin-load sweep treats leftover glimpse_clip_*.png files.
   ccsAll == "delete older than 0"; both modes share one age-parameterised
   sweep. Order is load-bearing: serialised by token name via
   ClipboardCleanupStrategyToStr, and the settings combo's ItemIndex matches
   Ord(enum). Reordering would silently pick the wrong strategy on next load.}
  TClipboardCleanupStrategy = (ccsNone, ccsAll, ccsOlderThan);

function StrToClipboardCleanupStrategy(const AValue: string;
  ADefault: TClipboardCleanupStrategy): TClipboardCleanupStrategy;
function ClipboardCleanupStrategyToStr(AStrategy: TClipboardCleanupStrategy): string;

{Splits a second count into whole days / hours / minutes for the dialog's
 three spin fields. Sub-minute remainders are dropped; negative input clamps
 to zero. 86400 -> (1, 0, 0).}
procedure SplitSecondsToDHM(ASeconds: Integer; out ADays, AHours, AMinutes: Integer);

{Composes days / hours / minutes back into seconds. Negative components clamp
 to zero. Inverse of SplitSecondsToDHM for in-range minute-granular values.}
function DHMToSeconds(ADays, AHours, AMinutes: Integer): Integer;

{Decides whether one leftover temp file should be swept. AAgeSeconds is
 now-minus-file-mtime. AMinAgeFloorSeconds protects a file a sibling TC
 instance may still be writing (or has just published but not yet pasted):
 anything younger than the floor is never swept, under any active strategy.
 The currently-clipboard-referenced file is excluded by the caller, not here.}
function ShouldSweepClipboardTemp(AStrategy: TClipboardCleanupStrategy;
  AAgeSeconds, AThresholdSeconds, AMinAgeFloorSeconds: Integer): Boolean;

const
  SECONDS_PER_MINUTE = 60;
  SECONDS_PER_HOUR = 3600;
  SECONDS_PER_DAY = 86400;

  {Single source of truth for the file-reference temp name shared by the
   publisher (which writes) and the sweeper (which enumerates). The GUID
   between prefix and extension keeps concurrent lister windows from
   colliding.}
  CLIPBOARD_TEMP_PREFIX = 'glimpse_clip_';
  CLIPBOARD_TEMP_EXT = '.png';
  CLIPBOARD_TEMP_PATTERN = 'glimpse_clip_*.png';

  {Files younger than this are never swept, even under "clean everything",
   so a sweep can not race a sibling instance that has just written (or
   published but not yet pasted) a temp file.}
  MIN_SWEEP_AGE_FLOOR_SECONDS = 120;

implementation

function StrToClipboardCleanupStrategy(const AValue: string;
  ADefault: TClipboardCleanupStrategy): TClipboardCleanupStrategy;
begin
  if SameText(AValue, 'none') then
    Result := ccsNone
  else if SameText(AValue, 'all') then
    Result := ccsAll
  else if SameText(AValue, 'olderthan') then
    Result := ccsOlderThan
  else
    Result := ADefault;
end;

function ClipboardCleanupStrategyToStr(AStrategy: TClipboardCleanupStrategy): string;
begin
  case AStrategy of
    ccsNone:      Result := 'none';
    ccsAll:       Result := 'all';
    ccsOlderThan: Result := 'olderthan';
  end;
end;

procedure SplitSecondsToDHM(ASeconds: Integer; out ADays, AHours, AMinutes: Integer);
begin
  if ASeconds < 0 then
    ASeconds := 0;
  ADays := ASeconds div SECONDS_PER_DAY;
  AHours := (ASeconds mod SECONDS_PER_DAY) div SECONDS_PER_HOUR;
  AMinutes := (ASeconds mod SECONDS_PER_HOUR) div SECONDS_PER_MINUTE;
end;

function DHMToSeconds(ADays, AHours, AMinutes: Integer): Integer;
begin
  if ADays < 0 then
    ADays := 0;
  if AHours < 0 then
    AHours := 0;
  if AMinutes < 0 then
    AMinutes := 0;
  Result := ADays * SECONDS_PER_DAY + AHours * SECONDS_PER_HOUR + AMinutes * SECONDS_PER_MINUTE;
end;

function ShouldSweepClipboardTemp(AStrategy: TClipboardCleanupStrategy;
  AAgeSeconds, AThresholdSeconds, AMinAgeFloorSeconds: Integer): Boolean;
begin
  Result := False;
  if AStrategy = ccsNone then
    Exit;
  {Floor wins over the strategy threshold: even "clean everything" must not
   race a concurrent instance's just-written file.}
  if AAgeSeconds < AMinAgeFloorSeconds then
    Exit;
  case AStrategy of
    ccsAll:
      Result := True;
    ccsOlderThan:
      Result := AAgeSeconds > AThresholdSeconds;
  end;
end;

end.
