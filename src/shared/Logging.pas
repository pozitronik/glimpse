{Thread-safe debug logging to file via TDebugLog singleton. Holds the
 stream open between writes (TStreamWriter + AutoFlush) for low-overhead
 logging. Configure is the only mutator. DebugLog/DebugLogger are facades.}
unit Logging;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs;

type
  TDebugLog = class
  private
    {Plain `private` (not strict) so initialization/finalization can
     touch the class var.}
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

    {Empty path disables logging. Never raises; logging must not crash
     the plugin. A failed open leaves ActivePath set for diagnosability
     while Log silently no-ops.}
    procedure Configure(const APath: string);

    {Last path passed to Configure; non-empty does not imply writable.}
    function ActivePath: string;

    procedure Log(const ATag, AMsg: string);

    class function Instance: TDebugLog; static;
  end;

procedure DebugLog(const ATag, AMsg: string);

{Returns a closure that prepends ATag to every call. ATag is captured
 by value, safe to keep as a unit-level constant.}
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
  {FWriter.OwnStream means freeing FWriter frees FStream too.}
  FreeAndNil(FWriter);
  FStream := nil;
end;

procedure TDebugLog.InternalOpen(const APath: string);
begin
  {fmShareDenyNone is required so tests using TFile.ReadAllLines
   (fmShareDenyWrite under the hood) can coexist with an active writer.}
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
      {FStream/FWriter stay nil so Log no-ops; FPath stays set for
       diagnosability via ActivePath.}
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
      DebugLog(ATag, AMsg);
    end;
end;

initialization
  TDebugLog.FInstance := TDebugLog.Create;

finalization
  FreeAndNil(TDebugLog.FInstance);

end.
