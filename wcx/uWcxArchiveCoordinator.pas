{Coordinates the WCX OpenArchive flow with injected dependencies.

 DoOpenArchive used to instantiate concrete TWcxSettings / TProbeCache /
 TFFmpegFrameExtractor directly inside the ABI thunk, which made the
 open-flow untestable except through the TWcxTest_* end-to-end seams
 bolted on for the cache layer. This coordinator takes 3 factory
 interfaces at construction; the export shim wires production
 instances at DLL load, tests inject fakes that record what would have
 been done without touching ffmpeg or the filesystem.

 The coordinator does NOT yet absorb DoProcessFile / DoCloseArchive —
 those move in step 101. This step's surface is the open-flow only.}
unit uWcxArchiveCoordinator;

interface

uses
  Winapi.Windows,
  uWcxAPI,
  uWcxSettings,
  uWcxArchiveHandle,
  uFrameExtractor,
  uVideoInfo;

type
  {Builds + loads a TWcxSettings for the given INI path. The
   production impl does TWcxSettings.Create(APath) + Load; tests
   inject fakes returning pre-populated settings without disk I/O.
   The handle takes ownership of the returned instance.
   Method named CreateSettings (not Create) to avoid colliding with
   the inherited TObject.Create constructor on TInterfacedObject
   descendants implementing this interface.}
  IWcxSettingsProvider = interface
    ['{5B68304F-EC3F-4EE0-B518-1280842CD291}']
    function CreateSettings(const AIniPath: string): TWcxSettings;
  end;

  {Probes the source video file via TProbeCache and returns the
   TVideoInfo. The production impl owns a transient TProbeCache that
   exists for the duration of the call; tests inject fakes returning
   pre-computed TVideoInfo. Caller does NOT own a probe-cache
   reference — that lifetime stays internal to the service.}
  IProbeService = interface
    ['{0FD780F7-E3DD-4B6C-8B90-831780F65685}']
    function Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
  end;

  {Coordinator that owns the OpenArchive happy path. Constructor
   captures the 3 factory interfaces; OpenArchive(AFileName, AOpenMode,
   AIniPath, AOpenResult) returns a populated TArchiveHandle or nil + an
   E_xxx code in AOpenResult on failure.

   Lifecycle: callers (DoOpenArchive thunk) construct the coordinator
   once per OpenArchive call, call OpenArchive, then free the
   coordinator. The factories outlive the coordinator (cached in the
   thunk's static state at DLL load).}
  TWcxArchiveCoordinator = class
  strict private
    FSettingsProvider: IWcxSettingsProvider;
    FProbeService: IProbeService;
    FFrameExtractorFactory: IFrameExtractorFactory;
  public
    constructor Create(const ASettingsProvider: IWcxSettingsProvider;
      const AProbeService: IProbeService;
      const AFrameExtractorFactory: IFrameExtractorFactory);
    function OpenArchive(const AFileName: string; AOpenMode: Integer;
      const AIniPath: string;
      out AOpenResult: Integer): TArchiveHandle;

    {Step 101 (C10): centralises the per-call WCX ABI logic that
     previously lived as `DoProcessFile` / `CloseArchive` helpers in
     uWcxExports. Both are stateless against the handle (the handle
     carries everything they need) so they're declared as static class
     methods — no instance, no factory dependencies. The export thunks
     in uWcxExports keep their stdcall ABI marshalling and just call
     these.

     ConfigurePacker stays in uWcxExports deliberately — it talks to
     ShowWcxSettingsDialog (VCL), and moving it would drag the VCL
     dialog unit into the otherwise headless-testable coordinator.
     The original step 101 deferral note documented this coupling-
     taste trade-off; the partial move here respects it.}

    {Advances the handle's cursor for skip/non-extract operations,
     dispatches PK_EXTRACT to the current entry's polymorphic Extract
     method, returns E_END_ARCHIVE when exhausted. Always advances the
     cursor after a successful extract attempt (success or per-entry
     failure) so the next ABI call sees the next entry.}
    class function ProcessFile(AHandle: TArchiveHandle; AOperation: Integer;
      const ADestPath, ADestName: string): Integer; static;

    {Frees the handle's owned Settings instance + the handle itself.
     Settings ownership is the handle's (production CloseArchive path)
     for symmetry with the open-flow's error paths in OpenArchive.}
    class function CloseArchive(AHandle: TArchiveHandle): Integer; static;
  end;

  {Production impls — used by DoOpenArchive at DLL init.}
  TProductionWcxSettingsProvider = class(TInterfacedObject, IWcxSettingsProvider)
    function CreateSettings(const AIniPath: string): TWcxSettings;
  end;

  TProductionProbeService = class(TInterfacedObject, IProbeService)
    function Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uProbeCache, uFFmpegLocator,
  uPathExpand,
  uFrameOffsets,
  uWcxFrameCache,
  uWcxListing,
  uWcxPresets,
  uWcxExtractionController,
  uDebugLog,
  uWcxEntryExtractors;

procedure CoordLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

{TProductionWcxSettingsProvider}

function TProductionWcxSettingsProvider.CreateSettings(const AIniPath: string): TWcxSettings;
begin
  Result := TWcxSettings.Create(AIniPath);
  Result.Load;
end;

{TProductionProbeService}

function TProductionProbeService.Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
var
  ProbeC: TProbeCache;
begin
  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    Result := ProbeC.TryGetOrProbe(AFileName, AFFmpegPath);
  finally
    ProbeC.Free;
  end;
end;

{TWcxArchiveCoordinator}

constructor TWcxArchiveCoordinator.Create(const ASettingsProvider: IWcxSettingsProvider;
  const AProbeService: IProbeService;
  const AFrameExtractorFactory: IFrameExtractorFactory);
begin
  inherited Create;
  FSettingsProvider := ASettingsProvider;
  FProbeService := AProbeService;
  FFrameExtractorFactory := AFrameExtractorFactory;
end;

function TWcxArchiveCoordinator.OpenArchive(const AFileName: string; AOpenMode: Integer;
  const AIniPath: string; out AOpenResult: Integer): TArchiveHandle;
var
  H: TArchiveHandle;
begin
  Result := nil;
  AOpenResult := E_SUCCESS;

  H := TArchiveHandle.Create;
  try
    H.FileName := AFileName;
    H.OpenMode := AOpenMode;
    H.ResetCursor;

    H.Settings := FSettingsProvider.CreateSettings(AIniPath);
    {Apply the hidden debug-log toggle. Kept here (rather than at DLL init)
     so a hand-edit of "[debug] LogEnabled" in Glimpse.ini takes effect on
     the next archive open without forcing a TC restart.}
    if H.Settings.DebugLogEnabled then
      TDebugLog.Instance.Configure(ChangeFileExt(GetModuleName(HInstance), '.log'))
    else
      TDebugLog.Instance.Configure('');

    H.FFmpegPath := FindFFmpegExe(ExtractFilePath(AIniPath), ExpandEnvVars(H.Settings.FFmpegExePath));

    if H.FFmpegPath = '' then
    begin
      AOpenResult := E_EOPEN;
      {Production CloseArchive frees Settings before the handle; the
       error paths here mirror that order so the partially-built handle
       does not leak the TWcxSettings instance the provider just built.}
      H.Settings.Free;
      H.Free;
      Exit;
    end;

    {Per-session collaborators. Constructed once per OpenArchive so
     dependents (TFrameEntry / TCombinedEntry / the pre-extract cache
     path) reuse the same instances across the session.}
    H.FrameExtractor := FFrameExtractorFactory.CreateExtractor(H.FFmpegPath);
    H.BitmapSaver := TVclBitmapSaverRouter.Create;

    H.VideoInfo := FProbeService.Probe(AFileName, H.FFmpegPath);

    if not H.VideoInfo.IsValid then
    begin
      AOpenResult := E_BAD_ARCHIVE;
      H.Settings.Free;
      H.Free;
      Exit;
    end;

    H.Offsets := BuildFrameOffsets(H.VideoInfo.Duration, H.Settings.FramesCount, H.Settings.SkipEdgesPercent, H.Settings.RandomPercent, H.Settings.RandomExtraction);
    H.FileTime := DateTimeToFileDate(TFile.GetLastWriteTime(AFileName));
    {Captured once so subsequent ReadHeader / DoExtractPreset reads stay
     consistent even if the source file changes mid-session.}
    try
      H.SourceFileSize := TFile.GetSize(AFileName);
    except
      H.SourceFileSize := 0;
    end;

    {Load presets only when their bit is set in the Mode mask so legacy
     installs skip the IO entirely. The listing builder still runs
     unconditionally because it produces the same legacy-only output
     when the preset array is empty.}
    if H.Settings.ShowPresets then
    begin
      H.Presets := LoadPresets(PresetsIniPath(AIniPath));
      CoordLog(Format('Presets: ShowPresets=ON, path="%s", loaded=%d', [PresetsIniPath(AIniPath), Length(H.Presets)]));
    end
    else
      CoordLog(Format('Presets: ShowPresets=OFF (read from "%s")', [AIniPath]));
    H.Listing := BuildArchiveListing(H.FileName, H.Offsets, H.Settings.ShowFrames, H.Settings.ShowCombined, H.Settings.ShowPresets, H.Settings.SaveFormat, H.Presets);

    if H.Settings.ShowFileSizes then
      PreExtractFrames(H);

    CoordLog(Format('OpenArchive: %s mode=%d frames=%d presets=%d', [AFileName, H.Settings.Mode, Length(H.Offsets), Length(H.Presets)]));
    Result := H;
  except
    {Settings may already have been wired before the exception fired;
     free it explicitly here because the handle does not own it (the
     production CloseArchive path frees it before TArchiveHandle).}
    if (H <> nil) and (H.Settings <> nil) then
      H.Settings.Free;
    H.Free;
    {PreExtractFrames may have populated GCachedVideoFile / GCachedTempDir
     and started writing temp files before the exception. Without this
     reset, a subsequent OpenArchive on the same video file would treat the
     partial directory as a cache hit and serve garbage entries (or trip
     over missing temp files mid-extraction).}
    TWcxFrameCache.Instance.Invalidate;
    AOpenResult := E_BAD_ARCHIVE;
  end;
end;

class function TWcxArchiveCoordinator.ProcessFile(AHandle: TArchiveHandle;
  AOperation: Integer; const ADestPath, ADestName: string): Integer;
begin
  if AOperation = PK_SKIP then
  begin
    AHandle.AdvanceCursor;
    Exit(E_SUCCESS);
  end;

  if (AOperation <> PK_EXTRACT) and (AOperation <> PK_TEST) then
  begin
    AHandle.AdvanceCursor;
    Exit(E_SUCCESS);
  end;

  if AHandle.IsExhausted then
    Exit(E_END_ARCHIVE);

  if AOperation = PK_EXTRACT then
  begin
    {Single polymorphic dispatch — TFrameEntry, TCombinedEntry, and
     TPresetEntry each carry the per-entry state (frame index, combined
     slot, preset index) they need and implement Extract themselves. A
     new entry kind becomes one new class, no edits here.}
    Result := AHandle.CurrentEntry.Extract(AHandle, ADestPath, ADestName);

    if Result <> E_SUCCESS then
    begin
      AHandle.AdvanceCursor;
      Exit;
    end;
  end;

  AHandle.AdvanceCursor;
  Result := E_SUCCESS;
end;

class function TWcxArchiveCoordinator.CloseArchive(AHandle: TArchiveHandle): Integer;
begin
  CoordLog(Format('CloseArchive: %s', [AHandle.FileName]));
  AHandle.Settings.Free;
  AHandle.Free;
  Result := E_SUCCESS;
end;

end.
