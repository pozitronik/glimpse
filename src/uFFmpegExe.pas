{ffmpeg.exe backend: process execution, video probing, and frame extraction.}
unit uFFmpegExe;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics,
  uFrameOffsets, uTypes;

type
  TVideoInfo = record
    Duration: Double; {seconds; -1 if unknown}
    Width: Integer; {storage pixel grid width}
    Height: Integer; {storage pixel grid height}
    {Sample aspect ratio (per-pixel display stretch) as a rational number.
     1:1 means square pixels and is the default when the source carries no
     SAR metadata. Anamorphic sources (DVD, broadcast, some camcorders)
     have non-1:1 SAR; e.g. 720x576 SAR=64:45 displays as 16:9.}
    SampleAspectN: Integer;
    SampleAspectD: Integer;
    {Pixel dimensions after applying SAR; equal to storage when SAR=1:1.
     What every aspect-aware player shows on screen.}
    DisplayWidth: Integer;
    DisplayHeight: Integer;
    VideoCodec: string;
    VideoBitrateKbps: Integer; {0 if unknown}
    Fps: Double; {0 if unknown}
    Bitrate: Integer; {overall bitrate in kb/s; 0 if unknown}
    AudioCodec: string; {empty if no audio}
    AudioSampleRate: Integer; {Hz; 0 if unknown}
    AudioChannels: string; {'mono', 'stereo', '5.1', etc.}
    AudioBitrateKbps: Integer; {0 if unknown}
    IsValid: Boolean; {True if at least duration was parsed}
    ErrorMessage: string;
  end;

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

  {Parsing functions exposed for unit testing}

  {Parses duration from ffmpeg stderr output. Returns seconds, or -1 if not found.}
function ParseDuration(const AText: string): Double;

{Parses video resolution from ffmpeg stderr output.}
function ParseResolution(const AText: string; out AWidth, AHeight: Integer): Boolean;

{Parses sample aspect ratio (SAR) numerator and denominator from ffmpeg
 stderr output. Looks for the "[SAR <N>:<D> ..." marker on the Video: line.
 When the marker is missing or the values are zero/invalid, AN/AD are set
 to 1:1 (square pixels) and the function returns False.}
function ParseSampleAspect(const AText: string; out AN, AD: Integer): Boolean;

{Parses video codec name from ffmpeg stderr output.}
function ParseVideoCodec(const AText: string): string;

{Parses overall bitrate from ffmpeg stderr Duration line. Returns kb/s, or 0.}
function ParseBitrate(const AText: string): Integer;

{Parses video framerate from ffmpeg stderr Video stream line. Returns fps, or 0.}
function ParseFps(const AText: string): Double;

{Parses video stream bitrate from ffmpeg stderr. Returns kb/s, or 0.}
function ParseVideoBitrate(const AText: string): Integer;

{Parses audio codec from ffmpeg stderr Audio stream line.}
function ParseAudioCodec(const AText: string): string;

{Parses audio sample rate from ffmpeg stderr. Returns Hz, or 0.}
function ParseAudioSampleRate(const AText: string): Integer;

{Parses audio channel layout from ffmpeg stderr (mono, stereo, 5.1, etc.).}
function ParseAudioChannels(const AText: string): string;

{Parses audio bitrate from ffmpeg stderr Audio stream line. Returns kb/s, or 0.}
function ParseAudioBitrate(const AText: string): Integer;

{Extracts the first line containing APrefix from ffmpeg output.}
function ExtractStreamLine(const AText, APrefix: string): string;

{Parses version string from `ffmpeg -version` output.
 Expects first line like "ffmpeg version 6.1.1 ...".
 Returns version string (e.g. "6.1.1") or empty if not recognized.}
function ParseFFmpegVersion(const AText: string): string;

{Runs `ffmpeg -version` and returns the version string.
 Returns empty string if the executable is not a valid ffmpeg.}
function ValidateFFmpeg(const AExePath: string): string;

{Builds the ffmpeg command line that ExtractFrame executes. Pure function:
 no I/O, no globals. Exposed so the option-to-filter mapping (HwAccel,
 UseKeyframes, MaxSide cap, RespectAnamorphic SAR scale) can be verified
 independently of the actual extraction.}
function BuildExtractCmdLine(const AExePath, AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions): string;

implementation

uses
  System.Math, uBitmapSaver, uRunProcess;

{Decodes bytes as UTF-8, replacing invalid sequences instead of raising.
 ffmpeg may embed legacy-encoded metadata (e.g. CP1251 titles) that is
 not valid UTF-8; strict decoding would raise EEncodingError.}
function LenientUTF8Decode(const ABytes: TBytes): string;
var
  Enc: TEncoding;
begin
  if Length(ABytes) = 0 then
    Exit('');
  Enc := TUTF8Encoding.Create(CP_UTF8, 0, 0);
  try
    Result := Enc.GetString(ABytes);
  finally
    Enc.Free;
  end;
end;

{Parsing}

function ParseDuration(const AText: string): Double;
var
  P: Integer;
  TimeStr: string;
  Parts: TArray<string>;
  H, M, S: Integer;
  DotPos: Integer;
  FracStr: string;
  Frac: Double;
begin
  Result := -1;

  P := Pos('Duration:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Duration:');

  {Skip whitespace}
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);

  {Read until comma, newline, or end}
  TimeStr := '';
  while (P <= Length(AText)) and not CharInSet(AText[P], [',', #13, #10]) do
  begin
    TimeStr := TimeStr + AText[P];
    Inc(P);
  end;
  TimeStr := Trim(TimeStr);

  if (TimeStr = '') or SameText(TimeStr, 'N/A') then
    Exit;

  {Expected: HH:MM:SS.ff}
  Parts := TimeStr.Split([':']);
  if Length(Parts) <> 3 then
    Exit;

  H := StrToIntDef(Parts[0], -1);
  M := StrToIntDef(Parts[1], -1);
  if (H < 0) or (M < 0) then
    Exit;

  DotPos := Pos('.', Parts[2]);
  if DotPos > 0 then
  begin
    S := StrToIntDef(Copy(Parts[2], 1, DotPos - 1), -1);
    FracStr := Copy(Parts[2], DotPos + 1, Length(Parts[2]) - DotPos);
    if (FracStr = '') or (S < 0) then
      Exit;
    Frac := StrToIntDef(FracStr, 0) / Power(10, Length(FracStr));
  end else begin
    S := StrToIntDef(Parts[2], -1);
    Frac := 0;
  end;

  if S < 0 then
    Exit;

  Result := H * 3600.0 + M * 60.0 + S + Frac;
end;

function ParseResolution(const AText: string; out AWidth, AHeight: Integer): Boolean;
var
  VideoPos, P, I: Integer;
  WidthStr, HeightStr: string;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;

  VideoPos := Pos('Video:', AText);
  if VideoPos = 0 then
    Exit;

  {Scan for NNNxNNN pattern after "Video:"}
  P := VideoPos + 6;
  while P < Length(AText) do
  begin
    if (AText[P] = 'x') and CharInSet(AText[P - 1], ['0' .. '9']) and CharInSet(AText[P + 1], ['0' .. '9']) then
    begin
      {Walk backwards for width digits}
      I := P - 1;
      while (I > VideoPos) and CharInSet(AText[I], ['0' .. '9']) do
        Dec(I);
      WidthStr := Copy(AText, I + 1, P - I - 1);

      {Walk forwards for height digits}
      I := P + 1;
      while (I <= Length(AText)) and CharInSet(AText[I], ['0' .. '9']) do
        Inc(I);
      HeightStr := Copy(AText, P + 1, I - P - 1);

      AWidth := StrToIntDef(WidthStr, 0);
      AHeight := StrToIntDef(HeightStr, 0);

      {Require at least 2-digit width and height to avoid false matches like "0x1A"}
      if (Length(WidthStr) >= 2) and (Length(HeightStr) >= 2) and (AWidth > 0) and (AHeight > 0) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(P);
  end;
end;

function ParseSampleAspect(const AText: string; out AN, AD: Integer): Boolean;
const
  Marker = '[SAR ';
var
  VideoPos, MarkerPos, ColonPos, EndPos, NumStart: Integer;
begin
  Result := False;
  AN := 1;
  AD := 1;

  VideoPos := Pos('Video:', AText);
  if VideoPos = 0 then
    Exit;

  MarkerPos := Pos(Marker, AText, VideoPos);
  if MarkerPos = 0 then
    Exit;

  {Walk digits up to ':' starting after the marker}
  NumStart := MarkerPos + Length(Marker);
  ColonPos := NumStart;
  while (ColonPos <= Length(AText)) and CharInSet(AText[ColonPos], ['0' .. '9']) do
    Inc(ColonPos);
  if (ColonPos > Length(AText)) or (ColonPos = NumStart) or (AText[ColonPos] <> ':') then
    Exit;
  AN := StrToIntDef(Copy(AText, NumStart, ColonPos - NumStart), 0);

  {Walk digits after ':'}
  EndPos := ColonPos + 1;
  while (EndPos <= Length(AText)) and CharInSet(AText[EndPos], ['0' .. '9']) do
    Inc(EndPos);
  if EndPos = ColonPos + 1 then
  begin
    AN := 1;
    Exit;
  end;
  AD := StrToIntDef(Copy(AText, ColonPos + 1, EndPos - ColonPos - 1), 0);

  if (AN <= 0) or (AD <= 0) then
  begin
    AN := 1;
    AD := 1;
    Exit;
  end;

  Result := True;
end;

function ParseVideoCodec(const AText: string): string;
var
  P, Start: Integer;
begin
  Result := '';

  P := Pos('Video:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Video:');

  {Skip whitespace}
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);

  {Read word characters}
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_']) do
    Inc(P);

  if P > Start then
    Result := Copy(AText, Start, P - Start);
end;

function ParseBitrate(const AText: string): Integer;
var
  P, Start: Integer;
  NumStr: string;
begin
  Result := 0;
  {Look for "bitrate:" on the Duration line (before any Stream lines)}
  P := Pos('bitrate:', AText);
  if P = 0 then
    Exit;
  P := P + Length('bitrate:');
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['0' .. '9']) do
    Inc(P);
  if P > Start then
  begin
    NumStr := Copy(AText, Start, P - Start);
    Result := StrToIntDef(NumStr, 0);
  end;
end;

{Extracts the first line containing APrefix from multi-line ffmpeg output}
function ExtractStreamLine(const AText, APrefix: string): string;
var
  P, LineEnd: Integer;
begin
  Result := '';
  P := Pos(APrefix, AText);
  if P = 0 then
    Exit;
  LineEnd := P;
  while (LineEnd <= Length(AText)) and not CharInSet(AText[LineEnd], [#13, #10]) do
    Inc(LineEnd);
  Result := Copy(AText, P, LineEnd - P);
end;

{Scans backward from position P through characters in ADigitChars,
 returning the extracted number string. P is unchanged.}
function ScanNumberBefore(const ALine: string; P: Integer; const ADigitChars: TSysCharSet): string;
var
  Start: Integer;
begin
  Result := '';
  Start := P;
  while (Start > 0) and CharInSet(ALine[Start], ADigitChars) do
    Dec(Start);
  Inc(Start);
  if Start <= P then
    Result := Copy(ALine, Start, P - Start + 1);
end;

{Skips whitespace backward from position P, returns updated position}
function SkipSpacesBack(const ALine: string; P: Integer): Integer;
begin
  while (P > 0) and (ALine[P] = ' ') do
    Dec(P);
  Result := P;
end;

function ParseFps(const AText: string): Double;
var
  Line, NumStr: string;
  P: Integer;
begin
  Result := 0;
  Line := ExtractStreamLine(AText, 'Video:');
  if Line = '' then
    Exit;
  P := Pos(' fps', Line);
  if P < 2 then
    Exit;
  P := SkipSpacesBack(Line, P - 1);
  NumStr := ScanNumberBefore(Line, P, ['0' .. '9', '.']);
  if NumStr <> '' then
    Result := StrToFloatDef(NumStr, 0, TFormatSettings.Invariant);
end;

{Parses bitrate (kb/s) from a single stream line}
function ParseStreamBitrate(const ALine: string): Integer;
var
  P: Integer;
  NumStr: string;
begin
  Result := 0;
  {Find last occurrence of "kb/s" on the line}
  P := Length(ALine);
  while P > 4 do
  begin
    if (ALine[P] = 's') and (Copy(ALine, P - 3, 4) = 'kb/s') then
    begin
      P := SkipSpacesBack(ALine, P - 4);
      NumStr := ScanNumberBefore(ALine, P, ['0' .. '9']);
      if NumStr <> '' then
        Result := StrToIntDef(NumStr, 0);
      Exit;
    end;
    Dec(P);
  end;
end;

function ParseVideoBitrate(const AText: string): Integer;
begin
  Result := ParseStreamBitrate(ExtractStreamLine(AText, 'Video:'));
end;

function ParseAudioCodec(const AText: string): string;
var
  P, Start: Integer;
begin
  Result := '';
  P := Pos('Audio:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Audio:');
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_']) do
    Inc(P);
  if P > Start then
    Result := Copy(AText, Start, P - Start);
end;

function ParseAudioSampleRate(const AText: string): Integer;
var
  Line, NumStr: string;
  P: Integer;
begin
  Result := 0;
  Line := ExtractStreamLine(AText, 'Audio:');
  if Line = '' then
    Exit;
  P := Pos(' Hz', Line);
  if P < 2 then
    Exit;
  NumStr := ScanNumberBefore(Line, P - 1, ['0' .. '9']);
  if NumStr <> '' then
    Result := StrToIntDef(NumStr, 0);
end;

function ParseAudioChannels(const AText: string): string;
var
  Line: string;
  Parts: TArray<string>;
  I: Integer;
  S: string;
begin
  Result := '';
  Line := ExtractStreamLine(AText, 'Audio:');
  if Line = '' then
    Exit;
  {Audio line format: "Audio: codec (profile) (fourcc), rate Hz, channels, fmt, bitrate"
   Channel layout is a comma-separated field: mono, stereo, 5.1, 7.1, etc.}
  Parts := Line.Split([',']);
  for I := 0 to High(Parts) do
  begin
    S := Parts[I].Trim.ToLower;
    if (S = 'mono') or (S = 'stereo') or (S = '5.1') or (S = '7.1') or (S = '5.1(side)') or (S = '7.1(side)') or (S = '4.0') or (S = '2.1') or (S = '6.1') or (S = '5.0') or (S = 'quad') then
    begin
      Result := Parts[I].Trim;
      Exit;
    end;
  end;
end;

function ParseAudioBitrate(const AText: string): Integer;
begin
  Result := ParseStreamBitrate(ExtractStreamLine(AText, 'Audio:'));
end;

function ParseFFmpegVersion(const AText: string): string;
var
  Line, Prefix: string;
  P, Start: Integer;
begin
  Result := '';
  if AText = '' then
    Exit;

  {Take first line only}
  P := Pos(#10, AText);
  if P > 0 then
    Line := Copy(AText, 1, P - 1)
  else
    Line := AText;
  Line := Trim(Line.Replace(#13, ''));

  Prefix := 'ffmpeg version ';
  if not Line.StartsWith(Prefix, True) then
    Exit;

  {Extract version token (everything up to the next space or dash)}
  P := Length(Prefix) + 1;
  Start := P;
  while (P <= Length(Line)) and not CharInSet(Line[P], [' ', '-']) do
    Inc(P);

  if P > Start then
    Result := Copy(Line, Start, P - Start);
end;

function ValidateFFmpeg(const AExePath: string): string;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  Output: string;
begin
  Result := '';
  CmdLine := Format('"%s" -version', [AExePath]);
  if RunProcess(CmdLine, StdOut, StdErr, 5000) <> 0 then
    Exit;
  if Length(StdOut) > 0 then
    Output := LenientUTF8Decode(StdOut)
  else if Length(StdErr) > 0 then
    Output := LenientUTF8Decode(StdErr)
  else
    Exit;
  Result := ParseFFmpegVersion(Output);
end;

{TFFmpegExe}

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
  {Display dims = storage when SAR=1:1; SAR scales width, leaves height alone}
  Result.DisplayHeight := Result.Height;
  if (Result.Width > 0) and (Result.SampleAspectD > 0) then
    Result.DisplayWidth := Round(Result.Width * Result.SampleAspectN / Result.SampleAspectD)
  else
    Result.DisplayWidth := Result.Width;
  Result.VideoCodec := ParseVideoCodec(StdErrStr);
  Result.Bitrate := ParseBitrate(StdErrStr);
  Result.Fps := ParseFps(StdErrStr);
  Result.VideoBitrateKbps := ParseVideoBitrate(StdErrStr);
  Result.AudioCodec := ParseAudioCodec(StdErrStr);
  Result.AudioSampleRate := ParseAudioSampleRate(StdErrStr);
  Result.AudioChannels := ParseAudioChannels(StdErrStr);
  Result.AudioBitrateKbps := ParseAudioBitrate(StdErrStr);
  Result.IsValid := Result.Duration > 0;

  if not Result.IsValid then
    Result.ErrorMessage := 'Could not parse video metadata';
end;

function BuildExtractCmdLine(const AExePath, AFileName: string; ATimeOffset: Double; const AOptions: TExtractionOptions): string;
var
  Codec, ScaleFilter, HwAccelFlag, KeyframeFlag, ChainFilters: string;
begin
  if AOptions.UseBmpPipe then
    Codec := '-f image2pipe -vcodec bmp'
  else
    Codec := '-q:v 2 -f image2pipe -vcodec png';

  ChainFilters := '';

  {SAR correction goes first: scale=iw*sar:ih turns the storage pixel grid
   into square-pixel display dimensions; setsar=1 stamps SAR=1:1 on the
   output so any downstream stage doesn't double-correct. No-op when the
   source already has SAR=1:1.}
  if AOptions.RespectAnamorphic then
    ChainFilters := 'scale=iw*sar:ih,setsar=1';

  {MaxSide cap: act as a one-way ceiling — sources whose longer side already
   fits pass through at native size; oversized sources get downscaled with
   aspect preserved. The expression min(iw,MAX) caps each target dimension
   at the input's actual size, so when both iw and ih are below MAX the
   filter is a no-op (no upscale). When the source is larger,
   force_original_aspect_ratio=decrease then trims one of the MAX-sized
   target dimensions to preserve aspect.
   The bare 'scale=MAX:MAX:force_original_aspect_ratio=decrease' form would
   upscale smaller sources (e.g. 720x576 anamorphic → 1920x1080) because
   force_original_aspect_ratio=decrease is about preserving aspect, not
   limiting scale direction. Commas inside the expressions need backslash
   escaping so the filter-graph parser does not split the chain on them.
   Applied after SAR correction so the cap operates on display dims.}
  if AOptions.MaxSide > 0 then
  begin
    if ChainFilters <> '' then
      ChainFilters := ChainFilters + ',';
    ChainFilters := ChainFilters + Format('scale=min(iw\,%d):min(ih\,%d):force_original_aspect_ratio=decrease:force_divisible_by=2', [AOptions.MaxSide, AOptions.MaxSide]);
  end;

  if ChainFilters <> '' then
    ScaleFilter := Format('-vf %s ', [ChainFilters])
  else
    ScaleFilter := '';

  if AOptions.HwAccel then
    HwAccelFlag := '-hwaccel auto '
  else
    HwAccelFlag := '';

  if AOptions.UseKeyframes then
    KeyframeFlag := '-noaccurate_seek '
  else
    KeyframeFlag := '';

  Result := Format('"%s" -nostdin -loglevel error %s-ss %s %s-i "%s" ' + '-frames:v 1 %s%s pipe:1', [AExePath, KeyframeFlag, Format('%.3f', [ATimeOffset], TFormatSettings.Invariant), HwAccelFlag, AFileName, ScaleFilter, Codec]);
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
