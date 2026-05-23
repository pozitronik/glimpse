{Frame cache for extracted video frames over an injected ICacheStorage.
 Composes the storage with an IEvictionPolicy and PNG encoding;
 TFrameCache owns only the lock, the bitmap-to-bytes encoding, and the
 hash-key computation.}
unit Cache;

interface

uses
  System.SysUtils, System.SyncObjs,
  Vcl.Graphics,
  CacheContracts;

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

  {Best-effort cache contract. Implementations may legitimately discard a Put
   (no-op) or return nil from TryGet for valid configuration reasons —
   caching-disabled, refresh-bypass and read-only decorators all do.
   Callers MUST treat TryGet=nil as a miss and the original source as
   authoritative; they MUST NOT assume "I just wrote it, so a TryGet of the
   same key returns the same bitmap." Bitmap ownership: caller owns what
   TryGet returns; Put copies (encoded) so the caller still owns ABitmap.}
  IFrameCache = interface
    ['{A7E3B2C1-4D5F-6E7A-8B9C-0D1E2F3A4B5C}']
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

{TFrameCache logging. The outcome records ferry the facts a log line
 needs out of the critical section, so DebugLog can run unlocked.}

type
  TCacheReadLog = record
    Key: string;
    PngSize: Integer;
    Loaded: Boolean;
    ReadFailed: Boolean;
    ExceptionMsg: string;
    BmpW, BmpH, BmpPf: Integer;
    BmpEmpty: Boolean;
  end;

  TCacheWriteLog = record
    Key: string;
    PngSize: Integer;
    WriteFailed: Boolean;
    ExceptionMsg: string;
  end;

procedure LogCacheRead(const ALog: TCacheReadLog);
begin
  if ALog.ReadFailed then
    DebugLog('Cache', Format('TryGet EXCEPTION key=%s %s', [ALog.Key, ALog.ExceptionMsg]))
  else if ALog.PngSize = 0 then
    DebugLog('Cache', Format('TryGet MISS (no file) key=%s', [ALog.Key]))
  else
  begin
    DebugLog('Cache', Format('TryGet key=%s fileBytes=%d', [ALog.Key, ALog.PngSize]));
    if ALog.Loaded then
      DebugLog('Cache', Format('  BMP loaded: %dx%d empty=%s pf=%d',
        [ALog.BmpW, ALog.BmpH, BoolToStr(ALog.BmpEmpty, True), ALog.BmpPf]));
  end;
end;

procedure LogCacheWrite(const ALog: TCacheWriteLog);
begin
  if ALog.WriteFailed then
    DebugLog('Cache', Format('Put EXCEPTION key=%s %s', [ALog.Key, ALog.ExceptionMsg]))
  else
    DebugLog('Cache', Format('  encoded pngSize=%d', [ALog.PngSize]));
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
  Data: TBytes;
  Log: TCacheReadLog;
begin
  Result := nil;
  Log := Default(TCacheReadLog);
  Log.Key := FrameKey(AKey.FilePath, AKey.TimeOffset, AKey.MaxSide, AKey.UseKeyframes, FFileStat);
  if Log.Key = '' then
    Exit;
  FLock.Enter;
  try
    try
      Data := FStorage.Read(Log.Key);
      Log.PngSize := Length(Data);
      if Log.PngSize > 0 then
      begin
        Result := PngBytesToBitmap(Data);
        if Result <> nil then
        begin
          Log.Loaded := True;
          Log.BmpW := Result.Width;
          Log.BmpH := Result.Height;
          Log.BmpEmpty := Result.Empty;
          Log.BmpPf := Ord(Result.PixelFormat);
        end;
      end;
    except
      on E: Exception do
      begin
        Log.ReadFailed := True;
        Log.ExceptionMsg := Format('%s: %s', [E.ClassName, E.Message]);
        FreeAndNil(Result);
      end;
    end;
    if Result <> nil then
      FStorage.Touch(Log.Key);
  finally
    FLock.Leave;
  end;
  {Logged outside the critical section so workers do not serialise on
   DebugLog I/O.}
  LogCacheRead(Log);
end;

procedure TFrameCache.Put(const AKey: TFrameCacheKey; ABitmap: TBitmap);
var
  Data: TBytes;
  Log: TCacheWriteLog;
begin
  if ABitmap = nil then
    Exit;
  Log := Default(TCacheWriteLog);
  Log.Key := FrameKey(AKey.FilePath, AKey.TimeOffset, AKey.MaxSide, AKey.UseKeyframes, FFileStat);
  if Log.Key = '' then
    Exit;
  DebugLog('Cache', Format('Put key=%s bmp=%dx%d', [Log.Key, ABitmap.Width, ABitmap.Height]));
  FLock.Enter;
  try
    try
      Data := EncodeBitmapToPngBytes(ABitmap);
      Log.PngSize := Length(Data);
      FStorage.Write(Log.Key, Data);
    except
      on E: Exception do
      begin
        Log.WriteFailed := True;
        Log.ExceptionMsg := Format('%s: %s', [E.ClassName, E.Message]);
      end;
    end;
  finally
    FLock.Leave;
  end;
  LogCacheWrite(Log);
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
