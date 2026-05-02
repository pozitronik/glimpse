{Toolbar collapse logic: computes per-button visibility and populates the
 hamburger overflow menu. Pure functions, no VCL control ownership.}
unit uToolbarLayout;

interface

uses
  System.Classes, Vcl.Menus, uTypes;

type
  TToolbarLayoutResult = record
    VisibleCount: Integer; {elements 0..VisibleCount-1 are visible}
    HamburgerVisible: Boolean;
    HamburgerLeft: Integer; {meaningful only when HamburgerVisible}
  end;

  TToolbarActionDef = record
    Caption: string;
    Tag: Integer;
  end;

const
  {Command tags shared by toolbar buttons, context menu, and keyboard handler}
  CM_SAVE_FRAME = 1;
  CM_SAVE_FRAMES = 2;
  {Tags 3 and 4 were the historical CM_SAVE_ALL and CM_SAVE_COMBINED.
   They are intentionally left as gaps after the action consolidation
   into Save frame / Save frames / Save view.}
  CM_SAVE_VIEW = 11;
  CM_COPY_FRAME = 5;
  CM_COPY_VIEW = 6;
  CM_SELECT_ALL = 7;
  CM_DESELECT_ALL = 8;
  CM_SETTINGS = 9;
  CM_REFRESH = 10;

  {Toolbar buttons differentiate the two scroll modes via icons (see
   uPluginForm.CreateToolbar); both modes share the textual caption.}
  MODE_CAPTIONS: array [TViewMode] of string = ('Smart', 'Grid', 'Scroll', 'Scroll', 'Single');

  {Per-mode sizing submode labels}
  SIZING_LABELS: array [TViewMode, TZoomMode] of string = (
    {vmSmartGrid}('', '', ''),
    {vmGrid}('', '', ''),
    {vmScroll}('Fit width', 'Fit if larger', 'Original size'),
    {vmFilmstrip}('Fit height', 'Fit if larger', 'Original size'),
    {vmSingle}('Fit', 'Fit if larger', 'Original size'));

  {Toolbar action buttons.
   "Save frames" is selection-aware at runtime (the context menu
   updates its caption with the selected count); on the toolbar it
   keeps a stable caption.}
  TB_ACTIONS: array [0 .. 6] of TToolbarActionDef = ((Caption: 'Save frame'; Tag: CM_SAVE_FRAME), (Caption: 'Save frames'; Tag: CM_SAVE_FRAMES), (Caption: 'Save view'; Tag: CM_SAVE_VIEW), (Caption: 'Copy frame'; Tag: CM_COPY_FRAME), (Caption: 'Copy view'; Tag: CM_COPY_VIEW), (Caption: 'Refresh'; Tag: CM_REFRESH), (Caption: 'Settings'; Tag: CM_SETTINGS));

  {Element indices within the ordered collapsible element array.
   Order: mode buttons, timecodes toggle, action buttons (left to right).}
  ELEM_TIMECODE_INDEX = Ord(High(TViewMode)) + 1; {5}
  ELEM_ACTION_FIRST = ELEM_TIMECODE_INDEX + 1; {6}
  ELEM_TOTAL_COUNT = ELEM_ACTION_FIRST + Length(TB_ACTIONS); {13}

  {Determines which toolbar elements are visible given the current width.
   AElementRights contains the right pixel edge of each collapsible element
   (mode buttons, timecodes, action buttons) in left-to-right order.
   Elements collapse from right to left as the toolbar shrinks.}
function ComputeToolbarLayout(AToolbarWidth: Integer; const AElementRights: array of Integer; AFrameCountRight, AHamburgerWidth, ACtrlGap: Integer): TToolbarLayoutResult;

type
  {Snapshot of form state needed to populate the hamburger menu}
  THamburgerMenuState = record
    VisibleCount: Integer;
    ActiveMode: TViewMode;
    ModeZooms: array [TViewMode] of TZoomMode;
    ModeHasSubmenu: array [TViewMode] of Boolean;
    {Image-list slot for each mode's glyph; -1 = no glyph. Caller owns the
     image list and is expected to assign it to the menu before calling
     PopulateHamburgerMenu so MI.ImageIndex resolves correctly.}
    ModeImageIndex: array [TViewMode] of Integer;
    ShowTimecode: Boolean;
    HasFrames: Boolean;
  end;

  {Clears AMenu and rebuilds it with only the hidden elements.
   Event handlers are attached to the created menu items.}
procedure PopulateHamburgerMenu(AMenu: TPopupMenu; const AState: THamburgerMenuState; AOnModeClick, AOnZoomClick, AOnTimecodeClick, AOnActionClick: TNotifyEvent);

implementation

function ComputeToolbarLayout(AToolbarWidth: Integer; const AElementRights: array of Integer; AFrameCountRight, AHamburgerWidth, ACtrlGap: Integer): TToolbarLayoutResult;
var
  N, I: Integer;
begin
  N := Length(AElementRights);

  {Everything fits: no hamburger needed}
  if (N = 0) or (AToolbarWidth >= AElementRights[N - 1]) then
  begin
    Result.VisibleCount := N;
    Result.HamburgerVisible := False;
    Result.HamburgerLeft := 0;
    Exit;
  end;

  {Find the rightmost element that fits alongside the hamburger}
  Result.HamburgerVisible := True;
  for I := N - 1 downto 0 do
    if AElementRights[I] + ACtrlGap + AHamburgerWidth <= AToolbarWidth then
    begin
      Result.VisibleCount := I + 1;
      Result.HamburgerLeft := AElementRights[I] + ACtrlGap;
      Exit;
    end;

  {Nothing fits: hamburger at frame count position}
  Result.VisibleCount := 0;
  Result.HamburgerLeft := AFrameCountRight;
end;

procedure PopulateHamburgerMenu(AMenu: TPopupMenu; const AState: THamburgerMenuState; AOnModeClick, AOnZoomClick, AOnTimecodeClick, AOnActionClick: TNotifyEvent);
var
  VM: TViewMode;
  ZM: TZoomMode;
  MI, SubMI, Sep: TMenuItem;
  I: Integer;
  HasModeItems, AddedActions: Boolean;
begin
  AMenu.Items.Clear;
  HasModeItems := False;

  {Mode items: only those hidden (index >= VisibleCount)}
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    if Ord(VM) < AState.VisibleCount then
      Continue;

    MI := TMenuItem.Create(AMenu);
    MI.Caption := MODE_CAPTIONS[VM];
    MI.Tag := Ord(VM);
    MI.ImageIndex := AState.ModeImageIndex[VM];

    if AState.ActiveMode = VM then
      MI.Default := True;

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
    HasModeItems := True;
  end;

  {Timecodes: only if hidden}
  if ELEM_TIMECODE_INDEX >= AState.VisibleCount then
  begin
    if HasModeItems then
    begin
      Sep := TMenuItem.Create(AMenu);
      Sep.Caption := '-';
      AMenu.Items.Add(Sep);
    end;

    MI := TMenuItem.Create(AMenu);
    MI.Caption := 'Timecodes';
    MI.Checked := AState.ShowTimecode;
    MI.OnClick := AOnTimecodeClick;
    AMenu.Items.Add(MI);
  end;

  {Action items: only those hidden}
  AddedActions := False;
  for I := 0 to High(TB_ACTIONS) do
  begin
    if ELEM_ACTION_FIRST + I < AState.VisibleCount then
      Continue;

    {Separator before the first action item, only if preceded by other items}
    if (not AddedActions) and (AMenu.Items.Count > 0) then
    begin
      Sep := TMenuItem.Create(AMenu);
      Sep.Caption := '-';
      AMenu.Items.Add(Sep);
    end;
    AddedActions := True;

    MI := TMenuItem.Create(AMenu);
    MI.Caption := TB_ACTIONS[I].Caption;
    MI.Tag := TB_ACTIONS[I].Tag;
    MI.OnClick := AOnActionClick;
    case TB_ACTIONS[I].Tag of
      CM_SETTINGS:
        MI.Enabled := True;
      else
        MI.Enabled := AState.HasFrames;
    end;
    AMenu.Items.Add(MI);
  end;
end;

end.
