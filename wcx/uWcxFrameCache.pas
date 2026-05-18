{Module-level pre-extraction cache for the WCX plugin.

 The cache survives across OpenArchive calls so that a TC user clicking
 between three frames of the same video does not re-spawn ffmpeg each
 time. Total Commander may dispatch OpenArchive / ConfigurePacker /
 finalization on different threads, so every read and write goes through
 the instance's TCriticalSection — concurrency safety is a class
 invariant, not a discipline the caller must remember.

 The pre-extraction itself is long (seconds to minutes per video), and
 the lock is intentionally held for its full duration so that two
 threads opening the same video cannot both race past the cache-hit
 check. Callers obtain a TWcxCacheExtractionSession via
 BeginExtractionSession, which owns the lock for its lifetime; Exit
 inside the orchestrating procedure still works because the session is
 a real object rather than an anonymous-method closure.

 Single-instance lifecycle via class var FInstance + Instance / ReleaseInstance
 — exactly one cache per loaded DLL. ReleaseInstance is finalization-safe:
 it calls Invalidate first, which swallows directory-delete failures so
 the DLL unload never crashes the host.}
unit uWcxFrameCache;

interface

uses
  System.SysUtils, System.SyncObjs;

type
  {Test-only injection point for the recursive directory delete used by
   Invalidate. Defaults to TDirectory.Delete(_, True). Tests swap in a
   thrower via SetDeleteDirectoryProc to exercise the
   exception-swallowing path that production needs at DLL unload.}
  TWcxDeleteDirectoryProc = reference to procedure(const APath: string);

  TWcxFrameCache = class;

  {Held-lock context for one pre-extraction pass. Constructed by
   TWcxFrameCache.BeginExtractionSession (which enters the lock); the
   destructor releases the lock. Mutators below assume the lock is held
   — that invariant is structural, not asserted, because the session is
   the only construction path.

   Typical use:
     Sess := Cache.BeginExtractionSession;
     try
       if Sess.TryHit(...) then Exit;  // Exit returns from the outer
       TempDir := Sess.PrepareFresh(...);
       ... do extraction, calling Sess.RecordSlot(I, ...) per slot ...
       Sess.PublishTo(H.TempPaths, H.EntrySizes);
     finally
       Sess.Free;
     end;}
  TWcxCacheExtractionSession = class
  strict private
    FCache: TWcxFrameCache;
  public
    constructor Create(ACache: TWcxFrameCache);
    destructor Destroy; override;

    {On a same-video cache hit, copies the cached arrays into the var
     parameters and returns True. The caller's Exit ends the session;
     the destructor releases the lock.}
    function TryHit(const AFileName: string; var ATempPaths: TArray<string>;
      var AEntrySizes: TArray<Int64>): Boolean;

    {Wipes any prior cache, creates a fresh GUID-named subdirectory of
     the user temp, stores AFileName as the cached video, and sizes the
     internal arrays to AEntryCount. Returns the new temp directory
     path; callers write per-slot files into it and call RecordSlot.}
    function PrepareFresh(const AFileName: string; AEntryCount: Integer): string;

    {Records the per-slot output of the extraction pass.}
    procedure RecordSlot(AIndex: Integer; const ATempPath: string; ASize: Int64);

    {Copies the currently held arrays into the caller's var slots.
     Mirrors the historical "H.TempPaths := GCachedTempPaths" at the
     end of PreExtractFrames.}
    procedure PublishTo(var ATempPaths: TArray<string>; var AEntrySizes: TArray<Int64>);

    {Convenience: the current session's temp directory (for the
     extraction helpers that need to compose per-slot paths).}
    function CachedTempDir: string;
  end;

  TWcxFrameCache = class
  strict private
    class var FInstance: TWcxFrameCache;
  {Plain `private` (not `strict`) so TWcxCacheExtractionSession in the
   same unit can read/write these directly under the held lock — without
   adding a parallel set of accessors that exist only to let one
   collaborator class reach in. The repeated visibility section also
   resets the scope from `class var` above back to instance-level (same
   gotcha as TPluginContext).}
  private
    FLock: TCriticalSection;
    FCachedVideoFile: string;
    FCachedTempDir: string;
    FCachedTempPaths: TArray<string>;
    FCachedEntrySizes: TArray<Int64>;
    FDeleteDirectoryProc: TWcxDeleteDirectoryProc;
    procedure InvalidateLocked;
  public
    constructor Create;
    destructor Destroy; override;

    class function Instance: TWcxFrameCache;
    class procedure ReleaseInstance;

    {Drops the cache. Public so the settings-dialog apply callback and
     the DoOpenArchive failure path can both invoke it; the recursive
     directory delete is wrapped in try/except because Invalidate runs
     from finalization where an unhandled exception would crash TC.}
    procedure Invalidate;

    {PRODUCTION CODE MUST NOT CALL THESE.

     SeedForTesting populates the video-file + temp-dir fields so a
     regression test can mimic PreExtractFrames partial state and then
     verify Invalidate wipes it. CachedVideoFile / CachedTempDir expose
     the seeded values for assertion. SetDeleteDirectoryProc / Reset...
     swap the directory-delete primitive so a test can force the
     try/except path that production relies on at DLL unload.}
    procedure SeedForTesting(const AVideoFile, ATempDir: string);
    function CachedVideoFile: string;
    function CachedTempDir: string;
    procedure SetDeleteDirectoryProc(const AProc: TWcxDeleteDirectoryProc);
    procedure ResetDeleteDirectoryProc;

    {Locks the cache for an extraction pass. Caller must Free the
     returned session (the destructor releases the lock).}
    function BeginExtractionSession: TWcxCacheExtractionSession;
  end;

implementation

uses
  System.IOUtils, uDebugLog;

procedure WcxCacheLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

procedure DefaultDeleteDirectory(const APath: string);
begin
  TDirectory.Delete(APath, True);
end;

{ TWcxFrameCache }

constructor TWcxFrameCache.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDeleteDirectoryProc := DefaultDeleteDirectory;
end;

destructor TWcxFrameCache.Destroy;
begin
  Invalidate;
  FLock.Free;
  inherited;
end;

class function TWcxFrameCache.Instance: TWcxFrameCache;
begin
  if FInstance = nil then
    FInstance := TWcxFrameCache.Create;
  Result := FInstance;
end;

class procedure TWcxFrameCache.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

procedure TWcxFrameCache.InvalidateLocked;
begin
  if (FCachedTempDir <> '') and TDirectory.Exists(FCachedTempDir) then
    try
      FDeleteDirectoryProc(FCachedTempDir);
    except
      on E: Exception do
        WcxCacheLog(Format('InvalidateFrameCache: delete failed for %s: %s: %s',
          [FCachedTempDir, E.ClassName, E.Message]));
    end;
  FCachedVideoFile := '';
  FCachedTempDir := '';
  FCachedTempPaths := nil;
  FCachedEntrySizes := nil;
end;

procedure TWcxFrameCache.Invalidate;
begin
  FLock.Enter;
  try
    InvalidateLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TWcxFrameCache.SeedForTesting(const AVideoFile, ATempDir: string);
begin
  FLock.Enter;
  try
    FCachedVideoFile := AVideoFile;
    FCachedTempDir := ATempDir;
  finally
    FLock.Leave;
  end;
end;

function TWcxFrameCache.CachedVideoFile: string;
begin
  FLock.Enter;
  try
    Result := FCachedVideoFile;
  finally
    FLock.Leave;
  end;
end;

function TWcxFrameCache.CachedTempDir: string;
begin
  FLock.Enter;
  try
    Result := FCachedTempDir;
  finally
    FLock.Leave;
  end;
end;

procedure TWcxFrameCache.SetDeleteDirectoryProc(const AProc: TWcxDeleteDirectoryProc);
begin
  FLock.Enter;
  try
    if Assigned(AProc) then
      FDeleteDirectoryProc := AProc
    else
      FDeleteDirectoryProc := DefaultDeleteDirectory;
  finally
    FLock.Leave;
  end;
end;

procedure TWcxFrameCache.ResetDeleteDirectoryProc;
begin
  SetDeleteDirectoryProc(nil);
end;

function TWcxFrameCache.BeginExtractionSession: TWcxCacheExtractionSession;
begin
  Result := TWcxCacheExtractionSession.Create(Self);
end;

{ TWcxCacheExtractionSession }

constructor TWcxCacheExtractionSession.Create(ACache: TWcxFrameCache);
begin
  inherited Create;
  FCache := ACache;
  FCache.FLock.Enter;
end;

destructor TWcxCacheExtractionSession.Destroy;
begin
  FCache.FLock.Leave;
  inherited;
end;

function TWcxCacheExtractionSession.TryHit(const AFileName: string;
  var ATempPaths: TArray<string>; var AEntrySizes: TArray<Int64>): Boolean;
begin
  if (FCache.FCachedVideoFile = AFileName) and (FCache.FCachedTempDir <> '')
    and TDirectory.Exists(FCache.FCachedTempDir) then
  begin
    ATempPaths := FCache.FCachedTempPaths;
    AEntrySizes := FCache.FCachedEntrySizes;
    Exit(True);
  end;
  Result := False;
end;

function TWcxCacheExtractionSession.PrepareFresh(const AFileName: string;
  AEntryCount: Integer): string;
begin
  FCache.InvalidateLocked;
  FCache.FCachedTempDir := TPath.Combine(TPath.GetTempPath,
    'glimpse_wcx_' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(FCache.FCachedTempDir);
  FCache.FCachedVideoFile := AFileName;
  SetLength(FCache.FCachedTempPaths, AEntryCount);
  SetLength(FCache.FCachedEntrySizes, AEntryCount);
  Result := FCache.FCachedTempDir;
end;

procedure TWcxCacheExtractionSession.RecordSlot(AIndex: Integer;
  const ATempPath: string; ASize: Int64);
begin
  FCache.FCachedTempPaths[AIndex] := ATempPath;
  FCache.FCachedEntrySizes[AIndex] := ASize;
end;

procedure TWcxCacheExtractionSession.PublishTo(var ATempPaths: TArray<string>;
  var AEntrySizes: TArray<Int64>);
begin
  ATempPaths := FCache.FCachedTempPaths;
  AEntrySizes := FCache.FCachedEntrySizes;
end;

function TWcxCacheExtractionSession.CachedTempDir: string;
begin
  Result := FCache.FCachedTempDir;
end;

initialization

finalization

{Owns the singleton lifecycle. uWcxExports also calls ReleaseInstance
 (FreeAndNil is idempotent) but consumers that link uWcxFrameCache
 without uWcxExports — e.g., the test executable — still get a clean
 shutdown.}
TWcxFrameCache.ReleaseInstance;

end.
