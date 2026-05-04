{Locates ffmpeg.exe on the system using a defined search order.}
unit uFFmpegLocator;

interface

{Searches for ffmpeg.exe in order:
 1. Plugin directory (next to the DLL)
 2. Configured path from INI
 3. System PATH
 Returns the full validated path, or empty string if not found.}
function FindFFmpegExe(const APluginDir, AConfiguredPath: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, uPathExpand;

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
  {1. Plugin directory}
  if APluginDir <> '' then
  begin
    Result := TPath.Combine(APluginDir, FFMPEG_EXE_NAME);
    if TFile.Exists(Result) then
      Exit;
  end;

  {2. Configured path from INI (expand %commander_path% etc.)}
  if AConfiguredPath <> '' then
  begin
    Result := ExpandEnvVars(AConfiguredPath);
    if TFile.Exists(Result) then
      Exit;
  end;

  {3. System PATH}
  Result := FindOnSystemPath(FFMPEG_EXE_NAME);
end;

end.
