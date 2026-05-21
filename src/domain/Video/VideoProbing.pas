{Video-probing abstraction for the domain. Implemented by TFFmpegExe
 (infrastructure); tests inject a stub returning canned TVideoInfo so
 consumers can be exercised without spawning ffmpeg.}
unit VideoProbing;

interface

uses
  VideoInfo;

type
  IVideoProber = interface
    ['{A4E91C82-FF0A-4B7D-91E8-CE5B27DAFA3C}']
    {An invalid result (IsValid = False) signals probe failure; caller
     decides whether to cache the negative result.}
    function ProbeVideo(const AFilePath: string): TVideoInfo;
  end;

  {Defers TFFmpegExe construction so prober consumers depend on the
   abstraction. Production: TProductionVideoProberFactory in FFmpegExe.}
  IVideoProberFactory = interface
    ['{6E2A9C41-7B58-4F0D-A3E6-1C9B5D8F0273}']
    function CreateProber(const AFFmpegPath: string): IVideoProber;
  end;

implementation

end.
