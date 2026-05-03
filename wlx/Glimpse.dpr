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
  uCombinedImage in '..\src\uCombinedImage.pas',
  uBitmapResize in '..\src\uBitmapResize.pas',
  uThumbnailRender in '..\src\uThumbnailRender.pas',
  uSettingsDlgLogic in '..\src\uSettingsDlgLogic.pas',
  uSettingsDlgUI in '..\src\uSettingsDlgUI.pas';

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

end.
