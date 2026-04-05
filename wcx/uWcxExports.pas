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

{ Stub: packing not supported, exists only to make Configure button accessible }
function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar;
  Flags: Integer): Integer; stdcall;

{ Shows configuration dialog }
procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;

implementation

uses
  System.SysUtils, System.Math, System.Types, System.AnsiStrings,
  System.UITypes,
  Vcl.Graphics,
  uWcxSettings, uWcxSettingsDlg, uFFmpegLocator, uFFmpegExe, uFrameOffsets,
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

{ Generates combined image filename: <basename>_combined.<ext> }
function GenerateCombinedFileName(const AVideoFileName: string;
  AFormat: TSaveFormat): string;
begin
  Result := ChangeFileExt(ExtractFileName(AVideoFileName), '') +
    '_combined' + SaveFormatExtension(AFormat);
end;

{ Renders all frames into a single grid image with optional timestamps }
function RenderCombinedImage(const AFrames: TArray<TBitmap>;
  const AOffsets: TFrameOffsetArray; ASettings: TWcxSettings): TBitmap;
var
  Cols, Rows, CellW, CellH, Gap, I, Row, Col, X, Y: Integer;
  FrameCount: Integer;
  Tc: string;
  TH: Integer;
begin
  FrameCount := Length(AFrames);
  if FrameCount = 0 then
    Exit(nil);

  Gap := ASettings.CellGap;
  Cols := ASettings.CombinedColumns;
  if Cols <= 0 then
    Cols := Ceil(Sqrt(FrameCount));
  if Cols > FrameCount then
    Cols := FrameCount;
  Rows := Ceil(FrameCount / Cols);

  { Use first non-nil frame dimensions as cell size }
  CellW := 320;
  CellH := 240;
  for I := 0 to FrameCount - 1 do
    if AFrames[I] <> nil then
    begin
      CellW := AFrames[I].Width;
      CellH := AFrames[I].Height;
      Break;
    end;

  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Cols * CellW + Max(Cols - 1, 0) * Gap,
                 Rows * CellH + Max(Rows - 1, 0) * Gap);
  Result.Canvas.Brush.Color := ASettings.Background;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then Continue;
    Row := I div Cols;
    Col := I mod Cols;
    X := Col * (CellW + Gap);
    Y := Row * (CellH + Gap);
    Result.Canvas.Draw(X, Y, AFrames[I]);

    if ASettings.ShowTimestamp and (I < Length(AOffsets)) then
    begin
      Tc := FormatTimecode(AOffsets[I].TimeOffset);
      Result.Canvas.Font.Name := 'Consolas';
      Result.Canvas.Font.Size := 9;
      Result.Canvas.Font.Style := [fsBold];
      TH := Result.Canvas.TextHeight(Tc);
      { Shadow for readability }
      Result.Canvas.Font.Color := clBlack;
      Result.Canvas.Brush.Style := bsClear;
      Result.Canvas.TextOut(X + 5, Y + CellH - TH - 4, Tc);
      { Foreground text }
      Result.Canvas.Font.Color := clWhite;
      Result.Canvas.TextOut(X + 4, Y + CellH - TH - 5, Tc);
    end;
  end;
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

function GetEntryCount(H: TArchiveHandle): Integer;
begin
  if H.Settings.OutputMode = womCombined then
    Result := 1
  else
    Result := Length(H.Offsets);
end;

function GetEntryName(H: TArchiveHandle): string;
begin
  if H.Settings.OutputMode = womCombined then
    Result := GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat)
  else
    Result := GenerateFrameFileName(H.FileName, H.CurrentIndex,
      H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat);
end;

function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: AnsiString;
begin
  H := TArchiveHandle(hArcData);
  if H.CurrentIndex >= GetEntryCount(H) then
    Exit(E_END_ARCHIVE);

  Name := AnsiString(GetEntryName(H));

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
  if H.CurrentIndex >= GetEntryCount(H) then
    Exit(E_END_ARCHIVE);

  Name := GetEntryName(H);

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  StrLCopy(HeaderData.FileName, PChar(Name), Length(HeaderData.FileName) - 1);
  HeaderData.UnpSizeLow := 0;
  HeaderData.FileAttr := $20;

  Result := E_SUCCESS;
end;

function DoExtractSeparate(H: TArchiveHandle;
  const ADestPath, ADestName: string): Integer;
var
  Extractor: IFrameExtractor;
  Bmp: TBitmap;
  FullPath: string;
begin
  if H.CurrentIndex >= Length(H.Offsets) then
    Exit(E_END_ARCHIVE);

  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) +
      GenerateFrameFileName(H.FileName, H.CurrentIndex,
        H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxLog(Format('Extract frame %d -> %s', [H.CurrentIndex, FullPath]));

  Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
  try
    Bmp := Extractor.ExtractFrame(H.FileName,
      H.Offsets[H.CurrentIndex].TimeOffset, H.Settings.UseBmpPipe);
    if Bmp = nil then
      Exit(E_BAD_DATA);
    try
      SaveBitmapToFile(Bmp, FullPath, H.Settings.SaveFormat,
        H.Settings.JpegQuality, H.Settings.PngCompression);
    finally
      Bmp.Free;
    end;
  except
    Exit(E_EWRITE);
  end;
  Result := E_SUCCESS;
end;

function DoExtractCombined(H: TArchiveHandle;
  const ADestPath, ADestName: string): Integer;
var
  Extractor: IFrameExtractor;
  Frames: TArray<TBitmap>;
  Combined: TBitmap;
  FullPath: string;
  I: Integer;
begin
  if ADestName <> '' then
    FullPath := ADestName
  else if ADestPath <> '' then
    FullPath := IncludeTrailingPathDelimiter(ADestPath) +
      GenerateCombinedFileName(H.FileName, H.Settings.SaveFormat)
  else
    Exit(E_ECREATE);

  WcxLog(Format('Extract combined (%d frames) -> %s',
    [Length(H.Offsets), FullPath]));

  Extractor := TFFmpegFrameExtractor.Create(H.FFmpegPath);
  SetLength(Frames, Length(H.Offsets));
  try
    try
      for I := 0 to Length(H.Offsets) - 1 do
        Frames[I] := Extractor.ExtractFrame(H.FileName,
          H.Offsets[I].TimeOffset, H.Settings.UseBmpPipe);

      Combined := RenderCombinedImage(Frames, H.Offsets, H.Settings);
      if Combined = nil then
        Exit(E_BAD_DATA);
      try
        SaveBitmapToFile(Combined, FullPath, H.Settings.SaveFormat,
          H.Settings.JpegQuality, H.Settings.PngCompression);
      finally
        Combined.Free;
      end;
      Result := E_SUCCESS;
    except
      Result := E_EWRITE;
    end;
  finally
    for I := 0 to Length(Frames) - 1 do
      Frames[I].Free;
  end;
end;

function DoProcessFile(hArcData: THandle; Operation: Integer;
  const ADestPath, ADestName: string): Integer;
var
  H: TArchiveHandle;
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

  if H.CurrentIndex >= GetEntryCount(H) then
    Exit(E_END_ARCHIVE);

  if Operation = PK_EXTRACT then
  begin
    if H.Settings.OutputMode = womCombined then
      Result := DoExtractCombined(H, ADestPath, ADestName)
    else
      Result := DoExtractSeparate(H, ADestPath, ADestName);

    if Result <> E_SUCCESS then
    begin
      Inc(H.CurrentIndex);
      Exit;
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
  { PK_CAPS_NEW is a stub to make the Pack dialog (and its Configure button)
    accessible; PackFiles always returns E_NOT_SUPPORTED }
  Result := PK_CAPS_NEW or PK_CAPS_BY_CONTENT or PK_CAPS_SEARCHTEXT
    or PK_CAPS_HIDE or PK_CAPS_OPTIONS;
end;

procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;
begin
  if (dps <> nil) and (dps^.Size >= SizeOf(TWcxDefaultParams)) then
  begin
    GIniPath := ChangeFileExt(string(AnsiString(dps^.DefaultIniName)), '.ini');
    WcxLog(Format('SetDefaultParams: ini=%s', [GIniPath]));
  end;
end;

function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar;
  Flags: Integer): Integer; stdcall;
begin
  Result := E_NOT_SUPPORTED;
end;

procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;
var
  Settings: TWcxSettings;
begin
  Settings := TWcxSettings.Create(GIniPath);
  try
    Settings.Load;
    if ShowWcxSettingsDialog(Parent, Settings) then
      Settings.Save;
  finally
    Settings.Free;
  end;
end;

end.
