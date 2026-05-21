{Notification interfaces that decouple workers and the controller from
 any specific transport. Production uses TWindowMessageSink (PostMessage);
 tests use a capture-only sink.}
unit FrameNotificationSink;

interface

uses
  Winapi.Windows, Winapi.Messages;

const
  WM_FRAME_READY = WM_USER + 100;
  WM_EXTRACTION_DONE = WM_USER + 101;

type
  {Worker-thread role: workers post frame-ready and extraction-done
   signals. Implementations must be thread-safe.}
  IFrameNotifier = interface
    ['{F1AD7E20-3B14-4C90-A2D8-7E1F9C0B5E83}']
    procedure NotifyFramesReady;
    {Posted by the last finishing worker.}
    procedure NotifyExtractionDone;
  end;

  {Controller (main thread) role: discards in-flight notifications so the
   next extraction starts clean.}
  IFrameNotificationDrain = interface
    ['{B8D5F2C9-AE73-4047-C6F1-2D9E5071B3CA}']
    procedure DrainPending;
  end;

  TWindowMessageSink = class(TInterfacedObject, IFrameNotifier, IFrameNotificationDrain)
  strict private
    FHwnd: HWND;
  public
    constructor Create(AHwnd: HWND);
    procedure NotifyFramesReady;
    procedure NotifyExtractionDone;
    procedure DrainPending;
  end;

implementation

constructor TWindowMessageSink.Create(AHwnd: HWND);
begin
  inherited Create;
  FHwnd := AHwnd;
end;

procedure TWindowMessageSink.NotifyFramesReady;
begin
  if FHwnd <> 0 then
    PostMessage(FHwnd, WM_FRAME_READY, 0, 0);
end;

procedure TWindowMessageSink.NotifyExtractionDone;
begin
  if FHwnd <> 0 then
    PostMessage(FHwnd, WM_EXTRACTION_DONE, 0, 0);
end;

procedure TWindowMessageSink.DrainPending;
var
  Msg: TMsg;
begin
  if FHwnd = 0 then
    Exit;
  while PeekMessage(Msg, FHwnd, WM_FRAME_READY, WM_FRAME_READY, PM_REMOVE) do
    ;
  PeekMessage(Msg, FHwnd, WM_EXTRACTION_DONE, WM_EXTRACTION_DONE, PM_REMOVE);
end;

end.
