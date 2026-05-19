{Persistence boundary for the WCX presets INI. Tests substitute an
 in-memory recorder.}
unit WcxPresetsRepository;

interface

uses
  WcxPresets;

type
  IWcxPresetsRepository = interface
    ['{C19F7B40-2A8E-4D86-8AC5-2D8E3A1E0F44}']
    function LoadAll: TWcxPresetArray;
    procedure SaveAll(const APresets: TWcxPresetArray);
  end;

  TProductionWcxPresetsRepository = class(TInterfacedObject, IWcxPresetsRepository)
  strict private
    FPath: string;
  public
    {Empty APath makes SaveAll a no-op and LoadAll return an empty array.}
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
