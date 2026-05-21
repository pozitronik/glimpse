{Pre-extraction orchestration for the WCX plugin. Drives IFrameExtractor
 to populate the temp cache that ReadHeaderExW reports sizes from and
 ProcessFile copies into the user's destination.

 Security caveat: the temp directory inherits the parent (user temp) ACL,
 so any process running as the same user can read the extracted frames.
 Tightening would require an explicit per-directory ACL via
 SetSecurityInfo; acceptable for a single-user TC session.}
unit WcxExtractionController;

interface

uses
  FrameExtractor,
  WcxArchiveHandle, WcxFrameCache;

{Combined slot lands at Length(Offsets) when frames are shown, else 0.}
procedure ExtractCombinedToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);

procedure ExtractSeparateToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);

{Holds the cache lock for the full extraction so two threads opening
 the same video cannot both proceed past the cache-hit check.}
procedure PreExtractFrames(H: TArchiveHandle; const AFrameCache: IWcxFrameCache);

implementation

uses
  System.SysUtils, System.IOUtils,
  Vcl.Graphics,
  FrameFileNames, Logging, Types,
  WcxSettings, WcxListing, WcxEntryExtractors;

procedure WcxControllerLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

{AMaxSide = 0 disables ffmpeg's scale filter; combined-mode relies on
 this since the assembled grid is shrunk separately.}
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
  Combined := WcxEntryExtractors.RenderCombinedBitmap(H, AExtractor);
  if Combined = nil then
    Exit;
  try
    TempPath := TPath.Combine(ASession.CachedTempDir, GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat));
    H.BitmapSaver.Save(Combined, TempPath, H.Settings.SaveOptions);
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
      H.BitmapSaver.Save(Bmp, TempPath, H.Settings.SaveOptions);
      ASession.RecordSlot(I, TempPath, TFile.GetSize(TempPath));
    finally
      Bmp.Free;
    end;
  end;
end;

procedure PreExtractFrames(H: TArchiveHandle; const AFrameCache: IWcxFrameCache);
var
  Session: TWcxCacheExtractionSession;
  EntryCount: Integer;
  TempDir: string;
begin
  Session := AFrameCache.BeginExtractionSession;
  try
    if Session.TryHit(H.FileName, H.TempPaths, H.EntrySizes) then
    begin
      WcxControllerLog(Format('PreExtract: cache hit for %s', [H.FileName]));
      Exit;
    end;

    {Sized to legacy entries only; presets do not pre-extract (they run
     on demand during ProcessFile).}
    EntryCount := LegacyEntryCount(H.Offsets, H.Settings.ShowFrames, H.Settings.ShowCombined);
    TempDir := Session.PrepareFresh(H.FileName, EntryCount);

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
