{Environment variable expansion for file paths.
 Wraps the Windows ExpandEnvironmentStrings API so callers don't need
 Winapi.Windows in their uses clause.}
unit uPathExpand;

interface

{Expands environment variables (%TEMP%, %commander_path%, etc.) in a path.
 Returns the input unchanged if it contains no variables or is empty.}
function ExpandEnvVars(const APath: string): string;

implementation

uses
  Winapi.Windows;

function ExpandEnvVars(const APath: string): string;
var
  BufLen: DWORD;
begin
  if APath = '' then
    Exit('');
  BufLen := ExpandEnvironmentStrings(PChar(APath), nil, 0);
  if BufLen = 0 then
    Exit(APath);
  SetLength(Result, BufLen - 1);
  ExpandEnvironmentStrings(PChar(APath), PChar(Result), BufLen);
end;

end.
