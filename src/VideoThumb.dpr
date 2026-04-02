library VideoThumb;

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
  uFFmpegSetupDlg in 'uFFmpegSetupDlg.pas',
  uPluginForm in 'uPluginForm.pas',
  uCache in 'uCache.pas';

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
