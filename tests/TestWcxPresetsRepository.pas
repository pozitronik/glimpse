{Tests for TProductionWcxPresetsRepository — a thin seam over
 LoadAllPresets / SavePresets. Pins the contract that LoadAll returns
 what was last SaveAll-ed at the construction-captured path, and
 that an empty path is a defined no-op for both.}
unit TestWcxPresetsRepository;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxPresetsRepository = class
  private
    FTempDir: string;
    FPresetsPath: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure LoadAll_MissingFile_ReturnsEmptyArray;
    [Test] procedure SaveAll_LoadAll_RoundTripsPresetFields;
    [Test] procedure SaveAll_Twice_SecondSaveReplacesFirst;
    [Test] procedure EmptyPath_LoadAll_ReturnsEmpty_SaveAll_NoOp;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uWcxPresets, uWcxPresetsRepository;

procedure TTestWcxPresetsRepository.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_PresetsRepo_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FPresetsPath := TPath.Combine(FTempDir, 'presets.ini');
end;

procedure TTestWcxPresetsRepository.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestWcxPresetsRepository.LoadAll_MissingFile_ReturnsEmptyArray;
var
  Repo: IWcxPresetsRepository;
  Loaded: TWcxPresetArray;
begin
  Repo := TProductionWcxPresetsRepository.Create(FPresetsPath);
  Loaded := Repo.LoadAll;
  Assert.AreEqual<Integer>(0, Length(Loaded),
    'LoadAll on a missing file must return an empty array, not raise');
end;

procedure TTestWcxPresetsRepository.SaveAll_LoadAll_RoundTripsPresetFields;
var
  Repo: IWcxPresetsRepository;
  Seed, Loaded: TWcxPresetArray;
begin
  Repo := TProductionWcxPresetsRepository.Create(FPresetsPath);
  SetLength(Seed, 2);
  Seed[0].Name := 'alpha';
  Seed[0].Enabled := True;
  Seed[0].OutputExt := 'mp4';
  Seed[0].OutputName := '%name%';
  Seed[0].Args := '-c:v libx264';
  Seed[1].Name := 'beta';
  Seed[1].Enabled := False;
  Seed[1].OutputExt := 'mkv';

  Repo.SaveAll(Seed);
  Loaded := Repo.LoadAll;

  Assert.AreEqual<Integer>(2, Length(Loaded), 'Round-trip must preserve the preset count');
  Assert.AreEqual('alpha', Loaded[0].Name);
  Assert.IsTrue(Loaded[0].Enabled);
  Assert.AreEqual('mp4', Loaded[0].OutputExt);
  Assert.AreEqual('%name%', Loaded[0].OutputName);
  Assert.AreEqual('-c:v libx264', Loaded[0].Args);
  Assert.AreEqual('beta', Loaded[1].Name);
  Assert.IsFalse(Loaded[1].Enabled);
  Assert.AreEqual('mkv', Loaded[1].OutputExt);
end;

procedure TTestWcxPresetsRepository.SaveAll_Twice_SecondSaveReplacesFirst;
var
  Repo: IWcxPresetsRepository;
  First, Second, Loaded: TWcxPresetArray;
begin
  Repo := TProductionWcxPresetsRepository.Create(FPresetsPath);
  SetLength(First, 2);
  First[0].Name := 'one'; First[0].Enabled := True; First[0].OutputExt := 'mp4';
  First[1].Name := 'two'; First[1].Enabled := True; First[1].OutputExt := 'mkv';
  Repo.SaveAll(First);

  SetLength(Second, 1);
  Second[0].Name := 'only'; Second[0].Enabled := True; Second[0].OutputExt := 'webm';
  Repo.SaveAll(Second);

  Loaded := Repo.LoadAll;
  Assert.AreEqual<Integer>(1, Length(Loaded),
    'Second SaveAll must wipe the first; otherwise removed presets leak back into the file');
  Assert.AreEqual('only', Loaded[0].Name);
end;

procedure TTestWcxPresetsRepository.EmptyPath_LoadAll_ReturnsEmpty_SaveAll_NoOp;
var
  Repo: IWcxPresetsRepository;
  Seed, Loaded: TWcxPresetArray;
begin
  Repo := TProductionWcxPresetsRepository.Create('');
  SetLength(Seed, 1);
  Seed[0].Name := 'x'; Seed[0].Enabled := True; Seed[0].OutputExt := 'mp4';
  Repo.SaveAll(Seed);
  Loaded := Repo.LoadAll;
  Assert.AreEqual<Integer>(0, Length(Loaded),
    'Empty-path repo must behave as a no-op on both sides; matches the legacy free-function contract');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxPresetsRepository);

end.
