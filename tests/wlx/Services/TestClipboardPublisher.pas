{Pure-text coverage for BuildClipboardCopyFailureMessage. The
 TClipboardPublisher class itself is exercised end-to-end via
 TestFrameExport's copy paths; this fixture pins the user-facing message
 format that does not require a clipboard.}
unit TestClipboardPublisher;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardPublisher = class
  public
    [Test] procedure EmptyFormatReturnsClipboardOpenFailureMessage;
    [Test] procedure EmptyFormatMessageOmitsFormatPlaceholder;
    [Test] procedure CombinedViewIncludesScaleTargetRemedy;
    [Test] procedure CombinedViewIncludesFrameCountRemedy;
    [Test] procedure FrameViewOmitsScaleTargetRemedy;
    [Test] procedure FrameViewIncludesFileReferenceRemedy;
    [Test] procedure FailedFormatNameAppearsInMessage;
  end;

implementation

uses
  System.SysUtils, System.StrUtils,
  ClipboardPublisher;

procedure TTestClipboardPublisher.EmptyFormatReturnsClipboardOpenFailureMessage;
var
  Msg: string;
begin
  {Empty format string is the sentinel for "could not even open the
   clipboard". Message must signal that distinct failure mode so the
   user does not chase format-specific remedies.}
  Msg := BuildClipboardCopyFailureMessage('', False);
  Assert.IsTrue(Pos('could not open the system clipboard', Msg) > 0,
    'must name the open-stage failure');
  Assert.IsTrue(Pos('closing other clipboard-using apps', Msg) > 0,
    'must surface the retry-after-closing-apps hint');
end;

procedure TTestClipboardPublisher.EmptyFormatMessageOmitsFormatPlaceholder;
var
  Msg: string;
begin
  {With no format involved, the message must not leak '[]' or '[%s]'
   placeholders from the Format() template; the empty-format branch
   takes a separate template entirely.}
  Msg := BuildClipboardCopyFailureMessage('', True);
  Assert.IsFalse(Pos('[]', Msg) > 0, 'empty-format branch must not emit empty brackets');
  Assert.IsFalse(Pos('%s', Msg) > 0, 'no unfilled format token');
end;

procedure TTestClipboardPublisher.CombinedViewIncludesScaleTargetRemedy;
var
  Msg: string;
begin
  Msg := BuildClipboardCopyFailureMessage('CF_DIB', True);
  Assert.IsTrue(Pos('Scale target', Msg) > 0,
    'combined view remedy must mention lowering the Scale target');
end;

procedure TTestClipboardPublisher.CombinedViewIncludesFrameCountRemedy;
var
  Msg: string;
begin
  Msg := BuildClipboardCopyFailureMessage('PNG', True);
  Assert.IsTrue(Pos('frame count', Msg) > 0,
    'combined view remedy must mention reducing frame count');
end;

procedure TTestClipboardPublisher.FrameViewOmitsScaleTargetRemedy;
var
  Msg: string;
begin
  {Single-frame view has no Scale target / frame-count knobs; remedy
   must not suggest them or the user will waste time looking.}
  Msg := BuildClipboardCopyFailureMessage('CF_DIB', False);
  Assert.IsFalse(Pos('Scale target', Msg) > 0,
    'frame view remedy must not mention Scale target');
  Assert.IsFalse(Pos('frame count', Msg) > 0,
    'frame view remedy must not mention frame count');
end;

procedure TTestClipboardPublisher.FrameViewIncludesFileReferenceRemedy;
var
  Msg: string;
begin
  Msg := BuildClipboardCopyFailureMessage('PNG', False);
  Assert.IsTrue(Pos('file reference', Msg) > 0,
    'frame view remedy must suggest enabling file reference');
end;

procedure TTestClipboardPublisher.FailedFormatNameAppearsInMessage;
var
  Msg: string;
begin
  {The failing strategy name must appear so the user can find it in the
   settings dialog. Tested separately for both view modes so a future
   message-template refactor cannot silently drop it.}
  Msg := BuildClipboardCopyFailureMessage('CF_HDROP', True);
  Assert.IsTrue(Pos('CF_HDROP', Msg) > 0, 'combined: failed format name must appear');
  Msg := BuildClipboardCopyFailureMessage('CF_HDROP', False);
  Assert.IsTrue(Pos('CF_HDROP', Msg) > 0, 'frame: failed format name must appear');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardPublisher);

end.
