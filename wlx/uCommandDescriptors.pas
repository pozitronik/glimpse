{TCommandDescriptor table types for the WLX plugin form. Pairs each
 CM_* tag with its hotkey action, enable policy, and executor closure
 so DispatchCommand / OnContextMenuPopup / UpdateToolbarButtons /
 ExecuteHotkey all read from one table.}
unit uCommandDescriptors;

interface

uses
  System.SysUtils, uHotkeys;

type
  TCommandEnabledPolicy = (
    epAlways,
    {Save / Copy: requires a stable non-empty loaded set.}
    epRequiresExtract,
    {Refresh / SelectAll: at least one cell (placeholders OK). Refresh stays
     clickable during extraction so the user can cancel and restart.}
    epRequiresLoadedCell,
    {DeselectAll: SelectedCount > 0.}
    epRequiresSelection);

  TCommandDescriptor = record
    Tag: Cardinal;
    ActionEnum: TPluginAction;
    EnabledPolicy: TCommandEnabledPolicy;
    Executor: TProc;
  end;

  TCommandTable = TArray<TCommandDescriptor>;

function FindCommandByTag(const ATable: TCommandTable; ATag: Cardinal; out ADescriptor: TCommandDescriptor): Boolean;

function FindCommandByAction(const ATable: TCommandTable; AAction: TPluginAction; out ADescriptor: TCommandDescriptor): Boolean;

implementation

function FindCommandByTag(const ATable: TCommandTable; ATag: Cardinal; out ADescriptor: TCommandDescriptor): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(ATable) do
    if ATable[I].Tag = ATag then
    begin
      ADescriptor := ATable[I];
      Exit(True);
    end;
  ADescriptor := Default(TCommandDescriptor);
  Result := False;
end;

function FindCommandByAction(const ATable: TCommandTable; AAction: TPluginAction; out ADescriptor: TCommandDescriptor): Boolean;
var
  I: Integer;
begin
  {paNone matches descriptors that have no configurable hotkey (DeselectAll);
   returning False here keeps ExecuteHotkey from dispatching them when
   THotkeyBindings.Lookup returns paNone for an unbound keystroke.}
  ADescriptor := Default(TCommandDescriptor);
  if AAction = paNone then
    Exit(False);
  for I := 0 to High(ATable) do
    if ATable[I].ActionEnum = AAction then
    begin
      ADescriptor := ATable[I];
      Exit(True);
    end;
  Result := False;
end;

end.
