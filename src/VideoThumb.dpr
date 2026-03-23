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
  uFrameOffsets in 'uFrameOffsets.pas';

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
