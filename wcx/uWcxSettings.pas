{ WCX plugin settings backed by an INI file.
  Separate from WLX settings to allow independent configuration. }
unit uWcxSettings;

interface

uses
  System.SysUtils, System.IniFiles, System.Math,
  uBitmapSaver, uTypes;

type
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
    FSaveFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
    { [extensions] }
    FExtensionList: string;
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
    property SaveFormat: TSaveFormat read FSaveFormat write FSaveFormat;
    property JpegQuality: Integer read FJpegQuality write FJpegQuality;
    property PngCompression: Integer read FPngCompression write FPngCompression;
    property ExtensionList: string read FExtensionList write FExtensionList;
  end;

const
  WCX_DEF_FRAMES_COUNT   = 4;
  WCX_DEF_SKIP_EDGES     = 2;
  WCX_DEF_MAX_WORKERS    = 1;
  WCX_DEF_MAX_THREADS    = -1;
  WCX_DEF_USE_BMP_PIPE   = True;
  WCX_DEF_SAVE_FORMAT    = sfPNG;
  WCX_DEF_JPEG_QUALITY   = 90;
  WCX_DEF_PNG_COMPRESSION = 6;
  WCX_DEF_EXTENSION_LIST = 'mp4,mkv,avi,mov,wmv,webm,flv,ts,m2ts,m4v,3gp,ogv,mpg,mpeg,vob,asf,rm,rmvb,f4v';

implementation

uses
  uPathExpand;

{ TWcxSettings }

constructor TWcxSettings.Create(const AIniPath: string);
begin
  inherited Create;
  FIniPath := AIniPath;
  FFFmpegMode := fmAuto;
  FFFmpegExePath := '';
  FFramesCount := WCX_DEF_FRAMES_COUNT;
  FSkipEdgesPercent := WCX_DEF_SKIP_EDGES;
  FMaxWorkers := WCX_DEF_MAX_WORKERS;
  FMaxThreads := WCX_DEF_MAX_THREADS;
  FUseBmpPipe := WCX_DEF_USE_BMP_PIPE;
  FSaveFormat := WCX_DEF_SAVE_FORMAT;
  FJpegQuality := WCX_DEF_JPEG_QUALITY;
  FPngCompression := WCX_DEF_PNG_COMPRESSION;
  FExtensionList := WCX_DEF_EXTENSION_LIST;
end;

procedure TWcxSettings.Load;
var
  Ini: TIniFile;
begin
  if not FileExists(FIniPath) then Exit;
  Ini := TIniFile.Create(FIniPath);
  try
    FFFmpegExePath := Ini.ReadString('ffmpeg', 'ExePath', '');
    FFramesCount := EnsureRange(
      Ini.ReadInteger('extraction', 'FramesCount', WCX_DEF_FRAMES_COUNT), 1, 99);
    FSkipEdgesPercent := EnsureRange(
      Ini.ReadInteger('extraction', 'SkipEdges', WCX_DEF_SKIP_EDGES), 0, 49);
    FMaxWorkers := EnsureRange(
      Ini.ReadInteger('extraction', 'MaxWorkers', WCX_DEF_MAX_WORKERS), 0, 16);
    FMaxThreads := EnsureRange(
      Ini.ReadInteger('extraction', 'MaxThreads', WCX_DEF_MAX_THREADS), -1, 64);
    FUseBmpPipe := Ini.ReadBool('extraction', 'UseBmpPipe', WCX_DEF_USE_BMP_PIPE);
    if SameText(Ini.ReadString('output', 'Format', 'PNG'), 'JPEG') then
      FSaveFormat := sfJPEG
    else
      FSaveFormat := sfPNG;
    FJpegQuality := EnsureRange(
      Ini.ReadInteger('output', 'JpegQuality', WCX_DEF_JPEG_QUALITY), 1, 100);
    FPngCompression := EnsureRange(
      Ini.ReadInteger('output', 'PngCompression', WCX_DEF_PNG_COMPRESSION), 0, 9);
    FExtensionList := Ini.ReadString('extensions', 'List', WCX_DEF_EXTENSION_LIST);
    if FExtensionList.Trim = '' then
      FExtensionList := WCX_DEF_EXTENSION_LIST;
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
    if FSaveFormat = sfJPEG then
      Ini.WriteString('output', 'Format', 'JPEG')
    else
      Ini.WriteString('output', 'Format', 'PNG');
    Ini.WriteInteger('output', 'JpegQuality', FJpegQuality);
    Ini.WriteInteger('output', 'PngCompression', FPngCompression);
    Ini.WriteString('extensions', 'List', FExtensionList);
  finally
    Ini.Free;
  end;
end;

end.
