{ Plugin settings manager backed by an INI file.
  Handles defaults, validation, type-safe access, and persistence. }
unit uSettings;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, System.UITypes, System.Math,
  uBitmapSaver, uTypes, uDefaults;

type
  TPluginSettings = class
  strict private
    FIniPath: string;
    { [ffmpeg] }
    FFFmpegMode: TFFmpegMode;
    FFFmpegExePath: string;
    FFFmpegAutoDownloaded: Boolean;
    { [extraction] }
    FFramesCount: Integer;
    FSkipEdgesPercent: Integer;
    FMaxWorkers: Integer;
    FMaxThreads: Integer;
    FUseBmpPipe: Boolean;
    FHwAccel: Boolean;
    FUseKeyframes: Boolean;
    FScaledExtraction: Boolean;
    FMinFrameSide: Integer;
    FMaxFrameSide: Integer;
    { [view] }
    FViewMode: TViewMode;
    FModeZoom: array[TViewMode] of TZoomMode;
    FBackground: TColor;
    FShowTimecode: Boolean;
    FShowToolbar: Boolean;
    FShowStatusBar: Boolean;
    FTimecodeBackColor: TColor;
    FTimecodeBackAlpha: Byte;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    { [extensions] }
    FExtensionList: string;
    { [save] }
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    FSaveFolder: string;
    FShowBanner: Boolean;
    { [cache] }
    FCacheEnabled: Boolean;
    FCacheFolder: string;
    FCacheMaxSizeMB: Integer;
    { [quickview] }
    FQVDisableNavigation: Boolean;
    FQVHideToolbar: Boolean;
    FQVHideStatusBar: Boolean;

    class function StrToFFmpegMode(const AValue: string): TFFmpegMode; static;
    class function FFmpegModeToStr(AMode: TFFmpegMode): string; static;
    class function StrToViewMode(const AValue: string): TViewMode; static;
    class function ViewModeToStr(AMode: TViewMode): string; static;
    class function StrToZoomMode(const AValue: string): TZoomMode; static;
    class function ZoomModeToStr(AMode: TZoomMode): string; static;
    class function StrToSaveFormat(const AValue: string): TSaveFormat; static;
    class function SaveFormatToStr(AFormat: TSaveFormat): string; static;
    function GetModeZoom(AMode: TViewMode): TZoomMode;
    procedure SetModeZoom(AMode: TViewMode; AValue: TZoomMode);
    function GetActiveZoom: TZoomMode;
    procedure SetActiveZoom(AValue: TZoomMode);
  public
    constructor Create(const AIniPath: string);

    { Loads all settings from the INI file. Missing or invalid values get defaults. }
    procedure Load;
    { Writes all current settings to the INI file. }
    procedure Save;
    { Resets all fields to default values without touching the file. }
    procedure ResetDefaults;

    property IniPath: string read FIniPath;

    { [ffmpeg] }
    property FFmpegMode: TFFmpegMode read FFFmpegMode write FFFmpegMode;
    property FFmpegExePath: string read FFFmpegExePath write FFFmpegExePath;
    property FFmpegAutoDownloaded: Boolean read FFFmpegAutoDownloaded write FFFmpegAutoDownloaded;

    { [extraction] }
    property FramesCount: Integer read FFramesCount write FFramesCount;
    property SkipEdgesPercent: Integer read FSkipEdgesPercent write FSkipEdgesPercent;
    property MaxWorkers: Integer read FMaxWorkers write FMaxWorkers;
    property MaxThreads: Integer read FMaxThreads write FMaxThreads;
    property UseBmpPipe: Boolean read FUseBmpPipe write FUseBmpPipe;
    property HwAccel: Boolean read FHwAccel write FHwAccel;
    property UseKeyframes: Boolean read FUseKeyframes write FUseKeyframes;
    property ScaledExtraction: Boolean read FScaledExtraction write FScaledExtraction;
    property MinFrameSide: Integer read FMinFrameSide write FMinFrameSide;
    property MaxFrameSide: Integer read FMaxFrameSide write FMaxFrameSide;

    { [view] }
    property ViewMode: TViewMode read FViewMode write FViewMode;
    { Per-mode zoom: FModeZoom[AMode] }
    property ModeZoom[AMode: TViewMode]: TZoomMode read GetModeZoom write SetModeZoom;
    { Convenience: reads/writes FModeZoom[FViewMode] }
    property ZoomMode: TZoomMode read GetActiveZoom write SetActiveZoom;
    property Background: TColor read FBackground write FBackground;
    property ShowTimecode: Boolean read FShowTimecode write FShowTimecode;
    property ShowToolbar: Boolean read FShowToolbar write FShowToolbar;
    property ShowStatusBar: Boolean read FShowStatusBar write FShowStatusBar;
    property TimecodeBackColor: TColor read FTimecodeBackColor write FTimecodeBackColor;
    property TimecodeBackAlpha: Byte read FTimecodeBackAlpha write FTimecodeBackAlpha;
    property TimestampFontName: string read FTimestampFontName write FTimestampFontName;
    property TimestampFontSize: Integer read FTimestampFontSize write FTimestampFontSize;

    { [extensions] }
    property ExtensionList: string read FExtensionList write FExtensionList;

    { [save] }
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property SaveFolder: string read FSaveFolder write FSaveFolder;
    property ShowBanner: Boolean read FShowBanner write FShowBanner;

    { [cache] }
    property CacheEnabled: Boolean read FCacheEnabled write FCacheEnabled;
    property CacheFolder: string read FCacheFolder write FCacheFolder;
    property CacheMaxSizeMB: Integer read FCacheMaxSizeMB write FCacheMaxSizeMB;

    { [quickview] }
    property QVDisableNavigation: Boolean read FQVDisableNavigation write FQVDisableNavigation;
    property QVHideToolbar: Boolean read FQVHideToolbar write FQVHideToolbar;
    property QVHideStatusBar: Boolean read FQVHideStatusBar write FQVHideStatusBar;
  end;

const
  { WLX-specific defaults }
  DEF_FFMPEG_MODE        = fmAuto;
  DEF_FFMPEG_EXE_PATH    = '';
  DEF_FFMPEG_AUTO_DL     = False;
  DEF_VIEW_MODE          = vmGrid;
  DEF_ZOOM_MODE          = zmFitWindow;
  DEF_BACKGROUND         = TColor($001E1E1E);
  DEF_SHOW_TIMECODE      = True;
  DEF_SHOW_TOOLBAR       = True;
  DEF_SHOW_STATUS_BAR    = True;
  DEF_TC_BACK_COLOR      = TColor($002D2D2D);
  DEF_TC_BACK_ALPHA      = 180;
  DEF_TIMESTAMP_FONT     = 'Segoe UI';
  DEF_TIMESTAMP_FONT_SIZE = 8;
  DEF_SAVE_FOLDER        = '';
  DEF_SHOW_BANNER        = False;
  DEF_CACHE_ENABLED      = True;
  DEF_CACHE_FOLDER       = '';
  DEF_CACHE_MAX_SIZE_MB  = 500;
  DEF_QV_DISABLE_NAV     = True;
  DEF_QV_HIDE_TOOLBAR    = True;
  DEF_QV_HIDE_STATUSBAR  = True;

  { Alias: uSettings historically used _PERCENT suffix }
  DEF_SKIP_EDGES_PERCENT = DEF_SKIP_EDGES;

{ Returns the default cache folder path used when CacheFolder setting is empty. }
function DefaultCacheFolder: string;

{ Returns the effective cache folder: the configured value (with env vars expanded),
  or the default if empty. }
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

{ TPluginSettings }

constructor TPluginSettings.Create(const AIniPath: string);
begin
  inherited Create;
  FIniPath := AIniPath;
  ResetDefaults;
end;

procedure TPluginSettings.ResetDefaults;
begin
  FFFmpegMode := DEF_FFMPEG_MODE;
  FFFmpegExePath := DEF_FFMPEG_EXE_PATH;
  FFFmpegAutoDownloaded := DEF_FFMPEG_AUTO_DL;
  FFramesCount := DEF_FRAMES_COUNT;
  FSkipEdgesPercent := DEF_SKIP_EDGES_PERCENT;
  FMaxWorkers := DEF_MAX_WORKERS;
  FMaxThreads := DEF_MAX_THREADS;
  FUseBmpPipe := DEF_USE_BMP_PIPE;
  FHwAccel := DEF_HW_ACCEL;
  FUseKeyframes := DEF_USE_KEYFRAMES;
  FScaledExtraction := DEF_SCALED_EXTRACTION;
  FMinFrameSide := DEF_MIN_FRAME_SIDE;
  FMaxFrameSide := DEF_MAX_FRAME_SIDE;
  FViewMode := DEF_VIEW_MODE;
  for var VM := Low(TViewMode) to High(TViewMode) do
    FModeZoom[VM] := DEF_ZOOM_MODE;
  FBackground := DEF_BACKGROUND;
  FShowTimecode := DEF_SHOW_TIMECODE;
  FShowToolbar := DEF_SHOW_TOOLBAR;
  FShowStatusBar := DEF_SHOW_STATUS_BAR;
  FTimecodeBackColor := DEF_TC_BACK_COLOR;
  FTimecodeBackAlpha := DEF_TC_BACK_ALPHA;
  FTimestampFontName := DEF_TIMESTAMP_FONT;
  FTimestampFontSize := DEF_TIMESTAMP_FONT_SIZE;
  FExtensionList := DEF_EXTENSION_LIST;
  FSaveFormat := DEF_SAVE_FORMAT;
  FJpegQuality := DEF_JPEG_QUALITY;
  FPngCompression := DEF_PNG_COMPRESSION;
  FSaveFolder := DEF_SAVE_FOLDER;
  FShowBanner := DEF_SHOW_BANNER;
  FCacheEnabled := DEF_CACHE_ENABLED;
  FCacheFolder := DEF_CACHE_FOLDER;
  FCacheMaxSizeMB := DEF_CACHE_MAX_SIZE_MB;
  FQVDisableNavigation := DEF_QV_DISABLE_NAV;
  FQVHideToolbar := DEF_QV_HIDE_TOOLBAR;
  FQVHideStatusBar := DEF_QV_HIDE_STATUSBAR;
end;

procedure TPluginSettings.Load;
var
  Ini: TIniFile;
begin
  ResetDefaults;
  if not FileExists(FIniPath) then
    Exit;

  Ini := TIniFile.Create(FIniPath);
  try
    FFFmpegMode := StrToFFmpegMode(Ini.ReadString('ffmpeg', 'Mode', ''));
    FFFmpegExePath := Ini.ReadString('ffmpeg', 'ExePath', DEF_FFMPEG_EXE_PATH);
    FFFmpegAutoDownloaded := Ini.ReadBool('ffmpeg', 'AutoDownloaded', DEF_FFMPEG_AUTO_DL);

    FFramesCount := EnsureRange(Ini.ReadInteger('extraction', 'FramesCount',
      DEF_FRAMES_COUNT), MIN_FRAMES_COUNT, MAX_FRAMES_COUNT);
    FSkipEdgesPercent := EnsureRange(Ini.ReadInteger('extraction', 'SkipEdges',
      DEF_SKIP_EDGES), MIN_SKIP_EDGES, MAX_SKIP_EDGES);
    FMaxWorkers := EnsureRange(Ini.ReadInteger('extraction', 'MaxWorkers',
      DEF_MAX_WORKERS), MIN_MAX_WORKERS, MAX_MAX_WORKERS);
    FMaxThreads := EnsureRange(Ini.ReadInteger('extraction', 'MaxThreads',
      DEF_MAX_THREADS), MIN_MAX_THREADS, MAX_MAX_THREADS);
    FUseBmpPipe := Ini.ReadBool('extraction', 'UseBmpPipe', DEF_USE_BMP_PIPE);
    FHwAccel := Ini.ReadBool('extraction', 'HwAccel', DEF_HW_ACCEL);
    FUseKeyframes := Ini.ReadBool('extraction', 'UseKeyframes', DEF_USE_KEYFRAMES);
    FScaledExtraction := Ini.ReadBool('extraction', 'ScaledExtraction', DEF_SCALED_EXTRACTION);
    FMinFrameSide := EnsureRange(Ini.ReadInteger('extraction', 'MinFrameSide',
      DEF_MIN_FRAME_SIDE), MIN_FRAME_SIDE, MAX_FRAME_SIDE);
    FMaxFrameSide := EnsureRange(Ini.ReadInteger('extraction', 'MaxFrameSide',
      DEF_MAX_FRAME_SIDE), MIN_FRAME_SIDE, MAX_FRAME_SIDE);

    FViewMode := StrToViewMode(Ini.ReadString('view', 'Mode', ''));
    for var VM := Low(TViewMode) to High(TViewMode) do
      FModeZoom[VM] := StrToZoomMode(Ini.ReadString(
        'view.' + ViewModeToStr(VM), 'ZoomMode', ''));
    FBackground := HexToColor(Ini.ReadString('view', 'Background', ''), DEF_BACKGROUND);
    FShowTimecode := Ini.ReadBool('view', 'ShowTimecode', DEF_SHOW_TIMECODE);
    FShowToolbar := Ini.ReadBool('view', 'ShowToolbar', DEF_SHOW_TOOLBAR);
    FShowStatusBar := Ini.ReadBool('view', 'ShowStatusBar', DEF_SHOW_STATUS_BAR);
    HexToColorAlpha(Ini.ReadString('view', 'TimecodeBackground', ''),
      DEF_TC_BACK_COLOR, DEF_TC_BACK_ALPHA, FTimecodeBackColor, FTimecodeBackAlpha);
    FTimestampFontName := Ini.ReadString('view', 'TimestampFont', DEF_TIMESTAMP_FONT);
    if FTimestampFontName.Trim = '' then
      FTimestampFontName := DEF_TIMESTAMP_FONT;
    FTimestampFontSize := EnsureRange(Ini.ReadInteger('view', 'TimestampFontSize',
      DEF_TIMESTAMP_FONT_SIZE), MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);

    FExtensionList := Ini.ReadString('extensions', 'List', DEF_EXTENSION_LIST);
    if FExtensionList.Trim = '' then
      FExtensionList := DEF_EXTENSION_LIST;

    FSaveFormat := StrToSaveFormat(Ini.ReadString('save', 'Format', ''));
    FJpegQuality := EnsureRange(Ini.ReadInteger('save', 'JpegQuality',
      DEF_JPEG_QUALITY), MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
    FPngCompression := EnsureRange(Ini.ReadInteger('save', 'PngCompression',
      DEF_PNG_COMPRESSION), MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);
    FSaveFolder := Ini.ReadString('save', 'SaveFolder', DEF_SAVE_FOLDER);
    FShowBanner := Ini.ReadBool('save', 'ShowBanner', DEF_SHOW_BANNER);

    FCacheEnabled := Ini.ReadBool('cache', 'Enabled', DEF_CACHE_ENABLED);
    FCacheFolder := Ini.ReadString('cache', 'Folder', DEF_CACHE_FOLDER);
    FCacheMaxSizeMB := EnsureRange(Ini.ReadInteger('cache', 'MaxSizeMB', DEF_CACHE_MAX_SIZE_MB), 10, 10000);

    FQVDisableNavigation := Ini.ReadBool('quickview', 'DisableNavigation', DEF_QV_DISABLE_NAV);
    FQVHideToolbar := Ini.ReadBool('quickview', 'HideToolbar', DEF_QV_HIDE_TOOLBAR);
    FQVHideStatusBar := Ini.ReadBool('quickview', 'HideStatusBar', DEF_QV_HIDE_STATUSBAR);
  finally
    Ini.Free;
  end;
end;

procedure TPluginSettings.Save;
var
  Ini: TIniFile;
begin
  if FIniPath = '' then
    Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    Ini.WriteString('ffmpeg', 'Mode', FFmpegModeToStr(FFFmpegMode));
    Ini.WriteString('ffmpeg', 'ExePath', FFFmpegExePath);
    Ini.WriteBool('ffmpeg', 'AutoDownloaded', FFFmpegAutoDownloaded);

    Ini.WriteInteger('extraction', 'FramesCount', FFramesCount);
    Ini.WriteInteger('extraction', 'SkipEdges', FSkipEdgesPercent);
    Ini.WriteInteger('extraction', 'MaxWorkers', FMaxWorkers);
    Ini.WriteInteger('extraction', 'MaxThreads', FMaxThreads);
    Ini.WriteBool('extraction', 'UseBmpPipe', FUseBmpPipe);
    Ini.WriteBool('extraction', 'HwAccel', FHwAccel);
    Ini.WriteBool('extraction', 'UseKeyframes', FUseKeyframes);
    Ini.WriteBool('extraction', 'ScaledExtraction', FScaledExtraction);
    Ini.WriteInteger('extraction', 'MinFrameSide', FMinFrameSide);
    Ini.WriteInteger('extraction', 'MaxFrameSide', FMaxFrameSide);

    Ini.WriteString('view', 'Mode', ViewModeToStr(FViewMode));
    for var VM := Low(TViewMode) to High(TViewMode) do
      Ini.WriteString('view.' + ViewModeToStr(VM), 'ZoomMode',
        ZoomModeToStr(FModeZoom[VM]));
    Ini.WriteString('view', 'Background', ColorToHex(FBackground));
    Ini.WriteBool('view', 'ShowTimecode', FShowTimecode);
    Ini.WriteBool('view', 'ShowToolbar', FShowToolbar);
    Ini.WriteBool('view', 'ShowStatusBar', FShowStatusBar);
    Ini.WriteString('view', 'TimecodeBackground',
      ColorAlphaToHex(FTimecodeBackColor, FTimecodeBackAlpha));
    Ini.WriteString('view', 'TimestampFont', FTimestampFontName);
    Ini.WriteInteger('view', 'TimestampFontSize', FTimestampFontSize);

    Ini.WriteString('extensions', 'List', FExtensionList);

    Ini.WriteString('save', 'Format', SaveFormatToStr(FSaveFormat));
    Ini.WriteInteger('save', 'JpegQuality', FJpegQuality);
    Ini.WriteInteger('save', 'PngCompression', FPngCompression);
    Ini.WriteString('save', 'SaveFolder', FSaveFolder);
    Ini.WriteBool('save', 'ShowBanner', FShowBanner);

    Ini.WriteBool('cache', 'Enabled', FCacheEnabled);
    Ini.WriteString('cache', 'Folder', FCacheFolder);
    Ini.WriteInteger('cache', 'MaxSizeMB', FCacheMaxSizeMB);

    Ini.WriteBool('quickview', 'DisableNavigation', FQVDisableNavigation);
    Ini.WriteBool('quickview', 'HideToolbar', FQVHideToolbar);
    Ini.WriteBool('quickview', 'HideStatusBar', FQVHideStatusBar);
  finally
    Ini.Free;
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
    fmExe: Result := 'exe';
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
    vmScroll:    Result := 'scroll';
    vmSmartGrid: Result := 'smartgrid';
    vmFilmstrip: Result := 'filmstrip';
    vmSingle:    Result := 'single';
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
    zmFitIfLarger: Result := 'fitlarger';
    zmActual: Result := 'actual';
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
    sfJPEG: Result := 'JPEG';
  else
    Result := 'PNG';
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
