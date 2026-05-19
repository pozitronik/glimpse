unit TestSettingsSaveOrchestrator;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsSaveOrchestrator = class
  private
    FTempDir: string;
    FIniPath: string;
    FPresetsPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Run_NilSettings_ReturnsSkipped;
    [Test] procedure Run_ValidationFails_ReturnsValidationFailedWithReason;
    [Test] procedure Run_ValidationFails_DoesNotCallPreparePersistence;
    [Test] procedure Run_ValidationFails_DoesNotFireOnApply;
    [Test] procedure Run_HappyPath_CallsPreparePersistenceThenPersistsThenFiresApply;
    [Test] procedure Run_HappyPath_EmptyPresetsPath_SkipsPresetSave;
    [Test] procedure Run_HappyPath_NilOnApply_DoesNotRaise;
    [Test] procedure Run_HappyPath_WritesSettingsIniToDisk;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uWcxSettings, uWcxPresets, uWcxPresetEditorModel,
  uSettingsSaveOrchestrator;

procedure TTestSettingsSaveOrchestrator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_SaveOrch_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FIniPath := TPath.Combine(FTempDir, 'wcx.ini');
  FPresetsPath := TPath.Combine(FTempDir, 'presets.ini');
end;

procedure TTestSettingsSaveOrchestrator.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestSettingsSaveOrchestrator.Run_NilSettings_ReturnsSkipped;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  R: TSettingsSaveResult;
begin
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    R := Orch.Run(nil, Model, '', nil, nil);
    Assert.IsTrue(R.Kind = ssrSkipped, 'Nil settings -> ssrSkipped');
  finally
    Orch.Free;
    Model.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_ValidationFails_ReturnsValidationFailedWithReason;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  R: TSettingsSaveResult;
  Bad: TWcxPresetArray;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    {Two presets with the same name trigger the editor's duplicate-name
     rule; ValidateForEditor blames the later one (index 1).}
    SetLength(Bad, 2);
    Bad[0].Name := 'dup'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'dup'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    R := Orch.Run(S, Model, FPresetsPath, nil, nil);
    Assert.IsTrue(R.Kind = ssrValidationFailed, 'Duplicate name -> ssrValidationFailed');
    Assert.AreEqual(1, R.ValidationIndex, 'Blame the later duplicate');
    Assert.IsTrue(Pos('used by another preset', R.ValidationReason) > 0,
      'Reason mentions the duplicate-name rule');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_ValidationFails_DoesNotCallPreparePersistence;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  Bad: TWcxPresetArray;
  PrepareCalled: Boolean;
begin
  PrepareCalled := False;
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    SetLength(Bad, 2);
    Bad[0].Name := 'X'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'X'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    Orch.Run(S, Model, FPresetsPath,
      procedure begin PrepareCalled := True end,
      nil);
    Assert.IsFalse(PrepareCalled,
      'Validation failure must short-circuit before PreparePersistence');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_ValidationFails_DoesNotFireOnApply;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  Bad: TWcxPresetArray;
  AppliedCount: Integer;
begin
  AppliedCount := 0;
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    SetLength(Bad, 2);
    Bad[0].Name := 'X'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'X'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    Orch.Run(S, Model, FPresetsPath, nil,
      procedure begin Inc(AppliedCount) end);
    Assert.AreEqual(0, AppliedCount,
      'OnApply must not fire when validation failed');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_CallsPreparePersistenceThenPersistsThenFiresApply;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  R: TSettingsSaveResult;
  Sequence: string;
begin
  Sequence := '';
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    R := Orch.Run(S, Model, FPresetsPath,
      procedure begin Sequence := Sequence + 'P' end,
      procedure begin Sequence := Sequence + 'A' end);
    Assert.IsTrue(R.Kind = ssrSuccess);
    Assert.AreEqual('PA', Sequence,
      'PreparePersistence (P) must run BEFORE Persist (S.Save happens in between) and OnApply (A) fires last');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_EmptyPresetsPath_SkipsPresetSave;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  R: TSettingsSaveResult;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    R := Orch.Run(S, Model, '', nil, nil);
    Assert.IsTrue(R.Kind = ssrSuccess);
    Assert.IsFalse(TFile.Exists(FPresetsPath),
      'Empty presets path must skip the preset-file write');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_NilOnApply_DoesNotRaise;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  R: TSettingsSaveResult;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    R := Orch.Run(S, Model, FPresetsPath, nil, nil);
    Assert.IsTrue(R.Kind = ssrSuccess, 'Nil OnApply is valid; orchestrator must guard');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_WritesSettingsIniToDisk;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  try
    Orch.Run(S, Model, FPresetsPath, nil, nil);
    Assert.IsTrue(TFile.Exists(FIniPath),
      'Settings.Save must produce the ini file');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsSaveOrchestrator);

end.
