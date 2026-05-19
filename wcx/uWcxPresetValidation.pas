{Preset input validators. Single source of truth for the forbidden
 sets so the editor model and the file loader stay in lockstep.}
unit uWcxPresetValidation;

interface

{Rejects -i / -y / -n (would override extractor-managed flags) and
 pipe:0/1/2 (would clash with -progress and the disk output target).
 Case-insensitive.}
function ValidatePresetArgs(const AArgs: string; out AReason: string): Boolean;

{Empty input is accepted (default template applies). Rejects: leading
 separator, "." or ".." segments, empty segments, and Windows-illegal
 chars inside any segment. Accepts both '/' and '\' as separators.}
function ValidateOutputName(const ATemplate: string; out AReason: string): Boolean;

function ValidateOutputExt(const ARaw: string; out AReason: string): Boolean;

{Strips a leading dot then validates, so editor-style ".mp3" cleans to
 "mp3" for TWcxPreset.OutputExt.}
function NormalizeOutputExt(const ARaw: string; out ANormalized: string): Boolean;

implementation

uses
  System.SysUtils,
  uCmdLineTokens;

function ValidatePresetArgs(const AArgs: string; out AReason: string): Boolean;
var
  Tokens: TArray<string>;
  T, Lower: string;
begin
  AReason := '';
  Tokens := TokenizeArgs(AArgs);
  for T in Tokens do
  begin
    Lower := T.ToLower;
    if (Lower = '-i') or (Lower = '-y') or (Lower = '-n') then
    begin
      AReason := Format('forbidden flag "%s" overrides extractor-managed behaviour', [T]);
      Exit(False);
    end;
    {Tolerate uppercase user input even though ffmpeg always emits lowercase.}
    if (Lower = 'pipe:0') or (Lower = 'pipe:1') or (Lower = 'pipe:2') then
    begin
      AReason := Format('forbidden token "%s" clashes with extractor stdio channels', [T]);
      Exit(False);
    end;
  end;
  Result := True;
end;

const
  CForbiddenExtChars = '\/:*?"<>| ' + #9;

function ValidateOutputExt(const ARaw: string; out AReason: string): Boolean;
var
  C: Char;
begin
  AReason := '';
  if ARaw.Trim = '' then
  begin
    AReason := 'OutputExt is required';
    Exit(False);
  end;
  for C in ARaw do
    if Pos(C, CForbiddenExtChars) > 0 then
    begin
      AReason := Format('OutputExt contains an invalid character: "%s"', [C]);
      Exit(False);
    end;
  Result := True;
end;

function NormalizeOutputExt(const ARaw: string; out ANormalized: string): Boolean;
var
  S, Reason: string;
begin
  ANormalized := '';
  S := ARaw.Trim;
  if (Length(S) > 0) and (S[1] = '.') then
    S := Copy(S, 2, Length(S) - 1);
  Result := ValidateOutputExt(S, Reason);
  if Result then
    ANormalized := S;
end;

function ValidateOutputName(const ATemplate: string; out AReason: string): Boolean;
const
  CForbiddenInSegment = ':*?"<>|';
var
  Normalized: string;
  Segments: TArray<string>;
  Segment: string;
  C: Char;
begin
  AReason := '';
  if ATemplate = '' then
    Exit(True);
  {Inlined to avoid a back-edge to uWcxPresetTemplate (which needs
   TWcxPreset and would create a cycle).}
  Normalized := StringReplace(ATemplate, '/', '\', [rfReplaceAll]);
  if (Length(Normalized) > 0) and (Normalized[1] = '\') then
  begin
    AReason := 'Leading separator is not allowed (no rooted virtual paths)';
    Exit(False);
  end;
  Segments := Normalized.Split(['\']);
  for Segment in Segments do
  begin
    if Segment = '' then
    begin
      AReason := 'Empty path segment (double separator)';
      Exit(False);
    end;
    if Segment = '.' then
    begin
      AReason := '"." segment is not allowed';
      Exit(False);
    end;
    if Segment = '..' then
    begin
      AReason := '".." segment is not allowed (no traversal)';
      Exit(False);
    end;
    for C in Segment do
      if Pos(C, CForbiddenInSegment) > 0 then
      begin
        AReason := Format('Path segment contains an invalid character: "%s"', [C]);
        Exit(False);
      end;
  end;
  Result := True;
end;

end.
