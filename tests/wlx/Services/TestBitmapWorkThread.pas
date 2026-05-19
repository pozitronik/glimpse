unit TestBitmapWorkThread;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBitmapWorkThread = class
  public
    [Test] procedure ExecuteCallsWorkProcWithOwnedBitmap;
    [Test] procedure ExecuteRecordsOutcomeFromProc;
    [Test] procedure ExecuteCatchesExceptionFromWorkProc;
    [Test] procedure ExecuteToleratesNilWorkProc;
    [Test] procedure ConstructorOwnsBitmap;
    [Test] procedure PostWorkRunsAfterWorkProc;
    [Test] procedure PostWorkReceivesOutcome;
    [Test] procedure PostWorkReceivesCancelledFalseWhenNotCancelled;
    [Test] procedure PostWorkReceivesCancelledTrueAfterRequestCancel;
    [Test] procedure PostWorkExceptionDoesNotPropagate;
    [Test] procedure PostWorkOmittedWhenNil;
    [Test] procedure CompletionCallbackInvokedAfterExecute;
    [Test] procedure CompletionCallbackOmittedWhenNotWired;
    [Test] procedure CancelledStartsFalse;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  Vcl.Graphics,
  BitmapWorkThread, ProgressModalForm;

function MakeTestBitmap: Vcl.Graphics.TBitmap;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  Result.SetSize(4, 4);
end;

procedure RunSync(AThread: TBitmapWorkThread);
begin
  AThread.Start;
  AThread.WaitFor;
end;

procedure TTestBitmapWorkThread.ExecuteCallsWorkProcWithOwnedBitmap;
var
  Thread: TBitmapWorkThread;
  Bmp: Vcl.Graphics.TBitmap;
  SeenBitmap: Vcl.Graphics.TBitmap;
begin
  Bmp := MakeTestBitmap;
  SeenBitmap := nil;
  Thread := TBitmapWorkThread.Create(Bmp,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      SeenBitmap := AB;
      AOutcome.Success := True;
    end);
  try
    RunSync(Thread);
    Assert.AreEqual(NativeUInt(Bmp), NativeUInt(SeenBitmap),
      'Work proc receives the constructor-provided bitmap by reference');
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.ExecuteRecordsOutcomeFromProc;
var
  Thread: TBitmapWorkThread;
begin
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      AOutcome.Success := True;
      AOutcome.ErrorMsg := 'recorded';
    end);
  try
    RunSync(Thread);
    Assert.IsTrue(Thread.Outcome.Success);
    Assert.AreEqual('recorded', Thread.Outcome.ErrorMsg);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.ExecuteCatchesExceptionFromWorkProc;
var
  Thread: TBitmapWorkThread;
begin
  {An uncaught exception escaping the work proc must be turned into a
   recorded failure outcome (with E.Message preserved), not propagated
   out of Execute where it would crash the worker thread.}
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      raise Exception.Create('boom');
    end);
  try
    RunSync(Thread);
    Assert.IsFalse(Thread.Outcome.Success);
    Assert.AreEqual('boom', Thread.Outcome.ErrorMsg);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.ExecuteToleratesNilWorkProc;
var
  Thread: TBitmapWorkThread;
begin
  {Defensive: nil work proc must not AV. Outcome stays at default
   (Success=False).}
  Thread := TBitmapWorkThread.Create(MakeTestBitmap, nil);
  try
    RunSync(Thread);
    Assert.IsFalse(Thread.Outcome.Success);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.ConstructorOwnsBitmap;
var
  Thread: TBitmapWorkThread;
begin
  {Construct + immediately free (no Start). The bitmap must be freed by
   the destructor; the leak detector running at process shutdown would
   fail this test if it weren't.}
  Thread := TBitmapWorkThread.Create(MakeTestBitmap, nil);
  Thread.Free;
  Assert.Pass('Destructor freed the owned bitmap without Execute running');
end;

procedure TTestBitmapWorkThread.PostWorkRunsAfterWorkProc;
var
  Thread: TBitmapWorkThread;
  Order: TStringList;
begin
  Order := TStringList.Create;
  try
    Thread := TBitmapWorkThread.Create(MakeTestBitmap,
      procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
      begin
        Order.Add('work');
        AOutcome.Success := True;
      end,
      procedure(const AOutcome: TBitmapWorkOutcome; ACancelled: Boolean)
      begin
        Order.Add('post');
      end);
    try
      RunSync(Thread);
      Assert.AreEqual(2, Order.Count);
      Assert.AreEqual('work', Order[0]);
      Assert.AreEqual('post', Order[1]);
    finally
      Thread.Free;
    end;
  finally
    Order.Free;
  end;
end;

procedure TTestBitmapWorkThread.PostWorkReceivesOutcome;
var
  Thread: TBitmapWorkThread;
  CapturedSuccess: Boolean;
  CapturedMsg: string;
begin
  CapturedSuccess := False;
  CapturedMsg := '';
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      AOutcome.Success := True;
      AOutcome.ErrorMsg := 'hello';
    end,
    procedure(const AOutcome: TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      CapturedSuccess := AOutcome.Success;
      CapturedMsg := AOutcome.ErrorMsg;
    end);
  try
    RunSync(Thread);
    Assert.IsTrue(CapturedSuccess);
    Assert.AreEqual('hello', CapturedMsg);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.PostWorkReceivesCancelledFalseWhenNotCancelled;
var
  Thread: TBitmapWorkThread;
  SeenCancelled: Boolean;
begin
  {Seed the capture to the opposite of the expected value so we know the
   post-work actually wrote False rather than the variable defaulting.}
  SeenCancelled := True;
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      AOutcome.Success := True;
    end,
    procedure(const AOutcome: TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      SeenCancelled := ACancelled;
    end);
  try
    RunSync(Thread);
    Assert.IsFalse(SeenCancelled);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.PostWorkReceivesCancelledTrueAfterRequestCancel;
var
  Thread: TBitmapWorkThread;
  SeenCancelled: Boolean;
  Done: TEvent;
begin
  {Calls RequestCancel BEFORE Start so FCancelled is already True when
   Execute reads it for the post-work invocation. RequestCancel detaches
   via FreeOnTerminate, so we must NOT touch the Thread reference after
   Start — use a TEvent to know when the post-work has captured its value.

   Side effect: RequestCancel pins our DLL via LoadLibrary. One leaked
   handle per run of this test — acceptable for a unit test that exercises
   the detached-cancel path.}
  SeenCancelled := False;
  Done := TEvent.Create(nil, True, False, '');
  try
    Thread := TBitmapWorkThread.Create(MakeTestBitmap,
      procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
      begin
        AOutcome.Success := True;
      end,
      procedure(const AOutcome: TBitmapWorkOutcome; ACancelled: Boolean)
      begin
        SeenCancelled := ACancelled;
        Done.SetEvent;
      end);
    Thread.RequestCancel;
    Thread.Start;
    Assert.AreEqual(wrSignaled, Done.WaitFor(5000),
      'Post-work fired within 5 seconds');
    Assert.IsTrue(SeenCancelled);
  finally
    Done.Free;
  end;
end;

procedure TTestBitmapWorkThread.PostWorkExceptionDoesNotPropagate;
var
  Thread: TBitmapWorkThread;
begin
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      AOutcome.Success := True;
    end,
    procedure(const AOutcome: TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      raise Exception.Create('post boom');
    end);
  try
    {If the exception escapes Execute, the worker thread crashes and the
     test runner surfaces the failure. The test passes silently if the
     class swallows the post-work exception as designed.}
    RunSync(Thread);
    Assert.Pass('Post-work exception swallowed silently');
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.PostWorkOmittedWhenNil;
var
  Thread: TBitmapWorkThread;
  WorkRan: Boolean;
begin
  WorkRan := False;
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      WorkRan := True;
      AOutcome.Success := True;
    end,
    nil);
  try
    RunSync(Thread);
    Assert.IsTrue(WorkRan);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.CompletionCallbackInvokedAfterExecute;
var
  Thread: TBitmapWorkThread;
  Completion: IModalThreadCompletion;
  CallbackFired: Boolean;
begin
  CallbackFired := False;
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      AOutcome.Success := True;
    end);
  try
    Assert.IsTrue(Supports(Thread, IModalThreadCompletion, Completion),
      'Thread exposes IModalThreadCompletion');
    Completion.SetCompletionCallback(
      procedure
      begin
        CallbackFired := True;
      end);
    {Release the interface ref before Start. The thread is non-refcounted,
     so this is symbolic, but keeping unused interface refs alive across
     thread boundaries is an easy mistake worth not modelling.}
    Completion := nil;
    RunSync(Thread);
    Assert.IsTrue(CallbackFired);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.CompletionCallbackOmittedWhenNotWired;
var
  Thread: TBitmapWorkThread;
begin
  {Without SetCompletionCallback, Execute must skip the callback dispatch.
   If the class accidentally called nil, an AV would crash the worker.}
  Thread := TBitmapWorkThread.Create(MakeTestBitmap,
    procedure(AB: Vcl.Graphics.TBitmap; var AOutcome: TBitmapWorkOutcome)
    begin
      AOutcome.Success := True;
    end);
  try
    RunSync(Thread);
    Assert.IsTrue(Thread.Outcome.Success);
  finally
    Thread.Free;
  end;
end;

procedure TTestBitmapWorkThread.CancelledStartsFalse;
var
  Thread: TBitmapWorkThread;
begin
  Thread := TBitmapWorkThread.Create(MakeTestBitmap, nil);
  try
    Assert.IsFalse(Thread.Cancelled);
  finally
    Thread.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBitmapWorkThread);

end.
