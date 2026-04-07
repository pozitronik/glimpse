{ Disk cache for extracted video frames.
  Stores frames as PNG files in a sharded directory structure, keyed by
  video file metadata and frame time offset. Provides LRU eviction. }
unit uCache;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Hash,
  System.Generics.Collections, System.Generics.Defaults,
  Vcl.Graphics, Vcl.Imaging.pngimage, uBitmapSaver;

type
  { Core cache contract: retrieve and store video frames by file identity
    and time offset. Implementations decide whether caching actually occurs. }
  IFrameCache = interface
    ['{A7E3B2C1-4D5F-6E7A-8B9C-0D1E2F3A4B5C}']
    { Loads a cached frame for the given video file at the specified offset.
      AMaxSide > 0 narrows lookup to scaled variant; 0 means full resolution.
      Returns nil on miss or if caching is not supported. Caller owns the bitmap. }
    function TryGet(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer): TBitmap;
    { Stores a frame bitmap for the given video file at the specified offset. }
    procedure Put(const AFilePath: string; ATimeOffset: Double;
      ABitmap: TBitmap; AMaxSide: Integer);
  end;

  { Cache management operations: size queries, eviction, clearing.
    Separated from IFrameCache so read/write callers don't see admin ops. }
  ICacheManager = interface
    ['{B8F4C3D2-5E6A-7F8B-9C0D-1E2F3A4B5C6D}']
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

  { Abstract base providing the IFrameCache contract for concrete implementations. }
  TFrameCacheBase = class(TInterfacedObject, IFrameCache)
  public
    function TryGet(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer): TBitmap; virtual; abstract;
    procedure Put(const AFilePath: string; ATimeOffset: Double;
      ABitmap: TBitmap; AMaxSide: Integer); virtual; abstract;
  end;

  { No-op cache: always misses, never stores. Used when caching is disabled
    so callers don't need nil checks. }
  TNullFrameCache = class(TFrameCacheBase)
  public
    function TryGet(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer): TBitmap; override;
    procedure Put(const AFilePath: string; ATimeOffset: Double;
      ABitmap: TBitmap; AMaxSide: Integer); override;
  end;

  { Decorator that skips cache reads but delegates writes to the inner cache.
    Used for forced re-extraction (Refresh) where we want fresh frames
    but still want to update the cache with the new results. }
  TBypassFrameCache = class(TFrameCacheBase)
  strict private
    FInner: IFrameCache;
  public
    constructor Create(const AInner: IFrameCache);
    function TryGet(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer): TBitmap; override;
    procedure Put(const AFilePath: string; ATimeOffset: Double;
      ABitmap: TBitmap; AMaxSide: Integer); override;
  end;

  { Real disk cache with sharded PNG storage and LRU eviction. }
  TFrameCache = class(TFrameCacheBase, ICacheManager)
  strict private
    FCacheDir: string;
    FMaxSizeBytes: Int64;

    class function BuildKeyString(const AFilePath: string; AFileSize: Int64;
      AFileTime: TDateTime; ATimeOffset: Double; AMaxSide: Integer): string; static;
    class function HashKey(const AKeyString: string): string; static;
    function KeyToPath(const AKey: string): string;

  public
    constructor Create(const ACacheDir: string; AMaxSizeMB: Integer);

    { Generates a cache key for a frame by reading file metadata from disk.
      Returns empty string if the file cannot be stat'd. }
    class function FrameKey(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer): string; static;

    function TryGet(const AFilePath: string; ATimeOffset: Double;
      AMaxSide: Integer): TBitmap; override;
    procedure Put(const AFilePath: string; ATimeOffset: Double;
      ABitmap: TBitmap; AMaxSide: Integer); override;

    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;

    property CacheDir: string read FCacheDir;
  end;

{ Creates an ICacheManager backed by disk cache.
  Callers use the interface for admin ops without depending on TFrameCache. }
function CreateCacheManager(const ACacheDir: string; AMaxSizeMB: Integer): ICacheManager;

implementation

uses
  System.DateUtils, uDebugLog;

const
  MOVEFILE_REPLACE_EXISTING = 1;
  SHARD_PREFIX_LEN = 2; { directory sharding depth: first N chars of the hash key }

function MoveFileEx(lpExistingFileName, lpNewFileName: PChar; dwFlags: Cardinal): LongBool; stdcall; external 'kernel32.dll' name 'MoveFileExW';

{ Invariant format settings for deterministic key strings }
var
  InvFmt: TFormatSettings;

{ TNullFrameCache }

function TNullFrameCache.TryGet(const AFilePath: string; ATimeOffset: Double;
  AMaxSide: Integer): TBitmap;
begin
  Result := nil;
end;

procedure TNullFrameCache.Put(const AFilePath: string; ATimeOffset: Double;
  ABitmap: TBitmap; AMaxSide: Integer);
begin
  { Intentionally empty }
end;

{ TBypassFrameCache }

constructor TBypassFrameCache.Create(const AInner: IFrameCache);
begin
  inherited Create;
  FInner := AInner;
end;

function TBypassFrameCache.TryGet(const AFilePath: string; ATimeOffset: Double;
  AMaxSide: Integer): TBitmap;
begin
  Result := nil;
end;

procedure TBypassFrameCache.Put(const AFilePath: string; ATimeOffset: Double;
  ABitmap: TBitmap; AMaxSide: Integer);
begin
  FInner.Put(AFilePath, ATimeOffset, ABitmap, AMaxSide);
end;

{ TFrameCache }

constructor TFrameCache.Create(const ACacheDir: string; AMaxSizeMB: Integer);
begin
  inherited Create;
  FCacheDir := ACacheDir;
  FMaxSizeBytes := Int64(AMaxSizeMB) * 1024 * 1024;
  if not TDirectory.Exists(FCacheDir) then
    TDirectory.CreateDirectory(FCacheDir);
  DebugLog('Cache', Format('Create: dir=%s maxMB=%d', [ACacheDir, AMaxSizeMB]));
end;

class function TFrameCache.BuildKeyString(const AFilePath: string;
  AFileSize: Int64; AFileTime: TDateTime; ATimeOffset: Double;
  AMaxSide: Integer): string;
begin
  Result := AnsiLowerCase(AFilePath) + '|' +
    IntToStr(AFileSize) + '|' +
    FormatDateTime('yyyymmddhhnnsszzz', AFileTime) + '|' +
    Format('%.3f', [ATimeOffset], InvFmt);
  { Append scaled resolution to distinguish from full-size cache entries }
  if AMaxSide > 0 then
    Result := Result + '|s' + IntToStr(AMaxSide);
end;

class function TFrameCache.HashKey(const AKeyString: string): string;
begin
  Result := THashMD5.GetHashString(AKeyString).ToLower;
end;

function TFrameCache.KeyToPath(const AKey: string): string;
begin
  Result := TPath.Combine(TPath.Combine(FCacheDir, Copy(AKey, 1, SHARD_PREFIX_LEN)), AKey + '.png');
end;

class function TFrameCache.FrameKey(const AFilePath: string; ATimeOffset: Double;
  AMaxSide: Integer): string;
var
  FileSize: Int64;
  FileTime: TDateTime;
begin
  Result := '';
  try
    if not TFile.Exists(AFilePath) then
      Exit;
    FileSize := TFile.GetSize(AFilePath);
    FileTime := TFile.GetLastWriteTime(AFilePath);
    Result := HashKey(BuildKeyString(AFilePath, FileSize, FileTime, ATimeOffset, AMaxSide));
  except
    { File inaccessible - return empty, caller treats as cache miss }
  end;
end;

function TFrameCache.TryGet(const AFilePath: string; ATimeOffset: Double;
  AMaxSide: Integer): TBitmap;
var
  Key, Path: string;
  Data: TBytes;
begin
  Result := nil;
  Key := FrameKey(AFilePath, ATimeOffset, AMaxSide);
  if Key = '' then
    Exit;
  try
    Path := KeyToPath(Key);
    if not TFile.Exists(Path) then
    begin
      DebugLog('Cache', Format('TryGet MISS (no file) key=%s', [Key]));
      Exit;
    end;

    Data := TFile.ReadAllBytes(Path);
    DebugLog('Cache', Format('TryGet key=%s fileBytes=%d', [Key, Length(Data)]));
    Result := PngBytesToBitmap(Data);
    DebugLog('Cache', Format('  BMP loaded: %dx%d empty=%s pf=%d',
      [Result.Width, Result.Height, BoolToStr(Result.Empty, True), Ord(Result.PixelFormat)]));
  except
    on E: Exception do
    begin
      DebugLog('Cache', Format('TryGet EXCEPTION key=%s %s: %s', [Key, E.ClassName, E.Message]));
      FreeAndNil(Result);
    end;
  end;

  { Update access time for LRU tracking; isolated so a failure here
    cannot discard the successfully loaded bitmap. }
  if Result <> nil then
  try
    TFile.SetLastAccessTime(KeyToPath(Key), Now);
  except
    { Access time is cosmetic for LRU; failure is harmless }
  end;
end;

procedure TFrameCache.Put(const AFilePath: string; ATimeOffset: Double;
  ABitmap: TBitmap; AMaxSide: Integer);
var
  Key, FinalPath, TempPath, SubDir: string;
  Png: TPngImage;
begin
  if ABitmap = nil then
    Exit;
  Key := FrameKey(AFilePath, ATimeOffset, AMaxSide);
  if Key = '' then
    Exit;
  DebugLog('Cache', Format('Put key=%s bmp=%dx%d', [Key, ABitmap.Width, ABitmap.Height]));
  try
    FinalPath := KeyToPath(Key);
    SubDir := ExtractFilePath(FinalPath);
    if not TDirectory.Exists(SubDir) then
      TDirectory.CreateDirectory(SubDir);

    { Write to temp file, then rename for atomicity }
    TempPath := TPath.Combine(FCacheDir, TGUID.NewGuid.ToString + '.tmp');
    Png := TPngImage.Create;
    try
      Png.Assign(ABitmap);
      Png.CompressionLevel := 1; { Fast compression for cache writes }
      Png.SaveToFile(TempPath);
      DebugLog('Cache', Format('  saved tmp=%s pngSize=%d', [TempPath, TFile.GetSize(TempPath)]));
    finally
      Png.Free;
    end;

    { Atomic replace: MoveFileEx with MOVEFILE_REPLACE_EXISTING is atomic
      on NTFS, eliminating the window where concurrent readers see no file }
    if not MoveFileEx(PChar(TempPath), PChar(FinalPath), MOVEFILE_REPLACE_EXISTING) then
    begin
      DebugLog('Cache', Format('  MoveFileEx failed err=%d', [GetLastError]));
      try
        if TFile.Exists(TempPath) then
          TFile.Delete(TempPath);
      except
        { Best-effort temp file cleanup }
      end;
      Exit;
    end;
    DebugLog('Cache', Format('  moved to %s', [FinalPath]));
  except
    on E: Exception do
    begin
      DebugLog('Cache', Format('Put EXCEPTION key=%s %s: %s', [Key, E.ClassName, E.Message]));
      try
        if TFile.Exists(TempPath) then
          TFile.Delete(TempPath);
      except
        { Best-effort temp file cleanup }
      end;
    end;
  end;
end;

procedure TFrameCache.Clear;
begin
  try
    if TDirectory.Exists(FCacheDir) then
      TDirectory.Delete(FCacheDir, True);
    TDirectory.CreateDirectory(FCacheDir);
  except
    { Best-effort clear; directory may be locked }
  end;
end;

procedure TFrameCache.Evict;
type
  TCacheFileInfo = record
    Path: string;
    Size: Int64;
    AccessTime: TDateTime;
  end;
var
  Infos: TList<TCacheFileInfo>;
  Info: TCacheFileInfo;
  TotalSize: Int64;
  Dirs: TArray<string>;
  Dir: string;
begin
  if not TDirectory.Exists(FCacheDir) then
    Exit;

  Infos := TList<TCacheFileInfo>.Create;
  try
    TotalSize := 0;
    try
      for var FileName in TDirectory.GetFiles(FCacheDir, '*.png', TSearchOption.soAllDirectories) do
      begin
        try
          Info.Path := FileName;
          Info.Size := TFile.GetSize(FileName);
          Info.AccessTime := TFile.GetLastAccessTime(FileName);
          Infos.Add(Info);
          TotalSize := TotalSize + Info.Size;
        except
          { Skip files we cannot stat }
        end;
      end;
    except
      Exit; { Directory inaccessible; nothing to evict }
    end;

    if TotalSize <= FMaxSizeBytes then
      Exit;

    { Sort by access time ascending (oldest first) }
    Infos.Sort(TComparer<TCacheFileInfo>.Construct(
      function(const A, B: TCacheFileInfo): Integer
      begin
        Result := CompareDateTime(A.AccessTime, B.AccessTime);
      end));

    { Delete oldest files until within budget }
    for Info in Infos do
    begin
      if TotalSize <= FMaxSizeBytes then
        Break;
      try
        TFile.Delete(Info.Path);
        TotalSize := TotalSize - Info.Size;
      except
        { File may be locked by another TC instance }
      end;
    end;

    { Clean up empty subdirectories }
    try
      Dirs := TDirectory.GetDirectories(FCacheDir);
      for Dir in Dirs do
      begin
        try
          if Length(TDirectory.GetFiles(Dir)) = 0 then
            TDirectory.Delete(Dir, False);
        except
          { Skip dirs that can't be removed }
        end;
      end;
    except
      { Subdirectory enumeration failed; not critical }
    end;
  finally
    Infos.Free;
  end;
end;

function TFrameCache.GetTotalSize: Int64;
var
  Files: TArray<string>;
  FileName: string;
begin
  Result := 0;
  if not TDirectory.Exists(FCacheDir) then
    Exit;
  try
    Files := TDirectory.GetFiles(FCacheDir, '*.png', TSearchOption.soAllDirectories);
    for FileName in Files do
    begin
      try
        Result := Result + TFile.GetSize(FileName);
      except
        { Skip files we cannot stat }
      end;
    end;
  except
    { Directory enumeration failed; return partial result }
  end;
end;

function CreateCacheManager(const ACacheDir: string; AMaxSizeMB: Integer): ICacheManager;
begin
  Result := TFrameCache.Create(ACacheDir, AMaxSizeMB);
end;

initialization
  InvFmt := TFormatSettings.Invariant;

end.
