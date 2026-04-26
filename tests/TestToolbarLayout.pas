unit TestToolbarLayout;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestToolbarLayout = class
  public
    { ComputeToolbarLayout }
    [Test] procedure AllVisible_WhenWidthExceedsLastElement;
    [Test] procedure LastElementHidden_WhenWidthJustBelow;
    [Test] procedure HamburgerAtLastVisible_PlusGap;
    [Test] procedure NothingFits_HamburgerAtFrameCount;
    [Test] procedure ExactBoundary_LastElement_StaysVisible;
    [Test] procedure MidGroupCutoff_HidesOnlyTail;
    [Test] procedure SingleElementHidden_ShowsHamburger;
    [Test] procedure EmptyElements_AllVisible;
    { PopulateHamburgerMenu: per-button behavior }
    [Test] procedure Menu_AllVisible_Empty;
    [Test] procedure Menu_OneActionHidden_ShowsOnlyThat;
    [Test] procedure Menu_AllActionsHidden_ShowsAllActions;
    [Test] procedure Menu_TimecodeHidden_ShowsTimecodeAndActions;
    [Test] procedure Menu_SomeModesHidden_ShowsOnlyHiddenModes;
    [Test] procedure Menu_NothingVisible_ShowsEverything;
    [Test] procedure Menu_TimecodeChecked_WhenActive;
    [Test] procedure Menu_SettingsAlwaysEnabled;
    [Test] procedure Menu_ActionsDisabled_WhenNoFrames;
    [Test] procedure Menu_ActionsEnabled_WhenHasFrames;
    [Test] procedure Menu_ActiveModeIsDefault;
    [Test] procedure Menu_ZoomSubmenuChecked;
    [Test] procedure Menu_ModeWithoutSubmenu_HasOnClick;
    [Test] procedure Menu_ModeWithSubmenu_HasNoOnClick;
    [Test] procedure Menu_Separators_BetweenGroups;
    [Test] procedure Menu_NoSeparator_WhenOnlyActions;
  end;

implementation

uses
  System.SysUtils, Vcl.Menus, uTypes, uToolbarLayout;

const
  { Simulated element right edges (13 elements, left to right) }
  FC_RIGHT  = 100;  { frame count group right edge }
  HAM_W     = 30;
  GAP       = 8;

{ Helper: builds a right-edge array where element I has right edge at BASE + I*STEP }
function MakeRights(ABase, AStep, ACount: Integer): TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    Result[I] := ABase + (I + 1) * AStep;
end;

{ Standard 13-element layout: right edges from 150 to 750 (step 50) }
function StdRights: TArray<Integer>;
begin
  Result := MakeRights(100, 50, ELEM_TOTAL_COUNT);
  { Element 0: 150, Element 1: 200, ..., Element 12: 750 }
end;

{ ComputeToolbarLayout tests }

procedure TTestToolbarLayout.AllVisible_WhenWidthExceedsLastElement;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(800, StdRights, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(ELEM_TOTAL_COUNT, R.VisibleCount);
  Assert.IsFalse(R.HamburgerVisible);
end;

procedure TTestToolbarLayout.LastElementHidden_WhenWidthJustBelow;
var
  R: TToolbarLayoutResult;
begin
  { Width 749: last element right is 750, doesn't fit without hamburger.
    Element 11 right = 700, 700 + 8 + 30 = 738 <= 749: fits }
  R := ComputeToolbarLayout(749, StdRights, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(12, R.VisibleCount);
  Assert.IsTrue(R.HamburgerVisible);
end;

procedure TTestToolbarLayout.HamburgerAtLastVisible_PlusGap;
var
  R: TToolbarLayoutResult;
begin
  R := ComputeToolbarLayout(749, StdRights, FC_RIGHT, HAM_W, GAP);
  { Last visible element (index 11) right = 700 }
  Assert.AreEqual(700 + GAP, R.HamburgerLeft);
end;

procedure TTestToolbarLayout.NothingFits_HamburgerAtFrameCount;
var
  R: TToolbarLayoutResult;
begin
  { Width 120: first element right = 150, 150 + 8 + 30 = 188 > 120 }
  R := ComputeToolbarLayout(120, StdRights, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(0, R.VisibleCount);
  Assert.IsTrue(R.HamburgerVisible);
  Assert.AreEqual(FC_RIGHT, R.HamburgerLeft);
end;

procedure TTestToolbarLayout.ExactBoundary_LastElement_StaysVisible;
var
  R: TToolbarLayoutResult;
begin
  { Width = 750 = last element right: all visible }
  R := ComputeToolbarLayout(750, StdRights, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(ELEM_TOTAL_COUNT, R.VisibleCount);
  Assert.IsFalse(R.HamburgerVisible);
end;

procedure TTestToolbarLayout.MidGroupCutoff_HidesOnlyTail;
var
  R: TToolbarLayoutResult;
begin
  { Width 500: elements with right <= 500 - GAP - HAM_W = 462 are visible.
    Element 6 right = 450 <= 462: visible. Element 7 right = 500 > 462: hidden.
    So VisibleCount = 7 (elements 0..6). }
  R := ComputeToolbarLayout(500, StdRights, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(7, R.VisibleCount);
  Assert.IsTrue(R.HamburgerVisible);
end;

procedure TTestToolbarLayout.SingleElementHidden_ShowsHamburger;
var
  Rights: TArray<Integer>;
  R: TToolbarLayoutResult;
begin
  { 3 elements at 200, 300, 400 }
  Rights := MakeRights(100, 100, 3);
  { Width 399: last element 400 doesn't fit. Element 1 right = 300, 300+8+30 = 338 <= 399 }
  R := ComputeToolbarLayout(399, Rights, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(2, R.VisibleCount);
  Assert.IsTrue(R.HamburgerVisible);
end;

procedure TTestToolbarLayout.EmptyElements_AllVisible;
var
  Empty: TArray<Integer>;
  R: TToolbarLayoutResult;
begin
  SetLength(Empty, 0);
  R := ComputeToolbarLayout(100, Empty, FC_RIGHT, HAM_W, GAP);
  Assert.AreEqual(0, R.VisibleCount);
  Assert.IsFalse(R.HamburgerVisible);
end;

{ PopulateHamburgerMenu tests }

function MakeState(AVisibleCount: Integer; AActiveMode: TViewMode;
  AShowTimecode, AHasFrames: Boolean): THamburgerMenuState;
var
  VM: TViewMode;
begin
  Result.VisibleCount := AVisibleCount;
  Result.ActiveMode := AActiveMode;
  Result.ShowTimecode := AShowTimecode;
  Result.HasFrames := AHasFrames;
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    Result.ModeZooms[VM] := zmFitWindow;
    { Smart and Grid have no submenu; Scroll, Filmstrip, Single do }
    Result.ModeHasSubmenu[VM] := not (VM in [vmSmartGrid, vmGrid]);
    { No menu glyph by default; tests that care set this explicitly }
    Result.ModeImageIndex[VM] := -1;
  end;
end;

function CountNonSeparators(AMenu: TPopupMenu): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to AMenu.Items.Count - 1 do
    if AMenu.Items[I].Caption <> '-' then
      Inc(Result);
end;

procedure TTestToolbarLayout.Menu_AllVisible_Empty;
var
  Menu: TPopupMenu;
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(ELEM_TOTAL_COUNT, vmGrid, False, True),
      nil, nil, nil, nil);
    Assert.AreEqual(0, Menu.Items.Count);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_OneActionHidden_ShowsOnlyThat;
var
  Menu: TPopupMenu;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { VisibleCount = 12: element 12 (Settings) hidden }
    PopulateHamburgerMenu(Menu, MakeState(12, vmGrid, False, True),
      nil, nil, nil, nil);
    { Should have: separator + Settings = 2 items }
    Assert.AreEqual(1, CountNonSeparators(Menu),
      'Only Settings should be in the menu');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_AllActionsHidden_ShowsAllActions;
var
  Menu: TPopupMenu;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { VisibleCount = 6: all modes + timecodes visible, all 7 actions hidden }
    PopulateHamburgerMenu(Menu, MakeState(ELEM_ACTION_FIRST, vmGrid, False, True),
      nil, nil, nil, nil);
    Assert.AreEqual(Length(TB_ACTIONS), CountNonSeparators(Menu));
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_TimecodeHidden_ShowsTimecodeAndActions;
var
  Menu: TPopupMenu;
  State: THamburgerMenuState;
  Found: Boolean;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { VisibleCount = 5: all modes visible, timecodes + all actions hidden }
    State := MakeState(ELEM_TIMECODE_INDEX, vmGrid, True, True);
    PopulateHamburgerMenu(Menu, State, nil, nil, nil, nil);
    { Timecodes + 7 actions = 8 non-separator items }
    Assert.AreEqual(8, CountNonSeparators(Menu));
    Found := False;
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Caption = 'Timecodes' then
        Found := True;
    Assert.IsTrue(Found, 'Timecodes item not found');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_SomeModesHidden_ShowsOnlyHiddenModes;
var
  Menu: TPopupMenu;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { VisibleCount = 3: Smart, Grid, Scroll visible; Filmstrip + Single hidden
      plus Timecodes + 7 actions }
    PopulateHamburgerMenu(Menu, MakeState(3, vmGrid, False, True),
      nil, nil, nil, nil);
    { 2 modes + Timecodes + 7 actions = 10 non-separator items }
    Assert.AreEqual(10, CountNonSeparators(Menu));
    { First non-separator should be Filmstrip (Scroll horizontal) }
    Assert.AreEqual(MODE_CAPTIONS[vmFilmstrip], Menu.Items[0].Caption);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_NothingVisible_ShowsEverything;
var
  Menu: TPopupMenu;
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, False, True),
      nil, nil, nil, nil);
    { 5 modes + Timecodes + 7 actions = 13 non-separator items }
    Assert.AreEqual(ELEM_TOTAL_COUNT, CountNonSeparators(Menu));
    { First item should be the first mode }
    Assert.AreEqual(MODE_CAPTIONS[vmSmartGrid], Menu.Items[0].Caption);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_TimecodeChecked_WhenActive;
var
  Menu: TPopupMenu;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, True, True),
      nil, nil, nil, nil);
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Caption = 'Timecodes' then
        Assert.IsTrue(Menu.Items[I].Checked);
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_SettingsAlwaysEnabled;
var
  Menu: TPopupMenu;
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, False, False),
      nil, nil, nil, nil);
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
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { Use ELEM_ACTION_FIRST to exclude mode items (whose tags collide with
      action tags) and focus on action-specific enable/disable behavior }
    PopulateHamburgerMenu(Menu, MakeState(ELEM_ACTION_FIRST, vmGrid, False, False),
      nil, nil, nil, nil);
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
  I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, False, True),
      nil, nil, nil, nil);
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
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmScroll, False, True),
      nil, nil, nil, nil);
    { vmScroll is element index 2, and first 5 items are modes }
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
    State := MakeState(0, vmScroll, False, True);
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
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, False, True),
      nil, nil, nil, nil);
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
begin
  Menu := TPopupMenu.Create(nil);
  try
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, False, True),
      nil, nil, nil, nil);
    { vmScroll (index 2) has a submenu with 3 zoom items }
    Assert.AreEqual(3, Menu.Items[Ord(vmScroll)].Count,
      'Scroll should have 3 zoom sub-items');
    Assert.IsFalse(Assigned(Menu.Items[Ord(vmScroll)].OnClick),
      'Mode with submenu should not have OnClick');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_Separators_BetweenGroups;
var
  Menu: TPopupMenu;
  SepCount, I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { All hidden: modes + timecodes + actions = 3 groups, 2 separators }
    PopulateHamburgerMenu(Menu, MakeState(0, vmGrid, False, True),
      nil, nil, nil, nil);
    SepCount := 0;
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Caption = '-' then
        Inc(SepCount);
    Assert.AreEqual(2, SepCount,
      'Should have separators between modes/timecodes and timecodes/actions');
  finally
    Menu.Free;
  end;
end;

procedure TTestToolbarLayout.Menu_NoSeparator_WhenOnlyActions;
var
  Menu: TPopupMenu;
  SepCount, I: Integer;
begin
  Menu := TPopupMenu.Create(nil);
  try
    { Only last 3 actions hidden: no mode/timecode items, just action group }
    PopulateHamburgerMenu(Menu, MakeState(10, vmGrid, False, True),
      nil, nil, nil, nil);
    SepCount := 0;
    for I := 0 to Menu.Items.Count - 1 do
      if Menu.Items[I].Caption = '-' then
        Inc(SepCount);
    Assert.AreEqual(0, SepCount, 'No separators when only actions are shown');
  finally
    Menu.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestToolbarLayout);

end.
