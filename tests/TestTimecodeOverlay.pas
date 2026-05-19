{ Tests for uTimecodeOverlay: TTimestampStyle, mode dispatch,
  DrawCellTimecode short-circuit gates, and painter selection
  (legacy vs modern). The combined-grid integration tests that
  exercise the overlay through RenderCombinedImage live here so the
  full overlay behaviour is in one file. }
unit TestTimecodeOverlay;

interface

uses
  DUnitX.TestFramework, Vcl.Graphics;

type
  [TestFixture]
  TTestTimecodeOverlay = class
  private
    { Creates a solid-color bitmap for testing }
    function MakeFrame(AWidth, AHeight: Integer; AColor: Integer): TBitmap;
  public
    { Timestamp overlay (integration via uniform grid: no crash, correct pixel format) }
    [Test] procedure TimestampEnabled_DoesNotCrash;
    [Test] procedure TimestampDisabled_NoTextDrawn;
    { Timestamp corner placement }
    [Test] procedure TimestampCorner_TopLeft_LeavesBottomRightClean;
    [Test] procedure TimestampCorner_BottomRight_LeavesTopLeftClean;
    [Test] procedure TimestampCorner_DefaultIsBottomLeft;
    { Timecode background block and text alpha (parity with live-view overlay) }
    [Test] procedure TimecodeBack_OpaqueBg_PaintsConfiguredColorAtCorner;
    [Test] procedure TimecodeBack_OpaqueBg_TextAlphaZero_LeavesBgIntact;
    [Test] procedure TimestampText_LegacyPath_UsesConfiguredColor;
    { DefaultTimestampStyle invariants }
    [Test] procedure DefaultTimestampStyle_ShowDefaultsOff;
    [Test] procedure DefaultTimestampStyle_FontAndSize;
    [Test] procedure DefaultTimestampStyle_CornerMatchesConstant;
    {Mode discriminator: now explicit (was inferred from BackAlpha=0).
     The default targets the legacy painter so pre-Mode saved sheets
     re-render identically.}
    [Test] procedure DefaultTimestampStyle_ModeIsLegacy;
    {TimecodeStyleModeFor preserves the historical sentinel: BackAlpha=0
     -> legacy, anything else -> modern. Keeps settings-driven
     construction sites behaviour-equivalent.}
    [Test] procedure ModeForZeroBackAlpha_IsLegacy;
    [Test] procedure ModeForOneBackAlpha_IsModern;
    [Test] procedure ModeFor255BackAlpha_IsModern;
    {Style-record factory pins the field-for-field mapping plus the
     derived Mode contract.}
    [Test] procedure TimestampStyle_FromSettings_CopiesGroupFields;
    [Test] procedure TimestampStyle_FromSettings_DefaultsFontStylesEmpty;
    [Test] procedure TimestampStyle_FromSettings_DerivesModeFromBackAlpha;
    {Painter dispatch: confirm DrawCellTimecode reaches the legacy
     branch when Mode=tsmLegacy AND the modern branch when
     Mode=tsmModern, regardless of BackAlpha. The pixel-set signature
     differs between the two algorithms (legacy paints a 4px-inset
     shadowed glyph stack; modern paints a full-width rect when
     BackAlpha>0) so we can distinguish them by counting marker pixels
     in regions where only one algorithm writes.}
    [Test] procedure ModeLegacy_DoesNotPaintTopLeftCornerPixel;
    [Test] procedure ModeModern_WithOpaqueBg_FillsCornerStripWithBackColor;
  end;

  {Direct tests for DrawCellTimecode. Exercised indirectly via the
   renderers in TTestTimecodeOverlay; this fixture pins the early-exit
   gates (Show=False / Corner=tcNone) at the unit level so a future
   "always draw" regression cannot slip past renderer smoke tests.}
  [TestFixture]
  TTestDrawCellTimecode = class
  public
    [Test] procedure ShowFalse_NoPixelsTouched;
    [Test] procedure ShowTrueCornerNone_NoPixelsTouched;
    [Test] procedure ShowTrueValidCorner_DrawsSomething;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.Types, System.UITypes,
  uTypes, uFrameOffsets, uCombinedGrid, uTimecodeOverlay, uRenderDefaults,
  uDefaults, uSettingsGroups;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   GetBValue/GetGValue/GetRValue) declares its own TBITMAP record alias
   that would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

{ Helper }

function TTestTimecodeOverlay.MakeFrame(AWidth, AHeight: Integer;
  AColor: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := TColor(AColor);
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{ Positional-arg builders so the pre-DTO test call sites stay one-liners.
  Match the old RenderCombinedImage parameter order/defaults exactly. }
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

{ Timestamp }

procedure TTestTimecodeOverlay.TimestampEnabled_DoesNotCrash;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, 0);
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(True, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(pf24bit, R.PixelFormat);
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestTimecodeOverlay.TimestampDisabled_NoTextDrawn;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  WithoutTS: TBitmap;
begin
  { Render same frame with and without timestamps.
    Without timestamps, the bottom-left corner should match the frame color. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clBlue));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 10.0;
  try
    WithoutTS := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(WithoutTS);
    try
      { Bottom-left pixel should be the frame color when no timestamp }
      Assert.AreEqual(Integer(clBlue),
        Integer(WithoutTS.Canvas.Pixels[5, 140]),
        'Frame pixel without timestamp should be original color');
    finally
      WithoutTS.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Timestamp corner placement }

procedure TTestTimecodeOverlay.TimestampCorner_TopLeft_LeavesBottomRightClean;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { With timestamp in the top-left corner, the bottom-right of the cell
    must be untouched (original frame color). This proves the corner
    parameter actually routes the placement, not just the fallback }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(True, 'Consolas', 12, tcTopLeft));
    Assert.IsNotNull(R);
    try
      { Bottom-right corner of the only cell: frame is 200x150, cell is at (0,0) }
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[195, 145]),
        'Bottom-right of cell must remain frame color when timestamp is top-left');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestTimecodeOverlay.TimestampCorner_BottomRight_LeavesTopLeftClean;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Symmetric to the previous test: timestamp in bottom-right, so the
    top-left of the cell must stay frame color }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(True, 'Consolas', 12, tcBottomRight));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[5, 5]),
        'Top-left of cell must remain frame color when timestamp is bottom-right');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestTimecodeOverlay.TimestampCorner_DefaultIsBottomLeft;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RDefault, RExplicit: TBitmap;
  X, Y: Integer;
  Equal: Boolean;
begin
  { Back-compat guarantee: omitting the corner parameter must produce the
    same pixels as passing tcBottomLeft explicitly }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    RDefault := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(True, 'Consolas', 12));
    RExplicit := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(True, 'Consolas', 12, tcBottomLeft));
    try
      Assert.AreEqual(RExplicit.Width, RDefault.Width);
      Assert.AreEqual(RExplicit.Height, RDefault.Height);
      Equal := True;
      for Y := 0 to RDefault.Height - 1 do
        for X := 0 to RDefault.Width - 1 do
          if RDefault.Canvas.Pixels[X, Y] <> RExplicit.Canvas.Pixels[X, Y] then
          begin
            Equal := False;
            Break;
          end;
      Assert.IsTrue(Equal, 'Default corner must render identically to tcBottomLeft');
    finally
      RDefault.Free;
      RExplicit.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Timecode background block and text alpha }

procedure TTestTimecodeOverlay.TimecodeBack_OpaqueBg_PaintsConfiguredColorAtCorner;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { With a fully opaque green bg block at bottom-left, the top-left pixel of the
    block (flush to the cell corner) must be green. The opposite corner of the
    cell must remain frame color - this proves bg is scoped to the label rect. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 9, tcBottomLeft, clGreen, 255, clWhite, 255));
    Assert.IsNotNull(R);
    try
      { Bg rect is flush to (0, 149-H) ... (W, 150). A point a few pixels above the
        bottom-left edge lands inside the block regardless of text width }
      Assert.AreEqual(Integer(clGreen), Integer(R.Canvas.Pixels[1, 148]),
        'Bottom-left block must paint configured bg color');
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[195, 5]),
        'Opposite corner must stay frame color');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestTimecodeOverlay.TimecodeBack_OpaqueBg_TextAlphaZero_LeavesBgIntact;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  X, Y, FoundNonGreen: Integer;
begin
  { TextAlpha=0 with an opaque bg must render bg-only: every pixel inside the
    block must be the bg color. Scans the block's interior (avoiding edges)
    and counts any pixels that are not clGreen - expected count is zero. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 9, tcBottomLeft, clGreen, 255, clWhite, 0));
    Assert.IsNotNull(R);
    try
      { Block is in the bottom-left; scan a safe 10x10 window inside it }
      FoundNonGreen := 0;
      for Y := 135 to 145 do
        for X := 2 to 12 do
          if R.Canvas.Pixels[X, Y] <> clGreen then
            Inc(FoundNonGreen);
      Assert.AreEqual(0, FoundNonGreen,
        'TextAlpha=0 must leave the bg block free of text pixels');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestTimecodeOverlay.TimestampText_LegacyPath_UsesConfiguredColor;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RDefault, RYellow: TBitmap;
  X, Y: Integer;
  DiffersInTextArea: Boolean;
begin
  { Legacy path (bg alpha = 0) with a non-default text color must produce
    different pixels than the default (clWhite) render inside the text area.
    We compare two renders that differ only in ATimestampTextColor and assert
    at least one pixel in the bottom-left text region differs between them. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    RDefault := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 12, tcBottomLeft, clBlack, 0, clWhite, 255));
    RYellow := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 12, tcBottomLeft, clBlack, 0, clYellow, 255));
    try
      DiffersInTextArea := False;
      { Bottom-left text area after the 4px margin; font height ~16 at 12pt bold }
      for Y := 125 to 145 do
      begin
        for X := 4 to 80 do
          if RDefault.Canvas.Pixels[X, Y] <> RYellow.Canvas.Pixels[X, Y] then
          begin
            DiffersInTextArea := True;
            Break;
          end;
        if DiffersInTextArea then
          Break;
      end;
      Assert.IsTrue(DiffersInTextArea,
        'Non-default text color must change pixels in the legacy-path text area');
    finally
      RDefault.Free;
      RYellow.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestTimecodeOverlay.DefaultTimestampStyle_ShowDefaultsOff;
var
  S: TTimestampStyle;
begin
  {The timestamp overlay must ship OFF - users opt in via the Show
   checkbox. A True default would slap timecodes on every rendered
   image without consent.}
  S := DefaultTimestampStyle;
  Assert.IsFalse(S.Show, 'Timestamp default must be hidden');
  Assert.AreEqual<Integer>(0, S.BackAlpha,
    'BackAlpha=0 selects the legacy shadow-only path for back-compat');
end;

procedure TTestTimecodeOverlay.DefaultTimestampStyle_FontAndSize;
var
  S: TTimestampStyle;
begin
  S := DefaultTimestampStyle;
  Assert.AreNotEqual('', S.FontName,
    'Timestamp font name must not be blank');
  Assert.IsTrue(S.FontSize > 0, 'Timestamp font size must be positive');
  Assert.AreEqual<Integer>(DEF_TIMESTAMP_TEXT_ALPHA, S.TextAlpha);
  Assert.AreEqual(TColor(DEF_TC_BACK_COLOR), S.BackColor);
  Assert.AreEqual(TColor(DEF_TIMESTAMP_TEXT_COLOR), S.TextColor);
end;

procedure TTestTimecodeOverlay.DefaultTimestampStyle_CornerMatchesConstant;
begin
  Assert.AreEqual(Ord(DEF_TIMESTAMP_CORNER),
    Ord(DefaultTimestampStyle.Corner));
end;

procedure TTestTimecodeOverlay.DefaultTimestampStyle_ModeIsLegacy;
begin
  Assert.AreEqual(Ord(tsmLegacy), Ord(DefaultTimestampStyle.Mode),
    'Default historically used the legacy shadow-only renderer ' +
    '(via BackAlpha=0 sentinel); Mode field must keep that promise');
end;

procedure TTestTimecodeOverlay.ModeForZeroBackAlpha_IsLegacy;
begin
  Assert.AreEqual(Ord(tsmLegacy), Ord(TimecodeStyleModeFor(0)));
end;

procedure TTestTimecodeOverlay.ModeForOneBackAlpha_IsModern;
begin
  Assert.AreEqual(Ord(tsmModern), Ord(TimecodeStyleModeFor(1)));
end;

procedure TTestTimecodeOverlay.ModeFor255BackAlpha_IsModern;
begin
  Assert.AreEqual(Ord(tsmModern), Ord(TimecodeStyleModeFor(255)));
end;

procedure TTestTimecodeOverlay.TimestampStyle_FromSettings_CopiesGroupFields;
var
  Group: TTimestampSettingsGroup;
  Style: TTimestampStyle;
begin
  Group := TTimestampSettingsGroup.Defaults;
  Group.Show := True;
  Group.Corner := tcTopRight;
  Group.FontName := 'Courier New';
  Group.FontSize := 14;
  Group.BackColor := clPurple;
  Group.BackAlpha := 180;
  Group.TextColor := clLime;
  Group.TextAlpha := 220;

  Style := TTimestampStyle.FromSettings(Group);
  Assert.IsTrue(Style.Show);
  Assert.AreEqual(Ord(tcTopRight), Ord(Style.Corner));
  Assert.AreEqual('Courier New', Style.FontName);
  Assert.AreEqual<Integer>(14, Style.FontSize);
  Assert.AreEqual(TColor(clPurple), Style.BackColor);
  Assert.AreEqual<Integer>(180, Style.BackAlpha);
  Assert.AreEqual(TColor(clLime), Style.TextColor);
  Assert.AreEqual<Integer>(220, Style.TextAlpha);
end;

procedure TTestTimecodeOverlay.TimestampStyle_FromSettings_DefaultsFontStylesEmpty;
var
  Style: TTimestampStyle;
begin
  {FromSettings defaults FontStyles to [] (matches WLX live view).
   WCX combined-sheet callers override after the call when they want
   [fsBold]. The group doesn't carry FontStyles because the persisted
   setting layer doesn't expose a bold toggle to users.}
  Style := TTimestampStyle.FromSettings(TTimestampSettingsGroup.Defaults);
  Assert.AreEqual<Integer>(0, Byte(Style.FontStyles),
    'FromSettings must default FontStyles to the empty set');
end;

procedure TTestTimecodeOverlay.TimestampStyle_FromSettings_DerivesModeFromBackAlpha;
var
  Group: TTimestampSettingsGroup;
  ModernStyle, LegacyStyle: TTimestampStyle;
begin
  Group := TTimestampSettingsGroup.Defaults;

  Group.BackAlpha := 0;
  LegacyStyle := TTimestampStyle.FromSettings(Group);
  Assert.AreEqual(Ord(tsmLegacy), Ord(LegacyStyle.Mode),
    'BackAlpha=0 must derive tsmLegacy via the historical sentinel-mapping');

  Group.BackAlpha := 128;
  ModernStyle := TTimestampStyle.FromSettings(Group);
  Assert.AreEqual(Ord(tsmModern), Ord(ModernStyle.Mode),
    'BackAlpha>0 must derive tsmModern via the historical sentinel-mapping');
end;

{TTestDrawCellTimecode}

{Helper: builds a TTimestampStyle for the gate tests with safe defaults.
 Show / Corner are the parameters under test; everything else carries
 plausible values so a positive draw produces visible pixels.}
function TimestampForGateTest(AShow: Boolean; ACorner: TTimestampCorner;
  ABackAlpha: Byte = 200): TTimestampStyle;
begin
  Result.Show := AShow;
  Result.Corner := ACorner;
  Result.FontName := 'Consolas';
  Result.FontSize := 12;
  Result.FontStyles := [fsBold];
  Result.BackColor := clBlack;
  Result.BackAlpha := ABackAlpha;
  Result.TextColor := clWhite;
  Result.TextAlpha := 255;
  Result.Mode := TimecodeStyleModeFor(ABackAlpha);
end;

{Counts pixels matching AColor inside ARect on ABmp.Canvas. Sparse cell
 means almost-everything matches; a draw mutates pixels in the corner.}
function CountMatchingPixels(ABmp: TBitmap; const ARect: TRect; AColor: TColor): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := ARect.Top to ARect.Bottom - 1 do
    for X := ARect.Left to ARect.Right - 1 do
      if ABmp.Canvas.Pixels[X, Y] = AColor then
        Inc(Result);
end;

procedure TTestDrawCellTimecode.ShowFalse_NoPixelsTouched;
var
  Bmp: TBitmap;
  CellRect: TRect;
  Style: TTimestampStyle;
  PixelCount: Integer;
begin
  {Fill a bitmap with a marker colour, call DrawCellTimecode with
   Show=False, then assert every pixel in the would-be-overlay region
   still carries the marker. Pins the Show-gate short-circuit at the
   unit boundary.}
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));

    CellRect := Rect(0, 0, 200, 100);
    Style := TimestampForGateTest(False, tcBottomLeft);
    DrawCellTimecode(Bmp.Canvas, CellRect, 12.345, Style);

    PixelCount := CountMatchingPixels(Bmp, CellRect, clRed);
    Assert.AreEqual(200 * 100, PixelCount,
      'Show=False must not touch any pixel inside the cell rect');
  finally
    Bmp.Free;
  end;
end;

procedure TTestDrawCellTimecode.ShowTrueCornerNone_NoPixelsTouched;
var
  Bmp: TBitmap;
  CellRect: TRect;
  Style: TTimestampStyle;
  PixelCount: Integer;
begin
  {Same shape as the Show=False test, but with Show=True and
   Corner=tcNone. Pins the second short-circuit gate; deleting the
   Corner check would slip past TimestampDisabled_NoTextDrawn
   (Show=False) but trip this test.}
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));

    CellRect := Rect(0, 0, 200, 100);
    Style := TimestampForGateTest(True, tcNone);
    DrawCellTimecode(Bmp.Canvas, CellRect, 12.345, Style);

    PixelCount := CountMatchingPixels(Bmp, CellRect, clRed);
    Assert.AreEqual(200 * 100, PixelCount,
      'Corner=tcNone must not touch any pixel inside the cell rect');
  finally
    Bmp.Free;
  end;
end;

procedure TTestDrawCellTimecode.ShowTrueValidCorner_DrawsSomething;
var
  Bmp: TBitmap;
  CellRect: TRect;
  Style: TTimestampStyle;
  RedCount: Integer;
begin
  {Sanity check the positive path: with Show=True and a valid corner,
   at least one pixel inside the cell rect must NOT match the marker
   colour (i.e. the helper drew something). Without this, the gate
   tests above could pass even if the helper became a complete no-op.}
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));

    CellRect := Rect(0, 0, 200, 100);
    Style := TimestampForGateTest(True, tcBottomLeft);
    DrawCellTimecode(Bmp.Canvas, CellRect, 12.345, Style);

    RedCount := CountMatchingPixels(Bmp, CellRect, clRed);
    Assert.IsTrue(RedCount < 200 * 100,
      'Some pixels must change when the helper draws the overlay');
  finally
    Bmp.Free;
  end;
end;

procedure TTestTimecodeOverlay.ModeLegacy_DoesNotPaintTopLeftCornerPixel;
var
  Bmp: TBitmap;
  Style: TTimestampStyle;
begin
  {Legacy painter for tcTopLeft positions text at (Left+4, Top+4). The
   pixel at (0,0) is therefore untouched. Modern painter would fill
   that same pixel with its corner rect (when BackAlpha>0). Counting on
   that single-pixel difference is fragile in general, but the painter
   geometry is pinned elsewhere; here we just need a witness that the
   dispatch went to the legacy branch.}
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));

    Style := TimestampForGateTest(True, tcTopLeft, 0);
    Style.Mode := tsmLegacy;
    DrawCellTimecode(Bmp.Canvas, Rect(0, 0, 200, 100), 12.345, Style);

    Assert.AreEqual<Integer>(clRed, Bmp.Canvas.Pixels[0, 0],
      'Legacy painter insets text from the cell corner; (0,0) must remain the marker colour');
  finally
    Bmp.Free;
  end;
end;

procedure TTestTimecodeOverlay.ModeModern_WithOpaqueBg_FillsCornerStripWithBackColor;
var
  Bmp: TBitmap;
  Style: TTimestampStyle;
begin
  {Modern painter for tcTopLeft + opaque BackAlpha=255 paints a solid
   BackColor rectangle anchored at the top-left, including (0,0). The
   legacy painter would leave that pixel alone.}
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));

    Style := TimestampForGateTest(True, tcTopLeft, 255);
    Style.BackColor := clBlue;
    Style.Mode := tsmModern;
    DrawCellTimecode(Bmp.Canvas, Rect(0, 0, 200, 100), 12.345, Style);

    Assert.AreEqual<Integer>(clBlue, Bmp.Canvas.Pixels[0, 0],
      'Modern painter with opaque background fills the corner rect; ' +
      '(0,0) must carry BackColor');
  finally
    Bmp.Free;
  end;
end;

end.
