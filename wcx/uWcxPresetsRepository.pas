{Persistence boundary for the WCX presets INI.

 Step 103 (M24): the dialog used to call LoadAllPresets / SavePresets
 free functions directly, hard-binding the editor flow to the on-disk
 INI shape. The repository interface owns the path and exposes a
 load/save pair the dialog can talk to without knowing where the
 presets live. Tests substitute an in-memory recorder.

 The production impl captures APath at construction so callers do not
 need to thread the path through every dialog method.}
unit uWcxPresetsRepository;

interface

uses
  uWcxPresets;

type
  IWcxPresetsRepository = interface
    ['{C19F7B40-2A8E-4D86-8AC5-2D8E3A1E0F44}']
    {Returns the full preset array from the backing store. The editor
     loads this verbatim into its model on dialog open. Production
     returns LoadAllPresets(APath); fakes return a canned array.}
    function LoadAll: TWcxPresetArray;
    {Replaces the backing store with APresets in order. The orchestrator
     calls this once per successful save. Production wraps
     SavePresets(APath, APresets); fakes record the call.}
    procedure SaveAll(const APresets: TWcxPresetArray);
  end;

  TProductionWcxPresetsRepository = class(TInterfacedObject, IWcxPresetsRepository)
  strict private
    FPath: string;
  public
    {APath is the presets INI path; usually PresetsIniPath(SettingsIniPath).
     An empty path makes SaveAll a no-op and LoadAll return an empty
     array, matching the legacy SavePresets / LoadAllPresets behaviour.}
    constructor Create(const APath: string);
    function LoadAll: TWcxPresetArray;
    procedure SaveAll(const APresets: TWcxPresetArray);
    property Path: string read FPath;
  end;

implementation

{TProductionWcxPresetsRepository}

constructor TProductionWcxPresetsRepository.Create(const APath: string);
begin
  inherited Create;
  FPath := APath;
end;

function TProductionWcxPresetsRepository.LoadAll: TWcxPresetArray;
begin
  Result := LoadAllPresets(FPath);
end;

procedure TProductionWcxPresetsRepository.SaveAll(const APresets: TWcxPresetArray);
begin
  SavePresets(FPath, APresets);
end;

end.
