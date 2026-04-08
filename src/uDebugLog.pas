{Thread-safe debug logging to file.
 Logging is active when GDebugLogPath is non-empty; set automatically
 in debug builds, can be enabled manually in release builds.}
unit uDebugLog;

interface

var
  GDebugLogPath: string;

  {Thread-safe debug logging to file. Tag identifies the subsystem.
   No-op when GDebugLogPath is empty.}
procedure DebugLog(const ATag, AMsg: string);

implementation

uses
  System.SysUtils, System.SyncObjs;

function GetCurrentThreadId: Cardinal; stdcall; external 'kernel32.dll';

var
  LogLock: TCriticalSection;

procedure DebugLog(const ATag, AMsg: string);
var
  F: TextFile;
begin
  if GDebugLogPath = '' then
    Exit;
  LogLock.Enter;
  try
    try
      AssignFile(F, GDebugLogPath);
      if FileExists(GDebugLogPath) then
        Append(F)
      else
        Rewrite(F);
      try
        WriteLn(F, Format('%s  [tid=%d] [%s] %s', [FormatDateTime('hh:nn:ss.zzz', Now), GetCurrentThreadId, ATag, AMsg]));
      finally
        CloseFile(F);
      end;
    except
      {Logging must never crash the plugin}
    end;
  finally
    LogLock.Leave;
  end;
end;

initialization

LogLock := TCriticalSection.Create;

finalization

FreeAndNil(LogLock);

end.
