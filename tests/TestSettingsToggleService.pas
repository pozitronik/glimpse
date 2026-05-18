unit TestSettingsToggleService;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsToggleService = class
  private
    FTempDir: string;
    FTempIniPath: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestPersistToolbarVisibleWritesToIni;
    [Test]
    procedure TestPersistStatusBarVisibleWritesToIni;
    [Test]
    procedure TestPersistTimecodeVisibleWritesToIni;
    [Test]
    procedure TestPersistedValueRoundTripsThroughTrueState;
    [Test]
    procedure TestServiceDoesNotChangeOtherFields;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uSettings, uSettingsToggleService;

procedure TTestSettingsToggleService.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_Test_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FTempIniPath := TPath.Combine(FTempDir, 'test.ini');
end;

procedure TTestSettingsToggleService.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestSettingsToggleService.TestPersistToolbarVisibleWritesToIni;
var
  S, S2: TPluginSettings;
  Svc: TSettingsToggleService;
begin
  {Service must mutate the targeted setting AND persist immediately so a
   crash between the toggle and the next Save would not lose the flip.
   Verify by reloading the ini through a fresh TPluginSettings instance.}
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Svc := TSettingsToggleService.Create(S);
    try
      Svc.PersistToolbarVisible(False);
    finally
      Svc.Free;
    end;
  finally
    S.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.IsFalse(S2.ShowToolbar, 'Service should persist ShowToolbar=False to disk');
  finally
    S2.Free;
  end;
end;

procedure TTestSettingsToggleService.TestPersistStatusBarVisibleWritesToIni;
var
  S, S2: TPluginSettings;
  Svc: TSettingsToggleService;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Svc := TSettingsToggleService.Create(S);
    try
      Svc.PersistStatusBarVisible(False);
    finally
      Svc.Free;
    end;
  finally
    S.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.IsFalse(S2.ShowStatusBar, 'Service should persist ShowStatusBar=False to disk');
  finally
    S2.Free;
  end;
end;

procedure TTestSettingsToggleService.TestPersistTimecodeVisibleWritesToIni;
var
  S, S2: TPluginSettings;
  Svc: TSettingsToggleService;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Svc := TSettingsToggleService.Create(S);
    try
      Svc.PersistTimecodeVisible(False);
    finally
      Svc.Free;
    end;
  finally
    S.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.IsFalse(S2.ShowTimecode, 'Service should persist ShowTimecode=False to disk');
  finally
    S2.Free;
  end;
end;

procedure TTestSettingsToggleService.TestPersistedValueRoundTripsThroughTrueState;
var
  S, S2: TPluginSettings;
  Svc: TSettingsToggleService;
begin
  {Catches a stuck-False bug: if the service short-circuited writes when the
   value matched, or hard-coded False, a True flip would silently fail to
   persist. Force the disk through False -> True, reload, expect True.}
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    Svc := TSettingsToggleService.Create(S);
    try
      Svc.PersistToolbarVisible(False);
      Svc.PersistToolbarVisible(True);
    finally
      Svc.Free;
    end;
  finally
    S.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.IsTrue(S2.ShowToolbar, 'Service should round-trip True after writing False then True');
  finally
    S2.Free;
  end;
end;

procedure TTestSettingsToggleService.TestServiceDoesNotChangeOtherFields;
var
  S, S2: TPluginSettings;
  Svc: TSettingsToggleService;
  OriginalFramesCount: Integer;
begin
  {The service is single-purpose. Verify it does not accidentally mutate
   non-targeted settings (e.g. via a bad property assignment in Save).
   Snapshot FramesCount, flip the toolbar, reload, expect FramesCount intact.}
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.Load;
    S.FramesCount := 7;
    S.Save;
    OriginalFramesCount := S.FramesCount;
    Svc := TSettingsToggleService.Create(S);
    try
      Svc.PersistToolbarVisible(False);
    finally
      Svc.Free;
    end;
  finally
    S.Free;
  end;

  S2 := TPluginSettings.Create(FTempIniPath);
  try
    S2.Load;
    Assert.AreEqual(OriginalFramesCount, S2.FramesCount,
      'PersistToolbarVisible should not modify unrelated FramesCount');
  finally
    S2.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsToggleService);

end.
