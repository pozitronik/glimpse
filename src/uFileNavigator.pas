{Sibling-file navigation with an in-memory listing cache keyed by
 (dir, mtime, extensions). NTFS mtime invalidation is automatic.
 Round-robin eviction at CACHE_CAPACITY. Single lock for thread safety.}
unit uFileNavigator;

interface

{ADelta=+1 next, -1 previous. AExtensions is comma-separated. Empty
 string when fewer than two siblings; wraps around at boundaries.}
function FindAdjacentFile(const ACurrentFile, AExtensions: string; ADelta: Integer): string;

{1-based AIndex within sorted siblings, plus total. False with zeros
 when directory unreadable or current file not in list.}
function GetFilePosition(const ACurrentFile, AExtensions: string; out AIndex, ATotal: Integer): Boolean;

{Test-only; production never needs to call this.}
procedure ClearDirectoryCache;

function DirectoryCacheSize: Integer;

implementation

uses
  System.SysUtils, System.IOUtils, System.Types, System.Classes,
  System.Generics.Collections, System.Generics.Defaults,
  System.SyncObjs;

const
  {8 covers TC's typical left + right panel + recent-navigation pattern.}
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

{Trimmed, lowercased, sorted, deduplicated for stable cache key.}
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

{'0' on failure means the cache key never matches a successful entry,
 so the cache bypasses until the directory is readable again.}
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

{Shared by FindAdjacentFile and GetFilePosition so ordering matches.}
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
  {Double-mod keeps the result non-negative for negative deltas;
   Delphi's mod preserves the dividend's sign.}
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
