unit TestFrameExport;

interface

uses
  DUnitX.TestFramework;

type

  [TestFixture]
  TTestRunBitmapWorkInModal = class
  public
    {RunBitmapWorkInModal is the shared scaffolding behind
     PublishBitmapAsFileReference and PublishBitmapToClipboardAsImage:
     it transfers bitmap ownership to a TBitmapWorkThread, runs it via
     an optional TAsyncTaskRunner (host modal) or synchronously when nil,
     and maps the thread's outcome to a tri-state TClipboardPublishResult.
     The cancel path is exercised at integration level (manual TC test);
     unit tests would either leak a DLL handle or race on FreeOnTerminate.}
    [Test] procedure WorkSucceeds_ReturnsSuccess;
    [Test] procedure WorkFails_ReturnsFailedWithOutcomePopulated;
    [Test] procedure WorkRaises_ReturnsFailedWithErrorMsg;
    [Test] procedure NilRunner_RunsSynchronouslyAndSucceeds;
    [Test] procedure NilBitmap_ReturnsFailedWithoutCallingWork;
    [Test] procedure BitmapOwnershipTransferred_ABitmapBecomesNil;
    [Test] procedure OutcomePreClearedEvenWhenCallerPrePopulates;
    [Test] procedure RunnerReceivesStatusText;
    [Test] procedure PostWorkRunsAfterWorkProc;
    [Test] procedure PostWorkRunsEvenOnWorkFailure;
  end;

  {BuildClipboardCopyFailureMessage composes the user-facing MessageDlg
   text after a failed PublishBitmapToClipboardAsImage call. Two axes:
     1. Did a specific format's Allocate fail (AFailedFormat non-empty)
        vs did the clipboard fail to open (AFailedFormat empty)?
     2. Is the caller a combined-view operation (remedies include
        "lower Scale target" and "reduce frame count") or a single-frame
        operation (those remedies do not apply)?
   The pure helper lives in the FrameExport interface section so these
   tests can exercise it without the WLX form harness.}
  [TestFixture]
  TTestBuildClipboardCopyFailureMessage = class
  public
    [Test] procedure EmptyFormat_ProducesClipboardOpenFailureMessage;
    [Test] procedure EmptyFormat_IsCombinedViewIrrelevant;
    [Test] procedure NamedFormat_IncludesFormatNameInOutput;
    [Test] procedure FrameContext_RemedyDoesNotMentionScaleOrFrameCount;
    [Test] procedure CombinedContext_RemedyMentionsScaleAndFrameCount;
    [Test] procedure BothContexts_MentionClipboardTabAndFileReference;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics,
  FrameExport, BitmapWorkThread;

{ TTestRunBitmapWorkInModal }

function MakeWorkTestBitmap: Vcl.Graphics.TBitmap;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  Result.SetSize(4, 4);
end;

procedure TTestRunBitmapWorkInModal.WorkSucceeds_ReturnsSuccess;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
begin
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := True;
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprSuccess, Res);
  Assert.IsTrue(Outcome.Success);
end;

procedure TTestRunBitmapWorkInModal.WorkFails_ReturnsFailedWithOutcomePopulated;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
begin
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := False;
      AOut.ErrorMsg := 'work declined';
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprFailed, Res);
  Assert.IsFalse(Outcome.Success);
  Assert.AreEqual('work declined', Outcome.ErrorMsg);
end;

procedure TTestRunBitmapWorkInModal.WorkRaises_ReturnsFailedWithErrorMsg;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
begin
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      raise Exception.Create('mid-work crash');
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprFailed, Res);
  Assert.AreEqual('mid-work crash', Outcome.ErrorMsg);
end;

procedure TTestRunBitmapWorkInModal.NilRunner_RunsSynchronouslyAndSucceeds;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
  WorkRan: Boolean;
begin
  WorkRan := False;
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, 'ignored',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      WorkRan := True;
      AOut.Success := True;
    end,
    nil,
    nil,
    Outcome);
  Assert.AreEqual(cprSuccess, Res);
  Assert.IsTrue(WorkRan, 'Work proc executed via the synchronous fallback');
end;

procedure TTestRunBitmapWorkInModal.NilBitmap_ReturnsFailedWithoutCallingWork;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
  WorkRan: Boolean;
begin
  WorkRan := False;
  Bmp := nil;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      WorkRan := True;
      AOut.Success := True;
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprFailed, Res);
  Assert.IsFalse(WorkRan, 'Work proc must not run when bitmap is nil');
end;

procedure TTestRunBitmapWorkInModal.BitmapOwnershipTransferred_ABitmapBecomesNil;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
begin
  Bmp := MakeWorkTestBitmap;
  RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := True;
    end,
    nil, nil, Outcome);
  Assert.IsNull(Bmp, 'Caller-side var becomes nil — ownership moved into the thread');
end;

procedure TTestRunBitmapWorkInModal.OutcomePreClearedEvenWhenCallerPrePopulates;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
begin
  {Caller may reuse the same Outcome variable across calls. The helper
   must clear it on entry so a stale ErrorMsg from a previous call does
   not bleed into a subsequent nil-bitmap early-exit.}
  Outcome.Success := True;
  Outcome.ErrorMsg := 'stale value';
  Bmp := nil;
  RunBitmapWorkInModal(Bmp, '', nil, nil, nil, Outcome);
  Assert.IsFalse(Outcome.Success, 'Pre-cleared on entry');
  Assert.AreEqual('', Outcome.ErrorMsg);
end;

procedure TTestRunBitmapWorkInModal.RunnerReceivesStatusText;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  CapturedText: string;
begin
  Bmp := MakeWorkTestBitmap;
  CapturedText := '';
  RunBitmapWorkInModal(Bmp, 'hello status',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := True;
    end,
    nil,
    function(AT: TThread; const AText: string): Boolean
    begin
      CapturedText := AText;
      AT.Start;
      AT.WaitFor;
      Result := True;
    end,
    Outcome);
  Assert.AreEqual('hello status', CapturedText);
end;

procedure TTestRunBitmapWorkInModal.PostWorkRunsAfterWorkProc;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  Order: TStringList;
begin
  Order := TStringList.Create;
  try
    Bmp := MakeWorkTestBitmap;
    RunBitmapWorkInModal(Bmp, '',
      procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
      begin
        Order.Add('work');
        AOut.Success := True;
      end,
      procedure(const AOut: BitmapWorkThread.TBitmapWorkOutcome; ACancelled: Boolean)
      begin
        Order.Add('post');
      end,
      nil, Outcome);
    Assert.AreEqual(2, Order.Count);
    Assert.AreEqual('work', Order[0]);
    Assert.AreEqual('post', Order[1]);
  finally
    Order.Free;
  end;
end;

procedure TTestRunBitmapWorkInModal.PostWorkRunsEvenOnWorkFailure;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: BitmapWorkThread.TBitmapWorkOutcome;
  PostRan: Boolean;
begin
  {Mirrors the file-reference path: even when SaveBitmapToFile fails,
   the post-work fires so any cleanup (delete partial file) can run.
   The current file-reference post-work guards with AOut.Success — this
   test does not assert that policy, only that the post-work hook is
   invoked at all.}
  PostRan := False;
  Bmp := MakeWorkTestBitmap;
  RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: BitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := False;
      AOut.ErrorMsg := 'declined';
    end,
    procedure(const AOut: BitmapWorkThread.TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      PostRan := True;
    end,
    nil, Outcome);
  Assert.IsTrue(PostRan);
end;

{ TTestBuildClipboardCopyFailureMessage }

procedure TTestBuildClipboardCopyFailureMessage.EmptyFormat_ProducesClipboardOpenFailureMessage;
var
  S: string;
begin
  S := BuildClipboardCopyFailureMessage('', False);
  Assert.Contains(S, 'could not open the system clipboard',
    'Empty format name signals a clipboard-open failure; the message must say so');
end;

procedure TTestBuildClipboardCopyFailureMessage.EmptyFormat_IsCombinedViewIrrelevant;
var
  SFrame, SCombined: string;
begin
  {When the failure is at clipboard-open (no specific format), the
   combined-view distinction does not apply — both contexts must yield
   the same message.}
  SFrame := BuildClipboardCopyFailureMessage('', False);
  SCombined := BuildClipboardCopyFailureMessage('', True);
  Assert.AreEqual(SFrame, SCombined,
    'Clipboard-open failure message must not branch on view context');
end;

procedure TTestBuildClipboardCopyFailureMessage.NamedFormat_IncludesFormatNameInOutput;
var
  S: string;
begin
  {The whole point of the failing-format out-param is that the dialog
   names the format the user should disable.}
  S := BuildClipboardCopyFailureMessage('Alpha-aware bitmap', False);
  Assert.Contains(S, 'Alpha-aware bitmap',
    'Failing format name must appear in the dialog body');
end;

procedure TTestBuildClipboardCopyFailureMessage.FrameContext_RemedyDoesNotMentionScaleOrFrameCount;
var
  S: string;
begin
  {Single-frame paths cannot lower the Scale target or reduce frame
   count — those remedies belong to combined-view operations only.}
  S := BuildClipboardCopyFailureMessage('Compressed PNG', False);
  Assert.IsFalse(S.Contains('Scale target'),
    'Frame-context remedy must not suggest lowering Scale target');
  Assert.IsFalse(S.Contains('frame count'),
    'Frame-context remedy must not suggest reducing frame count');
end;

procedure TTestBuildClipboardCopyFailureMessage.CombinedContext_RemedyMentionsScaleAndFrameCount;
var
  S: string;
begin
  S := BuildClipboardCopyFailureMessage('Compressed PNG', True);
  Assert.Contains(S, 'Scale target',
    'Combined-context remedy must suggest lowering Scale target');
  Assert.Contains(S, 'frame count',
    'Combined-context remedy must suggest reducing frame count');
end;

procedure TTestBuildClipboardCopyFailureMessage.BothContexts_MentionClipboardTabAndFileReference;
var
  SFrame, SCombined: string;
begin
  {Both single-frame and combined-view remedies share the two universal
   suggestions: disable the format on the Clipboard tab, or switch on
   the file-reference override. Pin both for both contexts so a remedy
   rewording does not accidentally drop one.}
  SFrame := BuildClipboardCopyFailureMessage('GDI bitmap handle', False);
  SCombined := BuildClipboardCopyFailureMessage('GDI bitmap handle', True);
  Assert.Contains(SFrame, 'Clipboard tab');
  Assert.Contains(SFrame, 'file reference');
  Assert.Contains(SCombined, 'Clipboard tab');
  Assert.Contains(SCombined, 'file reference');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRunBitmapWorkInModal);
  TDUnitX.RegisterTestFixture(TTestBuildClipboardCopyFailureMessage);

end.
