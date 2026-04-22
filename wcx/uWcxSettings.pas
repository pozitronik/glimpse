{WCX plugin settings backed by an INI file.
 Separate from WLX settings to allow independent configuration.}
unit uWcxSettings;

interface

uses
  System.SysUtils, System.IniFiles, System.Math, System.UITypes,
  uBitmapSaver, uTypes, uDefaults;

type
  TWcxOutputMode = (womSeparate, womCombined);

  TWcxSettings = class
  strict private
    FIniPath: string;
    {[ffmpeg]}
    FFFmpegMode: TFFmpegMode;
    FFFmpegExePath: string;
    {[extraction]}
    FFramesCount: Integer;
    FSkipEdgesPercent: Integer;
    FMaxWorkers: Integer;
    FMaxThreads: Integer;
    FUseBmpPipe: Boolean;
    FHwAccel: Boolean;
    FUseKeyframes: Boolean;
    {[output]}
    FOutputMode: TWcxOutputMode;
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    {[combined]}
    FCombinedColumns: Integer;
    FShowTimestamp: Boolean;
    FBackground: TColor;
    FCellGap: Integer;
    FCombinedBorder: Integer;
    FTimestampCorner: TTimestampCorner;
    FTimecodeBackColor: TColor;
    FTimecodeBackAlpha: Byte;
    FTimestampTextColor: TColor;
    FTimestampTextAlpha: Byte;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FShowBanner: Boolean;
    {[output]}
    FShowFileSizes: Boolean;
    {Output size cap in pixels, 0 = no limit. The cap applies to whichever
     side is longer, so it works regardless of orientation. The frame cap
     drives ffmpeg's scale filter for separate-mode extraction; the combined
     cap triggers a post-render HALFTONE downscale of the assembled grid.}
    FFrameMaxSide: Integer;
    FCombinedMaxSide: Integer;

    class function StrToTimestampCorner(const AValue: string): TTimestampCorner; static;
    class function TimestampCornerToStr(ACorner: TTimestampCorner): string; static;
  public
    constructor Create(const AIniPath: string);
    procedure Load;
    procedure Save;

    property IniPath: string read FIniPath;
    property FFmpegMode: TFFmpegMode read FFFmpegMode write FFFmpegMode;
    property FFmpegExePath: string read FFFmpegExePath write FFFmpegExePath;
    property FramesCount: Integer read FFramesCount write FFramesCount;
    property SkipEdgesPercent: Integer read FSkipEdgesPercent write FSkipEdgesPercent;
    property MaxWorkers: Integer read FMaxWorkers write FMaxWorkers;
    property MaxThreads: Integer read FMaxThreads write FMaxThreads;
    property UseBmpPipe: Boolean read FUseBmpPipe write FUseBmpPipe;
    property HwAccel: Boolean read FHwAccel write FHwAccel;
    property UseKeyframes: Boolean read FUseKeyframes write FUseKeyframes;
    property OutputMode: TWcxOutputMode read FOutputMode write FOutputMode;
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property CombinedColumns: Integer read FCombinedColumns write FCombinedColumns;
    property ShowTimestamp: Boolean read FShowTimestamp write FShowTimestamp;
    property Background: TColor read FBackground write FBackground;
    property CellGap: Integer read FCellGap write FCellGap;
    property CombinedBorder: Integer read FCombinedBorder write FCombinedBorder;
    property TimestampCorner: TTimestampCorner read FTimestampCorner write FTimestampCorner;
    property TimecodeBackColor: TColor read FTimecodeBackColor write FTimecodeBackColor;
    property TimecodeBackAlpha: Byte read FTimecodeBackAlpha write FTimecodeBackAlpha;
    property TimestampTextColor: TColor read FTimestampTextColor write FTimestampTextColor;
    property TimestampTextAlpha: Byte read FTimestampTextAlpha write FTimestampTextAlpha;
    property TimestampFontName: string read FTimestampFontName write FTimestampFontName;
    property TimestampFontSize: Integer read FTimestampFontSize write FTimestampFontSize;
    property ShowBanner: Boolean read FShowBanner write FShowBanner;
    property ShowFileSizes: Boolean read FShowFileSizes write FShowFileSizes;
    property FrameMaxSide: Integer read FFrameMaxSide write FFrameMaxSide;
    property CombinedMaxSide: Integer read FCombinedMaxSide write FCombinedMaxSide;
  end;

const
  {WCX-specific defaults (shared defaults are in uDefaults)}
  WCX_DEF_OUTPUT_MODE = womSeparate;
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

implementation

uses
  uPathExpand, uColorConv;

class function TWcxSettings.StrToTimestampCorner(const AValue: string): TTimestampCorner;
begin
  if SameText(AValue, 'none') then
    Result := tcNone
  else if SameText(AValue, 'topleft') then
    Result := tcTopLeft
  else if SameText(AValue, 'topright') then
    Result := tcTopRight
  else if SameText(AValue, 'bottomright') then
    Result := tcBottomRight
  else if SameText(AValue, 'bottomleft') then
    Result := tcBottomLeft
  else
    Result := DEF_TIMESTAMP_CORNER;
end;

class function TWcxSettings.TimestampCornerToStr(ACorner: TTimestampCorner): string;
begin
  case ACorner of
    tcNone:
      Result := 'none';
    tcTopLeft:
      Result := 'topleft';
    tcTopRight:
      Result := 'topright';
    tcBottomRight:
      Result := 'bottomright';
    else
      Result := 'bottomleft';
  end;
end;

{TWcxSettings}

constructor TWcxSettings.Create(const AIniPath: string);
begin
  inherited Create;
  FIniPath := AIniPath;
  FFFmpegMode := fmAuto;
  FFFmpegExePath := '';
  FFramesCount := DEF_FRAMES_COUNT;
  FSkipEdgesPercent := DEF_SKIP_EDGES;
  FMaxWorkers := DEF_MAX_WORKERS;
  FMaxThreads := DEF_MAX_THREADS;
  FUseBmpPipe := DEF_USE_BMP_PIPE;
  FHwAccel := DEF_HW_ACCEL;
  FUseKeyframes := DEF_USE_KEYFRAMES;
  FOutputMode := WCX_DEF_OUTPUT_MODE;
  FSaveFormat := DEF_SAVE_FORMAT;
  FJpegQuality := DEF_JPEG_QUALITY;
  FPngCompression := DEF_PNG_COMPRESSION;
  FCombinedColumns := WCX_DEF_COMBINED_COLS;
  FShowTimestamp := WCX_DEF_SHOW_TIMESTAMP;
  FBackground := WCX_DEF_BACKGROUND;
  FCellGap := WCX_DEF_CELL_GAP;
  FCombinedBorder := DEF_COMBINED_BORDER;
  FTimestampCorner := DEF_TIMESTAMP_CORNER;
  FTimecodeBackColor := DEF_TC_BACK_COLOR;
  FTimecodeBackAlpha := DEF_TC_BACK_ALPHA;
  FTimestampTextColor := DEF_TIMESTAMP_TEXT_COLOR;
  FTimestampTextAlpha := DEF_TIMESTAMP_TEXT_ALPHA;
  FTimestampFontName := WCX_DEF_TIMESTAMP_FONT;
  FTimestampFontSize := WCX_DEF_TIMESTAMP_FONT_SIZE;
  FShowBanner := WCX_DEF_SHOW_BANNER;
  FShowFileSizes := WCX_DEF_SHOW_FILE_SIZES;
  FFrameMaxSide := WCX_DEF_FRAME_MAX_SIDE;
  FCombinedMaxSide := WCX_DEF_COMBINED_MAX_SIDE;
end;

procedure TWcxSettings.Load;
var
  Ini: TIniFile;
begin
  if not FileExists(FIniPath) then
    Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    FFFmpegExePath := Ini.ReadString('ffmpeg', 'ExePath', '');
    FFramesCount := EnsureRange(Ini.ReadInteger('extraction', 'FramesCount', DEF_FRAMES_COUNT), MIN_FRAMES_COUNT, MAX_FRAMES_COUNT);
    FSkipEdgesPercent := EnsureRange(Ini.ReadInteger('extraction', 'SkipEdges', DEF_SKIP_EDGES), MIN_SKIP_EDGES, MAX_SKIP_EDGES);
    FMaxWorkers := EnsureRange(Ini.ReadInteger('extraction', 'MaxWorkers', DEF_MAX_WORKERS), MIN_MAX_WORKERS, MAX_MAX_WORKERS);
    FMaxThreads := EnsureRange(Ini.ReadInteger('extraction', 'MaxThreads', DEF_MAX_THREADS), MIN_MAX_THREADS, MAX_MAX_THREADS);
    FUseBmpPipe := Ini.ReadBool('extraction', 'UseBmpPipe', DEF_USE_BMP_PIPE);
    FHwAccel := Ini.ReadBool('extraction', 'HwAccel', DEF_HW_ACCEL);
    FUseKeyframes := Ini.ReadBool('extraction', 'UseKeyframes', DEF_USE_KEYFRAMES);

    if SameText(Ini.ReadString('output', 'Mode', 'separate'), 'combined') then
      FOutputMode := womCombined
    else
      FOutputMode := womSeparate;
    if SameText(Ini.ReadString('output', 'Format', 'PNG'), 'JPEG') then
      FSaveFormat := sfJPEG
    else
      FSaveFormat := sfPNG;
    FJpegQuality := EnsureRange(Ini.ReadInteger('output', 'JpegQuality', DEF_JPEG_QUALITY), MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
    FPngCompression := EnsureRange(Ini.ReadInteger('output', 'PngCompression', DEF_PNG_COMPRESSION), MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);

    FCombinedColumns := EnsureRange(Ini.ReadInteger('combined', 'Columns', WCX_DEF_COMBINED_COLS), 0, 20);
    FShowTimestamp := Ini.ReadBool('combined', 'ShowTimestamp', WCX_DEF_SHOW_TIMESTAMP);
    FBackground := HexToColor(Ini.ReadString('combined', 'Background', ''), WCX_DEF_BACKGROUND);
    FCellGap := EnsureRange(Ini.ReadInteger('combined', 'CellGap', WCX_DEF_CELL_GAP), MIN_CELL_GAP, MAX_CELL_GAP);
    FCombinedBorder := EnsureRange(Ini.ReadInteger('combined', 'CombinedBorder', DEF_COMBINED_BORDER), MIN_COMBINED_BORDER, MAX_COMBINED_BORDER);
    FTimestampCorner := StrToTimestampCorner(Ini.ReadString('combined', 'TimestampCorner', ''));
    HexToColorAlpha(Ini.ReadString('combined', 'TimecodeBackground', ''), DEF_TC_BACK_COLOR, DEF_TC_BACK_ALPHA, FTimecodeBackColor, FTimecodeBackAlpha);
    FTimestampTextColor := HexToColor(Ini.ReadString('combined', 'TimestampTextColor', ''), DEF_TIMESTAMP_TEXT_COLOR);
    FTimestampTextAlpha := EnsureRange(Ini.ReadInteger('combined', 'TimestampTextAlpha', DEF_TIMESTAMP_TEXT_ALPHA), MIN_TIMESTAMP_TEXT_ALPHA, MAX_TIMESTAMP_TEXT_ALPHA);
    FTimestampFontName := Ini.ReadString('combined', 'TimestampFont', WCX_DEF_TIMESTAMP_FONT);
    if FTimestampFontName.Trim = '' then
      FTimestampFontName := WCX_DEF_TIMESTAMP_FONT;
    FTimestampFontSize := EnsureRange(Ini.ReadInteger('combined', 'TimestampFontSize', WCX_DEF_TIMESTAMP_FONT_SIZE), MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
    FShowBanner := Ini.ReadBool('combined', 'ShowBanner', WCX_DEF_SHOW_BANNER);

    FShowFileSizes := Ini.ReadBool('output', 'ShowFileSizes', WCX_DEF_SHOW_FILE_SIZES);

    FFrameMaxSide := EnsureRange(Ini.ReadInteger('output', 'FrameMaxSide', WCX_DEF_FRAME_MAX_SIDE), WCX_MIN_OUTPUT_SIDE, WCX_MAX_OUTPUT_SIDE);
    FCombinedMaxSide := EnsureRange(Ini.ReadInteger('combined', 'CombinedMaxSide', WCX_DEF_COMBINED_MAX_SIDE), WCX_MIN_OUTPUT_SIDE, WCX_MAX_OUTPUT_SIDE);
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
    Ini.WriteInteger('extraction', 'FramesCount', FFramesCount);
    Ini.WriteInteger('extraction', 'SkipEdges', FSkipEdgesPercent);
    Ini.WriteInteger('extraction', 'MaxWorkers', FMaxWorkers);
    Ini.WriteInteger('extraction', 'MaxThreads', FMaxThreads);
    Ini.WriteBool('extraction', 'UseBmpPipe', FUseBmpPipe);
    Ini.WriteBool('extraction', 'HwAccel', FHwAccel);
    Ini.WriteBool('extraction', 'UseKeyframes', FUseKeyframes);

    if FOutputMode = womCombined then
      Ini.WriteString('output', 'Mode', 'combined')
    else
      Ini.WriteString('output', 'Mode', 'separate');
    if FSaveFormat = sfJPEG then
      Ini.WriteString('output', 'Format', 'JPEG')
    else
      Ini.WriteString('output', 'Format', 'PNG');
    Ini.WriteInteger('output', 'JpegQuality', FJpegQuality);
    Ini.WriteInteger('output', 'PngCompression', FPngCompression);

    Ini.WriteInteger('combined', 'Columns', FCombinedColumns);
    Ini.WriteBool('combined', 'ShowTimestamp', FShowTimestamp);
    Ini.WriteString('combined', 'Background', ColorToHex(FBackground));
    Ini.WriteInteger('combined', 'CellGap', FCellGap);
    Ini.WriteInteger('combined', 'CombinedBorder', FCombinedBorder);
    Ini.WriteString('combined', 'TimestampCorner', TimestampCornerToStr(FTimestampCorner));
    Ini.WriteString('combined', 'TimecodeBackground', ColorAlphaToHex(FTimecodeBackColor, FTimecodeBackAlpha));
    Ini.WriteString('combined', 'TimestampTextColor', ColorToHex(FTimestampTextColor));
    Ini.WriteInteger('combined', 'TimestampTextAlpha', FTimestampTextAlpha);
    Ini.WriteString('combined', 'TimestampFont', FTimestampFontName);
    Ini.WriteInteger('combined', 'TimestampFontSize', FTimestampFontSize);
    Ini.WriteBool('combined', 'ShowBanner', FShowBanner);

    Ini.WriteBool('output', 'ShowFileSizes', FShowFileSizes);

    Ini.WriteInteger('output', 'FrameMaxSide', FFrameMaxSide);
    Ini.WriteInteger('combined', 'CombinedMaxSide', FCombinedMaxSide);
  finally
    Ini.Free;
  end;
end;

end.
