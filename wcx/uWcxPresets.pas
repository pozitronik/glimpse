{User-defined ffmpeg preset model and INI loader/saver. Data and I/O
 only; template expansion, validation, tokenisation, dedupe, and
 process execution live in their own units.}
unit uWcxPresets;

interface

uses
  System.SysUtils;

type
  {Name is the INI section and doubles as a template variable.
   OutputExt is stored without a leading dot (BuildOutputFileName adds
   it). OutputName empty means "use the default %basename%_%name%" and
   stays empty in the record so the editor can tell "user picked the
   default" from "user blanked it". Args is the ffmpeg argument string
   that follows "-i <input>".}
  TWcxPreset = record
    Name: string;
    Description: string;
    OutputExt: string;
    OutputName: string;
    Args: string;
    Enabled: Boolean;
  end;

  TWcxPresetArray = TArray<TWcxPreset>;

{Returns empty on missing/empty INI; never raises. Disabled or invalid
 entries are skipped with a DebugLog warning so the rest still loads.
 The listing path uses this; the editor calls LoadAllPresets to keep
 disabled or malformed entries visible and fixable.}
function LoadPresets(const APath: string): TWcxPresetArray;

function LoadAllPresets(const APath: string): TWcxPresetArray;

{Writes in array order — first-defined wins the dedupe pass — and
 clears the file first so removed presets do not leak back in.}
procedure SavePresets(const APath: string; const APresets: TWcxPresetArray);

{Pure path manipulation; returns '' on empty input.}
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

{Normalises only OutputExt (leading dot stripped); deeper checks live
 in the caller.}
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
    {Wipe so editor-driven removals do not leak back in. TUnicodeIniFile
     preserves Insert order, so the write order matches the array.}
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
      {Skip empty Args so the loader's "absent = empty" path round-trips.}
      if P.Args <> '' then
        Ini.WriteString(P.Name, 'Args', P.Args);
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
