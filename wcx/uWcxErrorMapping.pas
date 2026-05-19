{Maps Delphi exception classes to WCX error codes, and the size-clamp
 used by the ANSI header API.

 Adding a new (ExceptionClass -> WcxError) mapping is a one-line table
 entry. Unmapped classes (and nil) fall through to E_EWRITE - TC's
 generic mid-extraction failure code, which the host surfaces as a
 follow-up dialog. The mapping is intentionally narrow: only the
 high-signal classes (out-of-memory, file-not-found) branch off so the
 user sees a meaningful code instead of the legacy "disk write failed"
 for every failure cause.

 Takes a class reference rather than an instance so tests can pin every
 branch without allocating instances of leak-tricky classes (EOutOfMemory
 overrides FreeInstance to a no-op for the singleton path).

 The ANSI header API uses 32-bit signed sizes; ClampSizeForAnsiHeader
 prevents wrap-around when a combined image exceeds 2 GB (rare but
 possible). The Wide variant (ReadHeaderExW) carries the full 64-bit
 value via UnpSize + UnpSizeHigh and is unaffected.

 Extracted from uWcxExports so the ABI thunk unit stays focused on the
 WCX stdcall entries; both helpers are now reachable by any WCX unit
 without a back-link into the dispatcher.}
unit uWcxErrorMapping;

interface

uses
  System.SysUtils;

type
  {One row in the exception-to-WCX-error lookup table. ExceptionClass is
   the metaclass reference; the lookup matches via InheritsFrom so any
   subclass of the listed class resolves to the same WcxError. Order
   matters when one mapped class inherits from another (more-specific
   first) - none of the current entries have that relationship.}
  TExceptionClassMapping = record
    ExceptionClass: TClass;
    WcxError: Integer;
  end;

{Looks up the WCX error code for AClass. Walks EXCEPTION_MAP with
 InheritsFrom; subclasses inherit the mapping. Nil and unmapped classes
 return E_EWRITE.}
function ExceptionClassToWcxError(AClass: TClass): Integer;

{Convenience wrapper that handles E = nil (returns E_EWRITE) before
 unwrapping E.ClassType into ExceptionClassToWcxError.}
function ExceptionToWcxError(E: Exception): Integer;

{Clamps a 64-bit size into the 32-bit signed range used by
 THeaderData.UnpSize. Negative values become 0 (defensive; sizes from
 disk are non-negative); values above MaxInt saturate at MaxInt so a
 5 GB combined image surfaces as ~2 GB instead of wrapping into a
 negative or truncated value.}
function ClampSizeForAnsiHeader(AValue: Int64): Integer;

implementation

uses
  uWcxAPI;

const
  {Adding a new (ExceptionClass -> WcxError) mapping is a one-line table
   entry. Unmapped classes (and nil) fall through to E_EWRITE - the WCX
   "write error" code that TC interprets as a generic mid-extraction
   failure with a follow-up dialog.}
  EXCEPTION_MAP: array[0..1] of TExceptionClassMapping = (
    (ExceptionClass: EOutOfMemory;           WcxError: E_NO_MEMORY),
    (ExceptionClass: EFileNotFoundException; WcxError: E_EOPEN)
  );

function ExceptionClassToWcxError(AClass: TClass): Integer;
var
  I: Integer;
begin
  if AClass = nil then
    Exit(E_EWRITE);
  for I := 0 to High(EXCEPTION_MAP) do
    if AClass.InheritsFrom(EXCEPTION_MAP[I].ExceptionClass) then
      Exit(EXCEPTION_MAP[I].WcxError);
  Result := E_EWRITE;
end;

function ExceptionToWcxError(E: Exception): Integer;
begin
  if E = nil then
    Result := E_EWRITE
  else
    Result := ExceptionClassToWcxError(E.ClassType);
end;

function ClampSizeForAnsiHeader(AValue: Int64): Integer;
begin
  if AValue < 0 then
    Result := 0
  else if AValue > MaxInt then
    Result := MaxInt
  else
    Result := Integer(AValue);
end;

end.
