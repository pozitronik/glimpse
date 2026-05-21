{Polymorphic archive-entry extractors for the WCX plugin. Each kind
 (frame, combined sheet, user preset) is one class implementing
 IWcxEntryExtractor; DoProcessFile dispatches via Entry.Extract.
 Adding a new entry kind = one new class implementing the interface.}
unit WcxEntryExtractors;

interface

uses
  WcxAPI, WcxSettings, BitmapSaver, FrameExtractor, FrameOffsets,
  VideoInfo, WcxPresets, Types, PresetExtractReporter,
  {Vcl.Graphics last so its TBitmap shadows Winapi.Windows.tagBITMAP
   pulled in transitively by WcxAPI; otherwise TBitmap is ambiguous.}
  Vcl.Graphics;

type
  IWcxExtractionContext = interface;
  IWcxEntryExtractor = interface;
  IBitmapSaverRouter = interface;

  {Wide on purpose: one archive open = one context, so the cohesion is
   high enough that splitting into per-extractor facets would add
   ceremony without buying isolation. Tests pass a lightweight stub.}
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
    function GetFailureReporter: IPresetExtractFailureReporter;

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
    property FailureReporter: IPresetExtractFailureReporter read GetFailureReporter;
  end;

  {AListingIndex is passed (rather than read from the extractor) because
   EntrySizes is keyed by TC's iteration index, not by the per-entry
   slot — that keeps the cache layout decoupled from per-class identity.}
  IWcxEntryExtractor = interface
    ['{7A3E9B4C-1D52-4E8F-9A0B-3C2D7E5F1A6B}']
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;

    property FileName: string read GetFileName;
  end;

  TWcxEntryExtractorArray = TArray<IWcxEntryExtractor>;

  {Test seam so frame/combined Extract paths do not write real files.
   Production wiring delegates to BitmapSaver.MakeBitmapSaver.}
  IBitmapSaverRouter = interface
    ['{2F1E8D5A-9C4B-47A6-B8E3-5D1F0A6C2E4B}']
    procedure Save(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions);
  end;

  TVclBitmapSaverRouter = class(TInterfacedObject, IBitmapSaverRouter)
  public
    procedure Save(ABitmap: TBitmap; const APath: string; const AOptions: TSaveOptions);
  end;

  {FrameIndex is the position in AContext.Offsets and in
   AContext.TempPaths when ShowFileSizes is on. ANSI ReadHeader clamps
   ReportedSize into Int32 at the call site.}
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

  {CombinedSlot is the cache slot the pre-extraction stage wrote the
   image to; carried so Extract is decoupled from the slot-numbering
   scheme (after the frames when ShowFrames is on, slot 0 otherwise).}
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

  {Runs the full ffmpeg pipeline on demand (no pre-extract). Progress is
   reported through TWcxProgressBridge. ReportedSize uses the source
   file size as a placeholder so TC's progress bar has a meaningful
   denominator — output size is not predictable in advance.}
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

{Caller owns the returned bitmap (nil on failure). Exported so the
 pre-extract cache path can share composition; TCombinedEntry.Extract
 calls it on cache-miss too.}
function RenderCombinedBitmap(const AContext: IWcxExtractionContext;
  const AExtractor: IFrameExtractor): TBitmap;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  FrameFileNames, BannerInfo, BannerPainter, CombinedGrid, TimecodeOverlay,
  BitmapResize, Logging,
  WcxPresetTemplate, WcxPresetExtractor, WcxProgressBridge,
  WcxErrorMapping;

procedure WcxEntryLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

{AMaxSide = 0 means no scale limit; combined-mode relies on this since
 the assembled grid is shrunk separately after rendering.}
function BuildExtractionOptions(ASettings: TWcxSettings; AMaxSide: Integer = 0): TExtractionOptions;
begin
  Result := ASettings.Extraction.ToExtractionOptions(AMaxSide);
end;

{Returns True when a cached source existed and a copy was attempted
 (AResult holds E_SUCCESS or the mapped error). Returns False to let
 the caller fall through to the ffmpeg path.}
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
    {WCX combined sheets render the timecode bold; FromSettings defaults
     to [] to match the WLX live view, so override here.}
    TimestampStyle.FontStyles := [fsBold];

    Result := RenderCombinedImage(Frames, Offsets, GridStyle, TimestampStyle);
    try
      {Resize BEFORE the banner so the banner stays at full width and is
       not counted toward the limit.}
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
        var BannerBytes: Int64 := 0;
        if TFile.Exists(AContext.FileName) then
          BannerBytes := TFile.GetSize(AContext.FileName);
        WithBanner := AttachBanner(Result, FormatBannerLines(BuildBannerInfo(AContext.FileName, BannerBytes, AContext.VideoInfo)), BannerStyle);
        Result.Free;
        Result := WithBanner;
      end;
    except
      Result.Free;
      raise;
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

{Uses FFrameIndex (not the iteration position) because the listing
 interleaves presets after the frames, so TC's index does not match
 the offset/temp-path index.}
function TFrameEntry.Extract(const AContext: IWcxExtractionContext;
  const ADestPath, ADestName: string): Integer;
var
  Bmp: TBitmap;
  FullPath: string;
  Settings: TWcxSettings;
begin
  Settings := AContext.Settings;
  if (FFrameIndex < 0) or (FFrameIndex >= Length(AContext.Offsets)) then
    Exit(E_BAD_DATA);
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

{Reporting 0 would freeze TC's progress bar at 0% forever; the source
 file size is the best available denominator since output size is
 unknown until ffmpeg finishes.}
function TPresetEntry.ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
begin
  Result := AContext.SourceFileSize;
end;

{Cancel maps to E_EWRITE because TC suppresses its own dialog on
 E_EWRITE-from-cancel, leaving us silent. Real errors also map to
 E_EWRITE so TC shows its generic write-error dialog after we have
 already surfaced the specific cause via the failure reporter.}
function TPresetEntry.Extract(const AContext: IWcxExtractionContext;
  const ADestPath, ADestName: string): Integer;
const
  {Presets are arbitrary user transcodes that may run for hours; the
   user's cancel button is the intended stop mechanism. A hung ffmpeg
   can still be killed via Task Manager.}
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
  {%basename% / %name% / %ext% tokens are expanded in Args too, not just
   OutputName (e.g. "Args=-metadata title=%basename%"). Preset is a
   value copy so AContext.Presets is not mutated.}
  Preset.Args := ExpandTemplate(Preset.Args, AContext.FileName, Preset.Name);

  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + FFileName
  else
    Exit(E_ECREATE);

  WcxEntryLog(Format('Extract preset "%s" -> %s', [Preset.Name, FullPath]));

  {Bridge total mirrors the synthetic UnpSize from ReadHeaderExW so
   deltas line up with TC's bar denominator.}
  Bridge := TWcxProgressBridge.Create(FullPath, AContext.SourceFileSize,
    AContext.ProcessDataProc, AContext.ProcessDataProcW);
  try
    {Up-front ping registers the file with TC's progress UI and gives
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
      {Stay silent on cancel — the user knows they cancelled and TC
       suppresses its dialog when it sees E_EWRITE-from-cancel.}
      Result := E_EWRITE;
      Exit;
    end;

    {TC's own follow-up dialog is generic ("Bad data" / "Write error");
     surface the actual ffmpeg cause so the user can fix the preset.}
    AContext.FailureReporter.Report(MakeFailureMessage(Preset.Name, FullPath, ExtractResult));

    {ExitCode<>0 means ffmpeg refused (bad codec, no stream) — closer to
     bad data. ExitCode=0 with Success=False means the rename step
     failed, which IS a real write error.}
    if ExtractResult.ExitCode <> 0 then
      Result := E_BAD_DATA
    else
      Result := E_EWRITE;
  finally
    Bridge.Free;
  end;
end;

end.
