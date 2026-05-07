unit TestWcxListing;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxListing = class
  public
    { Backwards-compatible legacy listing: presets off }
    [Test] procedure TestSeparateModeNoPresetsMatchesFrameOnlyListing;
    [Test] procedure TestCombinedModeNoPresetsSingleEntry;
    [Test] procedure TestUsePresetsFalseIgnoresPresetArray;
    [Test] procedure TestEmptyPresetArrayIsBitForBitSameAsOff;
    { Listing extension when presets are on }
    [Test] procedure TestPresetAppendedAfterFrames;
    [Test] procedure TestMultiplePresetsPreserveDefinitionOrder;
    [Test] procedure TestCombinedPlusPresetIsTwoEntries;
    { Cross-section dedupe: a preset name colliding with a frame name }
    [Test] procedure TestPresetCollidingWithFrameGetsSuffix;
    [Test] procedure TestPresetVsPresetCollisionStillDedupes;
    { Entry shape contracts that the dispatch code in uWcxExports relies on }
    [Test] procedure TestFrameEntryHasMatchingLegacyIndex;
    [Test] procedure TestCombinedEntryHasLegacyIndexZero;
    [Test] procedure TestPresetEntryHasNegativeLegacyIndex;
    [Test] procedure TestPresetEntryPresetIndexMatchesArrayPosition;
  end;

implementation

uses
  System.SysUtils,
  uBitmapSaver, uFrameOffsets, uFrameFileNames,
  uWcxPresets, uWcxListing;

{ Helpers }

function MakeOffsets(ACount: Integer): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := (I + 1) * 10.0;
  end;
end;

function MakePreset(const AName, AOutputName, AOutputExt: string): TWcxPreset;
begin
  Result := Default(TWcxPreset);
  Result.Name := AName;
  Result.OutputName := AOutputName;
  Result.OutputExt := AOutputExt;
  Result.Enabled := True;
end;

{ Backwards-compatible legacy listing }

procedure TTestWcxListing.TestSeparateModeNoPresetsMatchesFrameOnlyListing;
var
  Offsets: TFrameOffsetArray;
  Listing: TWcxListingEntryArray;
  I: Integer;
  Expected: string;
begin
  Offsets := MakeOffsets(3);
  Listing := BuildArchiveListing('C:\v\Movie.mkv', Offsets, True, False, False, sfPNG, nil);
  Assert.AreEqual(3, Integer(Length(Listing)));
  for I := 0 to 2 do
  begin
    Expected := GenerateFrameFileName('C:\v\Movie.mkv', I, Offsets[I].TimeOffset, sfPNG);
    Assert.AreEqual(Expected, Listing[I].FileName, Format('Frame %d filename mismatch', [I]));
    Assert.IsTrue(Listing[I].Kind = ekFrame, 'Frame entries must report ekFrame');
  end;
end;

procedure TTestWcxListing.TestCombinedModeNoPresetsSingleEntry;
var
  Listing: TWcxListingEntryArray;
begin
  Listing := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(5), False, True, False, sfJPEG, nil);
  Assert.AreEqual(1, Integer(Length(Listing)),
    'Combined mode produces exactly one entry regardless of frame count');
  Assert.IsTrue(Listing[0].Kind = ekCombined);
  Assert.AreEqual(GenerateCombinedFileName('C:\v\Movie.mkv', sfJPEG), Listing[0].FileName);
end;

procedure TTestWcxListing.TestUsePresetsFalseIgnoresPresetArray;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  { Even when a non-empty preset list is passed in, the master switch off
    must keep the legacy behaviour identical so existing installs see no
    change after upgrading to a presets-aware build. }
  SetLength(Presets, 2);
  Presets[0] := MakePreset('audio', '', 'mp3');
  Presets[1] := MakePreset('poster', '', 'jpg');
  Listing := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(2), True, False, False, sfPNG, Presets);
  Assert.AreEqual(2, Integer(Length(Listing)),
    'UsePresets=False must not surface any preset entries');
end;

procedure TTestWcxListing.TestEmptyPresetArrayIsBitForBitSameAsOff;
var
  ListingOn, ListingOff: TWcxListingEntryArray;
  I: Integer;
begin
  ListingOff := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(4), True, False, False, sfPNG, nil);
  ListingOn := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(4), True, False, True, sfPNG, nil);
  Assert.AreEqual(Integer(Length(ListingOff)), Integer(Length(ListingOn)));
  for I := 0 to High(ListingOff) do
    Assert.AreEqual(ListingOff[I].FileName, ListingOn[I].FileName);
end;

{ Listing extension when presets are on }

procedure TTestWcxListing.TestPresetAppendedAfterFrames;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  SetLength(Presets, 1);
  Presets[0] := MakePreset('audio', '%basename%_track', 'mp3');
  Listing := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(2), True, False, True, sfPNG, Presets);
  Assert.AreEqual(3, Integer(Length(Listing)),
    'Two frames + one preset = three entries');
  { Preset must be at the END so the legacy frame indices stay where TC and
    any pre-existing scripts expect them. }
  Assert.IsTrue(Listing[0].Kind = ekFrame);
  Assert.IsTrue(Listing[1].Kind = ekFrame);
  Assert.IsTrue(Listing[2].Kind = ekPreset);
  Assert.AreEqual('Movie_track.mp3', Listing[2].FileName);
end;

procedure TTestWcxListing.TestMultiplePresetsPreserveDefinitionOrder;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  SetLength(Presets, 3);
  Presets[0] := MakePreset('first', 'a', 'mp3');
  Presets[1] := MakePreset('second', 'b', 'mp3');
  Presets[2] := MakePreset('third', 'c', 'mp3');
  Listing := BuildArchiveListing('C:\v\X.mkv', MakeOffsets(0), True, False, True, sfPNG, Presets);
  Assert.AreEqual(3, Integer(Length(Listing)));
  Assert.AreEqual('a.mp3', Listing[0].FileName);
  Assert.AreEqual('b.mp3', Listing[1].FileName);
  Assert.AreEqual('c.mp3', Listing[2].FileName);
end;

procedure TTestWcxListing.TestCombinedPlusPresetIsTwoEntries;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  SetLength(Presets, 1);
  Presets[0] := MakePreset('audio', '', 'mp3');
  Listing := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(5), False, True, True, sfJPEG, Presets);
  Assert.AreEqual(2, Integer(Length(Listing)));
  Assert.IsTrue(Listing[0].Kind = ekCombined);
  Assert.IsTrue(Listing[1].Kind = ekPreset);
end;

{ Cross-section dedupe }

procedure TTestWcxListing.TestPresetCollidingWithFrameGetsSuffix;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
  FrameName: string;
begin
  { Construct a preset whose final filename matches the first frame name.
    Because legacy entries come first in the dedupe pass, the frame keeps
    the bare name and the preset gets the (2) suffix. This must apply
    cross-section, otherwise extracting both back-to-back would silently
    overwrite the first. }
  FrameName := GenerateFrameFileName('C:\v\Movie.mkv', 0, 10.0, sfPNG);
  SetLength(Presets, 1);
  Presets[0].Name := 'p';
  Presets[0].Enabled := True;
  Presets[0].OutputName := ChangeFileExt(FrameName, '');
  Presets[0].OutputExt := Copy(ExtractFileExt(FrameName), 2, MaxInt);
  Listing := BuildArchiveListing('C:\v\Movie.mkv', MakeOffsets(1), True, False, True, sfPNG, Presets);
  Assert.AreEqual(2, Integer(Length(Listing)));
  Assert.AreEqual(FrameName, Listing[0].FileName, 'Legacy entry wins the bare name');
  Assert.AreEqual(ChangeFileExt(FrameName, '') + '(2)' + ExtractFileExt(FrameName), Listing[1].FileName);
end;

procedure TTestWcxListing.TestPresetVsPresetCollisionStillDedupes;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  SetLength(Presets, 2);
  Presets[0] := MakePreset('p1', 'poster', 'jpg');
  Presets[1] := MakePreset('p2', 'poster', 'jpg');
  Listing := BuildArchiveListing('C:\v\X.mkv', MakeOffsets(0), True, False, True, sfPNG, Presets);
  Assert.AreEqual('poster.jpg', Listing[0].FileName);
  Assert.AreEqual('poster(2).jpg', Listing[1].FileName);
end;

{ Entry shape contracts }

procedure TTestWcxListing.TestFrameEntryHasMatchingLegacyIndex;
var
  Listing: TWcxListingEntryArray;
  I: Integer;
begin
  { LegacyIndex on a frame entry must equal its position in the legacy
    section, because the extractor uses it to index Offsets and TempPaths. }
  Listing := BuildArchiveListing('C:\v\X.mkv', MakeOffsets(4), True, False, False, sfPNG, nil);
  for I := 0 to 3 do
    Assert.AreEqual(I, Listing[I].LegacyIndex);
end;

procedure TTestWcxListing.TestCombinedEntryHasLegacyIndexZero;
var
  Listing: TWcxListingEntryArray;
begin
  { Combined uses temp-path slot 0; the dispatch code expects LegacyIndex=0
    so the same TryCopyCachedFrame call works for both ekFrame and ekCombined. }
  Listing := BuildArchiveListing('C:\v\X.mkv', MakeOffsets(5), False, True, False, sfPNG, nil);
  Assert.AreEqual(0, Listing[0].LegacyIndex);
end;

procedure TTestWcxListing.TestPresetEntryHasNegativeLegacyIndex;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  { Sentinel -1 traps the "preset routed through the frame extractor" misuse
    loudly via a bounds error rather than silently picking offset 0. }
  SetLength(Presets, 1);
  Presets[0] := MakePreset('p', 'foo', 'mp3');
  Listing := BuildArchiveListing('C:\v\X.mkv', MakeOffsets(2), True, False, True, sfPNG, Presets);
  Assert.AreEqual(-1, Listing[2].LegacyIndex);
end;

procedure TTestWcxListing.TestPresetEntryPresetIndexMatchesArrayPosition;
var
  Presets: TWcxPresetArray;
  Listing: TWcxListingEntryArray;
begin
  { PresetIndex is what the extractor will use to fetch the actual TWcxPreset
    record (Args, OutputExt, etc.). Pinning this contract here means the
    Step 6 extractor wiring just dereferences APresets[Listing[I].PresetIndex]
    without re-deriving anything from FileName. }
  SetLength(Presets, 3);
  Presets[0] := MakePreset('a', 'a', 'mp3');
  Presets[1] := MakePreset('b', 'b', 'mp3');
  Presets[2] := MakePreset('c', 'c', 'mp3');
  Listing := BuildArchiveListing('C:\v\X.mkv', MakeOffsets(0), True, False, True, sfPNG, Presets);
  Assert.AreEqual(0, Listing[0].PresetIndex);
  Assert.AreEqual(1, Listing[1].PresetIndex);
  Assert.AreEqual(2, Listing[2].PresetIndex);
end;

end.
