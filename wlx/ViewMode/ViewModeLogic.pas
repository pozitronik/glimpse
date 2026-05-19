{View mode switching and zoom cycling logic.
 Maps keyboard input to mode transitions without UI dependencies.}
unit ViewModeLogic;

interface

uses
  Types;

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

{Number of frames sharing the viewport under AMode. Single/Scroll/Filmstrip
 size at most one frame at viewport scale; grid layouts tile the full queue.}
function ViewportFrameCount(AMode: TViewMode; ATotalFrames: Integer): Integer;

{Returns '' for unhandled enum values — defensive against future enum growth.}
function ViewModeDisplayName(AMode: TViewMode): string;
function ZoomModeDisplayName(AMode: TZoomMode): string;

implementation

uses
  Winapi.Windows, WlxAPI;

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

function ViewModeDisplayName(AMode: TViewMode): string;
begin
  case AMode of
    vmSmartGrid: Result := 'Smart Grid';
    vmGrid:      Result := 'Grid';
    vmScroll:    Result := 'Scroll';
    vmFilmstrip: Result := 'Filmstrip';
    vmSingle:    Result := 'Single';
  else
    Result := '';
  end;
end;

function ZoomModeDisplayName(AMode: TZoomMode): string;
begin
  case AMode of
    zmFitWindow:   Result := 'Fit window';
    zmFitIfLarger: Result := 'Fit if larger';
    zmActual:      Result := 'Actual size';
  else
    Result := '';
  end;
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
