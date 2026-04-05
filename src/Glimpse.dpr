library Glimpse;

{$IFDEF WIN64}
  {$E wlx64}
{$ELSE}
  {$E wlx}
{$ENDIF}

uses
  Winapi.Windows,
  uTypes in 'uTypes.pas',
  uWlxAPI in 'uWlxAPI.pas',
  uPluginExports in 'uPluginExports.pas',
  uSettings in 'uSettings.pas',
  uFrameOffsets in 'uFrameOffsets.pas',
  uFFmpegLocator in 'uFFmpegLocator.pas',
  uFFmpegExe in 'uFFmpegExe.pas',
  uFrameView in 'uFrameView.pas',
  uExtractionWorker in 'uExtractionWorker.pas',
  uPluginForm in 'uPluginForm.pas',
  uDebugLog in 'uDebugLog.pas',
  uCache in 'uCache.pas',
  uSettingsDlg in 'uSettingsDlg.pas',
  uFrameFileNames in 'uFrameFileNames.pas',
  uBitmapSaver in 'uBitmapSaver.pas',
  uZoomController in 'uZoomController.pas',
  uViewModeLogic in 'uViewModeLogic.pas',
  uExtractionPlanner in 'uExtractionPlanner.pas',
  uToolbarLayout in 'uToolbarLayout.pas',
  uFileNavigator in 'uFileNavigator.pas',
  uPathExpand in 'uPathExpand.pas',
  uColorConv in 'uColorConv.pas',
  uRunProcess in 'uRunProcess.pas',
  uFrameExtractor in 'uFrameExtractor.pas',
  uViewModeLayout in 'uViewModeLayout.pas';

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
