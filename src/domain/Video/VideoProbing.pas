{Video-probing interface for TProbeCache. Production wires TFFmpegProber;
 tests inject a stub returning canned TVideoInfo so the cache layer can
 be exercised without spawning ffmpeg.}
unit VideoProbing;

interface

uses
  FFmpegExe, VideoInfo;

type
  IVideoProber = interface
    ['{A4E91C82-FF0A-4B7D-91E8-CE5B27DAFA3C}']
    {An invalid result (IsValid = False) signals probe failure; caller
     decides whether to cache the negative result.}
    function ProbeVideo(const AFilePath: string): TVideoInfo;
  end;

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
