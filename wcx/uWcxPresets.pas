{User-defined ffmpeg preset model and INI loader/saver for the WCX plugin.
 Each preset becomes one virtual file in the archive listing; running it
 invokes ffmpeg with the user's argument string against the source video.
 This unit owns the data model and INI I/O only — template expansion,
 validation, tokenisation, and the dedupe pass live in their own units
 (uWcxPresetTemplate / uWcxPresetValidation / uCmdLineTokens /
 uFileNameDedupe). No process execution lives here either — that
 belongs to uWcxPresetExtractor.}
unit uWcxPresets;

interface

uses
  System.SysUtils;

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
 editor stores its working order via this routine. Clears the file's
 previous content first so removed presets do not leak back in.}
procedure SavePresets(const APath: string; const APresets: TWcxPresetArray);

{Returns the full path to the presets file expected to live next to the
 WCX settings INI. Pure path manipulation; does not touch the disk.
 Returns '' when the settings path is empty so callers downstream can
 short-circuit on the documented "no presets" sentinel.}
function PresetsIniPath(const ASettingsIniPath: string): string;

implementation

uses
  System.Generics.Collections, System.Classes,
  uDebugLog, uUnicodeIniFile, uWcxPresetValidation;

const
  CPresetLog = 'WCX-Presets';

procedure PresetLog(const AMsg: string);
begin
  DebugLog(CPresetLog, AMsg);
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
function ReadPresetSection(AIni: TUnicodeIniFile; const ASection: string): TWcxPreset;
var
  RawExt: string;
begin
  Result := Default(TWcxPreset);
  Result.Name := ASection;
  Result.Enabled := AIni.ReadBool(ASection, 'Enabled', True);
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
  Ini: TUnicodeIniFile;
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
    Ini := TUnicodeIniFile.Create(APath);
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

          if not ValidateOutputName(Preset.OutputName, Reason) then
          begin
            PresetLog(Format('Preset "%s" rejected: OutputName invalid: %s', [Section, Reason]));
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
  Ini: TUnicodeIniFile;
  Sections: TStringList;
  Accum: TList<TWcxPreset>;
  I: Integer;
begin
  Result := nil;
  if not FileExists(APath) then
    Exit;
  Accum := TList<TWcxPreset>.Create;
  try
    Ini := TUnicodeIniFile.Create(APath);
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
  Ini: TUnicodeIniFile;
  I: Integer;
  P: TWcxPreset;
begin
  if APath = '' then
    Exit;
  Ini := TUnicodeIniFile.Create(APath);
  try
    {Wipe the file's previous content so an editor-driven full rewrite
     does not leak removed presets back into the saved output.
     Order-preserving Insert behaviour in TUnicodeIniFile guarantees the
     write order below matches the editor's array order.}
    Ini.Clear;
    for I := 0 to High(APresets) do
    begin
      P := APresets[I];
      Ini.WriteBool(P.Name, 'Enabled', P.Enabled);
      if P.Description <> '' then
        Ini.WriteString(P.Name, 'Description', P.Description);
      Ini.WriteString(P.Name, 'OutputExt', P.OutputExt);
      if P.OutputName <> '' then
        Ini.WriteString(P.Name, 'OutputName', P.OutputName);
      {Args may legitimately be empty (default-codec transcode); skip
       the key in that case so the loader's "absent = empty" path
       round-trips cleanly.}
      if P.Args <> '' then
        Ini.WriteString(P.Name, 'Args', P.Args);
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
