{Pins the WLX plugin DLL into the host process via an extra LoadLibrary
 refcount so background threads can run to natural completion even when
 TC unloads the plugin (e.g. when the user closes the Lister mid-task).

 Without the pin, TC's FreeLibrary would unmap our code while a worker
 thread is still executing inside it — instant crash. The pin is
 intentionally never released; the OS reclaims the DLL handle on TC
 exit. One pin per cancelled-and-detached operation, only when the
 cancel actually fires, so the per-session cost is negligible.

 Previously this LoadLibrary call lived inline inside
 TBitmapWorkThread.RequestCancel. Lifting it into a tiny helper
 separates the host-environment concern from the worker-runner role
 and lets future cancellable operations adopt the same pin without
 copy-pasting the GetModuleFileName + LoadLibrary boilerplate.

 Implemented as a class procedure (not a TInterfacedObject instance)
 so the DLL pin is a pure Win32 refcount with no Pascal object to
 track — DUnitX's leak detector would otherwise flag the deliberately-
 immortal instance every test run.}
unit uPluginDllPin;

interface

type
  TPluginDllPin = class
  public
    {Acquires the pin. Idempotent in effect: each call adds one
     LoadLibrary refcount, which is fine — the OS reclaims them all on
     host-process exit. Never raises; if LoadLibrary returns 0 for any
     reason the worst case is the historical pre-pin behaviour (host
     may unload the DLL mid-call).}
    class procedure Acquire; static;
  end;

implementation

uses
  Winapi.Windows;

class procedure TPluginDllPin.Acquire;
var
  ModuleName: array[0..MAX_PATH - 1] of Char;
begin
  GetModuleFileName(HInstance, ModuleName, Length(ModuleName));
  LoadLibrary(ModuleName);
end;

end.
