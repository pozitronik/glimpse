{Thin Win32 MessageBox wrapper that centralises the plugin's title
 literal. Callers across both WLX and WCX surfaces use this so renaming
 the plugin is a one-line change here instead of a grep-and-replace
 across every MessageBox call.

 Returns the underlying MessageBox result (IDOK / IDYES / etc.) so the
 caller can branch on the user's choice.}
unit uPluginMessages;

interface

uses
  Winapi.Windows;

const
  PLUGIN_MESSAGE_TITLE = 'Glimpse';

function ShowPluginMessage(AHandle: HWND; const AText: string; AFlags: Cardinal): Integer;

implementation

function ShowPluginMessage(AHandle: HWND; const AText: string; AFlags: Cardinal): Integer;
begin
  Result := MessageBox(AHandle, PChar(AText), PLUGIN_MESSAGE_TITLE, AFlags);
end;

end.
