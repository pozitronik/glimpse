{Pre-extraction orchestration for the WCX plugin.

 Given an opened TArchiveHandle (with Settings / Offsets / Presets
 populated by DoOpenArchive), this controller drives the IFrameExtractor
 to produce the temp-file cache that ReadHeaderExW reports sizes from
 and ProcessFile copies into the user's destination.

 Two extraction shapes: combined sheet (one image rendered via
 RenderCombinedBitmap into the cache slot AFTER the per-frame slots)
 and separate frames (one image per offset). PreExtractFrames composes
 them based on H.Settings.ShowFrames / ShowCombined.

 Lives in its own unit so the ABI thunks in uWcxExports stay narrow
 and the orchestration is independently testable. The TWcxFrameCache
 session lifecycle is owned by PreExtractFrames here (BeginExtractionSession
 / Free); ExtractCombinedToCache and ExtractSeparateToCache receive an
 active session passed in and just populate its slots.

 Security caveat (preserved from the original PreExtractFrames home in
 uWcxExports): the temp directory inherits the parent (user temp) ACL,
 so other processes running as the same user can read the extracted
 frames. Same exposure as ffmpeg's own temp output and as the WLX
 frame cache. Tightening would require an explicit per-directory ACL
 via SetSecurityInfo. Acceptable for a single-user TC session;
 revisit if multi-user or sandboxed contexts ever become a use case.}
unit uWcxExtractionController;

interface

uses
  uFrameExtractor,
  uWcxArchiveHandle, uWcxFrameCache;

{Extracts the combined sheet into the session's temp directory at the
 slot reserved for "the combined image". ARenderCombinedBitmap (in
 uWcxEntryExtractors) produces the bitmap; the saver bundle on
 H.Settings.SaveOptions drives the file format. The combined slot is
 the one immediately after the frames - when frames are also being
 shown the combined image lands at index Length(Offsets); when frames
 are off it lands at index 0. RenderCombinedBitmap lives in
 uWcxEntryExtractors so this pre-extract path and TCombinedEntry.Extract
 share the same composition rules.}
procedure ExtractCombinedToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);

{Extracts individual frames and writes each into the session's per-frame
 slot. One file per H.Offsets[I].}
procedure ExtractSeparateToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);

{Top-level entry. Pre-extracts all frames to the module's
 TWcxFrameCache, or reuses an existing cache entry if the same video
 was already extracted.

 The session held by BeginExtractionSession owns the cache lock for its
 lifetime - a concurrent OpenArchive on a second thread blocks here
 until this pass finishes, which is intentional: two threads on the
 same video must not both proceed past the cache-hit check.

 Calls ExtractSeparateToCache / ExtractCombinedToCache as required by
 H.Settings.ShowFrames / ShowCombined and records the produced
 EntrySizes back on H so ReadHeaderExW can report believable sizes.}
procedure PreExtractFrames(H: TArchiveHandle);

implementation

uses
  System.SysUtils, System.IOUtils,
  Vcl.Graphics,
  uFrameFileNames, uBitmapSaver, uDebugLog, uTypes,
  uWcxSettings, uWcxListing, uWcxEntryExtractors;

procedure WcxControllerLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

{Builds extraction options from WCX settings.
 AMaxSide = 0 means no scale limit (combined-mode caller relies on this:
 the assembled grid is shrunk separately after rendering). For
 separate-frame mode, pass H.Settings.FrameMaxSide so ffmpeg's scale
 filter fits the longer dimension to the cap.}
function BuildExtractionOptions(ASettings: TWcxSettings; AMaxSide: Integer = 0): TExtractionOptions;
begin
  Result := ASettings.Extraction.ToExtractionOptions(AMaxSide);
end;

procedure ExtractCombinedToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);
var
  Combined: TBitmap;
  TempPath: string;
  Slot: Integer;
begin
  Combined := uWcxEntryExtractors.RenderCombinedBitmap(H, AExtractor);
  if Combined = nil then
    Exit;
  try
    TempPath := TPath.Combine(ASession.CachedTempDir, GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat));
    SaveBitmapToFile(Combined, TempPath, H.Settings.SaveOptions);
    if H.Settings.ShowFrames then
      Slot := Length(H.Offsets)
    else
      Slot := 0;
    ASession.RecordSlot(Slot, TempPath, TFile.GetSize(TempPath));
  finally
    Combined.Free;
  end;
end;

procedure ExtractSeparateToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);
var
  Bmp: TBitmap;
  TempPath: string;
  I: Integer;
  Options: TExtractionOptions;
begin
  Options := BuildExtractionOptions(H.Settings, H.Settings.FrameMaxSide);
  for I := 0 to Length(H.Offsets) - 1 do
  begin
    Bmp := AExtractor.ExtractFrame(H.FileName, H.Offsets[I].TimeOffset, Options);
    if Bmp = nil then
      Continue;
    try
      TempPath := TPath.Combine(ASession.CachedTempDir, GenerateFrameFileName(H.FileName, I, H.Offsets[I].TimeOffset, H.Settings.SaveFormat));
      SaveBitmapToFile(Bmp, TempPath, H.Settings.SaveOptions);
      ASession.RecordSlot(I, TempPath, TFile.GetSize(TempPath));
    finally
      Bmp.Free;
    end;
  end;
end;

procedure PreExtractFrames(H: TArchiveHandle);
var
  Session: TWcxCacheExtractionSession;
  EntryCount: Integer;
  TempDir: string;
begin
  Session := TWcxFrameCache.Instance.BeginExtractionSession;
  try
    if Session.TryHit(H.FileName, H.TempPaths, H.EntrySizes) then
    begin
      WcxControllerLog(Format('PreExtract: cache hit for %s', [H.FileName]));
      Exit;
    end;

    {Cache arrays size to legacy entries only; preset entries do not
     pre-extract (they run on demand during ProcessFile).}
    EntryCount := LegacyEntryCount(H.Offsets, H.Settings.ShowFrames, H.Settings.ShowCombined);
    TempDir := Session.PrepareFresh(H.FileName, EntryCount);

    {Each enabled mode populates its own cache slots. Both can run in
     the same pass when the user has both Show* bits on. The frame
     extractor is the per-session one already on the handle (set at
     OpenArchive).}
    if H.Settings.ShowFrames then
      ExtractSeparateToCache(H, H.FrameExtractor, Session);
    if H.Settings.ShowCombined then
      ExtractCombinedToCache(H, H.FrameExtractor, Session);

    Session.PublishTo(H.TempPaths, H.EntrySizes);
    WcxControllerLog(Format('PreExtract: %d entries to %s', [EntryCount, TempDir]));
  finally
    Session.Free;
  end;
end;

end.
