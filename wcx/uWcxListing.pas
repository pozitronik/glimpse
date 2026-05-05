{Builds the typed entry list a WCX archive presents to Total Commander.
 Combines the legacy frame / combined-sheet entries with the user-defined
 preset entries (when the master switch is on), then dedupes filenames
 across the whole listing so a preset whose template happens to match a
 frame filename gets the auto-suffixed treatment too.
 Pure data transformation — no I/O, no globals, no FFmpeg invocation.
 The WCX export layer consumes the result to drive ReadHeaderExW iteration
 and to dispatch ProcessFile to the appropriate extractor.}
unit uWcxListing;

interface

uses
  uBitmapSaver,
  uFrameOffsets,
  uWcxSettings,
  uWcxPresets;

type
  {Distinguishes the three sources an archive entry can come from.
   - ekFrame: one of the per-frame still images in womSeparate mode
   - ekCombined: the single contact-sheet image in womCombined mode
   - ekPreset: a user-defined ffmpeg preset transcode (Step 6 wires the
     actual extractor; Step 3 lists them but ProcessFile refuses extract)}
  TWcxEntryKind = (ekFrame, ekCombined, ekPreset);

  {One row in the archive listing as TC sees it.
   FileName is the post-dedupe display name; LegacyIndex points into the
   frame offset / temp path arrays for ekFrame and into temp path slot 0
   for ekCombined; PresetIndex points into the preset array for ekPreset.
   The two indices are -1 when not applicable so a misuse traps loudly
   instead of silently picking entry 0.}
  TWcxListingEntry = record
    FileName: string;
    Kind: TWcxEntryKind;
    LegacyIndex: Integer;
    PresetIndex: Integer;
  end;

  TWcxListingEntryArray = TArray<TWcxListingEntry>;

{Builds the full archive listing for a video.
 Legacy entries (frames or combined sheet, depending on AOutputMode) come
 first so existing TC scripts that key off the well-known names continue to
 work. When AUsePresets is True, every preset is appended after the legacy
 entries with its filename expanded against AVideoFileName. Filenames are
 deduped across the whole set: a preset template that produces the same
 name as a frame entry gets the (N) suffix, with the legacy entry winning
 the bare name because legacy comes first in iteration order.
 When AUsePresets is False, the preset list is ignored entirely so the
 listing matches the pre-presets behaviour bit-for-bit.}
function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray; AOutputMode: TWcxOutputMode; ASaveFormat: TSaveFormat;
  AUsePresets: Boolean; const APresets: TWcxPresetArray): TWcxListingEntryArray;

implementation

uses
  uFrameFileNames;

function BuildArchiveListing(const AVideoFileName: string; const AOffsets: TFrameOffsetArray; AOutputMode: TWcxOutputMode; ASaveFormat: TSaveFormat;
  AUsePresets: Boolean; const APresets: TWcxPresetArray): TWcxListingEntryArray;
var
  I, LegacyCount, PresetCount: Integer;
  AllNames: TArray<string>;
begin
  if AOutputMode = womCombined then
    LegacyCount := 1
  else
    LegacyCount := Length(AOffsets);

  if AUsePresets then
    PresetCount := Length(APresets)
  else
    PresetCount := 0;

  {Build a flat name array for the dedupe pass; cross-section dedupe is
   why the legacy and preset names share one input rather than dedupe-ing
   each section independently.}
  SetLength(AllNames, LegacyCount + PresetCount);
  if AOutputMode = womCombined then
    AllNames[0] := GenerateCombinedFileName(AVideoFileName, ASaveFormat)
  else
    for I := 0 to LegacyCount - 1 do
      AllNames[I] := GenerateFrameFileName(AVideoFileName, I, AOffsets[I].TimeOffset, ASaveFormat);
  for I := 0 to PresetCount - 1 do
    AllNames[LegacyCount + I] := BuildOutputFileName(APresets[I], AVideoFileName);

  AllNames := DeduplicateFileNames(AllNames);

  SetLength(Result, LegacyCount + PresetCount);
  for I := 0 to LegacyCount - 1 do
  begin
    Result[I].FileName := AllNames[I];
    if AOutputMode = womCombined then
    begin
      Result[I].Kind := ekCombined;
      {Combined uses temp-path slot 0; LegacyIndex=0 keeps the lookup
       uniform with ekFrame so the extractor can index TempPaths the same
       way for both kinds.}
      Result[I].LegacyIndex := 0;
    end
    else
    begin
      Result[I].Kind := ekFrame;
      Result[I].LegacyIndex := I;
    end;
    Result[I].PresetIndex := -1;
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
