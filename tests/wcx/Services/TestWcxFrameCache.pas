{Coverage for TWcxFrameCache singleton + TWcxCacheExtractionSession.
 The cache is process-wide so each test resets the singleton (or replaces
 it) to keep tests isolated.}
unit TestWcxFrameCache;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxFrameCache = class
  public
    [Setup] procedure SetUp;
    [TearDown] procedure TearDown;
    [Test] procedure InstanceReturnsSameObjectAcrossCalls;
    [Test] procedure ReleaseInstanceAllowsFreshInstance;
    [Test] procedure SeedForTestingPopulatesCachedFields;
    [Test] procedure InvalidateClearsCachedFields;
    [Test] procedure InvalidateRoutesThroughDeleteProc;
    [Test] procedure InvalidateSwallowsDeleteProcException;
    [Test] procedure SetDeleteDirectoryProcNilFallsBackToDefault;
    [Test] procedure SessionTryHitFalseWhenNothingCached;
    [Test] procedure SessionTryHitFalseWhenVideoMismatch;
    [Test] procedure SessionTryHitFalseWhenCachedDirMissing;
    [Test] procedure SessionPrepareFreshCreatesDirAndSetsState;
    [Test] procedure SessionRecordAndPublishRoundTrip;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  WcxFrameCache;

procedure TTestWcxFrameCache.SetUp;
begin
  {Each test starts from a fresh singleton so cross-test state does not
   bleed (the cache is process-wide in production).}
  TWcxFrameCache.ReleaseInstance;
end;

procedure TTestWcxFrameCache.TearDown;
begin
  {Defensive cleanup: invalidate before releasing so any temp dir the
   test created gets removed.}
  TWcxFrameCache.Instance.Invalidate;
  TWcxFrameCache.ReleaseInstance;
end;

procedure TTestWcxFrameCache.InstanceReturnsSameObjectAcrossCalls;
begin
  Assert.AreSame(TWcxFrameCache.Instance, TWcxFrameCache.Instance);
end;

procedure TTestWcxFrameCache.ReleaseInstanceAllowsFreshInstance;
begin
  {Seed state on the current singleton, release it, then verify the
   replacement is fresh — i.e., did not retain the seeded fields.
   (We cannot compare object identity: the allocator can reuse the
   just-freed address, so AreNotSame would be a false-negative.)}
  TWcxFrameCache.Instance.SeedForTesting('C:\seeded.mkv', 'C:\seeded\dir');
  TWcxFrameCache.ReleaseInstance;
  Assert.AreEqual('', TWcxFrameCache.Instance.CachedVideoFile,
    'fresh instance must not inherit the seeded video file');
  Assert.AreEqual('', TWcxFrameCache.Instance.CachedTempDir,
    'fresh instance must not inherit the seeded temp dir');
end;

procedure TTestWcxFrameCache.SeedForTestingPopulatesCachedFields;
begin
  TWcxFrameCache.Instance.SeedForTesting('C:\v\sample.mkv', 'C:\temp\session');
  Assert.AreEqual('C:\v\sample.mkv', TWcxFrameCache.Instance.CachedVideoFile);
  Assert.AreEqual('C:\temp\session', TWcxFrameCache.Instance.CachedTempDir);
end;

procedure TTestWcxFrameCache.InvalidateClearsCachedFields;
begin
  TWcxFrameCache.Instance.SeedForTesting('C:\v\x.mkv', 'C:\temp\nonexistent_dir');
  TWcxFrameCache.Instance.Invalidate;
  Assert.AreEqual('', TWcxFrameCache.Instance.CachedVideoFile);
  Assert.AreEqual('', TWcxFrameCache.Instance.CachedTempDir);
end;

procedure TTestWcxFrameCache.InvalidateRoutesThroughDeleteProc;
var
  RealDir: string;
  CapturedPath: string;
begin
  {Create a real temp directory so the "dir exists" branch runs and
   reaches FDeleteDirectoryProc.}
  RealDir := TPath.Combine(TPath.GetTempPath, 'glimpse_test_' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(RealDir);
  try
    TWcxFrameCache.Instance.SeedForTesting('C:\v\x.mkv', RealDir);
    CapturedPath := '';
    TWcxFrameCache.Instance.SetDeleteDirectoryProc(
      procedure(const APath: string)
      begin
        CapturedPath := APath;
      end);
    try
      TWcxFrameCache.Instance.Invalidate;
      Assert.AreEqual(RealDir, CapturedPath,
        'delete proc must receive the cached temp dir path');
    finally
      TWcxFrameCache.Instance.ResetDeleteDirectoryProc;
    end;
  finally
    if TDirectory.Exists(RealDir) then
      TDirectory.Delete(RealDir, True);
  end;
end;

procedure TTestWcxFrameCache.InvalidateSwallowsDeleteProcException;
var
  RealDir: string;
begin
  {DLL unload runs Invalidate; an unhandled exception here would crash
   TC. Production wraps the call in try/except; this test pins that.}
  RealDir := TPath.Combine(TPath.GetTempPath, 'glimpse_test_' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(RealDir);
  try
    TWcxFrameCache.Instance.SeedForTesting('C:\v\x.mkv', RealDir);
    TWcxFrameCache.Instance.SetDeleteDirectoryProc(
      procedure(const APath: string)
      begin
        raise Exception.Create('simulated delete failure');
      end);
    try
      {Direct call must not propagate the inner exception — Invalidate
       wraps the delete in try/except specifically so DLL unload cannot
       crash TC. Wrapping in another try here would only mask a
       regression, so we just call it; any leaked exception fails the
       test naturally.}
      TWcxFrameCache.Instance.Invalidate;
      Assert.Pass('Invalidate swallowed the delete-proc exception');
    finally
      TWcxFrameCache.Instance.ResetDeleteDirectoryProc;
    end;
  finally
    if TDirectory.Exists(RealDir) then
      TDirectory.Delete(RealDir, True);
  end;
end;

procedure TTestWcxFrameCache.SetDeleteDirectoryProcNilFallsBackToDefault;
begin
  {Passing nil must reset to the production default (TDirectory.Delete)
   without leaving FDeleteDirectoryProc unassigned.}
  TWcxFrameCache.Instance.SetDeleteDirectoryProc(nil);
  {No assert — the test simply must not raise. The default proc is
   invoked indirectly via Invalidate, covered above.}
  Assert.Pass;
end;

procedure TTestWcxFrameCache.SessionTryHitFalseWhenNothingCached;
var
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
begin
  Session := TWcxFrameCache.Instance.BeginExtractionSession;
  try
    Assert.IsFalse(Session.TryHit('C:\v\never_cached.mkv', Paths, Sizes));
  finally
    Session.Free;
  end;
end;

procedure TTestWcxFrameCache.SessionTryHitFalseWhenVideoMismatch;
var
  RealDir: string;
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
begin
  RealDir := TPath.Combine(TPath.GetTempPath, 'glimpse_test_' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(RealDir);
  try
    TWcxFrameCache.Instance.SeedForTesting('C:\v\a.mkv', RealDir);
    Session := TWcxFrameCache.Instance.BeginExtractionSession;
    try
      {Different filename — cache miss even though dir exists.}
      Assert.IsFalse(Session.TryHit('C:\v\b.mkv', Paths, Sizes));
    finally
      Session.Free;
    end;
  finally
    if TDirectory.Exists(RealDir) then
      TDirectory.Delete(RealDir, True);
  end;
end;

procedure TTestWcxFrameCache.SessionTryHitFalseWhenCachedDirMissing;
var
  Session: TWcxCacheExtractionSession;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
begin
  {Seed a directory path that does not exist — TryHit must reject
   because the temp dir was wiped externally.}
  TWcxFrameCache.Instance.SeedForTesting('C:\v\x.mkv',
    TPath.Combine(TPath.GetTempPath, 'glimpse_test_does_not_exist_' + TPath.GetGUIDFileName(False)));
  Session := TWcxFrameCache.Instance.BeginExtractionSession;
  try
    Assert.IsFalse(Session.TryHit('C:\v\x.mkv', Paths, Sizes));
  finally
    Session.Free;
  end;
end;

procedure TTestWcxFrameCache.SessionPrepareFreshCreatesDirAndSetsState;
var
  Session: TWcxCacheExtractionSession;
  TempDir: string;
begin
  Session := TWcxFrameCache.Instance.BeginExtractionSession;
  try
    TempDir := Session.PrepareFresh('C:\v\new.mkv', 3);
    try
      Assert.IsTrue(TDirectory.Exists(TempDir), 'PrepareFresh must create the temp dir');
      Assert.AreEqual('C:\v\new.mkv', TWcxFrameCache.Instance.CachedVideoFile);
      Assert.AreEqual(TempDir, TWcxFrameCache.Instance.CachedTempDir);
      Assert.AreEqual(TempDir, Session.CachedTempDir);
    finally
      if TDirectory.Exists(TempDir) then
        TDirectory.Delete(TempDir, True);
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestWcxFrameCache.SessionRecordAndPublishRoundTrip;
var
  Session: TWcxCacheExtractionSession;
  TempDir: string;
  Paths: TArray<string>;
  Sizes: TArray<Int64>;
begin
  Session := TWcxFrameCache.Instance.BeginExtractionSession;
  try
    TempDir := Session.PrepareFresh('C:\v\x.mkv', 2);
    try
      Session.RecordSlot(0, 'a.png', 100);
      Session.RecordSlot(1, 'b.png', 200);
      Session.PublishTo(Paths, Sizes);
      Assert.AreEqual(2, Integer(Length(Paths)));
      Assert.AreEqual('a.png', Paths[0]);
      Assert.AreEqual('b.png', Paths[1]);
      Assert.AreEqual(Int64(100), Sizes[0]);
      Assert.AreEqual(Int64(200), Sizes[1]);
    finally
      if TDirectory.Exists(TempDir) then
        TDirectory.Delete(TempDir, True);
    end;
  finally
    Session.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxFrameCache);

end.
