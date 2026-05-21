{Tests for TWcxArchiveCoordinator + IWcxSettingsProvider / IProbeService.

 Pin the DI contract: the coordinator defers settings build, video
 probing, and frame-extractor construction to its collaborators
 rather than instantiating concrete types itself.

 The flow still touches the filesystem (TFile.GetLastWriteTime /
 GetSize on the source video, and FindFFmpegExe expects ffmpeg.exe
 on disk). Tests set up a temp directory with a synthetic zero-byte
 ffmpeg.exe stub and a synthetic source video; the coordinator never
 invokes ffmpeg because the probe service is faked.

 ShowFileSizes / ShowPresets are left False so PreExtractFrames
 (which would launch ffmpeg) and LoadPresets (which would need a
 presets.ini) are skipped.}
unit TestWcxArchiveCoordinator;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxArchiveCoordinator = class
  private
    FTempDir: string;
    FFFmpegStubPath: string;
    FVideoPath: string;
    FIniPath: string;
    procedure CleanUp;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    {Happy path: all 3 fakes return success; the coordinator returns a
     populated TArchiveHandle with Settings / VideoInfo / FrameExtractor
     all set. AOpenResult is E_SUCCESS.}
    [Test] procedure TestOpenArchive_HappyPath_ReturnsPopulatedHandle;

    {Invalid video info path: the probe service returns a TVideoInfo
     with Duration <= 0 (i.e. IsValid = False). Coordinator must short-
     circuit with E_BAD_ARCHIVE, return nil, and free the partial handle
     so no leak.}
    [Test] procedure TestOpenArchive_InvalidVideoInfo_ReturnsBadArchive;

    {Settings provider is the sole source of the TWcxSettings instance —
     the coordinator must not call TWcxSettings.Create itself. Verified
     by the recording fake's call-count being exactly 1 with the right
     INI path argument.}
    [Test] procedure TestOpenArchive_SettingsProviderInjected_NotConstructedInternally;

    {Frame extractor factory is the sole source of the IFrameExtractor —
     and is invoked with the path that FindFFmpegExe produced, not the
     raw configured path. Verified by the recording fake's call-count
     and the captured path argument matching FFFmpegStubPath.}
    [Test] procedure TestOpenArchive_FrameExtractorFactoryInjected_NotConstructedInternally;

    {Handle population: Offsets / FileTime / SourceFileSize / Listing
     are all set on success. Listing length must equal FramesCount
     (because ShowFrames=True and the other two Show* are False).}
    [Test] procedure TestOpenArchive_PopulatesArchiveHandleFields;

    {Probe service is asked for the video info exactly once and is
     handed the source file path along with the resolved FFmpeg path
     (not the configured-but-unresolved INI value).}
    [Test] procedure TestOpenArchive_ProbeService_CalledOnceWithResolvedFFmpegPath;

    {Bitmap-saver router is injected: the coordinator wires the supplied
     IBitmapSaverRouter onto the handle rather than constructing its own.}
    [Test] procedure TestOpenArchive_BitmapSaverRouterInjected_NotConstructedInternally;

    {On an OpenArchive exception the coordinator invalidates the injected
     IWcxFrameCache, not the TWcxFrameCache singleton.}
    [Test] procedure TestOpenArchive_OnException_InvalidatesInjectedFrameCache;

    {ProcessFile + CloseArchive are class methods — stateless against
     the handle.}
    [Test] procedure TestProcessFile_PKSkip_AdvancesCursorReturnsSuccess;
    [Test] procedure TestProcessFile_NonExtractOp_AdvancesCursorReturnsSuccess;
    [Test] procedure TestProcessFile_Exhausted_ReturnsEndArchive;
    [Test] procedure TestProcessFile_PKExtract_DispatchesToEntryExtract;
    [Test] procedure TestProcessFile_PKExtract_AdvancesCursorAfterSuccess;
    [Test] procedure TestProcessFile_PKExtract_OnFailure_AdvancesCursorReturnsErrorCode;
    [Test] procedure TestCloseArchive_FreesHandleAndSettings_ReturnsSuccess;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Winapi.Windows, Vcl.Graphics,
  Types, WcxAPI, WcxArchiveHandle, WcxSettings, WcxEntryExtractors, WcxFrameCache,
  FrameExtractor, VideoInfo,
  WcxArchiveCoordinator;

const
  TEST_FRAMES_COUNT = 5;
  TEST_DURATION = 120.0;
  TEST_WIDTH = 1920;
  TEST_HEIGHT = 1080;

type
  {Recording fake settings provider. CreateSettings returns a fresh
   TWcxSettings the caller (the handle) takes ownership of, populated
   with the values the test fixture set on the fake before exercising
   the coordinator. CallCount / LastIniPath give the assertions their
   pinning points.}
  TFakeSettingsProvider = class(TInterfacedObject, IWcxSettingsProvider)
  strict private
    FCallCount: Integer;
    FLastIniPath: string;
    FFFmpegExePath: string;
    FFramesCount: Integer;
    FShowFrames: Boolean;
    FShowCombined: Boolean;
    FShowPresets: Boolean;
    FShowFileSizes: Boolean;
  public
    constructor Create;
    function CreateSettings(const AIniPath: string): TWcxSettings;
    property CallCount: Integer read FCallCount;
    property LastIniPath: string read FLastIniPath;
    property FFmpegExePath: string read FFFmpegExePath write FFFmpegExePath;
    property FramesCount: Integer read FFramesCount write FFramesCount;
    property ShowFrames: Boolean read FShowFrames write FShowFrames;
    property ShowCombined: Boolean read FShowCombined write FShowCombined;
    property ShowPresets: Boolean read FShowPresets write FShowPresets;
    property ShowFileSizes: Boolean read FShowFileSizes write FShowFileSizes;
  end;

  {Recording fake probe service. Returns a canned TVideoInfo configured
   per-test via the public ResultInfo field.}
  TFakeProbeService = class(TInterfacedObject, IProbeService)
  strict private
    FCallCount: Integer;
    FLastFileName: string;
    FLastFFmpegPath: string;
    FResultInfo: TVideoInfo;
  public
    function Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
    property CallCount: Integer read FCallCount;
    property LastFileName: string read FLastFileName;
    property LastFFmpegPath: string read FLastFFmpegPath;
    property ResultInfo: TVideoInfo read FResultInfo write FResultInfo;
  end;

  {Recording stub IFrameExtractor for the fake factory below. Never
   actually extracts a frame — the open flow does not call ExtractFrame,
   it only stores the extractor on the handle for later use by entry
   extractors (which this test does not exercise).}
  TStubFrameExtractor = class(TInterfacedObject, IFrameExtractor)
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  TFakeFrameExtractorFactory = class(TInterfacedObject, IFrameExtractorFactory)
  strict private
    FCallCount: Integer;
    FLastFFmpegPath: string;
  public
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
    property CallCount: Integer read FCallCount;
    property LastFFmpegPath: string read FLastFFmpegPath;
  end;

  {Fake IWcxFrameCache: counts Invalidate so the except-path test can
   pin that the coordinator invalidates the injected cache rather than
   the TWcxFrameCache singleton.}
  TFakeWcxFrameCache = class(TInterfacedObject, IWcxFrameCache)
  strict private
    FInvalidateCallCount: Integer;
  public
    procedure Invalidate;
    function BeginExtractionSession: TWcxCacheExtractionSession;
    property InvalidateCallCount: Integer read FInvalidateCallCount;
  end;

{TFakeSettingsProvider}

constructor TFakeSettingsProvider.Create;
begin
  inherited;
  FFramesCount := TEST_FRAMES_COUNT;
  FShowFrames := True;
end;

function TFakeSettingsProvider.CreateSettings(const AIniPath: string): TWcxSettings;
begin
  Inc(FCallCount);
  FLastIniPath := AIniPath;
  Result := TWcxSettings.Create(AIniPath);
  {Skip Load — point of the fake. Apply only the per-test field overrides
   so the coordinator's downstream reads see deterministic values.}
  Result.FFmpegExePath := FFFmpegExePath;
  Result.FramesCount := FFramesCount;
  Result.ShowFrames := FShowFrames;
  Result.ShowCombined := FShowCombined;
  Result.ShowPresets := FShowPresets;
  Result.ShowFileSizes := FShowFileSizes;
end;

{TFakeProbeService}

function TFakeProbeService.Probe(const AFileName, AFFmpegPath: string): TVideoInfo;
begin
  Inc(FCallCount);
  FLastFileName := AFileName;
  FLastFFmpegPath := AFFmpegPath;
  Result := FResultInfo;
end;

{TStubFrameExtractor}

function TStubFrameExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
begin
  Result := nil;
end;

{TFakeFrameExtractorFactory}

function TFakeFrameExtractorFactory.CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
begin
  Inc(FCallCount);
  FLastFFmpegPath := AFFmpegPath;
  Result := TStubFrameExtractor.Create;
end;

{TFakeWcxFrameCache}

procedure TFakeWcxFrameCache.Invalidate;
begin
  Inc(FInvalidateCallCount);
end;

function TFakeWcxFrameCache.BeginExtractionSession: TWcxCacheExtractionSession;
begin
  {Unreached: these tests leave ShowFileSizes=False so PreExtractFrames
   never runs.}
  Result := nil;
end;

{Helper: builds a deterministic valid TVideoInfo. Caller may override
 fields on the returned record before assigning to a fake.}
function MakeValidVideoInfo: TVideoInfo;
begin
  Result := Default(TVideoInfo);
  Result.Duration := TEST_DURATION;
  Result.Width := TEST_WIDTH;
  Result.Height := TEST_HEIGHT;
  Result.SampleAspectN := 1;
  Result.SampleAspectD := 1;
  Result.DisplayWidth := TEST_WIDTH;
  Result.DisplayHeight := TEST_HEIGHT;
  Result.Fps := 30.0;
end;

{TTestWcxArchiveCoordinator}

procedure TTestWcxArchiveCoordinator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'Glimpse_TestWcxArchiveCoord_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  {Synthetic ffmpeg.exe — zero bytes; FindFFmpegExe only checks for
   existence, and the probe service is faked so the file is never
   invoked. Placing it in the same dir as the INI lets FindFFmpegExe's
   "plugin directory" branch resolve it.}
  FFFmpegStubPath := TPath.Combine(FTempDir, 'ffmpeg.exe');
  TFile.WriteAllBytes(FFFmpegStubPath, []);
  {Synthetic source video file — must exist on disk for
   TFile.GetLastWriteTime / GetSize to succeed inside OpenArchive.}
  FVideoPath := TPath.Combine(FTempDir, 'sample.mp4');
  TFile.WriteAllText(FVideoPath, 'synthetic video bytes');
  FIniPath := TPath.Combine(FTempDir, 'Glimpse.ini');
end;

procedure TTestWcxArchiveCoordinator.TearDown;
begin
  CleanUp;
end;

procedure TTestWcxArchiveCoordinator.CleanUp;
begin
  try
    if TDirectory.Exists(FTempDir) then
      TDirectory.Delete(FTempDir, True);
  except
    {Best-effort cleanup}
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_HappyPath_ReturnsPopulatedHandle;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, TVclBitmapSaverRouter.Create, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    try
      Assert.AreEqual(Integer(E_SUCCESS), OpenResult, 'AOpenResult must signal success');
      Assert.IsNotNull(H, 'Handle must be returned on the happy path');
      Assert.IsNotNull(H.Settings, 'Settings must be wired onto the handle');
      Assert.IsNotNull(H.FrameExtractor, 'FrameExtractor must be wired onto the handle');
      Assert.AreEqual(TEST_DURATION, H.VideoInfo.Duration, 0.001, 'VideoInfo must carry the probe-service payload');
    finally
      if H <> nil then
      begin
        H.Settings.Free;
        H.Free;
      end;
    end;
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_InvalidVideoInfo_ReturnsBadArchive;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
  Info: TVideoInfo;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  {Invalid info: Duration <= 0 → IsValid returns False. The coordinator
   must convert this into E_BAD_ARCHIVE without raising.}
  Info := Default(TVideoInfo);
  Info.Duration := 0;
  ProbeService.ResultInfo := Info;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, TVclBitmapSaverRouter.Create, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    Assert.AreEqual(Integer(E_BAD_ARCHIVE), OpenResult, 'Invalid video info must surface as E_BAD_ARCHIVE');
    Assert.IsNull(H, 'No handle must be returned when probe yields invalid info (coordinator frees the partial handle)');
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_SettingsProviderInjected_NotConstructedInternally;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, TVclBitmapSaverRouter.Create, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    try
      Assert.AreEqual(1, SettingsProvider.CallCount,
        'Settings must be built via the injected provider exactly once per OpenArchive call');
      Assert.AreEqual(FIniPath, SettingsProvider.LastIniPath,
        'The INI path passed to OpenArchive must be threaded into the provider');
    finally
      if H <> nil then
      begin
        H.Settings.Free;
        H.Free;
      end;
    end;
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_FrameExtractorFactoryInjected_NotConstructedInternally;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, TVclBitmapSaverRouter.Create, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    try
      Assert.AreEqual(1, ExtractorFactory.CallCount,
        'Frame extractor must be built via the injected factory exactly once');
      Assert.AreEqual(FFFmpegStubPath, ExtractorFactory.LastFFmpegPath,
        'Factory must receive the resolved ffmpeg path, not the configured value');
    finally
      if H <> nil then
      begin
        H.Settings.Free;
        H.Free;
      end;
    end;
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_PopulatesArchiveHandleFields;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
  ExpectedSize: Int64;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;
  ExpectedSize := TFile.GetSize(FVideoPath);

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, TVclBitmapSaverRouter.Create, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    try
      Assert.AreEqual(Integer(E_SUCCESS), OpenResult, 'Open must succeed for the field-population assertions to hold');
      Assert.AreEqual<Integer>(TEST_FRAMES_COUNT, Length(H.Offsets), 'Offsets must be built with the configured FramesCount');
      Assert.AreEqual<Integer>(TEST_FRAMES_COUNT, Length(H.Listing), 'Listing must produce one entry per frame when ShowFrames=True');
      Assert.AreEqual(ExpectedSize, H.SourceFileSize, 'SourceFileSize must reflect the on-disk source file size');
      Assert.IsTrue(H.FileTime <> 0, 'FileTime must be captured from the source file');
    finally
      if H <> nil then
      begin
        H.Settings.Free;
        H.Free;
      end;
    end;
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_ProbeService_CalledOnceWithResolvedFFmpegPath;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, TVclBitmapSaverRouter.Create, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    try
      Assert.AreEqual(1, ProbeService.CallCount,
        'Probe service must be invoked exactly once per OpenArchive');
      Assert.AreEqual(FVideoPath, ProbeService.LastFileName,
        'Probe service must receive the source video file path');
      Assert.AreEqual(FFFmpegStubPath, ProbeService.LastFFmpegPath,
        'Probe service must receive the resolved ffmpeg path, not the raw INI value');
    finally
      if H <> nil then
      begin
        H.Settings.Free;
        H.Free;
      end;
    end;
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_BitmapSaverRouterInjected_NotConstructedInternally;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  Router: IBitmapSaverRouter;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
begin
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;
  Router := TVclBitmapSaverRouter.Create;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory, Router, TFakeWcxFrameCache.Create);
  try
    H := Coord.OpenArchive(FVideoPath, 0, FIniPath, OpenResult);
    try
      Assert.IsNotNull(H, 'Open must succeed for the injection assertion to hold');
      Assert.IsTrue(H.BitmapSaver = Router,
        'Handle must carry the injected router, not a coordinator-constructed one');
    finally
      if H <> nil then
      begin
        H.Settings.Free;
        H.Free;
      end;
    end;
  finally
    Coord.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestOpenArchive_OnException_InvalidatesInjectedFrameCache;
var
  SettingsProvider: TFakeSettingsProvider;
  ProbeService: TFakeProbeService;
  ExtractorFactory: TFakeFrameExtractorFactory;
  FrameCache: TFakeWcxFrameCache;
  Coord: TWcxArchiveCoordinator;
  H: TArchiveHandle;
  OpenResult: Integer;
begin
  {A non-existent source file makes CaptureSourceFileMetadata raise, so
   OpenArchive runs its except handler. DIP-4: that handler must
   invalidate the injected IWcxFrameCache, not reach the singleton.}
  SettingsProvider := TFakeSettingsProvider.Create;
  ProbeService := TFakeProbeService.Create;
  ExtractorFactory := TFakeFrameExtractorFactory.Create;
  ProbeService.ResultInfo := MakeValidVideoInfo;
  FrameCache := TFakeWcxFrameCache.Create;

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService,
    ExtractorFactory, TVclBitmapSaverRouter.Create, FrameCache);
  try
    H := Coord.OpenArchive(TPath.Combine(FTempDir, 'no_such_video.mp4'), 0,
      FIniPath, OpenResult);
    Assert.IsNull(H, 'A mid-open exception must yield no handle');
    Assert.AreEqual(Integer(E_BAD_ARCHIVE), OpenResult,
      'A mid-open exception must surface as E_BAD_ARCHIVE');
    Assert.AreEqual(1, FrameCache.InvalidateCallCount,
      'The except handler must invalidate the injected frame cache');
  finally
    Coord.Free;
  end;
end;

{ProcessFile + CloseArchive are stateless against the handle, so
 these tests skip the coordinator instance + factories and drive the
 class methods directly with a TArchiveHandle + synthetic Listing.
 TStubEntry below records Extract invocations and returns a
 configurable code.}

type
  TStubEntry = class(TInterfacedObject, IWcxEntryExtractor)
  strict private
    FExtractCallCount: Integer;
    FExtractResult: Integer;
    FLastDestPath: string;
    FLastDestName: string;
  public
    constructor Create(AResult: Integer);
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
    property ExtractCallCount: Integer read FExtractCallCount;
    property LastDestPath: string read FLastDestPath;
    property LastDestName: string read FLastDestName;
  end;

constructor TStubEntry.Create(AResult: Integer);
begin
  inherited Create;
  FExtractResult := AResult;
end;

function TStubEntry.GetFileName: string;
begin
  Result := 'stub';
end;

function TStubEntry.ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
begin
  Result := 0;
end;

function TStubEntry.Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
begin
  Inc(FExtractCallCount);
  FLastDestPath := ADestPath;
  FLastDestName := ADestName;
  Result := FExtractResult;
end;

{Builds a TArchiveHandle with a 2-entry synthetic listing. Caller frees
 the handle (or passes it to CloseArchive). The two stub entries are
 returned as out params so the test can read their Extract counts.}
function MakeHandleWithStubs(out AStub0, AStub1: TStubEntry): TArchiveHandle;
var
  S0, S1: IWcxEntryExtractor;
begin
  Result := TArchiveHandle.Create;
  Result.FileName := 'synthetic.mp4';
  AStub0 := TStubEntry.Create(E_SUCCESS);
  AStub1 := TStubEntry.Create(E_SUCCESS);
  S0 := AStub0;
  S1 := AStub1;
  Result.Listing := TWcxEntryExtractorArray.Create(S0, S1);
  Result.ResetCursor;
end;

procedure TTestWcxArchiveCoordinator.TestProcessFile_PKSkip_AdvancesCursorReturnsSuccess;
var
  H: TArchiveHandle;
  Stub0, Stub1: TStubEntry;
  R: Integer;
begin
  H := MakeHandleWithStubs(Stub0, Stub1);
  try
    R := TWcxArchiveCoordinator.ProcessFile(H, PK_SKIP, '', '');
    Assert.AreEqual(Integer(E_SUCCESS), R, 'PK_SKIP returns E_SUCCESS');
    Assert.AreEqual(1, H.CurrentEntryIndex, 'Cursor advanced from 0 to 1');
    Assert.AreEqual(0, Stub0.ExtractCallCount,
      'PK_SKIP must NOT call Extract on the current entry');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestProcessFile_NonExtractOp_AdvancesCursorReturnsSuccess;
var
  H: TArchiveHandle;
  Stub0, Stub1: TStubEntry;
  R: Integer;
begin
  H := MakeHandleWithStubs(Stub0, Stub1);
  try
    {Use a fabricated op value outside PK_SKIP/PK_TEST/PK_EXTRACT range.
     TC sends only those three today; defensive handling per the original
     production code treats anything unknown the same as PK_SKIP.}
    R := TWcxArchiveCoordinator.ProcessFile(H, 99, '', '');
    Assert.AreEqual(Integer(E_SUCCESS), R, 'Unknown op falls through to advance + success');
    Assert.AreEqual(1, H.CurrentEntryIndex, 'Cursor advanced');
    Assert.AreEqual(0, Stub0.ExtractCallCount, 'Unknown op must NOT call Extract');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestProcessFile_Exhausted_ReturnsEndArchive;
var
  H: TArchiveHandle;
  Stub0, Stub1: TStubEntry;
  R: Integer;
begin
  H := MakeHandleWithStubs(Stub0, Stub1);
  try
    {Walk past both entries via PK_SKIP, then issue PK_EXTRACT. Cursor
     is exhausted by then, so ProcessFile must short-circuit with
     E_END_ARCHIVE instead of dereferencing CurrentEntry past the
     end of the listing.}
    TWcxArchiveCoordinator.ProcessFile(H, PK_SKIP, '', '');
    TWcxArchiveCoordinator.ProcessFile(H, PK_SKIP, '', '');
    Assert.IsTrue(H.IsExhausted, 'Sanity: cursor walked past both entries');

    R := TWcxArchiveCoordinator.ProcessFile(H, PK_EXTRACT, 'dst', 'name');
    Assert.AreEqual(Integer(E_END_ARCHIVE), R,
      'PK_EXTRACT on an exhausted handle returns E_END_ARCHIVE');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestProcessFile_PKExtract_DispatchesToEntryExtract;
var
  H: TArchiveHandle;
  Stub0, Stub1: TStubEntry;
  R: Integer;
begin
  H := MakeHandleWithStubs(Stub0, Stub1);
  try
    R := TWcxArchiveCoordinator.ProcessFile(H, PK_EXTRACT, 'C:\dst', 'frame.png');
    Assert.AreEqual(Integer(E_SUCCESS), R);
    Assert.AreEqual(1, Stub0.ExtractCallCount,
      'PK_EXTRACT must dispatch to the current entry''s Extract method');
    Assert.AreEqual('C:\dst', Stub0.LastDestPath,
      'DestPath argument threaded through');
    Assert.AreEqual('frame.png', Stub0.LastDestName,
      'DestName argument threaded through');
    Assert.AreEqual(0, Stub1.ExtractCallCount,
      'Only the current entry is invoked; cursor was at index 0');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestProcessFile_PKExtract_AdvancesCursorAfterSuccess;
var
  H: TArchiveHandle;
  Stub0, Stub1: TStubEntry;
begin
  H := MakeHandleWithStubs(Stub0, Stub1);
  try
    TWcxArchiveCoordinator.ProcessFile(H, PK_EXTRACT, 'd', 'n');
    Assert.AreEqual(1, H.CurrentEntryIndex,
      'Successful PK_EXTRACT advances cursor for the next TC iteration');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestProcessFile_PKExtract_OnFailure_AdvancesCursorReturnsErrorCode;
var
  H: TArchiveHandle;
  Stub0, Stub1: TStubEntry;
  R: Integer;
const
  SOME_ERROR = 5;
begin
  H := TArchiveHandle.Create;
  try
    H.FileName := 'synthetic.mp4';
    Stub0 := TStubEntry.Create(SOME_ERROR);
    Stub1 := TStubEntry.Create(E_SUCCESS);
    H.Listing := TWcxEntryExtractorArray.Create(
      IWcxEntryExtractor(Stub0), IWcxEntryExtractor(Stub1));
    H.ResetCursor;

    R := TWcxArchiveCoordinator.ProcessFile(H, PK_EXTRACT, 'd', 'n');
    Assert.AreEqual(SOME_ERROR, R,
      'PK_EXTRACT failure path propagates the entry''s error code');
    Assert.AreEqual(1, H.CurrentEntryIndex,
      'Failure also advances cursor so TC iteration does not loop on the bad entry');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveCoordinator.TestCloseArchive_FreesHandleAndSettings_ReturnsSuccess;
var
  H: TArchiveHandle;
  R: Integer;
  TempIni: string;
begin
  {Construct a handle carrying an owned TWcxSettings — CloseArchive
   must free both. DUnitX's leak detection at end-of-suite verifies
   nothing leaked.}
  TempIni := TPath.Combine(TPath.GetTempPath, 'VT_CoordClose_' + TGUID.NewGuid.ToString + '.ini');
  H := TArchiveHandle.Create;
  H.FileName := 'synthetic.mp4';
  H.Settings := TWcxSettings.Create(TempIni);
  R := TWcxArchiveCoordinator.CloseArchive(H);
  Assert.AreEqual(Integer(E_SUCCESS), R,
    'CloseArchive returns E_SUCCESS after freeing the handle + settings');
end;

initialization

TDUnitX.RegisterTestFixture(TTestWcxArchiveCoordinator);

end.
