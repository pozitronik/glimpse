{ Pure formatting helpers shared by the WLX and WCX settings dialogs.
  No VCL dependency, so these run under unit tests without a UI. The
  dialogs keep the wiring (control reads/writes, dialog plumbing); only
  the deterministic label-formatting policy lives here. }
unit uSettingsDlgLogic;

interface

type
  { Outcome of probing the ffmpeg path field in either settings dialog.
    The dialog computes this from filesystem state, then asks the
    formatter for the human-readable label. Splitting decision from
    rendering keeps the formatter pure (and trivially testable). }
  TFFmpegProbeState = (
    fpsNoPath,       { Empty input and no autodetected fallback }
    fpsFileMissing,  { Path resolved but the file is gone }
    fpsInvalid,      { File exists but ffmpeg -version did not match }
    fpsValid         { File exists and is a valid ffmpeg }
  );

{ Builds the auto-hint label for the "Max threads per worker" spin edit.
  - One-per-frame off       => empty (the field is disabled)
  - Auto, position < 0      => '(no limit)'
  - Auto, position = 0      => '(auto: N cores)'
  - Auto, position > 0      => empty (user picked an explicit value)
  ACpuCount must be the live System.CPUCount; injected so this stays
  pure and testable. }
function MaxThreadsAutoLabel(AOnePerFrame: Boolean;
  AThreadsPos, ACpuCount: Integer): string;

{ Builds the ffmpeg info label text from a probe outcome and inputs.
  AInputWasEmpty distinguishes "user typed a path" (=> 'Version: ...')
  from "fallback autodetection picked one" (=> 'Detected: <path> (...)').
  Branches not relevant to the state (e.g. AVersion when AState is
  fpsFileMissing) are simply ignored. }
function FFmpegInfoLabelText(AState: TFFmpegProbeState;
  const APath, AVersion: string; AInputWasEmpty: Boolean): string;

implementation

uses
  System.SysUtils;

function MaxThreadsAutoLabel(AOnePerFrame: Boolean;
  AThreadsPos, ACpuCount: Integer): string;
begin
  if not AOnePerFrame then
    Exit('');
  if AThreadsPos < 0 then
    Exit('(no limit)');
  if AThreadsPos = 0 then
    Exit(Format('(auto: %d cores)', [ACpuCount]));
  Result := '';
end;

function FFmpegInfoLabelText(AState: TFFmpegProbeState;
  const APath, AVersion: string; AInputWasEmpty: Boolean): string;
begin
  case AState of
    fpsNoPath:
      Result := 'Not found';
    fpsFileMissing:
      Result := Format('Not found: %s', [APath]);
    fpsInvalid:
      Result := Format('Invalid executable: %s', [APath]);
    fpsValid:
      if AInputWasEmpty then
        Result := Format('Detected: %s (%s)', [APath, AVersion])
      else
        Result := Format('Version: %s', [AVersion]);
  else
    Result := '';
  end;
end;

end.
