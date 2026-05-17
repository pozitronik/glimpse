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
  uTypes;

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
  {Used as raw int indices by CbxProgressBarLayout in the settings
   dialog and as Ord values cast through TProgressBarLayout in
   ControlsToSettings. The stretch-panels lock pins ItemIndex := 1 to
   force the Over Panels selection; if this enum is ever reordered,
   the dialog would silently pick the wrong layout. Pin the order
   here so the reorder fails loudly instead.}
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
