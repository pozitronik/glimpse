{Builds the typed entry list a WCX archive presents to Total Commander.
 Composes up to three independent listing sources — separate frames, the
 combined contact sheet, and user-defined ffmpeg presets — based on the
 booleans the caller passes in. Any combination is valid (including the
 all-off "empty archive" case). Filenames are deduped across the whole
 set so a preset template that happens to match a frame name still gets
 the (N) suffix.
 Pure data transformation — no I/O, no globals, no FFmpeg invocation.
 The WCX export layer consumes the result to drive ReadHeaderExW iteration
 and to dispatch ProcessFile to the appropriate extractor. Each entry is
 an IWcxEntryExtractor (TFrameEntry / TCombinedEntry / TPresetEntry) so
 the dispatch reduces to a single polymorphic call rather than a switch
 on a Kind enum.}
unit uWcxListing;

interface

uses
  uBitmapSaver,
  uFrameOffsets,
  uWcxPresets, uWcxPresetTemplate, uFileNameDedupe,
  uWcxEntryExtractors;

{Builds the full archive listing for a video.
 The three booleans select which sources contribute entries; their order
 in the listing is fixed at frames first, combined next, presets last so
 existing TC scripts that key off the legacy positions stay stable.
 Frame entries occupy slot 0..Length(AOffsets)-1 when shown; the
 combined entry occupies the slot immediately after (Length(AOffsets) if
 frames are shown, 0 otherwise). The cache layer sizes its arrays to the
 same scheme.
 Filename dedupe runs across the whole composed listing, not per source.
 First-defined wins the bare name, subsequent collisions get "(N)"
 suffixes — frames before combined before presets.}
function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray;
  AShowFrames, AShowCombined, AShowPresets: Boolean; ASaveFormat: TSaveFormat;
  const APresets: TWcxPresetArray): TWcxEntryExtractorArray;

{Number of legacy (frame + combined) entries the cache code sizes its
 temp arrays against. Frames contribute Length(AOffsets) when shown; the
 combined image contributes one slot after. Presets do not pre-extract
 and so consume no temp slots. Single source of truth for the
 slot-numbering invariant: BuildArchiveListing uses it internally, and
 the cache layer in uWcxExports calls it before the listing exists.}
function LegacyEntryCount(const AOffsets: TFrameOffsetArray; AShowFrames, AShowCombined: Boolean): Integer;

implementation

uses
  uFrameFileNames;

function LegacyEntryCount(const AOffsets: TFrameOffsetArray; AShowFrames, AShowCombined: Boolean): Integer;
begin
  Result := 0;
  if AShowFrames then
    Result := Length(AOffsets);
  if AShowCombined then
    Inc(Result);
end;

function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray;
  AShowFrames, AShowCombined, AShowPresets: Boolean; ASaveFormat: TSaveFormat;
  const APresets: TWcxPresetArray): TWcxEntryExtractorArray;
var
  I, FrameCount, LegacyCount, PresetCount, EntryIdx, CombinedSlot: Integer;
  AllNames: TArray<string>;
begin
  if AShowFrames then
    FrameCount := Length(AOffsets)
  else
    FrameCount := 0;

  LegacyCount := LegacyEntryCount(AOffsets, AShowFrames, AShowCombined);

  if AShowPresets then
    PresetCount := Length(APresets)
  else
    PresetCount := 0;

  {The combined image sits in the cache slot immediately after the
   frames; FrameCount=0 means it lands at slot 0 instead. TCombinedEntry
   carries this slot so its Extract call looks up the right TempPaths
   entry without re-deriving it from the iteration position.}
  CombinedSlot := FrameCount;

  SetLength(AllNames, LegacyCount + PresetCount);
  EntryIdx := 0;
  if AShowFrames then
    for I := 0 to FrameCount - 1 do
    begin
      AllNames[EntryIdx] := GenerateFrameFileName(AVideoFileName, I, AOffsets[I].TimeOffset, ASaveFormat);
      Inc(EntryIdx);
    end;
  if AShowCombined then
    AllNames[EntryIdx] := GenerateCombinedFileName(AVideoFileName, ASaveFormat);
  for I := 0 to PresetCount - 1 do
    AllNames[LegacyCount + I] := BuildOutputFileName(APresets[I], AVideoFileName);

  AllNames := DeduplicateFileNames(AllNames);

  SetLength(Result, LegacyCount + PresetCount);
  EntryIdx := 0;
  if AShowFrames then
    for I := 0 to FrameCount - 1 do
    begin
      Result[EntryIdx] := TFrameEntry.Create(AllNames[EntryIdx], I);
      Inc(EntryIdx);
    end;
  if AShowCombined then
    Result[EntryIdx] := TCombinedEntry.Create(AllNames[EntryIdx], CombinedSlot);
  for I := 0 to PresetCount - 1 do
    Result[LegacyCount + I] := TPresetEntry.Create(AllNames[LegacyCount + I], I);
end;

end.
