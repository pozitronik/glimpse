{Byte-keyed cache storage. TDiskCacheStorage stores entries as
 <root>\<2-char-shard>\<key>.<ext> with atomic writes via MoveFileEx.
 Not thread-safe — the caller (TFrameCache) owns the lock.}
unit CacheStorage;

interface

uses
  System.SysUtils;

type
  TCacheEntryInfo = record
    Key: string;
    Size: Int64;
    AccessTime: TDateTime;
  end;

  {Read returns empty bytes on miss or failure (indistinguishable by
   design). Write is atomic — readers see prior or new bytes, never
   torn. Delete/Clear are best-effort.}
  ICacheStorage = interface
    ['{C7A4F1E8-5B2D-4E3A-9F6C-1D8E2A5B7C9F}']
    function Read(const AKey: string): TBytes;
    procedure Write(const AKey: string; const AData: TBytes);
    procedure Delete(const AKey: string);
    procedure Clear;
    procedure Touch(const AKey: string);
    function List: TArray<TCacheEntryInfo>;
  end;

  TDiskCacheStorage = class(TInterfacedObject, ICacheStorage)
  strict private
    FRoot: string;
    FExt: string;
    function PathFor(const AKey: string): string; inline;
    procedure SweepOrphanedTempFiles;
  public
    constructor Create(const ARoot, AExt: string);
    function Read(const AKey: string): TBytes;
    procedure Write(const AKey: string; const AData: TBytes);
    procedure Delete(const AKey: string);
    procedure Clear;
    procedure Touch(const AKey: string);
    function List: TArray<TCacheEntryInfo>;
  end;

implementation

uses
  Winapi.Windows, System.IOUtils, CacheKey;

const
  MOVEFILE_REPLACE_EXISTING = 1;

function MoveFileEx(lpExistingFileName, lpNewFileName: PChar; dwFlags: Cardinal): LongBool; stdcall; external 'kernel32.dll' name 'MoveFileExW';

{TDiskCacheStorage}

constructor TDiskCacheStorage.Create(const ARoot, AExt: string);
begin
  inherited Create;
  FRoot := ARoot;
  FExt := AExt;
  if not TDirectory.Exists(FRoot) then
    TDirectory.CreateDirectory(FRoot);
  SweepOrphanedTempFiles;
end;

function TDiskCacheStorage.PathFor(const AKey: string): string;
begin
  Result := ShardedKeyPath(FRoot, AKey, FExt);
end;

procedure TDiskCacheStorage.SweepOrphanedTempFiles;
var
  Files: TArray<string>;
  F: string;
begin
  {Sweep .tmp files left by a crash mid-rename; otherwise they accumulate
   indefinitely since List only walks the configured extension.}
  if not TDirectory.Exists(FRoot) then
    Exit;
  try
    Files := TDirectory.GetFiles(FRoot, '*.tmp', TSearchOption.soTopDirectoryOnly);
  except
    Exit;
  end;
  for F in Files do
    try
      TFile.Delete(F);
    except
      {Locked .tmp will be retried on next constructor call}
    end;
end;

function TDiskCacheStorage.Read(const AKey: string): TBytes;
var
  Path: string;
begin
  Result := nil;
  try
    Path := PathFor(AKey);
    if not TFile.Exists(Path) then
      Exit;
    Result := TFile.ReadAllBytes(Path);
  except
    Result := nil;
  end;
end;

procedure TDiskCacheStorage.Write(const AKey: string; const AData: TBytes);
var
  FinalPath, TempPath, SubDir: string;
begin
  FinalPath := PathFor(AKey);
  SubDir := ExtractFilePath(FinalPath);
  if not TDirectory.Exists(SubDir) then
    TDirectory.CreateDirectory(SubDir);

  TempPath := TPath.Combine(FRoot, TGUID.NewGuid.ToString + '.tmp');
  try
    TFile.WriteAllBytes(TempPath, AData);
    {NTFS atomic replace prevents concurrent readers seeing no file}
    if not MoveFileEx(PChar(TempPath), PChar(FinalPath), MOVEFILE_REPLACE_EXISTING) then
    begin
      try
        if TFile.Exists(TempPath) then
          TFile.Delete(TempPath);
      except
        {Best-effort temp file cleanup}
      end;
    end;
  except
    try
      if TFile.Exists(TempPath) then
        TFile.Delete(TempPath);
    except
      {Best-effort temp file cleanup}
    end;
  end;
end;

procedure TDiskCacheStorage.Delete(const AKey: string);
var
  Path: string;
begin
  try
    Path := PathFor(AKey);
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  except
    {Best-effort delete}
  end;
end;

procedure TDiskCacheStorage.Clear;
var
  Dirs: TArray<string>;
  Dir: string;
begin
  try
    if TDirectory.Exists(FRoot) then
      TDirectory.Delete(FRoot, True);
    TDirectory.CreateDirectory(FRoot);
  except
    {Directory locked; tear down shards individually as fallback}
    try
      Dirs := TDirectory.GetDirectories(FRoot);
      for Dir in Dirs do
        try
          TDirectory.Delete(Dir, True);
        except
        end;
    except
    end;
  end;
end;

procedure TDiskCacheStorage.Touch(const AKey: string);
begin
  try
    TFile.SetLastAccessTime(PathFor(AKey), Now);
  except
    {Access time is cosmetic for LRU; failure is harmless}
  end;
end;

function TDiskCacheStorage.List: TArray<TCacheEntryInfo>;
var
  Files: TArray<string>;
  FileName, KeyOnly: string;
  Info: TCacheEntryInfo;
  Acc: TArray<TCacheEntryInfo>;
  Count: Integer;
begin
  Result := nil;
  if not TDirectory.Exists(FRoot) then
    Exit;
  try
    Files := TDirectory.GetFiles(FRoot, '*' + FExt, TSearchOption.soAllDirectories);
  except
    Exit;
  end;
  SetLength(Acc, Length(Files));
  Count := 0;
  for FileName in Files do
  begin
    try
      Info.Size := TFile.GetSize(FileName);
      Info.AccessTime := TFile.GetLastAccessTime(FileName);
      KeyOnly := TPath.GetFileNameWithoutExtension(FileName);
      if KeyOnly = '' then
        Continue;
      Info.Key := KeyOnly;
      Acc[Count] := Info;
      Inc(Count);
    except
      {Skip files we cannot stat}
    end;
  end;
  SetLength(Acc, Count);
  Result := Acc;
end;

end.
