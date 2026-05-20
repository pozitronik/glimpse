{Locates ffmpeg.exe on the system using a defined search order: plugin
 dir, configured path, system PATH. The IExecutableLocatorIO seam lets
 the search-order policy be tested without ffmpeg.exe on disk or PATH.}
unit FFmpegLocator;

interface

type
  {Filesystem and PATH probes the search-order policy depends on. The
   production adapter is private to this unit; tests pass a fake.}
  IExecutableLocatorIO = interface
    ['{4A7C2E91-8D63-4B05-9F1A-2E6C8B5D3047}']
    function FileExists(const APath: string): Boolean;
    function FindOnSystemPath(const AFileName: string): string;
  end;

{Search order: plugin dir, configured path, system PATH.}
function FindFFmpegExe(const APluginDir, AConfiguredPath: string): string; overload;

{Policy core: every filesystem touch goes through AIO, so the search
 order is testable with a fake.}
function FindFFmpegExe(const APluginDir, AConfiguredPath: string;
  const AIO: IExecutableLocatorIO): string; overload;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, PathExpand;

const
  FFMPEG_EXE_NAME = 'ffmpeg.exe';

type
  TSystemExecutableLocatorIO = class(TInterfacedObject, IExecutableLocatorIO)
  public
    function FileExists(const APath: string): Boolean;
    function FindOnSystemPath(const AFileName: string): string;
  end;

function TSystemExecutableLocatorIO.FileExists(const APath: string): Boolean;
begin
  Result := TFile.Exists(APath);
end;

function TSystemExecutableLocatorIO.FindOnSystemPath(const AFileName: string): string;
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

function FindFFmpegExe(const APluginDir, AConfiguredPath: string;
  const AIO: IExecutableLocatorIO): string;
begin
  if APluginDir <> '' then
  begin
    Result := TPath.Combine(APluginDir, FFMPEG_EXE_NAME);
    if AIO.FileExists(Result) then
      Exit;
  end;

  if AConfiguredPath <> '' then
  begin
    Result := ExpandEnvVars(AConfiguredPath);
    if AIO.FileExists(Result) then
      Exit;
  end;

  Result := AIO.FindOnSystemPath(FFMPEG_EXE_NAME);
end;

function FindFFmpegExe(const APluginDir, AConfiguredPath: string): string;
var
  IO: IExecutableLocatorIO;
begin
  IO := TSystemExecutableLocatorIO.Create;
  Result := FindFFmpegExe(APluginDir, AConfiguredPath, IO);
end;

end.
