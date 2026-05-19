{Shared settings-group value objects for TPluginSettings (WLX) and
 TWcxSettings (WCX).

 Each record owns a related cluster of fields plus their INI Load/Save
 plumbing so the two settings classes don't have to re-implement the same
 key-by-key reads and writes. Defaults come from Defaults; field names
 match the external properties exposed by the owning settings classes so
 the refactor is behaviour-preserving.

 LoadFrom uses the *current* record state as the fallback when an INI key
 is missing — callers reset the record to defaults before Load so the
 record's values act as the defaults. String fields additionally fall
 back to the pre-load value if the INI stored an explicit empty string,
 matching the historical "empty string becomes default font" behaviour.

 The timestamp group takes the show-toggle INI key as a parameter because
 WLX historically wrote it as "ShowTimecode" under [view] while WCX used
 "ShowTimestamp" under [combined]. Keeping the key name configurable
 avoids breaking either plugin's existing INI files.}
unit SettingsGroups;

interface

uses
  System.UITypes,
  BitmapSaver, StatusBarLayout, Types, UnicodeIniFile;

type
  {[extraction] group — eight fields shared verbatim between WLX and WCX.
   Both plugins write these under the INI section 'extraction'.}
  TExtractionSettingsGroup = record
    FramesCount: Integer;
    SkipEdgesPercent: Integer;
    MaxWorkers: Integer;
    MaxThreads: Integer;
    UseBmpPipe: Boolean;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
    RespectAnamorphic: Boolean;

    {Populates every field with the shared Defaults constants.}
    class function Defaults: TExtractionSettingsGroup; static;
    {Reads the group from AIni. Missing keys fall back to the record's
     current values (callers reset to defaults first). Numeric fields are
     clamped to their documented ranges.}
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    {Writes the group to AIni. Round-trips exactly through LoadFrom.}
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
    {Builds a TExtractionOptions from this group's UseBmpPipe / HwAccel /
     UseKeyframes / RespectAnamorphic, with the caller-supplied MaxSide.
     The four boolean fields travel together through the extraction
     pipeline as TExtractionOptions; owning the conversion here keeps
     the field-by-field copy from leaking into every export-boundary
     caller (WcxExports.BuildExtractionOptions, WLX TPluginForm's
     extraction kickoff, etc.).
     AMaxSide=0 means "no scale limit" — combined-mode callers rely on
     this because the assembled grid is shrunk separately after rendering.}
    function ToExtractionOptions(AMaxSide: Integer = 0): TExtractionOptions;
  end;

  {Info-banner group — seven fields shared verbatim between WLX and WCX.
   Show is exposed externally as ShowBanner on both classes. Both plugins
   use the same set of INI key names; only the section differs (WLX 'save',
   WCX 'combined').}
  TBannerSettingsGroup = record
    Show: Boolean;
    Background: TColor;
    TextColor: TColor;
    FontName: string;
    FontSize: Integer;
    AutoSize: Boolean;
    Position: TBannerPosition;

    class function Defaults: TBannerSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

  {Clipboard publish-format group — four toggles controlling which Win32
   clipboard formats CopyBitmapToClipboard publishes for the pf32bit
   combined-image path in ClipboardImage. WLX-only today (WCX has no
   clipboard copy feature); lives alongside the shared groups for the
   common record/Defaults/LoadFrom/SaveTo pattern. Each toggle gates one
   format; the orchestrator skips both allocation and publish for a
   disabled format. All four True out of the box (see Defaults).}
  TClipboardFormatsGroup = record
    PublishAlphaAwareBitmap: Boolean; {CF_DIBV5}
    PublishFlattenedBitmap: Boolean;  {CF_DIB}
    PublishBitmapHandle: Boolean;     {CF_BITMAP}
    PublishCompressedPng: Boolean;    {registered "PNG" format}

    class function Defaults: TClipboardFormatsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

  {Timestamp overlay group — eight fields shared between WLX and WCX,
   modulo the show-toggle key name. WLX uses 'ShowTimecode' under [view],
   WCX uses 'ShowTimestamp' under [combined]. The caller passes the
   appropriate key name so neither plugin's existing INIs break.

   Show is exposed externally as ShowTimecode (WLX) / ShowTimestamp (WCX)
   via property delegation.}
  TTimestampSettingsGroup = record
    Show: Boolean;
    Corner: TTimestampCorner;
    FontName: string;
    FontSize: Integer;
    BackColor: TColor;
    BackAlpha: Byte;
    TextColor: TColor;
    TextAlpha: Byte;

    class function Defaults: TTimestampSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection, AShowKey: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection, AShowKey: string);
  end;

  {[ffmpeg] group — three fields covering the WLX-side ffmpeg locator.
   Mode + ExePath are the user-facing knobs; AutoDownloaded is a one-shot
   flag the auto-downloader sets so the next launch knows the bundled
   binary on disk is "ours" rather than a user-supplied path.}
  TFFmpegSettingsGroup = record
    Mode: TFFmpegMode;
    ExePath: string;
    AutoDownloaded: Boolean;

    class function Defaults: TFFmpegSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

  {[view] group — eight scalar fields plus the per-ViewMode zoom table.
   Background is the panel backdrop; ShowToolbar/ShowStatusBar gate the
   chrome; CellGap/CombinedBorder configure grid layout. ProgressBarLayout
   selects the bar placement policy on the status bar. ModeZoom[VM] stores
   one zoom mode per view mode so toggling view modes restores the last
   zoom used in that mode.

   ModeZoom is indexed by TViewMode and persisted under per-mode subsections
   "view.<modename>" (e.g. "view.grid", "view.scroll") under the key
   "ZoomMode". The pre-extraction TPluginSettings.Load used this exact
   layout — preserved verbatim so existing INI files round-trip.}
  TViewSettingsGroup = record
    Mode: TViewMode;
    ModeZoom: array [TViewMode] of TZoomMode;
    Background: TColor;
    ShowToolbar: Boolean;
    ShowStatusBar: Boolean;
    CellGap: Integer;
    CombinedBorder: Integer;
    ProgressBarLayout: TProgressBarLayout;

    class function Defaults: TViewSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

  {[save] group — bitmap-output configuration. SaveFormat selects PNG vs JPEG;
   JpegQuality / PngCompression are format-specific quality knobs;
   BackgroundAlpha governs cell-background transparency for the combined
   image. SaveFolder is the user-configured output directory.
   SaveAtLiveResolution / CopyAtLiveResolution gate live-zoom-aware export
   for the file-save and clipboard paths respectively. CombinedMaxSide
   caps the assembled combined-image dimension. ScaledExtraction toggles
   the scaled-down extraction path. ExtensionList is the comma-separated
   list of recognised video extensions. ClipboardAsFileReference toggles
   the CF_HDROP file-reference clipboard format. MinFrameSide/MaxFrameSide
   bound the extractor output dimension. AutoRefreshOnViewportChange
   triggers re-extraction on window-size deltas.

   This group spans three INI sections - some fields live under [save]
   (the bitmap-output ones), others under [extraction] (frame dimensions
   + auto-refresh + scaled), [copy] (clipboard live-resolution and
   file-reference toggles), [extensions] (the recognised list). Kept in
   one group because they're all "output knobs" from the user's POV, even
   though the historical INI layout split them across sections.}
  TSaveSettingsGroup = record
    SaveFormat: TSaveFormat;
    JpegQuality: Integer;
    PngCompression: Integer;
    BackgroundAlpha: Byte;
    SaveFolder: string;
    SaveAtLiveResolution: Boolean;
    CopyAtLiveResolution: Boolean;
    ClipboardAsFileReference: Boolean;
    CombinedMaxSide: Integer;
    ScaledExtraction: Boolean;
    MinFrameSide: Integer;
    MaxFrameSide: Integer;
    AutoRefreshOnViewportChange: Boolean;
    ExtensionList: string;

    class function Defaults: TSaveSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile);
    procedure SaveTo(AIni: TUnicodeIniFile);
  end;

  {[cache] group — three persisted cache knobs plus the two
   random-extraction toggles. RandomExtraction picks a random frame subset
   rather than evenly-spaced timestamps; RandomPercent bounds the random
   pick fraction; CacheRandomFrames decides whether random extracts should
   be cached (off by default — caching random frames defeats the "fresh
   picks every load" intent for most users).

   Historical layout note: RandomExtraction / RandomPercent / CacheRandomFrames
   live under [extraction] in the INI, NOT [cache], even though the cache-
   on-random toggle conceptually belongs here. Kept the original sections
   so old INIs round-trip; the group's LoadFrom/SaveTo names the section
   per-call where it diverges from the default.}
  TCacheSettingsGroup = record
    Enabled: Boolean;
    Folder: string;
    MaxSizeMB: Integer;
    RandomExtraction: Boolean;
    RandomPercent: Integer;
    CacheRandomFrames: Boolean;

    class function Defaults: TCacheSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile);
    procedure SaveTo(AIni: TUnicodeIniFile);
  end;

  {[quickview] group — three booleans gating Quick View chrome.
   The "QV" prefix has been dropped from the field names because the group
   record's name already namespaces them; the owning TPluginSettings
   re-exposes the historical QVDisableNavigation / QVHideToolbar /
   QVHideStatusBar property names so the dialog code remains unchanged.}
  TQuickViewSettingsGroup = record
    DisableNavigation: Boolean;
    HideToolbar: Boolean;
    HideStatusBar: Boolean;

    class function Defaults: TQuickViewSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

  {[thumbnails] group — four fields configuring TC panel-preview rendering.
   Enabled gates the whole feature; Mode picks single vs grid; Position
   (0..100) is the timeline-percentage offset of the single-frame preview;
   GridFrames is the cell count for the grid layout.}
  TThumbnailsSettingsGroup = record
    Enabled: Boolean;
    Mode: TThumbnailMode;
    Position: Integer;
    GridFrames: Integer;

    class function Defaults: TThumbnailsSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

  {[statusbar] group — user-configurable token template + font +
   auto-width measurement policy. The template feeds StatusBarTemplate.Parse;
   missing or empty values fall back to the DEF_STATUSBAR_* constants so
   an upgraded INI from before this feature retains today's bar. Height +
   HeightApplyMode govern the bar's explicit height in pixels with a
   window-mode gate (sbhamLister / sbhamQuickView / sbhamBoth).}
  TStatusBarSettingsGroup = record
    Template: string;
    FontName: string;
    FontSize: Integer;
    AutoWidthLive: Boolean;
    StretchPanels: Boolean;
    Height: Integer;
    HeightApplyMode: TStatusBarHeightApplyMode;

    class function Defaults: TStatusBarSettingsGroup; static;
    procedure LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
    procedure SaveTo(AIni: TUnicodeIniFile; const ASection: string);
  end;

implementation

uses
  System.Math, System.SysUtils,
  Defaults, ColorConv;

{TExtractionSettingsGroup}

class function TExtractionSettingsGroup.Defaults: TExtractionSettingsGroup;
begin
  Result.FramesCount := DEF_FRAMES_COUNT;
  Result.SkipEdgesPercent := DEF_SKIP_EDGES;
  Result.MaxWorkers := DEF_MAX_WORKERS;
  Result.MaxThreads := DEF_MAX_THREADS;
  Result.UseBmpPipe := DEF_USE_BMP_PIPE;
  Result.HwAccel := DEF_HW_ACCEL;
  Result.UseKeyframes := DEF_USE_KEYFRAMES;
  Result.RespectAnamorphic := DEF_RESPECT_ANAMORPHIC;
end;

procedure TExtractionSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
begin
  FramesCount := EnsureRange(AIni.ReadInteger(ASection, 'FramesCount', FramesCount),
    MIN_FRAMES_COUNT, MAX_FRAMES_COUNT);
  SkipEdgesPercent := EnsureRange(AIni.ReadInteger(ASection, 'SkipEdges', SkipEdgesPercent),
    MIN_SKIP_EDGES, MAX_SKIP_EDGES);
  MaxWorkers := EnsureRange(AIni.ReadInteger(ASection, 'MaxWorkers', MaxWorkers),
    MIN_MAX_WORKERS, MAX_MAX_WORKERS);
  MaxThreads := EnsureRange(AIni.ReadInteger(ASection, 'MaxThreads', MaxThreads),
    MIN_MAX_THREADS, MAX_MAX_THREADS);
  UseBmpPipe := AIni.ReadBool(ASection, 'UseBmpPipe', UseBmpPipe);
  HwAccel := AIni.ReadBool(ASection, 'HwAccel', HwAccel);
  UseKeyframes := AIni.ReadBool(ASection, 'UseKeyframes', UseKeyframes);
  RespectAnamorphic := AIni.ReadBool(ASection, 'RespectAnamorphic', RespectAnamorphic);
end;

function TExtractionSettingsGroup.ToExtractionOptions(AMaxSide: Integer): TExtractionOptions;
begin
  Result := Default(TExtractionOptions);
  Result.UseBmpPipe := UseBmpPipe;
  Result.HwAccel := HwAccel;
  Result.UseKeyframes := UseKeyframes;
  Result.RespectAnamorphic := RespectAnamorphic;
  Result.MaxSide := AMaxSide;
end;

procedure TExtractionSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteInteger(ASection, 'FramesCount', FramesCount);
  AIni.WriteInteger(ASection, 'SkipEdges', SkipEdgesPercent);
  AIni.WriteInteger(ASection, 'MaxWorkers', MaxWorkers);
  AIni.WriteInteger(ASection, 'MaxThreads', MaxThreads);
  AIni.WriteBool(ASection, 'UseBmpPipe', UseBmpPipe);
  AIni.WriteBool(ASection, 'HwAccel', HwAccel);
  AIni.WriteBool(ASection, 'UseKeyframes', UseKeyframes);
  AIni.WriteBool(ASection, 'RespectAnamorphic', RespectAnamorphic);
end;

{TBannerSettingsGroup}

class function TBannerSettingsGroup.Defaults: TBannerSettingsGroup;
begin
  {WLX previously used DEF_SHOW_BANNER = False; WCX used
   WCX_DEF_SHOW_BANNER = False. Both resolve to False, so a single
   default is correct. Callers that want a different initial Show
   state overwrite Show after calling Defaults.}
  Result.Show := False;
  Result.Background := DEF_BANNER_BACKGROUND;
  Result.TextColor := DEF_BANNER_TEXT_COLOR;
  Result.FontName := DEF_BANNER_FONT_NAME;
  Result.FontSize := DEF_BANNER_FONT_SIZE;
  Result.AutoSize := DEF_BANNER_FONT_AUTO_SIZE;
  Result.Position := DEF_BANNER_POSITION;
end;

procedure TBannerSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
var
  FallbackFont: string;
begin
  Show := AIni.ReadBool(ASection, 'ShowBanner', Show);
  Background := HexToColor(AIni.ReadString(ASection, 'BannerBackground', ''), Background);
  TextColor := HexToColor(AIni.ReadString(ASection, 'BannerTextColor', ''), TextColor);
  FallbackFont := FontName;
  FontName := AIni.ReadString(ASection, 'BannerFont', FontName);
  if FontName.Trim = '' then
    FontName := FallbackFont;
  FontSize := EnsureRange(AIni.ReadInteger(ASection, 'BannerFontSize', FontSize),
    MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE);
  AutoSize := AIni.ReadBool(ASection, 'BannerFontAutoSize', AutoSize);
  Position := StrToBannerPosition(AIni.ReadString(ASection, 'BannerPosition', ''), Position);
end;

procedure TBannerSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteBool(ASection, 'ShowBanner', Show);
  AIni.WriteString(ASection, 'BannerBackground', ColorToHex(Background));
  AIni.WriteString(ASection, 'BannerTextColor', ColorToHex(TextColor));
  AIni.WriteString(ASection, 'BannerFont', FontName);
  AIni.WriteInteger(ASection, 'BannerFontSize', FontSize);
  AIni.WriteBool(ASection, 'BannerFontAutoSize', AutoSize);
  AIni.WriteString(ASection, 'BannerPosition', BannerPositionToStr(Position));
end;

{TClipboardFormatsGroup}

class function TClipboardFormatsGroup.Defaults: TClipboardFormatsGroup;
begin
  Result.PublishAlphaAwareBitmap := DEF_PUBLISH_ALPHA_AWARE_BITMAP;
  Result.PublishFlattenedBitmap := DEF_PUBLISH_FLATTENED_BITMAP;
  Result.PublishBitmapHandle := DEF_PUBLISH_BITMAP_HANDLE;
  Result.PublishCompressedPng := DEF_PUBLISH_COMPRESSED_PNG;
end;

procedure TClipboardFormatsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
begin
  PublishAlphaAwareBitmap := AIni.ReadBool(ASection, 'PublishAlphaAwareBitmap', PublishAlphaAwareBitmap);
  PublishFlattenedBitmap := AIni.ReadBool(ASection, 'PublishFlattenedBitmap', PublishFlattenedBitmap);
  PublishBitmapHandle := AIni.ReadBool(ASection, 'PublishBitmapHandle', PublishBitmapHandle);
  PublishCompressedPng := AIni.ReadBool(ASection, 'PublishCompressedPng', PublishCompressedPng);
end;

procedure TClipboardFormatsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteBool(ASection, 'PublishAlphaAwareBitmap', PublishAlphaAwareBitmap);
  AIni.WriteBool(ASection, 'PublishFlattenedBitmap', PublishFlattenedBitmap);
  AIni.WriteBool(ASection, 'PublishBitmapHandle', PublishBitmapHandle);
  AIni.WriteBool(ASection, 'PublishCompressedPng', PublishCompressedPng);
end;

{TTimestampSettingsGroup}

class function TTimestampSettingsGroup.Defaults: TTimestampSettingsGroup;
begin
  {Show defaults to True — matches the WLX DEF_SHOW_TIMECODE. WCX's
   WCX_DEF_SHOW_TIMESTAMP is also True, so both plugins agree. Callers
   only override when they need a non-historical start state.
   FontName/FontSize match WLX's DEF_TIMESTAMP_FONT / _SIZE; WCX
   overrides these to Consolas/9 after calling Defaults because its
   historical default differs.}
  Result.Show := True;
  Result.Corner := DEF_TIMESTAMP_CORNER;
  Result.FontName := DEF_TIMESTAMP_FONT;
  Result.FontSize := DEF_TIMESTAMP_FONT_SIZE;
  Result.BackColor := DEF_TC_BACK_COLOR;
  Result.BackAlpha := DEF_TC_BACK_ALPHA;
  Result.TextColor := DEF_TIMESTAMP_TEXT_COLOR;
  Result.TextAlpha := DEF_TIMESTAMP_TEXT_ALPHA;
end;

procedure TTimestampSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection, AShowKey: string);
var
  FallbackFont: string;
  FallbackColor: TColor;
  FallbackAlpha: Byte;
begin
  Show := AIni.ReadBool(ASection, AShowKey, Show);
  Corner := StrToTimestampCorner(AIni.ReadString(ASection, 'TimestampCorner', ''), Corner);
  FallbackFont := FontName;
  FontName := AIni.ReadString(ASection, 'TimestampFont', FontName);
  if FontName.Trim = '' then
    FontName := FallbackFont;
  FontSize := EnsureRange(AIni.ReadInteger(ASection, 'TimestampFontSize', FontSize),
    MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
  {HexToColorAlpha's out-params are simple types, so aliasing with the
   const defaults is safe under Delphi's out semantics. Local fallback
   vars guard defensively anyway.}
  FallbackColor := BackColor;
  FallbackAlpha := BackAlpha;
  HexToColorAlpha(AIni.ReadString(ASection, 'TimecodeBackground', ''),
    FallbackColor, FallbackAlpha, BackColor, BackAlpha);
  TextColor := HexToColor(AIni.ReadString(ASection, 'TimestampTextColor', ''), TextColor);
  TextAlpha := EnsureRange(AIni.ReadInteger(ASection, 'TimestampTextAlpha', TextAlpha),
    MIN_TIMESTAMP_TEXT_ALPHA, MAX_TIMESTAMP_TEXT_ALPHA);
end;

procedure TTimestampSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection, AShowKey: string);
begin
  AIni.WriteBool(ASection, AShowKey, Show);
  AIni.WriteString(ASection, 'TimestampCorner', TimestampCornerToStr(Corner));
  AIni.WriteString(ASection, 'TimestampFont', FontName);
  AIni.WriteInteger(ASection, 'TimestampFontSize', FontSize);
  AIni.WriteString(ASection, 'TimecodeBackground', ColorAlphaToHex(BackColor, BackAlpha));
  AIni.WriteString(ASection, 'TimestampTextColor', ColorToHex(TextColor));
  AIni.WriteInteger(ASection, 'TimestampTextAlpha', TextAlpha);
end;

{TFFmpegSettingsGroup}

class function TFFmpegSettingsGroup.Defaults: TFFmpegSettingsGroup;
begin
  Result.Mode := fmAuto;
  Result.ExePath := '';
  Result.AutoDownloaded := False;
end;

procedure TFFmpegSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
begin
  {Mode falls back to fmAuto when the INI value is empty/unknown — see
   StrToFFmpegMode's one-arg overload. The pre-extraction WLX Load did
   not pass the record's current Mode as a fallback; preserving that
   behaviour so an INI without a [ffmpeg] section resolves to fmAuto
   even if the caller seeded a different default.}
  Mode := StrToFFmpegMode(AIni.ReadString(ASection, 'Mode', ''));
  ExePath := AIni.ReadString(ASection, 'ExePath', ExePath);
  AutoDownloaded := AIni.ReadBool(ASection, 'AutoDownloaded', AutoDownloaded);
end;

procedure TFFmpegSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteString(ASection, 'Mode', FFmpegModeToStr(Mode));
  AIni.WriteString(ASection, 'ExePath', ExePath);
  AIni.WriteBool(ASection, 'AutoDownloaded', AutoDownloaded);
end;

{TViewSettingsGroup}

class function TViewSettingsGroup.Defaults: TViewSettingsGroup;
var
  VM: TViewMode;
begin
  Result.Mode := vmGrid;
  {Per-mode zoom defaults to zmFitWindow for every view mode — matches
   the historical TPluginSettings.ResetDefaults which assigned
   DEF_ZOOM_MODE (= zmFitWindow) to every TModeZoom entry.}
  for VM := Low(TViewMode) to High(TViewMode) do
    Result.ModeZoom[VM] := zmFitWindow;
  {Background literal mirrors Settings.DEF_BACKGROUND; CellGap literal
   mirrors Settings.DEF_CELL_GAP. The two constants live in Settings
   (the historical home) and are re-exported via the owning settings
   class; the group inlines the values to avoid a circular dependency
   between SettingsGroups and Settings.}
  Result.Background := TColor($001E1E1E);
  Result.ShowToolbar := True;
  Result.ShowStatusBar := True;
  Result.CellGap := 0;
  Result.CombinedBorder := DEF_COMBINED_BORDER;
  Result.ProgressBarLayout := pblAuto;
end;

procedure TViewSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
var
  VM: TViewMode;
begin
  Mode := StrToViewMode(AIni.ReadString(ASection, 'Mode', ''));
  {Per-mode zoom lives in sub-sections "view.<modename>" under the key
   ZoomMode. Preserves the historical layout from the pre-extraction
   TPluginSettings.Load. The sub-section name is built from ASection so
   a future caller could pass an alternative root (today only WLX uses
   this group; WCX has no view-mode chooser).}
  for VM := Low(TViewMode) to High(TViewMode) do
    ModeZoom[VM] := StrToZoomMode(AIni.ReadString(
      ASection + '.' + ViewModeToStr(VM), 'ZoomMode', ''));
  Background := HexToColor(AIni.ReadString(ASection, 'Background', ''), Background);
  ShowToolbar := AIni.ReadBool(ASection, 'ShowToolbar', ShowToolbar);
  ShowStatusBar := AIni.ReadBool(ASection, 'ShowStatusBar', ShowStatusBar);
  CellGap := Max(AIni.ReadInteger(ASection, 'CellGap', CellGap), MIN_CELL_GAP);
  CombinedBorder := Max(AIni.ReadInteger(ASection, 'CombinedBorder', CombinedBorder),
    MIN_COMBINED_BORDER);
  ProgressBarLayout := StrToProgressBarLayout(
    AIni.ReadString(ASection, 'ProgressBarLayout', ''), ProgressBarLayout);
end;

procedure TViewSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
var
  VM: TViewMode;
begin
  AIni.WriteString(ASection, 'Mode', ViewModeToStr(Mode));
  for VM := Low(TViewMode) to High(TViewMode) do
    AIni.WriteString(ASection + '.' + ViewModeToStr(VM), 'ZoomMode',
      ZoomModeToStr(ModeZoom[VM]));
  AIni.WriteString(ASection, 'Background', ColorToHex(Background));
  AIni.WriteBool(ASection, 'ShowToolbar', ShowToolbar);
  AIni.WriteBool(ASection, 'ShowStatusBar', ShowStatusBar);
  AIni.WriteString(ASection, 'ProgressBarLayout',
    ProgressBarLayoutToStr(ProgressBarLayout));
  AIni.WriteInteger(ASection, 'CellGap', CellGap);
  AIni.WriteInteger(ASection, 'CombinedBorder', CombinedBorder);
end;

{TSaveSettingsGroup}

class function TSaveSettingsGroup.Defaults: TSaveSettingsGroup;
begin
  Result.SaveFormat := DEF_SAVE_FORMAT;
  Result.JpegQuality := DEF_JPEG_QUALITY;
  Result.PngCompression := DEF_PNG_COMPRESSION;
  Result.BackgroundAlpha := DEF_BACKGROUND_ALPHA;
  Result.SaveFolder := '';
  Result.SaveAtLiveResolution := DEF_SAVE_AT_LIVE_RESOLUTION;
  Result.CopyAtLiveResolution := DEF_COPY_AT_LIVE_RESOLUTION;
  Result.ClipboardAsFileReference := DEF_CLIPBOARD_AS_FILE_REFERENCE;
  Result.CombinedMaxSide := DEF_COMBINED_MAX_SIDE;
  Result.ScaledExtraction := DEF_SCALED_EXTRACTION;
  Result.MinFrameSide := DEF_MIN_FRAME_SIDE;
  Result.MaxFrameSide := DEF_MAX_FRAME_SIDE;
  Result.AutoRefreshOnViewportChange := DEF_AUTO_REFRESH_VIEWPORT;
  Result.ExtensionList := DEF_EXTENSION_LIST;
end;

procedure TSaveSettingsGroup.LoadFrom(AIni: TUnicodeIniFile);
begin
  {[save] section — bitmap-output knobs proper.}
  SaveFormat := StrToSaveFormat(AIni.ReadString('save', 'Format', ''));
  JpegQuality := EnsureRange(AIni.ReadInteger('save', 'JpegQuality', JpegQuality),
    MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
  PngCompression := EnsureRange(AIni.ReadInteger('save', 'PngCompression', PngCompression),
    MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);
  BackgroundAlpha := EnsureRange(AIni.ReadInteger('save', 'BackgroundAlpha', BackgroundAlpha),
    MIN_BACKGROUND_ALPHA, MAX_BACKGROUND_ALPHA);
  SaveFolder := AIni.ReadString('save', 'SaveFolder', SaveFolder);
  SaveAtLiveResolution := AIni.ReadBool('save', 'AtLiveResolution', SaveAtLiveResolution);
  CombinedMaxSide := EnsureRange(AIni.ReadInteger('save', 'CombinedMaxSide', CombinedMaxSide),
    MIN_COMBINED_MAX_SIDE, MAX_COMBINED_MAX_SIDE);

  {[copy] section — clipboard-side knobs (separate from [save] so the
   two surfaces can be tuned independently).}
  CopyAtLiveResolution := AIni.ReadBool('copy', 'AtLiveResolution', CopyAtLiveResolution);
  ClipboardAsFileReference := AIni.ReadBool('copy', 'AsFileReference', ClipboardAsFileReference);

  {[extraction] section — frame-dimension bounds + auto-refresh + scaled
   flag. The cross-field Min<=Max invariant is enforced by the owning
   TPluginSettings.Validate, not here.}
  ScaledExtraction := AIni.ReadBool('extraction', 'ScaledExtraction', ScaledExtraction);
  MinFrameSide := EnsureRange(AIni.ReadInteger('extraction', 'MinFrameSide', MinFrameSide),
    MIN_FRAME_SIDE, MAX_FRAME_SIDE);
  MaxFrameSide := EnsureRange(AIni.ReadInteger('extraction', 'MaxFrameSide', MaxFrameSide),
    MIN_FRAME_SIDE, MAX_FRAME_SIDE);
  AutoRefreshOnViewportChange := AIni.ReadBool('extraction', 'AutoRefreshOnViewportChange',
    AutoRefreshOnViewportChange);

  {[extensions] section — recognised video extensions list. Empty/whitespace
   collapses to the default so a UI bug can not strand the user with no
   recognised files.}
  ExtensionList := AIni.ReadString('extensions', 'List', ExtensionList);
  if ExtensionList.Trim = '' then
    ExtensionList := DEF_EXTENSION_LIST;
end;

procedure TSaveSettingsGroup.SaveTo(AIni: TUnicodeIniFile);
begin
  AIni.WriteString('save', 'Format', SaveFormatToStr(SaveFormat));
  AIni.WriteInteger('save', 'JpegQuality', JpegQuality);
  AIni.WriteInteger('save', 'PngCompression', PngCompression);
  AIni.WriteInteger('save', 'BackgroundAlpha', BackgroundAlpha);
  AIni.WriteString('save', 'SaveFolder', SaveFolder);
  AIni.WriteBool('save', 'AtLiveResolution', SaveAtLiveResolution);
  AIni.WriteInteger('save', 'CombinedMaxSide', CombinedMaxSide);

  AIni.WriteBool('copy', 'AtLiveResolution', CopyAtLiveResolution);
  AIni.WriteBool('copy', 'AsFileReference', ClipboardAsFileReference);

  AIni.WriteBool('extraction', 'ScaledExtraction', ScaledExtraction);
  AIni.WriteInteger('extraction', 'MinFrameSide', MinFrameSide);
  AIni.WriteInteger('extraction', 'MaxFrameSide', MaxFrameSide);
  AIni.WriteBool('extraction', 'AutoRefreshOnViewportChange', AutoRefreshOnViewportChange);

  AIni.WriteString('extensions', 'List', ExtensionList);
end;

{TCacheSettingsGroup}

class function TCacheSettingsGroup.Defaults: TCacheSettingsGroup;
begin
  Result.Enabled := True;
  Result.Folder := '';
  Result.MaxSizeMB := 500;
  Result.RandomExtraction := DEF_RANDOM_EXTRACTION;
  Result.RandomPercent := DEF_RANDOM_PERCENT;
  Result.CacheRandomFrames := DEF_CACHE_RANDOM_FRAMES;
end;

procedure TCacheSettingsGroup.LoadFrom(AIni: TUnicodeIniFile);
begin
  {[cache] section — the three persisted cache fields. MaxSizeMB clamp
   mirrors the pre-extraction WLX Load: 10..10000.}
  Enabled := AIni.ReadBool('cache', 'Enabled', Enabled);
  Folder := AIni.ReadString('cache', 'Folder', Folder);
  MaxSizeMB := EnsureRange(AIni.ReadInteger('cache', 'MaxSizeMB', MaxSizeMB), 10, 10000);

  {[extraction] section — the random-extraction fields live here in the
   INI for historical reasons (frame selection is an extraction concern
   even though CacheRandomFrames also touches caching).}
  RandomExtraction := AIni.ReadBool('extraction', 'RandomExtraction', RandomExtraction);
  RandomPercent := EnsureRange(AIni.ReadInteger('extraction', 'RandomPercent', RandomPercent),
    MIN_RANDOM_PERCENT, MAX_RANDOM_PERCENT);
  CacheRandomFrames := AIni.ReadBool('extraction', 'CacheRandomFrames', CacheRandomFrames);
end;

procedure TCacheSettingsGroup.SaveTo(AIni: TUnicodeIniFile);
begin
  AIni.WriteBool('cache', 'Enabled', Enabled);
  AIni.WriteString('cache', 'Folder', Folder);
  AIni.WriteInteger('cache', 'MaxSizeMB', MaxSizeMB);

  AIni.WriteBool('extraction', 'RandomExtraction', RandomExtraction);
  AIni.WriteInteger('extraction', 'RandomPercent', RandomPercent);
  AIni.WriteBool('extraction', 'CacheRandomFrames', CacheRandomFrames);
end;

{TQuickViewSettingsGroup}

class function TQuickViewSettingsGroup.Defaults: TQuickViewSettingsGroup;
begin
  Result.DisableNavigation := True;
  Result.HideToolbar := True;
  Result.HideStatusBar := True;
end;

procedure TQuickViewSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
begin
  DisableNavigation := AIni.ReadBool(ASection, 'DisableNavigation', DisableNavigation);
  HideToolbar := AIni.ReadBool(ASection, 'HideToolbar', HideToolbar);
  HideStatusBar := AIni.ReadBool(ASection, 'HideStatusBar', HideStatusBar);
end;

procedure TQuickViewSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteBool(ASection, 'DisableNavigation', DisableNavigation);
  AIni.WriteBool(ASection, 'HideToolbar', HideToolbar);
  AIni.WriteBool(ASection, 'HideStatusBar', HideStatusBar);
end;

{TThumbnailsSettingsGroup}

class function TThumbnailsSettingsGroup.Defaults: TThumbnailsSettingsGroup;
begin
  Result.Enabled := DEF_THUMBNAILS_ENABLED;
  Result.Mode := DEF_THUMBNAIL_MODE;
  Result.Position := DEF_THUMBNAIL_POSITION;
  Result.GridFrames := DEF_THUMBNAIL_GRID_FRAMES;
end;

procedure TThumbnailsSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
begin
  Enabled := AIni.ReadBool(ASection, 'Enabled', Enabled);
  Mode := StrToThumbnailMode(AIni.ReadString(ASection, 'Mode', ''));
  Position := EnsureRange(AIni.ReadInteger(ASection, 'Position', Position),
    MIN_THUMBNAIL_POSITION, MAX_THUMBNAIL_POSITION);
  GridFrames := EnsureRange(AIni.ReadInteger(ASection, 'GridFrames', GridFrames),
    MIN_THUMBNAIL_GRID_FRAMES, MAX_THUMBNAIL_GRID_FRAMES);
end;

procedure TThumbnailsSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteBool(ASection, 'Enabled', Enabled);
  AIni.WriteString(ASection, 'Mode', ThumbnailModeToStr(Mode));
  AIni.WriteInteger(ASection, 'Position', Position);
  AIni.WriteInteger(ASection, 'GridFrames', GridFrames);
end;

{TStatusBarSettingsGroup}

class function TStatusBarSettingsGroup.Defaults: TStatusBarSettingsGroup;
begin
  Result.Template := DEF_STATUSBAR_TEMPLATE;
  Result.FontName := DEF_STATUSBAR_FONT_NAME;
  Result.FontSize := DEF_STATUSBAR_FONT_SIZE;
  Result.AutoWidthLive := DEF_STATUSBAR_AUTO_WIDTH_LIVE;
  Result.StretchPanels := DEF_STATUSBAR_STRETCH_PANELS;
  Result.Height := DEF_STATUSBAR_HEIGHT;
  Result.HeightApplyMode := DEF_STATUSBAR_HEIGHT_APPLY_MODE;
end;

procedure TStatusBarSettingsGroup.LoadFrom(AIni: TUnicodeIniFile; const ASection: string);
begin
  {Template + FontName: empty/whitespace falls back to the default
   constant rather than the record's current value. Subtle: a user who
   cleared the field via the UI and saved would otherwise be stuck with
   a blank bar / nameless font.}
  Template := AIni.ReadString(ASection, 'Template', Template);
  if Template.Trim = '' then
    Template := DEF_STATUSBAR_TEMPLATE;
  FontName := AIni.ReadString(ASection, 'FontName', FontName);
  if FontName.Trim = '' then
    FontName := DEF_STATUSBAR_FONT_NAME;
  FontSize := EnsureRange(AIni.ReadInteger(ASection, 'FontSize', FontSize),
    MIN_STATUSBAR_FONT_SIZE, MAX_STATUSBAR_FONT_SIZE);
  AutoWidthLive := AIni.ReadBool(ASection, 'AutoWidthLive', AutoWidthLive);
  StretchPanels := AIni.ReadBool(ASection, 'StretchPanels', StretchPanels);
  Height := EnsureRange(AIni.ReadInteger(ASection, 'Height', Height),
    MIN_STATUSBAR_HEIGHT, MAX_STATUSBAR_HEIGHT);
  HeightApplyMode := StrToStatusBarHeightApplyMode(
    AIni.ReadString(ASection, 'HeightApplyMode', ''), HeightApplyMode);
end;

procedure TStatusBarSettingsGroup.SaveTo(AIni: TUnicodeIniFile; const ASection: string);
begin
  AIni.WriteString(ASection, 'Template', Template);
  AIni.WriteString(ASection, 'FontName', FontName);
  AIni.WriteInteger(ASection, 'FontSize', FontSize);
  AIni.WriteBool(ASection, 'AutoWidthLive', AutoWidthLive);
  AIni.WriteBool(ASection, 'StretchPanels', StretchPanels);
  AIni.WriteInteger(ASection, 'Height', Height);
  AIni.WriteString(ASection, 'HeightApplyMode',
    StatusBarHeightApplyModeToStr(HeightApplyMode));
end;

end.
