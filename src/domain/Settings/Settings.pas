{Plugin settings manager backed by an INI file.}
unit Settings;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.UITypes, System.Math,
  BitmapSaver, Types, StatusBarLayout, Defaults, Hotkeys, SettingsGroups, UnicodeIniFile,
  SettingsInterfaces;

type
  {Inherits from TNoRefCountObject (not TInterfacedObject) because the
   WLX form owns the instance manually; automatic refcounting would
   crash when both the form and an interface field hold the same instance.}
  TPluginSettings = class(TNoRefCountObject,
    ITimecodeStyleProvider, IBannerStyleProvider, ISaveFormatPolicy,
    IRenderColorPolicy, IClipboardPolicy)
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
    FHotkeys: THotkeyBindings;
    FDebugLogEnabled: Boolean;

    function GetModeZoom(AMode: TViewMode): TZoomMode;
    procedure SetModeZoom(AMode: TViewMode; AValue: TZoomMode);
    function GetActiveZoom: TZoomMode;
    procedure SetActiveZoom(AValue: TZoomMode);
  public
    constructor Create(const AIniPath: string);
    destructor Destroy; override;
    {In-memory instance with no persistence; caller owns the result.}
    class function CreateDefaults: TPluginSettings; static;

    procedure Load;
    procedure Save;
    procedure ResetDefaults;
    {Enforces cross-field invariants that per-setter writes cannot
     guarantee. Today: pulls MinFrameSide down to MaxFrameSide when
     inverted (otherwise CalcExtractionMaxSide's EnsureRange silently
     returns the larger value, locking extraction size). Idempotent.
     Called at Load tail, Save head, and dialog ControlsToSettings tail.}
    procedure Validate;

    property IniPath: string read FIniPath;

    {Setters write fields directly with no validation. Load clamps numeric
     values to their range; Validate enforces cross-field invariants and
     runs automatically at Load/Save/dialog-commit boundaries. Do not add
     per-setter clamping here without removing the matching clamp in Load
     — duplicate validation has historically diverged.}

    property FFmpegMode: TFFmpegMode read FFFmpeg.Mode write FFFmpeg.Mode;
    property FFmpegExePath: string read FFFmpeg.ExePath write FFFmpeg.ExePath;
    property FFmpegAutoDownloaded: Boolean read FFFmpeg.AutoDownloaded write FFFmpeg.AutoDownloaded;

    {Atomic setter keeping Mode and ExePath consistent: empty APath drops
     both to (fmAuto, ''), non-empty promotes both to (fmExe, APath).
     Prevents the broken (fmAuto, '/path/to/ffmpeg') state where Load
     would silently discard the path.}
    procedure SetFFmpegPath(const APath: string);

    property FramesCount: Integer read FExtraction.FramesCount write FExtraction.FramesCount;
    property SkipEdgesPercent: Integer read FExtraction.SkipEdgesPercent write FExtraction.SkipEdgesPercent;
    property MaxWorkers: Integer read FExtraction.MaxWorkers write FExtraction.MaxWorkers;
    property MaxThreads: Integer read FExtraction.MaxThreads write FExtraction.MaxThreads;
    property UseBmpPipe: Boolean read FExtraction.UseBmpPipe write FExtraction.UseBmpPipe;
    property HwAccel: Boolean read FExtraction.HwAccel write FExtraction.HwAccel;
    property UseKeyframes: Boolean read FExtraction.UseKeyframes write FExtraction.UseKeyframes;
    property RespectAnamorphic: Boolean read FExtraction.RespectAnamorphic write FExtraction.RespectAnamorphic;
    {Whole-group access for callers that need the group-aware factory
     methods on style records (e.g. TTimestampStyle.FromSettings) instead
     of rebuilding the record field by field.}
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

    property ViewMode: TViewMode read FView.Mode write FView.Mode;
    {Indexed property routes through Get/SetModeZoom because Delphi does
     not allow indexed-property access directly through a record field.}
    property ModeZoom[AMode: TViewMode]: TZoomMode read GetModeZoom write SetModeZoom;
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

    property ExtensionList: string read FSave.ExtensionList write FSave.ExtensionList;

    property SaveFormat: TSaveFormat read FSave.SaveFormat write FSave.SaveFormat;
    property JpegQuality: Integer read FSave.JpegQuality write FSave.JpegQuality;
    property PngCompression: Integer read FSave.PngCompression write FSave.PngCompression;
    property BackgroundAlpha: Byte read FSave.BackgroundAlpha write FSave.BackgroundAlpha;
    property SaveFolder: string read FSave.SaveFolder write FSave.SaveFolder;
    property SaveAtLiveResolution: Boolean read FSave.SaveAtLiveResolution write FSave.SaveAtLiveResolution;
    property CopyAtLiveResolution: Boolean read FSave.CopyAtLiveResolution write FSave.CopyAtLiveResolution;
    property ClipboardAsFileReference: Boolean read FSave.ClipboardAsFileReference write FSave.ClipboardAsFileReference;
    property PublishAlphaAwareBitmap: Boolean read FClipboardFormats.PublishAlphaAwareBitmap write FClipboardFormats.PublishAlphaAwareBitmap;
    property PublishFlattenedBitmap: Boolean read FClipboardFormats.PublishFlattenedBitmap write FClipboardFormats.PublishFlattenedBitmap;
    property PublishBitmapHandle: Boolean read FClipboardFormats.PublishBitmapHandle write FClipboardFormats.PublishBitmapHandle;
    property PublishCompressedPng: Boolean read FClipboardFormats.PublishCompressedPng write FClipboardFormats.PublishCompressedPng;
    {Whole-group access so the worker thread captures a value-typed
     snapshot of the four publish toggles in one read rather than racing
     against per-field writes.}
    property ClipboardFormats: TClipboardFormatsGroup read FClipboardFormats;
    property CombinedMaxSide: Integer read FSave.CombinedMaxSide write FSave.CombinedMaxSide;
    property ShowBanner: Boolean read FBanner.Show write FBanner.Show;
    property BannerBackground: TColor read FBanner.Background write FBanner.Background;
    property BannerTextColor: TColor read FBanner.TextColor write FBanner.TextColor;
    property BannerFontName: string read FBanner.FontName write FBanner.FontName;
    property BannerFontSize: Integer read FBanner.FontSize write FBanner.FontSize;
    property BannerFontAutoSize: Boolean read FBanner.AutoSize write FBanner.AutoSize;
    property BannerPosition: TBannerPosition read FBanner.Position write FBanner.Position;

    property CacheEnabled: Boolean read FCache.Enabled write FCache.Enabled;
    property CacheFolder: string read FCache.Folder write FCache.Folder;
    property CacheMaxSizeMB: Integer read FCache.MaxSizeMB write FCache.MaxSizeMB;

    {QV* prefix kept for dialog-code compatibility; the group record drops
     the prefix because its name already namespaces the fields.}
    property QVDisableNavigation: Boolean read FQuickView.DisableNavigation write FQuickView.DisableNavigation;
    property QVHideToolbar: Boolean read FQuickView.HideToolbar write FQuickView.HideToolbar;
    property QVHideStatusBar: Boolean read FQuickView.HideStatusBar write FQuickView.HideStatusBar;

    property ThumbnailsEnabled: Boolean read FThumbnails.Enabled write FThumbnails.Enabled;
    property ThumbnailMode: TThumbnailMode read FThumbnails.Mode write FThumbnails.Mode;
    property ThumbnailPosition: Integer read FThumbnails.Position write FThumbnails.Position;
    property ThumbnailGridFrames: Integer read FThumbnails.GridFrames write FThumbnails.GridFrames;

    property ProgressBarLayout: TProgressBarLayout read FView.ProgressBarLayout write FView.ProgressBarLayout;

    property StatusBarTemplate: string read FStatusBar.Template write FStatusBar.Template;
    property StatusBarFontName: string read FStatusBar.FontName write FStatusBar.FontName;
    property StatusBarFontSize: Integer read FStatusBar.FontSize write FStatusBar.FontSize;
    property StatusBarAutoWidthLive: Boolean read FStatusBar.AutoWidthLive write FStatusBar.AutoWidthLive;
    property StatusBarStretchPanels: Boolean read FStatusBar.StretchPanels write FStatusBar.StretchPanels;
    property StatusBarHeight: Integer read FStatusBar.Height write FStatusBar.Height;
    property StatusBarHeightApplyMode: TStatusBarHeightApplyMode read FStatusBar.HeightApplyMode write FStatusBar.HeightApplyMode;

    {Binding table owns itself; mutate via its Get/Put/ResetToDefaults
     API rather than scalar properties.}
    property Hotkeys: THotkeyBindings read FHotkeys;

    {Hidden toggle persisted under [debug] LogEnabled in Glimpse.ini. Read
     once at ListSetDefaultParams; hand-edits take effect on next TC restart.}
    property DebugLogEnabled: Boolean read FDebugLogEnabled write FDebugLogEnabled;

    function GetTimestamp: TTimestampSettingsGroup;
    function GetBanner: TBannerSettingsGroup;
    function GetShowBanner: Boolean;
    function GetSaveFormat: TSaveFormat;
    function GetSaveFolder: string;
    procedure SetSaveFolder(const AValue: string);
    function GetSaveAtLiveResolution: Boolean;
    procedure SetSaveAtLiveResolution(AValue: Boolean);
    function GetCopyAtLiveResolution: Boolean;
    function GetCombinedMaxSide: Integer;
    function GetBackground: TColor;
    function GetBackgroundAlpha: Byte;
    function GetCellGap: Integer;
    function GetCombinedBorder: Integer;
    function GetClipboardFormats: TClipboardFormatsGroup;
    function GetClipboardAsFileReference: Boolean;
    function GetPngCompression: Integer;
  end;

const
  {WLX-specific defaults — external callers (FrameView, TestSettings)
   import these. The group records inline equivalent literals to avoid
   a circular dependency; keeping the two in sync is a maintenance concern.}
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
   while a release install stays silent until opted in. The user's
   [debug] LogEnabled is authoritative when present.}
{$IFDEF DEBUG}
  DEF_DEBUG_LOG_ENABLED = True;
{$ELSE}
  DEF_DEBUG_LOG_ENABLED = False;
{$ENDIF}

  DEF_SKIP_EDGES_PERCENT = DEF_SKIP_EDGES;

function DefaultCacheFolder: string;

function EffectiveCacheFolder(const ACacheFolder: string): string;

implementation

uses
  PathExpand;

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
  {Empty IniPath is the documented sentinel for in-memory-only.}
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
  {Match historical constant names so a future divergence of either
   constant flows through, even though current values are identical.}
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
  {Guard against call-order shifts: FHotkeys would be nil if
   ResetDefaults ever ran before the constructor created the table.}
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
    {Clipboard-copy lives in its own [copy] section, separate from [save].
     Does NOT seed from [save] AtLiveResolution; users on the old INI
     get the default for the new key without disturbing save settings.}
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
  {Downstream CalcExtractionMaxSide calls EnsureRange with these as lo/hi;
   if Min > Max, EnsureRange silently returns the larger value and locks
   the extraction size. Pull Min down to Max so the cap honours the user's
   upper bound regardless of typing order.}
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
    {TUnicodeIniFile buffers writes in memory; UpdateFile flushes to disk
     or new values are discarded on Free.}
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

function TPluginSettings.GetTimestamp: TTimestampSettingsGroup;
begin
  Result := FTimestamp;
end;

function TPluginSettings.GetBanner: TBannerSettingsGroup;
begin
  Result := FBanner;
end;

function TPluginSettings.GetShowBanner: Boolean;
begin
  Result := FBanner.Show;
end;

function TPluginSettings.GetSaveFormat: TSaveFormat;
begin
  Result := FSave.SaveFormat;
end;

function TPluginSettings.GetSaveFolder: string;
begin
  Result := FSave.SaveFolder;
end;

procedure TPluginSettings.SetSaveFolder(const AValue: string);
begin
  FSave.SaveFolder := AValue;
end;

function TPluginSettings.GetSaveAtLiveResolution: Boolean;
begin
  Result := FSave.SaveAtLiveResolution;
end;

procedure TPluginSettings.SetSaveAtLiveResolution(AValue: Boolean);
begin
  FSave.SaveAtLiveResolution := AValue;
end;

function TPluginSettings.GetCopyAtLiveResolution: Boolean;
begin
  Result := FSave.CopyAtLiveResolution;
end;

function TPluginSettings.GetCombinedMaxSide: Integer;
begin
  Result := FSave.CombinedMaxSide;
end;

function TPluginSettings.GetBackground: TColor;
begin
  Result := FView.Background;
end;

function TPluginSettings.GetBackgroundAlpha: Byte;
begin
  Result := FSave.BackgroundAlpha;
end;

function TPluginSettings.GetCellGap: Integer;
begin
  Result := FView.CellGap;
end;

function TPluginSettings.GetCombinedBorder: Integer;
begin
  Result := FView.CombinedBorder;
end;

function TPluginSettings.GetClipboardFormats: TClipboardFormatsGroup;
begin
  Result := FClipboardFormats;
end;

function TPluginSettings.GetClipboardAsFileReference: Boolean;
begin
  Result := FSave.ClipboardAsFileReference;
end;

function TPluginSettings.GetPngCompression: Integer;
begin
  Result := FSave.PngCompression;
end;

end.
