{Byte-keyed cache storage abstraction.

 ICacheStorage exposes the minimal operations a byte-cache needs:
 Read/Write/Delete/Clear, Touch (LRU access-time bump), and List (for
 eviction policies to enumerate entries with size + access metadata).
 The interface is intentionally narrow — anything caller-specific
 (PNG encoding, lock acquisition, key hashing) lives above this layer.

 TDiskCacheStorage is the production implementation: it stores each
 entry as `<root>\<2-char-shard>\<key>.<ext>`, writes atomically via
 MoveFileEx with MOVEFILE_REPLACE_EXISTING, and sweeps orphaned `.tmp`
 files at construction. The legacy on-disk layout (sharded dir +
 `.png` extension) is preserved so existing user caches keep working
 after the TFrameCache refactor.

 Implementations make no thread-safety claim — the caller (TFrameCache)
 is the composition root that owns the lock and serialises every
 invocation. Tests of an eviction policy can use a TMemoryCacheStorage
 fake (see tests/) to drive the policy without disk I/O.}
unit uCacheStorage;

interface

uses
  System.SysUtils;

type
  {Per-entry metadata returned by ICacheStorage.List. The policy uses
   Size for budget accounting and AccessTime for LRU ordering; Key is
   the same string the caller originally passed to Write and is what
   Delete expects back.}
  TCacheEntryInfo = record
    Key: string;
    Size: Int64;
    AccessTime: TDateTime;
  end;

  {Minimal byte-keyed cache contract. Read returns an empty byte array
   on miss (or on read failure — both are caller-indistinguishable, by
   design). Write is atomic — readers concurrent with a Write see either
   the prior bytes or the new bytes, never a torn payload. Delete and
   Clear are best-effort: failures are swallowed because a cache cannot
   meaningfully recover from "the OS would not let us delete this".}
  ICacheStorage = interface
    ['{C7A4F1E8-5B2D-4E3A-9F6C-1D8E2A5B7C9F}']
    {Loads the bytes stored under AKey. Returns an empty TBytes (length=0)
     on miss or read failure.}
    function Read(const AKey: string): TBytes;
    {Stores ABytes under AKey, replacing any prior entry atomically.}
    procedure Write(const AKey: string; const AData: TBytes);
    {Removes the entry under AKey. Best-effort — silently no-ops if the
     entry doesn't exist or can't be deleted.}
    procedure Delete(const AKey: string);
    {Removes every entry. Best-effort.}
    procedure Clear;
    {Updates the LRU access timestamp for AKey to now. Best-effort —
     silently no-ops if the entry doesn't exist or the OS rejects the
     update. The LRU policy reads access time via List.}
    procedure Touch(const AKey: string);
    {Enumerates every stored entry with its size and access timestamp.
     Order is unspecified — the eviction policy sorts as needed.}
    function List: TArray<TCacheEntryInfo>;
  end;

  {Disk-backed storage with the existing sharded `.png` layout. Atomic
   writes via temp-file + MoveFileEx; orphaned `.tmp` files (left by a
   crash mid-write) are swept at construction. The extension is
   per-instance — production passes `.png` to match the legacy layout;
   tests could use any extension.}
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
  Winapi.Windows, System.IOUtils, uCacheKey;

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
  {Write writes <root>\<guid>.tmp and renames via MoveFileEx. If the
   process crashed between SaveToStream and the rename, the .tmp
   survived forever — there was no later sweep, and List only walks
   the configured extension. Wipe leftover temp files at construction
   so a crash-prone environment does not accumulate disk-leaking shards.}
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
      {Best-effort: a temp may still be locked by another instance
       holding the cache open for a different write-in-progress.
       Skipping leaves it for the next constructor call.}
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
    {Atomic replace: MoveFileEx with MOVEFILE_REPLACE_EXISTING is atomic
     on NTFS, eliminating the window where concurrent readers see no file.}
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
    {Best-effort clear; directory may be locked. Tear down what we can
     by walking shards individually as a fallback.}
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
      {Reconstruct the original key from the on-disk path. The layout
       is <root>\<2-char-shard>\<key>.<ext>; the shard prefix is derived
       deterministically from the key, so the file's basename without
       extension is the key.}
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
