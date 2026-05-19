{Abstraction for frame extraction from video files.
 Decouples worker threads from the concrete ffmpeg implementation.}
unit uFrameExtractor;

interface

uses
  Winapi.Windows, Vcl.Graphics, uTypes;

type
  {Contract for extracting a single video frame at a given time offset.
   ACancelHandle is an optional Win32 waitable handle (e.g. TEvent.Handle) that,
   when signaled, cancels the in-flight extraction and causes the call to return nil.}
  IFrameExtractor = interface
    ['{C9A5D4E3-6F7B-8A9C-0D1E-2F3A4B5C6D7E}']
    function ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  {Adapter: delegates to TFFmpegExe without changing its ownership model.}
  TFFmpegFrameExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FFFmpegPath: string;
  public
    constructor Create(const AFFmpegPath: string);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  {Builds an IFrameExtractor wrapping ffmpeg at AFFmpegPath. Stateless
   factory; can be called many times from worker threads. Relocated from
   wlx/uPluginServices to this shared home in step 100 (C9) so the WCX
   coordinator can reuse it without importing from wlx/ — the return
   type already lives here, which makes this its natural home.}
  IFrameExtractorFactory = interface
    ['{A1B2C3D4-7777-8888-9999-AAAABBBBCCCC}']
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

  {Production factory: returns a fresh TFFmpegFrameExtractor per call.}
  TProductionFrameExtractorFactory = class(TInterfacedObject, IFrameExtractorFactory)
  public
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

implementation

uses
  uFFmpegExe;

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

{TProductionFrameExtractorFactory}

function TProductionFrameExtractorFactory.CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
begin
  Result := TFFmpegFrameExtractor.Create(AFFmpegPath);
end;

end.
