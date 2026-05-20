{Production wiring for the frame cache. Composes the concrete disk
 storage, LRU eviction policy and filesystem stat into a TFrameCache so
 those infrastructure choices stay out of the Cache domain unit.}
unit FrameCacheFactory;

interface

uses
  Cache;

{Builds a disk-backed frame cache rooted at ACacheDir. AMaxSizeMB is the
 LRU eviction budget.}
function CreateFrameCache(const ACacheDir: string; AMaxSizeMB: Integer): IFrameCache;

{The same cache exposed through its admin facet, for callers that only
 clear, evict or measure it.}
function CreateCacheManager(const ACacheDir: string; AMaxSizeMB: Integer): ICacheManager;

implementation

uses
  System.SysUtils,
  CacheStorage, LruEvictionPolicy, Logging;

{Single construction point so the two public factories cannot drift.}
function BuildCache(const ACacheDir: string; AMaxSizeMB: Integer): TFrameCache;
begin
  DebugLog('Cache', Format('CreateFrameCache: dir=%s maxMB=%d',
    [ACacheDir, AMaxSizeMB]));
  Result := TFrameCache.Create(
    TDiskCacheStorage.Create(ACacheDir, '.png'),
    TLruEvictionPolicy.Create(Int64(AMaxSizeMB) * 1024 * 1024),
    TFileSystemStat.Create);
end;

function CreateFrameCache(const ACacheDir: string; AMaxSizeMB: Integer): IFrameCache;
begin
  Result := BuildCache(ACacheDir, AMaxSizeMB);
end;

function CreateCacheManager(const ACacheDir: string; AMaxSizeMB: Integer): ICacheManager;
begin
  Result := BuildCache(ACacheDir, AMaxSizeMB);
end;

end.
