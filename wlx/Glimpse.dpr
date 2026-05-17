library Glimpse;

{$IFDEF WIN64}
{$E wlx64}
{$ELSE}
{$E wlx}
{$ENDIF}

uses
  Winapi.Windows,
  uTypes in '..\src\uTypes.pas',
  uDefaults in '..\src\uDefaults.pas',
  uWlxAPI in 'uWlxAPI.pas',
  uPluginExports in 'uPluginExports.pas',
  uSettings in '..\src\uSettings.pas',
  uFrameOffsets in '..\src\uFrameOffsets.pas',
  uFFmpegLocator in '..\src\uFFmpegLocator.pas',
  uFFmpegExe in '..\src\uFFmpegExe.pas',
  uFrameView in 'uFrameView.pas',
  uExtractionWorker in '..\src\uExtractionWorker.pas',
  uPluginForm in 'uPluginForm.pas',
  uDebugLog in '..\src\uDebugLog.pas',
  uCache in '..\src\uCache.pas',
  uCacheKey in '..\src\uCacheKey.pas',
  uProbeCache in '..\src\uProbeCache.pas',
  uSettingsDlg in 'uSettingsDlg.pas',
  uCaptureShortcutDlg in 'uCaptureShortcutDlg.pas',
  uFrameFileNames in '..\src\uFrameFileNames.pas',
  uBitmapSaver in '..\src\uBitmapSaver.pas',
  uClipboardImage in '..\src\uClipboardImage.pas',
  uZoomController in 'uZoomController.pas',
  uViewModeLogic in 'uViewModeLogic.pas',
  uExtractionPlanner in '..\src\uExtractionPlanner.pas',
  uToolbarLayout in 'uToolbarLayout.pas',
  uFileNavigator in '..\src\uFileNavigator.pas',
  uPathExpand in '..\src\uPathExpand.pas',
  uColorConv in '..\src\uColorConv.pas',
  uRunProcess in '..\src\uRunProcess.pas',
  uFrameExtractor in '..\src\uFrameExtractor.pas',
  uViewModeLayout in 'uViewModeLayout.pas',
  uFrameExport in 'uFrameExport.pas',
  uExtractionController in 'uExtractionController.pas',
  uSaveResolutionExtractor in 'uSaveResolutionExtractor.pas',
  uCombinedImage in '..\src\uCombinedImage.pas',
  uBitmapResize in '..\src\uBitmapResize.pas',
  uThumbnailRender in '..\src\uThumbnailRender.pas',
  uSettingsDlgLogic in '..\src\uSettingsDlgLogic.pas',
  uSettingsDlgUI in '..\src\uSettingsDlgUI.pas',
  uNoShadowHints in '..\src\uNoShadowHints.pas',
  uPlatformDetect in '..\src\uPlatformDetect.pas',
  uProgressModalForm in 'uProgressModalForm.pas',
  uBitmapWorkThread in 'uBitmapWorkThread.pas';

exports
  ListLoad,
  ListLoadW,
  ListLoadNext,
  ListLoadNextW,
  ListCloseWindow,
  ListGetDetectString,
  ListSearchText,
  ListSendCommand,
  ListSetDefaultParams,
  ListGetPreviewBitmap,
  ListGetPreviewBitmapW;

begin
  {Surface forgotten Free calls as a Delphi-builtin leak dialog when TC unloads
   the DLL. Debug-only: the report runs at finalization and would be noise for
   end users in release builds.}
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
end.
