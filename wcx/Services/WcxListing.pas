{Builds the IWcxEntryExtractor array TC sees as an archive listing.
 Composes frames + combined sheet + user presets per the Show* flags.
 Filenames are deduped across the whole set so a preset template that
 happens to match a frame name still gets the (N) suffix. Pure
 transformation — no I/O.}
unit WcxListing;

interface

uses
  BitmapSaver,
  FrameOffsets,
  WcxPresets, WcxPresetTemplate, FileNameDedupe,
  WcxEntryExtractors;

{Order is fixed (frames, combined, presets) so existing TC scripts that
 key off legacy positions stay stable. Dedupe runs across the composed
 listing; first-defined wins the bare name.}
function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray;
  AShowFrames, AShowCombined, AShowPresets: Boolean; ASaveFormat: TSaveFormat;
  const APresets: TWcxPresetArray): TWcxEntryExtractorArray;

{Single source of truth for the cache slot-numbering invariant: the
 cache layer calls this BEFORE the listing exists, and
 BuildArchiveListing uses it internally. Presets do not pre-extract.}
function LegacyEntryCount(const AOffsets: TFrameOffsetArray; AShowFrames, AShowCombined: Boolean): Integer;

implementation

uses
  FrameFileNames;

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

  {TCombinedEntry carries this slot so Extract looks up the right
   TempPaths entry without re-deriving it from the iteration position.}
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
