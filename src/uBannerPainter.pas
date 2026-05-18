{Banner painter: turns text lines + style into a bitmap above/below the
 source. Owns the GDI font-fitting, line-wrap, and alpha-aware lift logic
 the WLX/WCX renderers rely on to stamp the info banner onto a saved
 combined sheet. Pure rendering: no I/O, no settings storage.}
unit uBannerPainter;

interface

uses
  System.SysUtils, Vcl.Graphics,
  uTypes, uSettingsGroups;

type
  {Visual style and placement for the info banner. When AutoSize is True the
   renderer picks a font size using the historical width-based heuristic and
   shrinks to fit; when False it uses FontSize as a fixed point size and wraps
   overflowing lines instead of shrinking.}
  TBannerStyle = record
    Background: TColor;
    TextColor: TColor;
    FontName: string;
    FontSize: Integer;
    AutoSize: Boolean;
    Position: TBannerPosition;
    {Builds the banner style from the persisted settings group. The
     group's Show field is a gating concern (caller decides whether to
     render the banner at all) and intentionally has no parallel in the
     style record.}
    class function FromSettings(const AGroup: TBannerSettingsGroup): TBannerStyle; static;
  end;

{Attaches a solid-color info banner above or below an existing bitmap.
 @param ASrc Source bitmap (not freed; caller still owns it)
 @param ALines Text lines to display (empty array = no banner, returns copy of ASrc)
 @param AStyle Colors, font, and placement (top/bottom)
 @return New bitmap with banner attached. Caller owns result.}
function AttachBanner(ASrc: TBitmap; const ALines: TArray<string>; const AStyle: TBannerStyle): TBitmap;

implementation

uses
  Winapi.Windows, System.Math, System.Types,
  uDefaults;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   GDI calls) declares its own TBITMAP record alias that would
   otherwise shadow Vcl.Graphics.TBitmap throughout this implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

const
  BANNER_PADDING_H = 10; {horizontal padding}
  BANNER_PADDING_V = 6; {vertical padding (top and bottom)}
  BANNER_LINE_GAP = 2; {extra spacing between lines}
  BANNER_FONT_MIN = 8; {minimum font size for auto-scale}
  BANNER_FONT_MAX = 16; {maximum font size for auto-scale}
  BANNER_FONT_RATIO = 55; {image width divisor for auto-scale font size}
  BANNER_ELLIPSIS = '...';

class function TBannerStyle.FromSettings(const AGroup: TBannerSettingsGroup): TBannerStyle;
begin
  Result.Background := AGroup.Background;
  Result.TextColor := AGroup.TextColor;
  Result.FontName := AGroup.FontName;
  Result.FontSize := AGroup.FontSize;
  Result.AutoSize := AGroup.AutoSize;
  Result.Position := AGroup.Position;
end;

{Truncates text to fit within MaxW pixels, appending ellipsis if needed}
function TruncateToFit(ACanvas: TCanvas; const AText: string; AMaxW: Integer): string;
var
  Len: Integer;
  EllW: Integer;
begin
  if ACanvas.TextWidth(AText) <= AMaxW then
    Exit(AText);

  EllW := ACanvas.TextWidth(BANNER_ELLIPSIS);
  Len := Length(AText);
  while (Len > 0) and (ACanvas.TextWidth(Copy(AText, 1, Len)) + EllW > AMaxW) do
    Dec(Len);
  Result := Copy(AText, 1, Len) + BANNER_ELLIPSIS;
end;

{Word-wraps AText into lines that each fit within AMaxW at the canvas's
 current font. Splits on whitespace and rejoins with single spaces, so the
 decorative double-spaces around '|' separators collapse on wrapped lines
 (an acceptable cost for keeping all text visible). A single token wider
 than AMaxW is character-truncated with ellipsis.}
function WrapTextToLines(ACanvas: TCanvas; const AText: string; AMaxW: Integer): TArray<string>;
var
  Words: TArray<string>;
  Current, Test: string;
  I: Integer;
begin
  if ACanvas.TextWidth(AText) <= AMaxW then
  begin
    SetLength(Result, 1);
    Result[0] := AText;
    Exit;
  end;

  Words := AText.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := AText;
    Exit;
  end;

  SetLength(Result, 0);
  Current := '';
  for I := 0 to High(Words) do
  begin
    if Current = '' then
      Test := Words[I]
    else
      Test := Current + ' ' + Words[I];

    if ACanvas.TextWidth(Test) <= AMaxW then
      Current := Test
    else
    begin
      {Flush the in-progress line if any, then place this word on a new line}
      if Current <> '' then
        Result := Result + [Current];

      if ACanvas.TextWidth(Words[I]) <= AMaxW then
        Current := Words[I]
      else
      begin
        {Pathological: a single token wider than the line - truncate it}
        Result := Result + [TruncateToFit(ACanvas, Words[I], AMaxW)];
        Current := '';
      end;
    end;
  end;

  if Current <> '' then
    Result := Result + [Current];
end;

{Returns the largest font size in [BANNER_FONT_MIN, AInitial] at which every
 line in ALines fits within AMaxW. Returns BANNER_FONT_MIN when no size in
 the range fits - the caller should then wrap overflowing lines.}
function FindFittingBannerFontSize(ACanvas: TCanvas; const ALines: TArray<string>; AInitial, AMaxW: Integer): Integer;
var
  Size, I: Integer;
  Fits: Boolean;
begin
  for Size := AInitial downto BANNER_FONT_MIN do
  begin
    ACanvas.Font.Size := Size;
    Fits := True;
    for I := 0 to High(ALines) do
      if ACanvas.TextWidth(ALines[I]) > AMaxW then
      begin
        Fits := False;
        Break;
      end;
    if Fits then
      Exit(Size);
  end;
  Result := BANNER_FONT_MIN;
end;

{Forces every pixel in the banner band to alpha=255 so the GDI banner
 background and text show up opaque. GDI canvas operations on a pf32bit
 bitmap leave the alpha byte at whatever the destination held (zero for
 freshly-allocated scan lines).}
procedure StampBannerAlpha(ABmp: TBitmap; AY, AHeight: Integer);
var
  X, Y: Integer;
  Row: PByte;
begin
  for Y := AY to AY + AHeight - 1 do
  begin
    if (Y < 0) or (Y >= ABmp.Height) then
      Continue;
    Row := PByte(ABmp.ScanLine[Y]);
    Inc(Row, 3); {alpha byte of pixel 0}
    for X := 0 to ABmp.Width - 1 do
    begin
      Row^ := 255;
      Inc(Row, 4);
    end;
  end;
end;

{Byte-for-byte BGRA copy of ASrc into ABmp at vertical offset AY. Replaces
 Canvas.Draw for the pf32bit->pf32bit case: Canvas.Draw on alpha-aware
 sources routes through AlphaBlend, which expects pre-multiplied RGB and
 corrupts colour values when the source is plain non-pre-multiplied
 (which is what the saver and PNG format both want).}
procedure CopySourceBgraIntoBanner(ABmp: TBitmap; AY: Integer; ASrc: TBitmap);
var
  Y, RowBytes: Integer;
  DstRow, SrcRow: PByte;
begin
  RowBytes := ASrc.Width * 4;
  for Y := 0 to ASrc.Height - 1 do
  begin
    if (AY + Y < 0) or (AY + Y >= ABmp.Height) then
      Continue;
    DstRow := PByte(ABmp.ScanLine[AY + Y]);
    SrcRow := PByte(ASrc.ScanLine[Y]);
    Move(SrcRow^, DstRow^, RowBytes);
  end;
end;

function AttachBanner(ASrc: TBitmap; const ALines: TArray<string>; const AStyle: TBannerStyle): TBitmap;
var
  FontSize, LineH, BannerH, MaxTextW, BannerY, SrcY, I: Integer;
  TempBmp: TBitmap;
  Wrapped, RenderLines: TArray<string>;
  FontName: string;
  AlphaAware: Boolean;
begin
  if (Length(ALines) = 0) or (ASrc = nil) then
  begin
    {Return a copy so the caller always gets an owned bitmap}
    Result := TBitmap.Create;
    if ASrc <> nil then
      Result.Assign(ASrc);
    Exit;
  end;

  {Defensive: a source narrower than 4 * BANNER_PADDING_H has at most a
   sub-20-pixel content area after subtracting the horizontal padding on
   both sides. Earlier this produced a negative MaxTextW that drove
   FindFittingBannerFontSize and WrapTextToLines into pathological
   branches: every word truncated to '...', producing a banner band of
   ellipses on top of the tiny source. The legitimate WLX/WCX flows
   never feed inputs this small; treat them as degenerate and skip the
   banner entirely.}
  if ASrc.Width < 4 * BANNER_PADDING_H then
  begin
    Result := TBitmap.Create;
    Result.Assign(ASrc);
    Exit;
  end;

  FontName := AStyle.FontName;
  if FontName.Trim = '' then
    FontName := DEF_BANNER_FONT_NAME;
  MaxTextW := ASrc.Width - 2 * BANNER_PADDING_H;

  {Measure on a temp bitmap so the result canvas isn't dirtied with
   intermediate font states during the shrink probe.}
  TempBmp := TBitmap.Create;
  try
    TempBmp.Canvas.Font.Name := FontName;

    if AStyle.AutoSize then
      {Auto mode: historical width-based ratio, then shrink until every
       line fits (or bottom out at BANNER_FONT_MIN and rely on wrapping).}
      FontSize := FindFittingBannerFontSize(TempBmp.Canvas, ALines, EnsureRange(ASrc.Width div BANNER_FONT_RATIO, BANNER_FONT_MIN, BANNER_FONT_MAX), MaxTextW)
    else
      {Fixed mode: user-chosen size; overflow is handled by wrapping only.}
      FontSize := AStyle.FontSize;
    TempBmp.Canvas.Font.Size := FontSize;

    {Build the final render list: pass each line through the wrapper,
     which is a no-op for lines that already fit.}
    RenderLines := [];
    for I := 0 to High(ALines) do
    begin
      Wrapped := WrapTextToLines(TempBmp.Canvas, ALines[I], MaxTextW);
      RenderLines := RenderLines + Wrapped;
    end;

    LineH := TempBmp.Canvas.TextHeight('Wg');
  finally
    TempBmp.Free;
  end;

  BannerH := BANNER_PADDING_V + Length(RenderLines) * (LineH + BANNER_LINE_GAP) - BANNER_LINE_GAP + BANNER_PADDING_V;

  AlphaAware := ASrc.PixelFormat = pf32bit;
  Result := TBitmap.Create;
  if AlphaAware then
    {Defer setting AlphaFormat: while it is afDefined, GDI canvas
     operations would route through AlphaBlend, which corrupts non-pre-
     multiplied colour values. Set it at the end after every byte is
     where we want it.}
    Result.PixelFormat := pf32bit
  else
    Result.PixelFormat := pf24bit;
  Result.SetSize(ASrc.Width, BannerH + ASrc.Height);

  if AStyle.Position = bpBottom then
  begin
    SrcY := 0;
    BannerY := ASrc.Height;
  end else begin
    BannerY := 0;
    SrcY := BannerH;
  end;

  {Draw banner background}
  Result.Canvas.Brush.Color := AStyle.Background;
  Result.Canvas.FillRect(Rect(0, BannerY, Result.Width, BannerY + BannerH));

  {Draw text lines (already fitted by shrink + wrap; no truncation pass)}
  Result.Canvas.Font.Name := FontName;
  Result.Canvas.Font.Size := FontSize;
  Result.Canvas.Font.Color := AStyle.TextColor;
  Result.Canvas.Brush.Style := bsClear;
  for I := 0 to High(RenderLines) do
    Result.Canvas.TextOut(BANNER_PADDING_H, BannerY + BANNER_PADDING_V + I * (LineH + BANNER_LINE_GAP), RenderLines[I]);

  if AlphaAware then
  begin
    {Manual BGRA copy keeps source colours and alpha bit-identical;
     bypasses AlphaBlend's premultiplied-source assumption.}
    CopySourceBgraIntoBanner(Result, SrcY, ASrc);
    {GDI canvas left the banner band's alpha at zero; stamp it opaque.}
    StampBannerAlpha(Result, BannerY, BannerH);
    Result.AlphaFormat := afDefined;
  end
  else
    {Existing pf24bit fast path}
    Result.Canvas.Draw(0, SrcY, ASrc);
end;

end.
