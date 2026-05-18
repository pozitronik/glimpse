{Disk cache for extracted video frames.
 Composes:
   - ICacheStorage  (atomic byte-keyed storage, see uCacheStorage)
   - TLruEvictionPolicy (uLruEvictionPolicy)
   - PNG encoding/decoding (uBitmapSaver)
 TFrameCache itself only owns the lock, the bitmap<->bytes encoding, and
 the hash-key computation from file metadata. The disk layout and the
 LRU algorithm live in their own units so each can be tested in
 isolation against a memory-backed storage fake.}
unit uCache;

interface

uses
  System.SysUtils, System.SyncObjs,
  Vcl.Graphics,
  uCacheStorage, uLruEvictionPolicy;

type
  {Lookup identity for a cached frame. Bundles the four fields that made the
   old IFrameCache.TryGet / Put signatures a 4-arity parade and lets call
   sites compute the key once, reuse it for both get and put.}
  TFrameCacheKey = record
    {Video file path. Lowercased before hashing so case-insensitive Windows
     paths don't produce divergent cache entries.}
    FilePath: string;
    {Frame offset in seconds (accurate-seek or keyframe-snap time).}
    TimeOffset: Double;
    {Longest-side scale cap. 0 means the original (unscaled) entry.}
    MaxSide: Integer;
    {True for keyframe-only seek (faster, coarser). Keyframe and accurate
     entries live side-by-side — this flag disambiguates them.}
    UseKeyframes: Boolean;

    class function Create(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): TFrameCacheKey; static;
  end;

  {Core cache contract: retrieve and store video frames by file identity
   and time offset. Implementations decide whether caching actually occurs.}
  IFrameCache = interface
    ['{A7E3B2C1-4D5F-6E7A-8B9C-0D1E2F3A4B5C}']
    {Loads a cached frame matching AKey.
     Returns nil on miss or if caching is not supported. Caller owns the bitmap.}
    function TryGet(const AKey: TFrameCacheKey): TBitmap;
    {Stores a frame bitmap under AKey. Implementations may copy the bitmap
     to disk; the caller retains ownership of ABitmap.}
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
  end;

  {Cache management operations: size queries, eviction, clearing.
   Separated from IFrameCache so read/write callers don't see admin ops.}
  ICacheManager = interface
    ['{B8F4C3D2-5E6A-7F8B-9C0D-1E2F3A4B5C6D}']
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

  {Abstract base providing the IFrameCache contract for concrete implementations.}
  TFrameCacheBase = class(TInterfacedObject, IFrameCache)
  public
    function TryGet(const AKey: TFrameCacheKey): TBitmap; virtual; abstract;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); virtual; abstract;
  end;

  {No-op cache: always misses, never stores. Used when caching is disabled
   so callers don't need nil checks.}
  TNullFrameCache = class(TFrameCacheBase)
  public
    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;
  end;

  {Decorator that skips cache reads but delegates writes to the inner cache.
   Used for forced re-extraction (Refresh) where we want fresh frames
   but still want to update the cache with the new results.}
  TBypassFrameCache = class(TFrameCacheBase)
  strict private
    FInner: IFrameCache;
  public
    constructor Create(const AInner: IFrameCache);
    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;
  end;

  {Decorator that delegates reads but drops writes. Used for random
   extraction when the user has CacheRandomFrames disabled: a previously
   cached random pick can still hit (cheap), but new picks do not
   pollute the cache. Mirror image of TBypassFrameCache; the two narrow
   types are easier to reason about than one configurable wrapper.}
  TReadOnlyFrameCache = class(TFrameCacheBase)
  strict private
    FInner: IFrameCache;
  public
    constructor Create(const AInner: IFrameCache);
    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;
  end;

  {Real disk cache. Thin composition over ICacheStorage + TLruEvictionPolicy.
   Owns the lock that serialises every public op; the storage and policy
   collaborators are non-thread-safe and trust the cache to call them
   from inside the critical section.}
  TFrameCache = class(TFrameCacheBase, ICacheManager)
  strict private
    FCacheDir: string;
    FStorage: ICacheStorage;
    FPolicy: TLruEvictionPolicy;
    {Serialises every public operation. NTFS rename is atomic, so a
     concurrent TryGet during a Put already sees old-or-new but never
     partial; the lock additionally guards Evict's directory walk
     against a Put adding new entries mid-scan and the GetTotalSize /
     Clear admin paths against in-flight reads. Lock is held across the
     PNG encode + storage write inside Put; workers therefore serialise
     on cache writes, which is acceptable given typical frame sizes and
     the disk being the real bottleneck anyway.}
    FLock: TCriticalSection;
  public
    constructor Create(const ACacheDir: string; AMaxSizeMB: Integer);
    destructor Destroy; override;

    {Generates a cache key hash string for a frame by reading file metadata
     from disk. Returns empty string if the file cannot be stat'd.
     Kept with the 4-param signature (not TFrameCacheKey) because it's a
     low-level utility used by tests and exposed independently of the
     interface — call sites there don't benefit from the record form.}
    class function FrameKey(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): string; static;

    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;

    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;

    property CacheDir: string read FCacheDir;
  end;

  {Creates an ICacheManager backed by disk cache.
   Callers use the interface for admin ops without depending on TFrameCache.}
function CreateCacheManager(const ACacheDir: string; AMaxSizeMB: Integer): ICacheManager;

implementation

uses
  System.IOUtils, System.Classes,
  Vcl.Imaging.pngimage,
  uDebugLog, uCacheKey, uBitmapSaver;

{Test- and cache-internal helper: encode a bitmap to PNG bytes using
 fast compression (CompressionLevel=1 matches the previous behaviour
 of writing cache PNGs directly via TPngImage).}
function EncodeBitmapToPngBytes(ABitmap: TBitmap): TBytes;
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create;
  try
    EncodeBitmapAsPng(ABitmap, Stream, 1);
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Move(Stream.Bytes[0], Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

{TFrameCacheKey}

class function TFrameCacheKey.Create(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): TFrameCacheKey;
begin
  Result.FilePath := AFilePath;
  Result.TimeOffset := ATimeOffset;
  Result.MaxSide := AMaxSide;
  Result.UseKeyframes := AUseKeyframes;
end;

{TNullFrameCache}

function TNullFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
begin
  Result := nil;
end;

procedure TNullFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
begin
  {Intentionally empty}
end;

{TBypassFrameCache}

constructor TBypassFrameCache.Create(const AInner: IFrameCache);
begin
  inherited Create;
  FInner := AInner;
end;

function TBypassFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
begin
  Result := nil;
end;

procedure TBypassFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
begin
  FInner.Put(AKey, ABitmap);
end;

{TReadOnlyFrameCache}

constructor TReadOnlyFrameCache.Create(const AInner: IFrameCache);
begin
  inherited Create;
  FInner := AInner;
end;

function TReadOnlyFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
begin
  Result := FInner.TryGet(AKey);
end;

procedure TReadOnlyFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
begin
  {Intentional no-op: random extractions with CacheRandomFrames=False
   read from the disk cache when an offset happens to be cached, but
   never write fresh picks back.}
end;

{TFrameCache}

constructor TFrameCache.Create(const ACacheDir: string; AMaxSizeMB: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FCacheDir := ACacheDir;
  FStorage := TDiskCacheStorage.Create(ACacheDir, '.png');
  FPolicy := TLruEvictionPolicy.Create(Int64(AMaxSizeMB) * 1024 * 1024);
  DebugLog('Cache', Format('Create: dir=%s maxMB=%d', [ACacheDir, AMaxSizeMB]));
end;

destructor TFrameCache.Destroy;
begin
  FPolicy.Free;
  {FStorage is an interface; refcount drops to zero with the field clearing}
  FLock.Free;
  inherited;
end;

class function TFrameCache.FrameKey(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): string;
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
    Result := CacheHashKey(BuildFrameCacheKeyString(AFilePath, FileSize, FileTime, ATimeOffset, AMaxSide, AUseKeyframes));
  except
    {File inaccessible - return empty, caller treats as cache miss}
  end;
end;

function TFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
var
  Key: string;
  Data: TBytes;
begin
  Result := nil;
  Key := FrameKey(AKey.FilePath, AKey.TimeOffset, AKey.MaxSide, AKey.UseKeyframes);
  if Key = '' then
    Exit;
  FLock.Enter;
  try
    try
      Data := FStorage.Read(Key);
      if Length(Data) = 0 then
      begin
        DebugLog('Cache', Format('TryGet MISS (no file) key=%s', [Key]));
        Exit;
      end;
      DebugLog('Cache', Format('TryGet key=%s fileBytes=%d', [Key, Length(Data)]));
      Result := PngBytesToBitmap(Data);
      DebugLog('Cache', Format('  BMP loaded: %dx%d empty=%s pf=%d', [Result.Width, Result.Height, BoolToStr(Result.Empty, True), Ord(Result.PixelFormat)]));
    except
      on E: Exception do
      begin
        DebugLog('Cache', Format('TryGet EXCEPTION key=%s %s: %s', [Key, E.ClassName, E.Message]));
        FreeAndNil(Result);
      end;
    end;
    if Result <> nil then
      FStorage.Touch(Key);
  finally
    FLock.Leave;
  end;
end;

procedure TFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
var
  Key: string;
  Data: TBytes;
begin
  if ABitmap = nil then
    Exit;
  Key := FrameKey(AKey.FilePath, AKey.TimeOffset, AKey.MaxSide, AKey.UseKeyframes);
  if Key = '' then
    Exit;
  DebugLog('Cache', Format('Put key=%s bmp=%dx%d', [Key, ABitmap.Width, ABitmap.Height]));
  FLock.Enter;
  try
    try
      Data := EncodeBitmapToPngBytes(ABitmap);
      DebugLog('Cache', Format('  encoded pngSize=%d', [Length(Data)]));
      FStorage.Write(Key, Data);
    except
      on E: Exception do
        DebugLog('Cache', Format('Put EXCEPTION key=%s %s: %s', [Key, E.ClassName, E.Message]));
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TFrameCache.Clear;
begin
  FLock.Enter;
  try
    FStorage.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TFrameCache.Evict;
begin
  FLock.Enter;
  try
    FPolicy.Evict(FStorage);
  finally
    FLock.Leave;
  end;
end;

function TFrameCache.GetTotalSize: Int64;
var
  Entries: TArray<TCacheEntryInfo>;
  I: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    Entries := FStorage.List;
    for I := 0 to High(Entries) do
      Result := Result + Entries[I].Size;
  finally
    FLock.Leave;
  end;
end;

function CreateCacheManager(const ACacheDir: string; AMaxSizeMB: Integer): ICacheManager;
begin
  Result := TFrameCache.Create(ACacheDir, AMaxSizeMB);
end;

end.
