{User-defined ffmpeg preset model and loader for the WCX plugin.
 Each preset becomes one virtual file in the archive listing; running it
 invokes ffmpeg with the user's argument string against the source video.
 This unit owns the data model, INI loading, template expansion, validation,
 and the dedupe pass that resolves listing-time filename collisions.
 No process execution lives here — that belongs to the preset extractor
 (Step 5 of the WCX presets feature).}
unit uWcxPresets;

interface

uses
  System.SysUtils, System.IniFiles;

type
  {Preset definition as it appears in presets.ini.
   Name is the INI section name and doubles as a template variable.
   OutputExt is stored without a leading dot; the leading dot is added by
   BuildOutputFileName so callers do not need to know whether the user wrote
   "mp3" or ".mp3" in the INI.
   OutputName is a pre-expansion template; empty means "use the documented
   default (%basename%_%name%)" and stays empty in the record so a settings
   editor can distinguish "user set this to the default" from "user left it
   blank".
   Args is the ffmpeg argument string that goes after "-i <input>". May be
   empty when the user wants a default-codec transcode driven only by the
   output extension.
   Enabled mirrors the INI key; disabled presets are skipped at load time
   so they never reach the listing or extractor.}
  TWcxPreset = record
    Name: string;
    Description: string;
    OutputExt: string;
    OutputName: string;
    Args: string;
    Enabled: Boolean;
  end;

  TWcxPresetArray = TArray<TWcxPreset>;

{Loads enabled, valid presets from APath.
 Returns an empty array when the file does not exist or contains no
 sections; never raises. Disabled entries, entries missing the required
 OutputExt, entries with a malformed OutputExt or OutputName, and entries
 whose Args contain a forbidden token are skipped with a DebugLog warning
 so the rest of the file still loads.
 Note: the "skip disabled" semantics are tailored to the WCX listing path
 (a disabled preset has no place in the visible archive). The editor uses
 LoadAllPresets instead so it can show, edit, and re-enable disabled
 entries.}
function LoadPresets(const APath: string): TWcxPresetArray;

{Loads every preset section verbatim — including disabled entries —
 without applying the validation filter. Used by the GUI editor so a
 disabled or temporarily-malformed preset is visible and fixable rather
 than silently dropped on file open. Sections that cannot be parsed at
 all are still skipped (they would round-trip to invalid INI), but the
 OutputExt / OutputName / Args validation is deferred to save time.}
function LoadAllPresets(const APath: string): TWcxPresetArray;

{Writes APresets to APath in their array order. Order matters — first
 defined wins the bare name in the listing-time dedupe pass — so the
 editor stores its working order via this routine. Overwrites the file
 atomically by writing the full content in one shot rather than poking
 individual TIniFile keys (TIniFile would not preserve section order on
 a fresh file). UTF-8 with no BOM matches the loader's expectations.}
procedure SavePresets(const APath: string; const APresets: TWcxPresetArray);

{Expands the recognised template variables against AInputPath and APresetName.
 Recognised tokens: %basename% (input filename without path or extension),
 %name% (the preset section name verbatim), %ext% (input extension without
 the leading dot, lowercased so case-only differences do not propagate into
 the output filename). Unknown %tokens% pass through unchanged so future
 additions stay backwards-compatible at the INI layer.}
function ExpandTemplate(const ATemplate, AInputPath, APresetName: string): string;

{Builds the listed filename for APreset against AInputPath.
 Honours APreset.OutputName when non-empty; empty falls back to the
 documented default %basename%_%name%. The OutputExt is appended with a
 single separating dot. Pure function; performs no I/O.}
function BuildOutputFileName(const APreset: TWcxPreset; const AInputPath: string): string;

{Walks ANames in order and renames colliding entries TC-style: the first
 occurrence keeps its bare name; later occurrences become "<base>(N)<ext>"
 with N starting at 2 and incrementing until a free slot is found.
 Comparison is case-insensitive because Windows filesystems are
 case-insensitive — TC would otherwise treat "Poster.jpg" and "poster.jpg"
 as the same listing entry. The probe-against-running-set algorithm also
 protects literal hand-written entries: if a user defines a preset that
 produces "poster(2).jpg" verbatim, the auto-dedupe of a colliding
 "poster.jpg" entry skips 2 and lands on 3.}
function DeduplicateFileNames(const ANames: TArray<string>): TArray<string>;

{Validates an Args string against the forbidden-token list.
 Returns True with AReason=''. Returns False with AReason populated when
 the args contain a forbidden token: -i (would override the input the
 extractor injects), -y / -n (would override the tempfile-and-rename
 overwrite policy), pipe:0/pipe:1/pipe:2 (would clash with the -progress
 channel and our disk output target). Tokenisation is whitespace-based
 and respects double-quoted substrings; flag comparison is
 case-insensitive so "-Y" is also rejected.}
function ValidatePresetArgs(const AArgs: string; out AReason: string): Boolean;

{Tokenises a command-line-style argument string into whitespace-separated
 tokens, treating double-quoted runs as a single token (the surrounding
 quotes are stripped). Exposed for the validator and the extractor's
 future argv builder so both share the same parse rules.}
function TokenizeArgs(const AArgs: string): TArray<string>;

{Returns the full path to the presets file expected to live next to the
 WCX settings INI. Pure path manipulation; does not touch the disk.
 Returns '' when the settings path is empty so callers downstream can
 short-circuit on the documented "no presets" sentinel.}
function PresetsIniPath(const ASettingsIniPath: string): string;

implementation

uses
  System.Generics.Collections, System.Classes, System.Character, System.IOUtils,
  uDebugLog;

const
  CPresetLog = 'WCX-Presets';

procedure PresetLog(const AMsg: string);
begin
  DebugLog(CPresetLog, AMsg);
end;

{TIniFile.ReadBool only recognises 0/1 (it routes through ReadInteger). Users
 hand-editing presets.ini will write True/False/Yes/No and expect them to
 work; this helper keeps that ergonomic affordance without forcing users to
 learn the integer encoding.}
function ReadBoolLenient(AIni: TIniFile; const ASection, AKey: string; ADefault: Boolean): Boolean;
var
  S: string;
begin
  S := AIni.ReadString(ASection, AKey, '').Trim.ToLower;
  if S = '' then
    Exit(ADefault);
  if (S = 'false') or (S = 'no') or (S = '0') or (S = 'off') then
    Exit(False);
  if (S = 'true') or (S = 'yes') or (S = '1') or (S = 'on') then
    Exit(True);
  Result := ADefault;
end;

function TokenizeArgs(const AArgs: string): TArray<string>;
var
  List: TList<string>;
  I: Integer;
  Token: string;
  InQuote: Boolean;
  C: Char;
begin
  List := TList<string>.Create;
  try
    Token := '';
    InQuote := False;
    I := 1;
    while I <= Length(AArgs) do
    begin
      C := AArgs[I];
      if C = '"' then
      begin
        {Toggle quote state without copying the quote into the token —
         CreateProcess's command-line parser treats the same way, so the
         token shape we validate matches what ffmpeg eventually sees.}
        InQuote := not InQuote;
      end
      else if (not InQuote) and CharInSet(C, [' ', #9]) then
      begin
        if Token <> '' then
        begin
          List.Add(Token);
          Token := '';
        end;
      end
      else
        Token := Token + C;
      Inc(I);
    end;
    if Token <> '' then
      List.Add(Token);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

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

function ExpandTemplate(const ATemplate, AInputPath, APresetName: string): string;
var
  BaseName, Ext: string;
begin
  {ExtractFileName then strip extension via ChangeFileExt; ExtractFileExt
   includes the leading dot which we drop for %ext% so users can write
   "%basename%.%ext%" and get "Movie.mkv" rather than "Movie..mkv".}
  BaseName := TPath.GetFileNameWithoutExtension(AInputPath);
  Ext := ExtractFileExt(AInputPath);
  if (Length(Ext) > 0) and (Ext[1] = '.') then
    Ext := Copy(Ext, 2, Length(Ext) - 1);
  Ext := Ext.ToLower;

  Result := ATemplate;
  Result := StringReplace(Result, '%basename%', BaseName, [rfReplaceAll]);
  Result := StringReplace(Result, '%name%', APresetName, [rfReplaceAll]);
  Result := StringReplace(Result, '%ext%', Ext, [rfReplaceAll]);
end;

function BuildOutputFileName(const APreset: TWcxPreset; const AInputPath: string): string;
const
  CDefaultTemplate = '%basename%_%name%';
var
  Template: string;
begin
  if APreset.OutputName <> '' then
    Template := APreset.OutputName
  else
    Template := CDefaultTemplate;
  Result := ExpandTemplate(Template, AInputPath, APreset.Name) + '.' + APreset.OutputExt;
end;

function DeduplicateFileNames(const ANames: TArray<string>): TArray<string>;
var
  Taken: TDictionary<string, Boolean>;
  I, N: Integer;
  Name, Base, Ext, Candidate: string;
begin
  SetLength(Result, Length(ANames));
  {Case-insensitive set of already-claimed names. Lowercased keys avoid
   pulling in IEqualityComparer<string> just for one collision check.}
  Taken := TDictionary<string, Boolean>.Create;
  try
    for I := 0 to High(ANames) do
    begin
      Name := ANames[I];
      if not Taken.ContainsKey(Name.ToLower) then
      begin
        Result[I] := Name;
        Taken.Add(Name.ToLower, True);
        Continue;
      end;
      Ext := ExtractFileExt(Name);
      Base := Copy(Name, 1, Length(Name) - Length(Ext));
      N := 2;
      repeat
        Candidate := Format('%s(%d)%s', [Base, N, Ext]);
        Inc(N);
      until not Taken.ContainsKey(Candidate.ToLower);
      Result[I] := Candidate;
      Taken.Add(Candidate.ToLower, True);
    end;
  finally
    Taken.Free;
  end;
end;

function NormalizeOutputExt(const ARaw: string; out ANormalized: string): Boolean;
const
  CForbiddenChars = '\/:*?"<>| ' + #9;
var
  S: string;
  C: Char;
begin
  ANormalized := '';
  S := ARaw.Trim;
  if (Length(S) > 0) and (S[1] = '.') then
    S := Copy(S, 2, Length(S) - 1);
  if S = '' then
    Exit(False);
  for C in S do
    if Pos(C, CForbiddenChars) > 0 then
      Exit(False);
  ANormalized := S;
  Result := True;
end;

function IsValidOutputName(const ATemplate: string): Boolean;
const
  {Path separators and the Windows reserved characters; the template may
   contain template tokens like "%basename%" so '%' is not on the list.
   '.' is allowed because users might want literal dots in names.}
  CForbiddenChars = '\/:*?"<>|';
var
  C: Char;
begin
  for C in ATemplate do
    if Pos(C, CForbiddenChars) > 0 then
      Exit(False);
  Result := True;
end;

function PresetsIniPath(const ASettingsIniPath: string): string;
begin
  if ASettingsIniPath = '' then
    Exit('');
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ASettingsIniPath)) + 'presets.ini';
end;

{Reads one section into a preset record without applying any validation.
 OutputExt is normalised (leading dot stripped) for editor convenience;
 the more involved checks live in the caller.}
function ReadPresetSection(AIni: TIniFile; const ASection: string): TWcxPreset;
var
  RawExt: string;
begin
  Result := Default(TWcxPreset);
  Result.Name := ASection;
  Result.Enabled := ReadBoolLenient(AIni, ASection, 'Enabled', True);
  Result.Description := AIni.ReadString(ASection, 'Description', '').Trim;
  Result.OutputName := AIni.ReadString(ASection, 'OutputName', '').Trim;
  Result.Args := AIni.ReadString(ASection, 'Args', '');
  RawExt := AIni.ReadString(ASection, 'OutputExt', '').Trim;
  if (Length(RawExt) > 0) and (RawExt[1] = '.') then
    RawExt := Copy(RawExt, 2, Length(RawExt) - 1);
  Result.OutputExt := RawExt;
end;

function LoadPresets(const APath: string): TWcxPresetArray;
var
  Ini: TIniFile;
  Sections: TStringList;
  Preset: TWcxPreset;
  Accum: TList<TWcxPreset>;
  I: Integer;
  Section, NormalizedExt, Reason: string;
begin
  Result := nil;
  if not FileExists(APath) then
    Exit;
  Accum := TList<TWcxPreset>.Create;
  try
    Ini := TIniFile.Create(APath);
    try
      Sections := TStringList.Create;
      try
        Ini.ReadSections(Sections);
        for I := 0 to Sections.Count - 1 do
        begin
          Section := Sections[I];
          Preset := ReadPresetSection(Ini, Section);
          if not Preset.Enabled then
          begin
            PresetLog(Format('Preset "%s" disabled, skipped', [Section]));
            Continue;
          end;

          if not NormalizeOutputExt(Preset.OutputExt, NormalizedExt) then
          begin
            PresetLog(Format('Preset "%s" rejected: missing or invalid OutputExt', [Section]));
            Continue;
          end;
          Preset.OutputExt := NormalizedExt;

          if not IsValidOutputName(Preset.OutputName) then
          begin
            PresetLog(Format('Preset "%s" rejected: OutputName contains invalid filename characters', [Section]));
            Continue;
          end;

          if not ValidatePresetArgs(Preset.Args, Reason) then
          begin
            PresetLog(Format('Preset "%s" rejected: %s', [Section, Reason]));
            Continue;
          end;

          Accum.Add(Preset);
        end;
      finally
        Sections.Free;
      end;
    finally
      Ini.Free;
    end;
    Result := Accum.ToArray;
  finally
    Accum.Free;
  end;
end;

function LoadAllPresets(const APath: string): TWcxPresetArray;
var
  Ini: TIniFile;
  Sections: TStringList;
  Accum: TList<TWcxPreset>;
  I: Integer;
begin
  Result := nil;
  if not FileExists(APath) then
    Exit;
  Accum := TList<TWcxPreset>.Create;
  try
    Ini := TIniFile.Create(APath);
    try
      Sections := TStringList.Create;
      try
        Ini.ReadSections(Sections);
        for I := 0 to Sections.Count - 1 do
          Accum.Add(ReadPresetSection(Ini, Sections[I]));
      finally
        Sections.Free;
      end;
    finally
      Ini.Free;
    end;
    Result := Accum.ToArray;
  finally
    Accum.Free;
  end;
end;

procedure SavePresets(const APath: string; const APresets: TWcxPresetArray);
var
  Lines: TStringList;
  I: Integer;
  P: TWcxPreset;
begin
  if APath = '' then
    Exit;
  Lines := TStringList.Create;
  try
    {Manual emit so section ordering reflects the array verbatim — TIniFile
     re-orders new sections to the end and would not preserve the editor's
     drag-reorder semantics on an empty-or-rewritten file.}
    for I := 0 to High(APresets) do
    begin
      P := APresets[I];
      if I > 0 then
        Lines.Add('');
      Lines.Add('[' + P.Name + ']');
      if P.Enabled then
        Lines.Add('Enabled=1')
      else
        Lines.Add('Enabled=0');
      if P.Description <> '' then
        Lines.Add('Description=' + P.Description);
      Lines.Add('OutputExt=' + P.OutputExt);
      if P.OutputName <> '' then
        Lines.Add('OutputName=' + P.OutputName);
      {Args may legitimately be empty (default-codec transcode) so the
       presence of the key is what the loader checks; absence means
       "no args", which is round-trip safe.}
      if P.Args <> '' then
        Lines.Add('Args=' + P.Args);
    end;
    {UTF-16 LE with BOM is the only Unicode encoding TIniFile (Win32
     profile APIs underneath) reads correctly. UTF-8 BOM would be parsed
     as garbage prepended to the first section name, eating the first
     entry on the next load.}
    Lines.SaveToFile(APath, TEncoding.Unicode);
  finally
    Lines.Free;
  end;
end;

end.
