{WCX plugin settings backed by an INI file. Separate from WLX so each
 plugin can be configured independently.}
unit WcxSettings;

interface

uses
  System.SysUtils, System.Math, System.UITypes,
  BitmapSaver, Types, Defaults, SettingsGroups, UnicodeIniFile;

const
  {Mode bitmask values; any combination of the three sources is valid.}
  MODE_FRAMES   = 1;
  MODE_COMBINED = 2;
  MODE_PRESETS  = 4;

type
  TWcxSettings = class
  strict private
    FIniPath: string;
    FFFmpegExePath: string;
    FExtraction: TExtractionSettingsGroup;
    FRandomExtraction: Boolean;
    FRandomPercent: Integer;
    FMode: Integer;
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    FBackgroundAlpha: Byte;
    FCombinedColumns: Integer;
    FBackground: TColor;
    FCellGap: Integer;
    FCombinedBorder: Integer;
    FTimestamp: TTimestampSettingsGroup;
    FBanner: TBannerSettingsGroup;
    FShowFileSizes: Boolean;
    {0 = no limit; applies to the longer side. Frame cap drives ffmpeg's
     scale filter; combined cap triggers a post-render HALFTONE downscale.}
    FFrameMaxSide: Integer;
    FCombinedMaxSide: Integer;
    {Hidden toggle: enable by hand-editing [debug] LogEnabled in the INI.
     Off by default so a normal session leaves no trace.}
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
    procedure ResetDefaults;
    {Load's three composable stages, public for per-stage tests. Use
     Load in production (which orchestrates all three after ResetDefaults).}
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
    {Surfaced so callers can use TExtractionSettingsGroup.ToExtractionOptions
     instead of rebuilding a TExtractionOptions field-by-field.}
    property Extraction: TExtractionSettingsGroup read FExtraction;
    property Timestamp: TTimestampSettingsGroup read FTimestamp;
    property Banner: TBannerSettingsGroup read FBanner;
    property RandomExtraction: Boolean read FRandomExtraction write FRandomExtraction;
    property RandomPercent: Integer read FRandomPercent write FRandomPercent;
    property Mode: Integer read FMode write FMode;
    property ShowFrames: Boolean read GetShowFrames write SetShowFrames;
    property ShowCombined: Boolean read GetShowCombined write SetShowCombined;
    property ShowPresets: Boolean read GetShowPresets write SetShowPresets;
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    function SaveOptions: TSaveOptions;
    property BackgroundAlpha: Byte read FBackgroundAlpha write FBackgroundAlpha;
    property CombinedColumns: Integer read FCombinedColumns write FCombinedColumns;
    {WLX exposes the same underlying field as ShowTimecode.}
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
  PathExpand, ColorConv;

{Numeric, or the legacy strings "separate" / "combined". Unrecognised
 input falls back to ADefault. Range 0..7 enforced.}
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
  {WCX overrides applied after the shared seed so other defaults travel.}
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
  {Reset-then-read so a second Load starts from a known baseline.}
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
  {Pass current field as INI fallback so the post-Reset default flows
   through one source of truth. Unclamped — ApplyClamps runs separately.}
  FFFmpegExePath := AIni.ReadString('ffmpeg', 'ExePath', FFFmpegExePath);
  FExtraction.LoadFrom(AIni, 'extraction');
  FRandomExtraction := AIni.ReadBool('extraction', 'RandomExtraction', FRandomExtraction);
  FRandomPercent := AIni.ReadInteger('extraction', 'RandomPercent', FRandomPercent);
  FJpegQuality := AIni.ReadInteger('output', 'JpegQuality', FJpegQuality);
  FPngCompression := AIni.ReadInteger('output', 'PngCompression', FPngCompression);
  {EnsureRange+Byte cast here (not in ApplyClamps) because the field's
   storage type, not a logical range, drives the narrowing.}
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
  {Literal/constant fallbacks here (not the current field value)
   because converting an enum/hex back to string just to feed it as a
   default would add reverse-conversion noise for no benefit.}
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
