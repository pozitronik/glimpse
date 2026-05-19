{Cross-cutting cache-maintenance domain rules. Sums and clears both
 the user-configurable frame cache and the fixed-location probe cache
 (%TEMP%\Glimpse\probes) as a single user-facing action.}
unit uCacheMaintenance;

interface

{Sums every Glimpse-managed cache (frame + probe). Pure read; never raises.}
function TotalGlimpseCacheBytes(const AFrameDir: string): Int64;

{Wipes every Glimpse-managed cache. Best-effort: swallows disk errors
 so the dialog stays responsive.}
procedure ClearAllGlimpseCaches(const AFrameDir: string);

implementation

uses
  System.SysUtils, System.IOUtils,
  uCache, uProbeCache;

function TotalGlimpseCacheBytes(const AFrameDir: string): Int64;
var
  Mgr: ICacheManager;
  ProbeC: TProbeCache;
begin
  Result := 0;
  if (AFrameDir <> '') and TDirectory.Exists(AFrameDir) then
  begin
    Mgr := CreateCacheManager(AFrameDir, 0);
    Result := Result + Mgr.GetTotalSize;
  end;

  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    Result := Result + ProbeC.GetTotalSize;
  finally
    ProbeC.Free;
  end;
end;

procedure ClearAllGlimpseCaches(const AFrameDir: string);
var
  Mgr: ICacheManager;
  ProbeC: TProbeCache;
begin
  if (AFrameDir <> '') and TDirectory.Exists(AFrameDir) then
  begin
    Mgr := CreateCacheManager(AFrameDir, 0);
    Mgr.Clear;
  end;

  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    ProbeC.Clear;
  finally
    ProbeC.Free;
  end;
end;

end.
