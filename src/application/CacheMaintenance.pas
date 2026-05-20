{Cross-cutting cache-maintenance domain rules. Sums and clears both
 the user-configurable frame cache and the fixed-location probe cache
 (%TEMP%\Glimpse\probes) as a single user-facing action.}
unit CacheMaintenance;

interface

{Sums every Glimpse-managed cache (frame + probe). Pure read; never raises.}
function TotalGlimpseCacheBytes(const AFrameDir: string): Int64;

{Wipes every Glimpse-managed cache. Best-effort: swallows disk errors
 so the dialog stays responsive.}
procedure ClearAllGlimpseCaches(const AFrameDir: string);

implementation

uses
  System.SysUtils, System.IOUtils,
  Cache, ProbeCache, FrameCacheFactory;

function TotalGlimpseCacheBytes(const AFrameDir: string): Int64;
var
  Mgr: ICacheManager;
  ProbeC: IProbeCacheManager;
begin
  Result := 0;
  if (AFrameDir <> '') and TDirectory.Exists(AFrameDir) then
  begin
    Mgr := CreateCacheManager(AFrameDir, 0);
    Result := Result + Mgr.GetTotalSize;
  end;

  ProbeC := CreateProbeCacheManager;
  Result := Result + ProbeC.GetTotalSize;
end;

procedure ClearAllGlimpseCaches(const AFrameDir: string);
var
  Mgr: ICacheManager;
  ProbeC: IProbeCacheManager;
begin
  if (AFrameDir <> '') and TDirectory.Exists(AFrameDir) then
  begin
    Mgr := CreateCacheManager(AFrameDir, 0);
    Mgr.Clear;
  end;

  ProbeC := CreateProbeCacheManager;
  ProbeC.Clear;
end;

end.
