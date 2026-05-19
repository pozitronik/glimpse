{ffmpeg.exe driver: spawns the subprocess for probing and single-frame
 extraction. Parsing lives in FFmpegProbeParser; command-line assembly
 in FFmpegCmdLine.}
unit FFmpegExe;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics,
  Types, VideoInfo;

type
  TFFmpegExe = class
  strict private
    FExePath: string;
  public
    constructor Create(const AExePath: string);

    function ProbeVideo(const AFileName: string): TVideoInfo;

    {ACancelHandle (typically TEvent.Handle) terminates the ffmpeg child
     when signalled. Returns nil on failure; caller owns the bitmap.}
    function ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): TBitmap;

    property ExePath: string read FExePath;
  end;

implementation

uses
  BitmapSaver, ProcessRunner, FFmpegProbeParser, FFmpegCmdLine;

constructor TFFmpegExe.Create(const AExePath: string);
begin
  inherited Create;
  FExePath := AExePath;
end;

function TFFmpegExe.ProbeVideo(const AFileName: string): TVideoInfo;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  StdErrStr: string;
begin
  Result := Default (TVideoInfo);
  Result.Duration := -1;

  CmdLine := Format('"%s" -nostdin -hide_banner -i "%s"', [FExePath, AFileName]);
  {ffmpeg exits with 1 ("no output file specified"); we still get -i info on stderr.}
  RunProcess(CmdLine, StdOut, StdErr, 10000);

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

function TFFmpegExe.ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ATimeoutMs: DWORD; ACancelHandle: THandle): TBitmap;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  ExitCode: Integer;
  Stream: TMemoryStream;
begin
  Result := nil;

  CmdLine := BuildExtractCmdLine(FExePath, AFileName, ATimeOffset, AOptions);

  ExitCode := RunProcess(CmdLine, StdOut, StdErr, ATimeoutMs, ACancelHandle);
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

end.
