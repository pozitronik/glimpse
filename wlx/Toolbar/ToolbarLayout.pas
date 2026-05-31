{Toolbar collapse logic: computes per-button visibility and populates the
 hamburger overflow menu. Pure functions, no VCL control ownership.}
unit ToolbarLayout;

interface

uses
  System.Classes, Vcl.Menus, Types, Hotkeys;

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

  {Description of a Save/Copy view dropdown variant. The toolbar dropdown
   and hamburger overflow read from arrays of these so a future third
   variant lands in both surfaces from a single const-array edit.}
  TViewVariantDef = record
    Caption: string;
    Tag: Integer;
    {True = "at view resolution"; False = "at native size".}
    ForceLive: Boolean;
    {True = Copy variant (tracks CopyAtLiveResolution); False = Save.}
    IsCopy: Boolean;
    Action: TPluginAction;
  end;

const
  {Command tags shared by toolbar buttons, context menu, and keyboard handler}
  CM_SAVE_FRAME = 1;
  CM_SAVE_FRAMES = 2;
  {Tags 3 and 4 are intentionally left as gaps.}
  CM_SAVE_VIEW = 11;
  CM_COPY_FRAME = 5;
  CM_COPY_VIEW = 6;
  CM_SELECT_ALL = 7;
  CM_DESELECT_ALL = 8;
  CM_SETTINGS = 9;
  CM_REFRESH = 10;
  CM_SHUFFLE = 12;
  {Save view variants seed the dialog with the named choice instead of
   the persisted SaveAtLiveResolution setting.}
  CM_SAVE_VIEW_LIVE = 13;
  CM_SAVE_VIEW_NATIVE = 14;
  {Copy view variants are the final resolution (no dialog).}
  CM_COPY_VIEW_LIVE = 15;
  CM_COPY_VIEW_NATIVE = 16;
  {Selection commands: configurable hotkeys, also on the context menu.}
  CM_CLEAR_SELECTION = 17;
  CM_INVERT_SELECTION = 18;

  CAPTION_SAVE_VIEW_LIVE = 'Save view at view resolution...';
  CAPTION_SAVE_VIEW_NATIVE = 'Save view at native size...';
  CAPTION_COPY_VIEW_LIVE = 'Copy view at view resolution';
  CAPTION_COPY_VIEW_NATIVE = 'Copy view at native size';

  FRAME_COUNT_EDIT_W = 40;
  PROGRESSBAR_MIN_W = 40;

  IDX_ICON_HAMBURGER = 0;
  IDX_ICON_ARROW_W = 1; {Vertical arrow for vmScroll}
  IDX_ICON_ARROW_H = 2; {Horizontal arrow for vmFilmstrip}

  {Both Scroll modes share the textual caption; icons differentiate them.}
  MODE_CAPTIONS: array [TViewMode] of string = ('Smart', 'Grid', 'Scroll', 'Scroll', 'Single');

  {-1 = no glyph.}
  MODE_GLYPH_INDEX: array [TViewMode] of Integer = (
    {vmSmartGrid}-1,
    {vmGrid}-1,
    {vmScroll}IDX_ICON_ARROW_W,
    {vmFilmstrip}IDX_ICON_ARROW_H,
    {vmSingle}-1);

  MODE_HINTS: array [TViewMode] of string = (
    {vmSmartGrid}'Smart grid: auto-arranged grid sized to fit the viewport.',
    {vmGrid}'Grid: fixed-cell grid of frames.',
    {vmScroll}'Vertical scroll: full-width frames stacked top to bottom.',
    {vmFilmstrip}'Filmstrip: full-height frames laid out left to right.',
    {vmSingle}'Single frame: one frame at a time, navigate with arrow keys.');

  SIZING_LABELS: array [TViewMode, TZoomMode] of string = (
    {vmSmartGrid}('', '', ''),
    {vmGrid}('', '', ''),
    {vmScroll}('Fit width', 'Fit if larger', 'Original size'),
    {vmFilmstrip}('Fit height', 'Fit if larger', 'Original size'),
    {vmSingle}('Fit', 'Fit if larger', 'Original size'));

  {"Save frames" caption is stable on the toolbar; the context menu
   updates with the selected count at runtime.}
  TB_ACTIONS: array [0 .. 6] of TToolbarActionDef = (
    (Caption: 'Save frame'; Tag: CM_SAVE_FRAME; Hint: 'Save the focused frame to a file.'),
    (Caption: 'Save frames'; Tag: CM_SAVE_FRAMES; Hint: 'Save the currently selected frames to files.'),
    (Caption: 'Save view'; Tag: CM_SAVE_VIEW; Hint: 'Save the entire viewer canvas as one image.'),
    (Caption: 'Copy frame'; Tag: CM_COPY_FRAME; Hint: 'Copy the focused frame to the clipboard.'),
    (Caption: 'Copy view'; Tag: CM_COPY_VIEW; Hint: 'Copy the entire viewer canvas to the clipboard.'),
    (Caption: 'Refresh'; Tag: CM_REFRESH; Hint: 'Re-extract frames at the current settings. Click the arrow for Shuffle.'),
    (Caption: 'Settings'; Tag: CM_SETTINGS; Hint: 'Open the plugin settings dialog.'));

  {Order matches on-screen menu order.}
  SAVE_VIEW_VARIANTS: array[0..1] of TViewVariantDef = (
    (Caption: CAPTION_SAVE_VIEW_LIVE;   Tag: CM_SAVE_VIEW_LIVE;
     ForceLive: True;  IsCopy: False; Action: paSaveViewLive),
    (Caption: CAPTION_SAVE_VIEW_NATIVE; Tag: CM_SAVE_VIEW_NATIVE;
     ForceLive: False; IsCopy: False; Action: paSaveViewNative));

  COPY_VIEW_VARIANTS: array[0..1] of TViewVariantDef = (
    (Caption: CAPTION_COPY_VIEW_LIVE;   Tag: CM_COPY_VIEW_LIVE;
     ForceLive: True;  IsCopy: True;  Action: paCopyViewLive),
    (Caption: CAPTION_COPY_VIEW_NATIVE; Tag: CM_COPY_VIEW_NATIVE;
     ForceLive: False; IsCopy: True;  Action: paCopyViewNative));

  {Element order: mode buttons, timecodes, actions (left to right).}
  ELEM_TIMECODE_INDEX = Ord(High(TViewMode)) + 1; {5}
  ELEM_ACTION_FIRST = ELEM_TIMECODE_INDEX + 1; {6}
  ELEM_TOTAL_COUNT = ELEM_ACTION_FIRST + Length(TB_ACTIONS); {13}

{AElementRights = right pixel edge of each collapsible element, L-to-R.
 Elements collapse right-to-left as the toolbar shrinks.}
function ComputeToolbarLayout(AToolbarWidth: Integer; const AElementRights: array of Integer; AFrameCountRight, AHamburgerWidth, ACtrlGap: Integer): TToolbarLayoutResult;

type
  THamburgerMenuState = record
    VisibleCount: Integer;
    ActiveMode: TViewMode;
    ModeZooms: array [TViewMode] of TZoomMode;
    ModeHasSubmenu: array [TViewMode] of Boolean;
    {-1 = no glyph. Caller assigns the image list to the menu before calling.}
    ModeImageIndex: array [TViewMode] of Integer;
    ShowTimecode: Boolean;
    HasFrames: Boolean;
  end;

procedure PopulateHamburgerMenu(AMenu: TPopupMenu; const AState: THamburgerMenuState; AOnModeClick, AOnZoomClick, AOnTimecodeClick, AOnActionClick: TNotifyEvent);

{Reads only Caption + Tag from AItems. Returned menu is owned by AOwner.}
function BuildViewVariantsMenu(AOwner: TComponent; const AItems: array of TViewVariantDef; AOnPopup, AOnClick: TNotifyEvent): TPopupMenu;

function FindViewVariantByTag(ATag: Integer; out ADef: TViewVariantDef): Boolean;

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
  I, V: Integer;
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

    {Inject Shuffle next to Refresh in the overflow — Refresh's dropdown peer.}
    if TB_ACTIONS[I].Tag = CM_REFRESH then
    begin
      MI := TMenuItem.Create(AMenu);
      MI.Caption := 'Shuffle';
      MI.Tag := CM_SHUFFLE;
      MI.OnClick := AOnActionClick;
      MI.Enabled := AState.HasFrames;
      AMenu.Items.Add(MI);
    end;

    {Inject Save view's variants alongside it in the overflow, from the
     shared SAVE_VIEW_VARIANTS array so a new variant needs no edit here.}
    if TB_ACTIONS[I].Tag = CM_SAVE_VIEW then
      for V := 0 to High(SAVE_VIEW_VARIANTS) do
      begin
        MI := TMenuItem.Create(AMenu);
        MI.Caption := SAVE_VIEW_VARIANTS[V].Caption;
        MI.Tag := SAVE_VIEW_VARIANTS[V].Tag;
        MI.OnClick := AOnActionClick;
        MI.Enabled := AState.HasFrames;
        AMenu.Items.Add(MI);
      end;

    {Inject Copy view's variants, mirroring Save view, from COPY_VIEW_VARIANTS.}
    if TB_ACTIONS[I].Tag = CM_COPY_VIEW then
      for V := 0 to High(COPY_VIEW_VARIANTS) do
      begin
        MI := TMenuItem.Create(AMenu);
        MI.Caption := COPY_VIEW_VARIANTS[V].Caption;
        MI.Tag := COPY_VIEW_VARIANTS[V].Tag;
        MI.OnClick := AOnActionClick;
        MI.Enabled := AState.HasFrames;
        AMenu.Items.Add(MI);
      end;
  end;
end;

function BuildViewVariantsMenu(AOwner: TComponent; const AItems: array of TViewVariantDef; AOnPopup, AOnClick: TNotifyEvent): TPopupMenu;
var
  I: Integer;
  MI: TMenuItem;
begin
  Result := TPopupMenu.Create(AOwner);
  Result.OnPopup := AOnPopup;
  for I := 0 to High(AItems) do
  begin
    MI := TMenuItem.Create(Result);
    MI.Caption := AItems[I].Caption;
    MI.Tag := AItems[I].Tag;
    MI.OnClick := AOnClick;
    Result.Items.Add(MI);
  end;
end;

function FindViewVariantByTag(ATag: Integer; out ADef: TViewVariantDef): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(SAVE_VIEW_VARIANTS) do
    if SAVE_VIEW_VARIANTS[I].Tag = ATag then
    begin
      ADef := SAVE_VIEW_VARIANTS[I];
      Exit(True);
    end;
  for I := 0 to High(COPY_VIEW_VARIANTS) do
    if COPY_VIEW_VARIANTS[I].Tag = ATag then
    begin
      ADef := COPY_VIEW_VARIANTS[I];
      Exit(True);
    end;
  Result := False;
end;

end.
