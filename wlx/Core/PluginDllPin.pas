{Pins the WLX plugin DLL into the host process via an extra LoadLibrary
 refcount so background threads can run to natural completion even when
 TC unloads the plugin. The pin is intentionally never released; the OS
 reclaims the DLL handle on host exit.}
unit PluginDllPin;

interface

type
  TPluginDllPin = class
  public
    {Adds one LoadLibrary refcount. Never raises; if LoadLibrary fails the
     worst case is the pre-pin behaviour (host may unload the DLL mid-call).}
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
