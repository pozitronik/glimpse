{WCX plugin exported functions.
 Presents a video file as a virtual archive containing frame images.}
unit uWcxExports;

interface

uses
  System.SysUtils, Winapi.Windows, uWcxAPI;

{Opens archive (video file) for listing or extraction}
function OpenArchive(var ArchiveData: TOpenArchiveData): THandle; stdcall;
function OpenArchiveW(var ArchiveData: TOpenArchiveDataW): THandle; stdcall;

{Reads next file header from archive}
function ReadHeader(hArcData: THandle; var HeaderData: THeaderData): Integer; stdcall;
function ReadHeaderExW(hArcData: THandle; var HeaderData: THeaderDataExW): Integer; stdcall;

{Processes (extracts/skips) the current file}
function ProcessFile(hArcData: THandle; Operation: Integer; DestPath, DestName: PAnsiChar): Integer; stdcall;
function ProcessFileW(hArcData: THandle; Operation: Integer; DestPath, DestName: PWideChar): Integer; stdcall;

{Closes archive handle}
function CloseArchive(hArcData: THandle): Integer; stdcall;

{Callback setters}
procedure SetChangeVolProc(hArcData: THandle; pChangeVolProc: TChangeVolProc); stdcall;
procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
procedure SetProcessDataProcW(hArcData: THandle; pProcessDataProc: TProcessDataProcW); stdcall;

{Reports plugin capabilities}
function GetPackerCaps: Integer; stdcall;

{Receives default INI path from TC}
procedure SetDefaultParams(dps: PWcxDefaultParams); stdcall;

{Stub: packing not supported, exists only to make Configure button accessible}
function PackFiles(PackedFile, SubPath, SrcPath, AddList: PAnsiChar; Flags: Integer): Integer; stdcall;

{Shows configuration dialog}
procedure ConfigurePacker(Parent: HWND; DllInstance: THandle); stdcall;

implementation

uses
  System.AnsiStrings, System.Classes, System.IOUtils,
  uWcxSettings, uWcxSettingsDlg, uFFmpegLocator,
  uFrameExtractor,
  uDebugLog, uTypes,
  uWcxEntryExtractors, uWcxArchiveHandle,
  uWcxFrameCache, uPresetExtractReporter, uWcxErrorMapping,
  uWcxArchiveCoordinator;

var
  GIniPath: string;
  {Production factory instances. Constructed at unit initialization and
   released at finalization. Captured by the per-OpenArchive coordinator
   (which itself lives only for the duration of one call). Lifetime
   spans the DLL load, matching the legacy module-global GIniPath above.}
  GSettingsProvider: IWcxSettingsProvider;
  GProbeService: IProbeService;
  GFrameExtractorFactory: IFrameExtractorFactory;

procedure WcxLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

function DoOpenArchive(const AFileName: string; AOpenMode: Integer; out AOpenResult: Integer): THandle;
var
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
begin
  {Thunk: every open-flow concern (settings load, ffmpeg locate, probe,
   listing build, pre-extract) now lives behind TWcxArchiveCoordinator.
   This thunk's only job is to (1) translate the ABI integer handle to a
   class pointer and back, (2) wire the module-global factory cache into
   the per-call coordinator. Step 100 (C9) of the refactoring campaign.}
  Coord := TWcxArchiveCoordinator.Create(GSettingsProvider, GProbeService, GFrameExtractorFactory);
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
  {Encoding caveat: every ANSI export in this unit converts the incoming
   PAnsiChar via the system code page (string(AnsiString(...))). Paths
   containing characters not representable in the local CP_ACP are
   corrupted at this boundary. The Wide siblings (OpenArchiveW,
   ProcessFileW, ReadHeaderExW) are the supported path; modern TC
   always calls them. The ANSI shims exist for ABI completeness and
   fall back gracefully on plain ASCII paths.}
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
  H := TArchiveHandle(hArcData);
  if H.IsExhausted then
    Exit(E_END_ARCHIVE);

  Name := AnsiString(H.CurrentEntry.FileName);

  FillChar(HeaderData, SizeOf(HeaderData), 0);
  System.AnsiStrings.StrLCopy(HeaderData.FileName, PAnsiChar(Name), SizeOf(HeaderData.FileName) - 1);
  {THeaderData.UnpSize is 32-bit signed; clamp so >2 GB sizes surface as
   MaxInt instead of wrapping into a negative size. The polymorphic
   ReportedSize subsumes the prior "is this a preset? use source-file
   size; else use cached EntrySizes" branching — each entry class
   answers for itself.}
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
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle(hArcData);

  if Operation = PK_SKIP then
  begin
    H.AdvanceCursor;
    Exit(E_SUCCESS);
  end;

  if (Operation <> PK_EXTRACT) and (Operation <> PK_TEST) then
  begin
    H.AdvanceCursor;
    Exit(E_SUCCESS);
  end;

  if H.IsExhausted then
    Exit(E_END_ARCHIVE);

  if Operation = PK_EXTRACT then
  begin
    {Single polymorphic dispatch — TFrameEntry, TCombinedEntry, and
     TPresetEntry each carry the per-entry state (frame index, combined
     slot, preset index) they need and implement Extract themselves. A
     new entry kind becomes one new class, no edits here.}
    Result := H.CurrentEntry.Extract(H, ADestPath, ADestName);

    if Result <> E_SUCCESS then
    begin
      H.AdvanceCursor;
      Exit;
    end;
  end;

  H.AdvanceCursor;
  Result := E_SUCCESS;
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
  {Not used: video files are single-volume}
end;

procedure SetChangeVolProcW(hArcData: THandle; pChangeVolProc: TChangeVolProcW); stdcall;
begin
  {Not used: video files are single-volume. Exported for ABI completeness so
   modern TC builds find the symbol they expect.}
end;

procedure SetProcessDataProc(hArcData: THandle; pProcessDataProc: TProcessDataProc); stdcall;
begin
  {Stored on the handle; the preset extractor invokes it via
   uWcxProgressBridge to surface progress and observe user cancel.
   Legacy per-frame extraction is synchronous and does not call the
   callback.}
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
  {Read-only "video as virtual archive" plugin: no PK_CAPS_NEW (cannot create
   archives), no PK_CAPS_MODIFY/DELETE. PK_CAPS_OPTIONS gives users a
   Configure button in TC's Configuration > Options > Plugins > Packer
   plugins UI; PK_CAPS_BY_CONTENT lets TC probe by content; PK_CAPS_HIDE
   keeps videos shown as ordinary files in the file panel. PK_CAPS_SEARCHTEXT
   is intentionally not set - the virtual archive entries are binary PNG/JPEG
   frames with no text content to search.}
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
begin
  Settings := TWcxSettings.Create(GIniPath);
  try
    Settings.Load;
    if ShowWcxSettingsDialog(Parent, Settings,
      procedure
      begin
        TWcxFrameCache.Instance.Invalidate;
      end) then
    begin
      {ShowWcxSettingsDialog returns True only when TrySaveAll succeeded,
       which already called TWcxSettings.Save AND invoked the apply
       callback (Invalidate above). Keeping the Invalidate here is
       belt-and-braces in case the dialog's contract changes; the
       previous duplicate Settings.Save was removed.}
      TWcxFrameCache.Instance.Invalidate;
    end;
  finally
    Settings.Free;
  end;
end;

initialization

{Fallback: INI next to the DLL, in case SetDefaultParams is not called
 before ConfigurePacker or OpenArchive}
GIniPath := ChangeFileExt(GetModuleName(HInstance), '.ini');

{Production factory wiring for the OpenArchive coordinator. Stateless
 instances; one of each is built once per DLL load and reused for
 every OpenArchive call via the per-call TWcxArchiveCoordinator.}
GSettingsProvider := TProductionWcxSettingsProvider.Create;
GProbeService := TProductionProbeService.Create;
GFrameExtractorFactory := TProductionFrameExtractorFactory.Create;

{Production reporter. Lives in uPresetExtractReporter as a global so
 TPresetEntry.Extract can reach it without back-linking into this unit;
 tests can swap it via SetPresetFailureReporter.}
SetPresetFailureReporter(TMessageBoxFailureReporter.Create);

{Debug logging is opt-in via the hidden "[debug] LogEnabled=1" key in
 Glimpse.ini. Start silent; DoOpenArchive flips TDebugLog.Configure on
 or off each time after reading the setting, so a hand-edit of the INI
 takes effect on the next archive open without a TC restart.}
TDebugLog.Instance.Configure('');

{Seed the global Random once per DLL load. CalculateRandomFrameOffsets
 reads from this RNG; without seeding, every TC session would emit the
 same "random" sequence on this plugin and defeat the user's intent of
 a non-deterministic frame layout.}
Randomize;

finalization

SetPresetFailureReporter(nil);
{Release the factory interfaces in reverse construction order so any
 transitive references between them drop cleanly.}
GFrameExtractorFactory := nil;
GProbeService := nil;
GSettingsProvider := nil;
TWcxFrameCache.ReleaseInstance;

end.
