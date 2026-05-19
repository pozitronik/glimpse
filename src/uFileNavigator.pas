{Finds the next or previous supported file in the same directory,
 and reports the current file's 1-based position among the supported
 siblings. Sorted alphabetically, case-insensitive, with wrap-around
 at boundaries for navigation.

 Step 111 (S12): an in-memory cache keyed by (dir, mtime, extensions)
 amortises the per-keypress TDirectory.GetFiles + sort across runs of
 navigations in the same directory. Cache invalidates automatically
 when the directory's mtime changes (file create/delete in NTFS bumps
 the parent's mtime). Cache is bounded by CACHE_CAPACITY and uses
 round-robin eviction. Single TCriticalSection guards the cache;
 production callers are single-threaded (UI thread) but the lock is
 defensive against future use from a background thread.}
unit uFileNavigator;

interface

{Returns the path of the adjacent supported file in the same directory
 as ACurrentFile. ADelta = +1 for next, -1 for previous. AExtensions is
 a comma-separated list (e.g. 'mp4,mkv,avi'). Returns empty string if
 fewer than two supported files exist. Wraps around at first/last file.}
function FindAdjacentFile(const ACurrentFile, AExtensions: string; ADelta: Integer): string;

{Reports the 1-based position (AIndex) of ACurrentFile within the sorted
 list of supported files in its directory, plus the total count (ATotal).
 Returns True on success. Returns False with both out params at 0 when
 the directory is unreadable, no supported files are present, or
 ACurrentFile itself isn't in the sorted list.}
function GetFilePosition(const ACurrentFile, AExtensions: string; out AIndex, ATotal: Integer): Boolean;

{Drops every cache entry. Tests call this in Setup to start from a
 known state. Production code does not need to call this; entries
 expire automatically when the directory's mtime changes.}
procedure ClearDirectoryCache;

{Number of cached directory listings currently held. Tests use this to
 verify cache hits vs misses (a second call with identical arguments
 should not grow the count; a call with a different directory or
 extension set should).}
function DirectoryCacheSize: Integer;

implementation

uses
  System.SysUtils, System.IOUtils, System.Types, System.Classes,
  System.Generics.Collections, System.Generics.Defaults,
  System.SyncObjs;

const
  {Holds the most recently scanned directory listings. 8 covers TC's
   typical workflow (left + right panels plus a handful of recent
   navigations). Round-robin eviction; the oldest entry is overwritten
   when the table is full.}
  CACHE_CAPACITY = 8;

type
  TDirCacheEntry = record
    Key: string;
    Files: TArray<string>;
  end;

var
  GCacheLock: TCriticalSection;
  GCache: array[0..CACHE_CAPACITY - 1] of TDirCacheEntry;
  GCacheCount: Integer;
  GCacheNext: Integer;

{Builds a normalized comma-separated string from AExtensions: trimmed,
 lowercased, sorted, deduplicated. Empty entries are dropped. Used as
 part of the cache key so two callers with semantically-equivalent
 extension lists (different whitespace, different case, different
 order) hit the same cache row.}
function NormalizedExtKey(const AExtensions: string): string;
var
  ExtList: TArray<string>;
  ExtSet: TStringList;
  Ext: string;
  I: Integer;
begin
  ExtSet := TStringList.Create;
  try
    ExtSet.Sorted := True;
    ExtSet.Duplicates := dupIgnore;
    ExtList := AExtensions.Split([',', ' ']);
    for I := 0 to High(ExtList) do
    begin
      Ext := ExtList[I].Trim.ToLower;
      if Ext <> '' then
        ExtSet.Add(Ext);
    end;
    Result := ExtSet.CommaText;
  finally
    ExtSet.Free;
  end;
end;

{Locale-independent string form of the directory's last-write time.
 Used in the cache key so mtime equality is a string compare. On any
 failure (dir missing, access denied) returns '0' — the key then never
 matches a successful entry, so the cache effectively bypasses until
 the dir is readable again.}
function DirMTimeKey(const ADir: string): string;
var
  DT: TDateTime;
begin
  try
    DT := TDirectory.GetLastWriteTime(ExcludeTrailingPathDelimiter(ADir));
    Result := FormatDateTime('yyyymmddhhnnsszzz', DT);
  except
    Result := '0';
  end;
end;

function BuildCacheKey(const ADir, AExtensions: string): string;
begin
  Result := ADir.ToLower + '|' + DirMTimeKey(ADir) + '|' + NormalizedExtKey(AExtensions);
end;

function TryGetCached(const AKey: string; out AFiles: TArray<string>): Boolean;
var
  I: Integer;
begin
  for I := 0 to GCacheCount - 1 do
    if GCache[I].Key = AKey then
    begin
      AFiles := GCache[I].Files;
      Exit(True);
    end;
  AFiles := nil;
  Result := False;
end;

procedure StoreInCache(const AKey: string; const AFiles: TArray<string>);
begin
  GCache[GCacheNext].Key := AKey;
  GCache[GCacheNext].Files := AFiles;
  GCacheNext := (GCacheNext + 1) mod CACHE_CAPACITY;
  if GCacheCount < CACHE_CAPACITY then
    Inc(GCacheCount);
end;

procedure ClearDirectoryCache;
var
  I: Integer;
begin
  GCacheLock.Enter;
  try
    for I := 0 to CACHE_CAPACITY - 1 do
    begin
      GCache[I].Key := '';
      GCache[I].Files := nil;
    end;
    GCacheCount := 0;
    GCacheNext := 0;
  finally
    GCacheLock.Leave;
  end;
end;

function DirectoryCacheSize: Integer;
begin
  GCacheLock.Enter;
  try
    Result := GCacheCount;
  finally
    GCacheLock.Leave;
  end;
end;

{Enumerates supported files in ADir and returns their base names sorted
 case-insensitively. Shared by FindAdjacentFile and GetFilePosition so
 both use the exact same ordering. Step 111 adds the cache wrapper;
 the underlying scan logic is unchanged.}
function CollectSupportedFiles(const ADir, AExtensions: string): TArray<string>;
var
  Key, Ext: string;
  ExtList: TArray<string>;
  ExtSet: TDictionary<string, Boolean>;
  RawFiles: TStringDynArray;
  Sorted: TList<string>;
  I: Integer;
begin
  Result := nil;
  if (ADir = '') or not TDirectory.Exists(ADir) then
    Exit;

  Key := BuildCacheKey(ADir, AExtensions);
  GCacheLock.Enter;
  try
    if TryGetCached(Key, Result) then
      Exit;
  finally
    GCacheLock.Leave;
  end;

  ExtList := AExtensions.Split([',', ' ']);
  ExtSet := TDictionary<string, Boolean>.Create(Length(ExtList));
  try
    for I := 0 to High(ExtList) do
    begin
      Ext := ExtList[I].Trim;
      if Ext <> '' then
        ExtSet.AddOrSetValue('.' + Ext.ToUpper, True);
    end;
    if ExtSet.Count = 0 then
      Exit;

    RawFiles := TDirectory.GetFiles(ADir);
    Sorted := TList<string>.Create;
    try
      for I := 0 to High(RawFiles) do
      begin
        Ext := ExtractFileExt(RawFiles[I]).ToUpper;
        if ExtSet.ContainsKey(Ext) then
          Sorted.Add(ExtractFileName(RawFiles[I]));
      end;
      {Case-insensitive sort, same as TC's default alphabetical order}
      Sorted.Sort(TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          Result := CompareText(A, B);
        end));
      Result := Sorted.ToArray;
    finally
      Sorted.Free;
    end;
  finally
    ExtSet.Free;
  end;

  GCacheLock.Enter;
  try
    StoreInCache(Key, Result);
  finally
    GCacheLock.Leave;
  end;
end;

function IndexOfName(const AFiles: TArray<string>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AFiles) do
    if CompareText(AFiles[I], AName) = 0 then
      Exit(I);
  Result := -1;
end;

function FindAdjacentFile(const ACurrentFile, AExtensions: string; ADelta: Integer): string;
var
  Dir, CurName: string;
  Files: TArray<string>;
  CurIdx, NewIdx: Integer;
begin
  Result := '';
  Dir := ExtractFilePath(ACurrentFile);
  CurName := ExtractFileName(ACurrentFile);
  Files := CollectSupportedFiles(Dir, AExtensions);
  if Length(Files) < 2 then
    Exit;
  CurIdx := IndexOfName(Files, CurName);
  if CurIdx < 0 then
    Exit;
  {Double-mod keeps the result non-negative even for large negative deltas;
   plain Delphi mod preserves the dividend's sign.}
  NewIdx := ((CurIdx + ADelta) mod Length(Files) + Length(Files)) mod Length(Files);
  Result := Dir + Files[NewIdx];
end;

function GetFilePosition(const ACurrentFile, AExtensions: string; out AIndex, ATotal: Integer): Boolean;
var
  Dir, CurName: string;
  Files: TArray<string>;
  Idx: Integer;
begin
  AIndex := 0;
  ATotal := 0;
  Result := False;
  Dir := ExtractFilePath(ACurrentFile);
  CurName := ExtractFileName(ACurrentFile);
  Files := CollectSupportedFiles(Dir, AExtensions);
  if Length(Files) = 0 then
    Exit;
  Idx := IndexOfName(Files, CurName);
  if Idx < 0 then
    Exit;
  AIndex := Idx + 1;
  ATotal := Length(Files);
  Result := True;
end;

initialization
  GCacheLock := TCriticalSection.Create;

finalization
  ClearDirectoryCache;
  GCacheLock.Free;

end.
