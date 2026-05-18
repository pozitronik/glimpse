{Plugin settings manager backed by an INI file.
 Aggregates per-section group records (TFFmpegSettingsGroup,
 TExtractionSettingsGroup, TViewSettingsGroup, TSaveSettingsGroup,
 TBannerSettingsGroup, TTimestampSettingsGroup, TClipboardFormatsGroup,
 TCacheSettingsGroup, TQuickViewSettingsGroup, TThumbnailsSettingsGroup,
 TStatusBarSettingsGroup) plus the hotkey table and a small number of
 fields (FIniPath, FDebugLogEnabled) that do not fit a single group.

 The class re-exposes every historical scalar property by delegating
 to the appropriate group field so the dialog code, settings snapshot,
 and external callers compile unchanged. ResetDefaults / Load / Save
 forward to each group's class function Defaults / LoadFrom / SaveTo;
 Validate keeps the cross-field invariants (today: MinFrameSide <=
 MaxFrameSide) because they span two group fields.}
unit uSettings;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes, System.Math,
  uBitmapSaver, uTypes, uStatusBarLayout, uDefaults, uHotkeys, uSettingsGroups, uUnicodeIniFile;

type
  TPluginSettings = class
  strict private
    FIniPath: string;
    FFFmpeg: TFFmpegSettingsGroup;
    FExtraction: TExtractionSettingsGroup;
    FView: TViewSettingsGroup;
    FTimestamp: TTimestampSettingsGroup;
    FSave: TSaveSettingsGroup;
    FClipboardFormats: TClipboardFormatsGroup;
    FBanner: TBannerSettingsGroup;
    FCache: TCacheSettingsGroup;
    FQuickView: TQuickViewSettingsGroup;
    FThumbnails: TThumbnailsSettingsGroup;
    FStatusBar: TStatusBarSettingsGroup;
    {[hotkeys] — owned; reset/load/save delegates through this object.}
    FHotkeys: THotkeyBindings;
    {[debug] — outside any group: a single hidden toggle with no
     dialog surface. Lives on TPluginSettings rather than a one-field
     group because the field-to-group ratio would not earn the boilerplate.}
    FDebugLogEnabled: Boolean;

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

    {[ffmpeg] — delegated to FFFmpeg.}
    property FFmpegMode: TFFmpegMode read FFFmpeg.Mode write FFFmpeg.Mode;
    property FFmpegExePath: string read FFFmpeg.ExePath write FFFmpeg.ExePath;
    property FFmpegAutoDownloaded: Boolean read FFFmpeg.AutoDownloaded write FFFmpeg.AutoDownloaded;

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
    property ScaledExtraction: Boolean read FSave.ScaledExtraction write FSave.ScaledExtraction;
    property MinFrameSide: Integer read FSave.MinFrameSide write FSave.MinFrameSide;
    property MaxFrameSide: Integer read FSave.MaxFrameSide write FSave.MaxFrameSide;
    property AutoRefreshOnViewportChange: Boolean read FSave.AutoRefreshOnViewportChange write FSave.AutoRefreshOnViewportChange;
    property RandomExtraction: Boolean read FCache.RandomExtraction write FCache.RandomExtraction;
    property RandomPercent: Integer read FCache.RandomPercent write FCache.RandomPercent;
    property CacheRandomFrames: Boolean read FCache.CacheRandomFrames write FCache.CacheRandomFrames;

    {[view]}
    property ViewMode: TViewMode read FView.Mode write FView.Mode;
    {Per-mode zoom: FView.ModeZoom[AMode]. The two-level indexed-property
     plumbing routes through Get/SetModeZoom because Delphi does not
     allow indexed property access directly through a record field.}
    property ModeZoom[AMode: TViewMode]: TZoomMode read GetModeZoom write SetModeZoom;
    {Convenience: reads/writes FView.ModeZoom[FView.Mode]}
    property ZoomMode: TZoomMode read GetActiveZoom write SetActiveZoom;
    property Background: TColor read FView.Background write FView.Background;
    {ShowTimecode is the WLX name for the timestamp group's Show toggle;
     WCX exposes the same field as ShowTimestamp.}
    property ShowTimecode: Boolean read FTimestamp.Show write FTimestamp.Show;
    property ShowToolbar: Boolean read FView.ShowToolbar write FView.ShowToolbar;
    property ShowStatusBar: Boolean read FView.ShowStatusBar write FView.ShowStatusBar;
    property TimecodeBackColor: TColor read FTimestamp.BackColor write FTimestamp.BackColor;
    property TimecodeBackAlpha: Byte read FTimestamp.BackAlpha write FTimestamp.BackAlpha;
    property TimestampTextAlpha: Byte read FTimestamp.TextAlpha write FTimestamp.TextAlpha;
    property TimestampTextColor: TColor read FTimestamp.TextColor write FTimestamp.TextColor;
    property TimestampFontName: string read FTimestamp.FontName write FTimestamp.FontName;
    property TimestampFontSize: Integer read FTimestamp.FontSize write FTimestamp.FontSize;
    property CellGap: Integer read FView.CellGap write FView.CellGap;
    property CombinedBorder: Integer read FView.CombinedBorder write FView.CombinedBorder;
    property TimestampCorner: TTimestampCorner read FTimestamp.Corner write FTimestamp.Corner;

    {[extensions]}
    property ExtensionList: string read FSave.ExtensionList write FSave.ExtensionList;

    {[save]}
    property SaveFormat: TSaveFormat read FSave.SaveFormat write FSave.SaveFormat;
    property JpegQuality: Integer read FSave.JpegQuality write FSave.JpegQuality;
    property PngCompression: Integer read FSave.PngCompression write FSave.PngCompression;
    property BackgroundAlpha: Byte read FSave.BackgroundAlpha write FSave.BackgroundAlpha;
    property SaveFolder: string read FSave.SaveFolder write FSave.SaveFolder;
    property SaveAtLiveResolution: Boolean read FSave.SaveAtLiveResolution write FSave.SaveAtLiveResolution;
    property CopyAtLiveResolution: Boolean read FSave.CopyAtLiveResolution write FSave.CopyAtLiveResolution;
    property ClipboardAsFileReference: Boolean read FSave.ClipboardAsFileReference write FSave.ClipboardAsFileReference;
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
    property CombinedMaxSide: Integer read FSave.CombinedMaxSide write FSave.CombinedMaxSide;
    property ShowBanner: Boolean read FBanner.Show write FBanner.Show;
    property BannerBackground: TColor read FBanner.Background write FBanner.Background;
    property BannerTextColor: TColor read FBanner.TextColor write FBanner.TextColor;
    property BannerFontName: string read FBanner.FontName write FBanner.FontName;
    property BannerFontSize: Integer read FBanner.FontSize write FBanner.FontSize;
    property BannerFontAutoSize: Boolean read FBanner.AutoSize write FBanner.AutoSize;
    property BannerPosition: TBannerPosition read FBanner.Position write FBanner.Position;

    {[cache]}
    property CacheEnabled: Boolean read FCache.Enabled write FCache.Enabled;
    property CacheFolder: string read FCache.Folder write FCache.Folder;
    property CacheMaxSizeMB: Integer read FCache.MaxSizeMB write FCache.MaxSizeMB;

    {[quickview] — historical "QV" prefix kept on the property names for
     dialog-code compatibility; the group record drops the prefix because
     its name already namespaces the fields.}
    property QVDisableNavigation: Boolean read FQuickView.DisableNavigation write FQuickView.DisableNavigation;
    property QVHideToolbar: Boolean read FQuickView.HideToolbar write FQuickView.HideToolbar;
    property QVHideStatusBar: Boolean read FQuickView.HideStatusBar write FQuickView.HideStatusBar;

    {[thumbnails]}
    property ThumbnailsEnabled: Boolean read FThumbnails.Enabled write FThumbnails.Enabled;
    property ThumbnailMode: TThumbnailMode read FThumbnails.Mode write FThumbnails.Mode;
    property ThumbnailPosition: Integer read FThumbnails.Position write FThumbnails.Position;
    property ThumbnailGridFrames: Integer read FThumbnails.GridFrames write FThumbnails.GridFrames;

    {[view] — progress bar layout policy. Lives on the General tab next
     to "Show status bar".}
    property ProgressBarLayout: TProgressBarLayout read FView.ProgressBarLayout write FView.ProgressBarLayout;

    {[statusbar]}
    property StatusBarTemplate: string read FStatusBar.Template write FStatusBar.Template;
    property StatusBarFontName: string read FStatusBar.FontName write FStatusBar.FontName;
    property StatusBarFontSize: Integer read FStatusBar.FontSize write FStatusBar.FontSize;
    property StatusBarAutoWidthLive: Boolean read FStatusBar.AutoWidthLive write FStatusBar.AutoWidthLive;
    property StatusBarStretchPanels: Boolean read FStatusBar.StretchPanels write FStatusBar.StretchPanels;
    property StatusBarHeight: Integer read FStatusBar.Height write FStatusBar.Height;
    property StatusBarHeightApplyMode: TStatusBarHeightApplyMode read FStatusBar.HeightApplyMode write FStatusBar.HeightApplyMode;

    {[hotkeys] — the binding table owns itself; callers mutate it via its
     own Get/Put/ResetToDefaults API rather than through scalar properties.}
    property Hotkeys: THotkeyBindings read FHotkeys;

    {[debug] — hidden toggle, no UI. Written into Glimpse.ini under
     [debug] LogEnabled=1. Off by default. The plugin reads it once at
     ListSetDefaultParams (TC startup) and forwards to
     TDebugLog.Configure; hand-edits take effect on the next TC restart.}
    property DebugLogEnabled: Boolean read FDebugLogEnabled write FDebugLogEnabled;
  end;

const
  {WLX-specific defaults — kept here for back-compat with external callers
   (uFrameView, TestSettings, etc.). The group records inline equivalent
   literals to avoid a circular dependency with uSettings; keeping these
   constants in sync with the group internals is a maintenance concern.}
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
  uPathExpand;

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
  FFFmpeg := TFFmpegSettingsGroup.Defaults;
  FExtraction := TExtractionSettingsGroup.Defaults;
  FView := TViewSettingsGroup.Defaults;
  FTimestamp := TTimestampSettingsGroup.Defaults;
  {Group defaults seed Show=True and WLX font — match historical constant
   names even though current values are identical, so a future change to
   either constant flows through.}
  FTimestamp.Show := DEF_SHOW_TIMECODE;
  FTimestamp.FontName := DEF_TIMESTAMP_FONT;
  FTimestamp.FontSize := DEF_TIMESTAMP_FONT_SIZE;
  FSave := TSaveSettingsGroup.Defaults;
  FClipboardFormats := TClipboardFormatsGroup.Defaults;
  FBanner := TBannerSettingsGroup.Defaults;
  FBanner.Show := DEF_SHOW_BANNER;
  FCache := TCacheSettingsGroup.Defaults;
  FQuickView := TQuickViewSettingsGroup.Defaults;
  FThumbnails := TThumbnailsSettingsGroup.Defaults;
  FStatusBar := TStatusBarSettingsGroup.Defaults;
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
    FFFmpeg.LoadFrom(Ini, 'ffmpeg');
    FExtraction.LoadFrom(Ini, 'extraction');
    FView.LoadFrom(Ini, 'view');
    FTimestamp.LoadFrom(Ini, 'view', 'ShowTimecode');
    FSave.LoadFrom(Ini);
    FBanner.LoadFrom(Ini, 'save');
    {Clipboard-copy live-resolution toggle. Lives in its own [copy]
     section (separate from [save]) so the two surfaces can be tuned
     independently. Defaults to False (matches pre-split behaviour) and
     does NOT seed from [save] AtLiveResolution - users on the old INI
     get the default for the new key, save settings stay untouched.}
    FClipboardFormats.LoadFrom(Ini, 'copy');
    FCache.LoadFrom(Ini);
    FQuickView.LoadFrom(Ini, 'quickview');
    FThumbnails.LoadFrom(Ini, 'thumbnails');
    FHotkeys.Load(Ini);
    FStatusBar.LoadFrom(Ini, 'statusbar');

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
  if FSave.MinFrameSide > FSave.MaxFrameSide then
    FSave.MinFrameSide := FSave.MaxFrameSide;
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
    FFFmpeg.SaveTo(Ini, 'ffmpeg');
    FExtraction.SaveTo(Ini, 'extraction');
    FView.SaveTo(Ini, 'view');
    FTimestamp.SaveTo(Ini, 'view', 'ShowTimecode');
    FSave.SaveTo(Ini);
    FBanner.SaveTo(Ini, 'save');
    FClipboardFormats.SaveTo(Ini, 'copy');
    FCache.SaveTo(Ini);
    FQuickView.SaveTo(Ini, 'quickview');
    FThumbnails.SaveTo(Ini, 'thumbnails');
    FHotkeys.Save(Ini);
    FStatusBar.SaveTo(Ini, 'statusbar');

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
    FFFmpeg.ExePath := APath;
    FFFmpeg.Mode := fmExe;
  end
  else
  begin
    FFFmpeg.ExePath := '';
    FFFmpeg.Mode := fmAuto;
  end;
end;

function TPluginSettings.GetModeZoom(AMode: TViewMode): TZoomMode;
begin
  Result := FView.ModeZoom[AMode];
end;

procedure TPluginSettings.SetModeZoom(AMode: TViewMode; AValue: TZoomMode);
begin
  FView.ModeZoom[AMode] := AValue;
end;

function TPluginSettings.GetActiveZoom: TZoomMode;
begin
  Result := FView.ModeZoom[FView.Mode];
end;

procedure TPluginSettings.SetActiveZoom(AValue: TZoomMode);
begin
  FView.ModeZoom[FView.Mode] := AValue;
end;

end.
