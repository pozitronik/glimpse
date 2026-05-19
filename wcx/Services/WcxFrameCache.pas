{Module-level pre-extraction cache, one per loaded DLL. Survives across
 OpenArchive calls so clicking between frames of the same video does
 not re-spawn ffmpeg. TC may dispatch OpenArchive / ConfigurePacker /
 finalization on different threads, so every access goes through the
 instance's TCriticalSection.}
unit WcxFrameCache;

interface

uses
  System.SysUtils, System.SyncObjs;

type
  {Test seam for the recursive directory delete; tests swap in a thrower
   to exercise the exception-swallowing path that production needs at
   DLL unload.}
  TWcxDeleteDirectoryProc = reference to procedure(const APath: string);

  TWcxFrameCache = class;

  {Held-lock context for one pre-extraction pass. Constructor enters the
   lock; destructor releases it. Mutators assume the lock is held —
   structural invariant because BeginExtractionSession is the only
   construction path.}
  TWcxCacheExtractionSession = class
  strict private
    FCache: TWcxFrameCache;
  public
    constructor Create(ACache: TWcxFrameCache);
    destructor Destroy; override;

    function TryHit(const AFileName: string; var ATempPaths: TArray<string>;
      var AEntrySizes: TArray<Int64>): Boolean;

    function PrepareFresh(const AFileName: string; AEntryCount: Integer): string;

    procedure RecordSlot(AIndex: Integer; const ATempPath: string; ASize: Int64);

    procedure PublishTo(var ATempPaths: TArray<string>; var AEntrySizes: TArray<Int64>);

    function CachedTempDir: string;
  end;

  TWcxFrameCache = class
  strict private
    class var FInstance: TWcxFrameCache;
  {Plain private (not strict) so TWcxCacheExtractionSession in the same
   unit can read/write directly under the held lock without a parallel
   accessor surface. Repeated visibility section also resets the scope
   from "class var" above back to instance-level.}
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

    {Wraps the directory delete in try/except so finalization never
     crashes TC with an unhandled exception.}
    procedure Invalidate;

    {Test seams. PRODUCTION CODE MUST NOT CALL THESE.}
    procedure SeedForTesting(const AVideoFile, ATempDir: string);
    function CachedVideoFile: string;
    function CachedTempDir: string;
    procedure SetDeleteDirectoryProc(const AProc: TWcxDeleteDirectoryProc);
    procedure ResetDeleteDirectoryProc;

    function BeginExtractionSession: TWcxCacheExtractionSession;
  end;

implementation

uses
  System.IOUtils, Logging;

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

{Consumers that link WcxFrameCache without WcxExports (the test exe)
 still get a clean shutdown; FreeAndNil is idempotent so the
 WcxExports finalization call later is harmless.}
TWcxFrameCache.ReleaseInstance;

end.
