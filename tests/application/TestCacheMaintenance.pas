unit TestCacheMaintenance;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCacheMaintenance = class
  private
    FTempDir: string;
    FFrameCacheDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestTotalBytes_EmptyFrameDir_ReturnsAtLeastZero;
    [Test] procedure TestTotalBytes_NonexistentFrameDir_StillIncludesProbeCache;
    [Test] procedure TestTotalBytes_AfterFrameCachePut_IncludesPutBytes;
    [Test] procedure TestClearAll_EmptyFrameDir_DoesNotRaise;
    [Test] procedure TestClearAll_AfterPut_DropsFrameCacheTotalToZero;
    [Test] procedure TestClearAll_NonexistentFrameDir_DoesNotRaise;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, Vcl.Graphics,
  Cache, CacheMaintenance;

procedure TTestCacheMaintenance.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_CacheMaint_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FFrameCacheDir := TPath.Combine(FTempDir, 'frames');
end;

procedure TTestCacheMaintenance.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestCacheMaintenance.TestTotalBytes_EmptyFrameDir_ReturnsAtLeastZero;
var
  Total: Int64;
begin
  {Frame dir doesn't exist yet; probe cache may have leftover bytes from
   prior sessions in the user's %TEMP%. Total must be a valid Int64
   (>= 0) and the call must not raise.}
  Total := TotalGlimpseCacheBytes(FFrameCacheDir);
  Assert.IsTrue(Total >= 0, 'Total must be non-negative');
end;

procedure TTestCacheMaintenance.TestTotalBytes_NonexistentFrameDir_StillIncludesProbeCache;
begin
  {Just verifies the function returns without raising when the frame dir
   is missing; the probe-cache contribution is environment-dependent.}
  TotalGlimpseCacheBytes('Z:\definitely\not\here');
  Assert.Pass('TotalGlimpseCacheBytes must tolerate a missing frame dir');
end;

procedure TTestCacheMaintenance.TestTotalBytes_AfterFrameCachePut_IncludesPutBytes;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  TestFile, NewPath: string;
  Before, After: Int64;
begin
  {Put a small bitmap into a frame cache under FFrameCacheDir, then
   confirm TotalGlimpseCacheBytes reflects the delta. Compare before/after
   so the probe-cache baseline (whatever it is) cancels out.}
  TDirectory.CreateDirectory(FFrameCacheDir);
  TestFile := TPath.Combine(FFrameCacheDir, 'video.mp4');
  TFile.WriteAllText(TestFile, 'fake video file');

  Cache := TFrameCache.Create(FFrameCacheDir, 100);
  try
    Before := TotalGlimpseCacheBytes(FFrameCacheDir);
    Bmp := TBitmap.Create;
    try
      Bmp.SetSize(32, 32);
      Cache.Put(TFrameCacheKey.Create(TestFile, 1.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;
  finally
    Cache.Free;
  end;

  After := TotalGlimpseCacheBytes(FFrameCacheDir);
  Assert.IsTrue(After > Before,
    Format('After (%d) must exceed Before (%d) - the Put bytes should land in the total', [After, Before]));
end;

procedure TTestCacheMaintenance.TestClearAll_EmptyFrameDir_DoesNotRaise;
begin
  TDirectory.CreateDirectory(FFrameCacheDir);
  ClearAllGlimpseCaches(FFrameCacheDir);
  Assert.Pass('ClearAllGlimpseCaches must tolerate an empty frame dir');
end;

procedure TTestCacheMaintenance.TestClearAll_AfterPut_DropsFrameCacheTotalToZero;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  TestFile: string;
  Mgr: ICacheManager;
begin
  {Put a bitmap, confirm the frame cache reports non-zero bytes,
   ClearAllGlimpseCaches, confirm the frame cache reports zero.
   Use the cache manager directly for the frame-cache size measurement
   so the probe-cache contribution doesn't muddy the assertion.}
  TDirectory.CreateDirectory(FFrameCacheDir);
  TestFile := TPath.Combine(FFrameCacheDir, 'video.mp4');
  TFile.WriteAllText(TestFile, 'fake video file');

  Cache := TFrameCache.Create(FFrameCacheDir, 100);
  try
    Bmp := TBitmap.Create;
    try
      Bmp.SetSize(32, 32);
      Cache.Put(TFrameCacheKey.Create(TestFile, 1.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;
    Assert.IsTrue(Cache.GetTotalSize > 0, 'Sanity: Put must produce bytes');
  finally
    Cache.Free;
  end;

  ClearAllGlimpseCaches(FFrameCacheDir);

  Mgr := CreateCacheManager(FFrameCacheDir, 0);
  Assert.AreEqual<Int64>(0, Mgr.GetTotalSize,
    'After ClearAllGlimpseCaches the frame cache must be empty');
end;

procedure TTestCacheMaintenance.TestClearAll_NonexistentFrameDir_DoesNotRaise;
begin
  ClearAllGlimpseCaches('Z:\definitely\not\here');
  Assert.Pass('ClearAllGlimpseCaches must tolerate a missing frame dir');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCacheMaintenance);

end.
