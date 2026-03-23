/// Locates ffmpeg.exe on the system using a defined search order.
unit uFFmpegLocator;

interface

/// Searches for ffmpeg.exe in order:
///   1. Plugin directory (next to the DLL)
///   2. Configured path from INI
///   3. System PATH
/// Returns the full validated path, or empty string if not found.
function FindFFmpegExe(const APluginDir, AConfiguredPath: string): string;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows;

function FindOnSystemPath(const AFileName: string): string;
var
  Buffer: array[0..MAX_PATH] of Char;
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
  { 1. Plugin directory }
  if APluginDir <> '' then
  begin
    Result := TPath.Combine(APluginDir, 'ffmpeg.exe');
    if TFile.Exists(Result) then
      Exit;
  end;

  { 2. Configured path from INI }
  if (AConfiguredPath <> '') and TFile.Exists(AConfiguredPath) then
  begin
    Result := AConfiguredPath;
    Exit;
  end;

  { 3. System PATH }
  Result := FindOnSystemPath('ffmpeg.exe');
end;

end.
