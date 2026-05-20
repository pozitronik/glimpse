{Infrastructure implementation of the domain IVideoProber and
 IFrameExtractor abstractions: spawns the ffmpeg subprocess for probing
 and single-frame extraction. Parsing lives in FFmpegProbeParser;
 command-line assembly in FFmpegCmdLine. The process runner is injectable
 so this unit's branching can be tested without a real ffmpeg.}
unit FFmpegExe;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics,
  Types, VideoInfo, VideoProbing, FrameExtractor, ProcessRunner;

type
  TFFmpegExe = class(TInterfacedObject, IVideoProber, IFrameExtractor)
  strict private
    FExePath: string;
    {Wall-clock budget for one ExtractFrame call. The thumbnail path
     constructs with a shorter value than the lister's main extraction.}
    FExtractTimeoutMs: DWORD;
    FRunner: IProcessRunner;
  public
    {ARunner defaults to the production runner; tests pass a fake.}
    constructor Create(const AExePath: string; AExtractTimeoutMs: DWORD = 30000;
      const ARunner: IProcessRunner = nil);

    {IVideoProber}
    function ProbeVideo(const AFilePath: string): TVideoInfo;

    {IFrameExtractor. ACancelHandle (typically TEvent.Handle) terminates
     the ffmpeg child when signalled. Returns nil on failure; caller
     owns the bitmap.}
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;

    property ExePath: string read FExePath;
  end;

  {Production IFrameExtractorFactory: builds a TFFmpegExe for a requested
   ffmpeg path. Lets the WLX/WCX shells defer extractor construction.}
  TProductionFrameExtractorFactory = class(TInterfacedObject, IFrameExtractorFactory)
  public
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

implementation

uses
  BitmapSaver, FFmpegProbeParser, FFmpegCmdLine;

constructor TFFmpegExe.Create(const AExePath: string; AExtractTimeoutMs: DWORD;
  const ARunner: IProcessRunner);
begin
  inherited Create;
  FExePath := AExePath;
  FExtractTimeoutMs := AExtractTimeoutMs;
  if ARunner <> nil then
    FRunner := ARunner
  else
    FRunner := TProductionProcessRunner.Create;
end;

function TFFmpegExe.ProbeVideo(const AFilePath: string): TVideoInfo;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  StdErrStr: string;
begin
  Result := Default (TVideoInfo);
  Result.Duration := -1;

  CmdLine := Format('"%s" -nostdin -hide_banner -i "%s"', [FExePath, AFilePath]);
  {ffmpeg exits with 1 ("no output file specified"); we still get -i info on stderr.}
  FRunner.Run(CmdLine, StdOut, StdErr, 10000, 0);

  if Length(StdErr) = 0 then
  begin
    Result.ErrorMessage := 'No output from ffmpeg';
    Exit;
  end;

  StdErrStr := LenientUTF8Decode(StdErr);
  Result.Duration := ParseDuration(StdErrStr);
  ParseResolution(StdErrStr, Result.Width, Result.Height);
  ParseSampleAspect(StdErrStr, Result.SampleAspectN, Result.SampleAspectD);
  Result.RecalcDisplayDimensions;
  Result.VideoCodec := ParseVideoCodec(StdErrStr);
  Result.Bitrate := ParseBitrate(StdErrStr);
  Result.Fps := ParseFps(StdErrStr);
  Result.VideoBitrateKbps := ParseVideoBitrate(StdErrStr);
  Result.AudioCodec := ParseAudioCodec(StdErrStr);
  Result.AudioSampleRate := ParseAudioSampleRate(StdErrStr);
  Result.AudioChannels := ParseAudioChannels(StdErrStr);
  Result.AudioBitrateKbps := ParseAudioBitrate(StdErrStr);

  if not Result.IsValid then
    Result.ErrorMessage := 'Could not parse video metadata';
end;

function TFFmpegExe.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  ExitCode: Integer;
  Stream: TMemoryStream;
begin
  Result := nil;

  CmdLine := BuildExtractCmdLine(FExePath, AFileName, ATimeOffset, AOptions);

  ExitCode := FRunner.Run(CmdLine, StdOut, StdErr, FExtractTimeoutMs, ACancelHandle);
  if (ExitCode <> 0) or (Length(StdOut) < 8) then
    Exit;

  try
    if AOptions.UseBmpPipe then
    begin
      Stream := TMemoryStream.Create;
      try
        Stream.WriteBuffer(StdOut[0], Length(StdOut));
        Stream.Position := 0;
        Result := TBitmap.Create;
        Result.LoadFromStream(Stream);
        Result.PixelFormat := pf24bit;
      finally
        Stream.Free;
      end;
    end
    else
      Result := PngBytesToBitmap(StdOut);
  except
    on E: Exception do
      FreeAndNil(Result);
  end;
end;

function TProductionFrameExtractorFactory.CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
begin
  Result := TFFmpegExe.Create(AFFmpegPath);
end;

end.
