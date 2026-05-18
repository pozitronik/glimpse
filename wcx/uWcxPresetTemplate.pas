{Output-filename template expansion for WCX presets.

 ExpandTemplate substitutes %basename%, %name%, %ext% tokens.
 BuildOutputFileName composes a TWcxPreset's OutputName template + the
 input path into a final virtual-archive entry name.
 NormalizeOutputName canonicalises '/' to '\\' so downstream listing /
 dedupe operate on the WCX-canonical form regardless of which separator
 the user typed in the template.

 Imports uWcxPresets for the TWcxPreset record. No back-edge: the
 presets unit imports uWcxPresetValidation only; the template unit is
 free to depend on presets without creating a cycle.}
unit uWcxPresetTemplate;

interface

uses
  uWcxPresets;

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

{Normalises a path-style OutputName template to the WCX-canonical form:
 backslash separators (per the WCX SDK spec — TC does not recognise
 forward slashes as folder separators in archive entry names). Both '/'
 and '\' may appear in user input; both end up as '\' here. Keeps
 everything else verbatim, including template tokens like %basename%.
 Pure transform; safe to apply repeatedly.}
function NormalizeOutputName(const ATemplate: string): string;

implementation

uses
  System.SysUtils, System.IOUtils;

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
  {Normalise to '\' so virtual subfolders in user templates feed the
   listing builder and dedupe in canonical form regardless of which
   separator the user typed.}
  Result := NormalizeOutputName(Result);
end;

end.
