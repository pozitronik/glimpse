{ffmpeg command-line assembly and version probing.}
unit FFmpegCmdLine;

interface

uses
  System.SysUtils,
  Types, ProcessRunner;

function BuildExtractCmdLine(const AExePath, AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions): string;

{Returns the version token (e.g. "6.1.1") or empty when AText is not
 recognizable ffmpeg -version output.}
function ParseFFmpegVersion(const AText: string): string;

{Returns empty string if the executable is not a valid ffmpeg.}
function ValidateFFmpeg(const AExePath: string): string; overload;

{Policy core: the -version subprocess runs through ARunner, so exit-code
 handling and the stdout/stderr fallback are testable with a fake.}
function ValidateFFmpeg(const AExePath: string; const ARunner: IProcessRunner): string; overload;

implementation

uses
  FFmpegProbeParser;

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

  {SAR correction must be applied before MaxSide cap so the cap operates
   on display dims. setsar=1 prevents downstream double-correction.}
  if AOptions.RespectAnamorphic then
    ChainFilters := 'scale=iw*sar:ih,setsar=1';

  {One-way cap: min(iw,MAX) prevents upscale when source already fits.
   Bare scale=MAX:MAX:force_original_aspect_ratio=decrease would upscale
   smaller sources. Commas inside expressions need backslash escaping so
   the filter-graph parser does not split the chain on them.}
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

  P := Pos(#10, AText);
  if P > 0 then
    Line := Copy(AText, 1, P - 1)
  else
    Line := AText;
  Line := Trim(Line.Replace(#13, ''));

  Prefix := 'ffmpeg version ';
  if not Line.StartsWith(Prefix, True) then
    Exit;

  P := Length(Prefix) + 1;
  Start := P;
  while (P <= Length(Line)) and not CharInSet(Line[P], [' ', '-']) do
    Inc(P);

  if P > Start then
    Result := Copy(Line, Start, P - Start);
end;

function ValidateFFmpeg(const AExePath: string; const ARunner: IProcessRunner): string;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  Output: string;
begin
  Result := '';
  CmdLine := Format('"%s" -version', [AExePath]);
  if ARunner.Run(CmdLine, StdOut, StdErr, 5000, 0) <> 0 then
    Exit;
  if Length(StdOut) > 0 then
    Output := LenientUTF8Decode(StdOut)
  else if Length(StdErr) > 0 then
    Output := LenientUTF8Decode(StdErr)
  else
    Exit;
  Result := ParseFFmpegVersion(Output);
end;

function ValidateFFmpeg(const AExePath: string): string;
var
  Runner: IProcessRunner;
begin
  Runner := TProductionProcessRunner.Create;
  Result := ValidateFFmpeg(AExePath, Runner);
end;

end.
