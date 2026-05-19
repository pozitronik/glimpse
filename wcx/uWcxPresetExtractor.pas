{Runs an ffmpeg preset against a source video, streaming its -progress
 pipe:1 output through a callback and using a tempfile-and-rename
 pattern so a cancelled or failed run never leaves a partial file at
 the destination path.}
unit uWcxPresetExtractor;

interface

uses
  Winapi.Windows, System.SysUtils,
  uWcxPresets, uCmdLineTokens;

type
  {Returns True to continue, False to cancel.}
  TPresetProgressProc = reference to function(APercent: Integer): Boolean;

  TPresetExtractResult = record
    Success: Boolean;
    ExitCode: Integer;
    Cancelled: Boolean;
    ErrorMessage: string;
  end;

{Quotes per CommandLineToArgvW rules: backslashes preceding a quote
 (or at the very end before the closing quote) are doubled to preserve
 the literal backslash count after Windows parses the line back to argv.}
function QuoteArg(const ARaw: string): string;

{Inserts ".tmp" between basename and extension. A naive
 "<name>.<ext>.tmp" makes ffmpeg infer ".tmp" as the container and bail
 with "Unable to choose an output format".}
function MakeTempPath(const AOutputPath: string): string;

function BuildPresetCmdLine(const AFFmpegPath, AInputPath: string; const APreset: TWcxPreset; const AOutputTempPath: string): string;

{Recognises out_time_us / out_time_ms (both microseconds — ffmpeg's
 "ms" suffix is a known misnomer) and progress=end (terminal 100%
 tick, fires even when ADurationSeconds <= 0).}
function ParseProgressLine(const ALine: string; ADurationSeconds: Double; out APercent: Integer): Boolean;

{ATotalDurationSeconds <= 0 yields only the terminal 100% tick.
 ACancelHandle is what RunProcess waits on; pass the bridge's handle
 so AProgress=False also kills ffmpeg quickly.}
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

{-nostdin prevents ffmpeg from racing the cancel handle for keyboard
 input; -progress pipe:1 routes the parseable stream to stdout; -y is
 silent overwrite on retry; the rest trim noise.}
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
  {Build into one array then join — avoids the O(N^2) repeated
   concatenation walk.}
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
    {Best-effort: the next ExtractPreset run will retry.}
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

  {Pre-clean makes the failure mode deterministic and short-circuits
   ffmpeg's "file exists" probe on filesystems with slow open-for-write.}
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
  {RunProcess returns -1 on cancel or timeout; the callback flag
   distinguishes user cancel from wall-clock cap so the dispatcher can
   surface the right WCX error code.}
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

  {MoveFileEx with MOVEFILE_REPLACE_EXISTING is atomic on same volume —
   no window where the destination is missing.}
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
