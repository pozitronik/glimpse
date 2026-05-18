unit TestTypes;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTypes = class
  public
    { Enum ordering is load-bearing: used as array indices in uToolbarLayout }
    [Test] procedure ViewModeOrdinals;
    [Test] procedure ViewModeRange;
    [Test] procedure ZoomModeOrdinals;
    [Test] procedure ZoomModeRange;
    [Test] procedure FFmpegModeOrdinals;
    [Test] procedure ThumbnailModeOrdinals;
    [Test] procedure ThumbnailModeRange;
    [Test] procedure TimestampCornerOrdinals;
    [Test] procedure TimestampCornerRange;
    [Test] procedure BannerPositionOrdinals;
    [Test] procedure BannerPositionRange;
    [Test] procedure ProgressBarLayoutOrdinals;
    [Test] procedure StatusBarHeightApplyModeOrdinals;
    [Test] procedure StatusBarHeightApplyModeRoundTrip;
    [Test] procedure StatusBarHeightApplyModeUnknownReturnsDefault;
    [Test] procedure ShouldApplyStatusBarHeight_Both;
    [Test] procedure ShouldApplyStatusBarHeight_ListerOnly;
    [Test] procedure ShouldApplyStatusBarHeight_QuickViewOnly;
    [Test] procedure ResolveStatusBarHeight_AutoWhenSettingZero;
    [Test] procedure ResolveStatusBarHeight_AutoWhenSettingNegative;
    [Test] procedure ResolveStatusBarHeight_AutoWhenApplyModeGateFails;
    [Test] procedure ResolveStatusBarHeight_ExplicitScaledByPpi;
    [Test] procedure ResolveStatusBarHeight_BumpsWhenBelowFontMinimum;
    [Test] procedure ResolveStatusBarHeight_ZeroPpiTreatedAs96;
    [Test] procedure ResolveStatusBarHeight_NegativePpiTreatedAs96;
    [Test] procedure ResolveStatusBarHeight_ExplicitSmallerThanAuto_AllowedWhenAboveMin;
    [Test] procedure ResolveProgressBarBounds_Auto_WidePicksAfterPanels;
    [Test] procedure ResolveProgressBarBounds_Auto_NarrowPicksOverPanels;
    [Test] procedure ResolveProgressBarBounds_StretchPanels_ForcesOverPanels;
    [Test] procedure ResolveProgressBarBounds_AfterPanels_ClampsWidthToMin;
    [Test] procedure ResolveProgressBarBounds_OverPanels_SpansFullClientMinusMargins;
    [Test] procedure ResolveProgressBarBounds_TopAndHeightAlwaysSetFromMargin;
    [Test] procedure ExtractionOptionsValueSemantics;
    {Conversions for enums that round-trip through INI. Load-bearing
     because settings dialogs read/write these tokens verbatim.}
    [Test] procedure TimestampCornerToStr_AllValues;
    [Test] procedure StrToTimestampCorner_AllKnownTokens;
    [Test] procedure StrToTimestampCorner_RoundTrip_AllValues;
    [Test] procedure StrToTimestampCorner_Unknown_ReturnsDefault;
    [Test] procedure StrToTimestampCorner_MixedCase_Accepted;
    [Test] procedure StrToTimestampCorner_EmptyString_ReturnsDefault;
    [Test] procedure BannerPositionToStr_BothValues;
    [Test] procedure StrToBannerPosition_BothKnownTokens;
    [Test] procedure StrToBannerPosition_RoundTrip_BothValues;
    [Test] procedure StrToBannerPosition_Unknown_ReturnsDefault;
    [Test] procedure StrToBannerPosition_MixedCase_Accepted;
  end;

implementation

uses
  System.SysUtils,
  uTypes, uStatusBarLayout;

procedure TTestTypes.ViewModeOrdinals;
begin
  Assert.AreEqual(0, Ord(vmSmartGrid));
  Assert.AreEqual(1, Ord(vmGrid));
  Assert.AreEqual(2, Ord(vmScroll));
  Assert.AreEqual(3, Ord(vmFilmstrip));
  Assert.AreEqual(4, Ord(vmSingle));
end;

procedure TTestTypes.ViewModeRange;
begin
  Assert.AreEqual(vmSmartGrid, Low(TViewMode));
  Assert.AreEqual(vmSingle, High(TViewMode));
end;

procedure TTestTypes.ZoomModeOrdinals;
begin
  Assert.AreEqual(0, Ord(zmFitWindow));
  Assert.AreEqual(1, Ord(zmFitIfLarger));
  Assert.AreEqual(2, Ord(zmActual));
end;

procedure TTestTypes.ZoomModeRange;
begin
  Assert.AreEqual(zmFitWindow, Low(TZoomMode));
  Assert.AreEqual(zmActual, High(TZoomMode));
end;

procedure TTestTypes.FFmpegModeOrdinals;
begin
  Assert.AreEqual(0, Ord(fmAuto));
  Assert.AreEqual(1, Ord(fmExe));
end;

procedure TTestTypes.ThumbnailModeOrdinals;
begin
  Assert.AreEqual(0, Ord(tnmSingle));
  Assert.AreEqual(1, Ord(tnmGrid));
end;

procedure TTestTypes.ThumbnailModeRange;
begin
  Assert.AreEqual(tnmSingle, Low(TThumbnailMode));
  Assert.AreEqual(tnmGrid, High(TThumbnailMode));
end;

procedure TTestTypes.TimestampCornerOrdinals;
begin
  {Ordering pinned because some settings persisted older builds as ordinals
   (pre the string-based converter) — rearranging the enum would silently
   remap users' saved corners.}
  Assert.AreEqual(0, Ord(tcNone));
  Assert.AreEqual(1, Ord(tcTopLeft));
  Assert.AreEqual(2, Ord(tcTopRight));
  Assert.AreEqual(3, Ord(tcBottomLeft));
  Assert.AreEqual(4, Ord(tcBottomRight));
end;

procedure TTestTypes.TimestampCornerRange;
begin
  Assert.AreEqual(tcNone, Low(TTimestampCorner));
  Assert.AreEqual(tcBottomRight, High(TTimestampCorner));
end;

procedure TTestTypes.BannerPositionOrdinals;
begin
  Assert.AreEqual(0, Ord(bpTop));
  Assert.AreEqual(1, Ord(bpBottom));
end;

procedure TTestTypes.BannerPositionRange;
begin
  Assert.AreEqual(bpTop, Low(TBannerPosition));
  Assert.AreEqual(bpBottom, High(TBannerPosition));
end;

procedure TTestTypes.ProgressBarLayoutOrdinals;
begin
  {The settings dialog casts the combo box index straight to
   TProgressBarLayout (uSettingsDlg.ControlsToSettings) and uses the
   enum's Ord value to set the index back (uSettingsDlg.SettingsToControls).
   If this enum is ever reordered, the dialog would silently pick the
   wrong layout. Pin the order here so a reorder fails loudly instead.}
  Assert.AreEqual(0, Ord(pblAfterPanels));
  Assert.AreEqual(1, Ord(pblOverPanels));
  Assert.AreEqual(2, Ord(pblAuto));
end;

procedure TTestTypes.StatusBarHeightApplyModeOrdinals;
begin
  {CbxStatusBarHeightApply.ItemIndex is cast straight to
   TStatusBarHeightApplyMode in ControlsToSettings, so the combo's
   item order MUST match these ordinals or the dialog silently
   stores the wrong mode on every Apply.}
  Assert.AreEqual(0, Ord(sbhamLister));
  Assert.AreEqual(1, Ord(sbhamQuickView));
  Assert.AreEqual(2, Ord(sbhamBoth));
end;

procedure TTestTypes.StatusBarHeightApplyModeRoundTrip;
var
  M: TStatusBarHeightApplyMode;
begin
  for M := Low(TStatusBarHeightApplyMode) to High(TStatusBarHeightApplyMode) do
    Assert.AreEqual<Integer>(Ord(M),
      Ord(StrToStatusBarHeightApplyMode(StatusBarHeightApplyModeToStr(M), sbhamBoth)),
      'INI token must round-trip through StatusBarHeightApplyModeToStr / StrToStatusBarHeightApplyMode');
end;

procedure TTestTypes.StatusBarHeightApplyModeUnknownReturnsDefault;
begin
  Assert.AreEqual<Integer>(Ord(sbhamLister),
    Ord(StrToStatusBarHeightApplyMode('nonsense', sbhamLister)));
  Assert.AreEqual<Integer>(Ord(sbhamBoth),
    Ord(StrToStatusBarHeightApplyMode('', sbhamBoth)));
end;

procedure TTestTypes.ShouldApplyStatusBarHeight_Both;
begin
  Assert.IsTrue(ShouldApplyStatusBarHeight(sbhamBoth, False),
    'sbhamBoth must apply in Lister mode');
  Assert.IsTrue(ShouldApplyStatusBarHeight(sbhamBoth, True),
    'sbhamBoth must apply in Quick View mode');
end;

procedure TTestTypes.ShouldApplyStatusBarHeight_ListerOnly;
begin
  Assert.IsTrue(ShouldApplyStatusBarHeight(sbhamLister, False),
    'sbhamLister applies in Lister mode');
  Assert.IsFalse(ShouldApplyStatusBarHeight(sbhamLister, True),
    'sbhamLister must NOT apply in Quick View — falls back to auto height');
end;

procedure TTestTypes.ShouldApplyStatusBarHeight_QuickViewOnly;
begin
  Assert.IsFalse(ShouldApplyStatusBarHeight(sbhamQuickView, False),
    'sbhamQuickView must NOT apply in Lister mode');
  Assert.IsTrue(ShouldApplyStatusBarHeight(sbhamQuickView, True),
    'sbhamQuickView applies in Quick View mode');
end;

procedure TTestTypes.ResolveStatusBarHeight_AutoWhenSettingZero;
begin
  {Auto path: AutoHeight = TextHeight + 6 px padding. Setting=0 is the
   user's "auto" choice; even an applicable apply-mode + valid PPI must
   resolve to auto here.}
  Assert.AreEqual(20, ResolveStatusBarHeightPixels(14, 0, sbhamBoth, False, 96));
end;

procedure TTestTypes.ResolveStatusBarHeight_AutoWhenSettingNegative;
begin
  {Negative values are protected by the same "<= 0" guard as zero.
   Defensive: the UI's TUpDown clamps to >= 0 but a corrupt INI could
   slip a negative through.}
  Assert.AreEqual(20, ResolveStatusBarHeightPixels(14, -10, sbhamBoth, False, 96));
end;

procedure TTestTypes.ResolveStatusBarHeight_AutoWhenApplyModeGateFails;
begin
  {sbhamLister + AIsQuickView=True -> gate closed -> always auto,
   regardless of how aggressive the user's explicit setting is.}
  Assert.AreEqual(20, ResolveStatusBarHeightPixels(14, 40, sbhamLister, True, 96));
  Assert.AreEqual(20, ResolveStatusBarHeightPixels(14, 40, sbhamQuickView, False, 96));
end;

procedure TTestTypes.ResolveStatusBarHeight_ExplicitScaledByPpi;
begin
  {Setting=24 at 96 DPI -> 24 px. At 192 DPI -> 48 px. MulDiv applies.}
  Assert.AreEqual(24, ResolveStatusBarHeightPixels(14, 24, sbhamBoth, False, 96));
  Assert.AreEqual(48, ResolveStatusBarHeightPixels(14, 24, sbhamBoth, False, 192));
  {144 DPI -> 36 px.}
  Assert.AreEqual(36, ResolveStatusBarHeightPixels(14, 24, sbhamBoth, False, 144));
end;

procedure TTestTypes.ResolveStatusBarHeight_BumpsWhenBelowFontMinimum;
begin
  {Font reach 14 px + 2 px min padding = 16 px floor. Setting=10 at
   96 DPI scales to 10 px which is below the floor -> bumps to 16.}
  Assert.AreEqual(16, ResolveStatusBarHeightPixels(14, 10, sbhamBoth, False, 96));
  {Setting=16 lands exactly on the floor and passes through unchanged.}
  Assert.AreEqual(16, ResolveStatusBarHeightPixels(14, 16, sbhamBoth, False, 96));
end;

procedure TTestTypes.ResolveStatusBarHeight_ZeroPpiTreatedAs96;
begin
  {CurrentPPI returns 0 in some pre-paint states. Helper must normalise
   to 96 rather than dividing by zero or returning nonsense.}
  Assert.AreEqual(24, ResolveStatusBarHeightPixels(14, 24, sbhamBoth, False, 0));
end;

procedure TTestTypes.ResolveStatusBarHeight_NegativePpiTreatedAs96;
begin
  {Defensive: any negative PPI value also normalises to 96.}
  Assert.AreEqual(24, ResolveStatusBarHeightPixels(14, 24, sbhamBoth, False, -1));
end;

procedure TTestTypes.ResolveStatusBarHeight_ExplicitSmallerThanAuto_AllowedWhenAboveMin;
begin
  {Pinning the 2-vs-6 px asymmetry. Auto = TextHeight + 6 = 20.
   Setting=17 explicit > MinHeight (16) so it passes through, producing
   a bar tighter than auto. This is the intended escape hatch for users
   who want a compact bar with a known-fitting font.}
  Assert.AreEqual(17, ResolveStatusBarHeightPixels(14, 17, sbhamBoth, False, 96));
end;

procedure TTestTypes.ResolveProgressBarBounds_Auto_WidePicksAfterPanels;
var
  B: TProgressBarBounds;
begin
  {Client 200, panels 100, min 40, margin 1. 200 >= 100 + 40 + 2 = 142,
   so auto -> AfterPanels. Left = 101, Width = 200 - 100 - 2 = 98.}
  B := ResolveProgressBarBounds(200, 20, 100, False, pblAuto, 40, 1);
  Assert.AreEqual(101, B.Left);
  Assert.AreEqual(98, B.Width);
end;

procedure TTestTypes.ResolveProgressBarBounds_Auto_NarrowPicksOverPanels;
var
  B: TProgressBarBounds;
begin
  {Client 120, panels 100, min 40, margin 1. 120 < 100 + 40 + 2 = 142,
   so auto -> OverPanels. Left = margin = 1, Width = 120 - 2 = 118.}
  B := ResolveProgressBarBounds(120, 20, 100, False, pblAuto, 40, 1);
  Assert.AreEqual(1, B.Left);
  Assert.AreEqual(118, B.Width);
end;

procedure TTestTypes.ResolveProgressBarBounds_StretchPanels_ForcesOverPanels;
var
  B: TProgressBarBounds;
begin
  {Even with an explicit AfterPanels request, stretch mode wins because
   the stretched panels leave no trailing slack. Output mirrors the
   OverPanels path: full-width minus margins.}
  B := ResolveProgressBarBounds(200, 20, 100, True, pblAfterPanels, 40, 1);
  Assert.AreEqual(1, B.Left);
  Assert.AreEqual(198, B.Width);
end;

procedure TTestTypes.ResolveProgressBarBounds_AfterPanels_ClampsWidthToMin;
var
  B: TProgressBarBounds;
begin
  {Client 150, panels 140, min 40, margin 1. AfterPanels gives
   Width = 150 - 140 - 2 = 8, which is below the min — clamp to 40.
   The bar will visually overlap the rightmost panel; intentional
   fallback to keep the bar usable in tight layouts.}
  B := ResolveProgressBarBounds(150, 20, 140, False, pblAfterPanels, 40, 1);
  Assert.AreEqual(141, B.Left);
  Assert.AreEqual(40, B.Width);
end;

procedure TTestTypes.ResolveProgressBarBounds_OverPanels_SpansFullClientMinusMargins;
var
  B: TProgressBarBounds;
begin
  B := ResolveProgressBarBounds(300, 20, 250, False, pblOverPanels, 40, 1);
  Assert.AreEqual(1, B.Left);
  Assert.AreEqual(298, B.Width);
end;

procedure TTestTypes.ResolveProgressBarBounds_TopAndHeightAlwaysSetFromMargin;
var
  B: TProgressBarBounds;
begin
  {Top is always the margin; Height is the client height minus 2 margins.
   Independent of layout policy.}
  B := ResolveProgressBarBounds(200, 20, 100, False, pblAuto, 40, 1);
  Assert.AreEqual(1, B.Top);
  Assert.AreEqual(18, B.Height);
  {Different margin propagates everywhere.}
  B := ResolveProgressBarBounds(200, 30, 100, False, pblOverPanels, 40, 3);
  Assert.AreEqual(3, B.Top);
  Assert.AreEqual(24, B.Height);
end;

procedure TTestTypes.TimestampCornerToStr_AllValues;
begin
  {Every enum value must serialise to a distinct, non-empty token —
   otherwise the settings INI row for two different corners collapses
   to the same string.}
  Assert.AreEqual('none', TimestampCornerToStr(tcNone));
  Assert.AreEqual('topleft', TimestampCornerToStr(tcTopLeft));
  Assert.AreEqual('topright', TimestampCornerToStr(tcTopRight));
  Assert.AreEqual('bottomleft', TimestampCornerToStr(tcBottomLeft));
  Assert.AreEqual('bottomright', TimestampCornerToStr(tcBottomRight));
end;

procedure TTestTypes.StrToTimestampCorner_AllKnownTokens;
begin
  Assert.AreEqual(Ord(tcNone), Ord(StrToTimestampCorner('none', tcTopLeft)));
  Assert.AreEqual(Ord(tcTopLeft), Ord(StrToTimestampCorner('topleft', tcNone)));
  Assert.AreEqual(Ord(tcTopRight), Ord(StrToTimestampCorner('topright', tcNone)));
  Assert.AreEqual(Ord(tcBottomLeft), Ord(StrToTimestampCorner('bottomleft', tcNone)));
  Assert.AreEqual(Ord(tcBottomRight), Ord(StrToTimestampCorner('bottomright', tcNone)));
end;

procedure TTestTypes.StrToTimestampCorner_RoundTrip_AllValues;
var
  C: TTimestampCorner;
begin
  {Every enum value must survive a full ToStr -> StrTo cycle. If one ever
   doesn't, saved settings would silently drift to the default.}
  for C := Low(TTimestampCorner) to High(TTimestampCorner) do
    Assert.AreEqual(Ord(C),
      Ord(StrToTimestampCorner(TimestampCornerToStr(C), tcNone)),
      Format('Round-trip failed for corner #%d', [Ord(C)]));
end;

procedure TTestTypes.StrToTimestampCorner_Unknown_ReturnsDefault;
begin
  Assert.AreEqual(Ord(tcBottomLeft),
    Ord(StrToTimestampCorner('garbage', tcBottomLeft)));
  Assert.AreEqual(Ord(tcTopRight),
    Ord(StrToTimestampCorner('', tcTopRight)),
    'Empty string must also fall back to the default');
end;

procedure TTestTypes.StrToTimestampCorner_MixedCase_Accepted;
begin
  {SameText comparison: hand-edited INI with 'TopLeft' or 'TOPLEFT' must parse.}
  Assert.AreEqual(Ord(tcTopLeft),
    Ord(StrToTimestampCorner('TopLeft', tcNone)));
  Assert.AreEqual(Ord(tcBottomRight),
    Ord(StrToTimestampCorner('BOTTOMRIGHT', tcNone)));
end;

procedure TTestTypes.StrToTimestampCorner_EmptyString_ReturnsDefault;
begin
  {Explicit empty-string lock: a missing INI key read via ReadString('', ...)
   must defer to the supplied default rather than silently becoming tcNone.}
  Assert.AreEqual(Ord(tcBottomLeft),
    Ord(StrToTimestampCorner('', tcBottomLeft)));
end;

procedure TTestTypes.BannerPositionToStr_BothValues;
begin
  Assert.AreEqual('top', BannerPositionToStr(bpTop));
  Assert.AreEqual('bottom', BannerPositionToStr(bpBottom));
end;

procedure TTestTypes.StrToBannerPosition_BothKnownTokens;
begin
  Assert.AreEqual(Ord(bpTop), Ord(StrToBannerPosition('top', bpBottom)));
  Assert.AreEqual(Ord(bpBottom), Ord(StrToBannerPosition('bottom', bpTop)));
end;

procedure TTestTypes.StrToBannerPosition_RoundTrip_BothValues;
var
  P: TBannerPosition;
begin
  for P := Low(TBannerPosition) to High(TBannerPosition) do
    Assert.AreEqual(Ord(P),
      Ord(StrToBannerPosition(BannerPositionToStr(P), bpTop)),
      Format('Round-trip failed for position #%d', [Ord(P)]));
end;

procedure TTestTypes.StrToBannerPosition_Unknown_ReturnsDefault;
begin
  Assert.AreEqual(Ord(bpBottom),
    Ord(StrToBannerPosition('sideways', bpBottom)));
  Assert.AreEqual(Ord(bpTop),
    Ord(StrToBannerPosition('', bpTop)));
end;

procedure TTestTypes.StrToBannerPosition_MixedCase_Accepted;
begin
  Assert.AreEqual(Ord(bpTop), Ord(StrToBannerPosition('Top', bpBottom)));
  Assert.AreEqual(Ord(bpBottom), Ord(StrToBannerPosition('BOTTOM', bpTop)));
end;

procedure TTestTypes.ExtractionOptionsValueSemantics;
var
  A, B: TExtractionOptions;
begin
  A := Default(TExtractionOptions);
  A.UseBmpPipe := True;
  A.MaxSide := 480;
  A.HwAccel := True;
  A.UseKeyframes := False;

  { Record copy preserves all fields }
  B := A;
  Assert.IsTrue(B.UseBmpPipe);
  Assert.AreEqual(480, B.MaxSide);
  Assert.IsTrue(B.HwAccel);
  Assert.IsFalse(B.UseKeyframes);

  { Modifying copy does not affect original }
  B.MaxSide := 1920;
  B.UseKeyframes := True;
  Assert.AreEqual(480, A.MaxSide);
  Assert.IsFalse(A.UseKeyframes);
end;

end.
