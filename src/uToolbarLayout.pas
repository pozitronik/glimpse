{ Toolbar collapse logic: computes layout thresholds and populates the
  hamburger overflow menu. Pure functions, no VCL control ownership. }
unit uToolbarLayout;

interface

uses
  System.Classes, Vcl.Menus, uSettings;

type
  TToolbarCollapseState = (tcsExpanded, tcsActionsCollapsed, tcsAllCollapsed);

  TToolbarLayoutResult = record
    CollapseState: TToolbarCollapseState;
    HamburgerLeft: Integer;
    ProgressLeft: Integer;
  end;

  TToolbarActionDef = record
    Caption: string;
    Tag: Integer;
  end;

const
  { Command tags shared by toolbar buttons, context menu, and keyboard handler }
  CM_SAVE_FRAME    = 1;
  CM_SAVE_SELECTED = 2;
  CM_SAVE_ALL      = 3;
  CM_SAVE_COMBINED = 4;
  CM_COPY_FRAME    = 5;
  CM_COPY_ALL      = 6;
  CM_SELECT_ALL    = 7;
  CM_DESELECT_ALL  = 8;
  CM_SETTINGS      = 9;
  CM_REFRESH       = 10;

  MODE_CAPTIONS: array[TViewMode] of string = (
    'Smart', 'Grid', 'Scroll '#$2195, 'Scroll '#$2194, 'Single'
  );

  { Per-mode sizing submode labels }
  SIZING_LABELS: array[TViewMode, TZoomMode] of string = (
    { vmSmartGrid } ('', '', ''),
    { vmGrid }      ('', '', ''),
    { vmScroll }    ('Fit width',  'Fit if larger', 'Original size'),
    { vmFilmstrip } ('Fit height', 'Fit if larger', 'Original size'),
    { vmSingle }    ('Fit',        'Fit if larger', 'Original size')
  );

  { Toolbar action buttons (excluding selection-dependent commands) }
  TB_ACTIONS: array[0..6] of TToolbarActionDef = (
    (Caption: 'Save';     Tag: CM_SAVE_FRAME),
    (Caption: 'Save All'; Tag: CM_SAVE_ALL),
    (Caption: 'Combined'; Tag: CM_SAVE_COMBINED),
    (Caption: 'Copy';     Tag: CM_COPY_FRAME),
    (Caption: 'Copy All'; Tag: CM_COPY_ALL),
    (Caption: 'Refresh';  Tag: CM_REFRESH),
    (Caption: 'Settings'; Tag: CM_SETTINGS)
  );

{ Returns collapse state and positions given toolbar width and group boundaries.
  ACtrlGap is the gap between the hamburger button and the next element. }
function ComputeToolbarLayout(AToolbarWidth, AFrameCountRight, AModeGroupRight,
  AActionsRight, AHamburgerWidth, ACtrlGap: Integer): TToolbarLayoutResult;

type
  { Snapshot of form state needed to populate the hamburger menu }
  THamburgerMenuState = record
    CollapseState: TToolbarCollapseState;
    ActiveMode: TViewMode;
    ModeZooms: array[TViewMode] of TZoomMode;
    ModeHasSubmenu: array[TViewMode] of Boolean;
    ShowTimecode: Boolean;
    HasFrames: Boolean;
  end;

{ Clears AMenu and rebuilds it from the given state.
  Event handlers are attached to the created menu items. }
procedure PopulateHamburgerMenu(AMenu: TPopupMenu;
  const AState: THamburgerMenuState;
  AOnModeClick, AOnZoomClick, AOnTimecodeClick, AOnActionClick: TNotifyEvent);

implementation

function ComputeToolbarLayout(AToolbarWidth, AFrameCountRight, AModeGroupRight,
  AActionsRight, AHamburgerWidth, ACtrlGap: Integer): TToolbarLayoutResult;
var
  CollapseActions, CollapseModes: Boolean;
  X: Integer;
begin
  CollapseActions := AToolbarWidth < AActionsRight;
  CollapseModes := CollapseActions and
    (AToolbarWidth < AModeGroupRight + AHamburgerWidth + ACtrlGap);

  if not CollapseActions then
    Result.CollapseState := tcsExpanded
  else if not CollapseModes then
    Result.CollapseState := tcsActionsCollapsed
  else
    Result.CollapseState := tcsAllCollapsed;

  if CollapseActions then
  begin
    if CollapseModes then
      X := AFrameCountRight
    else
      X := AModeGroupRight;
    Result.HamburgerLeft := X;
    Result.ProgressLeft := X + AHamburgerWidth + ACtrlGap;
  end
  else
  begin
    Result.HamburgerLeft := 0;
    Result.ProgressLeft := AActionsRight;
  end;
end;

procedure PopulateHamburgerMenu(AMenu: TPopupMenu;
  const AState: THamburgerMenuState;
  AOnModeClick, AOnZoomClick, AOnTimecodeClick, AOnActionClick: TNotifyEvent);
var
  VM: TViewMode;
  ZM: TZoomMode;
  MI, SubMI, Sep: TMenuItem;
  I: Integer;
begin
  AMenu.Items.Clear;

  { Mode items: only when mode buttons are collapsed }
  if AState.CollapseState = tcsAllCollapsed then
  begin
    for VM := Low(TViewMode) to High(TViewMode) do
    begin
      MI := TMenuItem.Create(AMenu);
      MI.Caption := MODE_CAPTIONS[VM];
      MI.Tag := Ord(VM);

      if AState.ActiveMode = VM then
        MI.Default := True;

      { Modes with zoom submodes get a submenu }
      if AState.ModeHasSubmenu[VM] then
      begin
        for ZM := Low(TZoomMode) to High(TZoomMode) do
        begin
          SubMI := TMenuItem.Create(MI);
          SubMI.Caption := SIZING_LABELS[VM, ZM];
          SubMI.Tag := Ord(VM) shl 8 or Ord(ZM);
          SubMI.RadioItem := True;
          SubMI.Checked := AState.ModeZooms[VM] = ZM;
          SubMI.OnClick := AOnZoomClick;
          MI.Add(SubMI);
        end;
      end
      else
        MI.OnClick := AOnModeClick;

      AMenu.Items.Add(MI);
    end;

    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Items.Add(Sep);
  end;

  { Timecodes toggle }
  MI := TMenuItem.Create(AMenu);
  MI.Caption := 'Timecodes';
  MI.Checked := AState.ShowTimecode;
  MI.OnClick := AOnTimecodeClick;
  AMenu.Items.Add(MI);

  Sep := TMenuItem.Create(AMenu);
  Sep.Caption := '-';
  AMenu.Items.Add(Sep);

  { Action items }
  for I := 0 to High(TB_ACTIONS) do
  begin
    MI := TMenuItem.Create(AMenu);
    MI.Caption := TB_ACTIONS[I].Caption;
    MI.Tag := TB_ACTIONS[I].Tag;
    MI.OnClick := AOnActionClick;
    case TB_ACTIONS[I].Tag of
      CM_SETTINGS: MI.Enabled := True;
    else
      MI.Enabled := AState.HasFrames;
    end;
    AMenu.Items.Add(MI);
  end;
end;

end.
