{Polymorphic archive-entry extractors for the WCX plugin.

 Replaces the prior `case Entry.Kind of ekSeparateFrame / ekCombinedSheet /
 ekUserPreset` dispatch ladder in uWcxExports with a single
 `Entry.Extract(...)` / `Entry.ReportedSize(...)` virtual call. The three
 concrete classes (TFrameEntry / TCombinedEntry / TPresetEntry) each
 carry the per-archive-entry state they need (frame index, combined
 cache slot, preset index) and implement the IWcxEntryExtractor
 contract. BuildArchiveListing in uWcxListing now allocates instances of
 these instead of populating a record + enum + index triple.

 Adding a new archive-entry kind becomes one new class implementing the
 interface — no edits to DoProcessFile or ReadHeader/ReadHeaderExW.

 Two narrow seams live alongside for test isolation:
   - IFrameExtractor (already exported by uFrameExtractor) lets frame /
     combined Extract tests run without launching ffmpeg.
   - IBitmapSaverRouter is the multi-format dispatcher seam: entry
     classes call its single Save(ABitmap, APath, AFormat, AJpegQuality,
     APngCompression) method so the per-archive Settings.SaveFormat can
     vary. Production wiring (TVclBitmapSaverRouter) delegates to
     uBitmapSaver.MakeBitmapSaver internally; test fakes record what
     would have been written without touching disk. Distinct from the
     per-format `IBitmapSaver` polymorphic family in uBitmapSaver — the
     router selects the right per-format saver, the family encapsulates
     the format-specific encoding.

 The preset path (TPresetEntry.Extract) uses concrete dependencies
 (TWcxProgressBridge / ExtractPreset / GPresetFailureReporter) because
 the bulk of its testable behaviour already lives under
 TestWcxPresetExtractor; this unit only pins its structural contract
 (FileName / ReportedSize / constructor wiring).}
unit uWcxEntryExtractors;

interface

uses
  uWcxAPI, uWcxSettings, uBitmapSaver, uFrameExtractor, uFrameOffsets,
  uVideoInfo, uWcxPresets, uTypes,
  {Vcl.Graphics last so its TBitmap shadows the Winapi.Windows.tagBITMAP
   that uWcxAPI transitively imports — otherwise TBitmap is ambiguous.}
  Vcl.Graphics;

type
  IWcxExtractionContext = interface;
  IWcxEntryExtractor = interface;
  IBitmapSaverRouter = interface;

  {Abstracts what one entry extractor reads from the open archive handle.
   TArchiveHandle in uWcxExports implements it directly; tests pass a
   lightweight stub. The interface is intentionally wide because
   per-open-session state (file path, settings, ffmpeg path, frame
   offsets, temp cache slots, presets, progress callbacks) all flows
   through here. ISP would fragment this into many narrow facets per
   concrete extractor, but the cohesion (one archive open = one context)
   is high enough that one interface is the pragmatic shape.}
  IWcxExtractionContext = interface
    ['{8C5B2E1A-4F7D-49A8-B6C3-1E2D5F4A9B7C}']
    function GetFileName: string;
    function GetFFmpegPath: string;
    function GetSourceFileSize: Int64;
    function GetSettings: TWcxSettings;
    function GetOffsets: TFrameOffsetArray;
    function GetPresets: TWcxPresetArray;
    function GetVideoInfo: TVideoInfo;
    function GetTempPaths: TArray<string>;
    function GetEntrySizes: TArray<Int64>;
    function GetProcessDataProc: TProcessDataProc;
    function GetProcessDataProcW: TProcessDataProcW;
    function GetFrameExtractor: IFrameExtractor;
    function GetBitmapSaver: IBitmapSaverRouter;

    property FileName: string read GetFileName;
    property FFmpegPath: string read GetFFmpegPath;
    property SourceFileSize: Int64 read GetSourceFileSize;
    property Settings: TWcxSettings read GetSettings;
    property Offsets: TFrameOffsetArray read GetOffsets;
    property Presets: TWcxPresetArray read GetPresets;
    property VideoInfo: TVideoInfo read GetVideoInfo;
    property TempPaths: TArray<string> read GetTempPaths;
    property EntrySizes: TArray<Int64> read GetEntrySizes;
    property ProcessDataProc: TProcessDataProc read GetProcessDataProc;
    property ProcessDataProcW: TProcessDataProcW read GetProcessDataProcW;
    property FrameExtractor: IFrameExtractor read GetFrameExtractor;
    property BitmapSaver: IBitmapSaverRouter read GetBitmapSaver;
  end;

  {One archive entry. The dispatch in DoProcessFile collapses to
   `Entry.Extract(...)` and the size logic in ReadHeader/ReadHeaderExW
   to `Entry.ReportedSize(AContext, AListingIndex)`. AListingIndex is
   passed because EntrySizes is keyed by the listing position (TC's
   iteration index), not by the per-entry slot; lifting that into the
   call signature keeps the cache layout decoupled from the per-class
   identity.}
  IWcxEntryExtractor = interface
    ['{7A3E9B4C-1D52-4E8F-9A0B-3C2D7E5F1A6B}']
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;

    property FileName: string read GetFileName;
  end;

  TWcxEntryExtractorArray = TArray<IWcxEntryExtractor>;

  {Multi-format bitmap-saving seam so frame/combined Extract tests do
   not write real files. TVclBitmapSaverRouter is the production wiring
   — it delegates to uBitmapSaver.MakeBitmapSaver (the per-format
   polymorphic family), so adding a new format only requires touching
   MakeBitmapSaver; the router stays the same. Test fakes record what
   would have been written.}
  IBitmapSaverRouter = interface
    ['{2F1E8D5A-9C4B-47A6-B8E3-5D1F0A6C2E4B}']
    procedure Save(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions);
  end;

  TVclBitmapSaverRouter = class(TInterfacedObject, IBitmapSaverRouter)
  public
    procedure Save(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions);
  end;

  {One separately-extracted frame. FrameIndex is the position in
   AContext.Offsets (and in AContext.TempPaths when ShowFileSizes is on).
   ReportedSize returns the cached on-disk size when available; the
   ANSI ReadHeader path is responsible for clamping into Int32.}
  TFrameEntry = class(TInterfacedObject, IWcxEntryExtractor)
  strict private
    FFileName: string;
    FFrameIndex: Integer;
  public
    constructor Create(const AFileName: string; AFrameIndex: Integer);
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
    property FrameIndex: Integer read FFrameIndex;
  end;

  {The contact-sheet image. CombinedSlot is the cache slot the
   pre-extraction stage wrote the image to — immediately after the
   frames when ShowFrames is on, slot 0 when frames are off. Carried so
   the dispatch in Extract stays decoupled from the slot-numbering
   scheme.}
  TCombinedEntry = class(TInterfacedObject, IWcxEntryExtractor)
  strict private
    FFileName: string;
    FCombinedSlot: Integer;
  public
    constructor Create(const AFileName: string; ACombinedSlot: Integer);
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
    property CombinedSlot: Integer read FCombinedSlot;
  end;

  {One user-defined ffmpeg preset. PresetIndex points into
   AContext.Presets. Unlike the frame / combined entries, presets do not
   pre-extract — Extract runs the full ffmpeg pipeline on demand and
   reports progress through TWcxProgressBridge. ReportedSize returns the
   source-file size as a placeholder because the output size is not
   predictable in advance; using the source size keeps the listing
   column believable AND gives the progress bridge a meaningful
   denominator.}
  TPresetEntry = class(TInterfacedObject, IWcxEntryExtractor)
  strict private
    FFileName: string;
    FPresetIndex: Integer;
  public
    constructor Create(const AFileName: string; APresetIndex: Integer);
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
    property PresetIndex: Integer read FPresetIndex;
  end;

{Renders the combined contact sheet bitmap by extracting each offset
 through AExtractor and composing the grid. Caller owns the returned
 bitmap (nil on failure). Exported so the pre-extract cache path in
 uWcxExports can share the same composition without duplicating the
 style logic; TCombinedEntry.Extract calls it on cache-miss as well.}
function RenderCombinedBitmap(const AContext: IWcxExtractionContext;
  const AExtractor: IFrameExtractor): TBitmap;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  uFrameFileNames, uBannerInfo, uBannerPainter, uCombinedGrid, uTimecodeOverlay,
  uBitmapResize, uDebugLog,
  uWcxPresetTemplate, uWcxPresetExtractor, uWcxProgressBridge,
  uPresetExtractReporter, uWcxErrorMapping;
{Note: Winapi.Windows is in scope transitively via uWcxAPI (interface
 uses), but Vcl.Graphics is listed AFTER it in this unit's interface
 uses so the unqualified TBitmap resolves to Vcl.Graphics.TBitmap, not
 to Winapi.Windows.tagBITMAP. INFINITE (from Winapi.Windows) is
 available via the same transitive path.}

procedure WcxEntryLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

{Builds extraction options from WCX settings.
 AMaxSide = 0 means no scale limit (combined-mode caller relies on
 this: the assembled grid is shrunk separately after rendering).}
function BuildExtractionOptions(ASettings: TWcxSettings; AMaxSide: Integer = 0): TExtractionOptions;
begin
  Result := ASettings.Extraction.ToExtractionOptions(AMaxSide);
end;

{Tries to satisfy an extract request from the pre-extracted temp file
 pool populated by PreExtractFrames. Returns True when a cached source
 existed and a copy to ADestPath was attempted; AResult then carries
 E_SUCCESS or the mapped error. Returns False when no cached source was
 available, leaving the caller to fall through to the ffmpeg path.}
function TryCopyCachedFrame(const ATempPaths: TArray<string>; AIndex: Integer;
  const ADestPath: string; out AResult: Integer): Boolean;
begin
  if (ATempPaths = nil) or (AIndex < 0) or (AIndex >= Length(ATempPaths))
    or (ATempPaths[AIndex] = '') or (not TFile.Exists(ATempPaths[AIndex])) then
    Exit(False);
  Result := True;
  try
    TFile.Copy(ATempPaths[AIndex], ADestPath, True);
    AResult := E_SUCCESS;
  except
    on E: Exception do
      AResult := ExceptionToWcxError(E);
  end;
end;

function RenderCombinedBitmap(const AContext: IWcxExtractionContext;
  const AExtractor: IFrameExtractor): TBitmap;
var
  Frames: TArray<TBitmap>;
  Resized, WithBanner: TBitmap;
  BannerStyle: TBannerStyle;
  GridStyle: TCombinedGridStyle;
  TimestampStyle: TTimestampStyle;
  Settings: TWcxSettings;
  Offsets: TFrameOffsetArray;
  I: Integer;
begin
  Settings := AContext.Settings;
  Offsets := AContext.Offsets;
  SetLength(Frames, Length(Offsets));
  try
    for I := 0 to Length(Offsets) - 1 do
      Frames[I] := AExtractor.ExtractFrame(AContext.FileName, Offsets[I].TimeOffset, BuildExtractionOptions(Settings));

    GridStyle := TCombinedGridStyle.FromFields(
      Settings.CombinedColumns, Settings.CellGap, Settings.CombinedBorder,
      Settings.Background, Settings.BackgroundAlpha);

    TimestampStyle := TTimestampStyle.FromSettings(Settings.Timestamp);
    {WCX combined sheets historically render the timecode bold; FromSettings
     defaults FontStyles to [] (matches WLX live view), so we override
     here.}
    TimestampStyle.FontStyles := [fsBold];

    Result := RenderCombinedImage(Frames, Offsets, GridStyle, TimestampStyle);

    {Apply combined size limit BEFORE the banner so the banner stays at
     full width and is not counted toward the limit.}
    if Result <> nil then
    begin
      Resized := DownscaleBitmapToFit(Result, Settings.CombinedMaxSide);
      if Resized <> nil then
      begin
        Result.Free;
        Result := Resized;
      end;
    end;

    if (Result <> nil) and Settings.ShowBanner then
    begin
      BannerStyle := TBannerStyle.FromSettings(Settings.Banner);
      WithBanner := AttachBanner(Result, FormatBannerLines(BuildBannerInfo(AContext.FileName, AContext.VideoInfo)), BannerStyle);
      Result.Free;
      Result := WithBanner;
    end;
  finally
    for I := 0 to Length(Frames) - 1 do
      Frames[I].Free;
  end;
end;

{ TVclBitmapSaverRouter }

procedure TVclBitmapSaverRouter.Save(ABitmap: TBitmap; const APath: string;
  const AOptions: TSaveOptions);
begin
  {Delegate to the per-format polymorphic family in uBitmapSaver.
   SaveBitmapToFile itself now routes through MakeBitmapSaver, so this
   could call either — going direct keeps one less indirection.}
  MakeBitmapSaver(AOptions.Format, AOptions.JpegQuality, AOptions.PngCompression).Save(ABitmap, APath);
end;

{ TFrameEntry }

constructor TFrameEntry.Create(const AFileName: string; AFrameIndex: Integer);
begin
  inherited Create;
  FFileName := AFileName;
  FFrameIndex := AFrameIndex;
end;

function TFrameEntry.GetFileName: string;
begin
  Result := FFileName;
end;

function TFrameEntry.ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
var
  Sizes: TArray<Int64>;
begin
  Sizes := AContext.EntrySizes;
  if (Sizes <> nil) and (AListingIndex >= 0) and (AListingIndex < Length(Sizes)) then
    Result := Sizes[AListingIndex]
  else
    Result := 0;
end;

{Extracts a single frame. The frame index is the entry's own
 FFrameIndex — decoupled from H.CurrentIndex because the listing
 interleaves presets after the legacy frames, so the TC iteration
 position no longer matches the offset/temp-path index. ekSeparateFrame
 entries carry their own FrameIndex, which is set at construction by
 BuildArchiveListing.}
function TFrameEntry.Extract(const AContext: IWcxExtractionContext;
  const ADestPath, ADestName: string): Integer;
var
  Bmp: TBitmap;
  FullPath: string;
  Settings: TWcxSettings;
begin
  Settings := AContext.Settings;
  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + GenerateFrameFileName(AContext.FileName, FFrameIndex, AContext.Offsets[FFrameIndex].TimeOffset, Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxEntryLog(Format('Extract frame %d -> %s', [FFrameIndex, FullPath]));

  if TryCopyCachedFrame(AContext.TempPaths, FFrameIndex, FullPath, Result) then
    Exit;

  try
    Bmp := AContext.FrameExtractor.ExtractFrame(AContext.FileName, AContext.Offsets[FFrameIndex].TimeOffset, BuildExtractionOptions(Settings, Settings.FrameMaxSide));
    if Bmp = nil then
      Exit(E_BAD_DATA);
    try
      AContext.BitmapSaver.Save(Bmp, FullPath, Settings.SaveOptions);
    finally
      Bmp.Free;
    end;
  except
    on E: Exception do
      Exit(ExceptionToWcxError(E));
  end;
  Result := E_SUCCESS;
end;

{ TCombinedEntry }

constructor TCombinedEntry.Create(const AFileName: string; ACombinedSlot: Integer);
begin
  inherited Create;
  FFileName := AFileName;
  FCombinedSlot := ACombinedSlot;
end;

function TCombinedEntry.GetFileName: string;
begin
  Result := FFileName;
end;

function TCombinedEntry.ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
var
  Sizes: TArray<Int64>;
begin
  Sizes := AContext.EntrySizes;
  if (Sizes <> nil) and (AListingIndex >= 0) and (AListingIndex < Length(Sizes)) then
    Result := Sizes[AListingIndex]
  else
    Result := 0;
end;

{Extracts the combined contact sheet to ADestName / ADestPath.
 FCombinedSlot is the cache slot the pre-extraction stage wrote the
 image to (set at construction by BuildArchiveListing so the dispatch
 stays decoupled from the slot scheme).}
function TCombinedEntry.Extract(const AContext: IWcxExtractionContext;
  const ADestPath, ADestName: string): Integer;
var
  Combined: TBitmap;
  FullPath: string;
  Settings: TWcxSettings;
begin
  Settings := AContext.Settings;
  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + GenerateCombinedFileName(AContext.FileName, Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxEntryLog(Format('Extract combined (%d frames) -> %s', [Length(AContext.Offsets), FullPath]));

  if TryCopyCachedFrame(AContext.TempPaths, FCombinedSlot, FullPath, Result) then
    Exit;

  try
    Combined := RenderCombinedBitmap(AContext, AContext.FrameExtractor);
    if Combined = nil then
      Exit(E_BAD_DATA);
    try
      AContext.BitmapSaver.Save(Combined, FullPath, Settings.SaveOptions);
    finally
      Combined.Free;
    end;
    Result := E_SUCCESS;
  except
    on E: Exception do
      Result := ExceptionToWcxError(E);
  end;
end;

{ TPresetEntry }

constructor TPresetEntry.Create(const AFileName: string; APresetIndex: Integer);
begin
  inherited Create;
  FFileName := AFileName;
  FPresetIndex := APresetIndex;
end;

function TPresetEntry.GetFileName: string;
begin
  Result := FFileName;
end;

{Synthetic UnpSize for preset entries: the source file size. Output
 size is unknown in advance (the user can compress or transcode to
 anything), and reporting 0 would freeze TC's progress bar at 0%
 forever. Using the source size makes the listing column believable
 and gives the progress bridge a meaningful denominator. Independent
 of the cache (AListingIndex is unused here).}
function TPresetEntry.ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
begin
  Result := AContext.SourceFileSize;
end;

{Runs a user-defined ffmpeg preset, surfacing progress through TC's
 ProcessDataProc callback and respecting user cancel.
 Both cancel and error paths map to E_EWRITE because TC handles E_EWRITE
 on cancel by suppressing its error popup, while a real error still
 surfaces via the WcxLog message and the dialog TC shows for E_EWRITE.
 The reporter dependency is the unit-level GPresetFailureReporter in
 uWcxExports — keeping it static here avoids the test-only wiring this
 path does not need; preset extraction's behaviour is already covered
 by TestWcxPresetExtractor.}
function TPresetEntry.Extract(const AContext: IWcxExtractionContext;
  const ADestPath, ADestName: string): Integer;
const
  {Effectively no wall-clock cap: presets are arbitrary user transcodes
   that may run for hours on long videos. The user's cancel button
   (which signals the bridge cancel handle) is the intended stop
   mechanism; a hung ffmpeg can still be killed via Task Manager.}
  PRESET_EXTRACT_TIMEOUT_MS = INFINITE;
var
  Bridge: TWcxProgressBridge;
  FullPath: string;
  ExtractResult: TPresetExtractResult;
  Preset: TWcxPreset;
  Presets: TWcxPresetArray;
begin
  Presets := AContext.Presets;
  if (FPresetIndex < 0) or (FPresetIndex >= Length(Presets)) then
    Exit(E_BAD_DATA);

  Preset := Presets[FPresetIndex];
  {Apply template expansion to Args so the same %basename% / %name% /
   %ext% tokens that work in OutputName also work in Args (e.g.
   "Args=-metadata title=%basename%"). The local Preset is a value
   copy, so this does not mutate AContext.Presets.}
  Preset.Args := ExpandTemplate(Preset.Args, AContext.FileName, Preset.Name);

  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + FFileName
  else
    Exit(E_ECREATE);

  WcxEntryLog(Format('Extract preset "%s" -> %s', [Preset.Name, FullPath]));

  {Total bytes for the bridge mirrors the synthetic UnpSize we reported
   in ReadHeaderExW so deltas line up with what TC's bar denominator
   expects. Source file size was captured at OpenArchive time.}
  Bridge := TWcxProgressBridge.Create(FullPath, AContext.SourceFileSize,
    AContext.ProcessDataProc, AContext.ProcessDataProcW);
  try
    {Up-front ping registers this file with TC's progress UI and gives
     the user a cancel point before ffmpeg even starts spinning.}
    if not Bridge.Ping then
      Exit(E_EWRITE);

    ExtractResult := ExtractPreset(AContext.FFmpegPath, AContext.FileName, FullPath, Preset, AContext.VideoInfo.Duration,
      function(APercent: Integer): Boolean
      begin
        Result := Bridge.ReportPercent(APercent);
      end,
      Bridge.CancelHandle, PRESET_EXTRACT_TIMEOUT_MS);

    if ExtractResult.Success then
      Exit(E_SUCCESS);

    WcxEntryLog(Format('Preset "%s" failed (cancelled=%s exitCode=%d): %s',
      [Preset.Name, BoolToStr(ExtractResult.Cancelled, True), ExtractResult.ExitCode, ExtractResult.ErrorMessage]));

    if ExtractResult.Cancelled then
    begin
      {Cancel: TC suppresses its own dialog when it sees E_EWRITE on a
       user-initiated cancel, so stay silent on our side too — the user
       knows they cancelled.}
      Result := E_EWRITE;
      Exit;
    end;

    {Surface the real ffmpeg error. TC's follow-up dialog ("Bad data" /
     "Write error") is generic and unhelpful for problems like "no
     audio stream" or "unknown encoder"; this message gives the user
     the actual reason they need to fix the preset or pick a different
     source.}
    GetPresetFailureReporter.Report(MakeFailureMessage(Preset.Name, FullPath, ExtractResult));

    {Distinguish the two failure modes in the WCX return code:
     - ExitCode<>0 means ffmpeg refused (bad codec, no stream, bad
       args) which is closer to E_BAD_DATA than to a write error.
     - ExitCode=0 with Success=False means the rename step failed,
       which IS a real write error.}
    if ExtractResult.ExitCode <> 0 then
      Result := E_BAD_DATA
    else
      Result := E_EWRITE;
  finally
    Bridge.Free;
  end;
end;

end.
