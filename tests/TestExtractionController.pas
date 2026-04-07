unit TestExtractionController;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExtractionController = class
  public
    [Test] procedure TestCreateDestroy;
    [Test] procedure TestStopWhenNoThreads;
    [Test] procedure TestDrainWhenEmpty;
    [Test] procedure TestRecreateCacheEnabled;
    [Test] procedure TestRecreateCacheDisabled;
    [Test] procedure TestInitialFramesLoadedZero;
    [Test] procedure TestInitialTotalFramesZero;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uCache, uExtractionController;

{ TTestExtractionController }

procedure TTestExtractionController.TestCreateDestroy;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    Assert.IsNotNull(Ctrl);
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestStopWhenNoThreads;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    { Stop with no running threads must not crash }
    Ctrl.Stop;
    Ctrl.Stop;
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestDrainWhenEmpty;
var
  Ctrl: TExtractionController;
begin
  { FormHandle=0 skips PeekMessage calls }
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    Ctrl.DrainPendingFrameMessages;
    Ctrl.DrainPendingFrameMessages;
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestRecreateCacheEnabled;
var
  Ctrl: TExtractionController;
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'glimpse_ctrl_test_' + IntToStr(Random(MaxInt)));
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    Ctrl.RecreateCache(True, Dir, 100);
    { After recreation, cache should be functional (not null) }
    Assert.IsNotNull(Ctrl.Cache);
    { Put/TryGet round-trip is verified by TestCache, here just check
      the controller wired it correctly }
  finally
    Ctrl.Free;
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestExtractionController.TestRecreateCacheDisabled;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    Ctrl.RecreateCache(False, '', 0);
    { Null cache always misses }
    Assert.IsNull(Ctrl.Cache.TryGet('nonexistent.mp4', 1.0, 0));
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestInitialFramesLoadedZero;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    Assert.AreEqual(0, Ctrl.FramesLoaded);
  finally
    Ctrl.Free;
  end;
end;

procedure TTestExtractionController.TestInitialTotalFramesZero;
var
  Ctrl: TExtractionController;
begin
  Ctrl := TExtractionController.Create(0, TNullFrameCache.Create);
  try
    Assert.AreEqual(0, Ctrl.TotalFrames);
  finally
    Ctrl.Free;
  end;
end;

end.
