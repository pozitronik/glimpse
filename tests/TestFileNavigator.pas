unit TestFileNavigator;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileNavigator = class
  private
    FTempDir: string;
    procedure CreateFiles(const ANames: array of string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestNextFileAlphabetical;
    [Test] procedure TestPrevFileAlphabetical;
    [Test] procedure TestWrapAroundForward;
    [Test] procedure TestWrapAroundBackward;
    [Test] procedure TestSingleFileSameDir;
    [Test] procedure TestNoSupportedFiles;
    [Test] procedure TestMixedExtensions;
    [Test] procedure TestCaseInsensitiveExtensions;
    [Test] procedure TestCaseInsensitiveSorting;
    [Test] procedure TestEmptyExtensionList;
    [Test] procedure TestNonexistentDirectory;
    [Test] procedure TestCurrentFileNotInList;
    [Test] procedure TestLargeNegativeDelta;
    [Test] procedure TestLargePositiveDelta;
    [Test] procedure TestZeroDelta_ReturnsSameFile;
    [Test] procedure TestSpacesInExtensionList;
    [Test] procedure TestGetFilePositionFirst;
    [Test] procedure TestGetFilePositionMiddle;
    [Test] procedure TestGetFilePositionLast;
    [Test] procedure TestGetFilePositionSingleFile;
    [Test] procedure TestGetFilePositionMixedExtensionsMatchesOnlyCount;
    [Test] procedure TestGetFilePositionCurrentNotInList;
    [Test] procedure TestGetFilePositionEmptyDirReturnsFalse;
    {Cache tests (step 111).}
    [Test] procedure Cache_ClearedInSetup_SizeIsZero;
    [Test] procedure Cache_FirstCall_GrowsSizeToOne;
    [Test] procedure Cache_SecondCallSameArgs_DoesNotGrow;
    [Test] procedure Cache_DifferentExtensionList_AddsEntry;
    [Test] procedure Cache_DirectoryMutation_InvalidatesAndReturnsFreshList;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Winapi.Windows,
  uFileNavigator;

procedure TTestFileNavigator.Setup;
begin
  FTempDir := IncludeTrailingPathDelimiter(TPath.GetTempPath) + 'GlimpseNavTest_' +
    IntToStr(GetCurrentThreadId) + PathDelim;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
  TDirectory.CreateDirectory(FTempDir);
  {Clear the module-level directory cache so each test starts from a
   known state. Required for the Cache_* tests that observe size; the
   other tests are independent of cache state because the per-test
   fresh FTempDir mtime always differs from any cached entry, but
   clearing here is defensive against test-order side effects.}
  ClearDirectoryCache;
end;

procedure TTestFileNavigator.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestFileNavigator.CreateFiles(const ANames: array of string);
var
  I: Integer;
begin
  for I := 0 to High(ANames) do
    TFile.WriteAllText(FTempDir + ANames[I], '');
end;

procedure TTestFileNavigator.TestNextFileAlphabetical;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.AreEqual(FTempDir + 'b.mp4',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4', 1));
  Assert.AreEqual(FTempDir + 'c.mp4',
    FindAdjacentFile(FTempDir + 'b.mp4', 'mp4', 1));
end;

procedure TTestFileNavigator.TestPrevFileAlphabetical;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.AreEqual(FTempDir + 'a.mp4',
    FindAdjacentFile(FTempDir + 'b.mp4', 'mp4', -1));
  Assert.AreEqual(FTempDir + 'b.mp4',
    FindAdjacentFile(FTempDir + 'c.mp4', 'mp4', -1));
end;

procedure TTestFileNavigator.TestWrapAroundForward;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.AreEqual(FTempDir + 'a.mp4',
    FindAdjacentFile(FTempDir + 'c.mp4', 'mp4', 1));
end;

procedure TTestFileNavigator.TestWrapAroundBackward;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.AreEqual(FTempDir + 'c.mp4',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4', -1));
end;

procedure TTestFileNavigator.TestSingleFileSameDir;
begin
  CreateFiles(['only.mp4']);
  Assert.AreEqual('',
    FindAdjacentFile(FTempDir + 'only.mp4', 'mp4', 1));
  Assert.AreEqual('',
    FindAdjacentFile(FTempDir + 'only.mp4', 'mp4', -1));
end;

procedure TTestFileNavigator.TestNoSupportedFiles;
begin
  CreateFiles(['readme.txt', 'notes.doc']);
  Assert.AreEqual('',
    FindAdjacentFile(FTempDir + 'readme.txt', 'mp4,mkv', 1));
end;

procedure TTestFileNavigator.TestMixedExtensions;
begin
  CreateFiles(['a.mp4', 'b.mkv', 'c.avi', 'readme.txt']);
  { Alphabetical order: a.mp4, b.mkv, c.avi; readme.txt excluded }
  Assert.AreEqual(FTempDir + 'b.mkv',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4,mkv,avi', 1));
  Assert.AreEqual(FTempDir + 'c.avi',
    FindAdjacentFile(FTempDir + 'b.mkv', 'mp4,mkv,avi', 1));
  Assert.AreEqual(FTempDir + 'a.mp4',
    FindAdjacentFile(FTempDir + 'c.avi', 'mp4,mkv,avi', 1));
end;

procedure TTestFileNavigator.TestCaseInsensitiveExtensions;
begin
  CreateFiles(['video.MP4', 'clip.mp4']);
  { Both should be found regardless of extension case }
  Assert.AreEqual(FTempDir + 'video.MP4',
    FindAdjacentFile(FTempDir + 'clip.mp4', 'mp4', 1));
end;

procedure TTestFileNavigator.TestCaseInsensitiveSorting;
begin
  CreateFiles(['Alpha.mp4', 'beta.mp4', 'Gamma.mp4']);
  { Case-insensitive sort: Alpha, beta, Gamma }
  Assert.AreEqual(FTempDir + 'beta.mp4',
    FindAdjacentFile(FTempDir + 'Alpha.mp4', 'mp4', 1));
  Assert.AreEqual(FTempDir + 'Gamma.mp4',
    FindAdjacentFile(FTempDir + 'beta.mp4', 'mp4', 1));
end;

procedure TTestFileNavigator.TestEmptyExtensionList;
begin
  CreateFiles(['a.mp4']);
  Assert.AreEqual('',
    FindAdjacentFile(FTempDir + 'a.mp4', '', 1));
end;

procedure TTestFileNavigator.TestNonexistentDirectory;
begin
  Assert.AreEqual('',
    FindAdjacentFile('X:\no\such\path\file.mp4', 'mp4', 1));
end;

procedure TTestFileNavigator.TestCurrentFileNotInList;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'notes.txt']);
  { Current file has unsupported extension }
  Assert.AreEqual('',
    FindAdjacentFile(FTempDir + 'notes.txt', 'mp4', 1));
end;

procedure TTestFileNavigator.TestLargeNegativeDelta;
begin
  { ADelta whose absolute value exceeds the file count must wrap correctly
    instead of producing a negative index (Delphi mod preserves sign). }
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  { 3 files, current=a (idx 0), delta=-7: (0-7) mod 3 -> wraps to idx 2 -> c }
  Assert.AreEqual(FTempDir + 'c.mp4',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4', -7));
  { delta=-100 from b (idx 1): (1-100) mod 3 = -99 mod 3 = 0 -> a }
  Assert.AreEqual(FTempDir + 'b.mp4',
    FindAdjacentFile(FTempDir + 'b.mp4', 'mp4', -99));
end;

procedure TTestFileNavigator.TestLargePositiveDelta;
begin
  { Large positive delta must also wrap correctly. }
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  { 3 files, current=a (idx 0), delta=7 -> 7 mod 3 = 1 -> b }
  Assert.AreEqual(FTempDir + 'b.mp4',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4', 7));
  { delta=100 from a (idx 0): 100 mod 3 = 1 -> b }
  Assert.AreEqual(FTempDir + 'b.mp4',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4', 100));
end;

procedure TTestFileNavigator.TestZeroDelta_ReturnsSameFile;
begin
  { ADelta=0 should return the same file (no navigation).
    The caller filters this with SameText check. }
  CreateFiles(['a.mp4', 'b.mp4']);
  Assert.AreEqual(FTempDir + 'a.mp4',
    FindAdjacentFile(FTempDir + 'a.mp4', 'mp4', 0));
end;

procedure TTestFileNavigator.TestSpacesInExtensionList;
begin
  { Extension list with spaces around commas should still work }
  CreateFiles(['a.mp4', 'b.mkv', 'c.avi']);
  Assert.AreEqual(FTempDir + 'b.mkv',
    FindAdjacentFile(FTempDir + 'a.mp4', ' mp4 , mkv , avi ', 1));
end;

procedure TTestFileNavigator.TestGetFilePositionFirst;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.IsTrue(GetFilePosition(FTempDir + 'a.mp4', 'mp4', Idx, Total));
  Assert.AreEqual(1, Idx);
  Assert.AreEqual(3, Total);
end;

procedure TTestFileNavigator.TestGetFilePositionMiddle;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.IsTrue(GetFilePosition(FTempDir + 'b.mp4', 'mp4', Idx, Total));
  Assert.AreEqual(2, Idx);
  Assert.AreEqual(3, Total);
end;

procedure TTestFileNavigator.TestGetFilePositionLast;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mp4', 'c.mp4']);
  Assert.IsTrue(GetFilePosition(FTempDir + 'c.mp4', 'mp4', Idx, Total));
  Assert.AreEqual(3, Idx);
  Assert.AreEqual(3, Total);
end;

procedure TTestFileNavigator.TestGetFilePositionSingleFile;
var
  Idx, Total: Integer;
begin
  { GetFilePosition MUST succeed with a single file (position 1 of 1),
    unlike FindAdjacentFile which needs at least two to navigate. }
  CreateFiles(['lonely.mp4']);
  Assert.IsTrue(GetFilePosition(FTempDir + 'lonely.mp4', 'mp4', Idx, Total));
  Assert.AreEqual(1, Idx);
  Assert.AreEqual(1, Total);
end;

procedure TTestFileNavigator.TestGetFilePositionMixedExtensionsMatchesOnlyCount;
var
  Idx, Total: Integer;
begin
  { Only supported extensions count toward the total. Here txt/jpg are
    filtered out, leaving just a.mp4 and b.mkv. }
  CreateFiles(['a.mp4', 'b.mkv', 'c.txt', 'd.jpg']);
  Assert.IsTrue(GetFilePosition(FTempDir + 'b.mkv', 'mp4,mkv', Idx, Total));
  Assert.AreEqual(2, Idx);
  Assert.AreEqual(2, Total);
end;

procedure TTestFileNavigator.TestGetFilePositionCurrentNotInList;
var
  Idx, Total: Integer;
begin
  { File on disk but extension not in the supported list. }
  CreateFiles(['a.mp4', 'b.mp4', 'foreign.xyz']);
  Assert.IsFalse(GetFilePosition(FTempDir + 'foreign.xyz', 'mp4,mkv', Idx, Total));
  Assert.AreEqual(0, Idx, 'Out params reset to 0 on failure');
  Assert.AreEqual(0, Total);
end;

procedure TTestFileNavigator.TestGetFilePositionEmptyDirReturnsFalse;
var
  Idx, Total: Integer;
begin
  { Directory exists but has no supported files. }
  Assert.IsFalse(GetFilePosition(FTempDir + 'phantom.mp4', 'mp4', Idx, Total));
  Assert.AreEqual(0, Idx);
  Assert.AreEqual(0, Total);
end;

procedure TTestFileNavigator.Cache_ClearedInSetup_SizeIsZero;
begin
  { Setup calls ClearDirectoryCache; verify the contract. }
  Assert.AreEqual(0, DirectoryCacheSize);
end;

procedure TTestFileNavigator.Cache_FirstCall_GrowsSizeToOne;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mp4']);
  GetFilePosition(FTempDir + 'a.mp4', 'mp4', Idx, Total);
  Assert.AreEqual(1, DirectoryCacheSize,
    'First call inserts one cache entry for (dir, mtime, extensions)');
end;

procedure TTestFileNavigator.Cache_SecondCallSameArgs_DoesNotGrow;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mp4']);
  GetFilePosition(FTempDir + 'a.mp4', 'mp4', Idx, Total);
  GetFilePosition(FTempDir + 'b.mp4', 'mp4', Idx, Total);
  Assert.AreEqual(1, DirectoryCacheSize,
    'Second call with identical key hits the cache; size stays at 1');
end;

procedure TTestFileNavigator.Cache_DifferentExtensionList_AddsEntry;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mkv']);
  GetFilePosition(FTempDir + 'a.mp4', 'mp4', Idx, Total);
  GetFilePosition(FTempDir + 'a.mp4', 'mp4,mkv', Idx, Total);
  Assert.AreEqual(2, DirectoryCacheSize,
    'Different extension list -> different key -> separate cache entry');
end;

procedure TTestFileNavigator.Cache_DirectoryMutation_InvalidatesAndReturnsFreshList;
var
  Idx, Total: Integer;
begin
  CreateFiles(['a.mp4', 'b.mp4']);
  Assert.IsTrue(GetFilePosition(FTempDir + 'a.mp4', 'mp4', Idx, Total),
    'Pre-mutation: a.mp4 is at position 1 of 2');
  Assert.AreEqual(2, Total);

  {Wait briefly + add file: NTFS bumps the parent's mtime when an
   entry is added/removed. The cache's key includes FileAge(dir), so
   the next lookup misses and triggers a fresh scan.

   The sleep is here because some filesystems / Windows builds quantize
   directory mtimes to 1-second resolution; without a wait the file
   add could leave the dir's reported mtime equal to the pre-mutation
   value (within the same second). 1100ms safely crosses the boundary.}
  Sleep(1100);
  CreateFiles(['c.mp4']);

  Assert.IsTrue(GetFilePosition(FTempDir + 'a.mp4', 'mp4', Idx, Total),
    'Post-mutation: a.mp4 still at position 1 but total grew to 3');
  Assert.AreEqual(3, Total,
    'mtime invalidation: cache miss triggers fresh scan; new file included');
end;

end.
