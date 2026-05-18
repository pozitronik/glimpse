{Plugin settings manager backed by an INI file.
 Handles defaults, validation, type-safe access, and persistence.}
unit uSettings;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes, System.Math,
  uBitmapSaver, uTypes, uStatusBarLayout, uDefaults, uHotkeys, uSettingsGroups, uUnicodeIniFile;

type
  TPluginSettings = class
  strict private
    FIniPath: string;
    {[ffmpeg]}
    FFFmpegMode: TFFmpegMode;
    FFFmpegExePath: string;
    FFFmpegAutoDownloaded: Boolean;
    {[extraction] — group record, exposed via delegated properties below}
    FExtraction: TExtractionSettingsGroup;
    FScaledExtraction: Boolean;
    FMinFrameSide: Integer;
    FMaxFrameSide: Integer;
    FAutoRefreshOnViewportChange: Boolean;
    FRandomExtraction: Boolean;
    FRandomPercent: Integer;
    FCacheRandomFrames: Boolean;
    {[view]}
    FViewMode: TViewMode;
    FModeZoom: array [TViewMode] of TZoomMode;
    FBackground: TColor;
    FShowToolbar: Boolean;
    FShowStatusBar: Boolean;
    FCellGap: Integer;
    FCombinedBorder: Integer;
    {[view] — timestamp overlay group shared with WCX via uSettingsGroups}
    FTimestamp: TTimestampSettingsGroup;
    {[extensions]}
    FExtensionList: string;
    {[save]}
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    FBackgroundAlpha: Byte;
    FSaveFolder: string;
    FSaveAtLiveResolution: Boolean;
    FCopyAtLiveResolution: Boolean;
    FClipboardAsFileReference: Boolean;
    {[copy] — per-format publish toggles for the pf32bit clipboard path.
     See TClipboardFormatsGroup for the format-to-field mapping.}
    FClipboardFormats: TClipboardFormatsGroup;
    FCombinedMaxSide: Integer;
    {[save] — banner group shared with WCX}
    FBanner: TBannerSettingsGroup;
    {[cache]}
    FCacheEnabled: Boolean;
    FCacheFolder: string;
    FCacheMaxSizeMB: Integer;
    {[quickview]}
    FQVDisableNavigation: Boolean;
    FQVHideToolbar: Boolean;
    FQVHideStatusBar: Boolean;
    {[thumbnails]}
    FThumbnailsEnabled: Boolean;
    FThumbnailMode: TThumbnailMode;
    FThumbnailPosition: Integer; {0..100 percent}
    FThumbnailGridFrames: Integer; {count for grid mode}
    {[hotkeys] — owned; reset/load/save delegates through this object.}
    FHotkeys: THotkeyBindings;
    {[view] — progress-bar layout policy}
    FProgressBarLayout: TProgressBarLayout;
    {[statusbar] — user-configurable token template + font + auto-width
     measurement policy. The template feeds uStatusBarTemplate.Parse;
     missing or empty values fall back to the DEF_STATUSBAR_* constants
     so an upgraded INI from before this feature retains today's bar.}
    FStatusBarTemplate: string;
    FStatusBarFontName: string;
    FStatusBarFontSize: Integer;
    FStatusBarAutoWidthLive: Boolean;
    FStatusBarStretchPanels: Boolean;
    FStatusBarHeight: Integer;
    FStatusBarHeightApplyMode: TStatusBarHeightApplyMode;
    {[debug]}
    FDebugLogEnabled: Boolean;

    class function StrToFFmpegMode(const AValue: string): TFFmpegMode; static;
    class function FFmpegModeToStr(AMode: TFFmpegMode): string; static;
    class function StrToViewMode(const AValue: string): TViewMode; static;
    class function ViewModeToStr(AMode: TViewMode): string; static;
    class function StrToZoomMode(const AValue: string): TZoomMode; static;
    class function ZoomModeToStr(AMode: TZoomMode): string; static;
    class function StrToSaveFormat(const AValue: string): TSaveFormat; static;
    class function SaveFormatToStr(AFormat: TSaveFormat): string; static;
    class function StrToThumbnailMode(const AValue: string): TThumbnailMode; static;
    class function ThumbnailModeToStr(AMode: TThumbnailMode): string; static;
    function GetModeZoom(AMode: TViewMode): TZoomMode;
    procedure SetModeZoom(AMode: TViewMode; AValue: TZoomMode);
    function GetActiveZoom: TZoomMode;
    procedure SetActiveZoom(AValue: TZoomMode);
  public
    constructor Create(const AIniPath: string);
    destructor Destroy; override;
    {Creates a transient TPluginSettings (no INI path) seeded with the
     historical defaults. Used by the Settings dialog's Defaults button
     to push every field back to its baked-in value without touching the
     persisted file. Caller owns the returned instance.}
    class function CreateDefaults: TPluginSettings; static;

    {Loads all settings from the INI file. Missing or invalid values get defaults.}
    procedure Load;
    {Writes all current settings to the INI file.}
    procedure Save;
    {Resets all fields to default values without touching the file.}
    procedure ResetDefaults;
    {Enforces cross-field invariants that per-setter writes cannot
     guarantee on their own. Today: pulls FMinFrameSide down to
     FMaxFrameSide when they are inverted (downstream CalcExtractionMaxSide
     calls EnsureRange with swapped lo/hi and silently returns the larger
     value, locking the extraction size). Idempotent — safe to call
     repeatedly. Invoked at the tail of Load, the head of Save, and at
     the tail of TSettingsForm.ControlsToSettings so the in-memory
     state is always self-consistent regardless of which entry point
     was used.}
    procedure Validate;

    property IniPath: string read FIniPath;

    {Property contract: setters write the field directly with no range or
     cross-field validation. Load clamps every numeric value to its
     documented range; Validate enforces cross-field invariants
     (e.g. MinFrameSide <= MaxFrameSide) and is automatically called at
     the tail of Load, the head of Save, and the tail of the dialog's
     ControlsToSettings. Programmatic mutators that bypass the dialog
     either write valid values themselves or call Validate explicitly.
     Do not add per-setter clamping here without removing the
     corresponding clamp in Load — duplicate validation has historically
     diverged.}

    {[ffmpeg]}
    property FFmpegMode: TFFmpegMode read FFFmpegMode write FFFmpegMode;
    property FFmpegExePath: string read FFFmpegExePath write FFFmpegExePath;
    property FFmpegAutoDownloaded: Boolean read FFFmpegAutoDownloaded write FFFmpegAutoDownloaded;

    {Atomic setter that keeps FFmpegMode and FFmpegExePath consistent: an
     empty APath drops both to (fmAuto, ''), a non-empty APath promotes
     both to (fmExe, APath). Callers can still write the two properties
     individually — the setter exists so a programmatic caller does not
     accidentally leave (fmAuto, '/path/to/ffmpeg') — a state where Load
     would silently discard the path because the persisted Mode is auto.}
    procedure SetFFmpegPath(const APath: string);

    {[extraction] — delegated to FExtraction so the field layout and INI
     Load/Save stay in lockstep with WCX via uSettingsGroups.}
    property FramesCount: Integer read FExtraction.FramesCount write FExtraction.FramesCount;
    property SkipEdgesPercent: Integer read FExtraction.SkipEdgesPercent write FExtraction.SkipEdgesPercent;
    property MaxWorkers: Integer read FExtraction.MaxWorkers write FExtraction.MaxWorkers;
    property MaxThreads: Integer read FExtraction.MaxThreads write FExtraction.MaxThreads;
    property UseBmpPipe: Boolean read FExtraction.UseBmpPipe write FExtraction.UseBmpPipe;
    property HwAccel: Boolean read FExtraction.HwAccel write FExtraction.HwAccel;
    property UseKeyframes: Boolean read FExtraction.UseKeyframes write FExtraction.UseKeyframes;
    property RespectAnamorphic: Boolean read FExtraction.RespectAnamorphic write FExtraction.RespectAnamorphic;
    {Read-only views of the persisted-settings groups. Surfaced so
     callers can use the group-aware factory methods on style records
     (TTimestampStyle.FromSettings / TBannerStyle.FromSettings /
     TExtractionSettingsGroup.ToExtractionOptions) instead of rebuilding
     each value record field-by-field.}
    property Extraction: TExtractionSettingsGroup read FExtraction;
    property Timestamp: TTimestampSettingsGroup read FTimestamp;
    property Banner: TBannerSettingsGroup read FBanner;
    property ScaledExtraction: Boolean read FScaledExtraction write FScaledExtraction;
    property MinFrameSide: Integer read FMinFrameSide write FMinFrameSide;
    property MaxFrameSide: Integer read FMaxFrameSide write FMaxFrameSide;
    property AutoRefreshOnViewportChange: Boolean read FAutoRefreshOnViewportChange write FAutoRefreshOnViewportChange;
    property RandomExtraction: Boolean read FRandomExtraction write FRandomExtraction;
    property RandomPercent: Integer read FRandomPercent write FRandomPercent;
    property CacheRandomFrames: Boolean read FCacheRandomFrames write FCacheRandomFrames;

    {[view]}
    property ViewMode: TViewMode read FViewMode write FViewMode;
    {Per-mode zoom: FModeZoom[AMode]}
    property ModeZoom[AMode: TViewMode]: TZoomMode read GetModeZoom write SetModeZoom;
    {Convenience: reads/writes FModeZoom[FViewMode]}
    property ZoomMode: TZoomMode read GetActiveZoom write SetActiveZoom;
    property Background: TColor read FBackground write FBackground;
    {ShowTimecode is the WLX name for the timestamp group's Show toggle;
     WCX exposes the same field as ShowTimestamp.}
    property ShowTimecode: Boolean read FTimestamp.Show write FTimestamp.Show;
    property ShowToolbar: Boolean read FShowToolbar write FShowToolbar;
    property ShowStatusBar: Boolean read FShowStatusBar write FShowStatusBar;
    property TimecodeBackColor: TColor read FTimestamp.BackColor write FTimestamp.BackColor;
    property TimecodeBackAlpha: Byte read FTimestamp.BackAlpha write FTimestamp.BackAlpha;
    property TimestampTextAlpha: Byte read FTimestamp.TextAlpha write FTimestamp.TextAlpha;
    property TimestampTextColor: TColor read FTimestamp.TextColor write FTimestamp.TextColor;
    property TimestampFontName: string read FTimestamp.FontName write FTimestamp.FontName;
    property TimestampFontSize: Integer read FTimestamp.FontSize write FTimestamp.FontSize;
    property CellGap: Integer read FCellGap write FCellGap;
    property CombinedBorder: Integer read FCombinedBorder write FCombinedBorder;
    property TimestampCorner: TTimestampCorner read FTimestamp.Corner write FTimestamp.Corner;

    {[extensions]}
    property ExtensionList: string read FExtensionList write FExtensionList;

    {[save]}
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property BackgroundAlpha: Byte read FBackgroundAlpha write FBackgroundAlpha;
    property SaveFolder: string read FSaveFolder write FSaveFolder;
    property SaveAtLiveResolution: Boolean read FSaveAtLiveResolution write FSaveAtLiveResolution;
    property CopyAtLiveResolution: Boolean read FCopyAtLiveResolution write FCopyAtLiveResolution;
    property ClipboardAsFileReference: Boolean read FClipboardAsFileReference write FClipboardAsFileReference;
    {[copy] — per-format clipboard publish toggles, delegated to
     FClipboardFormats so adding another format only touches the group.}
    property PublishAlphaAwareBitmap: Boolean read FClipboardFormats.PublishAlphaAwareBitmap write FClipboardFormats.PublishAlphaAwareBitmap;
    property PublishFlattenedBitmap: Boolean read FClipboardFormats.PublishFlattenedBitmap write FClipboardFormats.PublishFlattenedBitmap;
    property PublishBitmapHandle: Boolean read FClipboardFormats.PublishBitmapHandle write FClipboardFormats.PublishBitmapHandle;
    property PublishCompressedPng: Boolean read FClipboardFormats.PublishCompressedPng write FClipboardFormats.PublishCompressedPng;
    {Read-only access to the whole group record — used by the clipboard
     publish path (uFrameExport -> BuildClipboardFormatStrategies) so the
     worker thread captures a value-typed snapshot instead of four
     individual booleans.}
    property ClipboardFormats: TClipboardFormatsGroup read FClipboardFormats;
    property CombinedMaxSide: Integer read FCombinedMaxSide write FCombinedMaxSide;
    property ShowBanner: Boolean read FBanner.Show write FBanner.Show;
    property BannerBackground: TColor read FBanner.Background write FBanner.Background;
    property BannerTextColor: TColor read FBanner.TextColor write FBanner.TextColor;
    property BannerFontName: string read FBanner.FontName write FBanner.FontName;
    property BannerFontSize: Integer read FBanner.FontSize write FBanner.FontSize;
    property BannerFontAutoSize: Boolean read FBanner.AutoSize write FBanner.AutoSize;
    property BannerPosition: TBannerPosition read FBanner.Position write FBanner.Position;

    {[cache]}
    property CacheEnabled: Boolean read FCacheEnabled write FCacheEnabled;
    property CacheFolder: string read FCacheFolder write FCacheFolder;
    property CacheMaxSizeMB: Integer read FCacheMaxSizeMB write FCacheMaxSizeMB;

    {[quickview]}
    property QVDisableNavigation: Boolean read FQVDisableNavigation write FQVDisableNavigation;
    property QVHideToolbar: Boolean read FQVHideToolbar write FQVHideToolbar;
    property QVHideStatusBar: Boolean read FQVHideStatusBar write FQVHideStatusBar;

    {[thumbnails]}
    property ThumbnailsEnabled: Boolean read FThumbnailsEnabled write FThumbnailsEnabled;
    property ThumbnailMode: TThumbnailMode read FThumbnailMode write FThumbnailMode;
    property ThumbnailPosition: Integer read FThumbnailPosition write FThumbnailPosition;
    property ThumbnailGridFrames: Integer read FThumbnailGridFrames write FThumbnailGridFrames;

    {[view] — progress bar layout policy. Lives on the General tab next
     to "Show status bar".}
    property ProgressBarLayout: TProgressBarLayout read FProgressBarLayout write FProgressBarLayout;

    {[statusbar]}
    property StatusBarTemplate: string read FStatusBarTemplate write FStatusBarTemplate;
    property StatusBarFontName: string read FStatusBarFontName write FStatusBarFontName;
    property StatusBarFontSize: Integer read FStatusBarFontSize write FStatusBarFontSize;
    property StatusBarAutoWidthLive: Boolean read FStatusBarAutoWidthLive write FStatusBarAutoWidthLive;
    property StatusBarStretchPanels: Boolean read FStatusBarStretchPanels write FStatusBarStretchPanels;
    property StatusBarHeight: Integer read FStatusBarHeight write FStatusBarHeight;
    property StatusBarHeightApplyMode: TStatusBarHeightApplyMode read FStatusBarHeightApplyMode write FStatusBarHeightApplyMode;

    {[hotkeys] — the binding table owns itself; callers mutate it via its
     own Get/Put/ResetToDefaults API rather than through scalar properties.}
    property Hotkeys: THotkeyBindings read FHotkeys;

    {[debug] — hidden toggle, no UI. Written into Glimpse.ini under
     [debug] LogEnabled=1. Off by default. The plugin reads it once at
     ListSetDefaultParams (TC startup) and applies it to GDebugLogPath;
     hand-edits take effect on the next TC restart.}
    property DebugLogEnabled: Boolean read FDebugLogEnabled write FDebugLogEnabled;
  end;

const
  {WLX-specific defaults}
  DEF_FFMPEG_MODE = fmAuto;
  DEF_FFMPEG_EXE_PATH = '';
  DEF_FFMPEG_AUTO_DL = False;
  DEF_VIEW_MODE = vmGrid;
  DEF_ZOOM_MODE = zmFitWindow;
  DEF_BACKGROUND = TColor($001E1E1E);
  DEF_SHOW_TIMECODE = True;
  DEF_SHOW_TOOLBAR = True;
  DEF_SHOW_STATUS_BAR = True;
  DEF_CELL_GAP = 0;
  DEF_SAVE_FOLDER = '';
  DEF_SHOW_BANNER = False;
  DEF_CACHE_ENABLED = True;
  DEF_CACHE_FOLDER = '';
  DEF_CACHE_MAX_SIZE_MB = 500;
  DEF_QV_DISABLE_NAV = True;
  DEF_QV_HIDE_TOOLBAR = True;
  DEF_QV_HIDE_STATUSBAR = True;
  DEF_PROGRESS_BAR_LAYOUT = pblAuto;
  {Default differs by build so a fresh dev install logs out of the box
   while a release install stays silent until the user opts in. Either
   way the user's [debug] LogEnabled value (when present in Glimpse.ini)
   is authoritative; this constant only seeds defaults / a missing key.}
{$IFDEF DEBUG}
  DEF_DEBUG_LOG_ENABLED = True;
{$ELSE}
  DEF_DEBUG_LOG_ENABLED = False;
{$ENDIF}

  {Alias: uSettings historically used _PERCENT suffix}
  DEF_SKIP_EDGES_PERCENT = DEF_SKIP_EDGES;

  {Returns the default cache folder path used when CacheFolder setting is empty.}
function DefaultCacheFolder: string;

{Returns the effective cache folder: the configured value (with env vars expanded),
 or the default if empty.}
function EffectiveCacheFolder(const ACacheFolder: string): string;

implementation

uses
  uPathExpand, uColorConv;

function DefaultCacheFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'Glimpse' + PathDelim + 'cache');
end;

function EffectiveCacheFolder(const ACacheFolder: string): string;
begin
  if ACacheFolder <> '' then
    Result := ExpandEnvVars(ACacheFolder)
  else
    Result := DefaultCacheFolder;
end;

{TPluginSettings}

constructor TPluginSettings.Create(const AIniPath: string);
begin
  inherited Create;
  FIniPath := AIniPath;
  FHotkeys := THotkeyBindings.Create;
  ResetDefaults;
end;

class function TPluginSettings.CreateDefaults: TPluginSettings;
begin
  {Empty IniPath is the documented sentinel for "in-memory only, no
   persistence". The base constructor calls ResetDefaults so no extra
   step is needed.}
  Result := TPluginSettings.Create('');
end;

destructor TPluginSettings.Destroy;
begin
  FHotkeys.Free;
  inherited;
end;

procedure TPluginSettings.ResetDefaults;
begin
  FFFmpegMode := DEF_FFMPEG_MODE;
  FFFmpegExePath := DEF_FFMPEG_EXE_PATH;
  FFFmpegAutoDownloaded := DEF_FFMPEG_AUTO_DL;
  FExtraction := TExtractionSettingsGroup.Defaults;
  FScaledExtraction := DEF_SCALED_EXTRACTION;
  FMinFrameSide := DEF_MIN_FRAME_SIDE;
  FMaxFrameSide := DEF_MAX_FRAME_SIDE;
  FAutoRefreshOnViewportChange := DEF_AUTO_REFRESH_VIEWPORT;
  FRandomExtraction := DEF_RANDOM_EXTRACTION;
  FRandomPercent := DEF_RANDOM_PERCENT;
  FCacheRandomFrames := DEF_CACHE_RANDOM_FRAMES;
  FViewMode := DEF_VIEW_MODE;
  for var VM := Low(TViewMode) to High(TViewMode) do
    FModeZoom[VM] := DEF_ZOOM_MODE;
  FBackground := DEF_BACKGROUND;
  FShowToolbar := DEF_SHOW_TOOLBAR;
  FShowStatusBar := DEF_SHOW_STATUS_BAR;
  FTimestamp := TTimestampSettingsGroup.Defaults;
  {Group defaults seed Show=True and WLX font — match historical constant
   names even though current values are identical, so a future change to
   either constant flows through.}
  FTimestamp.Show := DEF_SHOW_TIMECODE;
  FTimestamp.FontName := DEF_TIMESTAMP_FONT;
  FTimestamp.FontSize := DEF_TIMESTAMP_FONT_SIZE;
  FCellGap := DEF_CELL_GAP;
  FCombinedBorder := DEF_COMBINED_BORDER;
  FExtensionList := DEF_EXTENSION_LIST;
  FSaveFormat := DEF_SAVE_FORMAT;
  FJpegQuality := DEF_JPEG_QUALITY;
  FPngCompression := DEF_PNG_COMPRESSION;
  FBackgroundAlpha := DEF_BACKGROUND_ALPHA;
  FSaveFolder := DEF_SAVE_FOLDER;
  FSaveAtLiveResolution := DEF_SAVE_AT_LIVE_RESOLUTION;
  FCopyAtLiveResolution := DEF_COPY_AT_LIVE_RESOLUTION;
  FClipboardAsFileReference := DEF_CLIPBOARD_AS_FILE_REFERENCE;
  FClipboardFormats := TClipboardFormatsGroup.Defaults;
  FCombinedMaxSide := DEF_COMBINED_MAX_SIDE;
  FBanner := TBannerSettingsGroup.Defaults;
  FBanner.Show := DEF_SHOW_BANNER;
  FCacheEnabled := DEF_CACHE_ENABLED;
  FCacheFolder := DEF_CACHE_FOLDER;
  FCacheMaxSizeMB := DEF_CACHE_MAX_SIZE_MB;
  FQVDisableNavigation := DEF_QV_DISABLE_NAV;
  FQVHideToolbar := DEF_QV_HIDE_TOOLBAR;
  FQVHideStatusBar := DEF_QV_HIDE_STATUSBAR;
  FThumbnailsEnabled := DEF_THUMBNAILS_ENABLED;
  FThumbnailMode := DEF_THUMBNAIL_MODE;
  FThumbnailPosition := DEF_THUMBNAIL_POSITION;
  FThumbnailGridFrames := DEF_THUMBNAIL_GRID_FRAMES;
  FProgressBarLayout := DEF_PROGRESS_BAR_LAYOUT;
  FStatusBarTemplate := DEF_STATUSBAR_TEMPLATE;
  FStatusBarFontName := DEF_STATUSBAR_FONT_NAME;
  FStatusBarFontSize := DEF_STATUSBAR_FONT_SIZE;
  FStatusBarAutoWidthLive := DEF_STATUSBAR_AUTO_WIDTH_LIVE;
  FStatusBarStretchPanels := DEF_STATUSBAR_STRETCH_PANELS;
  FStatusBarHeight := DEF_STATUSBAR_HEIGHT;
  FStatusBarHeightApplyMode := DEF_STATUSBAR_HEIGHT_APPLY_MODE;
  FDebugLogEnabled := DEF_DEBUG_LOG_ENABLED;
  {FHotkeys may be nil when ResetDefaults is called from the constructor
   before the hotkey table is allocated (the ctor creates it just above,
   so this path is safe today, but guard anyway in case call order shifts.)}
  if FHotkeys <> nil then
    FHotkeys.ResetToDefaults;
end;

procedure TPluginSettings.Load;
var
  Ini: TUnicodeIniFile;
begin
  ResetDefaults;
  if not FileExists(FIniPath) then
    Exit;

  Ini := TUnicodeIniFile.Create(FIniPath);
  try
    FFFmpegMode := StrToFFmpegMode(Ini.ReadString('ffmpeg', 'Mode', ''));
    FFFmpegExePath := Ini.ReadString('ffmpeg', 'ExePath', DEF_FFMPEG_EXE_PATH);
    FFFmpegAutoDownloaded := Ini.ReadBool('ffmpeg', 'AutoDownloaded', DEF_FFMPEG_AUTO_DL);

    FExtraction.LoadFrom(Ini, 'extraction');
    FScaledExtraction := Ini.ReadBool('extraction', 'ScaledExtraction', DEF_SCALED_EXTRACTION);
    FMinFrameSide := EnsureRange(Ini.ReadInteger('extraction', 'MinFrameSide', DEF_MIN_FRAME_SIDE), MIN_FRAME_SIDE, MAX_FRAME_SIDE);
    FMaxFrameSide := EnsureRange(Ini.ReadInteger('extraction', 'MaxFrameSide', DEF_MAX_FRAME_SIDE), MIN_FRAME_SIDE, MAX_FRAME_SIDE);
    {Cross-field invariant — Min <= Max — is enforced by Validate at the
     tail of this procedure, not inline here.}
    FAutoRefreshOnViewportChange := Ini.ReadBool('extraction', 'AutoRefreshOnViewportChange', DEF_AUTO_REFRESH_VIEWPORT);
    FRandomExtraction := Ini.ReadBool('extraction', 'RandomExtraction', DEF_RANDOM_EXTRACTION);
    FRandomPercent := EnsureRange(Ini.ReadInteger('extraction', 'RandomPercent', DEF_RANDOM_PERCENT), MIN_RANDOM_PERCENT, MAX_RANDOM_PERCENT);
    FCacheRandomFrames := Ini.ReadBool('extraction', 'CacheRandomFrames', DEF_CACHE_RANDOM_FRAMES);

    FViewMode := StrToViewMode(Ini.ReadString('view', 'Mode', ''));
    for var VM := Low(TViewMode) to High(TViewMode) do
      FModeZoom[VM] := StrToZoomMode(Ini.ReadString('view.' + ViewModeToStr(VM), 'ZoomMode', ''));
    FBackground := HexToColor(Ini.ReadString('view', 'Background', ''), DEF_BACKGROUND);
    FShowToolbar := Ini.ReadBool('view', 'ShowToolbar', DEF_SHOW_TOOLBAR);
    FShowStatusBar := Ini.ReadBool('view', 'ShowStatusBar', DEF_SHOW_STATUS_BAR);
    FProgressBarLayout := StrToProgressBarLayout(Ini.ReadString('view', 'ProgressBarLayout', ''), DEF_PROGRESS_BAR_LAYOUT);
    FTimestamp.LoadFrom(Ini, 'view', 'ShowTimecode');
    FCellGap := Max(Ini.ReadInteger('view', 'CellGap', DEF_CELL_GAP), MIN_CELL_GAP);
    FCombinedBorder := Max(Ini.ReadInteger('view', 'CombinedBorder', DEF_COMBINED_BORDER), MIN_COMBINED_BORDER);

    FExtensionList := Ini.ReadString('extensions', 'List', DEF_EXTENSION_LIST);
    if FExtensionList.Trim = '' then
      FExtensionList := DEF_EXTENSION_LIST;

    FSaveFormat := StrToSaveFormat(Ini.ReadString('save', 'Format', ''));
    FJpegQuality := EnsureRange(Ini.ReadInteger('save', 'JpegQuality', DEF_JPEG_QUALITY), MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
    FPngCompression := EnsureRange(Ini.ReadInteger('save', 'PngCompression', DEF_PNG_COMPRESSION), MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);
    FBackgroundAlpha := EnsureRange(Ini.ReadInteger('save', 'BackgroundAlpha', DEF_BACKGROUND_ALPHA), MIN_BACKGROUND_ALPHA, MAX_BACKGROUND_ALPHA);
    FSaveFolder := Ini.ReadString('save', 'SaveFolder', DEF_SAVE_FOLDER);
    FSaveAtLiveResolution := Ini.ReadBool('save', 'AtLiveResolution', DEF_SAVE_AT_LIVE_RESOLUTION);
    FCombinedMaxSide := EnsureRange(Ini.ReadInteger('save', 'CombinedMaxSide', DEF_COMBINED_MAX_SIDE), MIN_COMBINED_MAX_SIDE, MAX_COMBINED_MAX_SIDE);
    FBanner.LoadFrom(Ini, 'save');

    {Clipboard-copy live-resolution toggle. Lives in its own [copy]
     section (separate from [save]) so the two surfaces can be tuned
     independently. Defaults to False (matches pre-split behaviour) and
     does NOT seed from [save] AtLiveResolution - users on the old INI
     get the default for the new key, save settings stay untouched.}
    FCopyAtLiveResolution := Ini.ReadBool('copy', 'AtLiveResolution', DEF_COPY_AT_LIVE_RESOLUTION);
    FClipboardAsFileReference := Ini.ReadBool('copy', 'AsFileReference', DEF_CLIPBOARD_AS_FILE_REFERENCE);
    FClipboardFormats.LoadFrom(Ini, 'copy');

    FCacheEnabled := Ini.ReadBool('cache', 'Enabled', DEF_CACHE_ENABLED);
    FCacheFolder := Ini.ReadString('cache', 'Folder', DEF_CACHE_FOLDER);
    FCacheMaxSizeMB := EnsureRange(Ini.ReadInteger('cache', 'MaxSizeMB', DEF_CACHE_MAX_SIZE_MB), 10, 10000);

    FQVDisableNavigation := Ini.ReadBool('quickview', 'DisableNavigation', DEF_QV_DISABLE_NAV);
    FQVHideToolbar := Ini.ReadBool('quickview', 'HideToolbar', DEF_QV_HIDE_TOOLBAR);
    FQVHideStatusBar := Ini.ReadBool('quickview', 'HideStatusBar', DEF_QV_HIDE_STATUSBAR);

    FThumbnailsEnabled := Ini.ReadBool('thumbnails', 'Enabled', DEF_THUMBNAILS_ENABLED);
    FThumbnailMode := StrToThumbnailMode(Ini.ReadString('thumbnails', 'Mode', ''));
    FThumbnailPosition := EnsureRange(Ini.ReadInteger('thumbnails', 'Position', DEF_THUMBNAIL_POSITION), MIN_THUMBNAIL_POSITION, MAX_THUMBNAIL_POSITION);
    FThumbnailGridFrames := EnsureRange(Ini.ReadInteger('thumbnails', 'GridFrames', DEF_THUMBNAIL_GRID_FRAMES), MIN_THUMBNAIL_GRID_FRAMES, MAX_THUMBNAIL_GRID_FRAMES);

    FHotkeys.Load(Ini);

    {Status bar template + font + measurement policy. An empty Template
     value (user cleared the field, or hand-edited the INI) is treated
     as "use the default" rather than "render a blank bar" — empties
     creep in via UI bugs and we'd rather degrade safely than ship a
     broken bar.}
    FStatusBarTemplate := Ini.ReadString('statusbar', 'Template', DEF_STATUSBAR_TEMPLATE);
    if FStatusBarTemplate.Trim = '' then
      FStatusBarTemplate := DEF_STATUSBAR_TEMPLATE;
    FStatusBarFontName := Ini.ReadString('statusbar', 'FontName', DEF_STATUSBAR_FONT_NAME);
    if FStatusBarFontName.Trim = '' then
      FStatusBarFontName := DEF_STATUSBAR_FONT_NAME;
    FStatusBarFontSize := EnsureRange(
      Ini.ReadInteger('statusbar', 'FontSize', DEF_STATUSBAR_FONT_SIZE),
      MIN_STATUSBAR_FONT_SIZE, MAX_STATUSBAR_FONT_SIZE);
    FStatusBarAutoWidthLive := Ini.ReadBool('statusbar', 'AutoWidthLive', DEF_STATUSBAR_AUTO_WIDTH_LIVE);
    FStatusBarStretchPanels := Ini.ReadBool('statusbar', 'StretchPanels', DEF_STATUSBAR_STRETCH_PANELS);
    FStatusBarHeight := EnsureRange(
      Ini.ReadInteger('statusbar', 'Height', DEF_STATUSBAR_HEIGHT),
      MIN_STATUSBAR_HEIGHT, MAX_STATUSBAR_HEIGHT);
    FStatusBarHeightApplyMode := StrToStatusBarHeightApplyMode(
      Ini.ReadString('statusbar', 'HeightApplyMode', ''),
      DEF_STATUSBAR_HEIGHT_APPLY_MODE);

    FDebugLogEnabled := Ini.ReadBool('debug', 'LogEnabled', FDebugLogEnabled);
  finally
    Ini.Free;
  end;
  Validate;
end;

procedure TPluginSettings.Validate;
begin
  {Downstream CalcExtractionMaxSide calls EnsureRange with the two
   bounds in lo/hi order; if Min > Max, EnsureRange silently returns
   the larger value and the extraction size is locked to that single
   value. Pull Min down to Max so the cap honours the user's upper
   bound regardless of which order they typed the two numbers in.}
  if FMinFrameSide > FMaxFrameSide then
    FMinFrameSide := FMaxFrameSide;
end;

procedure TPluginSettings.Save;
var
  Ini: TUnicodeIniFile;
begin
  if FIniPath = '' then
    Exit;
  Validate;
  Ini := TUnicodeIniFile.Create(FIniPath);
  try
    Ini.WriteString('ffmpeg', 'Mode', FFmpegModeToStr(FFFmpegMode));
    Ini.WriteString('ffmpeg', 'ExePath', FFFmpegExePath);
    Ini.WriteBool('ffmpeg', 'AutoDownloaded', FFFmpegAutoDownloaded);

    FExtraction.SaveTo(Ini, 'extraction');
    Ini.WriteBool('extraction', 'ScaledExtraction', FScaledExtraction);
    Ini.WriteInteger('extraction', 'MinFrameSide', FMinFrameSide);
    Ini.WriteInteger('extraction', 'MaxFrameSide', FMaxFrameSide);
    Ini.WriteBool('extraction', 'AutoRefreshOnViewportChange', FAutoRefreshOnViewportChange);
    Ini.WriteBool('extraction', 'RandomExtraction', FRandomExtraction);
    Ini.WriteInteger('extraction', 'RandomPercent', FRandomPercent);
    Ini.WriteBool('extraction', 'CacheRandomFrames', FCacheRandomFrames);

    Ini.WriteString('view', 'Mode', ViewModeToStr(FViewMode));
    for var VM := Low(TViewMode) to High(TViewMode) do
      Ini.WriteString('view.' + ViewModeToStr(VM), 'ZoomMode', ZoomModeToStr(FModeZoom[VM]));
    Ini.WriteString('view', 'Background', ColorToHex(FBackground));
    Ini.WriteBool('view', 'ShowToolbar', FShowToolbar);
    Ini.WriteBool('view', 'ShowStatusBar', FShowStatusBar);
    Ini.WriteString('view', 'ProgressBarLayout', ProgressBarLayoutToStr(FProgressBarLayout));
    FTimestamp.SaveTo(Ini, 'view', 'ShowTimecode');
    Ini.WriteInteger('view', 'CellGap', FCellGap);
    Ini.WriteInteger('view', 'CombinedBorder', FCombinedBorder);

    Ini.WriteString('extensions', 'List', FExtensionList);

    Ini.WriteString('save', 'Format', SaveFormatToStr(FSaveFormat));
    Ini.WriteInteger('save', 'JpegQuality', FJpegQuality);
    Ini.WriteInteger('save', 'PngCompression', FPngCompression);
    Ini.WriteInteger('save', 'BackgroundAlpha', FBackgroundAlpha);
    Ini.WriteString('save', 'SaveFolder', FSaveFolder);
    Ini.WriteBool('save', 'AtLiveResolution', FSaveAtLiveResolution);
    Ini.WriteInteger('save', 'CombinedMaxSide', FCombinedMaxSide);
    FBanner.SaveTo(Ini, 'save');

    Ini.WriteBool('copy', 'AtLiveResolution', FCopyAtLiveResolution);
    Ini.WriteBool('copy', 'AsFileReference', FClipboardAsFileReference);
    FClipboardFormats.SaveTo(Ini, 'copy');

    Ini.WriteBool('cache', 'Enabled', FCacheEnabled);
    Ini.WriteString('cache', 'Folder', FCacheFolder);
    Ini.WriteInteger('cache', 'MaxSizeMB', FCacheMaxSizeMB);

    Ini.WriteBool('quickview', 'DisableNavigation', FQVDisableNavigation);
    Ini.WriteBool('quickview', 'HideToolbar', FQVHideToolbar);
    Ini.WriteBool('quickview', 'HideStatusBar', FQVHideStatusBar);

    Ini.WriteBool('thumbnails', 'Enabled', FThumbnailsEnabled);
    Ini.WriteString('thumbnails', 'Mode', ThumbnailModeToStr(FThumbnailMode));
    Ini.WriteInteger('thumbnails', 'Position', FThumbnailPosition);
    Ini.WriteInteger('thumbnails', 'GridFrames', FThumbnailGridFrames);

    FHotkeys.Save(Ini);

    Ini.WriteString('statusbar', 'Template', FStatusBarTemplate);
    Ini.WriteString('statusbar', 'FontName', FStatusBarFontName);
    Ini.WriteInteger('statusbar', 'FontSize', FStatusBarFontSize);
    Ini.WriteBool('statusbar', 'AutoWidthLive', FStatusBarAutoWidthLive);
    Ini.WriteBool('statusbar', 'StretchPanels', FStatusBarStretchPanels);
    Ini.WriteInteger('statusbar', 'Height', FStatusBarHeight);
    Ini.WriteString('statusbar', 'HeightApplyMode',
      StatusBarHeightApplyModeToStr(FStatusBarHeightApplyMode));

    Ini.WriteBool('debug', 'LogEnabled', FDebugLogEnabled);
    {TUnicodeIniFile buffers writes in memory; UpdateFile flushes to disk.
     Without it the new values would be discarded on Free.}
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TPluginSettings.SetFFmpegPath(const APath: string);
begin
  if APath <> '' then
  begin
    FFFmpegExePath := APath;
    FFFmpegMode := fmExe;
  end
  else
  begin
    FFFmpegExePath := '';
    FFFmpegMode := fmAuto;
  end;
end;

class function TPluginSettings.StrToFFmpegMode(const AValue: string): TFFmpegMode;
begin
  if SameText(AValue, 'exe') then
    Result := fmExe
  else
    Result := DEF_FFMPEG_MODE;
end;

class function TPluginSettings.FFmpegModeToStr(AMode: TFFmpegMode): string;
begin
  case AMode of
    fmExe:
      Result := 'exe';
    else
      Result := 'auto';
  end;
end;

class function TPluginSettings.StrToViewMode(const AValue: string): TViewMode;
begin
  if SameText(AValue, 'scroll') then
    Result := vmScroll
  else if SameText(AValue, 'smartgrid') then
    Result := vmSmartGrid
  else if SameText(AValue, 'filmstrip') then
    Result := vmFilmstrip
  else if SameText(AValue, 'single') then
    Result := vmSingle
  else
    Result := DEF_VIEW_MODE;
end;

class function TPluginSettings.ViewModeToStr(AMode: TViewMode): string;
begin
  case AMode of
    vmScroll:
      Result := 'scroll';
    vmSmartGrid:
      Result := 'smartgrid';
    vmFilmstrip:
      Result := 'filmstrip';
    vmSingle:
      Result := 'single';
    else
      Result := 'grid';
  end;
end;

class function TPluginSettings.StrToZoomMode(const AValue: string): TZoomMode;
begin
  if SameText(AValue, 'fitlarger') then
    Result := zmFitIfLarger
  else if SameText(AValue, 'actual') then
    Result := zmActual
  else
    Result := DEF_ZOOM_MODE;
end;

class function TPluginSettings.ZoomModeToStr(AMode: TZoomMode): string;
begin
  case AMode of
    zmFitIfLarger:
      Result := 'fitlarger';
    zmActual:
      Result := 'actual';
    else
      Result := 'fit';
  end;
end;

class function TPluginSettings.StrToSaveFormat(const AValue: string): TSaveFormat;
begin
  if SameText(AValue, 'JPEG') or SameText(AValue, 'JPG') then
    Result := sfJPEG
  else
    Result := DEF_SAVE_FORMAT;
end;

class function TPluginSettings.SaveFormatToStr(AFormat: TSaveFormat): string;
begin
  case AFormat of
    sfJPEG:
      Result := 'JPEG';
    else
      Result := 'PNG';
  end;
end;

class function TPluginSettings.StrToThumbnailMode(const AValue: string): TThumbnailMode;
begin
  if SameText(AValue, 'grid') then
    Result := tnmGrid
  else
    Result := tnmSingle;
end;

class function TPluginSettings.ThumbnailModeToStr(AMode: TThumbnailMode): string;
begin
  case AMode of
    tnmGrid:
      Result := 'grid';
    else
      Result := 'single';
  end;
end;

function TPluginSettings.GetModeZoom(AMode: TViewMode): TZoomMode;
begin
  Result := FModeZoom[AMode];
end;

procedure TPluginSettings.SetModeZoom(AMode: TViewMode; AValue: TZoomMode);
begin
  FModeZoom[AMode] := AValue;
end;

function TPluginSettings.GetActiveZoom: TZoomMode;
begin
  Result := FModeZoom[FViewMode];
end;

procedure TPluginSettings.SetActiveZoom(AValue: TZoomMode);
begin
  FModeZoom[FViewMode] := AValue;
end;

end.
