{ WCX plugin settings backed by an INI file.
  Separate from WLX settings to allow independent configuration. }
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
    { [ffmpeg] }
    FFFmpegMode: TFFmpegMode;
    FFFmpegExePath: string;
    { [extraction] }
    FFramesCount: Integer;
    FSkipEdgesPercent: Integer;
    FMaxWorkers: Integer;
    FMaxThreads: Integer;
    FUseBmpPipe: Boolean;
    { [output] }
    FOutputMode: TWcxOutputMode;
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    { [combined] }
    FCombinedColumns: Integer;
    FShowTimestamp: Boolean;
    FBackground: TColor;
    FCellGap: Integer;
    { [output] }
    FShowFileSizes: Boolean;
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
    property OutputMode: TWcxOutputMode read FOutputMode write FOutputMode;
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property CombinedColumns: Integer read FCombinedColumns write FCombinedColumns;
    property ShowTimestamp: Boolean read FShowTimestamp write FShowTimestamp;
    property Background: TColor read FBackground write FBackground;
    property CellGap: Integer read FCellGap write FCellGap;
    property ShowFileSizes: Boolean read FShowFileSizes write FShowFileSizes;
  end;

const
  { WCX-specific defaults (shared defaults are in uDefaults) }
  WCX_DEF_OUTPUT_MODE     = womSeparate;
  WCX_DEF_COMBINED_COLS   = 0;   { 0 = auto }
  WCX_DEF_SHOW_TIMESTAMP  = True;
  WCX_DEF_BACKGROUND      = TColor($001E1E1E);
  WCX_DEF_CELL_GAP        = 2;
  WCX_DEF_SHOW_FILE_SIZES = False;

implementation

uses
  uPathExpand, uColorConv;

{ TWcxSettings }

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
  FOutputMode := WCX_DEF_OUTPUT_MODE;
  FSaveFormat := DEF_SAVE_FORMAT;
  FJpegQuality := DEF_JPEG_QUALITY;
  FPngCompression := DEF_PNG_COMPRESSION;
  FCombinedColumns := WCX_DEF_COMBINED_COLS;
  FShowTimestamp := WCX_DEF_SHOW_TIMESTAMP;
  FBackground := WCX_DEF_BACKGROUND;
  FCellGap := WCX_DEF_CELL_GAP;
  FShowFileSizes := WCX_DEF_SHOW_FILE_SIZES;
end;

procedure TWcxSettings.Load;
var
  Ini: TIniFile;
begin
  if not FileExists(FIniPath) then Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    FFFmpegExePath := Ini.ReadString('ffmpeg', 'ExePath', '');
    FFramesCount := EnsureRange(Ini.ReadInteger('extraction', 'FramesCount',
      DEF_FRAMES_COUNT), MIN_FRAMES_COUNT, MAX_FRAMES_COUNT);
    FSkipEdgesPercent := EnsureRange(Ini.ReadInteger('extraction', 'SkipEdges',
      DEF_SKIP_EDGES), MIN_SKIP_EDGES, MAX_SKIP_EDGES);
    FMaxWorkers := EnsureRange(Ini.ReadInteger('extraction', 'MaxWorkers',
      DEF_MAX_WORKERS), MIN_MAX_WORKERS, MAX_MAX_WORKERS);
    FMaxThreads := EnsureRange(Ini.ReadInteger('extraction', 'MaxThreads',
      DEF_MAX_THREADS), MIN_MAX_THREADS, MAX_MAX_THREADS);
    FUseBmpPipe := Ini.ReadBool('extraction', 'UseBmpPipe', DEF_USE_BMP_PIPE);

    if SameText(Ini.ReadString('output', 'Mode', 'separate'), 'combined') then
      FOutputMode := womCombined
    else
      FOutputMode := womSeparate;
    if SameText(Ini.ReadString('output', 'Format', 'PNG'), 'JPEG') then
      FSaveFormat := sfJPEG
    else
      FSaveFormat := sfPNG;
    FJpegQuality := EnsureRange(Ini.ReadInteger('output', 'JpegQuality',
      DEF_JPEG_QUALITY), MIN_JPEG_QUALITY, MAX_JPEG_QUALITY);
    FPngCompression := EnsureRange(Ini.ReadInteger('output', 'PngCompression',
      DEF_PNG_COMPRESSION), MIN_PNG_COMPRESSION, MAX_PNG_COMPRESSION);

    FCombinedColumns := EnsureRange(
      Ini.ReadInteger('combined', 'Columns', WCX_DEF_COMBINED_COLS), 0, 20);
    FShowTimestamp := Ini.ReadBool('combined', 'ShowTimestamp', WCX_DEF_SHOW_TIMESTAMP);
    FBackground := HexToColor(
      Ini.ReadString('combined', 'Background', ''), WCX_DEF_BACKGROUND);
    FCellGap := EnsureRange(
      Ini.ReadInteger('combined', 'CellGap', WCX_DEF_CELL_GAP), 0, 20);

    FShowFileSizes := Ini.ReadBool('output', 'ShowFileSizes', WCX_DEF_SHOW_FILE_SIZES);
  finally
    Ini.Free;
  end;
end;

procedure TWcxSettings.Save;
var
  Ini: TIniFile;
begin
  if FIniPath = '' then Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    Ini.WriteString('ffmpeg', 'ExePath', FFFmpegExePath);
    Ini.WriteInteger('extraction', 'FramesCount', FFramesCount);
    Ini.WriteInteger('extraction', 'SkipEdges', FSkipEdgesPercent);
    Ini.WriteInteger('extraction', 'MaxWorkers', FMaxWorkers);
    Ini.WriteInteger('extraction', 'MaxThreads', FMaxThreads);
    Ini.WriteBool('extraction', 'UseBmpPipe', FUseBmpPipe);

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

    Ini.WriteBool('output', 'ShowFileSizes', FShowFileSizes);
  finally
    Ini.Free;
  end;
end;

end.
