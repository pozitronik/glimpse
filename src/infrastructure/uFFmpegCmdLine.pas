{ffmpeg command-line assembly + version probing.

 Two related concerns extracted from uFFmpegExe so the command-line
 string-building (which is pure and easy to unit-test) lives
 independently of the TFFmpegExe class that spawns the subprocess:

 - BuildExtractCmdLine: assembles the `ffmpeg -i ... -frames:v 1 pipe:1`
   command for a single-frame extraction, honouring the user's
   HwAccel / UseKeyframes / RespectAnamorphic / MaxSide options.

 - ParseFFmpegVersion: extracts the version token (e.g. "6.1.1") from
   the first line of `ffmpeg -version` output.

 - ValidateFFmpeg: runs `ffmpeg -version` and returns the parsed
   version string — empty string means "this exe is not a valid
   ffmpeg" (wrong tool, broken install, etc.). Used by uFFmpegLocator
   to qualify auto-discovered candidates.}
unit uFFmpegCmdLine;

interface

uses
  System.SysUtils,
  uTypes;

{Builds the ffmpeg command line that TFFmpegExe.ExtractFrame executes.
 Pure function: no I/O, no globals. Exposed so the option-to-filter
 mapping (HwAccel, UseKeyframes, MaxSide cap, RespectAnamorphic SAR
 scale) can be verified independently of the actual extraction.}
function BuildExtractCmdLine(const AExePath, AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions): string;

{Parses version string from `ffmpeg -version` output.
 Expects first line like "ffmpeg version 6.1.1 ...".
 Returns version string (e.g. "6.1.1") or empty if not recognized.}
function ParseFFmpegVersion(const AText: string): string;

{Runs `ffmpeg -version` and returns the version string.
 Returns empty string if the executable is not a valid ffmpeg.}
function ValidateFFmpeg(const AExePath: string): string;

implementation

uses
  uRunProcess, uFFmpegProbeParser;

function BuildExtractCmdLine(const AExePath, AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions): string;
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
   upscale smaller sources (e.g. 720x576 anamorphic -> 1920x1080) because
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

  Result := Format('"%s" -nostdin -loglevel error %s-ss %s %s-i "%s" ' + '-frames:v 1 %s%s pipe:1',
    [AExePath, KeyframeFlag, Format('%.3f', [ATimeOffset], TFormatSettings.Invariant),
     HwAccelFlag, AFileName, ScaleFilter, Codec]);
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

end.
