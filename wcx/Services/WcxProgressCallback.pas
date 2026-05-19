{Selects between TC's ANSI / Wide process-data callbacks. Prefers Wide
 when both are wired; falls back to ANSI; returns 1 (continue) when
 neither is wired so the extractor does not spuriously cancel itself.}
unit WcxProgressCallback;

interface

uses
  WcxAPI;

type
  IProcessDataProc = interface
    ['{82E6B4F2-AC1D-4F7A-8E1B-7F3E2D6A9B45}']
    {Returns 1=continue, 0=user cancelled.}
    function Notify(ASize: Integer): Integer;
  end;

  {AnsiString cached at construction so the per-tick Notify path does
   not allocate. Non-CP_ACP characters degrade silently in the ANSI
   conversion; acceptable because modern TC takes the Wide path.}
  TWcxProcessDataProc = class(TInterfacedObject, IProcessDataProc)
  strict private
    FFileNameW: string;
    FFileNameA: AnsiString;
    FCallbackA: TProcessDataProc;
    FCallbackW: TProcessDataProcW;
  public
    constructor Create(const AFileName: string; ACallbackA: TProcessDataProc;
      ACallbackW: TProcessDataProcW);
    function Notify(ASize: Integer): Integer;
  end;

implementation

constructor TWcxProcessDataProc.Create(const AFileName: string;
  ACallbackA: TProcessDataProc; ACallbackW: TProcessDataProcW);
begin
  inherited Create;
  FFileNameW := AFileName;
  FFileNameA := AnsiString(AFileName);
  FCallbackA := ACallbackA;
  FCallbackW := ACallbackW;
end;

function TWcxProcessDataProc.Notify(ASize: Integer): Integer;
begin
  if Assigned(FCallbackW) then
    Result := FCallbackW(PWideChar(FFileNameW), ASize)
  else if Assigned(FCallbackA) then
    Result := FCallbackA(PAnsiChar(FFileNameA), ASize)
  else
    Result := 1;
end;

end.
