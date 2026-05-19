{Notification sink interface that decouples workers from any specific
 transport. Production uses TWindowMessageSink (PostMessage); tests use
 a capture-only sink.}
unit uFrameNotificationSink;

interface

uses
  Winapi.Windows, Winapi.Messages;

const
  WM_FRAME_READY = WM_USER + 100;
  WM_EXTRACTION_DONE = WM_USER + 101;

type
  IFrameNotificationSink = interface
    ['{F1AD7E20-3B14-4C90-A2D8-7E1F9C0B5E83}']
    {Worker thread; must be thread-safe.}
    procedure NotifyFramesReady;
    {Last finishing worker; must be thread-safe.}
    procedure NotifyExtractionDone;
    {Controller (main thread); discards in-flight notifications so the
     next extraction starts clean.}
    procedure DrainPending;
  end;

  TWindowMessageSink = class(TInterfacedObject, IFrameNotificationSink)
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
