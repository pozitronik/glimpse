library Glimpse;

{$IFDEF WIN64}
  {$E wcx64}
{$ELSE}
  {$E wcx}
{$ENDIF}

uses
  Winapi.Windows,
  uTypes in '..\src\uTypes.pas',
  uWcxAPI in 'uWcxAPI.pas',
  uWcxExports in 'uWcxExports.pas',
  uWcxSettings in 'uWcxSettings.pas',
  uWcxSettingsDlg in 'uWcxSettingsDlg.pas',
  uFrameOffsets in '..\src\uFrameOffsets.pas',
  uFFmpegLocator in '..\src\uFFmpegLocator.pas',
  uFFmpegExe in '..\src\uFFmpegExe.pas',
  uDebugLog in '..\src\uDebugLog.pas',
  uCache in '..\src\uCache.pas',
  uCacheKey in '..\src\uCacheKey.pas',
  uFrameFileNames in '..\src\uFrameFileNames.pas',
  uBitmapSaver in '..\src\uBitmapSaver.pas',
  uExtractionPlanner in '..\src\uExtractionPlanner.pas',
  uPathExpand in '..\src\uPathExpand.pas',
  uColorConv in '..\src\uColorConv.pas',
  uRunProcess in '..\src\uRunProcess.pas',
  uDefaults in '..\src\uDefaults.pas',
  uFrameExtractor in '..\src\uFrameExtractor.pas',
  uCombinedImage in '..\src\uCombinedImage.pas',
  uSettings in '..\src\uSettings.pas';

exports
  OpenArchive,
  OpenArchiveW,
  ReadHeader,
  ReadHeaderExW,
  ProcessFile,
  ProcessFileW,
  CloseArchive,
  SetChangeVolProc,
  SetProcessDataProc,
  GetPackerCaps,
  SetDefaultParams,
  PackFiles,
  ConfigurePacker;

begin
end.
