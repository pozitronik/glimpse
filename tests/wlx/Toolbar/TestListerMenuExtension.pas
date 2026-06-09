{Leak-regression tests for TListerMenuExtension teardown. The extension
 appends a popup tree onto the host's menu bar; Win32 RemoveMenu only
 detaches popup items, so Teardown must DestroyMenu the detached tree or
 every Lister close / ForceRebuild leaks USER handles into the host
 process. Menu APIs refuse to work against fakes, so the fixture hosts a
 real (hidden) top-level window with a real menu bar.}
unit TestListerMenuExtension;

interface

uses
  DUnitX.TestFramework,
  Winapi.Windows,
  ListerMenuExtension;

type
  [TestFixture]
  TTestListerMenuExtension = class
  strict private
    FWnd: HWND;
    FExt: TListerMenuExtension;
    function MenuBar: HMENU;
    function GlimpsePopup: HMENU;
    procedure CreateExtension;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Create_AppendsGlimpseItemWithPopup;
    [Test] procedure Destroy_RemovesItemAndDestroysPopupTree;
    [Test] procedure Destroy_PreservesHostItems;
    [Test] procedure ForceRebuild_KeepsExactlyOneGlimpseItem;
    [Test] procedure RepeatedForceRebuild_DoesNotAccumulateUserObjects;
  end;

implementation

uses
  System.SysUtils;

const
  HOST_CLASS = 'GlimpseTestListerMenuHostWnd';
  {Pretend host menu item so our appends land at position 1, mirroring a
   real TLister bar that already has its own entries.}
  HOST_ITEM_ID = 1;

var
  GClassRegistered: Boolean = False;

procedure EnsureHostClass;
var
  WC: TWndClassEx;
begin
  if GClassRegistered then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.lpfnWndProc := @DefWindowProc;
  WC.hInstance := HInstance;
  WC.lpszClassName := HOST_CLASS;
  if RegisterClassEx(WC) = 0 then
    raise Exception.Create('TestListerMenuExtension: RegisterClassEx failed');
  GClassRegistered := True;
end;

{First nested popup inside APopup (the mode-zoom / frame-count / save-view
 submenus). Used to prove DestroyMenu released the whole tree, not just
 the top-level handle.}
function FirstNestedPopup(APopup: HMENU): HMENU;
var
  I: Integer;
begin
  for I := 0 to GetMenuItemCount(APopup) - 1 do
  begin
    Result := GetSubMenu(APopup, I);
    if Result <> 0 then
      Exit;
  end;
  Result := 0;
end;

procedure TTestListerMenuExtension.Setup;
var
  Bar: HMENU;
begin
  EnsureHostClass;
  FWnd := CreateWindowEx(0, HOST_CLASS, 'Glimpse menu host', WS_OVERLAPPEDWINDOW,
    0, 0, 320, 200, 0, 0, HInstance, nil);
  if FWnd = 0 then
    raise Exception.Create('TestListerMenuExtension: CreateWindowEx failed');
  Bar := CreateMenu;
  AppendMenu(Bar, MF_STRING, HOST_ITEM_ID, 'File');
  SetMenu(FWnd, Bar);
end;

procedure TTestListerMenuExtension.TearDown;
var
  Msg: TMsg;
begin
  {Free before DestroyWindow so the destructor's Teardown runs against the
   live menu — the exact path the leak fix guards.}
  FreeAndNil(FExt);
  if FWnd <> 0 then
  begin
    {Purge the constructor's posted deferred-install message so it cannot
     linger in the test thread's queue between fixtures.}
    while PeekMessage(Msg, FWnd, 0, 0, PM_REMOVE) do
      ;
    {DestroyWindow also destroys the attached menu bar.}
    DestroyWindow(FWnd);
    FWnd := 0;
  end;
end;

function TTestListerMenuExtension.MenuBar: HMENU;
begin
  Result := GetMenu(FWnd);
end;

function TTestListerMenuExtension.GlimpsePopup: HMENU;
begin
  Result := GetSubMenu(MenuBar, 1);
end;

procedure TTestListerMenuExtension.CreateExtension;
begin
  FExt := TListerMenuExtension.Create(FWnd, nil,
    procedure(const AEntry: TListerMenuEntry)
    begin
    end,
    function: Integer
    begin
      Result := 4;
    end);
end;

procedure TTestListerMenuExtension.Create_AppendsGlimpseItemWithPopup;
begin
  CreateExtension;
  Assert.AreEqual(2, GetMenuItemCount(MenuBar), 'host item + Glimpse item expected');
  Assert.IsTrue(GlimpsePopup <> 0, 'Glimpse item must carry a popup submenu');
end;

procedure TTestListerMenuExtension.Destroy_RemovesItemAndDestroysPopupTree;
var
  Popup, Nested: HMENU;
begin
  CreateExtension;
  Popup := GlimpsePopup;
  Nested := FirstNestedPopup(Popup);
  Assert.IsTrue(IsMenu(Popup), 'sanity: popup alive while installed');
  Assert.IsTrue(Nested <> 0, 'sanity: build produces nested popups');

  FreeAndNil(FExt);

  {No menu is created between Free and these checks, so a False IsMenu
   cannot be masked by handle reuse.}
  Assert.AreEqual(1, GetMenuItemCount(MenuBar), 'Glimpse item must be removed');
  Assert.IsFalse(IsMenu(Popup), 'detached popup must be destroyed, not leaked');
  Assert.IsFalse(IsMenu(Nested), 'nested popups must die with the tree');
end;

procedure TTestListerMenuExtension.Destroy_PreservesHostItems;
begin
  CreateExtension;
  FreeAndNil(FExt);
  Assert.AreEqual(1, GetMenuItemCount(MenuBar));
  Assert.AreEqual(HOST_ITEM_ID, Integer(GetMenuItemID(MenuBar, 0)),
    'host''s own item must survive teardown untouched');
end;

procedure TTestListerMenuExtension.ForceRebuild_KeepsExactlyOneGlimpseItem;
begin
  CreateExtension;
  FExt.ForceRebuild;
  {Old-handle IsMenu checks are unreliable here: the rebuild creates new
   popups that may reuse the freed handle value. Structural asserts here;
   destruction itself is proven by the Destroy and GuiResources tests.}
  Assert.AreEqual(2, GetMenuItemCount(MenuBar), 'rebuild must not duplicate the item');
  Assert.IsTrue(GlimpsePopup <> 0, 'rebuilt item must carry a popup');
end;

procedure TTestListerMenuExtension.RepeatedForceRebuild_DoesNotAccumulateUserObjects;
var
  I: Integer;
  Before, After: DWORD;
begin
  CreateExtension;
  {Warm up so one-time lazy allocations do not pollute the measurement.}
  for I := 1 to 3 do
    FExt.ForceRebuild;
  Before := GetGuiResources(GetCurrentProcess, GR_USEROBJECTS);
  for I := 1 to 40 do
    FExt.ForceRebuild;
  After := GetGuiResources(GetCurrentProcess, GR_USEROBJECTS);
  {Pre-fix each cycle orphaned the whole popup tree (~9 USER handles,
   ~360 over 40 cycles). Post-fix growth is zero; 40 leaves slack for
   unrelated jitter while still failing hard on a reintroduced leak.}
  Assert.IsTrue(Integer(After) - Integer(Before) < 40,
    Format('USER objects grew by %d over 40 rebuild cycles', [Integer(After) - Integer(Before)]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestListerMenuExtension);

end.
