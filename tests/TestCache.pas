unit TestCache;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, System.Classes,
  Vcl.Graphics, uCache;

type
  [TestFixture]
  TTestFrameCache = class
  private
    FTempDir: string;
    FCacheDir: string;

    /// Creates a dummy file with the specified size and returns its path.
    function CreateDummyFile(const AName: string; ASize: Integer): string;

    /// Creates a small test bitmap of the given dimensions.
    function CreateTestBitmap(AWidth, AHeight: Integer): TBitmap;

    /// Sets the last write time of a file (for key generation tests).
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

{ Key generation tests -- these test the static FrameKey method directly }

procedure TTestFrameCache.TestKeyDeterministic;
var
  FilePath: string;
  K1, K2: string;
begin
  FilePath := CreateDummyFile('video1.mp4', 1024);
  K1 := TFrameCache.FrameKey(FilePath, 10.500);
  K2 := TFrameCache.FrameKey(FilePath, 10.500);
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
    TFrameCache.FrameKey(Path1, 5.0),
    TFrameCache.FrameKey(Path2, 5.0),
    'Different paths must produce different keys');
end;

procedure TTestFrameCache.TestKeyChangesOnSize;
var
  Path1, Path2: string;
begin
  Path1 := CreateDummyFile('size_a.mp4', 1000);
  Path2 := CreateDummyFile('size_b.mp4', 2000);
  Assert.AreNotEqual(
    TFrameCache.FrameKey(Path1, 5.0),
    TFrameCache.FrameKey(Path2, 5.0),
    'Different file sizes must produce different keys');
end;

procedure TTestFrameCache.TestKeyChangesOnMtime;
var
  FilePath: string;
  K1, K2: string;
begin
  FilePath := CreateDummyFile('mtime.mp4', 1024);

  SetFileWriteTime(FilePath, EncodeDateTime(2024, 1, 1, 12, 0, 0, 0));
  K1 := TFrameCache.FrameKey(FilePath, 5.0);

  SetFileWriteTime(FilePath, EncodeDateTime(2025, 6, 15, 8, 30, 0, 0));
  K2 := TFrameCache.FrameKey(FilePath, 5.0);

  Assert.AreNotEqual(K1, K2,
    'Different modification times must produce different keys');
end;

procedure TTestFrameCache.TestKeyChangesOnOffset;
var
  FilePath: string;
begin
  FilePath := CreateDummyFile('offset.mp4', 1024);
  Assert.AreNotEqual(
    TFrameCache.FrameKey(FilePath, 10.0),
    TFrameCache.FrameKey(FilePath, 20.0),
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

  KeyLower := TFrameCache.FrameKey(AnsiLowerCase(FilePath), 1.0);
  KeyUpper := TFrameCache.FrameKey(AnsiUpperCase(FilePath), 1.0);

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
      Cache.Put(FilePath, 5.0, Bmp);
    finally
      Bmp.Free;
    end;

    Retrieved := Cache.TryGet(FilePath, 5.0);
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
    Bmp := Cache.TryGet(FilePath, 99.0);
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
    Key := TFrameCache.FrameKey(FilePath, 1.0);
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

    Bmp := Cache.TryGet(FilePath, 1.0);
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
      Cache.Put(FilePath, 5.0, Bmp);
    finally
      Bmp.Free;
    end;

    Key := TFrameCache.FrameKey(FilePath, 5.0);
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
      Cache.Put(FilePath1, 1.0, Bmp);
      Cache.Put(FilePath2, 1.0, Bmp);
      Cache.Put(FilePath3, 1.0, Bmp);
    finally
      Bmp.Free;
    end;

    { Set access times so we can verify eviction order }
    Key1 := TFrameCache.FrameKey(FilePath1, 1.0);
    Key2 := TFrameCache.FrameKey(FilePath2, 1.0);
    Key3 := TFrameCache.FrameKey(FilePath3, 1.0);

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
      Cache.Put(FilePathOld, 1.0, Bmp);
      Cache.Put(FilePathNew, 1.0, Bmp);
    finally
      Bmp.Free;
    end;

    KeyOld := TFrameCache.FrameKey(FilePathOld, 1.0);
    KeyNew := TFrameCache.FrameKey(FilePathNew, 1.0);
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
      Cache.Put(FilePathNew, 1.0, Bmp);
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
      Cache.Put(FilePath1, 1.0, Bmp);
      Cache.Put(FilePath2, 2.0, Bmp);
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
      Cache.Put(FilePath1, 1.0, Bmp);
    finally
      Bmp.Free;
    end;
    Size1 := Cache.GetTotalSize;
    Assert.IsTrue(Size1 > 0, 'Size must be positive after putting one frame');

    Bmp := CreateTestBitmap(64, 64);
    try
      Cache.Put(FilePath2, 2.0, Bmp);
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
  Bmp := Cache.TryGet(FilePath, 5.0);
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
    Cache.Put(FilePath, 1.0, Bmp);
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
    RealCache.Put(FilePath, 5.0, Bmp);
  finally
    Bmp.Free;
  end;

  { Verify the frame is in the real cache }
  Bmp := RealCache.TryGet(FilePath, 5.0);
  Assert.IsNotNull(Bmp, 'Frame must exist in real cache');
  Bmp.Free;

  { Bypass must return nil even though the frame is cached }
  Bypass := TBypassFrameCache.Create(RealCache);
  Bmp := Bypass.TryGet(FilePath, 5.0);
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
    Bypass.Put(FilePath, 3.0, Bmp);
  finally
    Bmp.Free;
  end;

  { Verify the frame landed in the real cache }
  Bmp := RealCache.TryGet(FilePath, 3.0);
  try
    Assert.IsNotNull(Bmp, 'Bypass Put must delegate to inner cache');
    Assert.AreEqual(48, Bmp.Width, 'Width must match');
    Assert.AreEqual(48, Bmp.Height, 'Height must match');
  finally
    Bmp.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameCache);

end.
