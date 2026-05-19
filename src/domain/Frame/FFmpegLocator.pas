{Locates ffmpeg.exe on the system using a defined search order.}
unit FFmpegLocator;

interface

{Search order: plugin dir, configured path, system PATH.}
function FindFFmpegExe(const APluginDir, AConfiguredPath: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, PathExpand;

const
  FFMPEG_EXE_NAME = 'ffmpeg.exe';

function FindOnSystemPath(const AFileName: string): string;
var
  Buffer: array [0 .. MAX_PATH] of Char;
  FilePart: PChar;
begin
  FilePart := nil;
  if SearchPath(nil, PChar(AFileName), nil, MAX_PATH + 1, Buffer, FilePart) > 0 then
    Result := Buffer
  else
    Result := '';
end;

function FindFFmpegExe(const APluginDir, AConfiguredPath: string): string;
begin
  if APluginDir <> '' then
  begin
    Result := TPath.Combine(APluginDir, FFMPEG_EXE_NAME);
    if TFile.Exists(Result) then
      Exit;
  end;

  if AConfiguredPath <> '' then
  begin
    Result := ExpandEnvVars(AConfiguredPath);
    if TFile.Exists(Result) then
      Exit;
  end;

  Result := FindOnSystemPath(FFMPEG_EXE_NAME);
end;

end.
