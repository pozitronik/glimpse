{Shared type declarations used across multiple units.
 Extracted from uSettings to break unnecessary coupling.}
unit uTypes;

interface

type
  TFFmpegMode = (fmAuto, fmExe);
  TViewMode = (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);
  TZoomMode = (zmFitWindow, zmFitIfLarger, zmActual);
  {Thumbnail rendering mode for TC panel previews. Single = one frame at
   a configurable position; Grid = mini multi-frame composite.}
  TThumbnailMode = (tnmSingle, tnmGrid);
  {Timestamp overlay corner on each frame cell (WLX live view and combined image).
   tcNone disables the overlay entirely (useful as a single-control off switch).}
  TTimestampCorner = (tcNone, tcTopLeft, tcTopRight, tcBottomLeft, tcBottomRight);
  {Info banner placement relative to the combined image.}
  TBannerPosition = (bpTop, bpBottom);

  {Status-bar progress bar layout policy. AfterPanels reserves a slot to
   the right of the info panels (legacy behaviour, fine on wide windows
   but the bar disappears off-screen in narrow ones); OverPanels paints
   the bar full-width on top of the panels; Auto picks AfterPanels when
   the lister is wide enough to fit both, otherwise OverPanels.}
  TProgressBarLayout = (pblAfterPanels, pblOverPanels, pblAuto);

  {Bundles extraction parameters that travel together through the
   extraction pipeline (controller -> worker -> extractor).}
  TExtractionOptions = record
    UseBmpPipe: Boolean;
    MaxSide: Integer;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
    {When True, a leading scale=iw*sar:ih,setsar=1 is added to the ffmpeg
     filter chain so anamorphic sources are output at display dimensions
     instead of the raw storage pixel grid. No-op for SAR=1:1 sources.
     Default False so callers must opt in; settings layers do.}
    RespectAnamorphic: Boolean;
  end;

  {Enum <-> INI-string conversions for TTimestampCorner and TBannerPosition.
   StrToX returns ADefault when the string does not match any known literal,
   matching the StrToIntDef convention. XToStr always returns a recognised
   literal so its output round-trips through StrToX.}
function StrToTimestampCorner(const AValue: string; ADefault: TTimestampCorner): TTimestampCorner;
function TimestampCornerToStr(ACorner: TTimestampCorner): string;
function StrToBannerPosition(const AValue: string; ADefault: TBannerPosition): TBannerPosition;
function BannerPositionToStr(APosition: TBannerPosition): string;
function StrToProgressBarLayout(const AValue: string; ADefault: TProgressBarLayout): TProgressBarLayout;
function ProgressBarLayoutToStr(ALayout: TProgressBarLayout): string;

implementation

uses
  System.SysUtils;

function StrToTimestampCorner(const AValue: string; ADefault: TTimestampCorner): TTimestampCorner;
begin
  if SameText(AValue, 'none') then
    Result := tcNone
  else if SameText(AValue, 'topleft') then
    Result := tcTopLeft
  else if SameText(AValue, 'topright') then
    Result := tcTopRight
  else if SameText(AValue, 'bottomright') then
    Result := tcBottomRight
  else if SameText(AValue, 'bottomleft') then
    Result := tcBottomLeft
  else
    Result := ADefault;
end;

function TimestampCornerToStr(ACorner: TTimestampCorner): string;
begin
  {Exhaustive enumeration so a future TTimestampCorner value triggers a
   compiler hint instead of silently falling through to 'bottomleft'.}
  case ACorner of
    tcNone:
      Result := 'none';
    tcTopLeft:
      Result := 'topleft';
    tcTopRight:
      Result := 'topright';
    tcBottomLeft:
      Result := 'bottomleft';
    tcBottomRight:
      Result := 'bottomright';
  end;
end;

function StrToBannerPosition(const AValue: string; ADefault: TBannerPosition): TBannerPosition;
begin
  if SameText(AValue, 'bottom') then
    Result := bpBottom
  else if SameText(AValue, 'top') then
    Result := bpTop
  else
    Result := ADefault;
end;

function BannerPositionToStr(APosition: TBannerPosition): string;
begin
  case APosition of
    bpTop:
      Result := 'top';
    bpBottom:
      Result := 'bottom';
  end;
end;

function StrToProgressBarLayout(const AValue: string; ADefault: TProgressBarLayout): TProgressBarLayout;
begin
  if SameText(AValue, 'after') then
    Result := pblAfterPanels
  else if SameText(AValue, 'over') then
    Result := pblOverPanels
  else if SameText(AValue, 'auto') then
    Result := pblAuto
  else
    Result := ADefault;
end;

function ProgressBarLayoutToStr(ALayout: TProgressBarLayout): string;
begin
  case ALayout of
    pblAfterPanels:
      Result := 'after';
    pblOverPanels:
      Result := 'over';
    pblAuto:
      Result := 'auto';
  end;
end;

end.
