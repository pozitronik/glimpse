{Video-probing interface for TProbeCache and any future consumer that
 wants to ask "what is this video file's metadata?" without constructing
 a TFFmpegExe directly.

 Production wires TFFmpegProber, which is a thin adapter over TFFmpegExe.
 Tests inject a stub that returns canned TVideoInfo so the cache layer
 can be exercised without spawning ffmpeg.}
unit uVideoProbing;

interface

uses
  uFFmpegExe, uVideoInfo;

type
  IVideoProber = interface
    ['{A4E91C82-FF0A-4B7D-91E8-CE5B27DAFA3C}']
    {Probes AFilePath and returns the resulting TVideoInfo. An invalid
     result (IsValid = False) signals "probe failed"; the caller decides
     whether to cache the negative result or not.}
    function ProbeVideo(const AFilePath: string): TVideoInfo;
  end;

  {Production prober — wraps a TFFmpegExe constructed from the supplied
   ffmpeg.exe path. The TFFmpegExe instance is created once per
   TFFmpegProber and reused across every ProbeVideo call.}
  TFFmpegProber = class(TInterfacedObject, IVideoProber)
  strict private
    FFFmpeg: TFFmpegExe;
  public
    constructor Create(const AFFmpegPath: string);
    destructor Destroy; override;
    function ProbeVideo(const AFilePath: string): TVideoInfo;
  end;

implementation

constructor TFFmpegProber.Create(const AFFmpegPath: string);
begin
  inherited Create;
  FFFmpeg := TFFmpegExe.Create(AFFmpegPath);
end;

destructor TFFmpegProber.Destroy;
begin
  FFFmpeg.Free;
  inherited;
end;

function TFFmpegProber.ProbeVideo(const AFilePath: string): TVideoInfo;
begin
  Result := FFFmpeg.ProbeVideo(AFilePath);
end;

end.
