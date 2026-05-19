unit TestStatusBarFormatters;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStatusBarFormatters = class
  public
    {Pass-through / fallback}
    [Test]
    procedure TestUnknownReturnsRawText;
    [Test]
    procedure TestUnknownIgnoresValues;
    [Test]
    procedure TestUnrecognisedTokenWithCasingIgnoresCasing;

    {File position}
    [Test]
    procedure TestFilePositionFormatsAsIndexSlashTotal;
    [Test]
    procedure TestFilePositionEmptyWhenUnavailable;

    {Filename}
    [Test]
    procedure TestFilenamePassesThrough;
    [Test]
    procedure TestFilenameEmptyWhenUnset;

    {Frames vs frame_position}
    [Test]
    procedure TestFramesEmptyWhenUnavailable;
    [Test]
    procedure TestFramesShowsTotalAlways;
    [Test]
    procedure TestFramePositionEmptyWhenUnavailable;
    [Test]
    procedure TestFramePositionShowsCurrentSlashTotalInSingleView;
    [Test]
    procedure TestFramePositionShowsTotalOutsideSingleView;

    {Source video info}
    [Test]
    procedure TestResolutionFormatsWxH;
    [Test]
    procedure TestResolutionEmptyWhenZero;
    [Test]
    procedure TestFpsFormatsWithSuffix;
    [Test]
    procedure TestFpsEmptyWhenZero;
    [Test]
    procedure TestDurationDelegatesToFormatDurationHMS;
    [Test]
    procedure TestDurationEmptyWhenZero;
    [Test]
    procedure TestBitrateBelowOneMegaShowsKbps;
    [Test]
    procedure TestBitrateAtOrAboveOneMegaShowsMbps;
    [Test]
    procedure TestBitrateEmptyWhenZero;
    [Test]
    procedure TestVideoCodecPassesThrough;

    {Audio composite}
    [Test]
    procedure TestAudioEmptyWhenVideoInfoInvalid;
    [Test]
    procedure TestAudioReportsNoAudioWhenCodecMissing;
    [Test]
    procedure TestAudioConcatenatesAvailableParts;
    [Test]
    procedure TestAudioOmitsZeroSampleRate;
    [Test]
    procedure TestAudioOmitsEmptyChannels;
    [Test]
    procedure TestAudioOmitsZeroBitrate;

    {Load time}
    [Test]
    procedure TestLoadTimePassesThrough;
    [Test]
    procedure TestLoadTimeEmptyWhenUnset;

    {Predicted dimensions}
    [Test]
    procedure TestSaveDimensionUnavailableEmpty;
    [Test]
    procedure TestSaveDimensionWithoutCapShowsBareSize;
    [Test]
    procedure TestSaveDimensionWithCapAppendsTransform;
    [Test]
    procedure TestSaveDimensionCapEqualsToSourceOmitsTransform;
    [Test]
    procedure TestSaveDimensionCapFalseSuppressesTransform;
    [Test]
    procedure TestSaveDimensionWithCapInjectsGlyphLiteral;
    [Test]
    procedure TestCopyDimensionUsesCopyLabel;

    {View mode / zoom}
    [Test]
    procedure TestViewModePassesThrough;
    [Test]
    procedure TestZoomPassesThrough;

    {Casing}
    [Test]
    procedure TestUppercaseCasingUppercasesResult;
    [Test]
    procedure TestUppercaseCasingDoesNothingWhenEmpty;
    [Test]
    procedure TestAsIsCasingPreservesCase;
  end;

implementation

uses
  System.SysUtils,
  StatusBarTokens, StatusBarTemplate, StatusBarFormatters;

{Build a TStatusBarToken of a known kind without going through the parser
 — keeps tests independent of parser bugs. Pure factory.}
function MakeToken(AKind: TStatusBarTokenKind;
  ACasing: TStatusBarTokenCase = tcAsIs): TStatusBarToken;
begin
  Result := Default(TStatusBarToken);
  Result.Kind := AKind;
  Result.Casing := ACasing;
end;

function MakeTokenWithAttr(AKind: TStatusBarTokenKind;
  const AAttrName, AAttrValue: string): TStatusBarToken;
var
  Attr: TStatusBarTokenAttr;
begin
  Result := MakeToken(AKind);
  Attr.Name := AAttrName;
  Attr.Value := AAttrValue;
  Result.Attributes := [Attr];
end;

{Shared empty values — every Available flag false, every numeric zero,
 every string empty. Tests mutate just the fields they care about.}
function EmptyValues: TStatusBarValues;
begin
  Result := Default(TStatusBarValues);
end;

procedure TTestStatusBarFormatters.TestUnknownReturnsRawText;
var
  Tok: TStatusBarToken;
begin
  Tok := Default(TStatusBarToken);
  Tok.Kind := tkUnknown;
  Tok.RawText := '%mistype%';
  Assert.AreEqual('%mistype%', FormatStatusBarToken(Tok, EmptyValues));
end;

procedure TTestStatusBarFormatters.TestUnknownIgnoresValues;
var
  Tok: TStatusBarToken;
  V: TStatusBarValues;
begin
  Tok := Default(TStatusBarToken);
  Tok.Kind := tkUnknown;
  Tok.RawText := '%abc%';
  V := EmptyValues;
  V.Filename := 'should not appear';
  Assert.AreEqual('%abc%', FormatStatusBarToken(Tok, V));
end;

procedure TTestStatusBarFormatters.TestUnrecognisedTokenWithCasingIgnoresCasing;
var
  Tok: TStatusBarToken;
begin
  {RawText is the user's literal source — uppercasing it would silently
   distort their typo and confuse the diagnostic.}
  Tok := Default(TStatusBarToken);
  Tok.Kind := tkUnknown;
  Tok.Casing := tcUpper;
  Tok.RawText := '%MyTypo%';
  Assert.AreEqual('%MyTypo%', FormatStatusBarToken(Tok, EmptyValues));
end;

procedure TTestStatusBarFormatters.TestFilePositionFormatsAsIndexSlashTotal;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.FilePositionAvailable := True;
  V.FilePositionIndex := 3;
  V.FilePositionTotal := 12;
  Assert.AreEqual('3 / 12',
    FormatStatusBarToken(MakeToken(tkFilePosition), V));
end;

procedure TTestStatusBarFormatters.TestFilePositionEmptyWhenUnavailable;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkFilePosition), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestFilenamePassesThrough;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.Filename := 'video.mp4';
  Assert.AreEqual('video.mp4',
    FormatStatusBarToken(MakeToken(tkFilename), V));
end;

procedure TTestStatusBarFormatters.TestFilenameEmptyWhenUnset;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkFilename), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestFramesEmptyWhenUnavailable;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkFrames), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestFramesShowsTotalAlways;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.FramesAvailable := True;
  V.FramesTotal := 24;
  V.CurrentFrameIndex := 5;
  V.IsSingleViewMode := True;  {must be ignored by tkFrames}
  Assert.AreEqual('24',
    FormatStatusBarToken(MakeToken(tkFrames), V));
end;

procedure TTestStatusBarFormatters.TestFramePositionEmptyWhenUnavailable;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkFramePosition), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestFramePositionShowsCurrentSlashTotalInSingleView;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.FramesAvailable := True;
  V.FramesTotal := 12;
  V.CurrentFrameIndex := 4;  {0-based}
  V.IsSingleViewMode := True;
  Assert.AreEqual('5 / 12',
    FormatStatusBarToken(MakeToken(tkFramePosition), V));
end;

procedure TTestStatusBarFormatters.TestFramePositionShowsTotalOutsideSingleView;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.FramesAvailable := True;
  V.FramesTotal := 12;
  V.CurrentFrameIndex := 4;
  V.IsSingleViewMode := False;
  Assert.AreEqual('12',
    FormatStatusBarToken(MakeToken(tkFramePosition), V));
end;

procedure TTestStatusBarFormatters.TestResolutionFormatsWxH;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SourceWidth := 1920;
  V.SourceHeight := 1080;
  Assert.AreEqual('1920x1080',
    FormatStatusBarToken(MakeToken(tkResolution), V));
end;

procedure TTestStatusBarFormatters.TestResolutionEmptyWhenZero;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SourceWidth := 1920;  {height missing}
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkResolution), V));
end;

procedure TTestStatusBarFormatters.TestFpsFormatsWithSuffix;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SourceFps := 23.976;
  Assert.IsTrue(FormatStatusBarToken(MakeToken(tkFps), V).EndsWith(' fps'));
end;

procedure TTestStatusBarFormatters.TestFpsEmptyWhenZero;
begin
  Assert.AreEqual('', FormatStatusBarToken(MakeToken(tkFps), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestDurationDelegatesToFormatDurationHMS;
var
  V: TStatusBarValues;
  S: string;
begin
  V := EmptyValues;
  V.SourceDurationSec := 65;  {1m 5s}
  S := FormatStatusBarToken(MakeToken(tkDuration), V);
  Assert.IsNotEmpty(S);
  Assert.IsTrue(S.Contains(':'),
    'Expected H:M:S formatting (delegates to FrameOffsets.FormatDurationHMS)');
end;

procedure TTestStatusBarFormatters.TestDurationEmptyWhenZero;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkDuration), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestBitrateBelowOneMegaShowsKbps;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SourceBitrateKbps := 850;
  Assert.AreEqual('850 kbps',
    FormatStatusBarToken(MakeToken(tkBitrate), V));
end;

procedure TTestStatusBarFormatters.TestBitrateAtOrAboveOneMegaShowsMbps;
var
  V: TStatusBarValues;
  S: string;
begin
  V := EmptyValues;
  V.SourceBitrateKbps := 5200;
  S := FormatStatusBarToken(MakeToken(tkBitrate), V);
  {Decimal separator is locale-dependent (Format('%.1f') honours
   FormatSettings.DecimalSeparator). Pre-template behaviour was the
   same — preserved on purpose. Assertion accepts either form so the
   test passes on every Windows locale.}
  Assert.IsTrue((S = '5.2 Mbps') or (S = '5,2 Mbps'),
    'Expected "5.2 Mbps" or "5,2 Mbps", got "' + S + '"');
end;

procedure TTestStatusBarFormatters.TestBitrateEmptyWhenZero;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkBitrate), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestVideoCodecPassesThrough;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SourceVideoCodec := 'h264';
  Assert.AreEqual('h264',
    FormatStatusBarToken(MakeToken(tkVideoCodec), V));
end;

procedure TTestStatusBarFormatters.TestAudioEmptyWhenVideoInfoInvalid;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SourceAudioCodec := 'aac';
  {VideoInfoValid still False — tkAudio must short-circuit so a stale
   audio panel doesn't survive a switch to a video that has not been
   probed yet.}
  Assert.AreEqual('', FormatStatusBarToken(MakeToken(tkAudio), V));
end;

procedure TTestStatusBarFormatters.TestAudioReportsNoAudioWhenCodecMissing;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.VideoInfoValid := True;
  Assert.AreEqual('No audio',
    FormatStatusBarToken(MakeToken(tkAudio), V));
end;

procedure TTestStatusBarFormatters.TestAudioConcatenatesAvailableParts;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.VideoInfoValid := True;
  V.SourceAudioCodec := 'aac';
  V.SourceAudioSampleRate := 48000;
  V.SourceAudioChannels := 'stereo';
  V.SourceAudioBitrateKbps := 192;
  Assert.AreEqual('aac 48000 Hz stereo 192 kbps',
    FormatStatusBarToken(MakeToken(tkAudio), V));
end;

procedure TTestStatusBarFormatters.TestAudioOmitsZeroSampleRate;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.VideoInfoValid := True;
  V.SourceAudioCodec := 'aac';
  V.SourceAudioChannels := 'stereo';
  V.SourceAudioBitrateKbps := 192;
  Assert.AreEqual('aac stereo 192 kbps',
    FormatStatusBarToken(MakeToken(tkAudio), V));
end;

procedure TTestStatusBarFormatters.TestAudioOmitsEmptyChannels;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.VideoInfoValid := True;
  V.SourceAudioCodec := 'aac';
  V.SourceAudioSampleRate := 48000;
  V.SourceAudioBitrateKbps := 192;
  Assert.AreEqual('aac 48000 Hz 192 kbps',
    FormatStatusBarToken(MakeToken(tkAudio), V));
end;

procedure TTestStatusBarFormatters.TestAudioOmitsZeroBitrate;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.VideoInfoValid := True;
  V.SourceAudioCodec := 'aac';
  V.SourceAudioSampleRate := 48000;
  V.SourceAudioChannels := 'stereo';
  Assert.AreEqual('aac 48000 Hz stereo',
    FormatStatusBarToken(MakeToken(tkAudio), V));
end;

procedure TTestStatusBarFormatters.TestLoadTimePassesThrough;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.LoadTimeText := 'cache 5/12 1.23s';
  Assert.AreEqual('cache 5/12 1.23s',
    FormatStatusBarToken(MakeToken(tkLoadTime), V));
end;

procedure TTestStatusBarFormatters.TestLoadTimeEmptyWhenUnset;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkLoadTime), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestSaveDimensionUnavailableEmpty;
begin
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkSaveDimension), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestSaveDimensionWithoutCapShowsBareSize;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SaveDimAvailable := True;
  V.SaveDimW := 1920;       V.SaveDimH := 1080;
  V.SaveDimCappedW := 1920; V.SaveDimCappedH := 1080;  {cap == source -> no transform}
  Assert.AreEqual('Save: 1920x1080',
    FormatStatusBarToken(MakeToken(tkSaveDimension), V));
end;

procedure TTestStatusBarFormatters.TestSaveDimensionWithCapAppendsTransform;
var
  V: TStatusBarValues;
  S: string;
begin
  V := EmptyValues;
  V.SaveDimAvailable := True;
  V.SaveDimW := 1920;      V.SaveDimH := 1080;
  V.SaveDimCappedW := 192; V.SaveDimCappedH := 108;
  S := FormatStatusBarToken(MakeToken(tkSaveDimension), V);
  Assert.IsTrue(S.StartsWith('Save: 1920x1080'),
    'Expected pre-cap dimensions first');
  Assert.IsTrue(S.EndsWith('192x108'),
    'Expected post-cap dimensions last');
end;

procedure TTestStatusBarFormatters.TestSaveDimensionCapEqualsToSourceOmitsTransform;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SaveDimAvailable := True;
  V.SaveDimW := 800;       V.SaveDimH := 600;
  V.SaveDimCappedW := 800; V.SaveDimCappedH := 600;
  Assert.AreEqual('Save: 800x600',
    FormatStatusBarToken(MakeToken(tkSaveDimension), V),
    'When capping is a no-op, the transform glyph must not appear');
end;

procedure TTestStatusBarFormatters.TestSaveDimensionCapFalseSuppressesTransform;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.SaveDimAvailable := True;
  V.SaveDimW := 1920;      V.SaveDimH := 1080;
  V.SaveDimCappedW := 192; V.SaveDimCappedH := 108;
  Assert.AreEqual('Save: 1920x1080',
    FormatStatusBarToken(MakeTokenWithAttr(tkSaveDimension, ATTR_CAP, 'false'), V),
    'cap=false must suppress the post-cap segment even when capping fires');
end;

procedure TTestStatusBarFormatters.TestSaveDimensionWithCapInjectsGlyphLiteral;
var
  V: TStatusBarValues;
begin
  {Pins the injected-glyph contract: whatever the caller passes for
   AResolutionTransformGlyph appears verbatim between the pre-cap and
   post-cap halves. The formatter used to query PlatformDetect itself,
   which made it OS-dependent and untestable; this test proves the
   coupling is gone.}
  V := EmptyValues;
  V.SaveDimAvailable := True;
  V.SaveDimW := 1920;      V.SaveDimH := 1080;
  V.SaveDimCappedW := 192; V.SaveDimCappedH := 108;
  Assert.AreEqual('Save: 1920x1080-XYZ-192x108',
    FormatStatusBarToken(MakeToken(tkSaveDimension), V, '-XYZ-'));
end;

procedure TTestStatusBarFormatters.TestCopyDimensionUsesCopyLabel;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.CopyDimAvailable := True;
  V.CopyDimW := 800;       V.CopyDimH := 600;
  V.CopyDimCappedW := 800; V.CopyDimCappedH := 600;
  Assert.AreEqual('Copy: 800x600',
    FormatStatusBarToken(MakeToken(tkCopyDimension), V));
end;

procedure TTestStatusBarFormatters.TestViewModePassesThrough;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.ViewModeName := 'Smart Grid';
  Assert.AreEqual('Smart Grid',
    FormatStatusBarToken(MakeToken(tkViewMode), V));
end;

procedure TTestStatusBarFormatters.TestZoomPassesThrough;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.ZoomModeName := 'Fit window';
  Assert.AreEqual('Fit window',
    FormatStatusBarToken(MakeToken(tkZoom), V));
end;

procedure TTestStatusBarFormatters.TestUppercaseCasingUppercasesResult;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.ViewModeName := 'Smart Grid';
  Assert.AreEqual('SMART GRID',
    FormatStatusBarToken(MakeToken(tkViewMode, tcUpper), V));
end;

procedure TTestStatusBarFormatters.TestUppercaseCasingDoesNothingWhenEmpty;
begin
  {No data + tcUpper must still return '' — UpperCase('') is '' but we
   want to be sure the casing branch doesn't accidentally synthesise
   anything.}
  Assert.AreEqual('',
    FormatStatusBarToken(MakeToken(tkResolution, tcUpper), EmptyValues));
end;

procedure TTestStatusBarFormatters.TestAsIsCasingPreservesCase;
var
  V: TStatusBarValues;
begin
  V := EmptyValues;
  V.ViewModeName := 'Smart Grid';
  Assert.AreEqual('Smart Grid',
    FormatStatusBarToken(MakeToken(tkViewMode, tcAsIs), V));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStatusBarFormatters);

end.
