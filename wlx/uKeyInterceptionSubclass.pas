{Window-subclass + keyboard-hook machinery used by the plugin form to
 (a) keep its bounds in sync with TC's Lister window, (b) intercept
 every key off the form's wndproc so Lister's built-in shortcuts stay
 out of the plugin's way, and (c) close the hamburger popup when the
 tilde key is pressed. Hoisted from uPluginForm so the externals,
 callbacks and constants live in one place, and so ShouldLetKeyPassThrough
 is independently testable.}
unit uKeyInterceptionSubclass;

interface

uses
  Winapi.Windows, Winapi.Messages,
  Vcl.Forms;

const
  {Deferred self-subclass: installed after TC subclasses us so we fire first}
  FORM_SUBCLASS_ID = 2;
  WM_DEFERRED_INIT = WM_USER + 102; {Triggers self-subclass installation}
  WM_PLUGIN_FKEY = WM_USER + 103; {Re-posted key intercepted from TC}

  {Bit flags packed into the re-posted WM_PLUGIN_FKEY's lParam so the form
   WndProc can reconstruct TShiftState on the other side of the re-post.}
  FKEY_LPARAM_SHIFT = 1;
  FKEY_LPARAM_CTRL = 2;
  FKEY_LPARAM_ALT = 4;

{Closes the active menu on the calling thread}
function EndMenu: BOOL; stdcall; external user32 name 'EndMenu';

{comctl32 v6 subclass API - lets us monitor the parent window's WM_SIZE}
function SetWindowSubclass(HWND: HWND; pfnSubclass: Pointer; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): BOOL; stdcall; external 'comctl32.dll' name 'SetWindowSubclass';
function RemoveWindowSubclass(HWND: HWND; pfnSubclass: Pointer; uIdSubclass: UINT_PTR): BOOL; stdcall; external 'comctl32.dll' name 'RemoveWindowSubclass';
function DefSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam): LRESULT; stdcall; external 'comctl32.dll' name 'DefSubclassProc';

{Intercepts VK_OEM_3 (tilde) during popup menu's modal loop to close it}
function MenuKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;

{Subclass callback on TC's Lister parent window.
 TC may not resize the plugin child for all resize directions;
 this ensures the plugin always fills the parent's client rect.}
function ParentSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;

{True when AKey should flow through to the VCL/OS key pipeline unchanged
 instead of being swallowed by the plugin's key-interception. These are the
 keys the plugin cannot own without breaking system behaviour:
 - Tab: VCL focus cycling relies on the standard WM_KEYDOWN path.
 - Alt+F4: Windows delivers SC_CLOSE via the normal chain; hijacking it
 would leave users unable to close the Lister window.
 - Bare modifier keys: meaningless alone, and we need TranslateMessage to
 see their down/up transitions for subsequent key combinations to build
 correct WM_SYSKEYDOWN messages.}
function ShouldLetKeyPassThrough(AKey: Word): Boolean;

{Packs the live modifier-key state into a single LPARAM value so the
 repost target can rebuild TShiftState without another GetKeyState call.}
function PackShiftIntoLParam: lParam;

{Self-subclass callback on the plugin form window.
 Installed AFTER TC subclasses us (via deferred PostMessage), so it fires
 first in the chain. Claims every key-down message so Lister's built-in
 shortcuts (Escape to close, 1-9 view-mode switch, N/P file navigation,
 letter-key mode toggles, etc.) stay out of the plugin's way and every
 key flows through the plugin's own hotkey dispatcher instead. Excluded
 keys (see ShouldLetKeyPassThrough) flow through unchanged.}
function FormSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;

{Installs the keyboard hook that closes a popup menu when VK_OEM_3
 (tilde) is pressed. Mirrors the OnHamburgerClick lifecycle: hook on
 popup open, uninstall on popup close. Returns the HHOOK so the
 caller can pass it back to UninstallMenuKeyboardHook.}
function InstallMenuKeyboardHook: HHOOK;

{Uninstalls AHook if non-zero. Idempotent; zero is a valid input.}
procedure UninstallMenuKeyboardHook(AHook: HHOOK);

implementation

var
  {Thread-local keyboard hook handle, active only during hamburger popup}
  GMenuHook: HHOOK;

function MenuKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;
begin
  if (nCode = HC_ACTION) and (wParam = VK_OEM_3) and (lParam and (1 shl 31) = 0) then
  begin
    EndMenu;
    Result := 1;
  end
  else
    Result := CallNextHookEx(GMenuHook, nCode, wParam, lParam);
end;

function ParentSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
var
  {The original cast was to TPluginForm; using the TForm base avoids the
   uPluginForm uses-cycle and is sufficient because only HandleAllocated
   and SetBounds are called, both declared on TForm/TWinControl bases.}
  Form: TForm;
  R: TRect;
begin
  Result := DefSubclassProc(HWND, uMsg, wParam, lParam);
  if uMsg = WM_SIZE then
  begin
    Form := TForm(Pointer(dwRefData));
    if (Form <> nil) and Form.HandleAllocated then
    begin
      Winapi.Windows.GetClientRect(HWND, R);
      Form.SetBounds(0, 0, R.Right, R.Bottom);
    end;
  end;
end;

function ShouldLetKeyPassThrough(AKey: Word): Boolean;
begin
  case AKey of
    VK_TAB, VK_SHIFT, VK_CONTROL, VK_MENU, VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU:
      Exit(True);
  end;
  {Alt+F4 is a system close shortcut — let the OS deliver its SC_CLOSE.}
  if (AKey = VK_F4) and (GetKeyState(VK_MENU) < 0) then
    Exit(True);
  Result := False;
end;

function PackShiftIntoLParam: lParam;
begin
  Result := 0;
  if GetKeyState(VK_SHIFT) < 0 then
    Result := Result or FKEY_LPARAM_SHIFT;
  if GetKeyState(VK_CONTROL) < 0 then
    Result := Result or FKEY_LPARAM_CTRL;
  if GetKeyState(VK_MENU) < 0 then
    Result := Result or FKEY_LPARAM_ALT;
end;

function FormSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;
begin
  case uMsg of
    WM_KEYDOWN, WM_SYSKEYDOWN:
      if not ShouldLetKeyPassThrough(wParam) then
      begin
        PostMessage(HWND, WM_PLUGIN_FKEY, wParam, PackShiftIntoLParam);
        Result := 0;
        Exit;
      end;
    WM_NCDESTROY:
      RemoveWindowSubclass(HWND, @FormSubclassProc, FORM_SUBCLASS_ID);
  end;
  Result := DefSubclassProc(HWND, uMsg, wParam, lParam);
end;

function InstallMenuKeyboardHook: HHOOK;
begin
  GMenuHook := SetWindowsHookEx(WH_KEYBOARD, @MenuKeyboardProc, 0, GetCurrentThreadId);
  Result := GMenuHook;
end;

procedure UninstallMenuKeyboardHook(AHook: HHOOK);
begin
  if AHook <> 0 then
    UnhookWindowsHookEx(AHook);
  GMenuHook := 0;
end;

end.
