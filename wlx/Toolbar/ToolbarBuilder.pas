{Toolbar construction for TPluginForm. Build measures captions via
 AForm.Canvas.TextWidth, so caller MUST ensure a valid Canvas first
 (handle allocated).}
unit ToolbarBuilder;

interface

uses
  System.Classes,
  Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Buttons,
  Vcl.ComCtrls, Vcl.Forms,
  Types,
  ToolbarGlyphLibrary;

type
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
    {Build's per-control-group steps. AX is the running horizontal cursor;
     ACtrlH is the shared control height set by the frame-count group.}
    procedure BuildToolbarPanel(var AHandles: TToolbarHandles);
    procedure BuildFrameCountGroup(var AHandles: TToolbarHandles; out ACtrlH, AX: Integer);
    procedure BuildModeButtons(var AHandles: TToolbarHandles; ACtrlH: Integer; var AX: Integer);
    procedure BuildTimecodeButton(var AHandles: TToolbarHandles; ACtrlH: Integer; var AX: Integer);
    procedure BuildActionButtons(var AHandles: TToolbarHandles; ACtrlH: Integer; var AX: Integer);
    procedure BuildHamburger(var AHandles: TToolbarHandles; ACtrlH: Integer);
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
  PlatformDetect, ToolbarLayout;

const
  MAX_FRAME_COUNT = 99; {upper limit for the frame-count spin edit}
  TB_PAD = 4; {Vertical padding above and below controls}
  CTRL_GAP = 8; {Gap between control groups}
  BTN_GAP = 2; {Gap between adjacent buttons in a group}
  BTN_PAD = 16; {Horizontal text padding inside button (both sides)}
  {Refresh has no glyph, so reserve dropdown-arrow width explicitly.}
  REFRESH_DROPDOWN_EXTRA = 14;
  {Save/Copy captions are longer than Refresh; extra buffer keeps the
   bsSplitButton arrow from pinching the text.}
  VIEW_DROPDOWN_EXTRA = REFRESH_DROPDOWN_EXTRA + 6;
  SPLIT_ARROW_W = 20; {Extra width for split button dropdown arrow}
  ICON_W = 16; {Toolbar icon width}
  ICON_GAP = 4; {Space between icon and caption on icon-bearing buttons}

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
  {Variants live in ToolbarLayout.SAVE_VIEW_VARIANTS — hamburger overflow
   and the resolution-suffix updater read the same constant.}
  Result := BuildViewVariantsMenu(FForm, SAVE_VIEW_VARIANTS,
    FOnViewDropdownPopup, FOnContextMenuClick);
end;

function TToolbarBuilder.CreateCopyViewPopup: TPopupMenu;
begin
  Result := BuildViewVariantsMenu(FForm, COPY_VIEW_VARIANTS,
    FOnViewDropdownPopup, FOnContextMenuClick);
end;

function TToolbarBuilder.Build: TToolbarHandles;
var
  CtrlH, X: Integer;
begin
  BuildToolbarPanel(Result);
  BuildFrameCountGroup(Result, CtrlH, X);
  {Collapsible elements: modes, timecodes, actions (left to right).}
  SetLength(Result.ElementRights, ELEM_TOTAL_COUNT);
  BuildModeButtons(Result, CtrlH, X);
  BuildTimecodeButton(Result, CtrlH, X);
  BuildActionButtons(Result, CtrlH, X);
  BuildHamburger(Result, CtrlH);
end;

procedure TToolbarBuilder.BuildToolbarPanel(var AHandles: TToolbarHandles);
begin
  AHandles.Toolbar := TPanel.Create(FForm);
  AHandles.Toolbar.Parent := FForm;
  AHandles.Toolbar.Align := alTop;
  AHandles.Toolbar.BevelOuter := bvNone;
  AHandles.Toolbar.ParentBackground := False;
end;

procedure TToolbarBuilder.BuildFrameCountGroup(var AHandles: TToolbarHandles;
  out ACtrlH, AX: Integer);
begin
  {Create the edit first: its auto-sized height is the reference for every
   toolbar control.}
  AHandles.EditFrameCount := TEdit.Create(AHandles.Toolbar);
  AHandles.EditFrameCount.Parent := AHandles.Toolbar;
  AHandles.EditFrameCount.Width := FRAME_COUNT_EDIT_W;
  AHandles.EditFrameCount.NumbersOnly := True;
  AHandles.EditFrameCount.TabOrder := 0;
  ACtrlH := AHandles.EditFrameCount.Height;

  AHandles.Toolbar.Height := ACtrlH + 2 * TB_PAD;
  AX := CTRL_GAP;

  AHandles.LblFrames := TLabel.Create(AHandles.Toolbar);
  AHandles.LblFrames.Parent := AHandles.Toolbar;
  AHandles.LblFrames.Caption := 'Frames:';
  AHandles.LblFrames.AutoSize := True;
  AHandles.LblFrames.Left := AX;
  AHandles.LblFrames.Top := TB_PAD + (ACtrlH - AHandles.LblFrames.Height) div 2;
  Inc(AX, AHandles.LblFrames.Width + 4);

  AHandles.EditFrameCount.SetBounds(AX, TB_PAD, FRAME_COUNT_EDIT_W, ACtrlH);
  AHandles.EditFrameCount.Hint := 'Number of frames to extract from the video.';

  AHandles.UpDown := TUpDown.Create(AHandles.Toolbar);
  AHandles.UpDown.Parent := AHandles.Toolbar;
  AHandles.UpDown.Associate := AHandles.EditFrameCount;
  AHandles.UpDown.Min := 1;
  AHandles.UpDown.Max := MAX_FRAME_COUNT;
  AHandles.UpDown.Hint := 'Number of frames to extract from the video.';
  Inc(AX, FRAME_COUNT_EDIT_W + AHandles.UpDown.Width + CTRL_GAP);
  AHandles.FrameCountRight := AX;
end;

procedure TToolbarBuilder.BuildModeButtons(var AHandles: TToolbarHandles;
  ACtrlH: Integer; var AX: Integer);
var
  VM: TViewMode;
  TabIdx, BW: Integer;
begin
  TabIdx := 1;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    {Create the popup menu first (needed for the DropDownMenu assignment).}
    AHandles.ModePopups[VM] := CreateModePopup(VM);

    AHandles.ModeButtons[VM] := TButton.Create(AHandles.Toolbar);
    AHandles.ModeButtons[VM].Parent := AHandles.Toolbar;

    {Skip split-arrow reservation on legacy Windows: BS_SPLITBUTTON does
     not render there and the extra width would leave a dead gap.}
    BW := FForm.Canvas.TextWidth(MODE_CAPTIONS[VM]) + BTN_PAD;
    if (AHandles.ModePopups[VM] <> nil) and not IsLegacyWindows then
      Inc(BW, SPLIT_ARROW_W);
    if VM in [vmScroll, vmFilmstrip] then
      Inc(BW, ICON_W + ICON_GAP);

    AHandles.ModeButtons[VM].SetBounds(AX, TB_PAD, BW, ACtrlH);
    AHandles.ModeButtons[VM].Caption := MODE_CAPTIONS[VM];
    AHandles.ModeButtons[VM].Hint := MODE_HINTS[VM];
    AHandles.ModeButtons[VM].Tag := Ord(VM);
    AHandles.ModeButtons[VM].TabOrder := TabIdx;
    AHandles.ModeButtons[VM].OnClick := FOnModeButtonClick;

    if MODE_GLYPH_INDEX[VM] >= 0 then
    begin
      AHandles.ModeButtons[VM].Images := FGlyphs.Images;
      AHandles.ModeButtons[VM].ImageIndex := MODE_GLYPH_INDEX[VM];
      {Qualify because Vcl.ComCtrls also defines iaRight.}
      AHandles.ModeButtons[VM].ImageAlignment := Vcl.StdCtrls.iaRight;
    end;

    {Legacy Windows pulls iaRight icons flush to the edge; add inset manually.}
    if (VM in [vmScroll, vmFilmstrip]) and IsLegacyWindows then
      AHandles.ModeButtons[VM].ImageMargins.Right := 2;

    {PopupMenu duplicates DropDownMenu for right-click so the submodes
     stay reachable on legacy Windows (no split-arrow rendering).}
    if AHandles.ModePopups[VM] <> nil then
    begin
      AHandles.ModeButtons[VM].Style := bsSplitButton;
      AHandles.ModeButtons[VM].DropDownMenu := AHandles.ModePopups[VM];
      AHandles.ModeButtons[VM].PopupMenu := AHandles.ModePopups[VM];
    end;

    AHandles.ElementRights[Ord(VM)] := AX + BW;
    Inc(TabIdx);
    if VM < High(TViewMode) then
      Inc(AX, BW + BTN_GAP)
    else
      Inc(AX, BW + CTRL_GAP);
  end;
end;

procedure TToolbarBuilder.BuildTimecodeButton(var AHandles: TToolbarHandles;
  ACtrlH: Integer; var AX: Integer);
var
  BW: Integer;
begin
  AHandles.BtnTimecode := TSpeedButton.Create(AHandles.Toolbar);
  AHandles.BtnTimecode.Parent := AHandles.Toolbar;
  BW := FForm.Canvas.TextWidth('Timecodes') + BTN_PAD;
  AHandles.BtnTimecode.SetBounds(AX, TB_PAD, BW, ACtrlH);
  AHandles.BtnTimecode.Caption := 'Timecodes';
  AHandles.BtnTimecode.Hint := 'Toggle timecode overlay on each frame (F2).';
  AHandles.BtnTimecode.GroupIndex := 1;
  AHandles.BtnTimecode.AllowAllUp := True;
  AHandles.BtnTimecode.OnClick := FOnTimecodeButtonClick;
  AHandles.ElementRights[ELEM_TIMECODE_INDEX] := AX + BW;
  Inc(AX, BW + CTRL_GAP);
end;

procedure TToolbarBuilder.BuildActionButtons(var AHandles: TToolbarHandles;
  ACtrlH: Integer; var AX: Integer);
var
  I, BW: Integer;
  Btn: TButton;
begin
  {Refresh becomes a split button so the dropdown exposes Shuffle as a peer.}
  SetLength(AHandles.ToolbarButtons, 0);
  AHandles.RefreshPopup := nil;
  AHandles.SaveViewPopup := nil;
  AHandles.CopyViewPopup := nil;
  for I := 0 to High(TB_ACTIONS) do
  begin
    Btn := TButton.Create(AHandles.Toolbar);
    Btn.Parent := AHandles.Toolbar;
    BW := FForm.Canvas.TextWidth(TB_ACTIONS[I].Caption) + BTN_PAD;
    if not IsLegacyWindows then
      case TB_ACTIONS[I].Tag of
        CM_REFRESH:
          Inc(BW, REFRESH_DROPDOWN_EXTRA);
        CM_SAVE_VIEW, CM_COPY_VIEW:
          Inc(BW, VIEW_DROPDOWN_EXTRA);
      end;
    Btn.SetBounds(AX, TB_PAD, BW, ACtrlH);
    Btn.Caption := TB_ACTIONS[I].Caption;
    Btn.Hint := TB_ACTIONS[I].Hint;
    Btn.Tag := TB_ACTIONS[I].Tag;
    Btn.Enabled := False;
    Btn.OnClick := FOnToolbarButtonClick;
    if TB_ACTIONS[I].Tag = CM_REFRESH then
    begin
      AHandles.RefreshPopup := CreateRefreshPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := AHandles.RefreshPopup;
      Btn.PopupMenu := AHandles.RefreshPopup;
    end
    else if TB_ACTIONS[I].Tag = CM_SAVE_VIEW then
    begin
      AHandles.SaveViewPopup := CreateSaveViewPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := AHandles.SaveViewPopup;
      Btn.PopupMenu := AHandles.SaveViewPopup;
    end
    else if TB_ACTIONS[I].Tag = CM_COPY_VIEW then
    begin
      AHandles.CopyViewPopup := CreateCopyViewPopup;
      Btn.Style := bsSplitButton;
      Btn.DropDownMenu := AHandles.CopyViewPopup;
      Btn.PopupMenu := AHandles.CopyViewPopup;
    end;
    AHandles.ElementRights[ELEM_ACTION_FIRST + I] := AX + BW;
    Inc(AX, BW + BTN_GAP);
    SetLength(AHandles.ToolbarButtons, Length(AHandles.ToolbarButtons) + 1);
    AHandles.ToolbarButtons[High(AHandles.ToolbarButtons)] := Btn;
  end;
end;

procedure TToolbarBuilder.BuildHamburger(var AHandles: TToolbarHandles; ACtrlH: Integer);
begin
  AHandles.HamburgerMenu := TPopupMenu.Create(FForm);
  AHandles.HamburgerMenu.OnPopup := FOnHamburgerMenuPopup;
  {Share the toolbar's image list so menu items can paint the same arrow
   glyphs next to Scroll/Filmstrip entries (both share a textual caption).}
  AHandles.HamburgerMenu.Images := FGlyphs.Images;

  AHandles.BtnHamburger := TButton.Create(AHandles.Toolbar);
  AHandles.BtnHamburger.Parent := AHandles.Toolbar;
  AHandles.BtnHamburger.Images := FGlyphs.Images;
  AHandles.BtnHamburger.ImageIndex := IDX_ICON_HAMBURGER;
  AHandles.BtnHamburger.ImageAlignment := iaCenter;
  AHandles.BtnHamburger.Hint := 'More commands (toolbar buttons that did not fit).';
  {Square button matched to the rest of the toolbar's height.}
  AHandles.BtnHamburger.SetBounds(0, TB_PAD, ACtrlH, ACtrlH);
  AHandles.BtnHamburger.OnClick := FOnHamburgerClick;
  AHandles.BtnHamburger.Visible := False;
end;

end.
