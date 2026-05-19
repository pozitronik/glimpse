{Default-style fabricators for the combined-image renderer. Pure
 functions over Defaults constants; lets tests build styles without
 importing the GDI rendering stack.}
unit RenderDefaults;

interface

uses
  Vcl.Graphics,
  BannerPainter, CombinedGrid, TimecodeOverlay;

function DefaultBannerStyle: TBannerStyle;

function DefaultCombinedGridStyle: TCombinedGridStyle;

function DefaultTimestampStyle: TTimestampStyle;

implementation

uses
  System.UITypes,
  Defaults;

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
  {Legacy renderer for back-compat with saved combined sheets; modern
   rect-based path is opt-in via Mode.}
  Result.Mode := tsmLegacy;
end;

end.
