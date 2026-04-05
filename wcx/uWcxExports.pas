{ WCX plugin exported functions.
  Presents a video file as a virtual archive containing frame images. }
unit uWcxExports;

interface

uses
  Winapi.Windows, uWcxAPI;

{ Opens archive (video file) for listing or extraction }
function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;

{ Reads next file header from archive }
function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;

{ Processes (extracts/skips) the current file }
function ProcessFile(hArcData: THandle; Operation: Integer;
  DestPath, DestName: PAnsiChar): Integer; stdcall;
function ProcessFileW(hArcData: THandle; Operation: Integer;
  DestPath, DestName: PWideChar): Integer; stdcall;

{ Closes archive handle }
function CloseArchive(hArcData: THandle): Integer; stdcall;

{ Callback setters }
procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;

{ Reports plugin capabilities }
function GetPackerCaps: Integer; stdcall;

{ Receives default INI path from TC }
procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;

implementation

uses
  System.SysUtils, System.AnsiStrings,
  Vcl.Graphics,
  uWcxSettings, uFFmpegLocator, uFFmpegExe, uFrameOffsets,
  uFrameFileNames, uBitmapSaver, uFrameExtractor, uExtractionPlanner,
  uDebugLog, uPathExpand;

type
  { State for one open archive (video file) }
  TArchiveHandle = class
    FileName: string;
    Settings: TWcxSettings;
    FFmpegPath: string;
    VideoInfo: TVideoInfo;
    Offsets: TFrameOffsetArray;
    CurrentIndex: Integer;
    OpenMode: Integer;
    ProcessDataProc: TProcessDataProc;
    ProcessDataProcW: TProcessDataProcW;
  end;

var
  GIniPath: string;

procedure WcxLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

function DoOpenArchive(const AFileName: string; AOpenMode: Integer;
  out AOpenResult: Integer): THandle;
var
  H: TArchiveHandle;
  FFmpeg: TFFmpegExe;
begin
  Result := 0;
  AOpenResult := E_SUCCESS;

  H := TArchiveHandle.Create;
  try
    H.FileName := AFileName;
    H.OpenMode := AOpenMode;
    H.CurrentIndex := 0;

    H.Settings := TWcxSettings.Create(GIniPath);
    H.Settings.Load;

    H.FFmpegPath := FindFFmpegExe(ExtractFilePath(GIniPath),
      ExpandEnvVars(H.Settings.FFmpegExePath));

    if H.FFmpegPath = '' then
    begin
      AOpenResult := E_EOPEN;
      H.Free;
      Exit;
    end;

    FFmpeg := TFFmpegExe.Create(H.FFmpegPath);
    try
      H.VideoInfo := FFmpeg.ProbeVideo(AFileName);
    finally
      FFmpeg.Free;
    end;

    if not H.VideoInfo.IsValid then
    begin
      AOpenResult := E_BAD_ARCHIVE;
      H.Free;
      Exit;
    end;

    H.Offsets := CalculateFrameOffsets(H.VideoInfo.Duration,
      H.Settings.FramesCount, H.Settings.SkipEdgesPercent);

    WcxLog(Format('OpenArchive: %s frames=%d', [AFileName, Length(H.Offsets)]));
    Result := THandle(H);
  except
    H.Free;
    AOpenResult := E_BAD_ARCHIVE;
  end;
end;

function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
begin
  Result := DoOpenArchive(string(AnsiString(ArchiveData.ArcName)),
    ArchiveData.OpenMode, ArchiveData.OpenResult);
end;

function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;
begin
  Result := DoOpenArchive(ArchiveData.ArcName,
    ArchiveData.OpenMode, ArchiveData.OpenResult);
end;

function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: AnsiString;
begin
  H := TArchiveHandle(hArcData);
  if H.CurrentIndex >= Length(H.Offsets) then
    Exit(E_END_ARCHIVE);

  Name := AnsiString(GenerateFrameFileName(H.FileName, H.CurrentIndex,
    H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat));

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  System.AnsiStrings.StrLCopy(HeaderData.FileName, PAnsiChar(Name), SizeOf(HeaderData.FileName) - 1);
  HeaderData.UnpSize := 0;
  HeaderData.FileAttr := $20; { FILE_ATTRIBUTE_ARCHIVE }

  Result := E_SUCCESS;
end;

function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: string;
begin
  H := TArchiveHandle(hArcData);
  if H.CurrentIndex >= Length(H.Offsets) then
    Exit(E_END_ARCHIVE);

  Name := GenerateFrameFileName(H.FileName, H.CurrentIndex,
    H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat);

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  StrLCopy(HeaderData.FileName, PChar(Name), Length(HeaderData.FileName) - 1);
  HeaderData.UnpSizeLow := 0;
  HeaderData.FileAttr := $20;

  Result := E_SUCCESS;
end;

function DoProcessFile(hArcData: THandle; Operation: Integer;
  const ADestPath, ADestName: string): Integer;
var
  H: TArchiveHandle;
  Extractor: IFrameExtractor;
  Bmp: TBitmap;
  FullPath: string;
begin
  H := TArchiveHandle(hArcData);

  if Operation = PK_SKIP then
  begin
    Inc(H.CurrentIndex);
    Exit(E_SUCCESS);
  end;

  if (Operation <> PK_EXTRACT) and (Operation <> PK_TEST) then
  begin
    Inc(H.CurrentIndex);
    Exit(E_SUCCESS);
  end;

  if H.CurrentIndex >= Length(H.Offsets) then
    Exit(E_END_ARCHIVE);

  if Operation = PK_EXTRACT then
  begin
    if ADestName <> '' then
      FullPath := ADestName
    else if ADestPath <> '' then
      FullPath := IncludeTrailingPathDelimiter(ADestPath) +
        GenerateFrameFileName(H.FileName, H.CurrentIndex,
          H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat)
    else
    begin
      Inc(H.CurrentIndex);
      Exit(E_ECREATE);
    end;

    WcxLog(Format('Extract frame %d -> %s', [H.CurrentIndex, FullPath]));

    Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
    try
      Bmp := Extractor.ExtractFrame(H.FileName,
        H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.UseBmpPipe);
      if Bmp = nil then
      begin
        Inc(H.CurrentIndex);
        Exit(E_BAD_DATA);
      end;
      try
        SaveBitmapToFile(Bmp, FullPath, H.Settings.SaveFormat,
          H.Settings.JpegQuality, H.Settings.PngCompression);
      finally
        Bmp.Free;
      end;
    except
      Inc(H.CurrentIndex);
      Exit(E_EWRITE);
    end;
  end;

  Inc(H.CurrentIndex);
  Result := E_SUCCESS;
end;

function ProcessFile(hArcData: THandle; Operation: Integer;
  DestPath, DestName: PAnsiChar): Integer; stdcall;
var
  SPath, SName: string;
begin
  if DestPath <> nil then SPath := string(AnsiString(DestPath)) else SPath := '';
  if DestName <> nil then SName := string(AnsiString(DestName)) else SName := '';
  Result := DoProcessFile(hArcData, Operation, SPath, SName);
end;

function ProcessFileW(hArcData: THandle; Operation: Integer;
  DestPath, DestName: PWideChar): Integer; stdcall;
var
  SPath, SName: string;
begin
  if DestPath <> nil then SPath := DestPath else SPath := '';
  if DestName <> nil then SName := DestName else SName := '';
  Result := DoProcessFile(hArcData, Operation, SPath, SName);
end;

function CloseArchive(hArcData: THandle): Integer; stdcall;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle(hArcData);
  WcxLog(Format('CloseArchive: %s', [H.FileName]));
  H.Settings.Free;
  H.Free;
  Result := E_SUCCESS;
end;

procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
begin
  { Not used: video files are single-volume }
end;

procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
begin
  if hArcData <> 0 then
    TArchiveHandle(hArcData).ProcessDataProc := pProcessDataProc;
end;

function GetPackerCaps: Integer; stdcall;
begin
  { Read-only: we can list and extract, nothing else }
  Result := PK_CAPS_BY_CONTENT or PK_CAPS_SEARCHTEXT or PK_CAPS_HIDE;
end;

procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;
begin
  if (dps <> nil) and (dps^.Size >= SizeOf(TWcxDefaultParams)) then
  begin
    GIniPath := ChangeFileExt(string(AnsiString(dps^.DefaultIniName)), '.ini');
    WcxLog(Format('SetDefaultParams: ini=%s', [GIniPath]));
  end;
end;

end.
