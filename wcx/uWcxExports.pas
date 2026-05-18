{WCX plugin exported functions.
 Presents a video file as a virtual archive containing frame images.}
unit uWcxExports;

interface

uses
  System.SysUtils, Winapi.Windows, uWcxAPI;

{Opens archive (video file) for listing or extraction}
function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;

{Reads next file header from archive}
function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;

{Processes (extracts/skips) the current file}
function ProcessFile(hArcData: THandle; Operation: Integer; DestPath, DestName: PAnsiChar): Integer; stdcall;
function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;

{Closes archive handle}
function CloseArchive(hArcData: THandle): Integer; stdcall;

{Callback setters}
procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;

{Reports plugin capabilities}
function GetPackerCaps: Integer; stdcall;

{Receives default INI path from TC}
procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;

{Stub: packing not supported, exists only to make Configure button accessible}
function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar; Flags: Integer): Integer; stdcall;

{Shows configuration dialog}
procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;

{Clamps a 64-bit file size into the 32-bit signed range used by the WCX
 ANSI ReadHeader (THeaderData.UnpSize is Integer). Negative input is
 promoted to zero (defensive; sizes from disk are non-negative); values
 above MaxInt saturate at MaxInt so a 5 GB combined image surfaces as
 ~2 GB instead of wrapping into a negative or truncated value. The Wide
 variant (ReadHeaderExW) carries the full 64-bit value via UnpSize +
 UnpSizeHigh and is unaffected.}
function ClampSizeForAnsiHeader(AValue: Int64): Integer;

{Maps a Delphi exception class to the closest WCX error code. Earlier the
 extract / copy except blocks mapped every exception to E_EWRITE, which
 told the user "disk write failed" even when the real problem was RAM
 exhaustion or a missing source file. The mapping is intentionally
 narrow: only the high-signal classes branch off; everything else still
 falls through to E_EWRITE so legacy behaviour is preserved for the
 uncategorised majority.
 Takes a class reference rather than an instance so tests can pin every
 branch without allocating instances of leak-tricky classes (EOutOfMemory
 overrides FreeInstance to a no-op for the singleton path).}
function ExceptionClassToWcxError(AClass: TClass): Integer;
function ExceptionToWcxError(E: Exception): Integer;

implementation

uses
  System.AnsiStrings, System.Classes, System.IOUtils,
  Vcl.Graphics,
  uWcxSettings, uWcxSettingsDlg, uFFmpegLocator, uFFmpegExe, uFrameOffsets,
  uFrameFileNames, uBitmapSaver, uFrameExtractor,
  uCombinedImage, uDebugLog, uPathExpand, uProbeCache, uTypes, uBitmapResize,
  uWcxPresets, uWcxListing, uWcxProgressBridge, uWcxPresetExtractor,
  uWcxFrameCache;

type
  {State for one open archive (video file)}
  TArchiveHandle = class
    FileName: string;
    Settings: TWcxSettings;
    FFmpegPath: string;
    VideoInfo: TVideoInfo;
    Offsets: TFrameOffsetArray;
    CurrentIndex: Integer;
    OpenMode: Integer;
    FileTime: Integer;
    {Populated from module-level cache when ShowFileSizes is enabled}
    TempPaths: TArray<string>;
    EntrySizes: TArray<Int64>;
    {Loaded once at OpenArchive when ShowPresets is on; empty otherwise.
     Indexed by Listing[I].PresetIndex.}
    Presets: TWcxPresetArray;
    {Pre-built typed listing: legacy entries first (frames or combined),
     preset entries appended after. ReadHeaderExW iterates this; ProcessFile
     dispatches on Listing[CurrentIndex].Kind.}
    Listing: TWcxListingEntryArray;
    {TC's progress callbacks. The Wide variant is preferred when set;
     legacy TC builds fall back to the ANSI variant. Either or both may
     be nil — ProcessFile then runs without surfacing progress.}
    ProcessDataProc: TProcessDataProc;
    ProcessDataProcW: TProcessDataProcW;
    {Source video size in bytes. Reported as the synthetic UnpSize for
     preset entries (output size is not predictable in advance, but
     using the source size keeps the listing column believable AND gives
     the progress bridge a meaningful denominator).}
    SourceFileSize: Int64;
  end;

var
  GIniPath: string;

procedure WcxLog(const AMsg: string);
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
  Result := Default (TExtractionOptions);
  Result.UseBmpPipe := ASettings.UseBmpPipe;
  Result.HwAccel := ASettings.HwAccel;
  Result.UseKeyframes := ASettings.UseKeyframes;
  Result.RespectAnamorphic := ASettings.RespectAnamorphic;
  Result.MaxSide := AMaxSide;
end;

function ClampSizeForAnsiHeader(AValue: Int64): Integer;
begin
  if AValue < 0 then
    Result := 0
  else if AValue > MaxInt then
    Result := MaxInt
  else
    Result := Integer(AValue);
end;

function ExceptionClassToWcxError(AClass: TClass): Integer;
begin
  if (AClass <> nil) and AClass.InheritsFrom(EOutOfMemory) then
    Result := E_NO_MEMORY
  else if (AClass <> nil) and AClass.InheritsFrom(EFileNotFoundException) then
    Result := E_EOPEN
  else
    Result := E_EWRITE;
end;

function ExceptionToWcxError(E: Exception): Integer;
begin
  if E = nil then
    Result := E_EWRITE
  else
    Result := ExceptionClassToWcxError(E.ClassType);
end;

function GetEntryCount(H: TArchiveHandle): Integer;
begin
  Result := Length(H.Listing);
end;

function GetEntryName(H: TArchiveHandle): string;
begin
  Result := H.Listing[H.CurrentIndex].FileName;
end;

{Extracts all frames, renders a combined grid with optional banner.
 Caller owns the returned bitmap (nil on failure).}
function RenderCombinedBitmap(H: TArchiveHandle; const AExtractor: IFrameExtractor): TBitmap;
var
  Frames: TArray<TBitmap>;
  Resized, WithBanner: TBitmap;
  BannerStyle: TBannerStyle;
  GridStyle: TCombinedGridStyle;
  TimestampStyle: TTimestampStyle;
  I: Integer;
begin
  SetLength(Frames, Length(H.Offsets));
  try
    for I := 0 to Length(H.Offsets) - 1 do
      Frames[I] := AExtractor.ExtractFrame(H.FileName, H.Offsets[I].TimeOffset, BuildExtractionOptions(H.Settings));

    GridStyle.Columns := H.Settings.CombinedColumns;
    GridStyle.CellGap := H.Settings.CellGap;
    GridStyle.Border := H.Settings.CombinedBorder;
    GridStyle.Background := H.Settings.Background;
    GridStyle.BackgroundAlpha := H.Settings.BackgroundAlpha;

    TimestampStyle.Show := H.Settings.ShowTimestamp;
    TimestampStyle.Corner := H.Settings.TimestampCorner;
    TimestampStyle.FontName := H.Settings.TimestampFontName;
    TimestampStyle.FontSize := H.Settings.TimestampFontSize;
    TimestampStyle.FontStyles := [fsBold];
    TimestampStyle.BackColor := H.Settings.TimecodeBackColor;
    TimestampStyle.BackAlpha := H.Settings.TimecodeBackAlpha;
    TimestampStyle.TextColor := H.Settings.TimestampTextColor;
    TimestampStyle.TextAlpha := H.Settings.TimestampTextAlpha;

    Result := RenderCombinedImage(Frames, H.Offsets, GridStyle, TimestampStyle);

    {Apply combined size limit BEFORE the banner so the banner stays
     at full width and is not counted toward the limit}
    if Result <> nil then
    begin
      Resized := DownscaleBitmapToFit(Result, H.Settings.CombinedMaxSide);
      if Resized <> nil then
      begin
        Result.Free;
        Result := Resized;
      end;
    end;

    if (Result <> nil) and H.Settings.ShowBanner then
    begin
      BannerStyle.Background := H.Settings.BannerBackground;
      BannerStyle.TextColor := H.Settings.BannerTextColor;
      BannerStyle.FontName := H.Settings.BannerFontName;
      BannerStyle.FontSize := H.Settings.BannerFontSize;
      BannerStyle.AutoSize := H.Settings.BannerFontAutoSize;
      BannerStyle.Position := H.Settings.BannerPosition;
      WithBanner := AttachBanner(Result, FormatBannerLines(BuildBannerInfo(H.FileName, H.VideoInfo)), BannerStyle);
      Result.Free;
      Result := WithBanner;
    end;
  finally
    for I := 0 to Length(Frames) - 1 do
      Frames[I].Free;
  end;
end;

{Extracts all frames, renders a combined image, and saves to cache.
 The combined slot is the one immediately after the frames — when frames
 are also being shown the combined image lands at index Length(Offsets);
 when frames are off it lands at index 0.}
procedure ExtractCombinedToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor;
  const ASession: TWcxCacheExtractionSession);
var
  Combined: TBitmap;
  TempPath: string;
  Slot: Integer;
begin
  Combined := RenderCombinedBitmap(H, AExtractor);
  if Combined = nil then
    Exit;
  try
    TempPath := TPath.Combine(ASession.CachedTempDir, GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat));
    SaveBitmapToFile(Combined, TempPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
    if H.Settings.ShowFrames then
      Slot := Length(H.Offsets)
    else
      Slot := 0;
    ASession.RecordSlot(Slot, TempPath, TFile.GetSize(TempPath));
  finally
    Combined.Free;
  end;
end;

{Extracts individual frames and saves each to cache}
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
      SaveBitmapToFile(Bmp, TempPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
      ASession.RecordSlot(I, TempPath, TFile.GetSize(TempPath));
    finally
      Bmp.Free;
    end;
  end;
end;

{Pre-extracts all frames to the module's TWcxFrameCache, or reuses an
 existing cache entry if the same video was already extracted.
 The session held by BeginExtractionSession owns the cache lock for its
 lifetime — a concurrent OpenArchive on a second thread blocks here
 until this pass finishes, which is intentional: two threads on the
 same video must not both proceed past the cache-hit check.
 Security caveat: the temp directory inherits the parent (user temp)
 ACL, so other processes running as the same user can read the
 extracted frames. Same exposure as ffmpeg's own temp output and as the
 WLX frame cache. Tightening would require an explicit per-directory
 ACL via SetSecurityInfo. Acceptable for a single-user TC session;
 revisit if multi-user or sandboxed contexts ever become a use case.}
procedure PreExtractFrames(H: TArchiveHandle);
var
  Session: TWcxCacheExtractionSession;
  Extractor: IFrameExtractor;
  EntryCount: Integer;
  TempDir: string;
begin
  Session := TWcxFrameCache.Instance.BeginExtractionSession;
  try
    if Session.TryHit(H.FileName, H.TempPaths, H.EntrySizes) then
    begin
      WcxLog(Format('PreExtract: cache hit for %s', [H.FileName]));
      Exit;
    end;

    {Cache arrays size to legacy entries only; preset entries do not
     pre-extract (they run on demand during ProcessFile).}
    EntryCount := LegacyEntryCount(H.Offsets, H.Settings.ShowFrames, H.Settings.ShowCombined);
    TempDir := Session.PrepareFresh(H.FileName, EntryCount);

    Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
    {Each enabled mode populates its own cache slots. Both can run in
     the same pass when the user has both Show* bits on.}
    if H.Settings.ShowFrames then
      ExtractSeparateToCache(H, Extractor, Session);
    if H.Settings.ShowCombined then
      ExtractCombinedToCache(H, Extractor, Session);

    Session.PublishTo(H.TempPaths, H.EntrySizes);
    WcxLog(Format('PreExtract: %d entries to %s', [EntryCount, TempDir]));
  finally
    Session.Free;
  end;
end;

function DoOpenArchive(const AFileName: string; AOpenMode: Integer; out AOpenResult: Integer): THandle;
var
  H: TArchiveHandle;
  ProbeC: TProbeCache;
begin
  Result := 0;
  AOpenResult := E_SUCCESS;

  H := TArchiveHandle.Create;
  try
    H.FileName := AFileName;
    H.OpenMode := AOpenMode;
    H.CurrentIndex := 0;

    H.Settings := TWcxSettings.Create(GIniPath);
    H.Settings.Load;
    {Apply the hidden debug-log toggle. Kept here (rather than at DLL init)
     so a hand-edit of "[debug] LogEnabled" in Glimpse.ini takes effect on
     the next archive open without forcing a TC restart.}
    if H.Settings.DebugLogEnabled then
      GDebugLogPath := ChangeFileExt(GetModuleName(HInstance), '.log')
    else
      GDebugLogPath := '';

    H.FFmpegPath := FindFFmpegExe(ExtractFilePath(GIniPath), ExpandEnvVars(H.Settings.FFmpegExePath));

    if H.FFmpegPath = '' then
    begin
      AOpenResult := E_EOPEN;
      H.Free;
      Exit;
    end;

    ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
    try
      H.VideoInfo := ProbeC.TryGetOrProbe(AFileName, H.FFmpegPath);
    finally
      ProbeC.Free;
    end;

    if not H.VideoInfo.IsValid then
    begin
      AOpenResult := E_BAD_ARCHIVE;
      H.Free;
      Exit;
    end;

    H.Offsets := BuildFrameOffsets(H.VideoInfo.Duration, H.Settings.FramesCount, H.Settings.SkipEdgesPercent, H.Settings.RandomPercent, H.Settings.RandomExtraction);
    H.FileTime := DateTimeToFileDate(TFile.GetLastWriteTime(AFileName));
    {Captured once so subsequent ReadHeader / DoExtractPreset reads stay
     consistent even if the source file changes mid-session.}
    try
      H.SourceFileSize := TFile.GetSize(AFileName);
    except
      H.SourceFileSize := 0;
    end;

    {Load presets only when their bit is set in the Mode mask so legacy
     installs skip the IO entirely. The listing builder still runs
     unconditionally because it produces the same legacy-only output
     when the preset array is empty.}
    if H.Settings.ShowPresets then
    begin
      H.Presets := LoadPresets(PresetsIniPath(GIniPath));
      WcxLog(Format('Presets: ShowPresets=ON, path="%s", loaded=%d', [PresetsIniPath(GIniPath), Length(H.Presets)]));
    end
    else
      WcxLog(Format('Presets: ShowPresets=OFF (read from "%s")', [GIniPath]));
    H.Listing := BuildArchiveListing(H.FileName, H.Offsets, H.Settings.ShowFrames, H.Settings.ShowCombined, H.Settings.ShowPresets, H.Settings.SaveFormat, H.Presets);

    if H.Settings.ShowFileSizes then
      PreExtractFrames(H);

    WcxLog(Format('OpenArchive: %s mode=%d frames=%d presets=%d', [AFileName, H.Settings.Mode, Length(H.Offsets), Length(H.Presets)]));
    Result := THandle(H);
  except
    H.Free;
    {PreExtractFrames may have populated GCachedVideoFile / GCachedTempDir
     and started writing temp files before the exception. Without this
     reset, a subsequent OpenArchive on the same video file would treat the
     partial directory as a cache hit and serve garbage entries (or trip
     over missing temp files mid-extraction).}
    TWcxFrameCache.Instance.Invalidate;
    AOpenResult := E_BAD_ARCHIVE;
  end;
end;

function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
begin
  {Encoding caveat: every ANSI export in this unit converts the incoming
   PAnsiChar via the system code page (string(AnsiString(...))). Paths
   containing characters not representable in the local CP_ACP are
   corrupted at this boundary. The Wide siblings (OpenArchiveW,
   ProcessFileW, ReadHeaderExW) are the supported path; modern TC
   always calls them. The ANSI shims exist for ABI completeness and
   fall back gracefully on plain ASCII paths.}
  Result := DoOpenArchive(string(AnsiString(ArchiveData.ArcName)), ArchiveData.OpenMode, ArchiveData.OpenResult);
end;

function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;
begin
  Result := DoOpenArchive(ArchiveData.ArcName, ArchiveData.OpenMode, ArchiveData.OpenResult);
end;

function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: AnsiString;
begin
  H := TArchiveHandle(hArcData);
  if H.CurrentIndex >= GetEntryCount(H) then
    Exit(E_END_ARCHIVE);

  Name := AnsiString(GetEntryName(H));

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  System.AnsiStrings.StrLCopy(HeaderData.FileName, PAnsiChar(Name), SizeOf(HeaderData.FileName) - 1);
  if H.Listing[H.CurrentIndex].Kind = ekUserPreset then
    {Source file size as a placeholder — believable in the listing column
     and gives the bridge a non-zero denominator so the progress bar
     animates. Output size is unknown in advance.}
    HeaderData.UnpSize := ClampSizeForAnsiHeader(H.SourceFileSize)
  else if (H.EntrySizes <> nil) and (H.CurrentIndex < Length(H.EntrySizes)) then
    {THeaderData.UnpSize is 32-bit signed; clamp so >2 GB combined
     images surface as MaxInt instead of wrapping into a negative size.}
    HeaderData.UnpSize := ClampSizeForAnsiHeader(H.EntrySizes[H.CurrentIndex]);
  HeaderData.FileTime := H.FileTime;
  HeaderData.FileAttr := FILE_ATTRIBUTE_ARCHIVE;

  Result := E_SUCCESS;
end;

function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: string;
  Size: Int64;
begin
  H := TArchiveHandle(hArcData);
  if H.CurrentIndex >= GetEntryCount(H) then
    Exit(E_END_ARCHIVE);

  Name := GetEntryName(H);

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  StrLCopy(HeaderData.FileName, PChar(Name), Length(HeaderData.FileName) - 1);
  if H.Listing[H.CurrentIndex].Kind = ekUserPreset then
  begin
    Size := H.SourceFileSize;
    HeaderData.UnpSize := DWORD(Size);
    HeaderData.UnpSizeHigh := DWORD(Size shr 32);
  end
  else if (H.EntrySizes <> nil) and (H.CurrentIndex < Length(H.EntrySizes)) then
  begin
    Size := H.EntrySizes[H.CurrentIndex];
    HeaderData.UnpSize := DWORD(Size);
    HeaderData.UnpSizeHigh := DWORD(Size shr 32);
  end;
  HeaderData.FileTime := H.FileTime;
  HeaderData.FileAttr := FILE_ATTRIBUTE_ARCHIVE;

  Result := E_SUCCESS;
end;

{Tries to satisfy an extract request from the pre-extracted temp file pool
 populated by PreExtractFrames. Returns True when a cached source existed
 and a copy to ADestPath was attempted; AResult then carries E_SUCCESS or
 E_EWRITE. Returns False when no cached source was available, leaving the
 caller to fall through to the ffmpeg extraction path.}
function TryCopyCachedFrame(const ATempPaths: TArray<string>; AIndex: Integer; const ADestPath: string; out AResult: Integer): Boolean;
begin
  if (ATempPaths = nil) or (AIndex < 0) or (AIndex >= Length(ATempPaths)) or (ATempPaths[AIndex] = '') or (not TFile.Exists(ATempPaths[AIndex])) then
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

{Extracts a single frame at the legacy frame index AFrameIndex.
 Index is decoupled from H.CurrentIndex because the listing now interleaves
 presets after the legacy frames, so the TC iteration position no longer
 matches the offset/temp-path index. ekSeparateFrame entries carry their own
 LegacyIndex, which the dispatch in DoProcessFile passes in here.}
function DoExtractSeparate(H: TArchiveHandle; AFrameIndex: Integer; const ADestPath, ADestName: string): Integer;
var
  Extractor: IFrameExtractor;
  Bmp: TBitmap;
  FullPath: string;
begin
  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + GenerateFrameFileName(H.FileName, AFrameIndex, H.Offsets[AFrameIndex].TimeOffset, H.Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxLog(Format('Extract frame %d -> %s', [AFrameIndex, FullPath]));

  if TryCopyCachedFrame(H.TempPaths, AFrameIndex, FullPath, Result) then
    Exit;

  Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
  try
    Bmp := Extractor.ExtractFrame(H.FileName, H.Offsets[AFrameIndex].TimeOffset, BuildExtractionOptions(H.Settings, H.Settings.FrameMaxSide));
    if Bmp = nil then
      Exit(E_BAD_DATA);
    try
      SaveBitmapToFile(Bmp, FullPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
    finally
      Bmp.Free;
    end;
  except
    on E: Exception do
      Exit(ExceptionToWcxError(E));
  end;
  Result := E_SUCCESS;
end;

{Extracts the combined contact sheet to ADestName / ADestPath.
 ACombinedSlot is the cache slot the pre-extraction stage wrote the
 image to (carried via the listing entry's LegacyIndex so the dispatch
 stays decoupled from the slot scheme).}
function DoExtractCombined(H: TArchiveHandle; ACombinedSlot: Integer; const ADestPath, ADestName: string): Integer;
var
  Extractor: IFrameExtractor;
  Combined: TBitmap;
  FullPath: string;
begin
  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxLog(Format('Extract combined (%d frames) -> %s', [Length(H.Offsets), FullPath]));

  if TryCopyCachedFrame(H.TempPaths, ACombinedSlot, FullPath, Result) then
    Exit;

  Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
  try
    Combined := RenderCombinedBitmap(H, Extractor);
    if Combined = nil then
      Exit(E_BAD_DATA);
    try
      SaveBitmapToFile(Combined, FullPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
    finally
      Combined.Free;
    end;
    Result := E_SUCCESS;
  except
    on E: Exception do
      Result := ExceptionToWcxError(E);
  end;
end;

{Runs a user-defined ffmpeg preset, surfacing progress through TC's
 ProcessDataProc callback and respecting user cancel.
 ADisplayName is the dedupe-resolved listed filename used as the fallback
 when TC supplies only ADestPath; ADestName, when set, is the absolute
 destination TC has already chosen and wins over the fallback.
 Both cancel and error paths map to E_EWRITE because TC handles E_EWRITE
 on cancel by suppressing its error popup, while a real error still
 surfaces via the WcxLog message and the dialog TC shows for E_EWRITE.}
{Trims the ffmpeg stderr down to the most signal-rich one-liner for a
 dialog box. ffmpeg often emits a multi-line preamble before the actual
 error; prefer the LAST non-empty line because the immediate cause is
 typically last (e.g. "Output file does not contain any stream"). When
 ffmpeg said nothing useful, fall back to the exit code so the user
 still has a handle for searching docs.}
function SummarizeFFmpegError(const AErrorMessage: string; AExitCode: Integer): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := AErrorMessage;
    for I := Lines.Count - 1 downto 0 do
      if Trim(Lines[I]) <> '' then
      begin
        Result := Trim(Lines[I]);
        Break;
      end;
  finally
    Lines.Free;
  end;
  if Result = '' then
    Result := Format('ffmpeg exited with code %d (no stderr captured)', [AExitCode]);
end;

procedure ShowPresetExtractError(const APresetName, AOutputPath: string; const AResult: TPresetExtractResult);
var
  Msg: string;
begin
  Msg := Format('Preset "%s" could not produce "%s":'#13#10#13#10'%s',
    [APresetName, ExtractFileName(AOutputPath), SummarizeFFmpegError(AResult.ErrorMessage, AResult.ExitCode)]);
  {Foreground window as parent so the dialog appears in front of TC and
   inherits the right modality; passing 0 risks the dialog landing behind
   the file panel on multi-monitor setups.}
  MessageBox(GetForegroundWindow, PChar(Msg), 'Glimpse preset extraction failed', MB_OK or MB_ICONWARNING);
end;

function DoExtractPreset(H: TArchiveHandle; APresetIndex: Integer; const ADisplayName, ADestPath, ADestName: string): Integer;
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
begin
  if (APresetIndex < 0) or (APresetIndex >= Length(H.Presets)) then
    Exit(E_BAD_DATA);

  Preset := H.Presets[APresetIndex];
  {Apply template expansion to Args so the same %basename% / %name% /
   %ext% tokens that work in OutputName also work in Args (e.g.
   "Args=-metadata title=%basename%"). The local Preset is a value copy,
   so this does not mutate H.Presets.}
  Preset.Args := ExpandTemplate(Preset.Args, H.FileName, Preset.Name);

  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + ADisplayName
  else
    Exit(E_ECREATE);

  WcxLog(Format('Extract preset "%s" -> %s', [Preset.Name, FullPath]));

  {Total bytes for the bridge mirrors the synthetic UnpSize we reported
   in ReadHeaderExW so deltas line up with what TC's bar denominator
   expects. Source file size was captured at OpenArchive time.}
  Bridge := TWcxProgressBridge.Create(FullPath, H.SourceFileSize, H.ProcessDataProc, H.ProcessDataProcW);
  try
    {Up-front ping registers this file with TC's progress UI and gives the
     user a cancel point before ffmpeg even starts spinning.}
    if not Bridge.Ping then
      Exit(E_EWRITE);

    ExtractResult := ExtractPreset(H.FFmpegPath, H.FileName, FullPath, Preset, H.VideoInfo.Duration,
      function(APercent: Integer): Boolean
      begin
        Result := Bridge.ReportPercent(APercent);
      end,
      Bridge.CancelHandle, PRESET_EXTRACT_TIMEOUT_MS);

    if ExtractResult.Success then
      Exit(E_SUCCESS);

    WcxLog(Format('Preset "%s" failed (cancelled=%s exitCode=%d): %s',
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
     "Write error") is generic and unhelpful for problems like "no audio
     stream" or "unknown encoder"; this dialog gives the user the actual
     reason they need to fix the preset or pick a different source.}
    ShowPresetExtractError(Preset.Name, FullPath, ExtractResult);

    {Distinguish the two failure modes in the WCX return code:
     - ExitCode<>0 means ffmpeg refused (bad codec, no stream, bad args)
       which is closer to E_BAD_DATA than to a write error.
     - ExitCode=0 with Success=False means the rename step failed, which
       IS a real write error.}
    if ExtractResult.ExitCode <> 0 then
      Result := E_BAD_DATA
    else
      Result := E_EWRITE;
  finally
    Bridge.Free;
  end;
end;

function DoProcessFile(hArcData: THandle; Operation: Integer; const ADestPath, ADestName: string): Integer;
var
  H: TArchiveHandle;
  Entry: TWcxListingEntry;
begin
  H := TArchiveHandle(hArcData);

  if Operation = PK_SKIP then
  begin
    Inc(H.CurrentIndex);
    Exit(E_SUCCESS);
  end;

  if (Operation <> PK_EXTRACT) and (Operation <> PK_TEST) then
  begin
    Inc(H.CurrentIndex);
    Exit(E_SUCCESS);
  end;

  if H.CurrentIndex >= GetEntryCount(H) then
    Exit(E_END_ARCHIVE);

  if Operation = PK_EXTRACT then
  begin
    Entry := H.Listing[H.CurrentIndex];
    case Entry.Kind of
      ekSeparateFrame:
        Result := DoExtractSeparate(H, Entry.LegacyIndex, ADestPath, ADestName);
      ekCombinedSheet:
        Result := DoExtractCombined(H, Entry.LegacyIndex, ADestPath, ADestName);
      ekUserPreset:
        Result := DoExtractPreset(H, Entry.PresetIndex, Entry.FileName, ADestPath, ADestName);
    else
      Result := E_NOT_SUPPORTED;
    end;

    if Result <> E_SUCCESS then
    begin
      Inc(H.CurrentIndex);
      Exit;
    end;
  end;

  Inc(H.CurrentIndex);
  Result := E_SUCCESS;
end;

function ProcessFile(hArcData: THandle; Operation: Integer; DestPath, DestName: PAnsiChar): Integer; stdcall;
var
  SPath, SName: string;
begin
  if DestPath <> nil then
    SPath := string(AnsiString(DestPath))
  else
    SPath := '';
  if DestName <> nil then
    SName := string(AnsiString(DestName))
  else
    SName := '';
  Result := DoProcessFile(hArcData, Operation, SPath, SName);
end;

function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;
var
  SPath, SName: string;
begin
  if DestPath <> nil then
    SPath := DestPath
  else
    SPath := '';
  if DestName <> nil then
    SName := DestName
  else
    SName := '';
  Result := DoProcessFile(hArcData, Operation, SPath, SName);
end;

function CloseArchive(hArcData: THandle): Integer; stdcall;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle(hArcData);
  WcxLog(Format('CloseArchive: %s', [H.FileName]));
  H.Settings.Free;
  H.Free;
  Result := E_SUCCESS;
end;

procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
begin
  {Not used: video files are single-volume}
end;

procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
begin
  {Not used: video files are single-volume. Exported for ABI completeness so
   modern TC builds find the symbol they expect.}
end;

procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
begin
  {Stored on the handle; the preset extractor invokes it via
   uWcxProgressBridge to surface progress and observe user cancel.
   Legacy per-frame extraction is synchronous and does not call the
   callback.}
  if hArcData = 0 then
    Exit;
  TArchiveHandle(hArcData).ProcessDataProc := pProcessDataProc;
end;

procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;
begin
  if hArcData = 0 then
    Exit;
  TArchiveHandle(hArcData).ProcessDataProcW := pProcessDataProc;
end;

function GetPackerCaps: Integer; stdcall;
begin
  {Read-only "video as virtual archive" plugin: no PK_CAPS_NEW (cannot create
   archives), no PK_CAPS_MODIFY/DELETE. PK_CAPS_OPTIONS gives users a
   Configure button in TC's Configuration > Options > Plugins > Packer
   plugins UI; PK_CAPS_BY_CONTENT lets TC probe by content; PK_CAPS_HIDE
   keeps videos shown as ordinary files in the file panel. PK_CAPS_SEARCHTEXT
   is intentionally not set - the virtual archive entries are binary PNG/JPEG
   frames with no text content to search.}
  Result := PK_CAPS_BY_CONTENT or PK_CAPS_HIDE or PK_CAPS_OPTIONS;
end;

procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;
begin
  if (dps <> nil) and (dps^.Size >= SizeOf(TWcxDefaultParams)) then
  begin
    GIniPath := ChangeFileExt(string(AnsiString(dps^.DefaultIniName)), '.ini');
    WcxLog(Format('SetDefaultParams: ini=%s', [GIniPath]));
  end;
end;

function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar; Flags: Integer): Integer; stdcall;
begin
  Result := E_NOT_SUPPORTED;
end;

procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;
var
  Settings: TWcxSettings;
begin
  Settings := TWcxSettings.Create(GIniPath);
  try
    Settings.Load;
    if ShowWcxSettingsDialog(Parent, Settings,
      procedure
      begin
        TWcxFrameCache.Instance.Invalidate;
      end) then
    begin
      {ShowWcxSettingsDialog returns True only when TrySaveAll succeeded,
       which already called TWcxSettings.Save AND invoked the apply
       callback (Invalidate above). Keeping the Invalidate here is
       belt-and-braces in case the dialog's contract changes; the
       previous duplicate Settings.Save was removed.}
      TWcxFrameCache.Instance.Invalidate;
    end;
  finally
    Settings.Free;
  end;
end;

initialization

{Fallback: INI next to the DLL, in case SetDefaultParams is not called
 before ConfigurePacker or OpenArchive}
GIniPath := ChangeFileExt(GetModuleName(HInstance), '.ini');

{Debug logging is opt-in via the hidden "[debug] LogEnabled=1" key in
 Glimpse.ini. Start silent; DoOpenArchive flips GDebugLogPath on or off
 each time after reading the setting, so a hand-edit of the INI takes
 effect on the next archive open without a TC restart.}
GDebugLogPath := '';

{Seed the global Random once per DLL load. CalculateRandomFrameOffsets
 reads from this RNG; without seeding, every TC session would emit the
 same "random" sequence on this plugin and defeat the user's intent of
 a non-deterministic frame layout.}
Randomize;

finalization

TWcxFrameCache.ReleaseInstance;

end.
