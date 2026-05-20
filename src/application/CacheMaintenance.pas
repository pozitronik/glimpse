{Cross-cutting cache-maintenance rules. Sums and clears both the
 user-configurable frame cache and the fixed-location probe cache
 (%TEMP%\Glimpse\probes) as a single user-facing action.}
unit CacheMaintenance;

interface

uses
  Cache, ProbeCache;

{Sums every Glimpse-managed cache (frame + probe). Pure read; never raises.}
function TotalGlimpseCacheBytes(const AFrameDir: string): Int64; overload;
{Store-explicit core: sums the two supplied managers. Lets the dialog's
 cache-size readout be exercised with substituted caches.}
function TotalGlimpseCacheBytes(const AFrameCache: ICacheManager;
  const AProbeCache: IProbeCacheManager): Int64; overload;

{Wipes every Glimpse-managed cache. Best-effort: swallows disk errors
 so the dialog stays responsive.}
procedure ClearAllGlimpseCaches(const AFrameDir: string); overload;
{Store-explicit core: clears the two supplied managers.}
procedure ClearAllGlimpseCaches(const AFrameCache: ICacheManager;
  const AProbeCache: IProbeCacheManager); overload;

implementation

uses
  System.SysUtils, System.IOUtils,
  FrameCacheFactory;

{Resolves a frame-cache directory to a manager: the real disk cache when
 the directory exists, otherwise a null manager that totals and clears
 to nothing.}
function FrameCacheManagerFor(const AFrameDir: string): ICacheManager;
begin
  if (AFrameDir <> '') and TDirectory.Exists(AFrameDir) then
    Result := CreateCacheManager(AFrameDir, 0)
  else
    Result := TNullFrameCache.Create;
end;

function TotalGlimpseCacheBytes(const AFrameCache: ICacheManager;
  const AProbeCache: IProbeCacheManager): Int64;
begin
  Result := AFrameCache.GetTotalSize + AProbeCache.GetTotalSize;
end;

function TotalGlimpseCacheBytes(const AFrameDir: string): Int64;
begin
  Result := TotalGlimpseCacheBytes(FrameCacheManagerFor(AFrameDir),
    CreateProbeCacheManager);
end;

procedure ClearAllGlimpseCaches(const AFrameCache: ICacheManager;
  const AProbeCache: IProbeCacheManager);
begin
  AFrameCache.Clear;
  AProbeCache.Clear;
end;

procedure ClearAllGlimpseCaches(const AFrameDir: string);
begin
  ClearAllGlimpseCaches(FrameCacheManagerFor(AFrameDir), CreateProbeCacheManager);
end;

end.
