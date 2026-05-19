{Working-set model for the WCX presets editor. No UI dependencies so
 every behaviour is testable in isolation. Order is semantic: listing-
 time dedupe gives the bare name to the first-defined preset, so
 reordering changes priority too.}
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
    function GenerateUniqueName(const APrefix: string): string;
    function NameExists(const AName: string; AExceptIndex: Integer): Boolean;
    {Flags the LATER of two duplicates as the offender — the freshly-
     added entry is the conflict from the user's perspective.}
    function HasDuplicateBefore(const AName: string; AIndex: Integer): Boolean;
    function CheckPresetAt(AIndex: Integer; const ADuplicateCheck: TFunc<string, Integer, Boolean>; out AReason: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadFrom(const APresets: TWcxPresetArray);
    function ToArray: TWcxPresetArray;
    function Count: Integer;
    function Get(AIndex: Integer): TWcxPreset;
    procedure Update(AIndex: Integer; const APreset: TWcxPreset);

    function Add: Integer;
    procedure Remove(AIndex: Integer);
    function Duplicate(AIndex: Integer): Integer;

    {Both variants share every rule except duplicate-blame:
     Structural blames the FIRST preset of a pair (order-agnostic, for
     CLI/import). ForEditor blames the LATER one (matches user intent
     for the freshly-added conflict).}
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
