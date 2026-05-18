{Notification sink that decouples the extraction worker / controller
 from any specific notification transport.

 The worker thread used to call PostMessage(SomeHwnd, WM_FRAME_READY, ...)
 directly, which meant it had to know about a Win32 window handle. That
 coupling made the worker / controller untestable without a real form
 HWND and made any non-Win32 host impossible.

 IFrameNotificationSink lets the worker say "I produced a frame" /
 "I'm done" against an abstract sink. The production wiring uses
 TWindowMessageSink (PostMessage + PeekMessage drain). Tests use a
 capture-only sink that records calls in an array.}
unit uFrameNotificationSink;

interface

uses
  Winapi.Windows, Winapi.Messages;

const
  {Win32 message ids used by TWindowMessageSink. The constants live
   here so they are the documented wire format of the sink, not an
   implementation detail of the worker that ends up reused by other
   layers.}
  WM_FRAME_READY = WM_USER + 100;
  WM_EXTRACTION_DONE = WM_USER + 101;

type
  IFrameNotificationSink = interface
    ['{F1AD7E20-3B14-4C90-A2D8-7E1F9C0B5E83}']
    {Called from a worker thread when one or more frames have landed in
     the shared pending-frame queue. Must be thread-safe.}
    procedure NotifyFramesReady;
    {Called from the last finishing worker thread to signal "extraction
     is over, no more NotifyFramesReady will arrive". Must be thread-safe.}
    procedure NotifyExtractionDone;
    {Called from the controller (main thread, between extractions) to
     drop any still-in-flight notifications so the next extraction
     starts from a clean slate. The implementation decides what
     "drain" means for its transport.}
    procedure DrainPending;
  end;

  {Production sink that translates the three sink calls into the Win32
   PostMessage / PeekMessage transport. PostMessage is documented
   thread-safe; the constructor caches the target HWND and the two
   message ids so the worker call sites pay no per-call lookup.}
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
  {Discard all stale WM_FRAME_READY notifications first (notifications
   carry no payload; the count is meaningless), then drop one
   WM_EXTRACTION_DONE if present (there is at most one per extraction).}
  while PeekMessage(Msg, FHwnd, WM_FRAME_READY, WM_FRAME_READY, PM_REMOVE) do
    ;
  PeekMessage(Msg, FHwnd, WM_EXTRACTION_DONE, WM_EXTRACTION_DONE, PM_REMOVE);
end;

end.
