{WCX plugin settings backed by an INI file.
 Separate from WLX settings to allow independent configuration.}
unit uWcxSettings;

interface

uses
  System.SysUtils, System.IniFiles, System.Math, System.UITypes,
  uBitmapSaver, uTypes, uDefaults, uSettingsGroups;

const
  {Bit values composed into the Mode bitmask. Each independent toggle
   contributes one bit, so any combination of the three listing sources
   can be enabled simultaneously.}
  MODE_FRAMES   = 1;
  MODE_COMBINED = 2;
  MODE_PRESETS  = 4;

type
  TWcxSettings = class
  strict private
    FIniPath: string;
    {[ffmpeg]}
    FFFmpegExePath: string;
    {[extraction] — shared group record (see uSettingsGroups)}
    FExtraction: TExtractionSettingsGroup;
    {Frame-position randomness. WCX has no live-view shuffle hotkey, so
     this only governs whether the on-demand archive render starts from
     deterministic midpoints (RandomExtraction = False) or randomised
     per-slice picks (True). No CacheRandomFrames toggle: WCX has no
     frame cache so the option would be a no-op.}
    FRandomExtraction: Boolean;
    FRandomPercent: Integer;
    {[output] — Mode is a bitmask of MODE_FRAMES / MODE_COMBINED /
     MODE_PRESETS. The three Show* properties flip individual bits so
     callers can manipulate one source at a time without touching the
     others.}
    FMode: Integer;
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    FBackgroundAlpha: Byte;
    {[combined]}
    FCombinedColumns: Integer;
    FBackground: TColor;
    FCellGap: Integer;
    FCombinedBorder: Integer;
    {[combined] — timestamp overlay group shared with WLX}
    FTimestamp: TTimestampSettingsGroup;
    {[combined] — banner group shared with WLX}
    FBanner: TBannerSettingsGroup;
    {[output]}
    FShowFileSizes: Boolean;
    {Output size cap in pixels, 0 = no limit. The cap applies to whichever
     side is longer, so it works regardless of orientation. The frame cap
     drives ffmpeg's scale filter for separate-mode extraction; the combined
     cap triggers a post-render HALFTONE downscale of the assembled grid.}
    FFrameMaxSide: Integer;
    FCombinedMaxSide: Integer;
    {Hidden diagnostic toggle, no UI control. When True, uWcxExports points
     GDebugLogPath at "<dll>.log" so the WcxLog calls scattered through the
     plugin start writing to a file next to the DLL. Off by default so a
     normal session leaves no trace; users opt in by hand-editing the INI
     when they need to diagnose something.}
    FDebugLogEnabled: Boolean;

  private
    function GetShowFrames: Boolean;
    procedure SetShowFrames(AValue: Boolean);
    function GetShowCombined: Boolean;
    procedure SetShowCombined(AValue: Boolean);
    function GetShowPresets: Boolean;
    procedure SetShowPresets(AValue: Boolean);
  public
    constructor Create(const AIniPath: string);
    procedure Load;
    procedure Save;
    {Resets every field to its documented default. Called from Create and at
     the top of Load so a fresh Load always starts from a known baseline,
     matching TPluginSettings behaviour.}
    procedure ResetDefaults;

    property IniPath: string read FIniPath;
    property FFmpegExePath: string read FFFmpegExePath write FFFmpegExePath;
    property FramesCount: Integer read FExtraction.FramesCount write FExtraction.FramesCount;
    property SkipEdgesPercent: Integer read FExtraction.SkipEdgesPercent write FExtraction.SkipEdgesPercent;
    property MaxWorkers: Integer read FExtraction.MaxWorkers write FExtraction.MaxWorkers;
    property MaxThreads: Integer read FExtraction.MaxThreads write FExtraction.MaxThreads;
    property UseBmpPipe: Boolean read FExtraction.UseBmpPipe write FExtraction.UseBmpPipe;
    property HwAccel: Boolean read FExtraction.HwAccel write FExtraction.HwAccel;
    property UseKeyframes: Boolean read FExtraction.UseKeyframes write FExtraction.UseKeyframes;
    property RespectAnamorphic: Boolean read FExtraction.RespectAnamorphic write FExtraction.RespectAnamorphic;
    property RandomExtraction: Boolean read FRandomExtraction write FRandomExtraction;
    property RandomPercent: Integer read FRandomPercent write FRandomPercent;
    {Mode bitmask: bitwise OR of MODE_FRAMES, MODE_COMBINED, MODE_PRESETS.
     0 means an empty archive listing — valid but unusual. The Show*
     properties below let callers manipulate one bit at a time without
     touching the others, which matters for the dialog's combo box that
     only knows about frames-vs-combined.}
    property Mode: Integer read FMode write FMode;
    property ShowFrames: Boolean read GetShowFrames write SetShowFrames;
    property ShowCombined: Boolean read GetShowCombined write SetShowCombined;
    property ShowPresets: Boolean read GetShowPresets write SetShowPresets;
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property BackgroundAlpha: Byte read FBackgroundAlpha write FBackgroundAlpha;
    property CombinedColumns: Integer read FCombinedColumns write FCombinedColumns;
    {ShowTimestamp is the WCX name for the timestamp group's Show toggle;
     WLX exposes the same field as ShowTimecode.}
    property ShowTimestamp: Boolean read FTimestamp.Show write FTimestamp.Show;
    property Background: TColor read FBackground write FBackground;
    property CellGap: Integer read FCellGap write FCellGap;
    property CombinedBorder: Integer read FCombinedBorder write FCombinedBorder;
    property TimestampCorner: TTimestampCorner read FTimestamp.Corner write FTimestamp.Corner;
    property TimecodeBackColor: TColor read FTimestamp.BackColor write FTimestamp.BackColor;
    property TimecodeBackAlpha: Byte read FTimestamp.BackAlpha write FTimestamp.BackAlpha;
    property TimestampTextColor: TColor read FTimestamp.TextColor write FTimestamp.TextColor;
    property TimestampTextAlpha: Byte read FTimestamp.TextAlpha write FTimestamp.TextAlpha;
    property TimestampFontName: string read FTimestamp.FontName write FTimestamp.FontName;
    property TimestampFontSize: Integer read FTimestamp.FontSize write FTimestamp.FontSize;
    property ShowBanner: Boolean read FBanner.Show write FBanner.Show;
    property BannerBackground: TColor read FBanner.Background write FBanner.Background;
    property BannerTextColor: TColor read FBanner.TextColor write FBanner.TextColor;
    property BannerFontName: string read FBanner.FontName write FBanner.FontName;
    property BannerFontSize: Integer read FBanner.FontSize write FBanner.FontSize;
    property BannerFontAutoSize: Boolean read FBanner.AutoSize write FBanner.AutoSize;
    property BannerPosition: TBannerPosition read FBanner.Position write FBanner.Position;
    property ShowFileSizes: Boolean read FShowFileSizes write FShowFileSizes;
    property FrameMaxSide: Integer read FFrameMaxSide write FFrameMaxSide;
    property CombinedMaxSide: Integer read FCombinedMaxSide write FCombinedMaxSide;
    property DebugLogEnabled: Boolean read FDebugLogEnabled write FDebugLogEnabled;
  end;

const
  {WCX-specific defaults (shared defaults are in uDefaults)}
  WCX_DEF_MODE = MODE_FRAMES;
  WCX_DEF_COMBINED_COLS = 0; {0 = auto}
  WCX_DEF_SHOW_TIMESTAMP = True;
  WCX_DEF_BACKGROUND = TColor($001E1E1E);
  WCX_DEF_CELL_GAP = 2;
  WCX_DEF_TIMESTAMP_FONT = 'Consolas';
  WCX_DEF_TIMESTAMP_FONT_SIZE = 9;
  WCX_DEF_SHOW_BANNER = False;
  WCX_DEF_SHOW_FILE_SIZES = False;
  WCX_DEF_FRAME_MAX_SIDE = 0; {0 = no limit}
  WCX_DEF_COMBINED_MAX_SIDE = 0;
  WCX_MIN_OUTPUT_SIDE = 0;
  WCX_MAX_OUTPUT_SIDE = MAX_FRAME_SIDE; {8K}
  WCX_DEF_DEBUG_LOG_ENABLED = False;

implementation

uses
  uPathExpand, uColorConv;

{Parses the [output] Mode= INI value across all supported forms:
   - Numeric (e.g. "5") → returned as-is when in valid bitmask range
   - Legacy string "separate" → MODE_FRAMES
   - Legacy string "combined" → MODE_COMBINED
   - Anything else (empty, garbage) → ADefault
 Range check accepts 0..7 (the only valid bit combinations); higher
 values fall back to ADefault since they would expose unsupported bits.}
function ParseModeKey(const ARawValue: string; ADefault: Integer): Integer;
var
  AsInt: Integer;
  Trimmed: string;
begin
  Trimmed := Trim(ARawValue);
  if Trimmed = '' then
    Exit(ADefault);
  if TryStrToInt(Trimmed, AsInt) then
  begin
    if (AsInt >= 0) and (AsInt <= MODE_FRAMES or MODE_COMBINED or MODE_PRESETS) then
      Exit(AsInt)
    else
      Exit(ADefault);
  end;
  if SameText(Trimmed, 'separate') then
    Exit(MODE_FRAMES);
  if SameText(Trimmed, 'combined') then
    Exit(MODE_COMBINED);
  Result := ADefault;
end;

{TWcxSettings}

constructor TWcxSettings.Create(const AIniPath: string);
begin
  inherited Create;
  FIniPath := AIniPath;
  ResetDefaults;
end;

procedure TWcxSettings.ResetDefaults;
begin
  FFFmpegExePath := '';
  FExtraction := TExtractionSettingsGroup.Defaults;
  FRandomExtraction := DEF_RANDOM_EXTRACTION;
  FRandomPercent := DEF_RANDOM_PERCENT;
  FMode := WCX_DEF_MODE;
  FSaveFormat := DEF_SAVE_FORMAT;
  FJpegQuality := DEF_JPEG_QUALITY;
  FPngCompression := DEF_PNG_COMPRESSION;
  FBackgroundAlpha := DEF_BACKGROUND_ALPHA;
  FCombinedColumns := WCX_DEF_COMBINED_COLS;
  FBackground := WCX_DEF_BACKGROUND;
  FCellGap := WCX_DEF_CELL_GAP;
  FCombinedBorder := DEF_COMBINED_BORDER;
  FTimestamp := TTimestampSettingsGroup.Defaults;
  {WCX historically uses different timestamp font defaults than WLX. Apply
   the overrides after the group seed so the shared defaults still travel.}
  FTimestamp.Show := WCX_DEF_SHOW_TIMESTAMP;
  FTimestamp.FontName := WCX_DEF_TIMESTAMP_FONT;
  FTimestamp.FontSize := WCX_DEF_TIMESTAMP_FONT_SIZE;
  FBanner := TBannerSettingsGroup.Defaults;
  FBanner.Show := WCX_DEF_SHOW_BANNER;
  FShowFileSizes := WCX_DEF_SHOW_FILE_SIZES;
  FFrameMaxSide := WCX_DEF_FRAME_MAX_SIDE;
  FCombinedMaxSide := WCX_DEF_COMBINED_MAX_SIDE;
  FDebugLogEnabled := WCX_DEF_DEBUG_LOG_ENABLED;
end;

function TWcxSettings.GetShowFrames: Boolean;
begin
  Result := (FMode and MODE_FRAMES) <> 0;
end;

procedure TWcxSettings.SetShowFrames(AValue: Boolean);
begin
  if AValue then
    FMode := FMode or MODE_FRAMES
  else
    FMode := FMode and not MODE_FRAMES;
end;

function TWcxSettings.GetShowCombined: Boolean;
begin
  Result := (FMode and MODE_COMBINED) <> 0;
end;

procedure TWcxSettings.SetShowCombined(AValue: Boolean);
begin
  if AValue then
    FMode := FMode or MODE_COMBINED
  else
    FMode := FMode and not MODE_COMBINED;
end;

function TWcxSettings.GetShowPresets: Boolean;
begin
  Result := (FMode and MODE_PRESETS) <> 0;
end;

procedure TWcxSettings.SetShowPresets(AValue: Boolean);
begin
  if AValue then
    FMode := FMode or MODE_PRESETS
  else
    FMode := FMode and not MODE_PRESETS;
end;

procedure TWcxSettings.Load;
var
  Ini: TIniFile;
begin
  {Reset-then-read mirrors TPluginSettings so a second Load on the same
   instance starts from a known baseline instead of inheriting whichever
   values the previous Load produced.}
  ResetDefaults;
  if not FileExists(FIniPath) then
    Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    {Pass the current field value as the INI fallback so the post-Reset
     default propagates through one source of truth (ResetDefaults). The
     LoadFrom helpers on the group records already follow this pattern;
     the inline reads now match. String-parsed enums (Mode, Format) and
     the hex-encoded Background are kept on literal/constant fallbacks
     because converting the current field back to a string just to feed
     it as a default would add reverse-conversion noise for no benefit.}
    FFFmpegExePath := Ini.ReadString('ffmpeg', 'ExePath', FFFmpegExePath);
    FExtraction.LoadFrom(Ini, 'extraction');
    FRandomExtraction := Ini.ReadBool('extraction', 'RandomExtraction', FRandomExtraction);
    FRandomPercent := EnsureRange(Ini.ReadInteger('extraction', 'RandomPercent', FRandomPercent), MIN_RANDOM_PERCENT, MAX_RANDOM_PERCENT);

    {Mode is a bitmask of MODE_FRAMES / MODE_COMBINED / MODE_PRESETS.
     Numeric values parse directly; the legacy string forms "separate"
     and "combined" map to the single-bit equivalent so an INI written
     by an older Glimpse build still loads.}
    FMode := ParseModeKey(Ini.ReadString('output', 'Mode', ''), WCX_DEF_MODE);

    if SameText(Ini.ReadString('output', 'Format', 'PNG'), 'JPEG') then
      FSaveFormat := sfJPEG
    else
      FSaveFormat := sfPNG;
    FJpegQuality := EnsureRange(Ini.ReadInteger('output', 'JpegQuality', FJpegQuality), MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
    FPngCompression := EnsureRange(Ini.ReadInteger('output', 'PngCompression', FPngCompression), MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);
    {Explicit Byte cast: EnsureRange returns Integer, target is Byte; the
     range is [0, 255] so the narrowing is always safe but the cast
     documents intent and survives stricter compiler options.}
    FBackgroundAlpha := Byte(EnsureRange(Ini.ReadInteger('output', 'BackgroundAlpha', FBackgroundAlpha), MIN_BACKGROUND_ALPHA, MAX_BACKGROUND_ALPHA));

    FCombinedColumns := EnsureRange(Ini.ReadInteger('combined', 'Columns', FCombinedColumns), 0, 20);
    FBackground := HexToColor(Ini.ReadString('combined', 'Background', ''), FBackground);
    FCellGap := Max(Ini.ReadInteger('combined', 'CellGap', FCellGap), MIN_CELL_GAP);
    FCombinedBorder := Max(Ini.ReadInteger('combined', 'CombinedBorder', FCombinedBorder), MIN_COMBINED_BORDER);
    FTimestamp.LoadFrom(Ini, 'combined', 'ShowTimestamp');
    FBanner.LoadFrom(Ini, 'combined');

    FShowFileSizes := Ini.ReadBool('output', 'ShowFileSizes', FShowFileSizes);

    FFrameMaxSide := EnsureRange(Ini.ReadInteger('output', 'FrameMaxSide', FFrameMaxSide), WCX_MIN_OUTPUT_SIDE, WCX_MAX_OUTPUT_SIDE);
    FCombinedMaxSide := EnsureRange(Ini.ReadInteger('combined', 'CombinedMaxSide', FCombinedMaxSide), WCX_MIN_OUTPUT_SIDE, WCX_MAX_OUTPUT_SIDE);

    FDebugLogEnabled := Ini.ReadBool('debug', 'LogEnabled', FDebugLogEnabled);
  finally
    Ini.Free;
  end;
end;

procedure TWcxSettings.Save;
var
  Ini: TIniFile;
begin
  if FIniPath = '' then
    Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    Ini.WriteString('ffmpeg', 'ExePath', FFFmpegExePath);
    FExtraction.SaveTo(Ini, 'extraction');
    Ini.WriteBool('extraction', 'RandomExtraction', FRandomExtraction);
    Ini.WriteInteger('extraction', 'RandomPercent', FRandomPercent);

    Ini.WriteInteger('output', 'Mode', FMode);
    if FSaveFormat = sfJPEG then
      Ini.WriteString('output', 'Format', 'JPEG')
    else
      Ini.WriteString('output', 'Format', 'PNG');
    Ini.WriteInteger('output', 'JpegQuality', FJpegQuality);
    Ini.WriteInteger('output', 'PngCompression', FPngCompression);
    Ini.WriteInteger('output', 'BackgroundAlpha', FBackgroundAlpha);

    Ini.WriteInteger('combined', 'Columns', FCombinedColumns);
    Ini.WriteString('combined', 'Background', ColorToHex(FBackground));
    Ini.WriteInteger('combined', 'CellGap', FCellGap);
    Ini.WriteInteger('combined', 'CombinedBorder', FCombinedBorder);
    FTimestamp.SaveTo(Ini, 'combined', 'ShowTimestamp');
    FBanner.SaveTo(Ini, 'combined');

    Ini.WriteBool('output', 'ShowFileSizes', FShowFileSizes);

    Ini.WriteInteger('output', 'FrameMaxSide', FFrameMaxSide);
    Ini.WriteInteger('combined', 'CombinedMaxSide', FCombinedMaxSide);

    Ini.WriteBool('debug', 'LogEnabled', FDebugLogEnabled);
  finally
    Ini.Free;
  end;
end;

end.
