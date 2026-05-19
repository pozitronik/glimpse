{WCX plugin settings backed by an INI file.
 Separate from WLX settings to allow independent configuration.}
unit uWcxSettings;

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  uBitmapSaver, uTypes, uDefaults, uSettingsGroups, uUnicodeIniFile;

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
    {Load's three composable stages, public to allow per-stage tests.
     Production callers should use Load (which orchestrates all three
     after ResetDefaults). The stages are independent enough to be
     exercised in isolation:
       LoadFromIni     reads every simple key from AIni into the matching
                       field with no transformation beyond a Byte narrowing
                       where the target field's storage is narrower than the
                       INI int (FBackgroundAlpha).
       ParseLegacyFormats reads the string-encoded keys that need
                       interpretation (Mode bitmask via ParseModeKey,
                       Format JPEG/PNG enum, Background hex colour).
       ApplyClamps     enforces the documented min/max ranges on fields
                       whose values are bounded; safe to call repeatedly.}
    procedure LoadFromIni(AIni: TUnicodeIniFile);
    procedure ParseLegacyFormats(AIni: TUnicodeIniFile);
    procedure ApplyClamps;

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
    {Read-only view of the whole extraction group. Surfaced so callers
     can use TExtractionSettingsGroup.ToExtractionOptions instead of
     rebuilding a TExtractionOptions field-by-field at every export
     boundary.}
    property Extraction: TExtractionSettingsGroup read FExtraction;
    {Read-only views of the timestamp + banner groups so callers can use
     TTimestampStyle.FromSettings / TBannerStyle.FromSettings instead of
     rebuilding the style records field-by-field.}
    property Timestamp: TTimestampSettingsGroup read FTimestamp;
    property Banner: TBannerSettingsGroup read FBanner;
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
    {Bundled save knobs for one SaveBitmapToFile / IBitmapSaverRouter.Save
     call. Built on demand; consumers pass it instead of three separate
     property reads. Cheap (a record copy of three small fields).}
    function SaveOptions: TSaveOptions;
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

function TWcxSettings.SaveOptions: TSaveOptions;
begin
  Result.Format := FSaveFormat;
  Result.JpegQuality := FJpegQuality;
  Result.PngCompression := FPngCompression;
end;

procedure TWcxSettings.Load;
var
  Ini: TUnicodeIniFile;
begin
  {Reset-then-read mirrors TPluginSettings so a second Load on the same
   instance starts from a known baseline instead of inheriting whichever
   values the previous Load produced.}
  ResetDefaults;
  if not FileExists(FIniPath) then
    Exit;
  Ini := TUnicodeIniFile.Create(FIniPath);
  try
    LoadFromIni(Ini);
    ParseLegacyFormats(Ini);
    ApplyClamps;
  finally
    Ini.Free;
  end;
end;

procedure TWcxSettings.LoadFromIni(AIni: TUnicodeIniFile);
begin
  {Pass the current field value as the INI fallback so the post-Reset
   default propagates through one source of truth (ResetDefaults). The
   LoadFrom helpers on the group records already follow this pattern;
   the inline reads here match. Unclamped reads — ApplyClamps enforces
   the documented bounds in a separate pass, exposing the clamp logic
   to its own per-step tests.}
  FFFmpegExePath := AIni.ReadString('ffmpeg', 'ExePath', FFFmpegExePath);
  FExtraction.LoadFrom(AIni, 'extraction');
  FRandomExtraction := AIni.ReadBool('extraction', 'RandomExtraction', FRandomExtraction);
  FRandomPercent := AIni.ReadInteger('extraction', 'RandomPercent', FRandomPercent);
  FJpegQuality := AIni.ReadInteger('output', 'JpegQuality', FJpegQuality);
  FPngCompression := AIni.ReadInteger('output', 'PngCompression', FPngCompression);
  {BackgroundAlpha is a Byte field; the EnsureRange + Byte cast happens
   inline because narrowing a wider INI int into a Byte is intrinsic
   to the read (any out-of-range INI value would be truncated by the
   cast alone — EnsureRange is what makes the truncation meaningful).
   This stays in LoadFromIni rather than ApplyClamps because the
   field's storage type, not a logical range limit, drives it.}
  FBackgroundAlpha := Byte(EnsureRange(AIni.ReadInteger('output', 'BackgroundAlpha', FBackgroundAlpha), MIN_BACKGROUND_ALPHA, MAX_BACKGROUND_ALPHA));
  FCombinedColumns := AIni.ReadInteger('combined', 'Columns', FCombinedColumns);
  FCellGap := AIni.ReadInteger('combined', 'CellGap', FCellGap);
  FCombinedBorder := AIni.ReadInteger('combined', 'CombinedBorder', FCombinedBorder);
  FTimestamp.LoadFrom(AIni, 'combined', 'ShowTimestamp');
  FBanner.LoadFrom(AIni, 'combined');
  FShowFileSizes := AIni.ReadBool('output', 'ShowFileSizes', FShowFileSizes);
  FFrameMaxSide := AIni.ReadInteger('output', 'FrameMaxSide', FFrameMaxSide);
  FCombinedMaxSide := AIni.ReadInteger('combined', 'CombinedMaxSide', FCombinedMaxSide);
  FDebugLogEnabled := AIni.ReadBool('debug', 'LogEnabled', FDebugLogEnabled);
end;

procedure TWcxSettings.ParseLegacyFormats(AIni: TUnicodeIniFile);
begin
  {Mode is a bitmask of MODE_FRAMES / MODE_COMBINED / MODE_PRESETS.
   Numeric values parse directly; the legacy string forms "separate"
   and "combined" map to the single-bit equivalent so an INI written
   by an older Glimpse build still loads. String-parsed enums (Mode,
   Format) and the hex-encoded Background keep literal/constant
   fallbacks because converting the current field back to a string
   just to feed it as a default would add reverse-conversion noise
   for no benefit.}
  FMode := ParseModeKey(AIni.ReadString('output', 'Mode', ''), WCX_DEF_MODE);
  if SameText(AIni.ReadString('output', 'Format', 'PNG'), 'JPEG') then
    FSaveFormat := sfJPEG
  else
    FSaveFormat := sfPNG;
  FBackground := HexToColor(AIni.ReadString('combined', 'Background', ''), FBackground);
end;

procedure TWcxSettings.ApplyClamps;
begin
  FRandomPercent := EnsureRange(FRandomPercent, MIN_RANDOM_PERCENT, MAX_RANDOM_PERCENT);
  FJpegQuality := EnsureRange(FJpegQuality, MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
  FPngCompression := EnsureRange(FPngCompression, MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);
  FCombinedColumns := EnsureRange(FCombinedColumns, 0, 20);
  FCellGap := Max(FCellGap, MIN_CELL_GAP);
  FCombinedBorder := Max(FCombinedBorder, MIN_COMBINED_BORDER);
  FFrameMaxSide := EnsureRange(FFrameMaxSide, WCX_MIN_OUTPUT_SIDE, WCX_MAX_OUTPUT_SIDE);
  FCombinedMaxSide := EnsureRange(FCombinedMaxSide, WCX_MIN_OUTPUT_SIDE, WCX_MAX_OUTPUT_SIDE);
end;

procedure TWcxSettings.Save;
var
  Ini: TUnicodeIniFile;
begin
  if FIniPath = '' then
    Exit;
  Ini := TUnicodeIniFile.Create(FIniPath);
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
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
