{Frame cache for extracted video frames over an injected ICacheStorage.
 Composes the storage with an IEvictionPolicy and PNG encoding;
 TFrameCache owns only the lock, the bitmap-to-bytes encoding, and the
 hash-key computation.}
unit Cache;

interface

uses
  System.SysUtils, System.SyncObjs,
  Vcl.Graphics,
  CacheStorage, LruEvictionPolicy;

type
  TFrameCacheKey = record
    {Lowercased before hashing so case-insensitive Windows paths do not
     produce divergent cache entries.}
    FilePath: string;
    TimeOffset: Double;
    {0 means the original (unscaled) entry.}
    MaxSide: Integer;
    {Keyframe and accurate-seek entries coexist; this flag disambiguates.}
    UseKeyframes: Boolean;

    class function Create(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): TFrameCacheKey; static;
  end;

  IFrameCache = interface
    ['{A7E3B2C1-4D5F-6E7A-8B9C-0D1E2F3A4B5C}']
    {Caller owns the returned bitmap.}
    function TryGet(const AKey: TFrameCacheKey): TBitmap;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
  end;

  {Separate from IFrameCache so read/write callers do not see admin ops.}
  ICacheManager = interface
    ['{B8F4C3D2-5E6A-7F8B-9C0D-1E2F3A4B5C6D}']
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

  TFrameCacheBase = class(TInterfacedObject, IFrameCache)
  public
    function TryGet(const AKey: TFrameCacheKey): TBitmap; virtual; abstract;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); virtual; abstract;
  end;

  {No-op cache for the disabled-caching case so callers do not need nil
   checks. Implements ICacheManager so substitution stays uniform.}
  TNullFrameCache = class(TFrameCacheBase, ICacheManager)
  public
    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

  {Used for forced re-extraction (Refresh): skip reads, still write.
   Admin ops propagate to the inner.}
  TBypassFrameCache = class(TFrameCacheBase, ICacheManager)
  strict private
    FInner: IFrameCache;
    FInnerMgr: ICacheManager;
  public
    constructor Create(const AInner: IFrameCache);
    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

  {Used for random extraction with CacheRandomFrames disabled: serve
   already-cached random picks but never write fresh ones back.}
  TReadOnlyFrameCache = class(TFrameCacheBase, ICacheManager)
  strict private
    FInner: IFrameCache;
    FInnerMgr: ICacheManager;
  public
    constructor Create(const AInner: IFrameCache);
    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;
    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

  {Owns the lock that serialises every public op; storage and policy
   collaborators are non-thread-safe and rely on the cache calling them
   inside the critical section.}
  TFrameCache = class(TFrameCacheBase, ICacheManager)
  strict private
    FStorage: ICacheStorage;
    FPolicy: IEvictionPolicy;
    FFileStat: IFileStat;
    FLock: TCriticalSection;
  public
    {Storage, eviction policy and file-stat are injected; tests pass
     fakes to run without a filesystem.}
    constructor Create(const AStorage: ICacheStorage;
      const APolicy: IEvictionPolicy; const AFileStat: IFileStat);
    destructor Destroy; override;

    {Returns empty when the file cannot be stat'd. AStat supplies the
     source-file identity (size and mtime) folded into the key.}
    class function FrameKey(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean; const AStat: IFileStat): string; static;

    function TryGet(const AKey: TFrameCacheKey): TBitmap; override;
    procedure Put(const AKey: TFrameCacheKey; ABitmap: TBitmap); override;

    procedure Clear;
    procedure Evict;
    function GetTotalSize: Int64;
  end;

implementation

uses
  System.Classes,
  Vcl.Imaging.pngimage,
  Logging, CacheKey, BitmapSaver;

{CompressionLevel=1 keeps cache writes fast at the cost of disk size.}
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

procedure TNullFrameCache.Clear;
begin
  {No-op: nothing has ever been stored.}
end;

procedure TNullFrameCache.Evict;
begin
  {No-op: nothing to evict.}
end;

function TNullFrameCache.GetTotalSize: Int64;
begin
  Result := 0;
end;

{TBypassFrameCache}

constructor TBypassFrameCache.Create(const AInner: IFrameCache);
begin
  inherited Create;
  FInner := AInner;
  {Cache the inner's admin facet so Supports runs once. nil = inner has
   no ICacheManager and admin ops become no-ops.}
  Supports(FInner, ICacheManager, FInnerMgr);
end;

function TBypassFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
begin
  Result := nil;
end;

procedure TBypassFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
begin
  FInner.Put(AKey, ABitmap);
end;

procedure TBypassFrameCache.Clear;
begin
  if FInnerMgr <> nil then
    FInnerMgr.Clear;
end;

procedure TBypassFrameCache.Evict;
begin
  if FInnerMgr <> nil then
    FInnerMgr.Evict;
end;

function TBypassFrameCache.GetTotalSize: Int64;
begin
  if FInnerMgr <> nil then
    Result := FInnerMgr.GetTotalSize
  else
    Result := 0;
end;

{TReadOnlyFrameCache}

constructor TReadOnlyFrameCache.Create(const AInner: IFrameCache);
begin
  inherited Create;
  FInner := AInner;
  Supports(FInner, ICacheManager, FInnerMgr);
end;

function TReadOnlyFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
begin
  Result := FInner.TryGet(AKey);
end;

procedure TReadOnlyFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
begin
  {Intentional no-op.}
end;

procedure TReadOnlyFrameCache.Clear;
begin
  if FInnerMgr <> nil then
    FInnerMgr.Clear;
end;

procedure TReadOnlyFrameCache.Evict;
begin
  if FInnerMgr <> nil then
    FInnerMgr.Evict;
end;

function TReadOnlyFrameCache.GetTotalSize: Int64;
begin
  if FInnerMgr <> nil then
    Result := FInnerMgr.GetTotalSize
  else
    Result := 0;
end;

{TFrameCache}

constructor TFrameCache.Create(const AStorage: ICacheStorage;
  const APolicy: IEvictionPolicy; const AFileStat: IFileStat);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FStorage := AStorage;
  FPolicy := APolicy;
  FFileStat := AFileStat;
end;

destructor TFrameCache.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TFrameCache.FrameKey(const AFilePath: string; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean; const AStat: IFileStat): string;
var
  FileSize: Int64;
  FileTime: TDateTime;
begin
  Result := '';
  if not AStat.TryStat(AFilePath, FileSize, FileTime) then
    Exit;
  Result := CacheHashKey(BuildFrameCacheKeyString(AFilePath, FileSize, FileTime, ATimeOffset, AMaxSide, AUseKeyframes));
end;

function TFrameCache.TryGet(const AKey: TFrameCacheKey): TBitmap;
var
  Key: string;
  Data: TBytes;
  PngSize: Integer;
  Loaded: Boolean;
  ReadFailed: Boolean;
  ExceptionMsg: string;
  BmpW, BmpH, BmpPf: Integer;
  BmpEmpty: Boolean;
begin
  Result := nil;
  Key := FrameKey(AKey.FilePath, AKey.TimeOffset, AKey.MaxSide, AKey.UseKeyframes, FFileStat);
  if Key = '' then
    Exit;
  PngSize := 0;
  Loaded := False;
  ReadFailed := False;
  ExceptionMsg := '';
  BmpW := 0; BmpH := 0; BmpPf := 0; BmpEmpty := True;
  FLock.Enter;
  try
    try
      Data := FStorage.Read(Key);
      PngSize := Length(Data);
      if PngSize > 0 then
      begin
        Result := PngBytesToBitmap(Data);
        if Result <> nil then
        begin
          Loaded := True;
          BmpW := Result.Width;
          BmpH := Result.Height;
          BmpEmpty := Result.Empty;
          BmpPf := Ord(Result.PixelFormat);
        end;
      end;
    except
      on E: Exception do
      begin
        ReadFailed := True;
        ExceptionMsg := Format('%s: %s', [E.ClassName, E.Message]);
        FreeAndNil(Result);
      end;
    end;
    if Result <> nil then
      FStorage.Touch(Key);
  finally
    FLock.Leave;
  end;
  {Log outside the critical section so workers do not serialise on
   DebugLog I/O.}
  if ReadFailed then
    DebugLog('Cache', Format('TryGet EXCEPTION key=%s %s', [Key, ExceptionMsg]))
  else if PngSize = 0 then
    DebugLog('Cache', Format('TryGet MISS (no file) key=%s', [Key]))
  else
  begin
    DebugLog('Cache', Format('TryGet key=%s fileBytes=%d', [Key, PngSize]));
    if Loaded then
      DebugLog('Cache', Format('  BMP loaded: %dx%d empty=%s pf=%d', [BmpW, BmpH, BoolToStr(BmpEmpty, True), BmpPf]));
  end;
end;

procedure TFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
var
  Key: string;
  Data: TBytes;
  PngSize: Integer;
  WriteFailed: Boolean;
  ExceptionMsg: string;
begin
  if ABitmap = nil then
    Exit;
  Key := FrameKey(AKey.FilePath, AKey.TimeOffset, AKey.MaxSide, AKey.UseKeyframes, FFileStat);
  if Key = '' then
    Exit;
  DebugLog('Cache', Format('Put key=%s bmp=%dx%d', [Key, ABitmap.Width, ABitmap.Height]));
  PngSize := 0;
  WriteFailed := False;
  ExceptionMsg := '';
  FLock.Enter;
  try
    try
      Data := EncodeBitmapToPngBytes(ABitmap);
      PngSize := Length(Data);
      FStorage.Write(Key, Data);
    except
      on E: Exception do
      begin
        WriteFailed := True;
        ExceptionMsg := Format('%s: %s', [E.ClassName, E.Message]);
      end;
    end;
  finally
    FLock.Leave;
  end;
  if WriteFailed then
    DebugLog('Cache', Format('Put EXCEPTION key=%s %s', [Key, ExceptionMsg]))
  else
    DebugLog('Cache', Format('  encoded pngSize=%d', [PngSize]));
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

end.
