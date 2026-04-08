{Zoom factor arithmetic and viewport centering for continuous zoom.
 Pure computation: no UI or VCL dependencies.}
unit uZoomController;

interface

const
  ZOOM_IN_FACTOR = 1.25;
  ZOOM_OUT_FACTOR = 1 / 1.25;
  MIN_ZOOM = 0.1;
  MAX_ZOOM = 10.0;
  ZOOM_EPSILON = 0.0001;

  {Calculates a new zoom factor by multiplying OldZoom by AFactor,
   clamped to MIN_ZOOM..MAX_ZOOM. Returns 0 if the result equals OldZoom
   within ZOOM_EPSILON (meaning no visible change).}
function ClampZoomFactor(OldZoom, AFactor: Double): Double;

{Returns the normalized position (0..1) of the viewport center
 within the content area. Returns 0.5 when ContentSize is zero.}
function NormalizeViewportCenter(ScrollPos, ViewportSize, ContentSize: Integer): Double;

{Converts a normalized center position back to a scroll position
 for the given new content and viewport sizes. Never returns negative.}
function DenormalizeViewportCenter(NormPos: Double; NewContentSize, ViewportSize: Integer): Integer;

implementation

uses
  System.Math;

function ClampZoomFactor(OldZoom, AFactor: Double): Double;
begin
  Result := EnsureRange(OldZoom * AFactor, MIN_ZOOM, MAX_ZOOM);
  if SameValue(Result, OldZoom, ZOOM_EPSILON) then
    Result := 0;
end;

function NormalizeViewportCenter(ScrollPos, ViewportSize, ContentSize: Integer): Double;
begin
  if ContentSize > 0 then
    Result := (ScrollPos + ViewportSize / 2) / ContentSize
  else
    Result := 0.5;
end;

function DenormalizeViewportCenter(NormPos: Double; NewContentSize, ViewportSize: Integer): Integer;
begin
  Result := Max(0, Round(NormPos * NewContentSize - ViewportSize / 2));
end;

end.
