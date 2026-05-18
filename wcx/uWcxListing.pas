{Builds the typed entry list a WCX archive presents to Total Commander.
 Composes up to three independent listing sources — separate frames, the
 combined contact sheet, and user-defined ffmpeg presets — based on the
 booleans the caller passes in. Any combination is valid (including the
 all-off "empty archive" case). Filenames are deduped across the whole
 set so a preset template that happens to match a frame name still gets
 the (N) suffix.
 Pure data transformation — no I/O, no globals, no FFmpeg invocation.
 The WCX export layer consumes the result to drive ReadHeaderExW iteration
 and to dispatch ProcessFile to the appropriate extractor.}
unit uWcxListing;

interface

uses
  uBitmapSaver,
  uFrameOffsets,
  uWcxPresets;

type
  {Distinguishes the three sources an archive entry can come from.
   - ekFrame: one of the per-frame still images
   - ekCombined: the single contact-sheet image
   - ekPreset: a user-defined ffmpeg preset transcode}
  TWcxEntryKind = (ekFrame, ekCombined, ekPreset);

  {One row in the archive listing as TC sees it.
   FileName is the post-dedupe display name. LegacyIndex maps to the
   slot in the cache arrays (TempPaths / EntrySizes) for ekFrame and
   ekCombined entries — frames occupy slots 0..N-1 (when shown), the
   combined image occupies the slot right after them. PresetIndex points
   into the preset array for ekPreset; both indices are -1 when not
   applicable so a misuse traps loudly instead of silently picking 0.}
  TWcxListingEntry = record
    FileName: string;
    Kind: TWcxEntryKind;
    LegacyIndex: Integer;
    PresetIndex: Integer;
  end;

  TWcxListingEntryArray = TArray<TWcxListingEntry>;

{Builds the full archive listing for a video.
 The three booleans select which sources contribute entries; their order
 in the listing is fixed at frames first, combined next, presets last so
 existing TC scripts that key off the legacy positions stay stable.
 Frame entries occupy LegacyIndex 0..Length(AOffsets)-1 when shown; the
 combined entry occupies the slot immediately after (Length(AOffsets) if
 frames are shown, 0 otherwise). The cache layer sizes its arrays to the
 same scheme.
 Filename dedupe runs across the whole composed listing, not per source.
 First-defined wins the bare name, subsequent collisions get "(N)"
 suffixes — frames before combined before presets.}
function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray; AShowFrames, AShowCombined, AShowPresets: Boolean;
  ASaveFormat: TSaveFormat; const APresets: TWcxPresetArray): TWcxListingEntryArray;

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

function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray; AShowFrames, AShowCombined, AShowPresets: Boolean;
  ASaveFormat: TSaveFormat; const APresets: TWcxPresetArray): TWcxListingEntryArray;
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
   frames; FrameCount=0 means it lands at slot 0 instead. The dispatcher
   uses Entry.LegacyIndex to look up TempPaths, so the slot number must
   match what PreExtractFrames will populate.}
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
      Result[EntryIdx].FileName := AllNames[EntryIdx];
      Result[EntryIdx].Kind := ekFrame;
      Result[EntryIdx].LegacyIndex := I;
      Result[EntryIdx].PresetIndex := -1;
      Inc(EntryIdx);
    end;
  if AShowCombined then
  begin
    Result[EntryIdx].FileName := AllNames[EntryIdx];
    Result[EntryIdx].Kind := ekCombined;
    Result[EntryIdx].LegacyIndex := CombinedSlot;
    Result[EntryIdx].PresetIndex := -1;
  end;
  for I := 0 to PresetCount - 1 do
  begin
    Result[LegacyCount + I].FileName := AllNames[LegacyCount + I];
    Result[LegacyCount + I].Kind := ekPreset;
    Result[LegacyCount + I].LegacyIndex := -1;
    Result[LegacyCount + I].PresetIndex := I;
  end;
end;

end.
