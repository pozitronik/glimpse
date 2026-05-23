{Drives the Hotkeys tab of the settings dialog: list-view population,
 row refresh after capture, and the four button / dbl-click gestures.
 The bindings table is borrowed from the host form; the presenter
 mutates it directly in response to user gestures. The host owns the
 VCL controls (DFM-defined) and the bindings snapshot (typically
 imported from / exported to TPluginSettings.Hotkeys at apply time).}
unit HotkeyUIPresenter;

interface

uses
  System.Classes,
  Vcl.ComCtrls, Vcl.Forms,
  Hotkeys;

type
  THotkeyUIPresenter = class
  strict private
    FOwnerForm: TForm;
    FListView: TListView;
    FBindings: THotkeyBindings;
    {Parallel to FListView.Items, indexed by Item.Index. Maps row to
     action without leaning on the row position matching the enum
     ordinal — keeps the mapping intact if the populated subset ever
     skips actions.}
    FRowActions: TArray<TPluginAction>;
    procedure RefreshRow(AAction: TPluginAction);
    function SelectedAction: TPluginAction;
    procedure CaptureAndAssign(AAction: TPluginAction);
  public
    {AOwnerForm parents the capture-shortcut modal dialog and the
     reset-confirm message box. AListView and ABindings are borrowed;
     the host owns both.}
    constructor Create(AOwnerForm: TForm; AListView: TListView; ABindings: THotkeyBindings);
    procedure Populate;
    {Forwarded from the host form's DFM-wired handlers so DFM event
     names remain unchanged.}
    procedure HandleListDblClick(Sender: TObject);
    procedure HandleAssignClick(Sender: TObject);
    procedure HandleClearClick(Sender: TObject);
    procedure HandleResetAllClick(Sender: TObject);
  end;

implementation

uses
  Winapi.Windows,
  CaptureShortcutDlg, HotkeysDisplay, PluginMessages;

constructor THotkeyUIPresenter.Create(AOwnerForm: TForm; AListView: TListView; ABindings: THotkeyBindings);
begin
  inherited Create;
  FOwnerForm := AOwnerForm;
  FListView := AListView;
  FBindings := ABindings;
end;

procedure THotkeyUIPresenter.Populate;
var
  A: TPluginAction;
  Item: TListItem;
begin
  SetLength(FRowActions, 0);
  FListView.Items.BeginUpdate;
  try
    FListView.Items.Clear;
    for A := Succ(paNone) to High(TPluginAction) do
    begin
      Item := FListView.Items.Add;
      Item.Caption := ActionCaption(A);
      SetLength(FRowActions, Length(FRowActions) + 1);
      FRowActions[High(FRowActions)] := A;
      Item.SubItems.Add(ChordsToDisplayStr(FBindings.Get(A)));
    end;
  finally
    FListView.Items.EndUpdate;
  end;
end;

procedure THotkeyUIPresenter.RefreshRow(AAction: TPluginAction);
var
  I: Integer;
  Item: TListItem;
  Display: string;
begin
  Display := ChordsToDisplayStr(FBindings.Get(AAction));
  for I := 0 to FListView.Items.Count - 1 do
  begin
    if (I < Length(FRowActions)) and (FRowActions[I] = AAction) then
    begin
      Item := FListView.Items[I];
      if Item.SubItems.Count = 0 then
        Item.SubItems.Add(Display)
      else
        Item.SubItems[0] := Display;
      Exit;
    end;
  end;
end;

function THotkeyUIPresenter.SelectedAction: TPluginAction;
var
  Item: TListItem;
begin
  Item := FListView.Selected;
  if Item = nil then
    Exit(paNone);
  if (Item.Index < 0) or (Item.Index >= Length(FRowActions)) then
    Exit(paNone);
  Result := FRowActions[Item.Index];
end;

procedure THotkeyUIPresenter.CaptureAndAssign(AAction: TPluginAction);
var
  NewChords: THotkeyChordArray;
  EvictedActions: TArray<TPluginAction>;
  Evicted: TPluginAction;
begin
  if AAction = paNone then
    Exit;
  if not EditShortcuts(FOwnerForm, AAction, FBindings, NewChords) then
    Exit;

  {ReassignExclusive removes NewChords from any other action that owned
   them (the editor already prompted the user and they said "Yes,
   reassign") and Puts NewChords on AAction. Returns the list of actions
   whose rows need a UI refresh.}
  EvictedActions := FBindings.ReassignExclusive(AAction, NewChords);
  for Evicted in EvictedActions do
    RefreshRow(Evicted);
  RefreshRow(AAction);
end;

procedure THotkeyUIPresenter.HandleListDblClick(Sender: TObject);
begin
  CaptureAndAssign(SelectedAction);
end;

procedure THotkeyUIPresenter.HandleAssignClick(Sender: TObject);
begin
  CaptureAndAssign(SelectedAction);
end;

procedure THotkeyUIPresenter.HandleClearClick(Sender: TObject);
var
  A: TPluginAction;
begin
  A := SelectedAction;
  if A = paNone then
    Exit;
  FBindings.Put(A, nil);
  RefreshRow(A);
end;

procedure THotkeyUIPresenter.HandleResetAllClick(Sender: TObject);
begin
  if ShowPluginMessage(FOwnerForm.Handle, 'Reset every hotkey to its default? Unsaved changes in this tab will be lost.', MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  FBindings.ResetToDefaults;
  Populate;
end;

end.
