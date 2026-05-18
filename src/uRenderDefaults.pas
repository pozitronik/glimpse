{Default-style fabricators for the combined-image renderer.

 These were originally housed in uCombinedImage alongside the rendering
 procedures, but they only consume uDefaults constants and emit value
 records — they have no rendering knowledge. Hoisting them lets the
 renderer be leaf-rendering only and lets test code import "give me a
 default style" without dragging in pf32bit bitmap construction and the
 GDI AlphaBlend stack uCombinedImage carries.

 No internal state; functions are pure. The records returned
 (TBannerStyle, TCombinedGridStyle, TTimestampStyle) are still defined
 in uCombinedImage — moving the types is a separate concern.}
unit uRenderDefaults;

interface

uses
  Vcl.Graphics,
  uCombinedImage;

{Returns the historical defaults (dark bg, light text, Segoe UI, auto size, top).
 Useful for tests and as a fallback when a caller has no configured style.}
function DefaultBannerStyle: TBannerStyle;

{Returns the historical defaults for the grid layout (auto columns, no gap,
 no border, black background). Callers override individual fields as needed.}
function DefaultCombinedGridStyle: TCombinedGridStyle;

{Returns the historical defaults for the timestamp overlay (hidden, bottom-left,
 Consolas 9pt, black legacy-shadow background, white text). Callers override
 individual fields as needed.}
function DefaultTimestampStyle: TTimestampStyle;

implementation

uses
  System.UITypes,
  uDefaults;

function DefaultBannerStyle: TBannerStyle;
begin
  Result.Background := DEF_BANNER_BACKGROUND;
  Result.TextColor := DEF_BANNER_TEXT_COLOR;
  Result.FontName := DEF_BANNER_FONT_NAME;
  Result.FontSize := DEF_BANNER_FONT_SIZE;
  Result.AutoSize := DEF_BANNER_FONT_AUTO_SIZE;
  Result.Position := DEF_BANNER_POSITION;
end;

function DefaultCombinedGridStyle: TCombinedGridStyle;
begin
  Result.Columns := 0;
  Result.CellGap := 0;
  Result.Border := DEF_COMBINED_BORDER;
  Result.Background := clBlack;
  Result.BackgroundAlpha := DEF_BACKGROUND_ALPHA;
end;

function DefaultTimestampStyle: TTimestampStyle;
begin
  Result.Show := False;
  Result.Corner := DEF_TIMESTAMP_CORNER;
  Result.FontName := 'Consolas';
  Result.FontSize := 9;
  Result.FontStyles := [fsBold];
  Result.BackColor := DEF_TC_BACK_COLOR;
  Result.BackAlpha := 0;
  Result.TextColor := DEF_TIMESTAMP_TEXT_COLOR;
  Result.TextAlpha := DEF_TIMESTAMP_TEXT_ALPHA;
  {Historic default matches the WLX 1.0.x legacy renderer for back-compat
   with saved combined sheets; the modern rect-based path is opt-in via
   the explicit Mode field.}
  Result.Mode := tsmLegacy;
end;

end.
