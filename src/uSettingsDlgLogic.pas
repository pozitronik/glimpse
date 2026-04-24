{Pure formatting helpers shared by the WLX and WCX settings dialogs.
 No VCL dependency, so these run under unit tests without a UI. The
 dialogs keep the wiring (control reads/writes, dialog plumbing); only
 the deterministic label-formatting and encode/decode policy lives here.}
unit uSettingsDlgLogic;

interface

uses
  uTypes;

type
  {Outcome of probing the ffmpeg path field in either settings dialog.
   The dialog computes this from filesystem state, then asks the
   formatter for the human-readable label. Splitting decision from
   rendering keeps the formatter pure (and trivially testable).}
  TFFmpegProbeState = (fpsNoPath, {Empty input and no autodetected fallback}
    fpsFileMissing, {Path resolved but the file is gone}
    fpsInvalid, {File exists but ffmpeg -version did not match}
    fpsValid{File exists and is a valid ffmpeg}
    );

  {Builds the auto-hint label for the "Max threads per worker" spin edit.
   - One-per-frame off       => empty (the field is disabled)
   - Auto, position < 0      => '(no limit)'
   - Auto, position = 0      => '(auto: N cores)'
   - Auto, position > 0      => empty (user picked an explicit value)
   ACpuCount must be the live System.CPUCount; injected so this stays
   pure and testable.}
function MaxThreadsAutoLabel(AOnePerFrame: Boolean; AThreadsPos, ACpuCount: Integer): string;

{Builds the ffmpeg info label text from a probe outcome and inputs.
 AInputWasEmpty distinguishes "user typed a path" (=> 'Version: ...')
 from "fallback autodetection picked one" (=> 'Detected: <path> (...)').
 Branches not relevant to the state (e.g. AVersion when AState is
 fpsFileMissing) are simply ignored.}
function FFmpegInfoLabelText(AState: TFFmpegProbeState; const APath, AVersion: string; AInputWasEmpty: Boolean): string;

{Decodes a stored timestamp (Show, Corner) pair into the (checkbox state,
 corner combo index) expected by the settings dialogs.

 Legacy tcNone — the pre-1.1 encoding when the corner combo had a "None"
 entry that doubled as the off-switch — migrates to ShowChecked=False
 plus the current default corner. The combo no longer carries tcNone;
 its items 0..3 map to tcTopLeft..tcBottomRight. This single helper
 prevents the two dialogs from drifting on the migration rule.}
procedure DecodeTimestampCornerControls(AShow: Boolean; ACorner: TTimestampCorner;
  out AShowChecked: Boolean; out AComboIndex: Integer);

{Encodes the checkbox state + combo index back into (Show, Corner) for
 saving. AComboIndex is assumed to be in range 0..3 (four real corners);
 Show passes through directly.}
procedure EncodeTimestampCornerControls(AShowChecked: Boolean; AComboIndex: Integer;
  out AShow: Boolean; out ACorner: TTimestampCorner);

{Decodes a stored MaxWorkers value into the (Auto checkbox, UpDown position)
 pair the dialogs display. MaxWorkers = 0 is the auto sentinel — checkbox
 checked, UpDown falls back to 1 so the explicit-mode field doesn't flash
 "0" when the user toggles auto off.}
procedure DecodeMaxWorkersControls(AMaxWorkers: Integer;
  out AAutoChecked: Boolean; out AUdPosition: Integer);

{Encodes the Auto checkbox + UpDown position back into MaxWorkers. Auto
 always maps to 0 regardless of the UpDown position (the UpDown value is
 stale when auto is toggled on).}
function EncodeMaxWorkersControls(AAutoChecked: Boolean; AUdPosition: Integer): Integer;

{Decodes a stored MaxThreads value into UpDown position. Positive values
 show as themselves; non-positive (-1 no-limit, 0 auto) collapse to 0 in
 the UI because the up-down min is 0. The reverse direction is a straight
 passthrough (UdPosition becomes MaxThreads), which is why no encode
 helper is needed here.}
function DecodeMaxThreadsControl(AMaxThreads: Integer): Integer;

implementation

uses
  System.SysUtils,
  uDefaults;

function MaxThreadsAutoLabel(AOnePerFrame: Boolean; AThreadsPos, ACpuCount: Integer): string;
begin
  if not AOnePerFrame then
    Exit('');
  if AThreadsPos < 0 then
    Exit('(no limit)');
  if AThreadsPos = 0 then
    Exit(Format('(auto: %d cores)', [ACpuCount]));
  Result := '';
end;

function FFmpegInfoLabelText(AState: TFFmpegProbeState; const APath, AVersion: string; AInputWasEmpty: Boolean): string;
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

procedure DecodeTimestampCornerControls(AShow: Boolean; ACorner: TTimestampCorner;
  out AShowChecked: Boolean; out AComboIndex: Integer);
begin
  if ACorner = tcNone then
  begin
    {Legacy migration: pre-1.1 "None" corner meant off. Show checkbox now
     owns visibility; corner falls back to the documented default.}
    AShowChecked := False;
    AComboIndex := Ord(DEF_TIMESTAMP_CORNER) - 1;
  end
  else
  begin
    AShowChecked := AShow;
    AComboIndex := Ord(ACorner) - 1;
  end;
end;

procedure EncodeTimestampCornerControls(AShowChecked: Boolean; AComboIndex: Integer;
  out AShow: Boolean; out ACorner: TTimestampCorner);
begin
  AShow := AShowChecked;
  ACorner := TTimestampCorner(AComboIndex + 1);
end;

procedure DecodeMaxWorkersControls(AMaxWorkers: Integer;
  out AAutoChecked: Boolean; out AUdPosition: Integer);
begin
  AAutoChecked := AMaxWorkers = 0;
  if AMaxWorkers > 0 then
    AUdPosition := AMaxWorkers
  else
    AUdPosition := 1;
end;

function EncodeMaxWorkersControls(AAutoChecked: Boolean; AUdPosition: Integer): Integer;
begin
  if AAutoChecked then
    Result := 0
  else
    Result := AUdPosition;
end;

function DecodeMaxThreadsControl(AMaxThreads: Integer): Integer;
begin
  if AMaxThreads > 0 then
    Result := AMaxThreads
  else
    Result := 0;
end;

end.
