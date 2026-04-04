library Glimpse;

{$IFDEF WIN64}
  {$E wlx64}
{$ELSE}
  {$E wlx}
{$ENDIF}

uses
  Winapi.Windows,
  uWlxAPI in 'uWlxAPI.pas',
  uPluginExports in 'uPluginExports.pas',
  uSettings in 'uSettings.pas',
  uFrameOffsets in 'uFrameOffsets.pas',
  uFFmpegLocator in 'uFFmpegLocator.pas',
  uFFmpegExe in 'uFFmpegExe.pas',
  uPluginForm in 'uPluginForm.pas',
  uCache in 'uCache.pas',
  uSettingsDlg in 'uSettingsDlg.pas',
  uFrameFileNames in 'uFrameFileNames.pas',
  uBitmapSaver in 'uBitmapSaver.pas',
  uZoomController in 'uZoomController.pas',
  uViewModeLogic in 'uViewModeLogic.pas',
  uExtractionPlanner in 'uExtractionPlanner.pas',
  uToolbarLayout in 'uToolbarLayout.pas';

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
