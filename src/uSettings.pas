{ Plugin settings manager backed by an INI file.
  Handles defaults, validation, type-safe access, and persistence. }
unit uSettings;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, System.UITypes, System.Math;

type
  TFFmpegMode = (fmAuto, fmExe);
  TViewMode = (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);
  TZoomMode = (zmFitWindow, zmFitIfLarger, zmActual);
  TSaveFormat = (sfPNG, sfJPEG);

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
    { [view] }
    FViewMode: TViewMode;
    FModeZoom: array[TViewMode] of TZoomMode;
    FBackground: TColor;
    FShowTimecode: Boolean;
    FShowToolbar: Boolean;
    FShowStatusBar: Boolean;
    FTimecodeBackColor: TColor;
    FTimecodeBackAlpha: Byte;
    { [extensions] }
    FExtensionList: string;
    { [save] }
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    FSaveFolder: string;
    { [cache] }
    FCacheEnabled: Boolean;
    FCacheFolder: string;
    FCacheMaxSizeMB: Integer;

    class function StrToFFmpegMode(const AValue: string): TFFmpegMode; static;
    class function FFmpegModeToStr(AMode: TFFmpegMode): string; static;
    class function StrToViewMode(const AValue: string): TViewMode; static;
    class function ViewModeToStr(AMode: TViewMode): string; static;
    class function StrToZoomMode(const AValue: string): TZoomMode; static;
    class function ZoomModeToStr(AMode: TZoomMode): string; static;
    class function StrToSaveFormat(const AValue: string): TSaveFormat; static;
    class function SaveFormatToStr(AFormat: TSaveFormat): string; static;
    class function TryParseHexRGB(const AHex: string; out AColor: TColor): Boolean; static;
    class function HexToColor(const AValue: string; ADefault: TColor): TColor; static;
    class function ColorToHex(AColor: TColor): string; static;
    class procedure HexToColorAlpha(const AValue: string; ADefColor: TColor;
      ADefAlpha: Byte; out AColor: TColor; out AAlpha: Byte); static;
    class function ColorAlphaToHex(AColor: TColor; AAlpha: Byte): string; static;
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

    { [extensions] }
    property ExtensionList: string read FExtensionList write FExtensionList;

    { [save] }
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property SaveFolder: string read FSaveFolder write FSaveFolder;

    { [cache] }
    property CacheEnabled: Boolean read FCacheEnabled write FCacheEnabled;
    property CacheFolder: string read FCacheFolder write FCacheFolder;
    property CacheMaxSizeMB: Integer read FCacheMaxSizeMB write FCacheMaxSizeMB;
  end;

const
  DEF_FFMPEG_MODE        = fmAuto;
  DEF_FFMPEG_EXE_PATH    = '';
  DEF_FFMPEG_AUTO_DL     = False;

  DEF_FRAMES_COUNT          = 4;
  DEF_SKIP_EDGES_PERCENT = 2;
  DEF_MAX_WORKERS        = 1;
  DEF_VIEW_MODE          = vmGrid;
  DEF_ZOOM_MODE          = zmFitWindow;
  DEF_BACKGROUND         = TColor($001E1E1E);
  DEF_SHOW_TIMECODE      = True;
  DEF_SHOW_TOOLBAR       = True;
  DEF_SHOW_STATUS_BAR    = True;
  DEF_TC_BACK_COLOR      = TColor($002D2D2D);
  DEF_TC_BACK_ALPHA      = 180;
  DEF_EXTENSION_LIST     = 'mp4,mkv,avi,mov,wmv,webm,flv,ts,m2ts,m4v,3gp,ogv,mpg,mpeg,vob,asf,rm,rmvb,f4v';
  DEF_SAVE_FORMAT        = sfPNG;
  DEF_JPEG_QUALITY       = 90;
  DEF_PNG_COMPRESSION    = 6;
  DEF_SAVE_FOLDER        = '';
  DEF_CACHE_ENABLED      = True;
  DEF_CACHE_FOLDER       = '';
  DEF_CACHE_MAX_SIZE_MB  = 500;

{ Returns the default cache folder path used when CacheFolder setting is empty. }
function DefaultCacheFolder: string;

{ Returns the effective cache folder: the configured value, or the default if empty. }
function EffectiveCacheFolder(const ACacheFolder: string): string;

implementation

function DefaultCacheFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'VideoThumb' + PathDelim + 'cache');
end;

function EffectiveCacheFolder(const ACacheFolder: string): string;
begin
  if ACacheFolder <> '' then
    Result := ACacheFolder
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
  FViewMode := DEF_VIEW_MODE;
  for var VM := Low(TViewMode) to High(TViewMode) do
    FModeZoom[VM] := DEF_ZOOM_MODE;
  FBackground := DEF_BACKGROUND;
  FShowTimecode := DEF_SHOW_TIMECODE;
  FShowToolbar := DEF_SHOW_TOOLBAR;
  FShowStatusBar := DEF_SHOW_STATUS_BAR;
  FTimecodeBackColor := DEF_TC_BACK_COLOR;
  FTimecodeBackAlpha := DEF_TC_BACK_ALPHA;
  FExtensionList := DEF_EXTENSION_LIST;
  FSaveFormat := DEF_SAVE_FORMAT;
  FJpegQuality := DEF_JPEG_QUALITY;
  FPngCompression := DEF_PNG_COMPRESSION;
  FSaveFolder := DEF_SAVE_FOLDER;
  FCacheEnabled := DEF_CACHE_ENABLED;
  FCacheFolder := DEF_CACHE_FOLDER;
  FCacheMaxSizeMB := DEF_CACHE_MAX_SIZE_MB;
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

    FFramesCount := EnsureRange(Ini.ReadInteger('extraction', 'FramesCount', DEF_FRAMES_COUNT), 1, 99);
    FSkipEdgesPercent := EnsureRange(Ini.ReadInteger('extraction', 'SkipEdges', DEF_SKIP_EDGES_PERCENT), 0, 49);
    FMaxWorkers := EnsureRange(Ini.ReadInteger('extraction', 'MaxWorkers', DEF_MAX_WORKERS), 0, 16);

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

    FExtensionList := Ini.ReadString('extensions', 'List', DEF_EXTENSION_LIST);
    if FExtensionList.Trim = '' then
      FExtensionList := DEF_EXTENSION_LIST;

    FSaveFormat := StrToSaveFormat(Ini.ReadString('save', 'Format', ''));
    FJpegQuality := EnsureRange(Ini.ReadInteger('save', 'JpegQuality', DEF_JPEG_QUALITY), 1, 100);
    FPngCompression := EnsureRange(Ini.ReadInteger('save', 'PngCompression', DEF_PNG_COMPRESSION), 0, 9);
    FSaveFolder := Ini.ReadString('save', 'SaveFolder', DEF_SAVE_FOLDER);

    FCacheEnabled := Ini.ReadBool('cache', 'Enabled', DEF_CACHE_ENABLED);
    FCacheFolder := Ini.ReadString('cache', 'Folder', DEF_CACHE_FOLDER);
    FCacheMaxSizeMB := EnsureRange(Ini.ReadInteger('cache', 'MaxSizeMB', DEF_CACHE_MAX_SIZE_MB), 10, 10000);
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

    Ini.WriteString('extensions', 'List', FExtensionList);

    Ini.WriteString('save', 'Format', SaveFormatToStr(FSaveFormat));
    Ini.WriteInteger('save', 'JpegQuality', FJpegQuality);
    Ini.WriteInteger('save', 'PngCompression', FPngCompression);
    Ini.WriteString('save', 'SaveFolder', FSaveFolder);

    Ini.WriteBool('cache', 'Enabled', FCacheEnabled);
    Ini.WriteString('cache', 'Folder', FCacheFolder);
    Ini.WriteInteger('cache', 'MaxSizeMB', FCacheMaxSizeMB);
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

{ Parses #RRGGBB from a hex string starting at position 1.
  Returns True on success, setting AColor. }
class function TPluginSettings.TryParseHexRGB(const AHex: string; out AColor: TColor): Boolean;
var
  R, G, B: Integer;
begin
  Result := False;
  try
    R := StrToInt('$' + Copy(AHex, 2, 2));
    G := StrToInt('$' + Copy(AHex, 4, 2));
    B := StrToInt('$' + Copy(AHex, 6, 2));
    { TColor is stored as $00BBGGRR }
    AColor := TColor(R or (G shl 8) or (B shl 16));
    Result := True;
  except
  end;
end;

class function TPluginSettings.HexToColor(const AValue: string; ADefault: TColor): TColor;
var
  Hex: string;
begin
  Hex := AValue.Trim;
  if (Length(Hex) = 7) and (Hex[1] = '#') and TryParseHexRGB(Hex, Result) then
    Exit;
  Result := ADefault;
end;

class function TPluginSettings.ColorToHex(AColor: TColor): string;
var
  C: Integer;
begin
  C := Integer(AColor);
  Result := Format('#%.2X%.2X%.2X', [
    C and $FF,
    (C shr 8) and $FF,
    (C shr 16) and $FF
  ]);
end;

class procedure TPluginSettings.HexToColorAlpha(const AValue: string;
  ADefColor: TColor; ADefAlpha: Byte; out AColor: TColor; out AAlpha: Byte);
var
  Hex: string;
begin
  Hex := AValue.Trim;
  if (Length(Hex) = 9) and (Hex[1] = '#') and TryParseHexRGB(Hex, AColor) then
  begin
    try
      AAlpha := Byte(StrToInt('$' + Copy(Hex, 8, 2)));
      Exit;
    except
    end;
  end;
  AColor := ADefColor;
  AAlpha := ADefAlpha;
end;

class function TPluginSettings.ColorAlphaToHex(AColor: TColor; AAlpha: Byte): string;
var
  C: Integer;
begin
  C := Integer(AColor);
  Result := Format('#%.2X%.2X%.2X%.2X', [
    C and $FF,
    (C shr 8) and $FF,
    (C shr 16) and $FF,
    AAlpha
  ]);
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
