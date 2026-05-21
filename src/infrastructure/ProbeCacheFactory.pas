{Production wiring for the probe cache. Composes the disk storage and
 the filesystem stat into a TProbeCache so those infrastructure choices
 stay out of the ProbeCache domain unit.}
unit ProbeCacheFactory;

interface

uses
  ProbeCache;

{Fixed %TEMP%\Glimpse\probes directory backing the production probe cache.}
function DefaultProbeCacheDir: string;

{Production probe cache, rooted at DefaultProbeCacheDir.}
function CreateProbeCache: IProbeCache;

{The same cache through its admin facet, for size/clear callers.}
function CreateProbeCacheManager: IProbeCacheManager;

implementation

uses
  System.SysUtils, System.IOUtils,
  CacheStorage;

function DefaultProbeCacheDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'Glimpse' + PathDelim + 'probes');
end;

{Single construction point so the two public factories cannot drift.}
function BuildProbeCache: TProbeCache;
begin
  Result := TProbeCache.Create(
    TDiskCacheStorage.Create(DefaultProbeCacheDir, '.probe'),
    TFileSystemStat.Create);
end;

function CreateProbeCache: IProbeCache;
begin
  Result := BuildProbeCache;
end;

function CreateProbeCacheManager: IProbeCacheManager;
begin
  Result := BuildProbeCache;
end;

end.
