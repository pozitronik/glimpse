{Callback wrapper for TC's WCX process-data progress callbacks.

 TC's WCX SDK exposes two parallel callback types: TProcessDataProc
 (ANSI, PAnsiChar filename) and TProcessDataProcW (Wide, PWideChar
 filename). At runtime modern TC wires the Wide variant; legacy and
 some embedded TC builds only wire the ANSI variant; very old builds
 may wire neither. The plugin must:

 1. Prefer the Wide variant when both are set.
 2. Fall back to the ANSI variant when only it is wired.
 3. Silently no-op (return 1 = continue) when neither is wired, so the
    extractor does not spuriously cancel itself.

 The ANSI/Wide selection used to live inline inside the progress
 bridge, which forced the bridge to know about both callback shapes
 and cache the filename in both encodings. This unit lifts that
 selection out: the bridge holds a single IProcessDataProc reference,
 the export boundary builds the wrapper from the raw callbacks, and
 the filename caching becomes the wrapper's private concern.}
unit uWcxProgressCallback;

interface

uses
  uWcxAPI;

type
  IProcessDataProc = interface
    ['{82E6B4F2-AC1D-4F7A-8E1B-7F3E2D6A9B45}']
    {Invokes TC's progress callback with the cached filename and the
     supplied Size value. Returns the callback's verdict: 1 = continue,
     0 = user cancelled. When no real callback is wired (both inner
     pointers nil), returns 1 unconditionally so the extractor runs
     silently rather than treating "no UI" as "cancel".}
    function Notify(ASize: Integer): Integer;
  end;

  {Production adapter holding both encodings of the filename and both
   callback pointers. Notify dispatches to the Wide callback first,
   falls back to ANSI, returns 1 when neither is wired.

   The filename is converted to AnsiString once at construction so the
   per-tick Notify path does not allocate. Non-CP_ACP characters
   degrade silently in the ANSI conversion; this matches the bridge's
   historical behaviour and is acceptable because modern TC takes the
   Wide path.}
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
