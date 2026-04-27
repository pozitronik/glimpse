{WCX plugin exported functions.
 Presents a video file as a virtual archive containing frame images.}
unit uWcxExports;

interface

uses
  Winapi.Windows, uWcxAPI;

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
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;

{Reports plugin capabilities}
function GetPackerCaps: Integer; stdcall;

{Receives default INI path from TC}
procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;

{Stub: packing not supported, exists only to make Configure button accessible}
function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar; Flags: Integer): Integer; stdcall;

{Shows configuration dialog}
procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;

implementation

uses
  System.SysUtils, System.AnsiStrings, System.IOUtils,
  Vcl.Graphics,
  uWcxSettings, uWcxSettingsDlg, uFFmpegLocator, uFFmpegExe, uFrameOffsets,
  uFrameFileNames, uBitmapSaver, uFrameExtractor,
  uCombinedImage, uDebugLog, uPathExpand, uProbeCache, uTypes, uBitmapResize;

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
  end;

var
  GIniPath: string;
  {Module-level cache for pre-extracted frames (survives across OpenArchive calls)}
  GCachedVideoFile: string;
  GCachedTempDir: string;
  GCachedTempPaths: TArray<string>;
  GCachedEntrySizes: TArray<Int64>;

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

procedure InvalidateFrameCache;
begin
  if (GCachedTempDir <> '') and TDirectory.Exists(GCachedTempDir) then
    TDirectory.Delete(GCachedTempDir, True);
  GCachedVideoFile := '';
  GCachedTempDir := '';
  GCachedTempPaths := nil;
  GCachedEntrySizes := nil;
end;

function GetEntryCount(H: TArchiveHandle): Integer;
begin
  if H.Settings.OutputMode = womCombined then
    Result := 1
  else
    Result := Length(H.Offsets);
end;

function GetEntryName(H: TArchiveHandle): string;
begin
  if H.Settings.OutputMode = womCombined then
    Result := GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat)
  else
    Result := GenerateFrameFileName(H.FileName, H.CurrentIndex, H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat);
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

{Extracts all frames, renders a combined image, and saves to cache}
procedure ExtractCombinedToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor);
var
  Combined: TBitmap;
  TempPath: string;
begin
  Combined := RenderCombinedBitmap(H, AExtractor);
  if Combined = nil then
    Exit;
  try
    TempPath := TPath.Combine(GCachedTempDir, GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat));
    SaveBitmapToFile(Combined, TempPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
    GCachedTempPaths[0] := TempPath;
    GCachedEntrySizes[0] := TFile.GetSize(TempPath);
  finally
    Combined.Free;
  end;
end;

{Extracts individual frames and saves each to cache}
procedure ExtractSeparateToCache(H: TArchiveHandle; const AExtractor: IFrameExtractor);
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
      TempPath := TPath.Combine(GCachedTempDir, GenerateFrameFileName(H.FileName, I, H.Offsets[I].TimeOffset, H.Settings.SaveFormat));
      SaveBitmapToFile(Bmp, TempPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
      GCachedTempPaths[I] := TempPath;
      GCachedEntrySizes[I] := TFile.GetSize(TempPath);
    finally
      Bmp.Free;
    end;
  end;
end;

{Pre-extracts all frames to a module-level temp cache, or reuses
 an existing cache if the same video was already extracted.}
procedure PreExtractFrames(H: TArchiveHandle);
var
  Extractor: IFrameExtractor;
  EntryCount: Integer;
begin
  {Reuse cached extraction if available for the same video}
  if (GCachedVideoFile = H.FileName) and (GCachedTempDir <> '') and TDirectory.Exists(GCachedTempDir) then
  begin
    H.TempPaths := GCachedTempPaths;
    H.EntrySizes := GCachedEntrySizes;
    WcxLog(Format('PreExtract: cache hit for %s', [H.FileName]));
    Exit;
  end;

  {Different video or no cache: invalidate old cache and extract fresh}
  InvalidateFrameCache;
  GCachedTempDir := TPath.Combine(TPath.GetTempPath, 'glimpse_wcx_' + TPath.GetGUIDFileName(False));
  TDirectory.CreateDirectory(GCachedTempDir);
  GCachedVideoFile := H.FileName;

  Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
  EntryCount := GetEntryCount(H);
  SetLength(GCachedTempPaths, EntryCount);
  SetLength(GCachedEntrySizes, EntryCount);

  if H.Settings.OutputMode = womCombined then
    ExtractCombinedToCache(H, Extractor)
  else
    ExtractSeparateToCache(H, Extractor);

  H.TempPaths := GCachedTempPaths;
  H.EntrySizes := GCachedEntrySizes;
  WcxLog(Format('PreExtract: %d entries to %s', [EntryCount, GCachedTempDir]));
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

    H.Offsets := CalculateFrameOffsets(H.VideoInfo.Duration, H.Settings.FramesCount, H.Settings.SkipEdgesPercent);
    H.FileTime := DateTimeToFileDate(TFile.GetLastWriteTime(AFileName));

    if H.Settings.ShowFileSizes then
      PreExtractFrames(H);

    WcxLog(Format('OpenArchive: %s frames=%d', [AFileName, Length(H.Offsets)]));
    Result := THandle(H);
  except
    H.Free;
    AOpenResult := E_BAD_ARCHIVE;
  end;
end;

function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
begin
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
  if (H.EntrySizes <> nil) and (H.CurrentIndex < Length(H.EntrySizes)) then
    HeaderData.UnpSize := H.EntrySizes[H.CurrentIndex];
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
  if (H.EntrySizes <> nil) and (H.CurrentIndex < Length(H.EntrySizes)) then
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
    AResult := E_EWRITE;
  end;
end;

function DoExtractSeparate(H: TArchiveHandle; const ADestPath, ADestName: string): Integer;
var
  Extractor: IFrameExtractor;
  Bmp: TBitmap;
  FullPath: string;
begin
  if H.CurrentIndex >= Length(H.Offsets) then
    Exit(E_END_ARCHIVE);

  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) + GenerateFrameFileName(H.FileName, H.CurrentIndex, H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxLog(Format('Extract frame %d -> %s', [H.CurrentIndex, FullPath]));

  if TryCopyCachedFrame(H.TempPaths, H.CurrentIndex, FullPath, Result) then
    Exit;

  Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
  try
    Bmp := Extractor.ExtractFrame(H.FileName, H.Offsets[H.CurrentIndex].TimeOffset, BuildExtractionOptions(H.Settings, H.Settings.FrameMaxSide));
    if Bmp = nil then
      Exit(E_BAD_DATA);
    try
      SaveBitmapToFile(Bmp, FullPath, H.Settings.SaveFormat, H.Settings.JpegQuality, H.Settings.PngCompression);
    finally
      Bmp.Free;
    end;
  except
    Exit(E_EWRITE);
  end;
  Result := E_SUCCESS;
end;

function DoExtractCombined(H: TArchiveHandle; const ADestPath, ADestName: string): Integer;
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

  if TryCopyCachedFrame(H.TempPaths, 0, FullPath, Result) then
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
    Result := E_EWRITE;
  end;
end;

function DoProcessFile(hArcData: THandle; Operation: Integer; const ADestPath, ADestName: string): Integer;
var
  H: TArchiveHandle;
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
    if H.Settings.OutputMode = womCombined then
      Result := DoExtractCombined(H, ADestPath, ADestName)
    else
      Result := DoExtractSeparate(H, ADestPath, ADestName);

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

procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
begin
  {Callback stored but not invoked: extraction is synchronous per-frame}
end;

function GetPackerCaps: Integer; stdcall;
begin
  {Read-only "video as virtual archive" plugin: no PK_CAPS_NEW (cannot create
   archives), no PK_CAPS_MODIFY/DELETE. PK_CAPS_OPTIONS gives users a
   Configure button in TC's Configuration > Options > Plugins > Packer
   plugins UI; PK_CAPS_BY_CONTENT lets TC probe by content; PK_CAPS_HIDE
   keeps videos shown as ordinary files in the file panel.}
  Result := PK_CAPS_BY_CONTENT or PK_CAPS_SEARCHTEXT or PK_CAPS_HIDE or PK_CAPS_OPTIONS;
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
    if ShowWcxSettingsDialog(Parent, Settings, procedure begin InvalidateFrameCache; end) then
    begin
      Settings.Save;
      InvalidateFrameCache;
    end;
  finally
    Settings.Free;
  end;
end;

initialization

{Fallback: INI next to the DLL, in case SetDefaultParams is not called
 before ConfigurePacker or OpenArchive}
GIniPath := ChangeFileExt(GetModuleName(HInstance), '.ini');

finalization

InvalidateFrameCache;

end.
