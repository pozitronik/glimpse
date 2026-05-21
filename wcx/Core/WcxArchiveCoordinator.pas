{Owns the WCX OpenArchive flow. Production exports inject concrete
 factories; tests inject fakes.}
unit WcxArchiveCoordinator;

interface

uses
  Winapi.Windows,
  WcxAPI,
  WcxSettings,
  WcxArchiveHandle,
  FrameExtractor,
  VideoInfo;

type
  {Caller takes ownership of the returned instance. Named CreateSettings
   (not Create) to avoid colliding with TObject.Create on
   TInterfacedObject implementers.}
  IWcxSettingsProvider = interface
    ['{5B68304F-EC3F-4EE0-B518-1280842CD291}']
    function CreateSettings(const AIniPath: string): TWcxSettings;
  end;

  {Caller does not own a probe-cache reference; that lifetime stays
   internal to the service.}
  IProbeService = interface
    ['{0FD780F7-E3DD-4B6C-8B90-831780F65685}']
    function Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
  end;

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
    class function ProcessFile(AHandle: TArchiveHandle; AOperation: Integer;
      const ADestPath, ADestName: string): Integer; static;
    class function CloseArchive(AHandle: TArchiveHandle): Integer; static;
  end;

  TProductionWcxSettingsProvider = class(TInterfacedObject, IWcxSettingsProvider)
    function CreateSettings(const AIniPath: string): TWcxSettings;
  end;

  TProductionProbeService = class(TInterfacedObject, IProbeService)
    function Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  ProbeCache, FFmpegLocator, FFmpegExe, VideoProbing,
  PathExpand,
  FrameOffsets,
  WcxFrameCache,
  WcxListing,
  WcxPresets,
  WcxExtractionController,
  Logging,
  WcxEntryExtractors;

procedure CoordLog(const AMsg: string);
begin
  DebugLog('WCX', AMsg);
end;

{Re-read on each open so hand-edits to [debug] LogEnabled in Glimpse.ini
 take effect without restarting TC.}
procedure ConfigureDebugLog(ASettings: TWcxSettings);
begin
  if ASettings.DebugLogEnabled then
    TDebugLog.Instance.Configure(ChangeFileExt(GetModuleName(HInstance), '.log'))
  else
    TDebugLog.Instance.Configure('');
end;

function ResolveFFmpegPath(ASettings: TWcxSettings; const AIniPath: string): string;
begin
  Result := FindFFmpegExe(ExtractFilePath(AIniPath), ExpandEnvVars(ASettings.FFmpegExePath));
end;

{Captured once so subsequent reads stay consistent if the source file
 changes mid-session.}
procedure CaptureSourceFileMetadata(AHandle: TArchiveHandle; const AFileName: string);
begin
  AHandle.FileTime := DateTimeToFileDate(TFile.GetLastWriteTime(AFileName));
  try
    AHandle.SourceFileSize := TFile.GetSize(AFileName);
  except
    AHandle.SourceFileSize := 0;
  end;
end;

{Skip preset IO when ShowPresets is off so legacy installs avoid the disk
 read.}
function LoadPresetsForOpen(ASettings: TWcxSettings; const AIniPath: string): TWcxPresetArray;
begin
  if ASettings.ShowPresets then
  begin
    Result := LoadPresets(PresetsIniPath(AIniPath));
    CoordLog(Format('Presets: ShowPresets=ON, path="%s", loaded=%d', [PresetsIniPath(AIniPath), Length(Result)]));
  end
  else
  begin
    Result := nil;
    CoordLog(Format('Presets: ShowPresets=OFF (read from "%s")', [AIniPath]));
  end;
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
  ProbeC: IProbeCache;
  Prober: IVideoProber;
begin
  ProbeC := CreateProbeCache;
  Prober := TFFmpegExe.Create(AFFmpegPath);
  Result := ProbeC.TryGetOrProbe(AFileName, Prober);
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
    ConfigureDebugLog(H.Settings);

    H.FFmpegPath := ResolveFFmpegPath(H.Settings, AIniPath);

    if H.FFmpegPath = '' then
    begin
      AOpenResult := E_EOPEN;
      {Handle does not own Settings; free explicitly to prevent leak.}
      H.Settings.Free;
      H.Free;
      Exit;
    end;

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
    CaptureSourceFileMetadata(H, AFileName);
    H.Presets := LoadPresetsForOpen(H.Settings, AIniPath);
    H.Listing := BuildArchiveListing(H.FileName, H.Offsets, H.Settings.ShowFrames, H.Settings.ShowCombined, H.Settings.ShowPresets, H.Settings.SaveFormat, H.Presets);

    if H.Settings.ShowFileSizes then
      PreExtractFrames(H);

    CoordLog(Format('OpenArchive: %s mode=%d frames=%d presets=%d', [AFileName, H.Settings.Mode, Length(H.Offsets), Length(H.Presets)]));
    Result := H;
  except
    if (H <> nil) and (H.Settings <> nil) then
      H.Settings.Free;
    H.Free;
    {PreExtractFrames may have populated partial cache state; invalidate
     so the next OpenArchive does not treat it as a cache hit.}
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
