{Pure clamping policy for the user-facing frames count. Lives in the
 domain layer (no VCL) so both the settings UI and the lister menu can
 route every proposed value through one authoritative range guard.}
unit FrameCountPolicy;

interface

type
  TFrameCountPolicy = record
    {Clamps AValue to [MIN_FRAMES_COUNT, MAX_FRAMES_COUNT].}
    class function Clamp(AValue: Integer): Integer; static;
  end;

implementation

uses
  System.Math, Defaults;

class function TFrameCountPolicy.Clamp(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MIN_FRAMES_COUNT, MAX_FRAMES_COUNT);
end;

end.
