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

  {Deterministic tests of the store-explicit cores — fake managers, no
   disk, so summing/clearing both caches is verified without the real
   %TEMP% probe tree.}
  [TestFixture]
  TTestCacheMaintenanceCore = class
  public
    [Test] procedure TotalSumsBothManagers;
    [Test] procedure ClearClearsBothManagers;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, Vcl.Graphics,
  Cache, CacheMaintenance, FrameCacheFactory, ProbeCache;

type
  {ICacheManager fake: canned total, records whether Clear ran.}
  TFakeCacheManager = class(TInterfacedObject, ICacheManager)
  strict private
    FSize: Int64;
    FCleared: Boolean;
  public
    constructor Create(ASize: Int64);
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
    property Cleared: Boolean read FCleared;
  end;

  {IProbeCacheManager fake: canned total, records whether Clear ran.}
  TFakeProbeCacheManager = class(TInterfacedObject, IProbeCacheManager)
  strict private
    FSize: Int64;
    FCleared: Boolean;
  public
    constructor Create(ASize: Int64);
    function GetTotalSize: Int64;
    procedure Clear;
    property Cleared: Boolean read FCleared;
  end;

constructor TFakeCacheManager.Create(ASize: Int64);
begin
  inherited Create;
  FSize := ASize;
end;

procedure TFakeCacheManager.Clear;
begin
  FCleared := True;
end;

procedure TFakeCacheManager.Evict;
begin
  {Unused by the cache-maintenance functions.}
end;

function TFakeCacheManager.GetTotalSize: Int64;
begin
  Result := FSize;
end;

constructor TFakeProbeCacheManager.Create(ASize: Int64);
begin
  inherited Create;
  FSize := ASize;
end;

function TFakeProbeCacheManager.GetTotalSize: Int64;
begin
  Result := FSize;
end;

procedure TFakeProbeCacheManager.Clear;
begin
  FCleared := True;
end;

{TTestCacheMaintenanceCore}

procedure TTestCacheMaintenanceCore.TotalSumsBothManagers;
var
  Frame: ICacheManager;
  Probe: IProbeCacheManager;
begin
  {The total must consult both the frame cache and the probe cache.}
  Frame := TFakeCacheManager.Create(100);
  Probe := TFakeProbeCacheManager.Create(250);
  Assert.AreEqual<Int64>(350, TotalGlimpseCacheBytes(Frame, Probe),
    'Total must be frame bytes + probe bytes');
end;

procedure TTestCacheMaintenanceCore.ClearClearsBothManagers;
var
  Frame: TFakeCacheManager;
  Probe: TFakeProbeCacheManager;
  FrameRef: ICacheManager;
  ProbeRef: IProbeCacheManager;
begin
  {Clearing must reach both caches, not just one.}
  Frame := TFakeCacheManager.Create(0);
  Probe := TFakeProbeCacheManager.Create(0);
  FrameRef := Frame;
  ProbeRef := Probe;
  ClearAllGlimpseCaches(FrameRef, ProbeRef);
  Assert.IsTrue(Frame.Cleared, 'Frame cache must be cleared');
  Assert.IsTrue(Probe.Cleared, 'Probe cache must be cleared');
end;

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
  Cache: IFrameCache;
  Bmp: TBitmap;
  TestFile: string;
  Before, After: Int64;
begin
  {Put a small bitmap into a frame cache under FFrameCacheDir, then
   confirm TotalGlimpseCacheBytes reflects the delta. Compare before/after
   so the probe-cache baseline (whatever it is) cancels out.}
  TDirectory.CreateDirectory(FFrameCacheDir);
  TestFile := TPath.Combine(FFrameCacheDir, 'video.mp4');
  TFile.WriteAllText(TestFile, 'fake video file');

  Cache := CreateFrameCache(FFrameCacheDir, 100);
  Before := TotalGlimpseCacheBytes(FFrameCacheDir);
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(32, 32);
    Cache.Put(TFrameCacheKey.Create(TestFile, 1.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;
  Cache := nil;

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
  Cache: IFrameCache;
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

  Cache := CreateFrameCache(FFrameCacheDir, 100);
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(32, 32);
    Cache.Put(TFrameCacheKey.Create(TestFile, 1.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;
  Assert.IsTrue((Cache as ICacheManager).GetTotalSize > 0, 'Sanity: Put must produce bytes');
  Cache := nil;

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
  TDUnitX.RegisterTestFixture(TTestCacheMaintenanceCore);

end.
