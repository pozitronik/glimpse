{Orchestrates the "save the WCX settings dialog" use case.

 The dialog's TrySaveAll used to mix validation orchestration with
 navigation, persistence, callback firing, and message-box UI. This
 orchestrator pulls the domain steps (validate + persist + fire-apply)
 into a single Run method that returns a structured result; the dialog
 then renders the result by navigating to the bad row, showing a
 message box, or doing nothing on success.

 Run's "PreparePersistence" callback lets the dialog hook in its
 `ControlsToSettings(FSettings)` step between validation success and
 persistence — that copy operation reaches into VCL controls and
 belongs to the dialog, not the orchestrator.

 Lives in wcx/ because the WCX preset model is one of its inputs;
 a future WLX analogue could reuse the same pattern if its dialog
 grows the same shape.}
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
    {Validation failed; ValidationIndex + ValidationReason populated.
     The dialog navigates to the offending preset row and shows the
     reason in a message box.}
    ssrValidationFailed,
    {Persistence succeeded and the on-apply callback (if any) fired.
     The dialog closes / returns True.}
    ssrSuccess,
    {The settings instance was nil — nothing to do. The dialog falls
     through without raising. Distinguished from ssrSuccess because the
     on-apply callback should NOT fire when no save happened.}
    ssrSkipped);

  TSettingsSaveResult = record
    Kind: TSettingsSaveResultKind;
    {Index of the failing preset for ssrValidationFailed. Undefined
     for other kinds.}
    ValidationIndex: Integer;
    {Human-readable validation failure message for ssrValidationFailed.
     Empty for other kinds.}
    ValidationReason: string;
  end;

  TSettingsSaveOrchestrator = class
  public
    {Validates the preset model, lets the caller prepare the settings
     instance via APreparePersistence, persists settings + presets, and
     fires AOnApply on success. Returns a structured result the dialog
     renders.

     Sequence:
       1. If ASettings is nil -> ssrSkipped (no callback fired).
       2. APresetModel.ValidateForEditor -> on fail return
          ssrValidationFailed with the offending index + reason.
       3. APreparePersistence() runs (dialog's ControlsToSettings flush).
          May be nil if the caller has no pre-persist hook.
       4. ASettingsRepo.Save(ASettings) persists the WCX ini.
       5. APresetsRepo.SaveAll(APresetModel.ToArray) persists the
          presets ini. May be nil for callers that have no presets
          backing store (e.g. minimal dialog wiring); the orchestrator
          guards against it.
       6. AOnApply() if assigned.
       7. Return ssrSuccess.

     CommitCurrentPreset (the dialog's "flush the right-pane edit fields
     into the model" call) is NOT done here — it operates on VCL controls
     and belongs to the dialog, which calls it BEFORE invoking Run.}
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
