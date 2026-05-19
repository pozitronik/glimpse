{Window-subclass + keyboard-hook machinery: keeps the form in sync with
 TC's Lister, intercepts keys so Lister's shortcuts stay out, and closes
 the hamburger popup on tilde.}
unit uKeyInterceptionSubclass;

interface

uses
  Winapi.Windows, Winapi.Messages,
  Vcl.Forms;

const
  {Self-subclass installed AFTER TC subclasses us, so we fire first.}
  FORM_SUBCLASS_ID = 2;
  WM_DEFERRED_INIT = WM_USER + 102;
  WM_PLUGIN_FKEY = WM_USER + 103;

  {Modifier bit-flags packed into WM_PLUGIN_FKEY's lParam for reconstruction.}
  FKEY_LPARAM_SHIFT = 1;
  FKEY_LPARAM_CTRL = 2;
  FKEY_LPARAM_ALT = 4;

function EndMenu: BOOL; stdcall; external user32 name 'EndMenu';

{comctl32 v6 subclass API.}
function SetWindowSubclass(HWND: HWND; pfnSubclass: Pointer; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): BOOL; stdcall; external 'comctl32.dll' name 'SetWindowSubclass';
function RemoveWindowSubclass(HWND: HWND; pfnSubclass: Pointer; uIdSubclass: UINT_PTR): BOOL; stdcall; external 'comctl32.dll' name 'RemoveWindowSubclass';
function DefSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam): LRESULT; stdcall; external 'comctl32.dll' name 'DefSubclassProc';

{Closes the popup menu when VK_OEM_3 (tilde) is pressed in its modal loop.}
function MenuKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;

{Forces plugin child to fill TC's parent client rect — TC may not resize for all directions.}
function ParentSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;

{Keys the plugin MUST NOT swallow: Tab (VCL focus), Alt+F4 (system close),
 bare modifiers (TranslateMessage needs to see their down/up transitions).}
function ShouldLetKeyPassThrough(AKey: Word): Boolean;

function PackShiftIntoLParam: lParam;

function FormSubclassProc(HWND: HWND; uMsg: UINT; wParam: wParam; lParam: lParam; uIdSubclass: UINT_PTR; dwRefData: DWORD_PTR): LRESULT; stdcall;

{Returns the HHOOK so the caller can pass it to UninstallMenuKeyboardHook.}
function InstallMenuKeyboardHook: HHOOK;

{Idempotent; zero is a valid input.}
procedure UninstallMenuKeyboardHook(AHook: HHOOK);

implementation

var
  {Thread-local handle; active only during hamburger popup.}
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
  {TForm base (not TPluginForm) avoids the uses-cycle.}
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
