{Multi-chord shortcut editor for the Hotkeys settings tab. Conflicts with
 other actions are resolved at capture time via a confirm prompt.}
unit CaptureShortcutDlg;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Hotkeys;

type
  TShortcutEditorForm = class(TForm)
    LblAction: TLabel;
    LblHint: TLabel;
    LstChords: TListBox;
    BtnRemove: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LstChordsClick(Sender: TObject);
    procedure BtnRemoveClick(Sender: TObject);
  private
    FAction: Hotkeys.TPluginAction;
    FBindings: Hotkeys.THotkeyBindings;
    FChords: Hotkeys.THotkeyChordArray;
    procedure RefreshList;
    procedure UpdateButtonStates;
    function OfferChord(const AChord: Hotkeys.THotkeyChord): Boolean;
  public
    {Must be called before ShowModal. ABindings is read-only, used for
     conflict detection against other actions.}
    procedure Initialize(AAction: Hotkeys.TPluginAction; const ABindings: Hotkeys.THotkeyBindings);
    property Chords: Hotkeys.THotkeyChordArray read FChords;
  end;

  {Returns True on OK (AResult carries the edited chord list); False on
   Cancel/Escape leaves AResult untouched.}
function EditShortcuts(AOwner: TWinControl; AAction: Hotkeys.TPluginAction; const ABindings: Hotkeys.THotkeyBindings; out AResult: Hotkeys.THotkeyChordArray): Boolean;

implementation

{$R *.dfm}

uses
  System.Math,
  Vcl.Dialogs;

procedure TShortcutEditorForm.Initialize(AAction: Hotkeys.TPluginAction; const ABindings: Hotkeys.THotkeyBindings);
begin
  FAction := AAction;
  FBindings := ABindings;
  FChords := ABindings.Get(AAction);
  Caption := Format('Shortcuts for "%s"', [Hotkeys.ActionCaption(AAction)]);
  LblAction.Caption := Format('Action: %s', [Hotkeys.ActionCaption(AAction)]);
  RefreshList;
end;

procedure TShortcutEditorForm.RefreshList;
var
  I: Integer;
begin
  LstChords.Items.BeginUpdate;
  try
    LstChords.Items.Clear;
    for I := 0 to High(FChords) do
      LstChords.Items.Add(FChords[I].ToDisplayStr);
  finally
    LstChords.Items.EndUpdate;
  end;
  UpdateButtonStates;
end;

procedure TShortcutEditorForm.UpdateButtonStates;
begin
  BtnRemove.Enabled := LstChords.ItemIndex >= 0;
end;

procedure TShortcutEditorForm.LstChordsClick(Sender: TObject);
begin
  UpdateButtonStates;
end;

function TShortcutEditorForm.OfferChord(const AChord: Hotkeys.THotkeyChord): Boolean;
var
  I: Integer;
  Conflict: Hotkeys.TPluginAction;
  N: Integer;
begin
  {Already in our list: silent no-op per UX spec.}
  for I := 0 to High(FChords) do
    if FChords[I].Equals(AChord) then
      Exit(True);

  Conflict := FBindings.FindActionByChord(AChord, FAction);
  if Conflict <> Hotkeys.paNone then
  begin
    if MessageBox(Handle, PChar(Format('This shortcut is already assigned to "%s". Reassign?', [Hotkeys.ActionCaption(Conflict)])), 'Glimpse', MB_YESNO or MB_ICONQUESTION) <> IDYES then
      Exit(False);
    {Caller reconciles by removing the chord from the conflicting action after OK.}
  end;

  N := Length(FChords);
  SetLength(FChords, N + 1);
  FChords[N] := AChord;
  Result := True;
end;

procedure TShortcutEditorForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Chord: Hotkeys.THotkeyChord;
begin
  {Drop bare modifier keys — chord needs a terminal non-modifier. Escape is
   NOT special-cased so it can be bound like any other key; users cancel via
   the Cancel button or close box.}
  case Key of
    VK_SHIFT, VK_CONTROL, VK_MENU, VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU:
      begin
        Key := 0;
        Exit;
      end;
  end;

  Chord := Hotkeys.THotkeyChord.Make(Key, Shift);
  if OfferChord(Chord) then
    RefreshList;
  Key := 0;
end;

procedure TShortcutEditorForm.BtnRemoveClick(Sender: TObject);
var
  Idx, I: Integer;
begin
  Idx := LstChords.ItemIndex;
  if Idx < 0 then
    Exit;
  for I := Idx to High(FChords) - 1 do
    FChords[I] := FChords[I + 1];
  SetLength(FChords, Length(FChords) - 1);
  RefreshList;
  if LstChords.Items.Count > 0 then
    LstChords.ItemIndex := Min(Idx, LstChords.Items.Count - 1);
  UpdateButtonStates;
end;

function EditShortcuts(AOwner: TWinControl; AAction: Hotkeys.TPluginAction; const ABindings: Hotkeys.THotkeyBindings; out AResult: Hotkeys.THotkeyChordArray): Boolean;
var
  Dlg: TShortcutEditorForm;
begin
  Dlg := TShortcutEditorForm.Create(AOwner);
  try
    Dlg.Initialize(AAction, ABindings);
    Result := Dlg.ShowModal = mrOk;
    if Result then
      AResult := Dlg.Chords;
  finally
    Dlg.Free;
  end;
end;

end.
