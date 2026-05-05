{View mode switching and zoom cycling logic.
 Maps keyboard input to mode transitions without UI dependencies.}
unit uViewModeLogic;

interface

uses
  uTypes;

{Maps a virtual key code to a view mode.
 Supports Ord('1')..Ord('5') and VK_NUMPAD1..VK_NUMPAD5.
 Returns False if the key does not map to any mode.}
function KeyToViewMode(AKey: Word; out AMode: TViewMode): Boolean;

{Cycles to the next zoom mode: FitWindow -> FitIfLarger -> Actual -> FitWindow.}
function NextZoomMode(ACurrent: TZoomMode): TZoomMode;

{Returns True for modes that support zoom submodes (Scroll, Filmstrip, Single).
 Grid modes always fit all frames to available space.}
function ModeHasZoomSubmodes(AMode: TViewMode): Boolean;

{Maps Total Commander Lister parameter flags to a zoom mode.}
function ListerParamsToZoomMode(AParams: Integer): TZoomMode;

{Number of frames that share the viewport at once under a given mode.
 Single-view, scroll and filmstrip all display at most one frame at
 viewport scale at a time (scroll stacks them vertically at full viewport
 width; filmstrip lays them horizontally at full viewport height), so
 scaled extraction must size against 1 for all three. Only the grid
 layouts tile multiple frames into shared cells, so the full queue
 length is the right divisor there.}
function ViewportFrameCount(AMode: TViewMode; ATotalFrames: Integer): Integer;

implementation

uses
  Winapi.Windows, uWlxAPI;

const
  KEY_TO_MODE: array [0 .. 4] of TViewMode = (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);

function KeyToViewMode(AKey: Word; out AMode: TViewMode): Boolean;
var
  Idx: Integer;
begin
  case AKey of
    Ord('1') .. Ord('5'):
      Idx := AKey - Ord('1');
    VK_NUMPAD1 .. VK_NUMPAD5:
      Idx := AKey - VK_NUMPAD1;
    else
      begin
        Result := False;
        Exit;
      end;
  end;
  AMode := KEY_TO_MODE[Idx];
  Result := True;
end;

function NextZoomMode(ACurrent: TZoomMode): TZoomMode;
begin
  Result := TZoomMode((Ord(ACurrent) + 1) mod (Ord(High(TZoomMode)) + 1));
end;

function ModeHasZoomSubmodes(AMode: TViewMode): Boolean;
begin
  Result := not(AMode in [vmSmartGrid, vmGrid]);
end;

function ListerParamsToZoomMode(AParams: Integer): TZoomMode;
begin
  if (AParams and lcp_FitToWindow) <> 0 then
  begin
    if (AParams and lcp_FitLargerOnly) <> 0 then
      Result := zmFitIfLarger
    else
      Result := zmFitWindow;
  end
  else
    Result := zmActual;
end;

function ViewportFrameCount(AMode: TViewMode; ATotalFrames: Integer): Integer;
begin
  case AMode of
    vmSingle, vmScroll, vmFilmstrip:
      Result := 1;
    else
      Result := ATotalFrames;
  end;
end;

end.
