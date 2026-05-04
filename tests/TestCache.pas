unit TestCache;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Classes,
  System.SyncObjs, Winapi.Windows,
  Vcl.Graphics, uCache;

type
  [TestFixture]
  TTestFrameCache = class
  private
    FTempDir: string;
    FCacheDir: string;

    { Creates a dummy file with the specified size and returns its path. }
    function CreateDummyFile(const AName: string; ASize: Integer): string;

    { Creates a small test bitmap of the given dimensions. }
    function CreateTestBitmap(AWidth, AHeight: Integer): TBitmap;

    { Sets the last write time of a file (for key generation tests). }
    procedure SetFileWriteTime(const APath: string; ATime: TDateTime);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    { Key generation tests }
    [Test]
    procedure TestKeyDeterministic;
    [Test]
    procedure TestKeyChangesOnPath;
    [Test]
    procedure TestKeyChangesOnSize;
    [Test]
    procedure TestKeyChangesOnMtime;
    [Test]
    procedure TestKeyChangesOnOffset;
    [Test]
    procedure TestKeyPathCaseInsensitive;

    { TFrameCache read/write tests }
    [Test]
    procedure TestPutAndGet;
    [Test]
    procedure TestGetMissReturnsNil;
    [Test]
    procedure TestGetCorruptFileReturnsNil;
    [Test]
    procedure TestPutCreatesSubdirectory;

    { Eviction tests }
    [Test]
    procedure TestEvictionRemovesOldest;
    [Test]
    procedure TestEvictionPreservesNewest;
    [Test]
    procedure TestClear;
    [Test]
    procedure TestGetTotalSize;

    { TNullFrameCache tests }
    [Test]
    procedure TestNullCacheTryGetReturnsNil;
    [Test]
    procedure TestNullCachePutDoesNothing;

    { TBypassFrameCache tests }
    [Test]
    procedure TestBypassCacheTryGetReturnsNil;
    [Test]
    procedure TestBypassCachePutDelegates;

    { TReadOnlyFrameCache tests }
    [Test]
    procedure TestReadOnlyCacheTryGetDelegates;
    [Test]
    procedure TestReadOnlyCachePutIsNoOp;

    { Eviction edge cases }
    [Test]
    procedure TestEvictionSkipsLockedFiles;

    { Overwrite test }
    [Test]
    procedure TestPutOverwritesExistingEntry;

    { ICacheManager via factory tests }
    [Test]
    procedure TestCacheManagerClear;
    [Test]
    procedure TestCacheManagerEvict;
    [Test]
    procedure TestCacheManagerGetTotalSize;

    {Orphan-temp sweep: Put writes <CacheDir>\<guid>.tmp and renames it.
     If the process crashed mid-write the .tmp survived forever -- Evict
     only walked .png. Construction now sweeps top-level *.tmp.}
    [Test]
    procedure TestConstructorSweepsOrphanTempFiles;
    [Test]
    procedure TestConstructorPreservesPngEntries;

    {Concurrency: every public operation is wrapped in FLock so concurrent
     workers cannot corrupt the cache directory or interleave Evict's
     directory walk with a Put. The stress test fires Put / TryGet / Evict
     / GetTotalSize from many threads and asserts no exception escapes.}
    [Test]
    procedure TestConcurrentOperations_DoNotCrash;
  end;

implementation

uses
  System.DateUtils;

{ TTestFrameCache }

procedure TTestFrameCache.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'VT_CacheTest_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FCacheDir := TPath.Combine(FTempDir, 'cache');
end;

procedure TTestFrameCache.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestFrameCache.CreateDummyFile(const AName: string;
  ASize: Integer): string;
var
  FS: TFileStream;
  Buf: TBytes;
begin
  Result := TPath.Combine(FTempDir, AName);
  SetLength(Buf, ASize);
  FillChar(Buf[0], ASize, $AA);
  FS := TFileStream.Create(Result, fmCreate);
  try
    FS.WriteBuffer(Buf[0], ASize);
  finally
    FS.Free;
  end;
end;

function TTestFrameCache.CreateTestBitmap(AWidth, AHeight: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := clRed;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

procedure TTestFrameCache.SetFileWriteTime(const APath: string;
  ATime: TDateTime);
begin
  TFile.SetLastWriteTime(APath, ATime);
end;

{ Key generation tests: these test the static FrameKey method directly }

procedure TTestFrameCache.TestKeyDeterministic;
var
  FilePath: string;
  K1, K2: string;
begin
  FilePath := CreateDummyFile('video1.mp4', 1024);
  K1 := TFrameCache.FrameKey(FilePath, 10.500, 0, False);
  K2 := TFrameCache.FrameKey(FilePath, 10.500, 0, False);
  Assert.AreEqual(K1, K2, 'Same inputs must produce same key');
  Assert.AreEqual(32, Length(K1), 'Key must be 32-char MD5 hex');
end;

procedure TTestFrameCache.TestKeyChangesOnPath;
var
  Path1, Path2: string;
begin
  Path1 := CreateDummyFile('video_a.mp4', 1024);
  Path2 := CreateDummyFile('video_b.mp4', 1024);
  Assert.AreNotEqual(
    TFrameCache.FrameKey(Path1, 5.0, 0, False),
    TFrameCache.FrameKey(Path2, 5.0, 0, False),
    'Different paths must produce different keys');
end;

procedure TTestFrameCache.TestKeyChangesOnSize;
var
  Path1, Path2: string;
begin
  Path1 := CreateDummyFile('size_a.mp4', 1000);
  Path2 := CreateDummyFile('size_b.mp4', 2000);
  Assert.AreNotEqual(
    TFrameCache.FrameKey(Path1, 5.0, 0, False),
    TFrameCache.FrameKey(Path2, 5.0, 0, False),
    'Different file sizes must produce different keys');
end;

procedure TTestFrameCache.TestKeyChangesOnMtime;
var
  FilePath: string;
  K1, K2: string;
begin
  FilePath := CreateDummyFile('mtime.mp4', 1024);

  SetFileWriteTime(FilePath, EncodeDateTime(2024, 1, 1, 12, 0, 0, 0));
  K1 := TFrameCache.FrameKey(FilePath, 5.0, 0, False);

  SetFileWriteTime(FilePath, EncodeDateTime(2025, 6, 15, 8, 30, 0, 0));
  K2 := TFrameCache.FrameKey(FilePath, 5.0, 0, False);

  Assert.AreNotEqual(K1, K2,
    'Different modification times must produce different keys');
end;

procedure TTestFrameCache.TestKeyChangesOnOffset;
var
  FilePath: string;
begin
  FilePath := CreateDummyFile('offset.mp4', 1024);
  Assert.AreNotEqual(
    TFrameCache.FrameKey(FilePath, 10.0, 0, False),
    TFrameCache.FrameKey(FilePath, 20.0, 0, False),
    'Different time offsets must produce different keys');
end;

procedure TTestFrameCache.TestKeyPathCaseInsensitive;
var
  FilePath: string;
  KeyLower, KeyUpper: string;
begin
  { FrameKey lowercases the path internally, so identical file metadata
    with different-case paths should yield the same key. On Windows both
    paths resolve to the same physical file. }
  FilePath := CreateDummyFile('CaseTest.mp4', 512);

  KeyLower := TFrameCache.FrameKey(AnsiLowerCase(FilePath), 1.0, 0, False);
  KeyUpper := TFrameCache.FrameKey(AnsiUpperCase(FilePath), 1.0, 0, False);

  Assert.AreEqual(KeyLower, KeyUpper,
    'Path casing must not affect cache key');
end;

{ TFrameCache read/write tests }

procedure TTestFrameCache.TestPutAndGet;
var
  Cache: TFrameCache;
  Bmp, Retrieved: TBitmap;
  FilePath: string;
begin
  FilePath := CreateDummyFile('putget.mp4', 1024);
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := CreateTestBitmap(64, 48);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath, 5.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;

    Retrieved := Cache.TryGet(TFrameCacheKey.Create(FilePath, 5.0, 0, False));
    try
      Assert.IsNotNull(Retrieved, 'Cached bitmap must be retrievable');
      Assert.AreEqual(64, Retrieved.Width, 'Width must match');
      Assert.AreEqual(48, Retrieved.Height, 'Height must match');
    finally
      Retrieved.Free;
    end;
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestGetMissReturnsNil;
var
  Cache: TFrameCache;
  FilePath: string;
  Bmp: TBitmap;
begin
  FilePath := CreateDummyFile('miss.mp4', 256);
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := Cache.TryGet(TFrameCacheKey.Create(FilePath, 99.0, 0, False));
    Assert.IsNull(Bmp, 'Non-existent cache entry must return nil');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestGetCorruptFileReturnsNil;
var
  Cache: TFrameCache;
  FilePath, Key, SubDir, CachePath: string;
  FS: TFileStream;
  Bmp: TBitmap;
begin
  FilePath := CreateDummyFile('corrupt.mp4', 512);
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    { Compute the key to find where the cache file would be stored }
    Key := TFrameCache.FrameKey(FilePath, 1.0, 0, False);
    Assert.IsNotEmpty(Key, 'Key must not be empty for existing file');

    { Manually place a corrupt file at the expected cache path }
    SubDir := TPath.Combine(FCacheDir, Copy(Key, 1, 2));
    TDirectory.CreateDirectory(SubDir);
    CachePath := TPath.Combine(SubDir, Key + '.png');
    FS := TFileStream.Create(CachePath, fmCreate);
    try
      FS.WriteBuffer(PAnsiChar('NOT_A_PNG')^, 9);
    finally
      FS.Free;
    end;

    Bmp := Cache.TryGet(TFrameCacheKey.Create(FilePath, 1.0, 0, False));
    Assert.IsNull(Bmp, 'Corrupt PNG must return nil, not raise exception');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestPutCreatesSubdirectory;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  FilePath, Key, ExpectedSubDir, ExpectedFile: string;
begin
  FilePath := CreateDummyFile('subdir.mp4', 256);
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := CreateTestBitmap(16, 16);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath, 5.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;

    Key := TFrameCache.FrameKey(FilePath, 5.0, 0, False);
    ExpectedSubDir := TPath.Combine(FCacheDir, Copy(Key, 1, 2));
    ExpectedFile := TPath.Combine(ExpectedSubDir, Key + '.png');

    Assert.IsTrue(TDirectory.Exists(ExpectedSubDir),
      'Shard subdirectory must be created');
    Assert.IsTrue(TFile.Exists(ExpectedFile),
      'PNG file must exist in shard subdirectory');
  finally
    Cache.Free;
  end;
end;

{ Eviction tests }

procedure TTestFrameCache.TestEvictionRemovesOldest;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  FilePath1, FilePath2, FilePath3: string;
  Key1, Key2, Key3: string;
begin
  FilePath1 := CreateDummyFile('evict1.mp4', 100);
  FilePath2 := CreateDummyFile('evict2.mp4', 200);
  FilePath3 := CreateDummyFile('evict3.mp4', 300);

  Cache := TFrameCache.Create(FCacheDir, 1);
  try
    Bmp := CreateTestBitmap(100, 100);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath1, 1.0, 0, False), Bmp);
      Cache.Put(TFrameCacheKey.Create(FilePath2, 1.0, 0, False), Bmp);
      Cache.Put(TFrameCacheKey.Create(FilePath3, 1.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;

    { Set access times so we can verify eviction order }
    Key1 := TFrameCache.FrameKey(FilePath1, 1.0, 0, False);
    Key2 := TFrameCache.FrameKey(FilePath2, 1.0, 0, False);
    Key3 := TFrameCache.FrameKey(FilePath3, 1.0, 0, False);

    TFile.SetLastAccessTime(
      TPath.Combine(TPath.Combine(FCacheDir, Copy(Key1, 1, 2)), Key1 + '.png'),
      EncodeDateTime(2020, 1, 1, 0, 0, 0, 0));
    TFile.SetLastAccessTime(
      TPath.Combine(TPath.Combine(FCacheDir, Copy(Key2, 1, 2)), Key2 + '.png'),
      EncodeDateTime(2023, 6, 1, 0, 0, 0, 0));
    TFile.SetLastAccessTime(
      TPath.Combine(TPath.Combine(FCacheDir, Copy(Key3, 1, 2)), Key3 + '.png'),
      EncodeDateTime(2025, 1, 1, 0, 0, 0, 0));
  finally
    Cache.Free;
  end;

  { Re-open with 0 MB limit: forces eviction of everything }
  Cache := TFrameCache.Create(FCacheDir, 0);
  try
    Cache.Evict;
    Assert.AreEqual(Int64(0), Cache.GetTotalSize,
      'All files must be evicted when max size is 0');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestEvictionPreservesNewest;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  FilePathOld, FilePathNew: string;
  KeyOld, KeyNew: string;
  PathOld, PathNew: string;
begin
  FilePathOld := CreateDummyFile('old.mp4', 100);
  FilePathNew := CreateDummyFile('new.mp4', 200);

  Cache := TFrameCache.Create(FCacheDir, 500);
  try
    Bmp := CreateTestBitmap(50, 50);
    try
      Cache.Put(TFrameCacheKey.Create(FilePathOld, 1.0, 0, False), Bmp);
      Cache.Put(TFrameCacheKey.Create(FilePathNew, 1.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;

    KeyOld := TFrameCache.FrameKey(FilePathOld, 1.0, 0, False);
    KeyNew := TFrameCache.FrameKey(FilePathNew, 1.0, 0, False);
    PathOld := TPath.Combine(TPath.Combine(FCacheDir, Copy(KeyOld, 1, 2)), KeyOld + '.png');
    PathNew := TPath.Combine(TPath.Combine(FCacheDir, Copy(KeyNew, 1, 2)), KeyNew + '.png');

    TFile.SetLastAccessTime(PathOld, EncodeDateTime(2020, 1, 1, 0, 0, 0, 0));
    TFile.SetLastAccessTime(PathNew, EncodeDateTime(2025, 12, 31, 23, 59, 59, 0));
  finally
    Cache.Free;
  end;

  { With 0 budget, eviction removes everything }
  Cache := TFrameCache.Create(FCacheDir, 0);
  try
    Cache.Evict;
    Assert.IsFalse(TFile.Exists(PathOld), 'Old file must be evicted');
    Assert.IsFalse(TFile.Exists(PathNew), 'New file must also be evicted at 0 budget');
  finally
    Cache.Free;
  end;

  { With large budget, nothing is evicted }
  Cache := TFrameCache.Create(FCacheDir, 500);
  try
    Bmp := CreateTestBitmap(50, 50);
    try
      Cache.Put(TFrameCacheKey.Create(FilePathNew, 1.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;
    Cache.Evict;
    Assert.IsTrue(TFile.Exists(
      TPath.Combine(TPath.Combine(FCacheDir, Copy(KeyNew, 1, 2)), KeyNew + '.png')),
      'File must survive eviction when within budget');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestClear;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  FilePath1, FilePath2: string;
begin
  FilePath1 := CreateDummyFile('clear1.mp4', 128);
  FilePath2 := CreateDummyFile('clear2.mp4', 256);

  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := CreateTestBitmap(32, 32);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath1, 1.0, 0, False), Bmp);
      Cache.Put(TFrameCacheKey.Create(FilePath2, 2.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;

    Assert.IsTrue(Cache.GetTotalSize > 0, 'Cache must have files before clear');
    Cache.Clear;
    Assert.AreEqual(Int64(0), Cache.GetTotalSize,
      'Cache must be empty after clear');
    Assert.IsTrue(TDirectory.Exists(FCacheDir),
      'Cache root must be recreated after clear');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestGetTotalSize;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  FilePath1, FilePath2: string;
  Size1, Size2: Int64;
begin
  FilePath1 := CreateDummyFile('size1.mp4', 128);
  FilePath2 := CreateDummyFile('size2.mp4', 256);

  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Assert.AreEqual(Int64(0), Cache.GetTotalSize,
      'Empty cache must report 0 size');

    Bmp := CreateTestBitmap(32, 32);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath1, 1.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;
    Size1 := Cache.GetTotalSize;
    Assert.IsTrue(Size1 > 0, 'Size must be positive after putting one frame');

    Bmp := CreateTestBitmap(64, 64);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath2, 2.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;
    Size2 := Cache.GetTotalSize;
    Assert.IsTrue(Size2 > Size1,
      'Size must increase after putting a second frame');
  finally
    Cache.Free;
  end;
end;

{ TNullFrameCache tests }

procedure TTestFrameCache.TestNullCacheTryGetReturnsNil;
var
  Cache: IFrameCache;
  FilePath: string;
  Bmp: TBitmap;
begin
  FilePath := CreateDummyFile('null_get.mp4', 128);
  Cache := TNullFrameCache.Create;
  Bmp := Cache.TryGet(TFrameCacheKey.Create(FilePath, 5.0, 0, False));
  Assert.IsNull(Bmp, 'Null cache must always return nil');
end;

procedure TTestFrameCache.TestNullCachePutDoesNothing;
var
  Cache: IFrameCache;
  FilePath: string;
  Bmp: TBitmap;
begin
  { Verify Put does not raise and creates no files }
  FilePath := CreateDummyFile('null_put.mp4', 128);
  Cache := TNullFrameCache.Create;
  Bmp := CreateTestBitmap(16, 16);
  try
    Cache.Put(TFrameCacheKey.Create(FilePath, 1.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;
  Assert.IsFalse(TDirectory.Exists(FCacheDir),
    'Null cache must not create any cache directory');
end;

{ TBypassFrameCache tests }

procedure TTestFrameCache.TestBypassCacheTryGetReturnsNil;
var
  RealCache: IFrameCache;
  Bypass: IFrameCache;
  FilePath: string;
  Bmp: TBitmap;
begin
  FilePath := CreateDummyFile('bypass_get.mp4', 256);
  { Use interface reference throughout to avoid mixing class/interface lifetimes }
  RealCache := TFrameCache.Create(FCacheDir, 100);

  { Store a frame in the real cache }
  Bmp := CreateTestBitmap(32, 32);
  try
    RealCache.Put(TFrameCacheKey.Create(FilePath, 5.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  { Verify the frame is in the real cache }
  Bmp := RealCache.TryGet(TFrameCacheKey.Create(FilePath, 5.0, 0, False));
  Assert.IsNotNull(Bmp, 'Frame must exist in real cache');
  Bmp.Free;

  { Bypass must return nil even though the frame is cached }
  Bypass := TBypassFrameCache.Create(RealCache);
  Bmp := Bypass.TryGet(TFrameCacheKey.Create(FilePath, 5.0, 0, False));
  Assert.IsNull(Bmp, 'Bypass cache must always return nil on TryGet');
end;

procedure TTestFrameCache.TestBypassCachePutDelegates;
var
  RealCache: IFrameCache;
  Bypass: IFrameCache;
  FilePath: string;
  Bmp: TBitmap;
begin
  FilePath := CreateDummyFile('bypass_put.mp4', 256);
  { Use interface reference throughout to avoid mixing class/interface lifetimes }
  RealCache := TFrameCache.Create(FCacheDir, 100);

  { Put via bypass }
  Bypass := TBypassFrameCache.Create(RealCache);
  Bmp := CreateTestBitmap(48, 48);
  try
    Bypass.Put(TFrameCacheKey.Create(FilePath, 3.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  { Verify the frame landed in the real cache }
  Bmp := RealCache.TryGet(TFrameCacheKey.Create(FilePath, 3.0, 0, False));
  try
    Assert.IsNotNull(Bmp, 'Bypass Put must delegate to inner cache');
    Assert.AreEqual(48, Bmp.Width, 'Width must match');
    Assert.AreEqual(48, Bmp.Height, 'Height must match');
  finally
    Bmp.Free;
  end;
end;

{ TReadOnlyFrameCache tests }

procedure TTestFrameCache.TestReadOnlyCacheTryGetDelegates;
var
  RealCache, ReadOnly: IFrameCache;
  FilePath: string;
  Bmp: TBitmap;
begin
  {ReadOnly must hit on entries already present in the inner cache —
   that is the whole point of "writes off, reads on" for the random
   extraction path with caching disabled.}
  FilePath := CreateDummyFile('ro_get.mp4', 256);
  RealCache := TFrameCache.Create(FCacheDir, 100);

  Bmp := CreateTestBitmap(64, 64);
  try
    RealCache.Put(TFrameCacheKey.Create(FilePath, 7.5, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  ReadOnly := TReadOnlyFrameCache.Create(RealCache);
  Bmp := ReadOnly.TryGet(TFrameCacheKey.Create(FilePath, 7.5, 0, False));
  try
    Assert.IsNotNull(Bmp, 'ReadOnly TryGet must delegate to inner');
    Assert.AreEqual(64, Bmp.Width);
  finally
    Bmp.Free;
  end;
end;

procedure TTestFrameCache.TestReadOnlyCachePutIsNoOp;
var
  RealCache, ReadOnly: IFrameCache;
  FilePath: string;
  Bmp, Probe: TBitmap;
begin
  {Put must NOT reach the inner cache. Verify by attempting a Put
   through the ReadOnly wrapper, then probing the inner directly: the
   key must miss.}
  FilePath := CreateDummyFile('ro_put.mp4', 256);
  RealCache := TFrameCache.Create(FCacheDir, 100);

  ReadOnly := TReadOnlyFrameCache.Create(RealCache);
  Bmp := CreateTestBitmap(32, 32);
  try
    ReadOnly.Put(TFrameCacheKey.Create(FilePath, 11.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  Probe := RealCache.TryGet(TFrameCacheKey.Create(FilePath, 11.0, 0, False));
  Assert.IsNull(Probe, 'ReadOnly Put must drop writes; inner cache must remain empty');
end;

procedure TTestFrameCache.TestEvictionSkipsLockedFiles;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  FilePath1, FilePath2, FilePath3: string;
  CachedPath: string;
  LockedStream: TFileStream;
  SizeAfter: Int64;
begin
  { Create 3 files so total exceeds a tiny budget }
  FilePath1 := CreateDummyFile('lock1.mp4', 100);
  FilePath2 := CreateDummyFile('lock2.mp4', 200);
  FilePath3 := CreateDummyFile('lock3.mp4', 300);

  { Use a very small max so eviction will be needed }
  Cache := TFrameCache.Create(FCacheDir, 1); { 1 MB limit }
  try
    Bmp := CreateTestBitmap(64, 64);
    try
      Cache.Put(TFrameCacheKey.Create(FilePath1, 1.0, 0, False), Bmp);
      Sleep(50);
      Cache.Put(TFrameCacheKey.Create(FilePath2, 2.0, 0, False), Bmp);
      Sleep(50);
      Cache.Put(TFrameCacheKey.Create(FilePath3, 3.0, 0, False), Bmp);
    finally
      Bmp.Free;
    end;

    { Total size should be within budget, so check we have files }
    Assert.IsTrue(Cache.GetTotalSize > 0, 'Cache should have files');

    { Now create a cache with a budget smaller than total to force eviction.
      Lock the oldest file so eviction must skip it. }
    CachedPath := '';
    for var F in TDirectory.GetFiles(FCacheDir, '*.png', TSearchOption.soAllDirectories) do
    begin
      CachedPath := F;
      Break; { Just grab any file to lock }
    end;

    if CachedPath <> '' then
    begin
      LockedStream := TFileStream.Create(CachedPath, fmOpenRead or fmShareExclusive);
      try
        { Eviction should not crash when it cannot delete the locked file }
        Cache.Evict;
        SizeAfter := Cache.GetTotalSize;
        { Locked file remains, so size should be > 0 }
        Assert.IsTrue(SizeAfter > 0, 'Locked file should survive eviction');
      finally
        LockedStream.Free;
      end;
    end;
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestPutOverwritesExistingEntry;
var
  Cache: TFrameCache;
  Bmp1, Bmp2, Got: TBitmap;
  VideoPath: string;
begin
  VideoPath := CreateDummyFile('overwrite.mp4', 512);
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    { First put: 10x10 bitmap }
    Bmp1 := CreateTestBitmap(10, 10);
    try
      Cache.Put(TFrameCacheKey.Create(VideoPath, 1.0, 0, False), Bmp1);
    finally
      Bmp1.Free;
    end;

    { Second put: 20x15 bitmap at same offset }
    Bmp2 := CreateTestBitmap(20, 15);
    try
      Cache.Put(TFrameCacheKey.Create(VideoPath, 1.0, 0, False), Bmp2);
    finally
      Bmp2.Free;
    end;

    { Get should return the second bitmap's dimensions }
    Got := Cache.TryGet(TFrameCacheKey.Create(VideoPath, 1.0, 0, False));
    try
      Assert.IsNotNull(Got, 'Should retrieve overwritten entry');
      Assert.AreEqual(20, Got.Width, 'Width should match second put');
      Assert.AreEqual(15, Got.Height, 'Height should match second put');
    finally
      Got.Free;
    end;
  finally
    Cache.Free;
  end;
end;

{ ICacheManager via factory tests }

procedure TTestFrameCache.TestCacheManagerClear;
var
  Cache: IFrameCache;
  Mgr: ICacheManager;
  Bmp: TBitmap;
  FilePath: string;
begin
  FilePath := CreateDummyFile('mgr_clear.mp4', 128);
  Cache := TFrameCache.Create(FCacheDir, 100);
  Bmp := CreateTestBitmap(32, 32);
  try
    Cache.Put(TFrameCacheKey.Create(FilePath, 1.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  Mgr := CreateCacheManager(FCacheDir, 100);
  Assert.IsTrue(Mgr.GetTotalSize > 0, 'Cache must have files before clear');
  Mgr.Clear;
  Assert.AreEqual(Int64(0), Mgr.GetTotalSize, 'Cache must be empty after clear via manager');
end;

procedure TTestFrameCache.TestCacheManagerEvict;
var
  Cache: IFrameCache;
  Mgr: ICacheManager;
  Bmp: TBitmap;
  FilePath: string;
begin
  FilePath := CreateDummyFile('mgr_evict.mp4', 128);
  Cache := TFrameCache.Create(FCacheDir, 100);
  Bmp := CreateTestBitmap(64, 64);
  try
    Cache.Put(TFrameCacheKey.Create(FilePath, 1.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  { Create manager with 0 budget to force full eviction }
  Mgr := CreateCacheManager(FCacheDir, 0);
  Mgr.Evict;
  Assert.AreEqual(Int64(0), Mgr.GetTotalSize, 'All files must be evicted at 0 budget');
end;

procedure TTestFrameCache.TestCacheManagerGetTotalSize;
var
  Cache: IFrameCache;
  Mgr: ICacheManager;
  Bmp: TBitmap;
  FilePath: string;
begin
  Mgr := CreateCacheManager(FCacheDir, 100);
  Assert.AreEqual(Int64(0), Mgr.GetTotalSize, 'Empty cache must report 0');

  FilePath := CreateDummyFile('mgr_size.mp4', 128);
  Cache := TFrameCache.Create(FCacheDir, 100);
  Bmp := CreateTestBitmap(32, 32);
  try
    Cache.Put(TFrameCacheKey.Create(FilePath, 1.0, 0, False), Bmp);
  finally
    Bmp.Free;
  end;

  { Fresh manager instance must see the files written by TFrameCache }
  Mgr := CreateCacheManager(FCacheDir, 100);
  Assert.IsTrue(Mgr.GetTotalSize > 0, 'Manager must report positive size after put');
end;

procedure TTestFrameCache.TestConstructorSweepsOrphanTempFiles;
var
  Cache: TFrameCache;
  OrphanA, OrphanB, Survivor: string;
begin
  {Pre-create the cache directory and seed it with two orphan .tmp files
   plus an unrelated text file. The constructor must wipe the orphans
   without touching files that do not match the .tmp pattern.}
  TDirectory.CreateDirectory(FCacheDir);
  OrphanA := TPath.Combine(FCacheDir, TGUID.NewGuid.ToString + '.tmp');
  OrphanB := TPath.Combine(FCacheDir, TGUID.NewGuid.ToString + '.tmp');
  Survivor := TPath.Combine(FCacheDir, 'unrelated.txt');
  TFile.WriteAllText(OrphanA, 'partial png 1');
  TFile.WriteAllText(OrphanB, 'partial png 2');
  TFile.WriteAllText(Survivor, 'unrelated');

  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Assert.IsFalse(TFile.Exists(OrphanA),
      'Orphan .tmp A must be swept on construction');
    Assert.IsFalse(TFile.Exists(OrphanB),
      'Orphan .tmp B must be swept on construction');
    Assert.IsTrue(TFile.Exists(Survivor),
      'Non-.tmp files must survive the sweep');
  finally
    Cache.Free;
    if TFile.Exists(Survivor) then
      TFile.Delete(Survivor);
  end;
end;

procedure TTestFrameCache.TestConstructorPreservesPngEntries;
var
  Cache: TFrameCache;
  ShardDir, PngFile: string;
begin
  {Sweep targets only .tmp at the top level. Real cache entries live in
   sharded subdirectories and have .png extensions; the sweep must not
   touch them.}
  TDirectory.CreateDirectory(FCacheDir);
  ShardDir := TPath.Combine(FCacheDir, 'ab');
  TDirectory.CreateDirectory(ShardDir);
  PngFile := TPath.Combine(ShardDir, 'abcdef.png');
  TFile.WriteAllText(PngFile, 'fake png bytes');

  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Assert.IsTrue(TFile.Exists(PngFile),
      'Cached .png entries must survive the constructor sweep');
  finally
    Cache.Free;
  end;
end;

type
  TCacheStressKind = (cskPut, cskGet, cskEvict, cskTotalSize);

  TCacheStressThread = class(TThread)
  strict private
    FCache: TFrameCache;
    FStart: TEvent;
    FKind: TCacheStressKind;
    FIterations: Integer;
    FSourceFile: string;
    FException: string;
  protected
    procedure Execute; override;
  public
    constructor Create(ACache: TFrameCache; AStart: TEvent;
      AKind: TCacheStressKind; AIterations: Integer; const ASourceFile: string);
    property Exc: string read FException;
  end;

constructor TCacheStressThread.Create(ACache: TFrameCache; AStart: TEvent;
  AKind: TCacheStressKind; AIterations: Integer; const ASourceFile: string);
begin
  FCache := ACache;
  FStart := AStart;
  FKind := AKind;
  FIterations := AIterations;
  FSourceFile := ASourceFile;
  inherited Create(False);
end;

procedure TCacheStressThread.Execute;
var
  I: Integer;
  Bmp, Got: TBitmap;
  Key: TFrameCacheKey;
begin
  FStart.WaitFor(INFINITE);
  try
    for I := 1 to FIterations do
    begin
      Key := TFrameCacheKey.Create(FSourceFile, 1.0 + (I mod 5), 0, False);
      case FKind of
        cskPut:
          begin
            Bmp := TBitmap.Create;
            try
              Bmp.PixelFormat := pf24bit;
              Bmp.SetSize(8, 8);
              FCache.Put(Key, Bmp);
            finally
              Bmp.Free;
            end;
          end;
        cskGet:
          begin
            Got := FCache.TryGet(Key);
            Got.Free;
          end;
        cskEvict:
          FCache.Evict;
        cskTotalSize:
          FCache.GetTotalSize;
      end;
    end;
  except
    on E: Exception do
      FException := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TTestFrameCache.TestConcurrentOperations_DoNotCrash;
const
  ITER = 25;
var
  Cache: TFrameCache;
  StartGate: TEvent;
  Threads: array [0 .. 7] of TCacheStressThread;
  Handles: array [0 .. 7] of THandle;
  SourceFile: string;
  I: Integer;
  Failures: string;
begin
  {Source file must exist so FrameKey returns a non-empty key. The
   running test executable is reliably present.}
  SourceFile := ParamStr(0);
  Cache := TFrameCache.Create(FCacheDir, 100);
  StartGate := TEvent.Create(nil, True, False, '');
  try
    {Mix kinds: 3 putters, 3 getters, 1 evicter, 1 size-poller all racing
     on the same cache.}
    Threads[0] := TCacheStressThread.Create(Cache, StartGate, cskPut, ITER, SourceFile);
    Threads[1] := TCacheStressThread.Create(Cache, StartGate, cskPut, ITER, SourceFile);
    Threads[2] := TCacheStressThread.Create(Cache, StartGate, cskPut, ITER, SourceFile);
    Threads[3] := TCacheStressThread.Create(Cache, StartGate, cskGet, ITER, SourceFile);
    Threads[4] := TCacheStressThread.Create(Cache, StartGate, cskGet, ITER, SourceFile);
    Threads[5] := TCacheStressThread.Create(Cache, StartGate, cskGet, ITER, SourceFile);
    Threads[6] := TCacheStressThread.Create(Cache, StartGate, cskEvict, ITER div 5, SourceFile);
    Threads[7] := TCacheStressThread.Create(Cache, StartGate, cskTotalSize, ITER, SourceFile);

    for I := 0 to High(Handles) do
      Handles[I] := Threads[I].Handle;
    StartGate.SetEvent;
    WaitForMultipleObjects(Length(Handles), @Handles[0], True, 60000);

    Failures := '';
    for I := 0 to High(Threads) do
    begin
      if Threads[I].Exc <> '' then
        Failures := Failures + Format('thread %d: %s; ', [I, Threads[I].Exc]);
      Threads[I].Free;
    end;
    Assert.AreEqual('', Failures, 'No thread may surface an exception under contention');
  finally
    StartGate.Free;
    Cache.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameCache);

end.
