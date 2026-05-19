{Frame-extraction interface. Decouples worker threads from ffmpeg.}
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

  TFFmpegFrameExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FFFmpegPath: string;
  public
    constructor Create(const AFFmpegPath: string);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  IFrameExtractorFactory = interface
    ['{A1B2C3D4-7777-8888-9999-AAAABBBBCCCC}']
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

  TProductionFrameExtractorFactory = class(TInterfacedObject, IFrameExtractorFactory)
  public
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

implementation

uses
  FFmpegExe;

constructor TFFmpegFrameExtractor.Create(const AFFmpegPath: string);
begin
  inherited Create;
  FFFmpegPath := AFFmpegPath;
end;

function TFFmpegFrameExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
var
  FFmpeg: TFFmpegExe;
begin
  FFmpeg := TFFmpegExe.Create(FFFmpegPath);
  try
    Result := FFmpeg.ExtractFrame(AFileName, ATimeOffset, AOptions, 30000, ACancelHandle);
  finally
    FFmpeg.Free;
  end;
end;

function TProductionFrameExtractorFactory.CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
begin
  Result := TFFmpegFrameExtractor.Create(AFFmpegPath);
end;

end.
