{ Thread-safe debug logging to file.
  Extracted so that any unit can log without depending on uCache. }
unit uDebugLog;

interface

{$IFDEF DEBUG}
var
  GDebugLogPath: string;

{ Thread-safe debug logging to file. Tag identifies the subsystem. }
procedure DebugLog(const ATag, AMsg: string);
{$ENDIF}

implementation

uses
  System.SysUtils;

{$IFDEF DEBUG}
function GetCurrentThreadId: Cardinal; stdcall; external 'kernel32.dll';

procedure DebugLog(const ATag, AMsg: string);
var
  F: TextFile;
begin
  if GDebugLogPath = '' then Exit;
  try
    AssignFile(F, GDebugLogPath);
    if FileExists(GDebugLogPath) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, Format('%s  [tid=%d] [%s] %s',
        [FormatDateTime('hh:nn:ss.zzz', Now), GetCurrentThreadId, ATag, AMsg]));
    finally
      CloseFile(F);
    end;
  except
    { Logging must never crash the plugin }
  end;
end;
{$ENDIF}

end.
