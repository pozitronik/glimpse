{Multi-chord shortcut editor used by the Hotkeys settings tab.

 Each action in the Hotkeys tab can hold any number of chords. This modal
 lets the user view, add, and remove them for a single action. Chords are
 added by pressing keys inside the dialog; conflicts with other actions
 are resolved right at the moment of capture via a confirm prompt.

 DFM-driven so the layout can be tweaked in the Delphi designer. Escape
 always cancels (same trade-off as the single-chord capture had — users
 are unlikely to want to rebind Escape itself).}
unit uCaptureShortcutDlg;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  uHotkeys;

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
    FAction: uHotkeys.TPluginAction;
    FBindings: uHotkeys.THotkeyBindings;
    FChords: uHotkeys.THotkeyChordArray;
    procedure RefreshList;
    procedure UpdateButtonStates;
    function OfferChord(const AChord: uHotkeys.THotkeyChord): Boolean;
  public
    {Must be called before ShowModal. Seeds the dialog with the current
     chord list for AAction; ABindings is used read-only for conflict
     detection against other actions.}
    procedure Initialize(AAction: uHotkeys.TPluginAction; const ABindings: uHotkeys.THotkeyBindings);
    property Chords: uHotkeys.THotkeyChordArray read FChords;
  end;

  {Runs the shortcut editor modally. Returns True when the user pressed OK;
   AResult then carries the edited chord list. Returns False on Cancel /
   Escape (AResult is left untouched).}
function EditShortcuts(AOwner: TWinControl; AAction: uHotkeys.TPluginAction; const ABindings: uHotkeys.THotkeyBindings; out AResult: uHotkeys.THotkeyChordArray): Boolean;

implementation

{$R *.dfm}

uses
  System.Math,
  Vcl.Dialogs;

procedure TShortcutEditorForm.Initialize(AAction: uHotkeys.TPluginAction; const ABindings: uHotkeys.THotkeyBindings);
begin
  FAction := AAction;
  FBindings := ABindings;
  FChords := ABindings.Get(AAction);
  Caption := Format('Shortcuts for "%s"', [uHotkeys.ActionCaption(AAction)]);
  LblAction.Caption := Format('Action: %s', [uHotkeys.ActionCaption(AAction)]);
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

function TShortcutEditorForm.OfferChord(const AChord: uHotkeys.THotkeyChord): Boolean;
var
  I: Integer;
  Conflict: uHotkeys.TPluginAction;
  N: Integer;
begin
  {Already in our list: silent no-op per UX spec.}
  for I := 0 to High(FChords) do
    if FChords[I].Equals(AChord) then
      Exit(True);

  Conflict := FBindings.FindActionByChord(AChord, FAction);
  if Conflict <> uHotkeys.paNone then
  begin
    if MessageBox(Handle, PChar(Format('This shortcut is already assigned to "%s". Reassign?', [uHotkeys.ActionCaption(Conflict)])), 'Glimpse', MB_YESNO or MB_ICONQUESTION) <> IDYES then
      Exit(False);
    {The caller (settings dialog) will reconcile by removing the chord
     from the conflicting action after we return OK.}
  end;

  N := Length(FChords);
  SetLength(FChords, N + 1);
  FChords[N] := AChord;
  Result := True;
end;

procedure TShortcutEditorForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Chord: uHotkeys.THotkeyChord;
begin
  {Bare modifier keys are dropped — we want a terminal non-modifier key
   to finish the chord. Escape is deliberately NOT special-cased so it can
   be captured and bound like any other key; users cancel the dialog via
   the Cancel button or the window-frame close.}
  case Key of
    VK_SHIFT, VK_CONTROL, VK_MENU, VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU:
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

function EditShortcuts(AOwner: TWinControl; AAction: uHotkeys.TPluginAction; const ABindings: uHotkeys.THotkeyBindings; out AResult: uHotkeys.THotkeyChordArray): Boolean;
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
