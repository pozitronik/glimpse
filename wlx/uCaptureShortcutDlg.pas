{Multi-chord shortcut editor used by the Hotkeys settings tab.

 Each action in the Hotkeys tab can hold any number of chords. This modal
 lets the user view, add, and remove them for a single action. Chords are
 added by pressing keys inside the dialog; conflicts with other actions
 are resolved right at the moment of capture via a confirm prompt.

 Built in code rather than from a DFM so it carries no companion resource
 and has no cross-dialog coupling. Escape always cancels (same trade-off
 as phase 2 — users are unlikely to want to rebind Escape).}
unit uCaptureShortcutDlg;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  uHotkeys;

{Runs the shortcut editor modally.

 @param AOwner Parent window used as ShowModal's parent.
 @param AAction The action being edited; passed through to ABindings for
        the "is the new chord already assigned elsewhere?" conflict check.
 @param ABindings The current global binding table. Read-only from the
        dialog's perspective (the caller installs AResult afterwards).
 @param AResult On True: the chord list the user left the editor with.
                On False: unchanged.
 @return True when the user pressed OK; False on Cancel / Escape.}
function EditShortcuts(AOwner: TWinControl;
  AAction: uHotkeys.TPluginAction;
  const ABindings: uHotkeys.THotkeyBindings;
  out AResult: uHotkeys.THotkeyChordArray): Boolean;

implementation

uses
  System.Math,
  Vcl.Dialogs;

type
  TShortcutEditorForm = class(TForm)
  private
    FLblAction: TLabel;
    FLblHint: TLabel;
    FLstChords: TListBox;
    FBtnRemove: TButton;
    FBtnOK: TButton;
    FBtnCancel: TButton;
    FAction: uHotkeys.TPluginAction;
    FBindings: uHotkeys.THotkeyBindings;
    FChords: uHotkeys.THotkeyChordArray;
    procedure RefreshList;
    procedure UpdateButtonStates;
    procedure HandleKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LstChordsClick(Sender: TObject);
    procedure BtnRemoveClick(Sender: TObject);
    procedure BtnOKClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    {Offers the given chord for the current action. Returns True when the
     chord was accepted (either already present and ignored, or appended
     after the caller resolved any conflict).}
    function OfferChord(const AChord: uHotkeys.THotkeyChord): Boolean;
  public
    constructor CreateFor(AOwner: TComponent;
      AAction: uHotkeys.TPluginAction;
      const ABindings: uHotkeys.THotkeyBindings);
    property Chords: uHotkeys.THotkeyChordArray read FChords;
  end;

constructor TShortcutEditorForm.CreateFor(AOwner: TComponent;
  AAction: uHotkeys.TPluginAction;
  const ABindings: uHotkeys.THotkeyBindings);
begin
  inherited CreateNew(AOwner);
  BorderIcons := [biSystemMenu];
  BorderStyle := bsDialog;
  Caption := Format('Shortcuts for "%s"', [uHotkeys.ActionCaption(AAction)]);
  Position := poOwnerFormCenter;
  ClientWidth := 380;
  ClientHeight := 280;
  KeyPreview := True;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Color := clBtnFace;

  FAction := AAction;
  FBindings := ABindings;
  FChords := ABindings.Get(AAction);

  FLblAction := TLabel.Create(Self);
  FLblAction.Parent := Self;
  FLblAction.SetBounds(16, 14, 348, 16);
  FLblAction.Anchors := [akLeft, akTop, akRight];
  FLblAction.Caption := Format('Action: %s', [uHotkeys.ActionCaption(AAction)]);
  FLblAction.Font.Style := [fsBold];

  FLstChords := TListBox.Create(Self);
  FLstChords.Parent := Self;
  FLstChords.SetBounds(16, 40, 348, 140);
  FLstChords.Anchors := [akLeft, akTop, akRight, akBottom];
  FLstChords.OnClick := LstChordsClick;

  FLblHint := TLabel.Create(Self);
  FLblHint.Parent := Self;
  FLblHint.SetBounds(16, 190, 348, 16);
  FLblHint.Anchors := [akLeft, akRight, akBottom];
  FLblHint.Caption := 'Press a key to add a shortcut (Escape closes the dialog)';
  FLblHint.Font.Color := clGrayText;

  FBtnRemove := TButton.Create(Self);
  FBtnRemove.Parent := Self;
  FBtnRemove.SetBounds(16, 214, 80, 28);
  FBtnRemove.Anchors := [akLeft, akBottom];
  FBtnRemove.Caption := 'Remove';
  FBtnRemove.OnClick := BtnRemoveClick;

  FBtnOK := TButton.Create(Self);
  FBtnOK.Parent := Self;
  FBtnOK.SetBounds(196, 214, 80, 28);
  FBtnOK.Anchors := [akRight, akBottom];
  FBtnOK.Caption := 'OK';
  FBtnOK.OnClick := BtnOKClick;

  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := Self;
  FBtnCancel.SetBounds(282, 214, 80, 28);
  FBtnCancel.Anchors := [akRight, akBottom];
  FBtnCancel.Caption := 'Cancel';
  FBtnCancel.OnClick := BtnCancelClick;

  OnKeyDown := HandleKeyDown;
  RefreshList;
end;

procedure TShortcutEditorForm.RefreshList;
var
  I: Integer;
begin
  FLstChords.Items.BeginUpdate;
  try
    FLstChords.Items.Clear;
    for I := 0 to High(FChords) do
      FLstChords.Items.Add(FChords[I].ToDisplayStr);
  finally
    FLstChords.Items.EndUpdate;
  end;
  UpdateButtonStates;
end;

procedure TShortcutEditorForm.UpdateButtonStates;
begin
  FBtnRemove.Enabled := FLstChords.ItemIndex >= 0;
end;

procedure TShortcutEditorForm.LstChordsClick(Sender: TObject);
begin
  UpdateButtonStates;
end;

function TShortcutEditorForm.OfferChord(const AChord: uHotkeys.THotkeyChord): Boolean;
var
  I: Integer;
  Conflict: uHotkeys.TPluginAction;
  N: Integer;
begin
  {Already in our list: silent no-op per UX spec (user may press the same
   key again without realising — we shouldn't nag).}
  for I := 0 to High(FChords) do
    if FChords[I].Equals(AChord) then
      Exit(True);

  {Check conflict against ALL actions (including the current one's other
   chords wouldn't trigger because we already returned above for dupes).}
  Conflict := FBindings.FindActionByChord(AChord, FAction);
  if Conflict <> uHotkeys.paNone then
  begin
    if MessageBox(Handle,
      PChar(Format('This shortcut is already assigned to "%s". Reassign?',
        [uHotkeys.ActionCaption(Conflict)])),
      'Glimpse', MB_YESNO or MB_ICONQUESTION) <> IDYES then
      Exit(False);
    {The caller (settings dialog) will reconcile: when it compares our
     returned list against the live bindings it'll see the new chord and
     remove it from Conflict. We only commit the intent here.}
  end;

  N := Length(FChords);
  SetLength(FChords, N + 1);
  FChords[N] := AChord;
  Result := True;
end;

procedure TShortcutEditorForm.HandleKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Chord: uHotkeys.THotkeyChord;
begin
  {Escape always cancels — predictable dismissal beats capturability for
   the one key users are least likely to want to rebind.}
  if (Key = VK_ESCAPE) and (Shift * [ssCtrl, ssShift, ssAlt] = []) then
  begin
    ModalResult := mrCancel;
    Key := 0;
    Exit;
  end;

  {Bare modifier keys are dropped — we want a terminal non-modifier key
   to finish the chord.}
  case Key of
    VK_SHIFT, VK_CONTROL, VK_MENU,
    VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU:
    begin
      Key := 0;
      Exit;
    end;
  end;

  Chord := uHotkeys.THotkeyChord.Make(Key, Shift);
  if OfferChord(Chord) then
    RefreshList;
  Key := 0;
end;

procedure TShortcutEditorForm.BtnRemoveClick(Sender: TObject);
var
  Idx, I: Integer;
begin
  Idx := FLstChords.ItemIndex;
  if Idx < 0 then
    Exit;
  for I := Idx to High(FChords) - 1 do
    FChords[I] := FChords[I + 1];
  SetLength(FChords, Length(FChords) - 1);
  RefreshList;
  if FLstChords.Items.Count > 0 then
    FLstChords.ItemIndex := Min(Idx, FLstChords.Items.Count - 1);
  UpdateButtonStates;
end;

procedure TShortcutEditorForm.BtnOKClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TShortcutEditorForm.BtnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function EditShortcuts(AOwner: TWinControl;
  AAction: uHotkeys.TPluginAction;
  const ABindings: uHotkeys.THotkeyBindings;
  out AResult: uHotkeys.THotkeyChordArray): Boolean;
var
  Dlg: TShortcutEditorForm;
begin
  Dlg := TShortcutEditorForm.CreateFor(AOwner, AAction, ABindings);
  try
    Result := Dlg.ShowModal = mrOk;
    if Result then
      AResult := Dlg.Chords;
  finally
    Dlg.Free;
  end;
end;

end.
