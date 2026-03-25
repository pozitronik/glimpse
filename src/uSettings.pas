/// Plugin settings manager backed by an INI file.
/// Handles defaults, validation, type-safe access, and persistence.
unit uSettings;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles, System.UITypes, System.Math;

type
  TFFmpegMode = (fmAuto, fmExe);
  TViewMode = (vmScroll, vmGrid, vmSmartGrid, vmFilmstrip, vmSingle);
  TZoomMode = (zmFitWindow, zmFitIfLarger, zmActual);
  TSaveFormat = (sfPNG, sfJPEG);

  TPluginSettings = class
  strict private
    FIniPath: string;
    { [ffmpeg] }
    FFFmpegMode: TFFmpegMode;
    FFFmpegExePath: string;
    FFFmpegAutoDownloaded: Boolean;
    FFFmpegSuppressPrompt: Boolean;
    { [extraction] }
    FDefaultN: Integer;
    FSkipEdgesPercent: Integer;
    FMaxWorkers: Integer;
    { [view] }
    FViewMode: TViewMode;
    FZoomMode: TZoomMode;
    FZoomFactor: Double;
    FBackground: TColor;
    FShowTimecode: Boolean;
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
    class function HexToColor(const AValue: string; ADefault: TColor): TColor; static;
    class function ColorToHex(AColor: TColor): string; static;
    class function Clamp(AValue, AMin, AMax: Integer): Integer; static;
  public
    constructor Create(const AIniPath: string);

    /// Loads all settings from the INI file. Missing or invalid values get defaults.
    procedure Load;
    /// Writes all current settings to the INI file.
    procedure Save;
    /// Resets all fields to default values without touching the file.
    procedure ResetDefaults;

    property IniPath: string read FIniPath;

    { [ffmpeg] }
    property FFmpegMode: TFFmpegMode read FFFmpegMode write FFFmpegMode;
    property FFmpegExePath: string read FFFmpegExePath write FFFmpegExePath;
    property FFmpegAutoDownloaded: Boolean read FFFmpegAutoDownloaded write FFFmpegAutoDownloaded;
    property FFmpegSuppressPrompt: Boolean read FFFmpegSuppressPrompt write FFFmpegSuppressPrompt;

    { [extraction] }
    property DefaultN: Integer read FDefaultN write FDefaultN;
    property SkipEdgesPercent: Integer read FSkipEdgesPercent write FSkipEdgesPercent;
    property MaxWorkers: Integer read FMaxWorkers write FMaxWorkers;

    { [view] }
    property ViewMode: TViewMode read FViewMode write FViewMode;
    property ZoomMode: TZoomMode read FZoomMode write FZoomMode;
    property ZoomFactor: Double read FZoomFactor write FZoomFactor;
    property Background: TColor read FBackground write FBackground;
    property ShowTimecode: Boolean read FShowTimecode write FShowTimecode;

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
  DEF_FFMPEG_SUPPRESS    = False;
  DEF_DEFAULT_N          = 4;
  DEF_SKIP_EDGES_PERCENT = 2;
  DEF_MAX_WORKERS        = 1;
  DEF_VIEW_MODE          = vmGrid;
  DEF_ZOOM_MODE          = zmFitWindow;
  DEF_ZOOM_FACTOR        = 1.0;
  DEF_BACKGROUND         = TColor($001E1E1E);
  DEF_SHOW_TIMECODE      = True;
  DEF_EXTENSION_LIST     = 'mp4,mkv,avi,mov,wmv,webm,flv,ts,m2ts,m4v,3gp,ogv,mpg,mpeg,vob,asf,rm,rmvb,f4v';
  DEF_SAVE_FORMAT        = sfPNG;
  DEF_JPEG_QUALITY       = 90;
  DEF_PNG_COMPRESSION    = 6;
  DEF_SAVE_FOLDER        = '';
  DEF_CACHE_ENABLED      = False;
  DEF_CACHE_FOLDER       = '';
  DEF_CACHE_MAX_SIZE_MB  = 500;

implementation

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
  FFFmpegSuppressPrompt := DEF_FFMPEG_SUPPRESS;
  FDefaultN := DEF_DEFAULT_N;
  FSkipEdgesPercent := DEF_SKIP_EDGES_PERCENT;
  FMaxWorkers := DEF_MAX_WORKERS;
  FViewMode := DEF_VIEW_MODE;
  FZoomMode := DEF_ZOOM_MODE;
  FZoomFactor := DEF_ZOOM_FACTOR;
  FBackground := DEF_BACKGROUND;
  FShowTimecode := DEF_SHOW_TIMECODE;
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
    FFFmpegSuppressPrompt := Ini.ReadBool('ffmpeg', 'SuppressSetupPrompt', DEF_FFMPEG_SUPPRESS);

    FDefaultN := Clamp(Ini.ReadInteger('extraction', 'DefaultN', DEF_DEFAULT_N), 1, 99);
    FSkipEdgesPercent := Clamp(Ini.ReadInteger('extraction', 'SkipEdges', DEF_SKIP_EDGES_PERCENT), 0, 49);
    FMaxWorkers := Clamp(Ini.ReadInteger('extraction', 'MaxWorkers', DEF_MAX_WORKERS), 1, 16);

    FViewMode := StrToViewMode(Ini.ReadString('view', 'Mode', ''));
    FZoomMode := StrToZoomMode(Ini.ReadString('view', 'ZoomMode', ''));
    FZoomFactor := Ini.ReadFloat('view', 'ZoomFactor', DEF_ZOOM_FACTOR);
    if FZoomFactor <= 0 then
      FZoomFactor := DEF_ZOOM_FACTOR;
    FBackground := HexToColor(Ini.ReadString('view', 'Background', ''), DEF_BACKGROUND);
    FShowTimecode := Ini.ReadBool('view', 'ShowTimecode', DEF_SHOW_TIMECODE);

    FExtensionList := Ini.ReadString('extensions', 'List', DEF_EXTENSION_LIST);
    if FExtensionList.Trim = '' then
      FExtensionList := DEF_EXTENSION_LIST;

    FSaveFormat := StrToSaveFormat(Ini.ReadString('save', 'Format', ''));
    FJpegQuality := Clamp(Ini.ReadInteger('save', 'JpegQuality', DEF_JPEG_QUALITY), 1, 100);
    FPngCompression := Clamp(Ini.ReadInteger('save', 'PngCompression', DEF_PNG_COMPRESSION), 0, 9);
    FSaveFolder := Ini.ReadString('save', 'SaveFolder', DEF_SAVE_FOLDER);

    FCacheEnabled := Ini.ReadBool('cache', 'Enabled', DEF_CACHE_ENABLED);
    FCacheFolder := Ini.ReadString('cache', 'Folder', DEF_CACHE_FOLDER);
    FCacheMaxSizeMB := Clamp(Ini.ReadInteger('cache', 'MaxSizeMB', DEF_CACHE_MAX_SIZE_MB), 10, 10000);
  finally
    Ini.Free;
  end;
end;

procedure TPluginSettings.Save;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FIniPath);
  try
    Ini.WriteString('ffmpeg', 'Mode', FFmpegModeToStr(FFFmpegMode));
    Ini.WriteString('ffmpeg', 'ExePath', FFFmpegExePath);
    Ini.WriteBool('ffmpeg', 'AutoDownloaded', FFFmpegAutoDownloaded);
    Ini.WriteBool('ffmpeg', 'SuppressSetupPrompt', FFFmpegSuppressPrompt);

    Ini.WriteInteger('extraction', 'DefaultN', FDefaultN);
    Ini.WriteInteger('extraction', 'SkipEdges', FSkipEdgesPercent);
    Ini.WriteInteger('extraction', 'MaxWorkers', FMaxWorkers);

    Ini.WriteString('view', 'Mode', ViewModeToStr(FViewMode));
    Ini.WriteString('view', 'ZoomMode', ZoomModeToStr(FZoomMode));
    Ini.WriteFloat('view', 'ZoomFactor', FZoomFactor);
    Ini.WriteString('view', 'Background', ColorToHex(FBackground));
    Ini.WriteBool('view', 'ShowTimecode', FShowTimecode);

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

class function TPluginSettings.HexToColor(const AValue: string; ADefault: TColor): TColor;
var
  R, G, B: Integer;
  Hex: string;
begin
  Hex := AValue.Trim;
  if (Length(Hex) = 7) and (Hex[1] = '#') then
  begin
    try
      R := StrToInt('$' + Copy(Hex, 2, 2));
      G := StrToInt('$' + Copy(Hex, 4, 2));
      B := StrToInt('$' + Copy(Hex, 6, 2));
      { TColor is stored as $00BBGGRR }
      Result := TColor(R or (G shl 8) or (B shl 16));
    except
      Result := ADefault;
    end;
  end
  else
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

class function TPluginSettings.Clamp(AValue, AMin, AMax: Integer): Integer;
begin
  Result := EnsureRange(AValue, AMin, AMax);
end;

end.
