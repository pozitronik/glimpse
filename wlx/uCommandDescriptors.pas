{TCommandDescriptor table types for the WLX plugin form.

 Collapses four parallel CM_* case ladders (DispatchCommand,
 OnContextMenuPopup, UpdateToolbarButtons, ExecuteHotkey's Save/Copy
 block) into one data-driven table. Each command has exactly one
 descriptor row pinning its Tag (CM_*), the matching TPluginAction
 enum value for hotkey lookup, its enable policy, and the executor
 closure that performs the work.

 Adding a new command becomes a one-place edit (push one descriptor
 onto the table) instead of four (one per ladder).

 The descriptor record + lookup helpers + policy enum live here; the
 table itself + the executor closures are built in uPluginForm where
 they need access to the form's private collaborators.}
unit uCommandDescriptors;

interface

uses
  System.SysUtils, uHotkeys;

type
  {Enable-state policy: a small enum so DispatchCommand,
   UpdateToolbarButtons, and OnContextMenuPopup can all derive a
   command's Enabled state from the same rule set without duplicating
   the underlying CanExportFrames / HasLoadedCells / SelectedCount
   checks.}
  TCommandEnabledPolicy = (
    epAlways,
    {Save / Copy commands. Gated on CanExportFrames (loaded set is
     stable and non-empty). Mid-extraction the button is visually
     disabled to surface why the action would no-op.}
    epRequiresExtract,
    {Refresh / SelectAll. Gated on HasLoadedCells (at least one cell,
     placeholders OK). Refresh stays clickable during extraction so
     the user can cancel and restart with new settings.}
    epRequiresLoadedCell,
    {DeselectAll. Gated on SelectedCount > 0. The only command with
     this policy today, but the enum value makes the rule explicit.}
    epRequiresSelection);

  {Single descriptor row. Executor captures whatever form state the
   command needs (FExporter, FFrameView, FFileName, FContextCellIndex,
   etc.); a bare TProc keeps the table type uniform regardless of how
   wide an individual command's closure capture is.}
  TCommandDescriptor = record
    Tag: Cardinal;
    ActionEnum: TPluginAction;
    EnabledPolicy: TCommandEnabledPolicy;
    Executor: TProc;
  end;

  TCommandTable = TArray<TCommandDescriptor>;

{Linear scan for the descriptor with ATag. Returns False (with
 ADescriptor zero-initialised) when no match. The table is small
 enough (≤14 entries) that the scan cost is negligible.}
function FindCommandByTag(const ATable: TCommandTable; ATag: Cardinal; out ADescriptor: TCommandDescriptor): Boolean;

{Linear scan for the descriptor whose ActionEnum matches AAction.
 Returns False when no match. Used by ExecuteHotkey to map a
 configurable TPluginAction back to its command-table entry.}
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
  {paNone is the "unassigned hotkey" sentinel. Descriptors that legitimately
   have no configurable hotkey (DeselectAll today) keep ActionEnum=paNone so
   the table stays homogeneous. Returning False on a paNone lookup keeps
   ExecuteHotkey from accidentally dispatching one of those descriptors when
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
