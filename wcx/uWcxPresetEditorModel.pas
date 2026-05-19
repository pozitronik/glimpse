{Working-set model for the WCX presets editor.
 Owns a mutable list of TWcxPreset records and exposes the operations the
 editor UI needs: add, remove, duplicate, reorder, and final validation.
 No UI dependencies — the editor form is a thin shell over this class so
 every behaviour pinned here is testable in isolation.
 Order matters: the listing-time dedupe pass gives the bare name to the
 first-defined preset, so MoveUp/Down change semantic priority too.}
unit uWcxPresetEditorModel;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  uWcxPresets;

type
  TPresetEditorModel = class
  strict private
    FPresets: TList<TWcxPreset>;
    {Generates a non-colliding default name for a freshly-added preset.
     Tries the bare prefix first, then suffixes _2, _3, ... until a
     case-insensitive unique slot is found.}
    function GenerateUniqueName(const APrefix: string): string;
    function NameExists(const AName: string; AExceptIndex: Integer): Boolean;
    {Returns True when AName matches any preset at an earlier index.
     Used by Validate to flag the LATER of two duplicates as the
     offender — that matches user intuition (the freshly-added entry
     is the conflict, not the original).}
    function HasDuplicateBefore(const AName: string; AIndex: Integer): Boolean;
    {Per-preset rule runner shared by ValidateStructural and
     ValidateForEditor. Differs only in ADuplicateCheck.}
    function CheckPresetAt(AIndex: Integer; const ADuplicateCheck: TFunc<string, Integer, Boolean>; out AReason: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadFrom(const APresets: TWcxPresetArray);
    function ToArray: TWcxPresetArray;
    function Count: Integer;
    function Get(AIndex: Integer): TWcxPreset;
    procedure Update(AIndex: Integer; const APreset: TWcxPreset);

    {Appends a new preset with sensible defaults and a unique name.
     Returns the index of the new preset.}
    function Add: Integer;
    procedure Remove(AIndex: Integer);
    {Inserts a copy right after the source. Returns the new index. The
     copy gets a unique name (sourcename_copy, _copy_2, ...) so the
     duplicate is immediately distinct.}
    function Duplicate(AIndex: Integer): Integer;

    {Runs every validation rule against every preset and returns False
     on first failure. AInvalidIndex points to the offender so the editor
     can focus that row; AReason carries the user-visible message.
     Rules: name non-empty and unique; OutputExt non-empty and free of
     filename-illegal characters; OutputName free of path separators;
     Args clear of the forbidden-token list.

     Two variants differ ONLY in how a duplicate name is reported:
       ValidateStructural — order-agnostic. Uses NameExists; on a
         duplicate-name pair, the FIRST preset encountered in the loop
         is flagged. Use this from non-UI paths (CLI, import).
       ValidateForEditor — overlays the "blame the later duplicate"
         UX rule via HasDuplicateBefore. The freshly-added preset is
         the conflict from the user's perspective; the original keeps
         its name. The editor dialog uses this variant.
     Every other rule (empty name, OutputExt, OutputName, Args) is
     identical between the two; the duplicate-blame is the only
     semantic difference.}
    function ValidateStructural(out AInvalidIndex: Integer; out AReason: string): Boolean;
    function ValidateForEditor(out AInvalidIndex: Integer; out AReason: string): Boolean;
  end;

implementation

uses
  uWcxPresetValidation;

constructor TPresetEditorModel.Create;
begin
  inherited;
  FPresets := TList<TWcxPreset>.Create;
end;

destructor TPresetEditorModel.Destroy;
begin
  FPresets.Free;
  inherited;
end;

procedure TPresetEditorModel.LoadFrom(const APresets: TWcxPresetArray);
var
  P: TWcxPreset;
begin
  FPresets.Clear;
  for P in APresets do
    FPresets.Add(P);
end;

function TPresetEditorModel.ToArray: TWcxPresetArray;
begin
  Result := FPresets.ToArray;
end;

function TPresetEditorModel.Count: Integer;
begin
  Result := FPresets.Count;
end;

function TPresetEditorModel.Get(AIndex: Integer): TWcxPreset;
begin
  Result := FPresets[AIndex];
end;

procedure TPresetEditorModel.Update(AIndex: Integer; const APreset: TWcxPreset);
begin
  FPresets[AIndex] := APreset;
end;

function TPresetEditorModel.NameExists(const AName: string; AExceptIndex: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to FPresets.Count - 1 do
    if (I <> AExceptIndex) and SameText(FPresets[I].Name, AName) then
      Exit(True);
  Result := False;
end;

function TPresetEditorModel.HasDuplicateBefore(const AName: string; AIndex: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to AIndex - 1 do
    if SameText(FPresets[I].Name, AName) then
      Exit(True);
  Result := False;
end;

function TPresetEditorModel.GenerateUniqueName(const APrefix: string): string;
var
  N: Integer;
begin
  Result := APrefix;
  if not NameExists(Result, -1) then
    Exit;
  N := 2;
  repeat
    Result := Format('%s_%d', [APrefix, N]);
    Inc(N);
  until not NameExists(Result, -1);
end;

function TPresetEditorModel.Add: Integer;
var
  P: TWcxPreset;
begin
  P := Default(TWcxPreset);
  P.Name := GenerateUniqueName('new_preset');
  P.Enabled := True;
  P.OutputExt := 'mp4';
  Result := FPresets.Add(P);
end;

procedure TPresetEditorModel.Remove(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FPresets.Count) then
    Exit;
  FPresets.Delete(AIndex);
end;

function TPresetEditorModel.Duplicate(AIndex: Integer): Integer;
var
  Copy: TWcxPreset;
begin
  if (AIndex < 0) or (AIndex >= FPresets.Count) then
    Exit(-1);
  Copy := FPresets[AIndex];
  Copy.Name := GenerateUniqueName(FPresets[AIndex].Name + '_copy');
  Result := AIndex + 1;
  FPresets.Insert(Result, Copy);
end;

{Per-preset rule runner shared by ValidateStructural and
 ValidateForEditor. The two callers differ only in ADuplicateCheck:
 NameExists for the structural variant (any-order conflict, the first
 preset of a pair is flagged), HasDuplicateBefore for the editor
 variant (LATER preset of the pair is flagged, matching user intent).}
function TPresetEditorModel.CheckPresetAt(AIndex: Integer; const ADuplicateCheck: TFunc<string, Integer, Boolean>; out AReason: string): Boolean;
var
  P: TWcxPreset;
  NameReason: string;
begin
  AReason := '';
  P := FPresets[AIndex];

  if P.Name.Trim = '' then
  begin
    AReason := 'Name must not be empty';
    Exit(False);
  end;
  if ADuplicateCheck(P.Name, AIndex) then
  begin
    AReason := Format('Name "%s" is used by another preset (case-insensitive)', [P.Name]);
    Exit(False);
  end;

  if not ValidateOutputExt(P.OutputExt, AReason) then
    Exit(False);

  if not ValidateOutputName(P.OutputName, NameReason) then
  begin
    AReason := 'OutputName: ' + NameReason;
    Exit(False);
  end;

  if not ValidatePresetArgs(P.Args, AReason) then
  begin
    AReason := 'Args: ' + AReason;
    Exit(False);
  end;

  Result := True;
end;

function TPresetEditorModel.ValidateStructural(out AInvalidIndex: Integer; out AReason: string): Boolean;
var
  I: Integer;
  DupCheck: TFunc<string, Integer, Boolean>;
begin
  AInvalidIndex := -1;
  AReason := '';
  DupCheck := function(AName: string; AIndex: Integer): Boolean
    begin
      Result := NameExists(AName, AIndex);
    end;
  for I := 0 to FPresets.Count - 1 do
    if not CheckPresetAt(I, DupCheck, AReason) then
    begin
      AInvalidIndex := I;
      Exit(False);
    end;
  Result := True;
end;

function TPresetEditorModel.ValidateForEditor(out AInvalidIndex: Integer; out AReason: string): Boolean;
var
  I: Integer;
  DupCheck: TFunc<string, Integer, Boolean>;
begin
  AInvalidIndex := -1;
  AReason := '';
  DupCheck := function(AName: string; AIndex: Integer): Boolean
    begin
      Result := HasDuplicateBefore(AName, AIndex);
    end;
  for I := 0 to FPresets.Count - 1 do
    if not CheckPresetAt(I, DupCheck, AReason) then
    begin
      AInvalidIndex := I;
      Exit(False);
    end;
  Result := True;
end;

end.
