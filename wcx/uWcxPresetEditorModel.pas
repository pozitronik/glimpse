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
     Args clear of the forbidden-token list.}
    function Validate(out AInvalidIndex: Integer; out AReason: string): Boolean;
  end;

implementation

uses
  System.SysUtils, uWcxPresetValidation;

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

function TPresetEditorModel.Validate(out AInvalidIndex: Integer; out AReason: string): Boolean;
var
  I: Integer;
  P: TWcxPreset;
  NameReason: string;
begin
  AInvalidIndex := -1;
  AReason := '';
  for I := 0 to FPresets.Count - 1 do
  begin
    P := FPresets[I];

    if P.Name.Trim = '' then
    begin
      AInvalidIndex := I;
      AReason := 'Name must not be empty';
      Exit(False);
    end;
    if HasDuplicateBefore(P.Name, I) then
    begin
      AInvalidIndex := I;
      AReason := Format('Name "%s" is used by another preset (case-insensitive)', [P.Name]);
      Exit(False);
    end;

    if not ValidateOutputExt(P.OutputExt, AReason) then
    begin
      AInvalidIndex := I;
      Exit(False);
    end;

    if not ValidateOutputName(P.OutputName, NameReason) then
    begin
      AInvalidIndex := I;
      AReason := 'OutputName: ' + NameReason;
      Exit(False);
    end;

    if not ValidatePresetArgs(P.Args, AReason) then
    begin
      AInvalidIndex := I;
      AReason := 'Args: ' + AReason;
      Exit(False);
    end;
  end;
  Result := True;
end;

end.
