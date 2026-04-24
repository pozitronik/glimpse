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
 Single-view displays one frame at a time occupying the full viewport,
 so scaled extraction must size against 1 regardless of how many frames
 are queued. All other modes render every extracted frame simultaneously,
 so the full queue length is the right divisor for viewport area.}
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
  if AMode = vmSingle then
    Result := 1
  else
    Result := ATotalFrames;
end;

end.
