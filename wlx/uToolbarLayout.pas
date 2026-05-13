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
    Hint: string;
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
  CM_SHUFFLE = 12;
  {Save view variants: explicit "use these dimensions" entry points used
   by the toolbar / hamburger Save view dropdown. CM_SAVE_VIEW (above)
   uses the persisted SaveAtLiveResolution setting as the dialog's
   initial state; the two below seed the dialog with the named choice
   instead. The user can still flip the dialog checkbox on modern
   Windows; on legacy Windows (no checkbox) the seed is the final value.}
  CM_SAVE_VIEW_LIVE = 13;
  CM_SAVE_VIEW_NATIVE = 14;
  {Copy view variants: same dropdown idea as Save view, but with no
   dialog the user cannot revisit the choice mid-flight, so the named
   choice is the final resolution for that single Copy view (the
   persisted SaveAtLiveResolution setting is not touched).}
  CM_COPY_VIEW_LIVE = 15;
  CM_COPY_VIEW_NATIVE = 16;

  {Base captions for the Save/Copy view dropdown variants. Centralised
   so the toolbar dropdown, the hamburger overflow, and the runtime
   resolution-suffix updater all start from the same string.}
  CAPTION_SAVE_VIEW_LIVE = 'Save view at view resolution...';
  CAPTION_SAVE_VIEW_NATIVE = 'Save view at native size...';
  CAPTION_COPY_VIEW_LIVE = 'Copy view at view resolution';
  CAPTION_COPY_VIEW_NATIVE = 'Copy view at native size';

  {Toolbar buttons differentiate the two scroll modes via icons (see
   uPluginForm.CreateToolbar); both modes share the textual caption.}
  MODE_CAPTIONS: array [TViewMode] of string = ('Smart', 'Grid', 'Scroll', 'Scroll', 'Single');

  {Tooltip text per view mode. Disambiguates the two modes that share the
   "Scroll" caption (vmScroll = vertical, vmFilmstrip = horizontal).}
  MODE_HINTS: array [TViewMode] of string = (
    {vmSmartGrid}'Smart grid: auto-arranged grid sized to fit the viewport.',
    {vmGrid}'Grid: fixed-cell grid of frames.',
    {vmScroll}'Vertical scroll: full-width frames stacked top to bottom.',
    {vmFilmstrip}'Filmstrip: full-height frames laid out left to right.',
    {vmSingle}'Single frame: one frame at a time, navigate with arrow keys.');

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
  TB_ACTIONS: array [0 .. 6] of TToolbarActionDef = (
    (Caption: 'Save frame'; Tag: CM_SAVE_FRAME; Hint: 'Save the focused frame to a file.'),
    (Caption: 'Save frames'; Tag: CM_SAVE_FRAMES; Hint: 'Save the currently selected frames to files.'),
    (Caption: 'Save view'; Tag: CM_SAVE_VIEW; Hint: 'Save the entire viewer canvas as one image.'),
    (Caption: 'Copy frame'; Tag: CM_COPY_FRAME; Hint: 'Copy the focused frame to the clipboard.'),
    (Caption: 'Copy view'; Tag: CM_COPY_VIEW; Hint: 'Copy the entire viewer canvas to the clipboard.'),
    (Caption: 'Refresh'; Tag: CM_REFRESH; Hint: 'Re-extract frames at the current settings. Click the arrow for Shuffle.'),
    (Caption: 'Settings'; Tag: CM_SETTINGS; Hint: 'Open the plugin settings dialog.'));

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

    {Shuffle is the dropdown peer of Refresh on the toolbar; when
     Refresh collapses into the hamburger we inject Shuffle next to it
     so the action stays reachable for users who do not know the Ctrl+R
     hotkey. Caption mirrors the Refresh popup.}
    if TB_ACTIONS[I].Tag = CM_REFRESH then
    begin
      MI := TMenuItem.Create(AMenu);
      MI.Caption := 'Shuffle';
      MI.Tag := CM_SHUFFLE;
      MI.OnClick := AOnActionClick;
      MI.Enabled := AState.HasFrames;
      AMenu.Items.Add(MI);
    end;

    {Save view's two explicit-resolution variants are the dropdown peers
     of Save view; mirror the Refresh/Shuffle pattern so they stay
     reachable when Save view collapses into the hamburger. Captions
     match the toolbar dropdown.}
    if TB_ACTIONS[I].Tag = CM_SAVE_VIEW then
    begin
      MI := TMenuItem.Create(AMenu);
      MI.Caption := CAPTION_SAVE_VIEW_LIVE;
      MI.Tag := CM_SAVE_VIEW_LIVE;
      MI.OnClick := AOnActionClick;
      MI.Enabled := AState.HasFrames;
      AMenu.Items.Add(MI);

      MI := TMenuItem.Create(AMenu);
      MI.Caption := CAPTION_SAVE_VIEW_NATIVE;
      MI.Tag := CM_SAVE_VIEW_NATIVE;
      MI.OnClick := AOnActionClick;
      MI.Enabled := AState.HasFrames;
      AMenu.Items.Add(MI);
    end;

    {Copy view dropdown peers, mirroring Save view.}
    if TB_ACTIONS[I].Tag = CM_COPY_VIEW then
    begin
      MI := TMenuItem.Create(AMenu);
      MI.Caption := CAPTION_COPY_VIEW_LIVE;
      MI.Tag := CM_COPY_VIEW_LIVE;
      MI.OnClick := AOnActionClick;
      MI.Enabled := AState.HasFrames;
      AMenu.Items.Add(MI);

      MI := TMenuItem.Create(AMenu);
      MI.Caption := CAPTION_COPY_VIEW_NATIVE;
      MI.Tag := CM_COPY_VIEW_NATIVE;
      MI.OnClick := AOnActionClick;
      MI.Enabled := AState.HasFrames;
      AMenu.Items.Add(MI);
    end;
  end;
end;

end.
