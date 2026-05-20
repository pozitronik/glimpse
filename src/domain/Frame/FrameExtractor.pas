{Frame-extraction abstraction. Decouples worker threads from ffmpeg.
 Implemented by TFFmpegExe (infrastructure); the production factory
 TProductionFrameExtractorFactory lives there too.}
unit FrameExtractor;

interface

uses
  Winapi.Windows, Vcl.Graphics, Types;

type
  {Signalling ACancelHandle cancels the in-flight extraction (call
   returns nil).}
  IFrameExtractor = interface
    ['{C9A5D4E3-6F7B-8A9C-0D1E-2F3A4B5C6D7E}']
    function ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  IFrameExtractorFactory = interface
    ['{A1B2C3D4-7777-8888-9999-AAAABBBBCCCC}']
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

implementation

end.
