{Output-filename template expansion for WCX presets. Substitutes
 %basename%, %name%, %ext%; canonicalises '/' to '\' so the listing and
 dedupe pass see WCX-canonical separators regardless of user input.}
unit uWcxPresetTemplate;

interface

uses
  uWcxPresets;

{Recognised tokens: %basename%, %name%, %ext% (lowercased and without
 leading dot so "%basename%.%ext%" gives "Movie.mkv", not "Movie..mkv").
 Unknown %tokens% pass through for forward compatibility.}
function ExpandTemplate(const ATemplate, AInputPath, APresetName: string): string;

{Empty APreset.OutputName falls back to %basename%_%name%.}
function BuildOutputFileName(const APreset: TWcxPreset; const AInputPath: string): string;

{TC does not recognise '/' as a folder separator in archive entry names
 per the WCX SDK spec.}
function NormalizeOutputName(const ATemplate: string): string;

implementation

uses
  System.SysUtils, System.IOUtils;

function ExpandTemplate(const ATemplate, AInputPath, APresetName: string): string;
var
  BaseName, Ext: string;
begin
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

function NormalizeOutputName(const ATemplate: string): string;
begin
  Result := StringReplace(ATemplate, '/', '\', [rfReplaceAll]);
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
  Result := NormalizeOutputName(Result);
end;

end.
