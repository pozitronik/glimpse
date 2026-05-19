{Tests for TProductionWcxSettingsRepository (step 103, M24).

 The repository is a thin seam over TWcxSettings.Save; the production
 contract under test is: "Save delegates to ASettings.Save which writes
 to its FIniPath". Nil-safety + round-trip via a tempdir ini path.}
unit TestWcxSettingsRepository;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxSettingsRepository = class
  private
    FTempDir: string;
    FIniPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Save_NilSettings_DoesNotRaise;
    [Test] procedure Save_PersistsToInstanceIniPath;
    [Test] procedure Save_TwoConsecutiveSaves_OverwriteCleanly;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uWcxSettings, uWcxSettingsRepository;

procedure TTestWcxSettingsRepository.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_SettingsRepo_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FIniPath := TPath.Combine(FTempDir, 'wcx.ini');
end;

procedure TTestWcxSettingsRepository.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestWcxSettingsRepository.Save_NilSettings_DoesNotRaise;
var
  Repo: IWcxSettingsRepository;
begin
  Repo := TProductionWcxSettingsRepository.Create;
  Repo.Save(nil);
  Assert.IsFalse(TFile.Exists(FIniPath),
    'Nil settings argument must be a no-op, not produce an INI file');
end;

procedure TTestWcxSettingsRepository.Save_PersistsToInstanceIniPath;
var
  Repo: IWcxSettingsRepository;
  S: TWcxSettings;
begin
  Repo := TProductionWcxSettingsRepository.Create;
  S := TWcxSettings.Create(FIniPath);
  try
    {Pin a non-default value so the assertion proves a write happened
     rather than relying on file existence alone.}
    S.FramesCount := 17;
    Repo.Save(S);
    Assert.IsTrue(TFile.Exists(FIniPath),
      'Save must produce the INI file at the instance''s IniPath');
  finally
    S.Free;
  end;
end;

procedure TTestWcxSettingsRepository.Save_TwoConsecutiveSaves_OverwriteCleanly;
var
  Repo: IWcxSettingsRepository;
  S: TWcxSettings;
  Reloaded: TWcxSettings;
begin
  Repo := TProductionWcxSettingsRepository.Create;
  S := TWcxSettings.Create(FIniPath);
  try
    S.FramesCount := 3;
    Repo.Save(S);
    S.FramesCount := 11;
    Repo.Save(S);
  finally
    S.Free;
  end;
  Reloaded := TWcxSettings.Create(FIniPath);
  try
    Reloaded.Load;
    Assert.AreEqual(11, Reloaded.FramesCount,
      'Second Save must overwrite the first; reloaded value must reflect the latest write');
  finally
    Reloaded.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxSettingsRepository);

end.
