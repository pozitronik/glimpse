{Runs an ffmpeg preset against a source video and writes the result to a
 user-chosen destination path. Streams ffmpeg's -progress pipe:1 output
 through a caller-supplied progress callback so TC's progress bar advances,
 and uses a tempfile-and-rename pattern so a cancelled or failed run never
 leaves a partial file at the destination path.
 The extractor itself is decoupled from TWcxProgressBridge: it takes a
 progress callback and a Win32 cancel handle, so tests can drive it with
 fakes and the dispatcher in uWcxExports owns the bridge.}
unit uWcxPresetExtractor;

interface

uses
  Winapi.Windows, System.SysUtils,
  uWcxPresets;

type
  {Returns True to continue extraction, False to cancel. Wired by the WCX
   ProcessFile dispatcher to TWcxProgressBridge.ReportPercent.}
  TPresetProgressProc = reference to function(APercent: Integer): Boolean;

  TPresetExtractResult = record
    Success: Boolean;
    ExitCode: Integer;
    Cancelled: Boolean;
    ErrorMessage: string;
  end;

{Quotes a single command-line argument per CommandLineToArgvW parsing
 rules. Args without spaces, tabs, double quotes, or empty strings pass
 through verbatim. Otherwise the arg is wrapped in double quotes and any
 embedded quotes get backslash-escaped, with backslashes preceding a
 quote (or at the very end before the closing quote) doubled to preserve
 the literal backslash count after Windows parses the line back to argv.
 Pure function exposed for tests.}
function QuoteArg(const ARaw: string): string;

{Builds the tempfile path used during a preset extract.
 Inserts ".tmp" between the basename and the extension so the real
 extension is preserved — ffmpeg infers the output container from the
 extension, and a naive "<name>.<ext>.tmp" form would make it see ".tmp"
 and bail with "Unable to choose an output format". For "poster.jpg"
 returns "poster.tmp.jpg"; for "no_ext" returns "no_ext.tmp".}
function MakeTempPath(const AOutputPath: string): string;

{Composes the ffmpeg command line for one preset run.
 Layout: <exe> -hide_banner -nostdin -loglevel error -progress pipe:1 -y
         -i <input> <user tokens> <tempout>
 The fixed prefix is non-negotiable for the extractor's contract:
 -progress pipe:1 is what the streaming line reader parses, -y forces
 silent overwrite of the tempfile from a prior aborted run, and -nostdin
 prevents ffmpeg from blocking on a tty read in headless contexts.
 User tokens come from TokenizeArgs(APreset.Args) and are re-quoted on
 the way out, so a token like "title=My Movie" round-trips correctly
 even after the user's quoting has been stripped by the tokeniser.}
function BuildPresetCmdLine(const AFFmpegPath, AInputPath: string; const APreset: TWcxPreset; const AOutputTempPath: string): string;

{Parses one line of ffmpeg's -progress pipe:1 output.
 Recognises:
   out_time_us=N or out_time_ms=N
     N is microseconds in both cases (ffmpeg's "ms" suffix is a known
     misnomer; it actually carries microseconds). Computes percent against
     ADurationSeconds.
   progress=end
     Reports 100% as the final tick.
 Returns True with APercent populated when the line yields a usable value;
 False on noise lines, N/A values, or when ADurationSeconds <= 0 makes
 percent computation impossible (progress=end still fires in that case
 because the duration is irrelevant for the terminal tick).}
function ParseProgressLine(const ALine: string; ADurationSeconds: Double; out APercent: Integer): Boolean;

{Runs the preset against AInputPath, writes to a tempfile next to
 AOutputPath, atomically renames to AOutputPath on exit code 0.
 Pre-cleans any stale tempfile from a prior aborted run so ffmpeg never
 sees an unexpected leftover.
 ATotalDurationSeconds drives metered progress (typically from the probe
 cache); pass <=0 to receive only the terminal 100% tick.
 AProgress receives parsed percentages; returning False signals cancel.
 ACancelHandle is what RunProcess waits on to terminate the child; pass
 the bridge's CancelHandle so AProgress=False also kills ffmpeg quickly.
 ATimeoutMs is the wall-clock cap.}
function ExtractPreset(const AFFmpegPath, AInputPath, AOutputPath: string; const APreset: TWcxPreset; ATotalDurationSeconds: Double; AProgress: TPresetProgressProc;
  ACancelHandle: THandle; ATimeoutMs: DWORD): TPresetExtractResult;

implementation

uses
  System.Classes, System.IOUtils,
  uRunProcess;

const
  MOVEFILE_REPLACE_EXISTING = 1;

function MoveFileEx(lpExistingFileName, lpNewFileName: PChar; dwFlags: Cardinal): LongBool; stdcall; external 'kernel32.dll' name 'MoveFileExW';

function MakeTempPath(const AOutputPath: string): string;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AOutputPath);
  Result := ChangeFileExt(AOutputPath, '') + '.tmp' + Ext;
end;

function QuoteArg(const ARaw: string): string;
var
  NeedsQuote: Boolean;
  I, Backslashes: Integer;
  C: Char;
  Body: TStringBuilder;
begin
  NeedsQuote := (ARaw = '') or (Pos(' ', ARaw) > 0) or (Pos(#9, ARaw) > 0) or (Pos('"', ARaw) > 0);
  if not NeedsQuote then
    Exit(ARaw);

  Body := TStringBuilder.Create;
  try
    Backslashes := 0;
    for I := 1 to Length(ARaw) do
    begin
      C := ARaw[I];
      if C = '\' then
      begin
        Inc(Backslashes);
        Body.Append(C);
      end
      else if C = '"' then
      begin
        {Per Microsoft's CommandLineToArgvW rules, every backslash
         immediately before a quote must be doubled, and the quote itself
         escaped with a leading backslash.}
        Body.Append('\', Backslashes);
        Body.Append('\"');
        Backslashes := 0;
      end
      else
      begin
        Backslashes := 0;
        Body.Append(C);
      end;
    end;
    {Trailing backslashes get doubled before the closing quote — without
     this, "foo\" parses back as foo" (escaped quote, no closing).}
    if Backslashes > 0 then
      Body.Append('\', Backslashes);
    Result := '"' + Body.ToString + '"';
  finally
    Body.Free;
  end;
end;

{Fixed flags between the exe and the input path. -hide_banner suppresses
 the ffmpeg version blurb; -nostdin prevents ffmpeg from racing the
 cancel handle for keyboard input; -loglevel error trims stderr to actual
 errors; -progress pipe:1 routes the parseable progress stream to stdout;
 -y silently overwrites the temp output file on retry.}
const
  FFMPEG_BASE_FLAGS: array[0..4] of string = (
    '-hide_banner', '-nostdin', '-loglevel', 'error', '-progress'
  );
  FFMPEG_PROGRESS_TARGET = 'pipe:1';
  FFMPEG_OVERWRITE_FLAG = '-y';
  FFMPEG_INPUT_FLAG = '-i';

function BuildPresetCmdLine(const AFFmpegPath, AInputPath: string; const APreset: TWcxPreset; const AOutputTempPath: string): string;
var
  UserTokens: TArray<string>;
  Parts: TArray<string>;
  I: Integer;
begin
  UserTokens := TokenizeArgs(APreset.Args);
  {Layout: <exe> <base flags> pipe:1 -y -i <input> <user tokens...> <output>.
   Built into a single TArray<string> then joined once with ' ' as the
   separator, avoiding the O(N^2) repeated-concatenation walk.}
  SetLength(Parts, 1 + Length(FFMPEG_BASE_FLAGS) + 4 + Length(UserTokens) + 1);
  Parts[0] := QuoteArg(AFFmpegPath);
  for I := 0 to High(FFMPEG_BASE_FLAGS) do
    Parts[1 + I] := FFMPEG_BASE_FLAGS[I];
  Parts[1 + Length(FFMPEG_BASE_FLAGS)] := FFMPEG_PROGRESS_TARGET;
  Parts[2 + Length(FFMPEG_BASE_FLAGS)] := FFMPEG_OVERWRITE_FLAG;
  Parts[3 + Length(FFMPEG_BASE_FLAGS)] := FFMPEG_INPUT_FLAG;
  Parts[4 + Length(FFMPEG_BASE_FLAGS)] := QuoteArg(AInputPath);
  for I := 0 to High(UserTokens) do
    Parts[5 + Length(FFMPEG_BASE_FLAGS) + I] := QuoteArg(UserTokens[I]);
  Parts[High(Parts)] := QuoteArg(AOutputTempPath);
  Result := string.Join(' ', Parts);
end;

function ParseProgressLine(const ALine: string; ADurationSeconds: Double; out APercent: Integer): Boolean;
var
  EqPos: Integer;
  Key, Value: string;
  TimeUs: Int64;
  RawPercent: Double;
begin
  Result := False;
  APercent := 0;
  EqPos := Pos('=', ALine);
  if EqPos < 2 then
    Exit;
  Key := Copy(ALine, 1, EqPos - 1).Trim.ToLower;
  Value := Copy(ALine, EqPos + 1, MaxInt).Trim;

  if (Key = 'progress') and SameText(Value, 'end') then
  begin
    APercent := 100;
    Exit(True);
  end;

  if (Key = 'out_time_ms') or (Key = 'out_time_us') then
  begin
    if (Value = '') or SameText(Value, 'N/A') then
      Exit;
    if not TryStrToInt64(Value, TimeUs) then
      Exit;
    if ADurationSeconds <= 0 then
      Exit;
    RawPercent := (TimeUs / 1.0E6) / ADurationSeconds * 100;
    if RawPercent < 0 then
      RawPercent := 0;
    if RawPercent > 100 then
      RawPercent := 100;
    APercent := Round(RawPercent);
    Result := True;
  end;
end;

procedure SafeDelete(const APath: string);
begin
  if APath = '' then
    Exit;
  try
    if TFile.Exists(APath) then
      TFile.Delete(APath);
  except
    {Best-effort cleanup; the next ExtractPreset run will retry the
     delete via the same path. Logging would belong to the dispatcher.}
  end;
end;

function ExtractPreset(const AFFmpegPath, AInputPath, AOutputPath: string; const APreset: TWcxPreset; ATotalDurationSeconds: Double; AProgress: TPresetProgressProc;
  ACancelHandle: THandle; ATimeoutMs: DWORD): TPresetExtractResult;
var
  TempPath, CmdLine: string;
  CapturedStdErr: TBytes;
  ExitCode: Integer;
  CancelFromCallback: Boolean;
  ErrorText: string;
begin
  Result := Default(TPresetExtractResult);
  TempPath := MakeTempPath(AOutputPath);

  {A leftover .tmp from a previous crashed run would normally be
   overwritten by the -y flag we pass to ffmpeg, but pre-cleaning makes
   the failure mode deterministic and short-circuits ffmpeg's "file exists"
   probe on filesystems where the open-for-write step is slow.}
  SafeDelete(TempPath);

  CmdLine := BuildPresetCmdLine(AFFmpegPath, AInputPath, APreset, TempPath);

  CancelFromCallback := False;
  try
    ExitCode := RunProcess(CmdLine,
      procedure(ALine: string)
      var
        Percent: Integer;
      begin
        if not ParseProgressLine(ALine, ATotalDurationSeconds, Percent) then
          Exit;
        if Assigned(AProgress) then
          if not AProgress(Percent) then
            CancelFromCallback := True;
      end,
      CapturedStdErr,
      ATimeoutMs,
      ACancelHandle);
  except
    on E: Exception do
    begin
      SafeDelete(TempPath);
      Result.Success := False;
      Result.ExitCode := -1;
      Result.ErrorMessage := Format('ffmpeg launch failed: %s: %s', [E.ClassName, E.Message]);
      Exit;
    end;
  end;

  Result.ExitCode := ExitCode;
  {RunProcess returns -1 on cancel or timeout; the cancel-from-callback
   flag distinguishes user cancel from wall-clock cap so the dispatcher
   can surface the right WCX error code.}
  Result.Cancelled := CancelFromCallback or
    ((ACancelHandle <> 0) and (WaitForSingleObject(ACancelHandle, 0) = WAIT_OBJECT_0));

  if Result.Cancelled then
  begin
    SafeDelete(TempPath);
    Result.Success := False;
    Result.ErrorMessage := 'Cancelled';
    Exit;
  end;

  if ExitCode <> 0 then
  begin
    SafeDelete(TempPath);
    Result.Success := False;
    if Length(CapturedStdErr) > 0 then
      ErrorText := TEncoding.UTF8.GetString(CapturedStdErr).Trim
    else
      ErrorText := '';
    Result.ErrorMessage := Format('ffmpeg exit code %d. %s', [ExitCode, ErrorText]);
    Exit;
  end;

  {Atomic same-volume rename. MoveFileEx with MOVEFILE_REPLACE_EXISTING
   beats the delete-then-rename approach because it removes the brief
   window where the destination does not exist (matters less for WCX,
   but matches the standard contract for this kind of write).}
  if not MoveFileEx(PChar(TempPath), PChar(AOutputPath), MOVEFILE_REPLACE_EXISTING) then
  begin
    SafeDelete(TempPath);
    Result.Success := False;
    Result.ErrorMessage := Format('Rename failed: Win32 error %d', [GetLastError]);
    Exit;
  end;

  Result.Success := True;
end;

end.
