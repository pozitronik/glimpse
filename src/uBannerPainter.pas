{Stamps an info banner above or below a source bitmap. Owns GDI font-
 fitting, line wrap, and alpha-aware copy. Pure rendering; no I/O.}
unit uBannerPainter;

interface

uses
  System.SysUtils, Vcl.Graphics,
  uTypes, uSettingsGroups;

type
  {AutoSize True picks a width-based font size and shrinks to fit;
   AutoSize False uses FontSize as fixed and wraps overflowing lines.}
  TBannerStyle = record
    Background: TColor;
    TextColor: TColor;
    FontName: string;
    FontSize: Integer;
    AutoSize: Boolean;
    Position: TBannerPosition;
    class function FromSettings(const AGroup: TBannerSettingsGroup): TBannerStyle; static;
  end;

{Empty ALines returns a copy of ASrc. Caller owns the result.}
function AttachBanner(ASrc: TBitmap; const ALines: TArray<string>; const AStyle: TBannerStyle): TBitmap;

implementation

uses
  Winapi.Windows, System.Math, System.Types,
  uDefaults;

type
  {Winapi.Windows declares its own TBITMAP record alias which would
   otherwise shadow Vcl.Graphics.TBitmap.}
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

{Decorative double-spaces around '|' separators collapse to single
 spaces on wrapped lines (accepted to keep all text visible).}
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
      if Current <> '' then
        Result := Result + [Current];

      if ACanvas.TextWidth(Words[I]) <= AMaxW then
        Current := Words[I]
      else
      begin
        Result := Result + [TruncateToFit(ACanvas, Words[I], AMaxW)];
        Current := '';
      end;
    end;
  end;

  if Current <> '' then
    Result := Result + [Current];
end;

{Returns BANNER_FONT_MIN when no size fits — caller should then wrap.}
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

{GDI canvas ops on pf32bit leave the alpha byte untouched (zero for
 freshly-allocated scan lines), so we must stamp it opaque explicitly.}
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

{Canvas.Draw on alpha-aware sources routes through AlphaBlend which
 expects pre-multiplied RGB and corrupts non-pre-multiplied colours.}
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
    {Always return an owned bitmap.}
    Result := TBitmap.Create;
    if ASrc <> nil then
      Result.Assign(ASrc);
    Exit;
  end;

  {Skip degenerate inputs: a sub-20-pixel content area would force every
   word to '...', producing a band of ellipses over a tiny source.}
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

  {Measure on a temp bitmap so the result canvas stays clean during the
   shrink probe.}
  TempBmp := TBitmap.Create;
  try
    TempBmp.Canvas.Font.Name := FontName;

    if AStyle.AutoSize then
      FontSize := FindFittingBannerFontSize(TempBmp.Canvas, ALines, EnsureRange(ASrc.Width div BANNER_FONT_RATIO, BANNER_FONT_MIN, BANNER_FONT_MAX), MaxTextW)
    else
      FontSize := AStyle.FontSize;
    TempBmp.Canvas.Font.Size := FontSize;

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
    {Defer AlphaFormat := afDefined until after the manual copy; while
     afDefined, GDI ops route through AlphaBlend and corrupt colours.}
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

  Result.Canvas.Brush.Color := AStyle.Background;
  Result.Canvas.FillRect(Rect(0, BannerY, Result.Width, BannerY + BannerH));

  Result.Canvas.Font.Name := FontName;
  Result.Canvas.Font.Size := FontSize;
  Result.Canvas.Font.Color := AStyle.TextColor;
  Result.Canvas.Brush.Style := bsClear;
  for I := 0 to High(RenderLines) do
    Result.Canvas.TextOut(BANNER_PADDING_H, BannerY + BANNER_PADDING_V + I * (LineH + BANNER_LINE_GAP), RenderLines[I]);

  if AlphaAware then
  begin
    CopySourceBgraIntoBanner(Result, SrcY, ASrc);
    StampBannerAlpha(Result, BannerY, BannerH);
    Result.AlphaFormat := afDefined;
  end
  else
    Result.Canvas.Draw(0, SrcY, ASrc);
end;

end.
