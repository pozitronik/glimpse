{Persistence boundary for the WCX settings INI.

 Step 103 (M24): the dialog used to call ASettings.Save directly inside
 TrySaveAll / TSettingsSaveOrchestrator, hard-binding the save flow to
 TWcxSettings's INI-on-disk implementation. The repository interface
 lifts that single side-effect behind a seam tests can intercept with
 an in-memory recorder, without spinning up a tempdir.

 Save-only by design: the dialog never loads its primary settings
 instance — ConfigurePacker constructs+loads TWcxSettings and hands it
 in. Adding a Load method on this contract would be speculative until a
 second caller actually needs it.}
unit uWcxSettingsRepository;

interface

uses
  uWcxSettings;

type
  IWcxSettingsRepository = interface
    ['{F0B5C92A-4D17-4E1A-9D2C-6CB6F0A78F11}']
    {Persists the mutated settings instance to its backing store.
     Production wraps TWcxSettings.Save (which writes to the instance's
     own FIniPath); fakes can record the call for assertion.}
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
