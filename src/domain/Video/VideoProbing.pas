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

implementation

end.
