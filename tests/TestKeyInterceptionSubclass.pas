{Pinning tests for the pure key-passthrough policy hoisted out of
 uPluginForm. ShouldLetKeyPassThrough's per-key rationale is load-
 bearing for the plugin's key-interception subclass — any future
 regression here would silently break either VCL focus cycling (Tab)
 or the user's ability to close the Lister window (Alt+F4) or hotkey
 chord assembly (bare modifiers). One test per branch.}
unit TestKeyInterceptionSubclass;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestKeyInterceptionSubclass = class
  public
    [Test] procedure Tab_PassesThrough;
    [Test] procedure ShiftKey_PassesThrough;
    [Test] procedure ControlKey_PassesThrough;
    [Test] procedure MenuKey_PassesThrough;
    [Test] procedure LeftShiftKey_PassesThrough;
    [Test] procedure LetterKey_DoesNotPassThrough;
    [Test] procedure F1_DoesNotPassThrough;
    [Test] procedure F4_WithoutAlt_DoesNotPassThrough;
  end;

implementation

uses
  Winapi.Windows,
  uKeyInterceptionSubclass;

procedure TTestKeyInterceptionSubclass.Tab_PassesThrough;
begin
  {Tab must reach the VCL so focus cycling works inside the form.}
  Assert.IsTrue(ShouldLetKeyPassThrough(VK_TAB));
end;

procedure TTestKeyInterceptionSubclass.ShiftKey_PassesThrough;
begin
  {Bare modifier; needed so subsequent combos build WM_SYSKEYDOWN correctly.}
  Assert.IsTrue(ShouldLetKeyPassThrough(VK_SHIFT));
end;

procedure TTestKeyInterceptionSubclass.ControlKey_PassesThrough;
begin
  Assert.IsTrue(ShouldLetKeyPassThrough(VK_CONTROL));
end;

procedure TTestKeyInterceptionSubclass.MenuKey_PassesThrough;
begin
  {VK_MENU == Alt. Bare Alt must reach the OS or system menus die.}
  Assert.IsTrue(ShouldLetKeyPassThrough(VK_MENU));
end;

procedure TTestKeyInterceptionSubclass.LeftShiftKey_PassesThrough;
begin
  {Sided variants of the modifier keys share the same passthrough policy
   as the generic VK_SHIFT/VK_CONTROL/VK_MENU. One representative pin
   guards the case branch from accidental removal.}
  Assert.IsTrue(ShouldLetKeyPassThrough(VK_LSHIFT));
end;

procedure TTestKeyInterceptionSubclass.LetterKey_DoesNotPassThrough;
begin
  {Plain letter keys are the plugin's domain; they must be intercepted
   and routed through the hotkey dispatcher instead of leaking to TC's
   built-in shortcuts.}
  Assert.IsFalse(ShouldLetKeyPassThrough(Ord('A')));
end;

procedure TTestKeyInterceptionSubclass.F1_DoesNotPassThrough;
begin
  {Function keys without Alt belong to the plugin's hotkey table.}
  Assert.IsFalse(ShouldLetKeyPassThrough(VK_F1));
end;

procedure TTestKeyInterceptionSubclass.F4_WithoutAlt_DoesNotPassThrough;
begin
  {Without Alt, VK_F4 is just a function key — the plugin owns it.
   The Alt+F4 -> passthrough branch reads live GetKeyState(VK_MENU) and
   can't be tested deterministically here without driving the live
   keyboard state, so this case stays uncovered by design.}
  Assert.IsFalse(ShouldLetKeyPassThrough(VK_F4));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestKeyInterceptionSubclass);

end.
