{Resolves the configured clipboard temp-folder setting to an actual writable
 directory. The pure pick (ChooseClipboardTempFolder) is split from the
 filesystem probe so the fallback policy is unit-testable without touching
 disk; ResolveClipboardTempFolder wires the probe to the pick and logs a
 fallback.}
unit ClipboardTempResolver;

interface

{Pure fallback policy. AConfigured is the raw setting (empty = system temp).
 AExpanded is AConfigured with env vars expanded. AExpandedUsable is whether
 that directory exists (or was successfully created). ASystemTemp is the
 system %TEMP%. Empty configured -> system; configured-but-unusable ->
 system (the caller logs that); otherwise the expanded path.}
function ChooseClipboardTempFolder(const AConfigured, AExpanded,
  ASystemTemp: string; AExpandedUsable: Boolean): string;

{Resolves the configured folder to a directory the publisher can write to,
 creating it if needed and falling back to the system temp on any failure.
 Always returns a trailing-delimited path. Never raises.}
function ResolveClipboardTempFolder(const AConfigured: string): string;

{Read-only display of where files will land, for the dialog's resolved-path
 hint. Empty -> system temp; otherwise the env-var-expanded path. Unlike
 ResolveClipboardTempFolder this never touches disk (no existence check, no
 directory creation), so it is safe to call on every keystroke.}
function DisplayClipboardTempFolder(const AConfigured: string): string;

implementation

uses
  System.SysUtils, System.IOUtils,
  PathExpand, Logging;

function ChooseClipboardTempFolder(const AConfigured, AExpanded,
  ASystemTemp: string; AExpandedUsable: Boolean): string;
begin
  if AConfigured.Trim = '' then
    Exit(ASystemTemp);
  if AExpandedUsable then
    Result := AExpanded
  else
    Result := ASystemTemp;
end;

{Best-effort: a configured folder that does not yet exist is created so a
 power user pointing at a fresh TC temp subtree just works; a creation
 failure is swallowed and reported as unusable.}
function DirectoryUsable(const APath: string): Boolean;
begin
  if APath = '' then
    Exit(False);
  if TDirectory.Exists(APath) then
    Exit(True);
  try
    Result := ForceDirectories(APath);
  except
    Result := False;
  end;
end;

function ResolveClipboardTempFolder(const AConfigured: string): string;
var
  SystemTemp, Expanded, Chosen: string;
  Usable: Boolean;
begin
  SystemTemp := TPath.GetTempPath;
  if AConfigured.Trim = '' then
    Exit(IncludeTrailingPathDelimiter(SystemTemp));

  Expanded := ExpandEnvVars(AConfigured);
  Usable := DirectoryUsable(Expanded);
  Chosen := ChooseClipboardTempFolder(AConfigured, Expanded, SystemTemp, Usable);
  if not Usable then
    DebugLog('Clipboard', Format(
      'ResolveClipboardTempFolder: configured folder "%s" (expanded "%s") is ' +
      'missing or could not be created; falling back to system temp "%s"',
      [AConfigured, Expanded, SystemTemp]));
  Result := IncludeTrailingPathDelimiter(Chosen);
end;

function DisplayClipboardTempFolder(const AConfigured: string): string;
begin
  if Trim(AConfigured) = '' then
    Result := IncludeTrailingPathDelimiter(TPath.GetTempPath)
  else
    Result := IncludeTrailingPathDelimiter(ExpandEnvVars(AConfigured));
end;

end.
