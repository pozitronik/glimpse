{Cross-cutting cache-maintenance domain rules for the Glimpse plugin.

 The plugin keeps two on-disk caches: the user-configurable frame
 cache (under EffectiveCacheFolder) and a fixed-location probe cache
 (DefaultProbeCacheDir, %TEMP%\Glimpse\probes). User-facing "clear
 every Glimpse cache" and "report total Glimpse cache size" actions
 are domain rules — neither caller (the WLX settings dialog today,
 the WCX dialog when it grows a cache button) should re-encode them.

 Extracted from `wlx/uSettingsDlg.pas` per VIOLATIONS.md M16.
 Living under `src/application/` keeps it WLX/WCX-neutral.}
unit uCacheMaintenance;

interface

{Total bytes across every Glimpse-managed on-disk cache. Sums the
 user-configurable frame cache (under AFrameDir, when the directory
 exists) plus the probe cache (always — its fixed directory is
 created on demand by TProbeCache). Returns 0 when nothing has been
 cached yet. Pure read; never raises.}
function TotalGlimpseCacheBytes(const AFrameDir: string): Int64;

{Wipes every Glimpse-managed on-disk cache. Clears the frame cache
 under AFrameDir (when the directory exists) and the probe cache
 (always). Best-effort — silently swallows any disk errors so the
 dialog stays responsive. Matches the user intent of a single
 "Clear cache" button: one click removes every byte the plugin keeps.}
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

  {Probe cache lives in a separate fixed directory; fold it into the
   total so the readout reflects every byte the plugin keeps on disk.}
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

  {Probe cache lives outside the user-configurable cache folder, in
   %TEMP%\Glimpse\probes. Wiping it alongside the frame cache matches
   user intent (one Cache button = all of Glimpse's on-disk caches).}
  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    ProbeC.Clear;
  finally
    ProbeC.Free;
  end;
end;

end.
