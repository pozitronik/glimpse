{Tests for TWindowMessageSink, the PostMessage-based notification
 transport between extraction workers and the controller. DrainPending's
 contract is "discard ALL in-flight notifications so the next extraction
 starts clean" — the regression pin here is that multiple queued
 WM_EXTRACTION_DONE messages are all drained, not just the first.
 A message-only window gives the test thread a real queue to post into.}
unit TestFrameNotificationSink;

interface

uses
  DUnitX.TestFramework,
  Winapi.Windows, Winapi.Messages,
  FrameNotificationSink;

type
  [TestFixture]
  TTestFrameNotificationSink = class
  strict private
    FWnd: HWND;
    function QueuedCount(AMsgFilter: UINT): Integer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NotifyFramesReady_PostsMessage;
    [Test] procedure NotifyExtractionDone_PostsMessage;
    [Test] procedure DrainPending_RemovesAllQueuedFrameReady;
    [Test] procedure DrainPending_RemovesAllQueuedExtractionDone;
    [Test] procedure DrainPending_LeavesForeignMessagesQueued;
    [Test] procedure ZeroHwnd_AllOperationsAreNoOps;
  end;

implementation

const
  {A message id outside the sink's two-message range; DrainPending must
   not swallow it.}
  WM_TEST_FOREIGN = WM_USER + 200;

procedure TTestFrameNotificationSink.Setup;
begin
  {Message-only window: cheap, invisible, owned by the test thread so
   PostMessage lands in this thread's queue.}
  FWnd := CreateWindowEx(0, 'STATIC', nil, 0, 0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
  if FWnd = 0 then
    Assert.Fail('CreateWindowEx(HWND_MESSAGE) failed');
end;

procedure TTestFrameNotificationSink.TearDown;
var
  Msg: TMsg;
begin
  if FWnd <> 0 then
  begin
    {Purge leftovers so one test's queue cannot bleed into the next.}
    while PeekMessage(Msg, FWnd, 0, 0, PM_REMOVE) do
      ;
    DestroyWindow(FWnd);
    FWnd := 0;
  end;
end;

function TTestFrameNotificationSink.QueuedCount(AMsgFilter: UINT): Integer;
var
  Msg: TMsg;
begin
  Result := 0;
  while PeekMessage(Msg, FWnd, AMsgFilter, AMsgFilter, PM_REMOVE) do
    Inc(Result);
end;

procedure TTestFrameNotificationSink.NotifyFramesReady_PostsMessage;
var
  Notifier: IFrameNotifier;
begin
  Notifier := TWindowMessageSink.Create(FWnd);
  Notifier.NotifyFramesReady;
  Assert.AreEqual(1, QueuedCount(WM_FRAME_READY));
end;

procedure TTestFrameNotificationSink.NotifyExtractionDone_PostsMessage;
var
  Notifier: IFrameNotifier;
begin
  Notifier := TWindowMessageSink.Create(FWnd);
  Notifier.NotifyExtractionDone;
  Assert.AreEqual(1, QueuedCount(WM_EXTRACTION_DONE));
end;

procedure TTestFrameNotificationSink.DrainPending_RemovesAllQueuedFrameReady;
var
  Drain: IFrameNotificationDrain;
begin
  Drain := TWindowMessageSink.Create(FWnd);
  PostMessage(FWnd, WM_FRAME_READY, 0, 0);
  PostMessage(FWnd, WM_FRAME_READY, 0, 0);
  PostMessage(FWnd, WM_FRAME_READY, 0, 0);
  Drain.DrainPending;
  Assert.AreEqual(0, QueuedCount(WM_FRAME_READY));
end;

procedure TTestFrameNotificationSink.DrainPending_RemovesAllQueuedExtractionDone;
var
  Drain: IFrameNotificationDrain;
begin
  Drain := TWindowMessageSink.Create(FWnd);
  {Two queued DONEs model a stop/start lifecycle change where a second
   completion lands before the controller drains. Drain-all must hold
   without relying on the at-most-one-in-flight invariant.}
  PostMessage(FWnd, WM_EXTRACTION_DONE, 0, 0);
  PostMessage(FWnd, WM_EXTRACTION_DONE, 0, 0);
  Drain.DrainPending;
  Assert.AreEqual(0, QueuedCount(WM_EXTRACTION_DONE));
end;

procedure TTestFrameNotificationSink.DrainPending_LeavesForeignMessagesQueued;
var
  Drain: IFrameNotificationDrain;
begin
  Drain := TWindowMessageSink.Create(FWnd);
  PostMessage(FWnd, WM_TEST_FOREIGN, 0, 0);
  PostMessage(FWnd, WM_FRAME_READY, 0, 0);
  PostMessage(FWnd, WM_EXTRACTION_DONE, 0, 0);
  Drain.DrainPending;
  Assert.AreEqual(1, QueuedCount(WM_TEST_FOREIGN),
    'drain must only filter its own two message ids');
end;

procedure TTestFrameNotificationSink.ZeroHwnd_AllOperationsAreNoOps;
var
  Sink: TWindowMessageSink;
  Notifier: IFrameNotifier;
  Drain: IFrameNotificationDrain;
begin
  Sink := TWindowMessageSink.Create(0);
  Notifier := Sink;
  Drain := Sink;
  Notifier.NotifyFramesReady;
  Notifier.NotifyExtractionDone;
  Drain.DrainPending;
  {Nothing must land in the test window's queue and nothing may crash.}
  Assert.AreEqual(0, QueuedCount(WM_FRAME_READY));
  Assert.AreEqual(0, QueuedCount(WM_EXTRACTION_DONE));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameNotificationSink);

end.
