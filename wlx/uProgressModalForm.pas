{Modal "please wait" form for long-running background work. Currently
 used by the file-reference clipboard copy path so a slow PNG encode
 doesn't leave the lister visually frozen.

 Communicates with the worker thread via Thread.OnTerminate +
 PostMessage to a fixed WM_USER message. The OnTerminate closure
 captures the HWND by value, not the form pointer — so when the user
 cancels and we free the form while the thread keeps encoding in the
 background, the eventual PostMessage targets a dead window and
 silently returns False (documented Win32 behaviour, no crash).

 No polling timer. No Synchronize-on-freed-form races.}
unit uProgressModalForm;

interface

uses
  System.Classes, System.SysUtils, Vcl.Forms;

type
  {Implemented by worker threads that want the modal dialog to close
   automatically when their work is done. SetCompletionCallback wires
   an anonymous procedure the thread invokes from its own context at
   the very end of Execute; the callback is responsible for posting
   the completion signal to the main thread (RunWithProgress provides
   a PostMessage-based one).

   Worker threads that don't implement this interface still run inside
   the modal, but the modal can only close via the user clicking
   Cancel — the function then waits for the thread externally.}
  IModalThreadCompletion = interface
    ['{1A6C7F3D-2E8B-4F71-9A9C-6F3B0F7C9D2A}']
    procedure SetCompletionCallback(ACallback: TProc);
  end;

{Runs AThread inside a modal dialog parented to AOwner. AText appears
 above the marquee progress bar. The function calls AThread.Start
 itself — caller passes a suspended thread.

 If AThread implements IModalThreadCompletion, the modal closes
 automatically with mrOk when the thread completes. Otherwise the
 modal only closes via Cancel.

 Returns True when the thread terminated normally (AThread.Free is the
 caller's responsibility after this call). Returns False when the user
 cancelled via the button, Esc, or X. On False, the caller MUST detach
 the thread (set FreeOnTerminate := True and signal whatever cancel
 mechanism the thread exposes) — this function does not touch AThread
 again after the modal closes, so otherwise the thread leaks.}
function RunWithProgress(AOwner: TCustomForm; AThread: TThread;
  const AText: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls;

const
  {Fixed identifier the worker thread posts to the modal HWND on
   termination. WM_USER+0 is private to this unit; the form's message
   handler is the only place that listens for it.}
  WM_THREAD_DONE = WM_USER + 0;

type
  TProgressModalForm = class(TForm)
  private
    FLabel: TLabel;
    FProgressBar: TProgressBar;
    FBtnCancel: TButton;
    procedure WMThreadDone(var Msg: TMessage); message WM_THREAD_DONE;
    procedure OnCancelClick(Sender: TObject);
  public
    constructor CreateForOwner(AOwner: TCustomForm; const AText: string); reintroduce;
  end;

constructor TProgressModalForm.CreateForOwner(AOwner: TCustomForm; const AText: string);
begin
  inherited CreateNew(AOwner);
  Caption := 'Glimpse';
  BorderStyle := bsDialog;
  {Centre on the active monitor rather than the owner form: TPluginForm
   is parented to TC's Lister via SetParent, so its Left/Top can sit
   outside the monitor's logical coordinates and poOwnerFormCenter
   lands the dialog in the wrong place. poScreenCenter is reliable.}
  Position := poScreenCenter;
  ClientWidth := 360;
  ClientHeight := 110;
  KeyPreview := True;

  FLabel := TLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.SetBounds(16, 14, ClientWidth - 32, 20);
  FLabel.Caption := AText;

  FProgressBar := TProgressBar.Create(Self);
  FProgressBar.Parent := Self;
  FProgressBar.SetBounds(16, 40, ClientWidth - 32, 18);
  FProgressBar.Style := pbstMarquee;
  FProgressBar.MarqueeInterval := 30;

  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := Self;
  FBtnCancel.SetBounds(ClientWidth - 16 - 75, ClientHeight - 12 - 25, 75, 25);
  FBtnCancel.Caption := 'Cancel';
  FBtnCancel.Cancel := True;
  FBtnCancel.OnClick := OnCancelClick;
end;

procedure TProgressModalForm.WMThreadDone(var Msg: TMessage);
begin
  {Worker thread finished naturally. Close the modal with mrOk — unless
   the user already clicked Cancel, in which case ModalResult is mrCancel
   and we leave it.}
  if ModalResult = mrNone then
    ModalResult := mrOk;
end;

procedure TProgressModalForm.OnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function RunWithProgress(AOwner: TCustomForm; AThread: TThread;
  const AText: string): Boolean;
var
  Form: TProgressModalForm;
  CapturedHandle: HWND;
  Completion: IModalThreadCompletion;
begin
  Form := TProgressModalForm.CreateForOwner(AOwner, AText);
  try
    {Force handle creation so PostMessage from the worker thread has a
     valid target the instant the thread starts. Capturing the HWND by
     value (not the form pointer) keeps the completion closure safe
     after the modal is freed — the post lands on a dead window and
     does nothing (documented ERROR_INVALID_WINDOW_HANDLE), instead of
     dereferencing a destroyed VCL object.}
    Form.HandleNeeded;
    CapturedHandle := Form.Handle;
    if Supports(AThread, IModalThreadCompletion, Completion) then
      Completion.SetCompletionCallback(
        procedure
        begin
          PostMessage(CapturedHandle, WM_THREAD_DONE, 0, 0);
        end);
    AThread.Start;
    Result := Form.ShowModal = mrOk;
  finally
    Form.Free;
  end;
end;

end.
