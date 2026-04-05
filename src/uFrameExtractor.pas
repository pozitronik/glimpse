{ Abstraction for frame extraction from video files.
  Decouples worker threads from the concrete ffmpeg implementation. }
unit uFrameExtractor;

interface

uses
  Vcl.Graphics;

type
  { Contract for extracting a single video frame at a given time offset. }
  IFrameExtractor = interface
    ['{C9A5D4E3-6F7B-8A9C-0D1E-2F3A4B5C6D7E}']
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      AUseBmp: Boolean): TBitmap;
  end;

  { Adapter: delegates to TFFmpegExe without changing its ownership model. }
  TFFmpegFrameExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FFFmpegPath: string;
  public
    constructor Create(const AFFmpegPath: string);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      AUseBmp: Boolean): TBitmap;
  end;

implementation

uses
  uFFmpegExe;

constructor TFFmpegFrameExtractor.Create(const AFFmpegPath: string);
begin
  inherited Create;
  FFFmpegPath := AFFmpegPath;
end;

function TFFmpegFrameExtractor.ExtractFrame(const AFileName: string;
  ATimeOffset: Double; AUseBmp: Boolean): TBitmap;
var
  FFmpeg: TFFmpegExe;
begin
  FFmpeg := TFFmpegExe.Create(FFFmpegPath);
  try
    Result := FFmpeg.ExtractFrame(AFileName, ATimeOffset, AUseBmp);
  finally
    FFmpeg.Free;
  end;
end;

end.
