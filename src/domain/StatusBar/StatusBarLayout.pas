{Status-bar layout policy: progress-bar bounds and configurable bar height.}
unit StatusBarLayout;

interface

uses
  System.SysUtils;

type
  {AfterPanels reserves space to the right of the panels (legacy; bar
   can vanish off-screen in narrow windows). OverPanels paints full-width
   on top of panels. Auto picks AfterPanels when there's room, otherwise
   OverPanels.}
  TProgressBarLayout = (pblAfterPanels, pblOverPanels, pblAuto);

  {Window-mode gate for the configurable StatusBarHeight setting. Quick
   View opens the same form in a WS_CHILD window; this per-mode toggle
   lets users keep a custom lister height while Quick View uses the
   font-derived default.

   Order is load-bearing: serialised via StatusBarHeightApplyModeToStr,
   and the settings combo's ItemIndex matches Ord(enum). Reordering
   would silently pick the wrong mode on next dialog open.}
  TStatusBarHeightApplyMode = (sbhamLister, sbhamQuickView, sbhamBoth);

  TProgressBarBounds = record
    Left, Top, Width, Height: Integer;
  end;

function StrToProgressBarLayout(const AValue: string; ADefault: TProgressBarLayout): TProgressBarLayout;
function ProgressBarLayoutToStr(ALayout: TProgressBarLayout): string;
function StrToStatusBarHeightApplyMode(const AValue: string;
  ADefault: TStatusBarHeightApplyMode): TStatusBarHeightApplyMode;
function StatusBarHeightApplyModeToStr(AMode: TStatusBarHeightApplyMode): string;

function ShouldApplyStatusBarHeight(AMode: TStatusBarHeightApplyMode;
  AIsQuickView: Boolean): Boolean;

{Pure: no VCL. ASettingPx <= 0 means auto (font-derived). APpi <= 0
 normalises to 96. Explicit heights below the font reach are bumped to
 ATextHeightPx + 2 px to avoid clipping.}
function ResolveStatusBarHeightPixels(ATextHeightPx, ASettingPx: Integer;
  AApplyMode: TStatusBarHeightApplyMode; AIsQuickView: Boolean;
  APpi: Integer): Integer;

{Pure: no VCL. AStretchPanelsOn forces pblOverPanels (no slack to dock
 against). pblAuto picks pblAfterPanels when ClientWidth has room for
 panels + AMinWidth + 2*AMargin; otherwise pblOverPanels. pblAfterPanels
 clamps width up to AMinWidth when space is tight — the bar visually
 overlaps the rightmost panel as an intentional fallback.}
function ResolveProgressBarBounds(AClientWidth, AClientHeight, APanelsRight: Integer;
  AStretchPanelsOn: Boolean; ARequestedLayout: TProgressBarLayout;
  AMinWidth, AMargin: Integer): TProgressBarBounds;

implementation

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
  {+48 nudges the integer division to round half-up for positive operands,
   matching MulDiv without dragging in Winapi.Windows.}
  ExplicitHeight := (ASettingPx * Ppi + 48) div 96;
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
