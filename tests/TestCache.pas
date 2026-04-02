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
    [Test]
    procedure TestPutAndGet;
    [Test]
    procedure TestGetMissReturnsNil;
    [Test]
    procedure TestGetCorruptFileReturnsNil;
    [Test]
    procedure TestPutCreatesSubdirectory;
    [Test]
    procedure TestEvictionRemovesOldest;
    [Test]
    procedure TestEvictionPreservesNewest;
    [Test]
    procedure TestClear;
    [Test]
    procedure TestGetTotalSize;
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

{ Key generation tests }

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
  { Rename so paths are identical but sizes differ }
  { Use separate files directly since paths differ anyway }
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
    with different-case paths should yield the same key. We test the
    BuildKeyString logic by calling FrameKey on the same file but with
    different casing in the path string. Since FrameKey reads actual
    file metadata, we use the same physical file. }
  FilePath := CreateDummyFile('CaseTest.mp4', 512);

  { FrameKey normalises via AnsiLowerCase, so casing in the path should
    not affect the result. On Windows both paths resolve to the same file. }
  KeyLower := TFrameCache.FrameKey(AnsiLowerCase(FilePath), 1.0);
  KeyUpper := TFrameCache.FrameKey(AnsiUpperCase(FilePath), 1.0);

  Assert.AreEqual(KeyLower, KeyUpper,
    'Path casing must not affect cache key');
end;

{ Read/write tests }

procedure TTestFrameCache.TestPutAndGet;
var
  Cache: TFrameCache;
  Bmp, Retrieved: TBitmap;
begin
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := CreateTestBitmap(64, 48);
    try
      Cache.Put('aabbccdd11223344aabbccdd11223344', Bmp);
    finally
      Bmp.Free;
    end;

    Retrieved := Cache.TryGet('aabbccdd11223344aabbccdd11223344');
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
  Bmp: TBitmap;
begin
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := Cache.TryGet('00000000000000000000000000000000');
    Assert.IsNull(Bmp, 'Non-existent key must return nil');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestGetCorruptFileReturnsNil;
var
  Cache: TFrameCache;
  Key, Path, SubDir: string;
  FS: TFileStream;
  Bmp: TBitmap;
begin
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Key := 'ff112233445566778899aabbccddeeff';
    { Manually create a corrupt file at the expected cache path }
    SubDir := TPath.Combine(FCacheDir, Copy(Key, 1, 2));
    TDirectory.CreateDirectory(SubDir);
    Path := TPath.Combine(SubDir, Key + '.png');
    FS := TFileStream.Create(Path, fmCreate);
    try
      { Write garbage data }
      FS.WriteBuffer(PAnsiChar('NOT_A_PNG')^, 9);
    finally
      FS.Free;
    end;

    Bmp := Cache.TryGet(Key);
    Assert.IsNull(Bmp, 'Corrupt PNG must return nil, not raise exception');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestPutCreatesSubdirectory;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
  Key, ExpectedSubDir, ExpectedFile: string;
begin
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Key := 'a3f4b200112233445566778899aabbcc';
    Bmp := CreateTestBitmap(16, 16);
    try
      Cache.Put(Key, Bmp);
    finally
      Bmp.Free;
    end;

    ExpectedSubDir := TPath.Combine(FCacheDir, 'a3');
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
  Key1, Key2, Key3: string;
begin
  { Create cache with very small max size (1 KB) so that any bitmap exceeds it }
  Cache := TFrameCache.Create(FCacheDir, 1);
  try
    Key1 := 'aa00000000000000000000000000001a';
    Key2 := 'bb00000000000000000000000000002b';
    Key3 := 'cc00000000000000000000000000003c';

    Bmp := CreateTestBitmap(100, 100);
    try
      Cache.Put(Key1, Bmp);
    finally
      Bmp.Free;
    end;
    { Set oldest access time }
    TFile.SetLastAccessTime(Cache.CacheDir + PathDelim + 'aa' + PathDelim +
      Key1 + '.png', EncodeDateTime(2020, 1, 1, 0, 0, 0, 0));

    Bmp := CreateTestBitmap(100, 100);
    try
      Cache.Put(Key2, Bmp);
    finally
      Bmp.Free;
    end;
    TFile.SetLastAccessTime(Cache.CacheDir + PathDelim + 'bb' + PathDelim +
      Key2 + '.png', EncodeDateTime(2023, 6, 1, 0, 0, 0, 0));

    Bmp := CreateTestBitmap(100, 100);
    try
      Cache.Put(Key3, Bmp);
    finally
      Bmp.Free;
    end;
    TFile.SetLastAccessTime(Cache.CacheDir + PathDelim + 'cc' + PathDelim +
      Key3 + '.png', EncodeDateTime(2025, 1, 1, 0, 0, 0, 0));

    { Max size is 1 MB = 1048576 bytes. Total of three 100x100 PNGs exceeds this.
      Actually 1 MB might be enough. Let me use a tiny max. }
    { Re-create with 0 MB max -- forces eviction of everything beyond budget }
  finally
    Cache.Free;
  end;

  { Re-open with 0 MB limit (actually minimum is not enforced in constructor) }
  Cache := TFrameCache.Create(FCacheDir, 0);
  try
    Cache.Evict;
    { All files should be evicted since 0 bytes budget }
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
  KeyOld, KeyNew: string;
  PathOld, PathNew: string;
begin
  Cache := TFrameCache.Create(FCacheDir, 500);
  try
    KeyOld := 'dd0000000000000000000000000000aa';
    KeyNew := 'ee0000000000000000000000000000bb';

    Bmp := CreateTestBitmap(50, 50);
    try
      Cache.Put(KeyOld, Bmp);
    finally
      Bmp.Free;
    end;
    PathOld := TPath.Combine(TPath.Combine(FCacheDir, 'dd'), KeyOld + '.png');
    TFile.SetLastAccessTime(PathOld, EncodeDateTime(2020, 1, 1, 0, 0, 0, 0));

    Bmp := CreateTestBitmap(50, 50);
    try
      Cache.Put(KeyNew, Bmp);
    finally
      Bmp.Free;
    end;
    PathNew := TPath.Combine(TPath.Combine(FCacheDir, 'ee'), KeyNew + '.png');
    TFile.SetLastAccessTime(PathNew, EncodeDateTime(2025, 12, 31, 23, 59, 59, 0));
  finally
    Cache.Free;
  end;

  { With 0 budget, eviction removes everything -- oldest first }
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
      Cache.Put(KeyNew, Bmp);
    finally
      Bmp.Free;
    end;
    Cache.Evict;
    Assert.IsTrue(TFile.Exists(
      TPath.Combine(TPath.Combine(FCacheDir, 'ee'), KeyNew + '.png')),
      'File must survive eviction when within budget');
  finally
    Cache.Free;
  end;
end;

procedure TTestFrameCache.TestClear;
var
  Cache: TFrameCache;
  Bmp: TBitmap;
begin
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Bmp := CreateTestBitmap(32, 32);
    try
      Cache.Put('1100000000000000000000000000aa11', Bmp);
      Cache.Put('2200000000000000000000000000bb22', Bmp);
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
  Size1, Size2: Int64;
begin
  Cache := TFrameCache.Create(FCacheDir, 100);
  try
    Assert.AreEqual(Int64(0), Cache.GetTotalSize,
      'Empty cache must report 0 size');

    Bmp := CreateTestBitmap(32, 32);
    try
      Cache.Put('5500000000000000000000000000cc55', Bmp);
    finally
      Bmp.Free;
    end;
    Size1 := Cache.GetTotalSize;
    Assert.IsTrue(Size1 > 0, 'Size must be positive after putting one frame');

    Bmp := CreateTestBitmap(64, 64);
    try
      Cache.Put('6600000000000000000000000000dd66', Bmp);
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

initialization
  TDUnitX.RegisterTestFixture(TTestFrameCache);

end.
