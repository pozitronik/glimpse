library Glimpse;

{$IFDEF WIN64}
{$E wcx64}
{$ELSE}
{$E wcx}
{$ENDIF}

uses
  Winapi.Windows,
  uTypes in '..\src\uTypes.pas',
  uStatusBarLayout in '..\src\uStatusBarLayout.pas',
  uWcxAPI in 'uWcxAPI.pas',
  uWcxExports in 'uWcxExports.pas',
  uWcxSettings in 'uWcxSettings.pas',
  uWcxSettingsDlg in 'uWcxSettingsDlg.pas',
  uFrameOffsets in '..\src\uFrameOffsets.pas',
  uFFmpegLocator in '..\src\uFFmpegLocator.pas',
  uFFmpegExe in '..\src\uFFmpegExe.pas',
  uDebugLog in '..\src\shared\uDebugLog.pas',
  uCacheStorage in '..\src\infrastructure\uCacheStorage.pas',
  uLruEvictionPolicy in '..\src\infrastructure\uLruEvictionPolicy.pas',
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
  uBannerInfo in '..\src\uBannerInfo.pas',
  uBannerPainter in '..\src\uBannerPainter.pas',
  uCombinedGrid in '..\src\uCombinedGrid.pas',
  uTimecodeOverlay in '..\src\uTimecodeOverlay.pas',
  uRenderDefaults in '..\src\uRenderDefaults.pas',
  uPluginMessages in '..\src\shared\uPluginMessages.pas',
  uVideoProbing in '..\src\uVideoProbing.pas',
  uWcxFrameCache in 'uWcxFrameCache.pas',
  uPresetExtractReporter in 'uPresetExtractReporter.pas',
  uWcxProgressCallback in 'uWcxProgressCallback.pas',
  uVideoInfo in '..\src\uVideoInfo.pas',
  uLineSplitter in '..\src\infrastructure\uLineSplitter.pas',
  uFFmpegProbeParser in '..\src\infrastructure\uFFmpegProbeParser.pas',
  uFFmpegCmdLine in '..\src\infrastructure\uFFmpegCmdLine.pas',
  uIniEncoding in '..\src\infrastructure\uIniEncoding.pas',
  uIniDocument in '..\src\infrastructure\uIniDocument.pas',
  uSettings in '..\src\uSettings.pas',
  uSettingsDlgLogic in '..\src\uSettingsDlgLogic.pas',
  uSettingsDlgUI in '..\src\uSettingsDlgUI.pas',
  uCmdLineTokens in 'uCmdLineTokens.pas',
  uWcxPresetValidation in 'uWcxPresetValidation.pas',
  uWcxPresetTemplate in 'uWcxPresetTemplate.pas',
  uFileNameDedupe in 'uFileNameDedupe.pas',
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
