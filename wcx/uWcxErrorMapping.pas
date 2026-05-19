{Maps Delphi exception classes to WCX error codes and clamps 64-bit
 sizes for the ANSI header API. Unmapped classes (and nil) fall through
 to E_EWRITE so the user gets a meaningful code instead of "disk write
 failed" for every cause.}
unit uWcxErrorMapping;

interface

uses
  System.SysUtils;

type
  {Lookup matches via InheritsFrom so subclasses resolve to the same
   WcxError. Order matters when one mapped class inherits from another
   (more-specific first); no current entries have that relationship.}
  TExceptionClassMapping = record
    ExceptionClass: TClass;
    WcxError: Integer;
  end;

function ExceptionClassToWcxError(AClass: TClass): Integer;

function ExceptionToWcxError(E: Exception): Integer;

{Saturates at MaxInt so a 5 GB combined image surfaces as ~2 GB instead
 of wrapping. Wide variant (ReadHeaderExW) is unaffected — it carries
 the full 64-bit value via UnpSize + UnpSizeHigh.}
function ClampSizeForAnsiHeader(AValue: Int64): Integer;

implementation

uses
  uWcxAPI;

const
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
