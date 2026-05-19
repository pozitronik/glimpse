{Modal "please wait" form for long-running background work. The worker
 thread signals completion via PostMessage to a captured HWND (NOT the
 form pointer) so a cancel-then-free path is crash-safe: the PostMessage
 lands on a dead window and silently returns False.}
unit uProgressModalForm;

interface

uses
  System.Classes, System.SysUtils, Vcl.Forms;

type
  {Worker threads implementing this interface let the modal auto-close
   when the work is done. The callback runs in the thread's context and
   is responsible for posting back to the main thread.}
  IModalThreadCompletion = interface
    ['{1A6C7F3D-2E8B-4F71-9A9C-6F3B0F7C9D2A}']
    procedure SetCompletionCallback(ACallback: TProc);
  end;

{Runs AThread inside a modal dialog. Caller passes a suspended thread; the
 function calls AThread.Start itself.

 Returns True when the thread terminated normally — AThread.Free is the
 caller's responsibility. Returns False on cancel; the caller MUST then
 detach the thread (set FreeOnTerminate and signal cancel) or it leaks.}
function RunWithProgress(AOwner: TCustomForm; AThread: TThread;
  const AText: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls;

const
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
  {Centre on screen, not owner: TPluginForm is SetParent'd into TC's
   Lister and its coordinates can sit outside the monitor.}
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
  {Preserve a user-initiated mrCancel; only auto-close when no result yet.}
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
    {Force handle creation so PostMessage has a valid target as soon as
     the thread starts. Capture the HWND by value so a post landing after
     the form is freed silently fails instead of dereferencing it.}
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
