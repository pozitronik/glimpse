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

  {Window-mode gate for the configurable StatusBarHeight setting. When
   the user has an explicit height, this enum decides in which window
   modes the override actually applies. Quick View opens the same form
   in a restricted child window (WS_CHILD), so a per-mode toggle lets
   users keep e.g. a chunky lister bar while Quick View keeps the
   font-derived default.

   Order is load-bearing: TPluginSettings.StatusBarHeightApplyMode is
   stored as a token string via StatusBarHeightApplyModeToStr; the
   settings dialog combo's ItemIndex matches Ord(enum) so reordering
   would silently pick the wrong mode on the next dialog open.}
  TStatusBarHeightApplyMode = (sbhamLister, sbhamQuickView, sbhamBoth);

  {Result of ResolveProgressBarBounds: bounds the host should pass
   straight to SetBounds for the progress bar inside the status bar.}
  TProgressBarBounds = record
    Left, Top, Width, Height: Integer;
  end;

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
function StrToStatusBarHeightApplyMode(const AValue: string; ADefault: TStatusBarHeightApplyMode): TStatusBarHeightApplyMode;
function StatusBarHeightApplyModeToStr(AMode: TStatusBarHeightApplyMode): string;

{Returns True iff a custom StatusBarHeight value should be applied for
 a window currently running in AIsQuickView mode (False = normal Lister
 child of TC's main lister window). Pure decision function with no VCL
 dependency so it stays testable; the form passes its own FQuickViewMode.}
function ShouldApplyStatusBarHeight(AMode: TStatusBarHeightApplyMode;
  AIsQuickView: Boolean): Boolean;

{Resolves the final pixel height of the status bar from the four inputs
 that drive the policy. Pure: no VCL access, callable from tests.

 - ATextHeightPx: GDI height of the configured font (ascender+descender,
   typically measured against 'Hg').
 - ASettingPx: the user's logical setting in 96-DPI pixels. <=0 means
   "auto" (always falls back to font-derived height).
 - AApplyMode + AIsQuickView: gate that lets the user restrict the
   custom height to one window mode; outside that mode this routine
   silently falls back to auto.
 - APpi: the panel's effective DPI for MulDiv scaling. <=0 normalises
   to 96 so callers can safely pass 0 when CurrentPPI isn't available.

 The auto height adds STATUSBAR_VPADDING (6 px) above the font reach so
 text breathes. An explicit setting smaller than the font reach silently
 bumps to font height + STATUSBAR_FONT_MIN_PADDING (2 px) — anything
 less would clip text, which is never what the user actually wants.
 The 2-vs-6 px asymmetry is deliberate: explicit mode can produce a
 tighter bar than auto when the font allows.}
function ResolveStatusBarHeightPixels(ATextHeightPx, ASettingPx: Integer;
  AApplyMode: TStatusBarHeightApplyMode; AIsQuickView: Boolean;
  APpi: Integer): Integer;

{Resolves the position + dimensions of the progress bar inside the
 status bar. Pure: no VCL touch.

 Layout policy:
 - AStretchPanelsOn forces pblOverPanels regardless of ARequestedLayout
   (a stretched-panels bar has no trailing slack to dock against).
 - pblAuto picks pblAfterPanels when ClientWidth has room for both the
   panels and AMinWidth + two margins; otherwise pblOverPanels.
 - pblAfterPanels positions the bar to the right of the panels; if the
   available width is below AMinWidth, the width is clamped up (the bar
   will visually overlap the rightmost panel, intentional fallback).
 - pblOverPanels paints the bar across the full client width minus
   two margins on each side, vertically inset by AMargin top and bottom.}
function ResolveProgressBarBounds(AClientWidth, AClientHeight, APanelsRight: Integer;
  AStretchPanelsOn: Boolean; ARequestedLayout: TProgressBarLayout;
  AMinWidth, AMargin: Integer): TProgressBarBounds;

implementation

uses
  System.SysUtils, Winapi.Windows;

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

function StrToStatusBarHeightApplyMode(const AValue: string;
  ADefault: TStatusBarHeightApplyMode): TStatusBarHeightApplyMode;
begin
  if SameText(AValue, 'lister') then
    Result := sbhamLister
  else if SameText(AValue, 'quickview') then
    Result := sbhamQuickView
  else if SameText(AValue, 'both') then
    Result := sbhamBoth
  else
    Result := ADefault;
end;

function StatusBarHeightApplyModeToStr(AMode: TStatusBarHeightApplyMode): string;
begin
  case AMode of
    sbhamLister:    Result := 'lister';
    sbhamQuickView: Result := 'quickview';
    sbhamBoth:      Result := 'both';
  end;
end;

function ShouldApplyStatusBarHeight(AMode: TStatusBarHeightApplyMode;
  AIsQuickView: Boolean): Boolean;
begin
  case AMode of
    sbhamBoth:      Result := True;
    sbhamLister:    Result := not AIsQuickView;
    sbhamQuickView: Result := AIsQuickView;
  else
    Result := True;
  end;
end;

function ResolveStatusBarHeightPixels(ATextHeightPx, ASettingPx: Integer;
  AApplyMode: TStatusBarHeightApplyMode; AIsQuickView: Boolean;
  APpi: Integer): Integer;
const
  STATUSBAR_VPADDING = 6;
  STATUSBAR_FONT_MIN_PADDING = 2;
var
  AutoHeight, Ppi, ExplicitHeight, MinHeight: Integer;
begin
  AutoHeight := ATextHeightPx + STATUSBAR_VPADDING;
  if not ShouldApplyStatusBarHeight(AApplyMode, AIsQuickView) then
    Exit(AutoHeight);
  if ASettingPx <= 0 then
    Exit(AutoHeight);
  Ppi := APpi;
  if Ppi <= 0 then
    Ppi := 96;
  ExplicitHeight := MulDiv(ASettingPx, Ppi, 96);
  MinHeight := ATextHeightPx + STATUSBAR_FONT_MIN_PADDING;
  if ExplicitHeight < MinHeight then
    Result := MinHeight
  else
    Result := ExplicitHeight;
end;

function ResolveProgressBarBounds(AClientWidth, AClientHeight, APanelsRight: Integer;
  AStretchPanelsOn: Boolean; ARequestedLayout: TProgressBarLayout;
  AMinWidth, AMargin: Integer): TProgressBarBounds;
var
  Layout: TProgressBarLayout;
begin
  if AStretchPanelsOn then
    Layout := pblOverPanels
  else
    Layout := ARequestedLayout;
  if Layout = pblAuto then
  begin
    if AClientWidth >= APanelsRight + AMinWidth + 2 * AMargin then
      Layout := pblAfterPanels
    else
      Layout := pblOverPanels;
  end;

  case Layout of
    pblAfterPanels:
      begin
        Result.Left := APanelsRight + AMargin;
        Result.Width := AClientWidth - APanelsRight - 2 * AMargin;
        if Result.Width < AMinWidth then
          Result.Width := AMinWidth;
      end;
    else
      Result.Left := AMargin;
      Result.Width := AClientWidth - 2 * AMargin;
  end;
  Result.Top := AMargin;
  Result.Height := AClientHeight - 2 * AMargin;
end;

end.
