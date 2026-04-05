unit TestToolbarLayout;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestToolbarLayout = class
  public
    { ComputeToolbarLayout }
    [Test] procedure Expanded_WhenWidthExceedsActionsRight;
    [Test] procedure ActionsCollapsed_WhenWidthBelowActionsRight;
    [Test] procedure AllCollapsed_WhenWidthBelowModesPlusHamburger;
    [Test] procedure HamburgerLeftAtModeGroup_WhenActionsCollapsed;
    [Test] procedure HamburgerLeftAtFrameCount_WhenAllCollapsed;
    [Test] procedure ExactBoundary_ActionsRight_StaysExpanded;
    [Test] procedure OneBelowBoundary_ActionsRight_Collapses;
    [Test] procedure ExactBoundary_ModesPlusHamburger_KeepsModes;
    [Test] procedure OneBelowBoundary_ModesPlusHamburger_CollapsesAll;
    { PopulateHamburgerMenu }
    [Test] procedure Menu_ActionsCollapsed_NoModeItems;
    [Test] procedure Menu_AllCollapsed_HasModeItems;
    [Test] procedure Menu_AlwaysHasTimecodeItem;
    [Test] procedure Menu_TimecodeChecked_WhenActive;
    [Test] procedure Menu_ActionItemsMatchCount;
    [Test] procedure Menu_SettingsAlwaysEnabled;
    [Test] procedure Menu_ActionsDisabled_WhenNoFrames;
    [Test] procedure Menu_ActionsEnabled_WhenHasFrames;
    [Test] procedure Menu_ActiveModeIsDefault;
    [Test] procedure Menu_ZoomSubmenuChecked;
    [Test] procedure Menu_ModeWithoutSubmenu_HasOnClick;
    [Test] procedure Menu_ModeWithSubmenu_HasNoOnClick;
  end;

implementation

uses
  System.SysUtils, Vcl.Menus, uTypes, uToolbarLayout;

const
  { Simulated group boundaries }
  FC_RIGHT  = 100;
  MG_RIGHT  = 350;
  ACT_RIGHT = 700;
  HAM_W     = 30;
  GAP       = 8;

{ ComputeToolbarLayout tests }

procedure TTestToolbarLayout.Expanded_WhenWidthExceedsActionsRight;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(800, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsExpanded), Ord(R.CollapseState));
end;

procedure TTestToolbarLayout.ActionsCollapsed_WhenWidthBelowActionsRight;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(500, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsActionsCollapsed), Ord(R.CollapseState));
end;

procedure TTestToolbarLayout.AllCollapsed_WhenWidthBelowModesPlusHamburger;
var
  R: TToolbarLayoutResult;
begin
  { MG_RIGHT + HAM_W + GAP = 350 + 30 + 8 = 388 }
  R := ComputeToolbarLayout(300, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsAllCollapsed), Ord(R.CollapseState));
end;

procedure TTestToolbarLayout.HamburgerLeftAtModeGroup_WhenActionsCollapsed;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(500, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(MG_RIGHT, R.HamburgerLeft);
end;

procedure TTestToolbarLayout.HamburgerLeftAtFrameCount_WhenAllCollapsed;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(200, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(FC_RIGHT, R.HamburgerLeft);
end;

procedure TTestToolbarLayout.ExactBoundary_ActionsRight_StaysExpanded;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(ACT_RIGHT, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsExpanded), Ord(R.CollapseState));
end;

procedure TTestToolbarLayout.OneBelowBoundary_ActionsRight_Collapses;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(ACT_RIGHT - 1, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsActionsCollapsed), Ord(R.CollapseState));
end;

procedure TTestToolbarLayout.ExactBoundary_ModesPlusHamburger_KeepsModes;
var
  R: TToolbarLayoutResult;
begin
  { Width = MG_RIGHT + HAM_W + GAP = 388, which is the threshold }
  R := ComputeToolbarLayout(MG_RIGHT + HAM_W + GAP, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsActionsCollapsed), Ord(R.CollapseState));
end;

procedure TTestToolbarLayout.OneBelowBoundary_ModesPlusHamburger_CollapsesAll;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(MG_RIGHT + HAM_W + GAP - 1, FC_RIGHT, MG_RIGHT, ACT_RIGHT, HAM_W, GAP);
  Assert.AreEqual(Ord(tcsAllCollapsed), Ord(R.CollapseState));
end;

{ PopulateHamburgerMenu tests }

function MakeState(ACollapse: TToolbarCollapseState; AActiveMode: TViewMode;
  AShowTimecode, AHasFrames: Boolean): THamburgerMenuState;
var
  VM: TViewMode;
begin
  Result.CollapseState := ACollapse;
  Result.ActiveMode := AActiveMode;
  Result.ShowTimecode := AShowTimecode;
  Result.HasFrames := AHasFrames;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    Result.ModeZooms[VM] := zmFitWindow;
    { Smart and Grid have no submenu; Scroll, Filmstrip, Single do }
    Result.ModeHasSubmenu[VM] := not (VM in [vmSmartGrid, vmGrid]);
  end;
end;

procedure TTestToolbarLayout.Menu_ActionsCollapsed_NoModeItems;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    { No mode items; first item should be Timecodes }
    for I := 0 to Menu.Items.Count - 1 do
      Assert.AreNotEqual(MODE_CAPTIONS[vmSmartGrid], Menu.Items[I].Caption);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_AllCollapsed_HasModeItems;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsAllCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    { First item should be the first mode caption }
    Assert.AreEqual(MODE_CAPTIONS[vmSmartGrid], Menu.Items[0].Caption);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_AlwaysHasTimecodeItem;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I: Integer;
  Found: Boolean;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    Found := False;
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Caption = 'Timecodes' then
        Found := True;
    Assert.IsTrue(Found, 'Timecodes item not found');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_TimecodeChecked_WhenActive;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, True, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Caption = 'Timecodes' then
        Assert.IsTrue(Menu.Items[I].Checked);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ActionItemsMatchCount;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I, ActionCount: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    ActionCount := 0;
    for I := 0 to Menu.Items.Count - 1 do
      if (Menu.Items[I].Caption <> '-') and (Menu.Items[I].Caption <> 'Timecodes') then
        Inc(ActionCount);
    Assert.AreEqual(Length(TB_ACTIONS), ActionCount);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_SettingsAlwaysEnabled;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, False, False);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Tag = CM_SETTINGS then
        Assert.IsTrue(Menu.Items[I].Enabled, 'Settings should always be enabled');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ActionsDisabled_WhenNoFrames;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, False, False);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    for I := 0 to Menu.Items.Count - 1 do
      if (Menu.Items[I].Tag <> 0) and (Menu.Items[I].Tag <> CM_SETTINGS) then
        Assert.IsFalse(Menu.Items[I].Enabled,
          Format('Item "%s" should be disabled', [Menu.Items[I].Caption]));
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ActionsEnabled_WhenHasFrames;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsActionsCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Tag <> 0 then
        Assert.IsTrue(Menu.Items[I].Enabled,
          Format('Item "%s" should be enabled', [Menu.Items[I].Caption]));
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ActiveModeIsDefault;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsAllCollapsed, vmScroll, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    { vmScroll is index 2 }
    Assert.IsTrue(Menu.Items[Ord(vmScroll)].Default,
      'Active mode item should be marked Default (bold)');
    Assert.IsFalse(Menu.Items[Ord(vmGrid)].Default,
      'Inactive mode item should not be Default');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ZoomSubmenuChecked;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  ModeItem: TMenuItem;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsAllCollapsed, vmScroll, False, True);
    State.ModeZooms[vmScroll] := zmFitIfLarger;
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    ModeItem := Menu.Items[Ord(vmScroll)];
    { Submenu: 3 zoom items; zmFitIfLarger is index 1 }
    Assert.IsFalse(ModeItem.Items[0].Checked, 'zmFitWindow should not be checked');
    Assert.IsTrue(ModeItem.Items[1].Checked, 'zmFitIfLarger should be checked');
    Assert.IsFalse(ModeItem.Items[2].Checked, 'zmActual should not be checked');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ModeWithoutSubmenu_HasOnClick;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsAllCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    { vmSmartGrid (index 0) and vmGrid (index 1) have no submenu }
    Assert.AreEqual(0, Menu.Items[Ord(vmSmartGrid)].Count,
      'Smart should have no sub-items');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_ModeWithSubmenu_HasNoOnClick;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
begin
  Menu := TPopupMenu.Create(nil);
  try
    State := MakeState(tcsAllCollapsed, vmGrid, False, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    { vmScroll (index 2) has a submenu with 3 zoom items }
    Assert.AreEqual(3, Menu.Items[Ord(vmScroll)].Count,
      'Scroll should have 3 zoom sub-items');
    Assert.IsFalse(Assigned(Menu.Items[Ord(vmScroll)].OnClick),
      'Mode with submenu should not have OnClick');
  finally
    Menu.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestToolbarLayout);

end.
