{Probed video metadata record + its derivation methods.

 Was previously declared inline in uFFmpegExe alongside the
 ffmpeg-process-runner. That coupling put the data record under VCL +
 Win32 baggage that consumers (uProbeCache, uThumbnailRender, the WLX
 form, the WCX archive handle) had no need for. Hoisting it to its own
 leaf unit lets:

 1. The IsValid contract live where the data does (a method rather than
    a field that the two writers — ProbeVideo and TProbeCache.TryGet —
    have to remember to set in lockstep with Duration).

 2. The SAR-aware display-dimension derivation be a single method
    (RecalcDisplayDimensions) that both the probe path and the
    cache-load path call, so they cannot drift. The cache-load path
    used to backfill DisplayWidth := Width when the cache entry lacked
    the explicit keys; for anamorphic sources (SAR != 1:1) that fallback
    silently lost the aspect ratio. RecalcDisplayDimensions on a record
    with valid Width/Height/SampleAspect gives the same answer as the
    inline math in ProbeVideo did, so production behaviour for
    forward-written cache entries is unchanged.

 3. A pure-record test fixture cover IsValid / RecalcDisplayDimensions /
    HasAudio without needing a real ffmpeg run.

 Eventual DDD home is suggested as src/domain/uVideoInfo.pas; for now
 the unit lives at src/ alongside the other shared records.}
unit uVideoInfo;

interface

type
  TVideoInfo = record
    Duration: Double; {seconds; -1 if unknown}
    Width: Integer; {storage pixel grid width}
    Height: Integer; {storage pixel grid height}
    {Sample aspect ratio (per-pixel display stretch) as a rational
     number. 1:1 means square pixels and is the default when the source
     carries no SAR metadata. Anamorphic sources (DVD, broadcast, some
     camcorders) have non-1:1 SAR; e.g. 720x576 SAR=64:45 displays as
     16:9.}
    SampleAspectN: Integer;
    SampleAspectD: Integer;
    {Pixel dimensions after applying SAR; equal to storage when SAR=1:1.
     What every aspect-aware player shows on screen. Populated by
     RecalcDisplayDimensions; both ProbeVideo (post-parse) and
     TProbeCache.TryGet (post-load) call it so the two paths cannot
     drift.}
    DisplayWidth: Integer;
    DisplayHeight: Integer;
    VideoCodec: string;
    VideoBitrateKbps: Integer; {0 if unknown}
    Fps: Double; {0 if unknown}
    Bitrate: Integer; {overall bitrate in kb/s; 0 if unknown}
    AudioCodec: string; {empty if no audio}
    AudioSampleRate: Integer; {Hz; 0 if unknown}
    AudioChannels: string; {'mono', 'stereo', '5.1', etc.}
    AudioBitrateKbps: Integer; {0 if unknown}
    ErrorMessage: string;

    {True iff the probe at least parsed a positive duration. Cheaper
     than rechecking Duration > 0 at every gate; previously a stored
     field that the two writers had to set explicitly (drift hazard
     fixed by methodisation).}
    function IsValid: Boolean;

    {True iff the source has an audio stream. Sourced from the parsed
     AudioCodec — ffmpeg only emits an audio-codec line when an audio
     stream exists, so the empty-string check is a faithful proxy.}
    function HasAudio: Boolean;

    {Derives DisplayWidth/DisplayHeight from Width/Height + SampleAspect.
     SAR=1:1 (or missing SampleAspect data) maps display to storage;
     anamorphic SAR scales the width and leaves the height alone. Both
     ProbeVideo and TProbeCache.TryGet call this so the two paths emit
     consistent display dimensions for the same source.

     Idempotent: calling repeatedly returns the same result.}
    procedure RecalcDisplayDimensions;
  end;

implementation

function TVideoInfo.IsValid: Boolean;
begin
  Result := Duration > 0;
end;

function TVideoInfo.HasAudio: Boolean;
begin
  Result := AudioCodec <> '';
end;

procedure TVideoInfo.RecalcDisplayDimensions;
begin
  DisplayHeight := Height;
  if (Width > 0) and (SampleAspectD > 0) then
    DisplayWidth := Round(Width * SampleAspectN / SampleAspectD)
  else
    DisplayWidth := Width;
end;

end.
