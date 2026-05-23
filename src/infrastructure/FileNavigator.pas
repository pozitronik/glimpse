{Sibling-file navigation with an in-memory listing cache keyed by
 (dir, mtime, extensions). NTFS mtime invalidation is automatic.
 Round-robin eviction at CACHE_CAPACITY. Each TFileNavigator owns its
 own cache, guarded by a per-instance lock for thread safety.}
unit FileNavigator;

interface

type
  {Sibling-file navigation over a directory listing. Each instance owns
   its cache, so a fresh navigator starts from a clean state.}
  IFileNavigator = interface
    ['{6C3F8A2E-1D74-4B59-A8E0-3F7C2B9D5061}']
    {ADelta=+1 next, -1 previous. AExtensions is comma-separated. Empty
     string when fewer than two siblings; wraps around at boundaries.}
    function FindAdjacentFile(const ACurrentFile, AExtensions: string; ADelta: Integer): string;

    {1-based AIndex within sorted siblings, plus total. False with zeros
     when directory unreadable or current file not in list.}
    function GetFilePosition(const ACurrentFile, AExtensions: string; out AIndex, ATotal: Integer): Boolean;
  end;

  {Diagnostic facet for cache observability (currently used by tests).
   Separate from IFileNavigator so production consumers depend only on
   the navigation surface.}
  IFileNavigatorDiagnostics = interface
    ['{8D5F6B91-3C7E-4A2D-9B1F-6A4E0C8D5F92}']
    function DirectoryCacheSize: Integer;
  end;

function CreateFileNavigator: IFileNavigator;

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

  TFileNavigator = class(TInterfacedObject, IFileNavigator, IFileNavigatorDiagnostics)
  strict private
    FCacheLock: TCriticalSection;
    FCache: array[0..CACHE_CAPACITY - 1] of TDirCacheEntry;
    FCacheCount: Integer;
    FCacheNext: Integer;
    function TryGetCached(const AKey: string; out AFiles: TArray<string>): Boolean;
    procedure StoreInCache(const AKey: string; const AFiles: TArray<string>);
    function CollectSupportedFiles(const ADir, AExtensions: string): TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function FindAdjacentFile(const ACurrentFile, AExtensions: string; ADelta: Integer): string;
    function GetFilePosition(const ACurrentFile, AExtensions: string; out AIndex, ATotal: Integer): Boolean;
    function DirectoryCacheSize: Integer;
  end;

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

function IndexOfName(const AFiles: TArray<string>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AFiles) do
    if CompareText(AFiles[I], AName) = 0 then
      Exit(I);
  Result := -1;
end;

{ TFileNavigator }

constructor TFileNavigator.Create;
begin
  inherited Create;
  FCacheLock := TCriticalSection.Create;
end;

destructor TFileNavigator.Destroy;
begin
  FCacheLock.Free;
  inherited;
end;

function TFileNavigator.TryGetCached(const AKey: string; out AFiles: TArray<string>): Boolean;
var
  I: Integer;
begin
  for I := 0 to FCacheCount - 1 do
    if FCache[I].Key = AKey then
    begin
      AFiles := FCache[I].Files;
      Exit(True);
    end;
  AFiles := nil;
  Result := False;
end;

procedure TFileNavigator.StoreInCache(const AKey: string; const AFiles: TArray<string>);
begin
  FCache[FCacheNext].Key := AKey;
  FCache[FCacheNext].Files := AFiles;
  FCacheNext := (FCacheNext + 1) mod CACHE_CAPACITY;
  if FCacheCount < CACHE_CAPACITY then
    Inc(FCacheCount);
end;

function TFileNavigator.DirectoryCacheSize: Integer;
begin
  FCacheLock.Enter;
  try
    Result := FCacheCount;
  finally
    FCacheLock.Leave;
  end;
end;

{Shared by FindAdjacentFile and GetFilePosition so ordering matches.}
function TFileNavigator.CollectSupportedFiles(const ADir, AExtensions: string): TArray<string>;
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
  FCacheLock.Enter;
  try
    if TryGetCached(Key, Result) then
      Exit;
  finally
    FCacheLock.Leave;
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

  FCacheLock.Enter;
  try
    StoreInCache(Key, Result);
  finally
    FCacheLock.Leave;
  end;
end;

function TFileNavigator.FindAdjacentFile(const ACurrentFile, AExtensions: string;
  ADelta: Integer): string;
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

function TFileNavigator.GetFilePosition(const ACurrentFile, AExtensions: string;
  out AIndex, ATotal: Integer): Boolean;
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

function CreateFileNavigator: IFileNavigator;
begin
  Result := TFileNavigator.Create;
end;

end.
