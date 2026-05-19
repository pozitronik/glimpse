{Persistence boundary for the WCX settings INI. Save-only by design:
 the dialog never loads its own settings instance — ConfigurePacker
 constructs and loads TWcxSettings before handing it in.}
unit WcxSettingsRepository;

interface

uses
  WcxSettings;

type
  IWcxSettingsRepository = interface
    ['{F0B5C92A-4D17-4E1A-9D2C-6CB6F0A78F11}']
    procedure Save(ASettings: TWcxSettings);
  end;

  TProductionWcxSettingsRepository = class(TInterfacedObject, IWcxSettingsRepository)
  public
    procedure Save(ASettings: TWcxSettings);
  end;

implementation

{TProductionWcxSettingsRepository}

procedure TProductionWcxSettingsRepository.Save(ASettings: TWcxSettings);
begin
  if ASettings <> nil then
    ASettings.Save;
end;

end.
