{ffmpeg.exe driver: spawns the subprocess for video probing and
 single-frame extraction.

 Slim class wrapper. The parsing of ffmpeg's stderr output lives in
 src/infrastructure/uFFmpegProbeParser; the command-line assembly and
 version-validation helpers live in src/infrastructure/uFFmpegCmdLine.
 This unit's only job is to glue ffmpeg-the-subprocess to the parsed
 results.}
unit uFFmpegExe;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics,
  uTypes, uVideoInfo;

type
  TFFmpegExe = class
  strict private
    FExePath: string;
  public
    constructor Create(const AExePath: string);

    {Probes a video file for metadata (duration, resolution, codec).}
    function ProbeVideo(const AFileName: string): TVideoInfo;

    {Extracts a single frame at the given time offset.
     AUseBmp=True uses BMP pipe (faster, larger); False uses PNG pipe (slower, smaller).
     AHwAccel=True adds -hwaccel auto for GPU-accelerated decoding.
     AUseKeyframes=True adds -noaccurate_seek to grab the nearest keyframe (faster).
     ATimeoutMs caps how long the ffmpeg call may run; default 30s matches the
     generic RunProcess default. Use a shorter value (e.g. for thumbnail panels)
     to avoid stalling on broken files.
     ACancelHandle is an optional Win32 waitable handle (typically TEvent.Handle).
     When signaled during the call, RunProcess terminates the ffmpeg child process.
     Returns a new TBitmap on success, nil on failure. Caller owns the returned bitmap.}
    function ExtractFrame(const AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions; ATimeoutMs: DWORD = 30000; ACancelHandle: THandle = 0): TBitmap;

    property ExePath: string read FExePath;
  end;

implementation

uses
  uBitmapSaver, uRunProcess, uFFmpegProbeParser, uFFmpegCmdLine;

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
  {Exit code 1 is expected: "no output file specified"}
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
