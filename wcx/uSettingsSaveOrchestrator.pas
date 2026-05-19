{Orchestrates the WCX settings save: validate, persist, fire on-apply.
 Returns a structured result the dialog renders (navigate-to-row,
 show message, or close).}
unit uSettingsSaveOrchestrator;

interface

uses
  System.SysUtils,
  uWcxSettings,
  uWcxPresets,
  uWcxPresetEditorModel,
  uWcxSettingsRepository,
  uWcxPresetsRepository;

type
  TSettingsSaveResultKind = (
    ssrValidationFailed,
    ssrSuccess,
    {ASettings was nil; no save happened so the on-apply callback must
     NOT fire. Distinct from ssrSuccess for that reason.}
    ssrSkipped);

  TSettingsSaveResult = record
    Kind: TSettingsSaveResultKind;
    {Populated only when Kind = ssrValidationFailed.}
    ValidationIndex: Integer;
    ValidationReason: string;
  end;

  TSettingsSaveOrchestrator = class
  public
    {APreparePersistence is the dialog's ControlsToSettings flush; it
     touches VCL controls and so cannot live in this unit. The dialog
     must call CommitCurrentPreset BEFORE invoking Run. APresetsRepo may
     be nil for callers without a presets backing store.}
    function Run(ASettings: TWcxSettings; APresetModel: TPresetEditorModel;
      const ASettingsRepo: IWcxSettingsRepository;
      const APresetsRepo: IWcxPresetsRepository;
      const APreparePersistence: TProc;
      const AOnApply: TProc): TSettingsSaveResult;
  end;

implementation

function TSettingsSaveOrchestrator.Run(ASettings: TWcxSettings;
  APresetModel: TPresetEditorModel;
  const ASettingsRepo: IWcxSettingsRepository;
  const APresetsRepo: IWcxPresetsRepository;
  const APreparePersistence: TProc; const AOnApply: TProc): TSettingsSaveResult;
begin
  Result.Kind := ssrSkipped;
  Result.ValidationIndex := -1;
  Result.ValidationReason := '';

  if ASettings = nil then
    Exit;

  if not APresetModel.ValidateForEditor(Result.ValidationIndex, Result.ValidationReason) then
  begin
    Result.Kind := ssrValidationFailed;
    Exit;
  end;

  if Assigned(APreparePersistence) then
    APreparePersistence();

  if ASettingsRepo <> nil then
    ASettingsRepo.Save(ASettings);
  if APresetsRepo <> nil then
    APresetsRepo.SaveAll(APresetModel.ToArray);

  if Assigned(AOnApply) then
    AOnApply();

  Result.Kind := ssrSuccess;
end;

end.
