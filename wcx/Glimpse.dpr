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
  uProbeCache in '..\src\uProbeCache.pas',
  uFrameFileNames in '..\src\uFrameFileNames.pas',
  uBitmapSaver in '..\src\uBitmapSaver.pas',
  uExtractionPlanner in '..\src\uExtractionPlanner.pas',
  uBitmapResize in '..\src\uBitmapResize.pas',
  uPathExpand in '..\src\uPathExpand.pas',
  uColorConv in '..\src\uColorConv.pas',
  uRunProcess in '..\src\uRunProcess.pas',
  uDefaults in '..\src\uDefaults.pas',
  uFrameExtractor in '..\src\uFrameExtractor.pas',
  uCombinedImage in '..\src\uCombinedImage.pas',
  uRenderDefaults in '..\src\uRenderDefaults.pas',
  uPluginMessages in '..\src\shared\uPluginMessages.pas',
  uVideoProbing in '..\src\uVideoProbing.pas',
  uSettings in '..\src\uSettings.pas',
  uSettingsDlgLogic in '..\src\uSettingsDlgLogic.pas',
  uSettingsDlgUI in '..\src\uSettingsDlgUI.pas',
  uWcxPresets in 'uWcxPresets.pas',
  uWcxListing in 'uWcxListing.pas',
  uWcxProgressBridge in 'uWcxProgressBridge.pas',
  uWcxPresetExtractor in 'uWcxPresetExtractor.pas',
  uNoShadowHints in '..\src\uNoShadowHints.pas';

exports
  OpenArchive,
  OpenArchiveW,
  ReadHeader,
  ReadHeaderExW,
  ProcessFile,
  ProcessFileW,
  CloseArchive,
  SetChangeVolProc,
  SetChangeVolProcW,
  SetProcessDataProc,
  SetProcessDataProcW,
  GetPackerCaps,
  SetDefaultParams,
  PackFiles,
  ConfigurePacker;

begin
  {Surface forgotten Free calls as a Delphi-builtin leak dialog when TC unloads
   the DLL. Debug-only: the report runs at finalization and would be noise for
   end users in release builds.}
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
end.
