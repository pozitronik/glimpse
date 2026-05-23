{Persistence boundary for the WCX presets INI. Tests substitute an
 in-memory recorder.}
unit WcxPresetsRepository;

interface

uses
  WcxPresets;

type
  {Read facet: load all presets from the backing store. Used by the
   preset-editor presenter when the dialog opens.}
  IWcxPresetsReader = interface
    ['{C19F7B40-2A8E-4D86-8AC5-2D8E3A1E0F44}']
    function LoadAll: TWcxPresetArray;
  end;

  {Write facet: persist the preset set. Used by the settings-save
   orchestrator on Apply / OK.}
  IWcxPresetsWriter = interface
    ['{D2A08C51-3B9F-4E97-9BD6-3E9F4B2F1054}']
    procedure SaveAll(const APresets: TWcxPresetArray);
  end;

  TProductionWcxPresetsRepository = class(TInterfacedObject, IWcxPresetsReader, IWcxPresetsWriter)
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
