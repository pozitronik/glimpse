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
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Run_NilSettings_ReturnsSkipped;
    [Test] procedure Run_ValidationFails_ReturnsValidationFailedWithReason;
    [Test] procedure Run_ValidationFails_DoesNotCallPreparePersistence;
    [Test] procedure Run_ValidationFails_DoesNotFireOnApply;
    [Test] procedure Run_ValidationFails_DoesNotInvokeRepositories;
    [Test] procedure Run_HappyPath_CallsPreparePersistenceThenPersistsThenFiresApply;
    [Test] procedure Run_HappyPath_SettingsRepoSavesExactlyOnceWithProvidedInstance;
    [Test] procedure Run_HappyPath_PresetsRepoSavesExactlyOnceWithModelArray;
    [Test] procedure Run_HappyPath_NilPresetsRepo_DoesNotRaise_StillFiresApply;
    [Test] procedure Run_HappyPath_NilSettingsRepo_DoesNotRaise_StillFiresApply;
    [Test] procedure Run_HappyPath_NilOnApply_DoesNotRaise;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  WcxSettings, WcxPresets, WcxPresetEditorModel,
  WcxSettingsRepository, WcxPresetsRepository,
  SettingsSaveOrchestrator;

type
  {Recording fake settings repository. Captures whether Save was called
   and against which TWcxSettings instance, so the happy-path tests can
   pin orchestrator -> repository delegation without touching disk.}
  TFakeSettingsRepo = class(TInterfacedObject, IWcxSettingsRepository)
  strict private
    FSaveCount: Integer;
    FLastInstance: TWcxSettings;
  public
    procedure Save(ASettings: TWcxSettings);
    property SaveCount: Integer read FSaveCount;
    property LastInstance: TWcxSettings read FLastInstance;
  end;

  {Recording fake presets writer: SaveAll records the call count + the
   persisted array length + a copy of the array so assertions can pin
   per-element fields. The orchestrator only writes.}
  TFakePresetsRepo = class(TInterfacedObject, IWcxPresetsWriter)
  strict private
    FSaveCount: Integer;
    FLastSaved: TWcxPresetArray;
  public
    procedure SaveAll(const APresets: TWcxPresetArray);
    property SaveCount: Integer read FSaveCount;
    property LastSaved: TWcxPresetArray read FLastSaved;
  end;

{TFakeSettingsRepo}

procedure TFakeSettingsRepo.Save(ASettings: TWcxSettings);
begin
  Inc(FSaveCount);
  FLastInstance := ASettings;
end;

{TFakePresetsRepo}

procedure TFakePresetsRepo.SaveAll(const APresets: TWcxPresetArray);
var
  I: Integer;
begin
  Inc(FSaveCount);
  SetLength(FLastSaved, Length(APresets));
  for I := 0 to High(APresets) do
    FLastSaved[I] := APresets[I];
end;

procedure TTestSettingsSaveOrchestrator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_SaveOrch_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FIniPath := TPath.Combine(FTempDir, 'wcx.ini');
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
  SettingsRepoObj: TFakeSettingsRepo;
  PresetsRepoObj: TFakePresetsRepo;
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  R: TSettingsSaveResult;
begin
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepoObj := TFakeSettingsRepo.Create;
  SettingsRepo := SettingsRepoObj;
  PresetsRepoObj := TFakePresetsRepo.Create;
  PresetsRepo := PresetsRepoObj;
  try
    R := Orch.Run(nil, Model, SettingsRepo, PresetsRepo, nil, nil);
    Assert.IsTrue(R.Kind = ssrSkipped, 'Nil settings -> ssrSkipped');
    Assert.AreEqual(0, SettingsRepoObj.SaveCount,
      'Skipped flow must not invoke the settings repo');
    Assert.AreEqual(0, PresetsRepoObj.SaveCount,
      'Skipped flow must not invoke the presets repo');
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
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  R: TSettingsSaveResult;
  Bad: TWcxPresetArray;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepo := TFakeSettingsRepo.Create;
  PresetsRepo := TFakePresetsRepo.Create;
  try
    {Two presets with the same name trigger the editor's duplicate-name
     rule; ValidateForEditor blames the later one (index 1).}
    SetLength(Bad, 2);
    Bad[0].Name := 'dup'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'dup'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    R := Orch.Run(S, Model, SettingsRepo, PresetsRepo, nil, nil);
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
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  Bad: TWcxPresetArray;
  PrepareCalled: Boolean;
begin
  PrepareCalled := False;
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepo := TFakeSettingsRepo.Create;
  PresetsRepo := TFakePresetsRepo.Create;
  try
    SetLength(Bad, 2);
    Bad[0].Name := 'X'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'X'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    Orch.Run(S, Model, SettingsRepo, PresetsRepo,
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
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  Bad: TWcxPresetArray;
  AppliedCount: Integer;
begin
  AppliedCount := 0;
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepo := TFakeSettingsRepo.Create;
  PresetsRepo := TFakePresetsRepo.Create;
  try
    SetLength(Bad, 2);
    Bad[0].Name := 'X'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'X'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    Orch.Run(S, Model, SettingsRepo, PresetsRepo, nil,
      procedure begin Inc(AppliedCount) end);
    Assert.AreEqual(0, AppliedCount,
      'OnApply must not fire when validation failed');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_ValidationFails_DoesNotInvokeRepositories;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  SettingsRepoObj: TFakeSettingsRepo;
  PresetsRepoObj: TFakePresetsRepo;
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  Bad: TWcxPresetArray;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepoObj := TFakeSettingsRepo.Create;
  SettingsRepo := SettingsRepoObj;
  PresetsRepoObj := TFakePresetsRepo.Create;
  PresetsRepo := PresetsRepoObj;
  try
    SetLength(Bad, 2);
    Bad[0].Name := 'X'; Bad[0].Enabled := True; Bad[0].OutputExt := 'mp4';
    Bad[1].Name := 'X'; Bad[1].Enabled := True; Bad[1].OutputExt := 'mkv';
    Model.LoadFrom(Bad);

    Orch.Run(S, Model, SettingsRepo, PresetsRepo, nil, nil);
    Assert.AreEqual(0, SettingsRepoObj.SaveCount,
      'Validation failure must short-circuit before settings repo Save');
    Assert.AreEqual(0, PresetsRepoObj.SaveCount,
      'Validation failure must short-circuit before presets repo SaveAll');
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
  SettingsRepoObj: TFakeSettingsRepo;
  PresetsRepoObj: TFakePresetsRepo;
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  R: TSettingsSaveResult;
  Sequence: string;
begin
  Sequence := '';
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepoObj := TFakeSettingsRepo.Create;
  SettingsRepo := SettingsRepoObj;
  PresetsRepoObj := TFakePresetsRepo.Create;
  PresetsRepo := PresetsRepoObj;
  try
    R := Orch.Run(S, Model, SettingsRepo, PresetsRepo,
      procedure begin Sequence := Sequence + 'P' end,
      procedure begin Sequence := Sequence + 'A' end);
    Assert.IsTrue(R.Kind = ssrSuccess);
    Assert.AreEqual('PA', Sequence,
      'PreparePersistence (P) must run BEFORE persistence (between P and A) and OnApply (A) fires last');
    Assert.AreEqual(1, SettingsRepoObj.SaveCount, 'Settings repo Save called exactly once');
    Assert.AreEqual(1, PresetsRepoObj.SaveCount, 'Presets repo SaveAll called exactly once');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_SettingsRepoSavesExactlyOnceWithProvidedInstance;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  SettingsRepoObj: TFakeSettingsRepo;
  PresetsRepoObj: TFakePresetsRepo;
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepoObj := TFakeSettingsRepo.Create;
  SettingsRepo := SettingsRepoObj;
  PresetsRepoObj := TFakePresetsRepo.Create;
  PresetsRepo := PresetsRepoObj;
  try
    Orch.Run(S, Model, SettingsRepo, PresetsRepo, nil, nil);
    Assert.AreEqual(1, SettingsRepoObj.SaveCount,
      'Settings repo must be invoked exactly once per successful Run');
    Assert.AreSame(S, SettingsRepoObj.LastInstance,
      'Settings repo must receive the exact instance threaded into Run');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_PresetsRepoSavesExactlyOnceWithModelArray;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  SettingsRepoObj: TFakeSettingsRepo;
  PresetsRepoObj: TFakePresetsRepo;
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  Seed: TWcxPresetArray;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepoObj := TFakeSettingsRepo.Create;
  SettingsRepo := SettingsRepoObj;
  PresetsRepoObj := TFakePresetsRepo.Create;
  PresetsRepo := PresetsRepoObj;
  try
    SetLength(Seed, 1);
    Seed[0].Name := 'alpha'; Seed[0].Enabled := True; Seed[0].OutputExt := 'mp4';
    Model.LoadFrom(Seed);

    Orch.Run(S, Model, SettingsRepo, PresetsRepo, nil, nil);
    Assert.AreEqual(1, PresetsRepoObj.SaveCount,
      'Presets repo SaveAll must be invoked exactly once per successful Run');
    Assert.AreEqual<Integer>(1, Length(PresetsRepoObj.LastSaved),
      'Presets repo SaveAll must receive the model''s array verbatim');
    Assert.AreEqual('alpha', PresetsRepoObj.LastSaved[0].Name,
      'Presets repo SaveAll must receive the model''s array contents');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_NilPresetsRepo_DoesNotRaise_StillFiresApply;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  SettingsRepo: IWcxSettingsRepository;
  R: TSettingsSaveResult;
  Applied: Boolean;
begin
  Applied := False;
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepo := TFakeSettingsRepo.Create;
  try
    R := Orch.Run(S, Model, SettingsRepo, nil, nil,
      procedure begin Applied := True end);
    Assert.IsTrue(R.Kind = ssrSuccess, 'Nil presets repo is valid; orchestrator must guard');
    Assert.IsTrue(Applied, 'OnApply must still fire when presets repo is nil');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

procedure TTestSettingsSaveOrchestrator.Run_HappyPath_NilSettingsRepo_DoesNotRaise_StillFiresApply;
var
  Orch: TSettingsSaveOrchestrator;
  Model: TPresetEditorModel;
  S: TWcxSettings;
  PresetsRepo: IWcxPresetsWriter;
  R: TSettingsSaveResult;
  Applied: Boolean;
begin
  Applied := False;
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  PresetsRepo := TFakePresetsRepo.Create;
  try
    R := Orch.Run(S, Model, nil, PresetsRepo, nil,
      procedure begin Applied := True end);
    Assert.IsTrue(R.Kind = ssrSuccess, 'Nil settings repo is valid; orchestrator must guard');
    Assert.IsTrue(Applied, 'OnApply must still fire when settings repo is nil');
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
  SettingsRepo: IWcxSettingsRepository;
  PresetsRepo: IWcxPresetsWriter;
  R: TSettingsSaveResult;
begin
  S := TWcxSettings.Create(FIniPath);
  Model := TPresetEditorModel.Create;
  Orch := TSettingsSaveOrchestrator.Create;
  SettingsRepo := TFakeSettingsRepo.Create;
  PresetsRepo := TFakePresetsRepo.Create;
  try
    R := Orch.Run(S, Model, SettingsRepo, PresetsRepo, nil, nil);
    Assert.IsTrue(R.Kind = ssrSuccess, 'Nil OnApply is valid; orchestrator must guard');
  finally
    Orch.Free;
    Model.Free;
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsSaveOrchestrator);

end.
