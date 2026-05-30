{Plugin-load sweep of leftover clipboard file-reference temp PNGs. The pure
 per-file decision lives in ClipboardTemp.ShouldSweepClipboardTemp; this unit
 supplies the filesystem enumeration plus the two cross-instance safety guards
 (skip the clipboard-referenced file; honour the min-age floor) and never
 raises so a bad folder can not crash the host.}
unit ClipboardTempSweeper;

interface

uses
  ClipboardTemp;

{Sweeps glimpse_clip_*.png in AFolder per AStrategy. ANow is injected so age
 is deterministic in tests; AProtectedPath (the file currently on the
 clipboard, or '') is never deleted regardless of age. Returns the count
 deleted. Per-file delete failures (file locked by a paste in progress) are
 swallowed and logged. Never raises.}
function SweepClipboardTempFolder(const AFolder: string;
  AStrategy: TClipboardCleanupStrategy;
  AThresholdSeconds, AMinAgeFloorSeconds: Integer;
  const AProtectedPath: string; ANow: TDateTime): Integer;

{Production entry: reads the clipboard-protected path, stamps "now", and
 sweeps with MIN_SWEEP_AGE_FLOOR_SECONDS. Safe to call on plugin load.}
procedure RunClipboardTempSweep(const AFolder: string;
  AStrategy: TClipboardCleanupStrategy; AThresholdSeconds: Integer);

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  ClipboardFileDrop, Logging;

function SweepClipboardTempFolder(const AFolder: string;
  AStrategy: TClipboardCleanupStrategy;
  AThresholdSeconds, AMinAgeFloorSeconds: Integer;
  const AProtectedPath: string; ANow: TDateTime): Integer;
var
  Files: TArray<string>;
  F, ProtectedFull: string;
  MTime: TDateTime;
  AgeSeconds: Integer;
begin
  Result := 0;
  if AStrategy = ccsNone then
    Exit;
  if not TDirectory.Exists(AFolder) then
    Exit;

  if AProtectedPath <> '' then
    ProtectedFull := TPath.GetFullPath(AProtectedPath)
  else
    ProtectedFull := '';

  try
    Files := TDirectory.GetFiles(AFolder, CLIPBOARD_TEMP_PATTERN,
      TSearchOption.soTopDirectoryOnly);
  except
    {Unreadable directory — nothing to sweep.}
    Exit;
  end;

  for F in Files do
  begin
    if (ProtectedFull <> '') and SameText(TPath.GetFullPath(F), ProtectedFull) then
      Continue;
    try
      MTime := TFile.GetLastWriteTime(F);
    except
      {Stat failed (e.g. file vanished mid-sweep) — skip.}
      Continue;
    end;
    {A future mtime (clock skew) collapses to age 0, which the floor then
     protects from deletion.}
    if MTime > ANow then
      AgeSeconds := 0
    else
      AgeSeconds := SecondsBetween(ANow, MTime);
    if not ShouldSweepClipboardTemp(AStrategy, AgeSeconds, AThresholdSeconds,
      AMinAgeFloorSeconds) then
      Continue;
    try
      TFile.Delete(F);
      Inc(Result);
    except
      on E: Exception do
        DebugLog('Clipboard', Format('Sweep: could not delete "%s": %s', [F, E.Message]));
    end;
  end;
end;

procedure RunClipboardTempSweep(const AFolder: string;
  AStrategy: TClipboardCleanupStrategy; AThresholdSeconds: Integer);
var
  Deleted: Integer;
begin
  if AStrategy = ccsNone then
    Exit;
  Deleted := SweepClipboardTempFolder(AFolder, AStrategy, AThresholdSeconds,
    MIN_SWEEP_AGE_FLOOR_SECONDS, GetClipboardFilePath, Now);
  DebugLog('Clipboard', Format(
    'RunClipboardTempSweep: folder="%s" strategy=%s deleted=%d',
    [AFolder, ClipboardCleanupStrategyToStr(AStrategy), Deleted]));
end;

end.
