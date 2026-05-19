{Probed video metadata record + derivation methods. Consumed by
 ProbeCache, ThumbnailRender, the WLX form, and the WCX archive
 handle.}
unit VideoInfo;

interface

type
  TVideoInfo = record
    Duration: Double; {seconds; -1 if unknown}
    Width: Integer; {storage pixel grid width}
    Height: Integer; {storage pixel grid height}
    {Sample aspect ratio (per-pixel display stretch) as a rational. 1:1
     means square pixels and is the default when the source carries no
     SAR metadata. Anamorphic sources (DVD, broadcast, some camcorders)
     have non-1:1 SAR; e.g. 720x576 SAR=64:45 displays as 16:9.}
    SampleAspectN: Integer;
    SampleAspectD: Integer;
    {Pixel dimensions after applying SAR; equal to storage when SAR=1:1.
     Populated by RecalcDisplayDimensions — both ProbeVideo and
     TProbeCache.TryGet call it so the probe and cache-load paths cannot
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

    function IsValid: Boolean;

    {ffmpeg only emits an audio-codec line when an audio stream exists,
     so the empty-string check is a faithful proxy.}
    function HasAudio: Boolean;

    {Derives DisplayWidth/DisplayHeight from Width/Height + SampleAspect.
     Idempotent.}
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
