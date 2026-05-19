{Thin MessageBox wrapper that centralises the plugin's title literal.}
unit PluginMessages;

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
