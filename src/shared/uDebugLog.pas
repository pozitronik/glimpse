{Thread-safe debug logging to file via TDebugLog singleton.

 The previous implementation opened/appended/closed the log file on
 every DebugLog call and exposed a mutable global `GDebugLogPath` as
 the on/off switch. That had two costs: per-call file-open/close I/O
 under heavy logging, and an unowned variable that any unit could
 write from anywhere.

 The singleton holds the file handle open between writes (TStreamWriter
 + AutoFlush) so successive DebugLog calls just append a line. The
 stream is opened with fmShareDenyWrite so other readers (tests,
 external log viewers) can read the file concurrently. The mutable
 global is gone — Configure(APath) is the only mutator and it is a
 method, not an exported variable.

 DebugLog and DebugLogger remain as free-function facades for callers
 that don't need to touch the singleton directly. They are the public
 surface every existing consumer already uses.}
unit uDebugLog;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs;

type
  TDebugLog = class
  private
    {Plain `private` (not strict) so the unit's initialization /
     finalization block can construct and free the singleton. strict
     private would also block same-unit code per Delphi's scoping rule.}
    class var FInstance: TDebugLog;
  strict private
    FLock: TCriticalSection;
    FStream: TFileStream;
    FWriter: TStreamWriter;
    FPath: string;
    procedure InternalClose;
    procedure InternalOpen(const APath: string);
  public
    constructor Create;
    destructor Destroy; override;

    {Opens APath for append (or creates it if missing) and routes every
     subsequent Log call to that file. Passing an empty path disables
     logging. Closes any previously-open handle first. If the open
     fails (invalid path, permission denied, ...) Log silently no-ops
     until the next successful Configure; ActivePath still reflects
     the caller's intent so the failure is diagnosable. Configure
     never raises — logging must not crash the plugin.}
    procedure Configure(const APath: string);

    {Returns the path most recently passed to Configure. Empty when
     logging is disabled. Note: a non-empty ActivePath does not
     guarantee the file is writable — only that Configure was called
     with that path.}
    function ActivePath: string;

    {Writes ATag + AMsg as a timestamped line to the held handle.
     Silently no-ops when Configure was never called, when Configure
     was called with '', or when the underlying open failed. Never
     raises.}
    procedure Log(const ATag, AMsg: string);

    class function Instance: TDebugLog; static;
  end;

  {Thread-safe debug logging to file. Tag identifies the subsystem.
   No-op when no log file is configured. Thin facade over
   TDebugLog.Instance.Log.}
procedure DebugLog(const ATag, AMsg: string);

{Returns a closure that prepends ATag and forwards to DebugLog. Lets a
 unit declare `Log: TProc<string> := DebugLogger('ExtCtrl')` once and
 call `Log('message')` everywhere, instead of hand-writing a
 tag-prepending wrapper procedure in every unit that does subsystem
 logging. The closure captures ATag by value so it is safe to keep as
 a unit-level constant.}
function DebugLogger(const ATag: string): TProc<string>;

implementation

function GetCurrentThreadId: Cardinal; stdcall; external 'kernel32.dll';

{TDebugLog}

constructor TDebugLog.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
end;

destructor TDebugLog.Destroy;
begin
  InternalClose;
  FreeAndNil(FLock);
  inherited;
end;

class function TDebugLog.Instance: TDebugLog;
begin
  Result := FInstance;
end;

procedure TDebugLog.InternalClose;
begin
  {FWriter owns FStream via OwnStream — freeing FWriter frees the
   stream too. Null FStream afterwards so the open-helper sees a
   clean slate on the next Configure.}
  FreeAndNil(FWriter);
  FStream := nil;
end;

procedure TDebugLog.InternalOpen(const APath: string);
begin
  {fmShareDenyNone (FILE_SHARE_READ | FILE_SHARE_WRITE) lets any other
   opener read AND write the file while we hold it open. The "any other
   writer" tolerance is what tests need: TFile.ReadAllLines opens with
   fmShareDenyWrite which itself refuses to coexist with any active
   writer; only an fmShareDenyNone-on-both-sides arrangement composes.
   The previous opens-and-closes-per-write impl also allowed concurrent
   readers and accepted concurrent writers (interleave-at-line risk),
   so this is no regression in practice. Append if the file exists;
   create otherwise.}
  if FileExists(APath) then
  begin
    FStream := TFileStream.Create(APath, fmOpenReadWrite or fmShareDenyNone);
    FStream.Seek(0, soEnd);
  end
  else
    FStream := TFileStream.Create(APath, fmCreate or fmShareDenyNone);
  FWriter := TStreamWriter.Create(FStream, TEncoding.UTF8);
  FWriter.OwnStream;
  FWriter.AutoFlush := True;
end;

procedure TDebugLog.Configure(const APath: string);
begin
  FLock.Enter;
  try
    InternalClose;
    FPath := APath;
    if APath = '' then
      Exit;
    try
      InternalOpen(APath);
    except
      {Open failed; FStream/FWriter stay nil so Log no-ops. FPath stays
       set so ActivePath shows the attempted path for diagnosability.}
      FreeAndNil(FWriter);
      FStream := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDebugLog.ActivePath: string;
begin
  FLock.Enter;
  try
    Result := FPath;
  finally
    FLock.Leave;
  end;
end;

procedure TDebugLog.Log(const ATag, AMsg: string);
begin
  FLock.Enter;
  try
    if FWriter = nil then
      Exit;
    try
      FWriter.WriteLine(Format('%s  [tid=%d] [%s] %s',
        [FormatDateTime('hh:nn:ss.zzz', Now), GetCurrentThreadId, ATag, AMsg]));
    except
      {Logging must never crash the plugin}
    end;
  finally
    FLock.Leave;
  end;
end;

{Facades}

procedure DebugLog(const ATag, AMsg: string);
begin
  TDebugLog.Instance.Log(ATag, AMsg);
end;

function DebugLogger(const ATag: string): TProc<string>;
begin
  Result :=
    procedure(AMsg: string)
    begin
      {TProc<string> is `reference to procedure(Arg1: string)` — no
       const-qualifier. The forwarded call uses DebugLog's const-string
       parameter which accepts the plain string without copy.}
      DebugLog(ATag, AMsg);
    end;
end;

initialization
  TDebugLog.FInstance := TDebugLog.Create;

finalization
  FreeAndNil(TDebugLog.FInstance);

end.
