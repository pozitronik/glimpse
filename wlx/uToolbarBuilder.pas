{Toolbar construction extracted from TPluginForm.CreateToolbar.

 The builder takes a parent panel host (the form whose Canvas measures
 captions and whose lifetime owns the resulting controls) plus the
 glyph library that supplies the shared TImageList. Click handlers
 (mode button click, timecode toggle, generic action, sizing menu,
 hamburger button, hamburger popup, context-menu click, view dropdown
 popup) come in as TNotifyEvent constructor parameters so the form's
 private handlers stay private — the builder never sees the form's
 internals beyond Canvas + ownership.

 Returns a TToolbarHandles record bundling every TControl the form
 needs to keep referencing; the form's CreateToolbar wrapper copies
 each Handles field into its own private field. This keeps the form's
 existing consumer sites (UpdateToolbarButtons, LayoutToolbar, etc.)
 unchanged after the extraction.

 The legacy-Windows split-button tweak (BS_SPLITBUTTON does not render
 on XP/2003, the spare dropdown-arrow width would leave a dead gap)
 is consulted in two places: the mode buttons' SPLIT_ARROW_W reservation
 and the action buttons' REFRESH/SAVE/COPY_DROPDOWN_EXTRA reservation.

 Width calculations use AForm.Canvas.TextWidth — caller's responsibility
 to call Build only after the form has a valid Canvas (i.e. after
 HandleNeeded equivalent has run, which is the case from CreateToolbar).}
unit uToolbarBuilder;

interface

uses
  System.Classes,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Buttons,
  Vcl.ComCtrls, Vcl.Forms,
  uTypes,
  uToolbarGlyphLibrary;

type
  {Bundle of every TControl produced by Build. The form's
   CreateToolbar wrapper assigns each field into its same-named
   private member so the rest of the form (UpdateToolbarButtons,
   LayoutToolbar, OnHamburgerMenuPopup, ...) keeps reading from
   FToolbar / FEditFrameCount / etc. without further changes.

   ElementRights / FrameCountRight feed LayoutToolbar's collapse
   calculation. ModePopups / RefreshPopup / SaveViewPopup /
   CopyViewPopup carry the dropdown menus that the form's
   UpdateResolutionMenuLabels and OnHamburgerMenuPopup share with
   the toolbar surface.}
  TToolbarHandles = record
    Toolbar: TPanel;
    EditFrameCount: TEdit;
    UpDown: TUpDown;
    LblFrames: TLabel;
    ModeButtons: array[TViewMode] of TButton;
    ModePopups: array[TViewMode] of TPopupMenu;
    BtnTimecode: TSpeedButton;
    ToolbarButtons: TArray<TButton>;
    RefreshPopup: TPopupMenu;
    SaveViewPopup: TPopupMenu;
    CopyViewPopup: TPopupMenu;
    BtnHamburger: TButton;
    HamburgerMenu: TPopupMenu;
    ElementRights: TArray<Integer>;
    FrameCountRight: Integer;
  end;

  TToolbarBuilder = class
  strict private
    FForm: TForm;
    FGlyphs: TToolbarGlyphLibrary;
    {Click handlers wired into the toolbar controls. All point at
     methods on the form; held as TNotifyEvent so the builder does
     not need to know the form's concrete type beyond TForm.}
    FOnModeButtonClick: TNotifyEvent;
    FOnSizingMenuClick: TNotifyEvent;
    FOnTimecodeButtonClick: TNotifyEvent;
    FOnToolbarButtonClick: TNotifyEvent;
    FOnContextMenuClick: TNotifyEvent;
    FOnViewDropdownPopup: TNotifyEvent;
    FOnHamburgerClick: TNotifyEvent;
    FOnHamburgerMenuPopup: TNotifyEvent;
    function CreateModePopup(AMode: TViewMode): TPopupMenu;
    function CreateRefreshPopup: TPopupMenu;
    function CreateSaveViewPopup: TPopupMenu;
    function CreateCopyViewPopup: TPopupMenu;
  public
    constructor Create(AForm: TForm; AGlyphs: TToolbarGlyphLibrary;
      AOnModeButtonClick, AOnSizingMenuClick, AOnTimecodeButtonClick,
      AOnToolbarButtonClick, AOnContextMenuClick, AOnViewDropdownPopup,
      AOnHamburgerClick, AOnHamburgerMenuPopup: TNotifyEvent);
    function Build: TToolbarHandles;
  end;

implementation

uses
  Vcl.Graphics,
  uPlatformDetect, uToolbarLayout;

const
  MAX_FRAME_COUNT = 99; {upper limit for the frame-count spin edit}

constructor TToolbarBuilder.Create(AForm: TForm; AGlyphs: TToolbarGlyphLibrary;
  AOnModeButtonClick, AOnSizingMenuClick, AOnTimecodeButtonClick,
  AOnToolbarButtonClick, AOnContextMenuClick, AOnViewDropdownPopup,
  AOnHamburgerClick, AOnHamburgerMenuPopup: TNotifyEvent);
begin
  inherited Create;
  FForm := AForm;
  FGlyphs := AGlyphs;
  FOnModeButtonClick := AOnModeButtonClick;
  FOnSizingMenuClick := AOnSizingMenuClick;
  FOnTimecodeButtonClick := AOnTimecodeButtonClick;
  FOnToolbarButtonClick := AOnToolbarButtonClick;
  FOnContextMenuClick := AOnContextMenuClick;
  FOnViewDropdownPopup := AOnViewDropdownPopup;
  FOnHamburgerClick := AOnHamburgerClick;
  FOnHamburgerMenuPopup := AOnHamburgerMenuPopup;
end;

function TToolbarBuilder.CreateModePopup(AMode: TViewMode): TPopupMenu;
var
  ZM: TZoomMode;
  MI: TMenuItem;
begin
  {Grid modes always fit all frames to the available space}
  if AMode in [vmSmartGrid, vmGrid] then
    Exit(nil);

  Result := TPopupMenu.Create(FForm);
  for ZM := Low(TZoomMode) to High(TZoomMode) do
  begin
    MI := TMenuItem.Create(Result);
    MI.Caption := SIZING_LABELS[AMode, ZM];
    MI.Tag := Ord(ZM);
    MI.RadioItem := True;
    MI.Checked := ZM = zmFitWindow;
    MI.OnClick := FOnSizingMenuClick;
    Result.Items.Add(MI);
  end;
end;

function TToolbarBuilder.CreateRefreshPopup: TPopupMenu;
var
  MI: TMenuItem;
begin
  Result := TPopupMenu.Create(FForm);

  MI := TMenuItem.Create(Result);
  MI.Caption := 'Refresh'#9'R';
  MI.Tag := CM_REFRESH;
  MI.OnClick := FOnContextMenuClick;
  Result.Items.Add(MI);

  MI := TMenuItem.Create(Result);
  MI.Caption := 'Shuffle'#9'Ctrl+R';
  MI.Tag := CM_SHUFFLE;
  MI.OnClick := FOnContextMenuClick;
  Result.Items.Add(MI);
end;

function TToolbarBuilder.CreateSaveViewPopup: TPopupMenu;
begin
  {Two explicit-resolution Save view variants. Their job is mainly to
   give legacy Windows users a way to pick the resolution at all (the
   modern file dialog's checkbox is unavailable on XP), but they also
   work as a faster path on modern Windows: one click chooses the
   resolution and opens the dialog with that as the seed. The item set
   lives in uToolbarLayout.SAVE_VIEW_VARIANTS so the hamburger overflow
   and the resolution-suffix updater stay in lockstep with this menu.}
  Result := BuildViewVariantsMenu(FForm, SAVE_VIEW_VARIANTS,
    FOnViewDropdownPopup, FOnContextMenuClick);
end;

function TToolbarBuilder.CreateCopyViewPopup: TPopupMenu;
begin
  {Mirror of CreateSaveViewPopup. No dialog follows so the COPY captions
   omit the trailing ellipsis - the action commits immediately.}
  Result := BuildViewVariantsMenu(FForm, COPY_VIEW_VARIANTS,
    FOnViewDropdownPopup, FOnContextMenuClick);
end;

function TToolbarBuilder.Build: TToolbarHandles;
const
  TB_PAD = 4; {Vertical padding above and below controls}
  CTRL_GAP = 8; {Gap between control groups}
  BTN_GAP = 2; {Gap between adjacent buttons in a group}
  BTN_PAD = 16; {Horizontal text padding inside button (both sides)}
  {Extra horizontal width reserved for the dropdown arrow on the
   Refresh split button. The view-mode buttons use the same allowance
   by virtue of the IDX_ICON_ARROW glyph; Refresh has no glyph so the
   space is added explicitly to match the visual weight.}
  REFRESH_DROPDOWN_EXTRA = 14;
  {Save view / Copy view captions are longer than Refresh, so the
   bsSplitButton arrow pinches the rendered text when only
   REFRESH_DROPDOWN_EXTRA is reserved. Add a small buffer on top so the
   full caption stays visible.}
  VIEW_DROPDOWN_EXTRA = REFRESH_DROPDOWN_EXTRA + 6;
  SPLIT_ARROW_W = 20; {Extra width for split button dropdown arrow}
  ICON_W = 16; {Toolbar icon width}
  ICON_GAP = 4; {Space between icon and caption on icon-bearing buttons}
var
  X, CY, CtrlH, BW, I: Integer;
  VM: TViewMode;
  TabIdx: Integer;
  Btn: TButton;
begin
  Result.Toolbar := TPanel.Create(FForm);
  Result.Toolbar.Parent := FForm;
  Result.Toolbar.Align := alTop;
  Result.Toolbar.BevelOuter := bvNone;
  Result.Toolbar.ParentBackground := False;

  {Create edit first: its auto-sized height is the reference for all controls}
  Result.EditFrameCount := TEdit.Create(Result.Toolbar);
  Result.EditFrameCount.Parent := Result.Toolbar;
  Result.EditFrameCount.Width := FRAME_COUNT_EDIT_W;
  Result.EditFrameCount.NumbersOnly := True;
  Result.EditFrameCount.TabOrder := 0;
  CtrlH := Result.EditFrameCount.Height;

  Result.Toolbar.Height := CtrlH + 2 * TB_PAD;
  CY := TB_PAD;
  X := CTRL_GAP;

  Result.LblFrames := TLabel.Create(Result.Toolbar);
  Result.LblFrames.Parent := Result.Toolbar;
  Result.LblFrames.Caption := 'Frames:';
  Result.LblFrames.AutoSize := True;
  Result.LblFrames.Left := X;
  Result.LblFrames.Top := CY + (CtrlH - Result.LblFrames.Height) div 2;
  Inc(X, Result.LblFrames.Width + 4);

  Result.EditFrameCount.SetBounds(X, CY, FRAME_COUNT_EDIT_W, CtrlH);
  Result.EditFrameCount.Hint := 'Number of frames to extract from the video.';

  Result.UpDown := TUpDown.Create(Result.Toolbar);
  Result.UpDown.Parent := Result.Toolbar;
  Result.UpDown.Associate := Result.EditFrameCount;
  Result.UpDown.Min := 1;
  Result.UpDown.Max := MAX_FRAME_COUNT;
  Result.UpDown.Hint := 'Number of frames to extract from the video.';
  Inc(X, FRAME_COUNT_EDIT_W + Result.UpDown.Width + CTRL_GAP);
  Result.FrameCountRight := X;

  {Collapsible elements: modes, timecodes, actions (left to right)}
  SetLength(Result.ElementRights, ELEM_TOTAL_COUNT);

  {Create 5 mode buttons}
  TabIdx := 1;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    {Create popup menu first (needed for DropDownMenu assignment)}
    Result.ModePopups[VM] := CreateModePopup(VM);

    Result.ModeButtons[VM] := TButton.Create(Result.Toolbar);
    Result.ModeButtons[VM].Parent := Result.Toolbar;

    {Auto-width: measure caption text and add padding. Scroll/Filmstrip
     also reserve space for a directional arrow icon to the left of the
     caption. The split-arrow reservation is skipped on legacy Windows
     (XP/2003) because BS_SPLITBUTTON does not render there — keeping
     the extra width would leave a dead gap between the caption and the
     iaRight icon.}
    BW := FForm.Canvas.TextWidth(MODE_CAPTIONS[VM]) + BTN_PAD;
    if (Result.ModePopups[VM] <> nil) and not IsLegacyWindows then
      Inc(BW, SPLIT_ARROW_W);
    if VM in [vmScroll, vmFilmstrip] then
      Inc(BW, ICON_W + ICON_GAP);

    Result.ModeButtons[VM].SetBounds(X, CY, BW, CtrlH);
    Result.ModeButtons[VM].Caption := MODE_CAPTIONS[VM];
    Result.ModeButtons[VM].Hint := MODE_HINTS[VM];
    Result.ModeButtons[VM].Tag := Ord(VM);
    Result.ModeButtons[VM].TabOrder := TabIdx;
    Result.ModeButtons[VM].OnClick := FOnModeButtonClick;

    if MODE_GLYPH_INDEX[VM] >= 0 then
    begin
      Result.ModeButtons[VM].Images := FGlyphs.Images;
      Result.ModeButtons[VM].ImageIndex := MODE_GLYPH_INDEX[VM];
      {Qualified — TIconArrangement (Vcl.ComCtrls) also defines iaRight.
       Icon sits to the right of the caption, matching the original
       arrow-glyph position.}
      Result.ModeButtons[VM].ImageAlignment := Vcl.StdCtrls.iaRight;
    end;

    {Legacy Windows pulls the iaRight icon flush against the button's
     right edge; modern Windows leaves a small visual margin courtesy of
     the themed button paint. Add the missing inset manually on XP so the
     glyph doesn't touch the border.}
    if (VM in [vmScroll, vmFilmstrip]) and IsLegacyWindows then
      Result.ModeButtons[VM].ImageMargins.Right := 2;

    {Split button: click activates mode, arrow shows submodes. PopupMenu
     duplicates the same menu on right-click for every OS so the submodes
     stay reachable on legacy Windows (where the split arrow does not
     render) and gives modern users a discoverable alternative to the
     small arrow glyph.}
    if Result.ModePopups[VM] <> nil then
    begin
      Result.ModeButtons[VM].Style := bsSplitButton;
      Result.ModeButtons[VM].DropDownMenu := Result.ModePopups[VM];
      Result.ModeButtons[VM].PopupMenu := Result.ModePopups[VM];
    end;

    Result.ElementRights[Ord(VM)] := X + BW;
    Inc(TabIdx);
    if VM < High(TViewMode) then
      Inc(X, BW + BTN_GAP)
    else
      Inc(X, BW + CTRL_GAP);
  end;

  Result.BtnTimecode := TSpeedButton.Create(Result.Toolbar);
  Result.BtnTimecode.Parent := Result.Toolbar;
  BW := FForm.Canvas.TextWidth('Timecodes') + BTN_PAD;
  Result.BtnTimecode.SetBounds(X, CY, BW, CtrlH);
  Result.BtnTimecode.Caption := 'Timecodes';
  Result.BtnTimecode.Hint := 'Toggle timecode overlay on each frame (F2).';
  Result.BtnTimecode.GroupIndex := 1;
  Result.BtnTimecode.AllowAllUp := True;
  Result.BtnTimecode.OnClick := FOnTimecodeButtonClick;
  Result.ElementRights[ELEM_TIMECODE_INDEX] := X + BW;
  Inc(X, BW + CTRL_GAP);

  {Action buttons matching context menu (except selection-dependent commands).
   The Refresh button is upgraded to a split button so the dropdown
   exposes Shuffle as a peer action (primary click stays Refresh).}
  SetLength(Result.ToolbarButtons, 0);
  Result.RefreshPopup := nil;
  Result.SaveViewPopup := nil;
  Result.CopyViewPopup := nil;
  for I := 0 to High(TB_ACTIONS) do
  begin
    Btn := TButton.Create(Result.Toolbar);
    Btn.Parent := Result.Toolbar;
    BW := FForm.Canvas.TextWidth(TB_ACTIONS[I].Caption) + BTN_PAD;
    {Skip the dropdown-arrow reservation on legacy Windows for the same
     reason as the mode buttons above: BS_SPLITBUTTON does not render on
     XP/2003 and the spare width would leave a dead gap.}
    if not IsLegacyWindows then
      case TB_ACTIONS[I].Tag of
        CM_REFRESH:
          Inc(BW, REFRESH_DROPDOWN_EXTRA);
        CM_SAVE_VIEW, CM_COPY_VIEW:
          Inc(BW, VIEW_DROPDOWN_EXTRA);
      end;
    Btn.SetBounds(X, CY, BW, CtrlH);
    Btn.Caption := TB_ACTIONS[I].Caption;
    Btn.Hint := TB_ACTIONS[I].Hint;
    Btn.Tag := TB_ACTIONS[I].Tag;
    Btn.Enabled := False;
    Btn.OnClick := FOnToolbarButtonClick;
    if TB_ACTIONS[I].Tag = CM_REFRESH then
    begin
      Result.RefreshPopup := CreateRefreshPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := Result.RefreshPopup;
      {Right-click pops the same Refresh / Shuffle menu — see the mode
       buttons above for why this duplicates DropDownMenu.}
      Btn.PopupMenu := Result.RefreshPopup;
    end
    else if TB_ACTIONS[I].Tag = CM_SAVE_VIEW then
    begin
      {Save view dropdown: explicit "...at view resolution" and "...at
       native size" entry points. On modern Windows the file dialog's
       checkbox is still authoritative; on legacy Windows (no checkbox)
       this is the only way to pick the resolution per save without
       opening the settings dialog first.}
      Result.SaveViewPopup := CreateSaveViewPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := Result.SaveViewPopup;
      Btn.PopupMenu := Result.SaveViewPopup;
    end
    else if TB_ACTIONS[I].Tag = CM_COPY_VIEW then
    begin
      {Copy view dropdown: same idea as Save view but commits immediately
       (no dialog), so the variants are the only way to override the
       persisted SaveAtLiveResolution setting for a single Copy view.
       The native variant also re-extracts at native resolution before
       publishing to the clipboard, which the default Copy view used to
       skip - the dropdown thus also fixes the long-standing "Copy view
       at native resolution copies low-res cells" surprise.}
      Result.CopyViewPopup := CreateCopyViewPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := Result.CopyViewPopup;
      Btn.PopupMenu := Result.CopyViewPopup;
    end;
    Result.ElementRights[ELEM_ACTION_FIRST + I] := X + BW;
    Inc(X, BW + BTN_GAP);
    SetLength(Result.ToolbarButtons, Length(Result.ToolbarButtons) + 1);
    Result.ToolbarButtons[High(Result.ToolbarButtons)] := Btn;
  end;

  {Hamburger overflow button: hidden until toolbar is too narrow. Glyph
   comes from the shared glyph library (loaded with the mode-button arrow
   icons) so the toolbar does not depend on the runtime font's coverage
   of U+2261.}
  Result.HamburgerMenu := TPopupMenu.Create(FForm);
  Result.HamburgerMenu.OnPopup := FOnHamburgerMenuPopup;
  {Sharing the toolbar's image list lets MI.ImageIndex paint the same arrow
   glyphs next to the Scroll/Filmstrip menu items that the toolbar buttons
   show — necessary because both modes share the textual caption.}
  Result.HamburgerMenu.Images := FGlyphs.Images;

  Result.BtnHamburger := TButton.Create(Result.Toolbar);
  Result.BtnHamburger.Parent := Result.Toolbar;
  Result.BtnHamburger.Images := FGlyphs.Images;
  Result.BtnHamburger.ImageIndex := IDX_ICON_HAMBURGER;
  Result.BtnHamburger.ImageAlignment := iaCenter;
  Result.BtnHamburger.Hint := 'More commands (toolbar buttons that did not fit).';
  {Square button matched to the rest of the toolbar's height}
  Result.BtnHamburger.SetBounds(0, CY, CtrlH, CtrlH);
  Result.BtnHamburger.OnClick := FOnHamburgerClick;
  Result.BtnHamburger.Visible := False;
end;

end.
