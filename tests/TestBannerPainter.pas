{ Tests for uBannerPainter: AttachBanner geometry, font fitting, wrap
  behaviour and alpha-aware lift. Verifies the painter handles narrow
  sources, long single-token lines, fixed vs auto font sizing, banner
  position and preserves alpha-aware source content. }
unit TestBannerPainter;

interface

uses
  DUnitX.TestFramework, Vcl.Graphics;

type
  [TestFixture]
  TTestBannerPainter = class
  private
    { Creates a solid-color bitmap for testing }
    function MakeFrame(AWidth, AHeight: Integer; AColor: Integer): TBitmap;
  public
    { AttachBanner }
    [Test] procedure AttachBanner_EmptyLines_ReturnsCopy;
    [Test] procedure AttachBanner_AddsHeightAboveSource;
    [Test] procedure AttachBanner_PreservesSourceContent;
    [Test] procedure AttachBanner_NilSource_ReturnsEmptyBitmap;
    [Test] procedure AttachBanner_NarrowImage_SmallBanner;
    [Test] procedure AttachBanner_WideImage_LargerBanner;
    [Test] procedure AttachBanner_LongLine_PreservesWidth;
    [Test] procedure AttachBanner_LongMultiWordLine_GrowsBannerHeight;
    [Test] procedure AttachBanner_PathologicalSingleToken_HeightStaysBounded;
    [Test] procedure AttachBanner_LongLineDoesNotTruncateToEllipsis;
    {Defensive: a source narrower than 4 x BANNER_PADDING_H has no usable
     content area after horizontal padding. Earlier MaxTextW went negative
     and every word was truncated to '...', producing a banner band of
     ellipses. The guard now skips the banner entirely and returns a
     plain copy at source dimensions.}
    [Test] procedure AttachBanner_NarrowSource_ReturnsBannerlessCopy;
    [Test] procedure AttachBanner_PositionBottom_PreservesTopSource;
    [Test] procedure AttachBanner_FixedFontSize_DiffersFromAutoHeight;
    { Cross-concern: AttachBanner over a pf32bit alpha-aware combined render.
      The setup uses uCombinedGrid for the source bitmap; the assertions
      pin AttachBanner's alpha-aware code path. }
    [Test] procedure AttachBanner_AlphaAwareSource_PreservesGapTransparency;
    [Test] procedure AttachBanner_AlphaAwareSource_PreservesFrameColors;
    { Default* factory helpers for the banner style }
    [Test] procedure DefaultBannerStyle_PopulatesFontAndSize;
    [Test] procedure DefaultBannerStyle_AutoSizeMatchesConstant;
    [Test] procedure DefaultBannerStyle_PositionMatchesConstant;
    { BannerStyle.FromSettings }
    [Test] procedure BannerStyle_FromSettings_CopiesAllSixFields;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.Types, System.UITypes,
  uTypes, uFrameOffsets, uBannerPainter, uCombinedGrid, uTimecodeOverlay,
  uRenderDefaults, uDefaults, uSettingsGroups;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   GetBValue/GetGValue/GetRValue) declares its own TBITMAP record alias
   that would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

{Pixel layout for pf32bit scan lines: byte order is BGRA per Win32 DIB}
function AlphaByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 3);
  Result := Row^;
end;

function BlueByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4);
  Result := Row^;
end;

function GreenByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 1);
  Result := Row^;
end;

function RedByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 2);
  Result := Row^;
end;

{ Helper }

function TTestBannerPainter.MakeFrame(AWidth, AHeight: Integer;
  AColor: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := TColor(AColor);
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{ Positional-arg builders so test call sites stay one-liners. }
function MakeGrid(ACols, AGap: Integer; ABg: TColor; ABorder: Integer = 0): TCombinedGridStyle;
begin
  Result.Columns := ACols;
  Result.CellGap := AGap;
  Result.Border := ABorder;
  Result.Background := ABg;
  {Default to opaque so existing tests pin the historical pf24bit fast
   path; alpha-aware tests set BackgroundAlpha explicitly.}
  Result.BackgroundAlpha := 255;
end;

function MakeTs(AShow: Boolean; const AFontName: string; AFontSize: Integer;
  ACorner: TTimestampCorner = tcBottomLeft;
  ABackColor: TColor = clBlack; ABackAlpha: Byte = 0;
  ATextColor: TColor = clWhite; ATextAlpha: Byte = 255): TTimestampStyle;
begin
  Result.Show := AShow;
  Result.Corner := ACorner;
  Result.FontName := AFontName;
  Result.FontSize := AFontSize;
  Result.FontStyles := [fsBold];
  Result.BackColor := ABackColor;
  Result.BackAlpha := ABackAlpha;
  Result.TextColor := ATextColor;
  Result.TextAlpha := ATextAlpha;
  {Match the historical BackAlpha-as-discriminator so tests that pass
   ABackAlpha=0 still exercise the legacy painter.}
  Result.Mode := TimecodeStyleModeFor(ABackAlpha);
end;

{ AttachBanner }

procedure TTestBannerPainter.AttachBanner_EmptyLines_ReturnsCopy;
var
  Src, R: TBitmap;
  EmptyLines: TArray<string>;
begin
  Src := MakeFrame(100, 80, Integer(clRed));
  try
    SetLength(EmptyLines, 0);
    R := AttachBanner(Src, EmptyLines, DefaultBannerStyle);
    try
      Assert.AreEqual(100, R.Width);
      Assert.AreEqual(80, R.Height);
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_NarrowSource_ReturnsBannerlessCopy;
var
  Src, R: TBitmap;
begin
  {10 px wide is well below 4 * BANNER_PADDING_H (40). The guard skips
   the banner; the result equals the source dimensions exactly.}
  Src := MakeFrame(10, 10, Integer(clGreen));
  try
    R := AttachBanner(Src, ['video.mp4'], DefaultBannerStyle);
    try
      Assert.AreEqual(10, R.Width, 'Bannerless copy keeps source width');
      Assert.AreEqual(10, R.Height,
        'Bannerless copy keeps source height (no banner band added)');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_AddsHeightAboveSource;
var
  Src, R: TBitmap;
begin
  Src := MakeFrame(200, 100, Integer(clBlue));
  try
    R := AttachBanner(Src, ['Line 1', 'Line 2'], DefaultBannerStyle);
    try
      Assert.AreEqual(200, R.Width, 'Width should match source');
      Assert.IsTrue(R.Height > 100, 'Height should exceed source by banner');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_PreservesSourceContent;
var
  Src, R: TBitmap;
  BannerH: Integer;
begin
  Src := MakeFrame(100, 50, Integer(clRed));
  try
    R := AttachBanner(Src, ['Test'], DefaultBannerStyle);
    try
      BannerH := R.Height - 50;
      Assert.IsTrue(BannerH > 0, 'Banner should add height');
      { Check a pixel in the source area (below banner) }
      Assert.AreEqual(Integer(clRed),
        Integer(R.Canvas.Pixels[50, BannerH + 25]),
        'Source content should be preserved below banner');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_NilSource_ReturnsEmptyBitmap;
var
  R: TBitmap;
begin
  R := AttachBanner(nil, ['Line'], DefaultBannerStyle);
  try
    Assert.AreEqual(0, R.Width);
    Assert.AreEqual(0, R.Height);
  finally
    R.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_NarrowImage_SmallBanner;
var
  Narrow, Wide, R1, R2: TBitmap;
  H1, H2: Integer;
begin
  { A narrow image should get a smaller font, hence shorter banner }
  Narrow := MakeFrame(200, 100, Integer(clBlack));
  Wide := MakeFrame(1200, 100, Integer(clBlack));
  try
    R1 := AttachBanner(Narrow, ['Test line'], DefaultBannerStyle);
    R2 := AttachBanner(Wide, ['Test line'], DefaultBannerStyle);
    try
      H1 := R1.Height - 100;
      H2 := R2.Height - 100;
      Assert.IsTrue(H1 > 0, 'Narrow banner should have height');
      Assert.IsTrue(H2 > H1, 'Wide image banner should be taller than narrow');
    finally
      R1.Free;
      R2.Free;
    end;
  finally
    Narrow.Free;
    Wide.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_WideImage_LargerBanner;
var
  Src, R: TBitmap;
  BannerH: Integer;
begin
  { Font size caps at BANNER_FONT_MAX for very wide images }
  Src := MakeFrame(2000, 100, Integer(clBlack));
  try
    R := AttachBanner(Src, ['Line'], DefaultBannerStyle);
    try
      BannerH := R.Height - 100;
      Assert.IsTrue(BannerH > 0, 'Banner should have height');
      Assert.AreEqual(2000, R.Width, 'Width must match source');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_LongLine_PreservesWidth;
var
  Src, R: TBitmap;
  LongText: string;
begin
  { A very long line on a narrow image must never widen the result }
  Src := MakeFrame(200, 100, Integer(clBlack));
  try
    LongText := StringOfChar('W', 500);
    R := AttachBanner(Src, [LongText], DefaultBannerStyle);
    try
      Assert.AreEqual(200, R.Width, 'Width must match source, not expand');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_LongMultiWordLine_GrowsBannerHeight;
var
  Src, RShort, RLong: TBitmap;
  ShortH, LongH, I: Integer;
  LongLine: string;
begin
  { A long multi-word line that exceeds the line width even at min font
    must wrap onto multiple sub-lines, producing a taller banner. }
  Src := MakeFrame(400, 100, Integer(clBlack));
  try
    { Build a long line of plausible-width words; 80 short words guarantees
      overflow even at minimum font on a 400px-wide line. }
    LongLine := '';
    for I := 0 to 79 do
    begin
      if LongLine <> '' then
        LongLine := LongLine + ' ';
      LongLine := LongLine + 'word' + IntToStr(I);
    end;

    RShort := AttachBanner(Src, ['short'], DefaultBannerStyle);
    RLong := AttachBanner(Src, [LongLine], DefaultBannerStyle);
    try
      ShortH := RShort.Height - 100;
      LongH := RLong.Height - 100;
      Assert.IsTrue(LongH > ShortH,
        Format('Wrapped banner (%d) must be taller than single-line banner (%d)',
          [LongH, ShortH]));
      Assert.AreEqual(400, RLong.Width, 'Wrapped banner must not widen image');
    finally
      RShort.Free;
      RLong.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_PathologicalSingleToken_HeightStaysBounded;
var
  Src, RNormal, RPath: TBitmap;
  NormalH, PathH: Integer;
  Token: string;
begin
  { A single 500-char token has no whitespace to wrap on; the wrap helper
    must fall back to ellipsis truncation, leaving the banner height close
    to the unwrapped baseline rather than blowing up. }
  Src := MakeFrame(200, 100, Integer(clBlack));
  try
    Token := StringOfChar('W', 500);
    RNormal := AttachBanner(Src, ['short'], DefaultBannerStyle);
    RPath := AttachBanner(Src, [Token], DefaultBannerStyle);
    try
      NormalH := RNormal.Height - 100;
      PathH := RPath.Height - 100;
      Assert.AreEqual(200, RPath.Width, 'Width must not expand');
      Assert.IsTrue(PathH > 0, 'Banner must have height');
      { The pathological single-token case should produce roughly the same
        height as a one-line banner (1 line, possibly 2 due to ellipsis path
        being created on a fresh "Current" line); 3x baseline is a generous
        upper bound that catches a runaway wrap. }
      Assert.IsTrue(PathH <= NormalH * 3,
        Format('Single-token banner height %d should not exceed 3x baseline %d',
          [PathH, NormalH]));
    finally
      RNormal.Free;
      RPath.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_LongLineDoesNotTruncateToEllipsis;
var
  Src, RShort, RLong: TBitmap;
  ShortH, LongH, I: Integer;
  LongLine: string;
begin
  { Regression for the truncation behavior at "realistic" widths: a 1024px
    image with a long-but-spaced line must wrap, not silently lose text. }
  Src := MakeFrame(1024, 200, Integer(clBlack));
  try
    LongLine := '';
    for I := 0 to 59 do
    begin
      if LongLine <> '' then
        LongLine := LongLine + ' ';
      LongLine := LongLine + 'segment' + IntToStr(I);
    end;

    RShort := AttachBanner(Src, ['short line'], DefaultBannerStyle);
    RLong := AttachBanner(Src, [LongLine], DefaultBannerStyle);
    try
      ShortH := RShort.Height - 200;
      LongH := RLong.Height - 200;
      Assert.IsTrue(LongH > ShortH,
        Format('At 1024px, the long line must wrap or shrink-grow the banner '
          + '(short=%d, long=%d)', [ShortH, LongH]));
      Assert.AreEqual(1024, RLong.Width);
    finally
      RShort.Free;
      RLong.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_PositionBottom_PreservesTopSource;
var
  Src, R: TBitmap;
  Style: TBannerStyle;
  BannerH: Integer;
begin
  { bpBottom must place the banner BELOW the source, so the source pixel
    at (x, 0) is preserved at result (x, 0). }
  Src := MakeFrame(200, 100, Integer(clLime));
  try
    Style := DefaultBannerStyle;
    Style.Position := bpBottom;
    R := AttachBanner(Src, ['Bottom banner'], Style);
    try
      BannerH := R.Height - 100;
      Assert.IsTrue(BannerH > 0, 'Banner should add height');
      Assert.AreEqual(200, R.Width, 'Width must match source');
      Assert.AreEqual(Integer(clLime), Integer(R.Canvas.Pixels[50, 25]),
        'Source content should be preserved at the top when banner is at bottom');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_FixedFontSize_DiffersFromAutoHeight;
var
  Src, RAuto, RFixed: TBitmap;
  Style: TBannerStyle;
  AutoH, FixedH: Integer;
begin
  { A fixed font size must bypass the auto-width heuristic. On a wide image,
    a small fixed font produces a visibly shorter banner than the auto sizing
    would. }
  Src := MakeFrame(1600, 100, Integer(clBlack));
  try
    RAuto := AttachBanner(Src, ['One line'], DefaultBannerStyle);

    Style := DefaultBannerStyle;
    Style.AutoSize := False;
    Style.FontSize := 6;
    RFixed := AttachBanner(Src, ['One line'], Style);
    try
      AutoH := RAuto.Height - 100;
      FixedH := RFixed.Height - 100;
      Assert.IsTrue(AutoH > 0, 'Auto banner should have height');
      Assert.IsTrue(FixedH > 0, 'Fixed banner should have height');
      Assert.IsTrue(FixedH < AutoH,
        Format('Fixed small font (%d) should produce shorter banner than auto (%d)',
          [FixedH, AutoH]));
    finally
      RAuto.Free;
      RFixed.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_AlphaAwareSource_PreservesFrameColors;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Combined, WithBanner: TBitmap;
  Style: TBannerStyle;
  Lines: TArray<string>;
  FrameY: Integer;
begin
  {Regression: AttachBanner used to route the pf32bit -> pf32bit source
   copy through GDI's AlphaBlend, which expects pre-multiplied RGB. Our
   alpha is non-pre-multiplied, so frame colours came out modified
   (effectively dst = src + dst*(1-srcA) instead of a flat copy). This
   test pins that frame interior pixels carry the exact source colours
   through the banner attachment.}
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(20, 20, Integer(clRed)); {clRed = $0000FF: B=0 G=0 R=255}
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 0.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Grid.BackgroundAlpha := 0;
    Combined := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Style := DefaultBannerStyle;
      SetLength(Lines, 1);
      Lines[0] := 'Test banner';
      WithBanner := AttachBanner(Combined, Lines, Style);
      try
        {Frame sits below the banner band: WithBanner.Height - Combined.Height
         is the source band start. Sample the centre of the (only) frame.}
        FrameY := WithBanner.Height - Combined.Height + 10;
        Assert.AreEqual(0, Integer(BlueByteAt(WithBanner, 10, FrameY)),
          'Frame blue must be 0 (clRed)');
        Assert.AreEqual(0, Integer(GreenByteAt(WithBanner, 10, FrameY)),
          'Frame green must be 0 (clRed)');
        Assert.AreEqual(255, Integer(RedByteAt(WithBanner, 10, FrameY)),
          'Frame red must be 255 (clRed); dimmer values mean AlphaBlend mangled colours');
      finally
        WithBanner.Free;
      end;
    finally
      Combined.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestBannerPainter.AttachBanner_AlphaAwareSource_PreservesGapTransparency;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Combined, WithBanner: TBitmap;
  Style: TBannerStyle;
  Lines: TArray<string>;
begin
  {Regression: when ShowBanner is enabled, AttachBanner used to produce a
   pf24bit output and lose the gap transparency built into the combined
   bitmap. Saved combined PNG looked uniformly opaque even at
   BackgroundAlpha=0. The fix makes AttachBanner alpha-aware when its
   source is pf32bit; this test pins the gap pixel's alpha through the
   banner attachment.}
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(20, 20, Integer(clRed));
  Frames[1] := MakeFrame(20, 20, Integer(clGreen));
  SetLength(Offsets, 2);
  Offsets[0].TimeOffset := 0.0;
  Offsets[1].TimeOffset := 1.0;
  try
    Grid := MakeGrid(2, 4, clBlue, 0);
    Grid.BackgroundAlpha := 0;
    Combined := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Style := DefaultBannerStyle;
      SetLength(Lines, 1);
      Lines[0] := 'Test banner';
      WithBanner := AttachBanner(Combined, Lines, Style);
      try
        Assert.AreEqual(Ord(pf32bit), Ord(WithBanner.PixelFormat),
          'Banner output must inherit pf32bit when source is alpha-aware');
        {Banner is at the top by default - gap pixel of source sits below
         banner at Combined.Height + a few rows.}
        Assert.AreEqual(0, Integer(AlphaByteAt(WithBanner, 21,
          WithBanner.Height - Combined.Height + 10)),
          'Gap pixel alpha must survive AttachBanner unchanged');
      finally
        WithBanner.Free;
      end;
    finally
      Combined.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestBannerPainter.DefaultBannerStyle_PopulatesFontAndSize;
var
  S: TBannerStyle;
begin
  S := DefaultBannerStyle;
  Assert.AreNotEqual('', S.FontName,
    'Banner default must name a font; empty defers to Canvas default which is fragile');
  Assert.IsTrue(S.FontSize > 0, 'Banner default font size must be positive');
  Assert.AreEqual(TColor(DEF_BANNER_BACKGROUND), S.Background);
  Assert.AreEqual(TColor(DEF_BANNER_TEXT_COLOR), S.TextColor);
  Assert.AreEqual(DEF_BANNER_FONT_NAME, S.FontName);
  Assert.AreEqual<Integer>(DEF_BANNER_FONT_SIZE, S.FontSize);
end;

procedure TTestBannerPainter.DefaultBannerStyle_AutoSizeMatchesConstant;
begin
  {AutoSize flips the banner between width-heuristic + shrink-to-fit
   (True) and fixed-size + wrap (False). The dialogs rely on the
   documented default shipping as True.}
  Assert.AreEqual(DEF_BANNER_FONT_AUTO_SIZE, DefaultBannerStyle.AutoSize);
end;

procedure TTestBannerPainter.DefaultBannerStyle_PositionMatchesConstant;
begin
  Assert.AreEqual(Ord(DEF_BANNER_POSITION),
    Ord(DefaultBannerStyle.Position));
end;

procedure TTestBannerPainter.BannerStyle_FromSettings_CopiesAllSixFields;
var
  Group: TBannerSettingsGroup;
  Style: TBannerStyle;
begin
  Group := TBannerSettingsGroup.Defaults;
  {Mutate every field away from the default so a missed copy in the
   factory would surface as a failed assertion rather than passing on
   the default value.}
  Group.Background := clNavy;
  Group.TextColor := clYellow;
  Group.FontName := 'Tahoma';
  Group.FontSize := 13;
  Group.AutoSize := False;
  Group.Position := bpBottom;

  Style := TBannerStyle.FromSettings(Group);
  Assert.AreEqual(TColor(clNavy), Style.Background);
  Assert.AreEqual(TColor(clYellow), Style.TextColor);
  Assert.AreEqual('Tahoma', Style.FontName);
  Assert.AreEqual<Integer>(13, Style.FontSize);
  Assert.IsFalse(Style.AutoSize);
  Assert.AreEqual(Ord(bpBottom), Ord(Style.Position));
end;

end.
