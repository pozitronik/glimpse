{WCX plugin exported functions. Presents a video file as a virtual
 archive containing frame images.}
unit WcxExports;

interface

uses
  System.SysUtils, Winapi.Windows, WcxAPI;

function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;

function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;

function ProcessFile(hArcData: THandle; Operation: Integer; DestPath, DestName: PAnsiChar): Integer; stdcall;
function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;

function CloseArchive(hArcData: THandle): Integer; stdcall;

procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;

function GetPackerCaps: Integer; stdcall;

procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;

{Stub: packing not supported, exported only to make TC enable the
 Configure button.}
function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar; Flags: Integer): Integer; stdcall;

procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;

implementation

uses
  System.AnsiStrings, System.Classes, System.IOUtils,
  WcxSettings, WcxSettingsDlg, FFmpegLocator,
  FrameExtractor, FFmpegExe,
  Logging, Types,
  WcxEntryExtractors, WcxArchiveHandle,
  WcxFrameCache, PresetExtractReporter, WcxErrorMapping,
  WcxArchiveCoordinator,
  WcxPresets, WcxSettingsRepository, WcxPresetsRepository;

var
  GIniPath: string;
  {Stateless production factories, built once per DLL load and captured
   by each per-call TWcxArchiveCoordinator.}
  GSettingsProvider: IWcxSettingsProvider;
  GProbeService: IProbeService;
  GFrameExtractorFactory: IFrameExtractorFactory;
  GBitmapSaver: IBitmapSaverRouter;
  GFailureReporter: IPresetExtractFailureReporter;

procedure WcxLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

function DoOpenArchive(const AFileName: string; AOpenMode: Integer; out AOpenResult: Integer): THandle;
var
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
begin
  {Thunk: only translates the ABI integer handle to a class pointer and
   wires the module-global factories into the per-call coordinator.}
  Coord := TWcxArchiveCoordinator.Create(GSettingsProvider, GProbeService, GFrameExtractorFactory, GBitmapSaver, TWcxFrameCache.Instance, GFailureReporter);
  try
    H := Coord.OpenArchive(AFileName, AOpenMode, GIniPath, AOpenResult);
    if H <> nil then
      Result := THandle(H)
    else
      Result := 0;
  finally
    Coord.Free;
  end;
end;

function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
begin
  {ANSI exports convert via the system code page; paths with characters
   outside CP_ACP corrupt here. The Wide siblings are the supported
   path; modern TC always calls them. Kept for ABI completeness.}
  Result := DoOpenArchive(string(AnsiString(ArchiveData.ArcName)), ArchiveData.OpenMode, ArchiveData.OpenResult);
end;

function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;
begin
  Result := DoOpenArchive(ArchiveData.ArcName, ArchiveData.OpenMode, ArchiveData.OpenResult);
end;

function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: AnsiString;
begin
  if hArcData = 0 then
    Exit(E_BAD_ARCHIVE);
  H := TArchiveHandle(hArcData);
  if H.IsExhausted then
    Exit(E_END_ARCHIVE);

  Name := AnsiString(H.CurrentEntry.FileName);

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  System.AnsiStrings.StrLCopy(HeaderData.FileName, PAnsiChar(Name), SizeOf(HeaderData.FileName) - 1);
  {THeaderData.UnpSize is 32-bit signed; clamp so >2 GB surfaces as
   MaxInt instead of wrapping negative.}
  HeaderData.UnpSize := ClampSizeForAnsiHeader(H.CurrentEntry.ReportedSize(H, H.CurrentEntryIndex));
  HeaderData.FileTime := H.FileTime;
  HeaderData.FileAttr := FILE_ATTRIBUTE_ARCHIVE;

  Result := E_SUCCESS;
end;

function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;
var
  H: TArchiveHandle;
  Name: string;
  Size: Int64;
begin
  if hArcData = 0 then
    Exit(E_BAD_ARCHIVE);
  H := TArchiveHandle(hArcData);
  if H.IsExhausted then
    Exit(E_END_ARCHIVE);

  Name := H.CurrentEntry.FileName;

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  StrLCopy(HeaderData.FileName, PChar(Name), Length(HeaderData.FileName) - 1);
  Size := H.CurrentEntry.ReportedSize(H, H.CurrentEntryIndex);
  HeaderData.UnpSize := DWORD(Size);
  HeaderData.UnpSizeHigh := DWORD(Size shr 32);
  HeaderData.FileTime := H.FileTime;
  HeaderData.FileAttr := FILE_ATTRIBUTE_ARCHIVE;

  Result := E_SUCCESS;
end;

function DoProcessFile(hArcData: THandle; Operation: Integer; const ADestPath, ADestName: string): Integer;
begin
  Result := TWcxArchiveCoordinator.ProcessFile(TArchiveHandle(hArcData),
    Operation, ADestPath, ADestName);
end;

function ProcessFile(hArcData: THandle; Operation: Integer; DestPath, DestName: PAnsiChar): Integer; stdcall;
var
  SPath, SName: string;
begin
  if DestPath <> nil then
    SPath := string(AnsiString(DestPath))
  else
    SPath := '';
  if DestName <> nil then
    SName := string(AnsiString(DestName))
  else
    SName := '';
  Result := DoProcessFile(hArcData, Operation, SPath, SName);
end;

function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;
var
  SPath, SName: string;
begin
  if DestPath <> nil then
    SPath := DestPath
  else
    SPath := '';
  if DestName <> nil then
    SName := DestName
  else
    SName := '';
  Result := DoProcessFile(hArcData, Operation, SPath, SName);
end;

function CloseArchive(hArcData: THandle): Integer; stdcall;
begin
  Result := TWcxArchiveCoordinator.CloseArchive(TArchiveHandle(hArcData));
end;

procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
begin
  {No-op: video files are single-volume.}
end;

procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
begin
  {No-op: video files are single-volume. Exported so modern TC finds the
   symbol it expects.}
end;

procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
begin
  {Stored on the handle for the preset extractor to invoke via
   WcxProgressBridge. Per-frame extraction is synchronous and does not
   touch this callback.}
  if hArcData = 0 then
    Exit;
  TArchiveHandle(hArcData).ProcessDataProc := pProcessDataProc;
end;

procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;
begin
  if hArcData = 0 then
    Exit;
  TArchiveHandle(hArcData).ProcessDataProcW := pProcessDataProc;
end;

function GetPackerCaps: Integer; stdcall;
begin
  {BY_CONTENT lets TC probe; HIDE keeps videos shown as ordinary files
   in the panel; OPTIONS surfaces the Configure button. SEARCHTEXT is
   omitted because the entries are binary frames.}
  Result := PK_CAPS_BY_CONTENT or PK_CAPS_HIDE or PK_CAPS_OPTIONS;
end;

procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;
begin
  if (dps <> nil) and (dps^.Size >= SizeOf(TWcxDefaultParams)) then
  begin
    GIniPath := ChangeFileExt(string(AnsiString(dps^.DefaultIniName)), '.ini');
    WcxLog(Format('SetDefaultParams: ini=%s', [GIniPath]));
  end;
end;

function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar; Flags: Integer): Integer; stdcall;
begin
  Result := E_NOT_SUPPORTED;
end;

procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;
var
  Settings: TWcxSettings;
  SettingsRepo: IWcxSettingsRepository;
  {One concrete repository implements both reader and writer; binding
   each role to its own typed local avoids a runtime as-cast that would
   crash if a future variant implemented only one side.}
  PresetsRepo: TProductionWcxPresetsRepository;
  PresetsReader: IWcxPresetsReader;
  PresetsWriter: IWcxPresetsWriter;
begin
  Settings := TWcxSettings.Create(GIniPath);
  try
    Settings.Load;
    SettingsRepo := TProductionWcxSettingsRepository.Create;
    PresetsRepo := TProductionWcxPresetsRepository.Create(PresetsIniPath(GIniPath));
    PresetsReader := PresetsRepo;
    PresetsWriter := PresetsRepo;
    if ShowWcxSettingsDialog(Parent, Settings, SettingsRepo, PresetsReader, PresetsWriter,
      procedure
      begin
        TWcxFrameCache.Instance.Invalidate;
      end) then
    begin
      {Belt-and-braces: the apply callback above already invalidated;
       this guards against a future change to the dialog's contract.}
      TWcxFrameCache.Instance.Invalidate;
    end;
  finally
    Settings.Free;
  end;
end;

initialization

{Fallback: INI next to the DLL, in case SetDefaultParams is not called
 before ConfigurePacker or OpenArchive.}
GIniPath := ChangeFileExt(GetModuleName(HInstance), '.ini');

GSettingsProvider := TProductionWcxSettingsProvider.Create;
GProbeService := TProductionProbeService.Create;
GFrameExtractorFactory := TProductionFrameExtractorFactory.Create;
GBitmapSaver := TVclBitmapSaverRouter.Create;
GFailureReporter := TMessageBoxFailureReporter.Create;

{Start silent. DoOpenArchive re-reads the "[debug] LogEnabled" key on
 every open so a hand-edit takes effect without restarting TC.}
TDebugLog.Instance.Configure('');

{Seeds the global RNG used by CalculateRandomFrameOffsets; without
 this, every TC session would emit the same "random" sequence.}
Randomize;

finalization

{Reverse construction order so any transitive references drop cleanly.}
GFailureReporter := nil;
GBitmapSaver := nil;
GFrameExtractorFactory := nil;
GProbeService := nil;
GSettingsProvider := nil;
TWcxFrameCache.ReleaseInstance;

end.
