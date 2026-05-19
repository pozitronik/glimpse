{Tests for TWcxArchiveCoordinator + IWcxSettingsProvider / IProbeService.

 Step 100 (C9): the OpenArchive flow was lifted out of the WCX ABI thunk
 (DoOpenArchive) into TWcxArchiveCoordinator with 3 injected factories.
 These tests pin the DI contract: the coordinator must defer settings
 build, video probing, and frame-extractor construction to its
 collaborators rather than instantiate concrete types itself.

 The flow still touches the filesystem (TFile.GetLastWriteTime /
 GetSize on the source video file, and FindFFmpegExe expects ffmpeg.exe
 to either exist on disk at the configured path, in the plugin
 directory next to the INI, or on PATH). Tests therefore set up a temp
 directory with a synthetic ffmpeg.exe stub (zero bytes is fine — the
 coordinator never invokes it because the probe service is faked) and
 a similarly-synthetic source video file. The synthetic INI path lives
 in the same temp directory.

 ShowFileSizes is left at its default False so PreExtractFrames does
 not run (it would launch ffmpeg). ShowPresets is also left False so
 the production LoadPresets path is not taken (and the test does not
 need a presets.ini next to the synthetic INI).}
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
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Winapi.Windows, Vcl.Graphics,
  uTypes, uWcxAPI, uWcxArchiveHandle, uWcxSettings,
  uFrameExtractor, uVideoInfo,
  uWcxArchiveCoordinator;

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

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory);
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

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory);
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

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory);
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

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory);
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

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory);
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

  Coord := TWcxArchiveCoordinator.Create(SettingsProvider, ProbeService, ExtractorFactory);
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

initialization

TDUnitX.RegisterTestFixture(TTestWcxArchiveCoordinator);

end.
