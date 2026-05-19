{Preset input validators.

 ValidatePresetArgs rejects forbidden ffmpeg flags / tokens that would
 collide with the extractor's I/O contract. ValidateOutputName checks a
 path-style template for traversal, illegal characters, and rooted
 paths. ValidateOutputExt + NormalizeOutputExt enforce the
 forbidden-character set on output extensions.

 Single source of truth for the forbidden sets — the editor model and
 the file loader both call these instead of growing their own copy.

 Imports uCmdLineTokens (for ValidatePresetArgs). Does NOT import
 uWcxPresetTemplate: ValidateOutputName canonicalises '/' to '\\'
 inline (one StringReplace call) so this unit stays standalone and the
 unit graph stays acyclic. The cost is a single line of duplicated
 transform versus a forced import cycle through TWcxPreset.}
unit uWcxPresetValidation;

interface

{Validates an Args string against the forbidden-token list.
 Returns True with AReason=''. Returns False with AReason populated when
 the args contain a forbidden token: -i (would override the input the
 extractor injects), -y / -n (would override the tempfile-and-rename
 overwrite policy), pipe:0/pipe:1/pipe:2 (would clash with the -progress
 channel and our disk output target). Tokenisation is whitespace-based
 and respects double-quoted substrings; flag comparison is
 case-insensitive so "-Y" is also rejected.}
function ValidatePresetArgs(const AArgs: string; out AReason: string): Boolean;

{Validates an OutputName template that may contain virtual path segments.
 Returns True with AReason='' on accept; False with AReason populated
 on reject. Empty input is accepted (loader / extractor falls back to
 the default template).
 Reject rules:
   - Leading separator (rooted virtual path)
   - "." or ".." segment (path traversal or no-op confusion)
   - Empty segment (double separator)
   - Any of :*?"<>| inside any segment (Windows-illegal in filenames)
 Both '/' and '\' are accepted as separators; the validator normalises
 internally so users may type either form.}
function ValidateOutputName(const ATemplate: string; out AReason: string): Boolean;

{Validates an output-extension string (no leading dot, no spaces, no
 Windows path separators or wildcards). Empty or whitespace-only is
 rejected with "OutputExt is required". The first forbidden character
 surfaces as "OutputExt contains an invalid character: '<C>'". Used by
 NormalizeOutputExt internally (which discards the reason) and by
 TPresetEditorModel.ValidateForEditor (which surfaces it to the editor user).
 The single source of truth for the forbidden-character set.}
function ValidateOutputExt(const ARaw: string; out AReason: string): Boolean;

{Strips a leading dot from ARaw if present, then validates the result
 via ValidateOutputExt. ANormalized is set to the cleaned form on
 success, empty on failure. Used by LoadPresets to clean editor-style
 ".mp3" input down to "mp3" before storing it in TWcxPreset.OutputExt.}
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
    {pipe:N is always lowercase from ffmpeg's own emitters but tolerate
     uppercase user input by comparing the lowered token.}
    if (Lower = 'pipe:0') or (Lower = 'pipe:1') or (Lower = 'pipe:2') then
    begin
      AReason := Format('forbidden token "%s" clashes with extractor stdio channels', [T]);
      Exit(False);
    end;
  end;
  Result := True;
end;

const
  {Single source of truth for "characters that cannot appear in an output
   extension". Used by ValidateOutputExt; NormalizeOutputExt and the
   editor model both go through ValidateOutputExt so neither needs to
   know this set directly.}
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
  {Canonicalise separators inline rather than importing uWcxPresetTemplate
   for its NormalizeOutputName helper. The one-line transform is
   duplicated to keep this unit free of a back-edge to the template unit
   (which itself needs TWcxPreset and would create a cycle).}
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
