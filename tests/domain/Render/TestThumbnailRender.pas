unit TestThumbnailRender;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestThumbnailRender = class
  public
    { CalcThumbnailOffsets — single mode }
    [Test] procedure SingleMode_PositionMiddle_ReturnsHalfDuration;
    [Test] procedure SingleMode_PositionZero_ReturnsZero;
    [Test] procedure SingleMode_PositionFull_PullsBackFromEnd;
    [Test] procedure SingleMode_PositionAboveRange_ClampsTo100;
    [Test] procedure SingleMode_NegativePosition_ClampsToZero;
    [Test] procedure SingleMode_AlwaysReturnsSingleOffset;
    [Test] procedure SingleMode_OffsetIndexIsOne;

    { CalcThumbnailOffsets — grid mode }
    [Test] procedure GridMode_ReturnsRequestedFrameCount;
    [Test] procedure GridMode_HonorsSkipEdges;
    [Test] procedure GridMode_OffsetsAreInBounds;
    [Test] procedure GridMode_OffsetsAreOrdered;

    { CalcThumbnailOffsets — error cases }
    [Test] procedure InvalidDuration_Raises;
    [Test] procedure GridMode_ZeroFrames_Raises;

    { PickThumbnailExtractionMaxSide }
    [Test] procedure ExtractionMaxSide_ZeroRequest_FallsBackToBucket;
    [Test] procedure ExtractionMaxSide_NegativeRequest_FallsBackToBucket;
    [Test] procedure ExtractionMaxSide_BucketsUp;
    [Test] procedure ExtractionMaxSide_ExactBucket_Unchanged;
    [Test] procedure ExtractionMaxSide_TakesLargerDimension;

    { BuildThumbnailExtractionOptions — pure plumbing of settings into the
      extractor options record. Pinning every field rather than just the
      missing one so a future field-add cannot silently regress. }
    [Test] procedure BuildOptions_UseBmpPipeAlwaysTrue;
    [Test] procedure BuildOptions_HwAccelMirrorsSettings;
    [Test] procedure BuildOptions_UseKeyframesMirrorsSettings;
    [Test] procedure BuildOptions_RespectAnamorphicMirrorsSettings;
    [Test] procedure BuildOptions_MaxSideFromRequestedCellSize;

    { RenderThumbnail guard conditions }
    [Test] procedure RenderThumbnail_NilExtractor_ReturnsNil;
    [Test] procedure RenderThumbnail_NilProber_ReturnsNil;
    [Test] procedure RenderThumbnail_NilCache_ReturnsNil;
    [Test] procedure RenderThumbnail_NilProbeCache_ReturnsNil;
    [Test] procedure RenderThumbnail_Disabled_ReturnsNil;
    [Test] procedure RenderThumbnail_ZeroWidth_ReturnsNil;
    [Test] procedure RenderThumbnail_ZeroHeight_ReturnsNil;
    [Test] procedure RenderThumbnail_ProbeInvalid_ReturnsNil;
    { RenderThumbnail pipeline — fake extractor + prober, no ffmpeg }
    [Test] procedure RenderThumbnail_SingleMode_ReturnsBitmap;
    [Test] procedure RenderThumbnail_SingleMode_ExtractorFails_ReturnsNil;
    [Test] procedure RenderThumbnail_GridMode_ReturnsBitmap;
    [Test] procedure RenderThumbnail_Downscale_ResultFitsRequested;
    [Test] procedure RenderThumbnail_SecondCall_DoesNotReprobe;
    [Test] procedure RenderThumbnail_UsesInjectedProbeCache;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Winapi.Windows, Vcl.Graphics,
  Types, Settings, Defaults, ProbeCache, Cache, CacheStorage, FrameOffsets,
  ThumbnailRender, FrameExtractor, VideoProbing, VideoInfo;

function MakeTempProbeCache: IProbeCache;
begin
  {Per-test probe cache in a throwaway temp dir so tests remain isolated.}
  Result := TProbeCache.Create(
    TDiskCacheStorage.Create(TPath.Combine(TPath.GetTempPath,
      'glimpse_thumb_probe_' + IntToStr(Random(MaxInt))), '.probe'),
    TFileSystemStat.Create);
end;

{Returns a TThumbnailParams with Enabled=True so the pipeline reaches
 past its early-disabled guard. Default(TThumbnailParams) zero-inits
 to Enabled=False, unlike a fresh TPluginSettings which seeds
 ThumbnailsEnabled := DEF_THUMBNAILS_ENABLED (True); this helper
 keeps the historical "enabled by default" convention for these
 tests. Tests that want a specific field override do so on the
 returned record before passing it on.}
function MakeEnabledThumbnailParams: TThumbnailParams;
begin
  Result := Default(TThumbnailParams);
  Result.Enabled := True;
end;

{A TVideoInfo that passes IsValid (Duration > 0).}
function MakeValidInfo: TVideoInfo;
begin
  Result := Default(TVideoInfo);
  Result.Duration := 100.0;
  Result.Width := 640;
  Result.Height := 480;
  Result.DisplayWidth := 640;
  Result.DisplayHeight := 480;
end;

type
  {Canned IVideoProber: returns a fixed TVideoInfo and counts calls so the
   probe-cache interaction can be observed without spawning ffmpeg.}
  TFakeProber = class(TInterfacedObject, IVideoProber)
  strict private
    FInfo: TVideoInfo;
    FCallCount: Integer;
  public
    constructor Create(const AInfo: TVideoInfo);
    function ProbeVideo(const AFilePath: string): TVideoInfo;
    property CallCount: Integer read FCallCount;
  end;

  {IFrameExtractor that yields a fresh pf24 bitmap of a fixed size, or nil
   to simulate an extraction failure.}
  TFakeExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FWidth, FHeight: Integer;
    FReturnNil: Boolean;
  public
    constructor Create(AWidth, AHeight: Integer; AReturnNil: Boolean = False);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
  end;

  {Fully in-memory IProbeCache — proves RenderThumbnail consults the
   injected abstraction with no disk probe cache.}
  TFakeProbeCache = class(TInterfacedObject, IProbeCache)
  strict private
    FInfo: TVideoInfo;
    FProbeCount: Integer;
  public
    constructor Create(const AInfo: TVideoInfo);
    function TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
    procedure Put(const AFilePath: string; const AInfo: TVideoInfo);
    function TryGetOrProbe(const AFilePath: string; const AProber: IVideoProber): TVideoInfo;
    property ProbeCount: Integer read FProbeCount;
  end;

constructor TFakeProber.Create(const AInfo: TVideoInfo);
begin
  inherited Create;
  FInfo := AInfo;
end;

function TFakeProber.ProbeVideo(const AFilePath: string): TVideoInfo;
begin
  Inc(FCallCount);
  Result := FInfo;
end;

constructor TFakeExtractor.Create(AWidth, AHeight: Integer; AReturnNil: Boolean);
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  FReturnNil := AReturnNil;
end;

function TFakeExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
begin
  if FReturnNil then
    Exit(nil);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(FWidth, FHeight);
end;

constructor TFakeProbeCache.Create(const AInfo: TVideoInfo);
begin
  inherited Create;
  FInfo := AInfo;
end;

function TFakeProbeCache.TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
begin
  AInfo := FInfo;
  Result := FInfo.IsValid;
end;

procedure TFakeProbeCache.Put(const AFilePath: string; const AInfo: TVideoInfo);
begin
  {Intentionally empty: the fake serves only canned data.}
end;

function TFakeProbeCache.TryGetOrProbe(const AFilePath: string;
  const AProber: IVideoProber): TVideoInfo;
begin
  Inc(FProbeCount);
  Result := FInfo;
end;

{ CalcThumbnailOffsets — single mode }

procedure TTestThumbnailRender.SingleMode_PositionMiddle_ReturnsHalfDuration;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalcThumbnailOffsets(100.0, tnmSingle, 50, 4, 0);
  Assert.AreEqual(1, Integer(Length(Offsets)));
  Assert.AreEqual(50.0, Offsets[0].TimeOffset, 0.001);
end;

procedure TTestThumbnailRender.SingleMode_PositionZero_ReturnsZero;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalcThumbnailOffsets(120.0, tnmSingle, 0, 4, 0);
  Assert.AreEqual(0.0, Offsets[0].TimeOffset, 0.001);
end;

procedure TTestThumbnailRender.SingleMode_PositionFull_PullsBackFromEnd;
var
  Offsets: TFrameOffsetArray;
begin
  { Position 100 must not produce an offset == Duration; ffmpeg would
    return no frame for the very last microsecond. The implementation
    backs off to 99% of the duration. }
  Offsets := CalcThumbnailOffsets(100.0, tnmSingle, 100, 4, 0);
  Assert.IsTrue(Offsets[0].TimeOffset < 100.0,
    'Position 100% must back off from the end');
  Assert.AreEqual(99.0, Offsets[0].TimeOffset, 0.001);
end;

procedure TTestThumbnailRender.SingleMode_PositionAboveRange_ClampsTo100;
var
  Offsets: TFrameOffsetArray;
begin
  { Defensive: a settings file edited by hand could supply 200%. The
    function clamps rather than producing a nonsense offset. }
  Offsets := CalcThumbnailOffsets(100.0, tnmSingle, 200, 4, 0);
  Assert.AreEqual(99.0, Offsets[0].TimeOffset, 0.001);
end;

procedure TTestThumbnailRender.SingleMode_NegativePosition_ClampsToZero;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalcThumbnailOffsets(100.0, tnmSingle, -10, 4, 0);
  Assert.AreEqual(0.0, Offsets[0].TimeOffset, 0.001);
end;

procedure TTestThumbnailRender.SingleMode_AlwaysReturnsSingleOffset;
var
  Offsets: TFrameOffsetArray;
begin
  { GridFrames is irrelevant in single mode and must not affect output }
  Offsets := CalcThumbnailOffsets(60.0, tnmSingle, 50, 16, 5);
  Assert.AreEqual(1, Integer(Length(Offsets)));
end;

procedure TTestThumbnailRender.SingleMode_OffsetIndexIsOne;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalcThumbnailOffsets(60.0, tnmSingle, 50, 4, 0);
  Assert.AreEqual(1, Offsets[0].Index);
end;

{ CalcThumbnailOffsets — grid mode }

procedure TTestThumbnailRender.GridMode_ReturnsRequestedFrameCount;
var
  Offsets: TFrameOffsetArray;
begin
  Offsets := CalcThumbnailOffsets(120.0, tnmGrid, 50, 4, 0);
  Assert.AreEqual(4, Integer(Length(Offsets)));
end;

procedure TTestThumbnailRender.GridMode_HonorsSkipEdges;
var
  WithSkip, NoSkip: TFrameOffsetArray;
begin
  { With SkipEdges > 0 the first offset must be later than with skip=0 }
  NoSkip := CalcThumbnailOffsets(100.0, tnmGrid, 50, 4, 0);
  WithSkip := CalcThumbnailOffsets(100.0, tnmGrid, 50, 4, 10);
  Assert.IsTrue(WithSkip[0].TimeOffset > NoSkip[0].TimeOffset,
    'SkipEdges must shift first offset later');
end;

procedure TTestThumbnailRender.GridMode_OffsetsAreInBounds;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
begin
  Offsets := CalcThumbnailOffsets(60.0, tnmGrid, 50, 9, 5);
  for I := 0 to High(Offsets) do
  begin
    Assert.IsTrue(Offsets[I].TimeOffset >= 0,
      Format('Offset %d below zero: %.3f', [I, Offsets[I].TimeOffset]));
    Assert.IsTrue(Offsets[I].TimeOffset < 60.0,
      Format('Offset %d at or beyond duration: %.3f', [I, Offsets[I].TimeOffset]));
  end;
end;

procedure TTestThumbnailRender.GridMode_OffsetsAreOrdered;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
begin
  Offsets := CalcThumbnailOffsets(60.0, tnmGrid, 50, 6, 0);
  for I := 1 to High(Offsets) do
    Assert.IsTrue(Offsets[I].TimeOffset > Offsets[I - 1].TimeOffset,
      Format('Offsets not strictly ascending at index %d', [I]));
end;

{ error cases }

procedure TTestThumbnailRender.InvalidDuration_Raises;
begin
  Assert.WillRaise(
    procedure begin CalcThumbnailOffsets(0, tnmSingle, 50, 4, 0); end,
    EArgumentException);

  Assert.WillRaise(
    procedure begin CalcThumbnailOffsets(-5, tnmSingle, 50, 4, 0); end,
    EArgumentException);
end;

procedure TTestThumbnailRender.GridMode_ZeroFrames_Raises;
begin
  Assert.WillRaise(
    procedure begin CalcThumbnailOffsets(100.0, tnmGrid, 50, 0, 0); end,
    EArgumentException);
end;

{ PickThumbnailExtractionMaxSide }

procedure TTestThumbnailRender.ExtractionMaxSide_ZeroRequest_FallsBackToBucket;
begin
  { Defensive: TC could theoretically pass 0 if the panel layout glitches.
    The helper must return a sensible non-zero size, not 0. }
  Assert.AreEqual(SCALE_BUCKET, PickThumbnailExtractionMaxSide(0, 0));
end;

procedure TTestThumbnailRender.ExtractionMaxSide_NegativeRequest_FallsBackToBucket;
begin
  Assert.AreEqual(SCALE_BUCKET, PickThumbnailExtractionMaxSide(-10, -10));
end;

procedure TTestThumbnailRender.ExtractionMaxSide_BucketsUp;
begin
  { 100 -> first bucket (160). 200 -> second bucket (320).
    Buckets keep nearby request sizes mapping to the same cache key. }
  Assert.AreEqual(SCALE_BUCKET, PickThumbnailExtractionMaxSide(100, 100));
  Assert.AreEqual(SCALE_BUCKET * 2, PickThumbnailExtractionMaxSide(200, 200));
end;

procedure TTestThumbnailRender.ExtractionMaxSide_ExactBucket_Unchanged;
begin
  { When the request equals a bucket boundary exactly, no rounding up }
  Assert.AreEqual(SCALE_BUCKET, PickThumbnailExtractionMaxSide(SCALE_BUCKET, SCALE_BUCKET));
  Assert.AreEqual(SCALE_BUCKET * 3, PickThumbnailExtractionMaxSide(SCALE_BUCKET * 3, SCALE_BUCKET * 3));
end;

procedure TTestThumbnailRender.ExtractionMaxSide_TakesLargerDimension;
begin
  { Wide rectangle: width drives the bucket; height is irrelevant }
  Assert.AreEqual(SCALE_BUCKET * 2, PickThumbnailExtractionMaxSide(300, 50));
  { Tall rectangle: height drives the bucket }
  Assert.AreEqual(SCALE_BUCKET * 2, PickThumbnailExtractionMaxSide(50, 300));
end;

{ BuildThumbnailExtractionOptions }

procedure TTestThumbnailRender.BuildOptions_UseBmpPipeAlwaysTrue;
var
  P: TThumbnailParams;
  O: TExtractionOptions;
begin
  P := Default(TThumbnailParams);
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsTrue(O.UseBmpPipe, 'Thumbnails always use the bmp pipe for speed');
end;

procedure TTestThumbnailRender.BuildOptions_HwAccelMirrorsSettings;
var
  P: TThumbnailParams;
  O: TExtractionOptions;
begin
  P := Default(TThumbnailParams);
  P.HwAccel := True;
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsTrue(O.HwAccel);
  P.HwAccel := False;
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsFalse(O.HwAccel);
end;

procedure TTestThumbnailRender.BuildOptions_UseKeyframesMirrorsSettings;
var
  P: TThumbnailParams;
  O: TExtractionOptions;
begin
  P := Default(TThumbnailParams);
  P.UseKeyframes := True;
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsTrue(O.UseKeyframes);
  P.UseKeyframes := False;
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsFalse(O.UseKeyframes);
end;

procedure TTestThumbnailRender.BuildOptions_RespectAnamorphicMirrorsSettings;
var
  P: TThumbnailParams;
  O: TExtractionOptions;
begin
  {Bug regression pin. Earlier the inline build forgot to copy
   RespectAnamorphic, so anamorphic-source thumbnails appeared squashed
   while the live preview rendered them correctly.}
  P := Default(TThumbnailParams);
  P.RespectAnamorphic := True;
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsTrue(O.RespectAnamorphic,
    'Thumbnail must respect anamorphic when the user has the toggle on');
  P.RespectAnamorphic := False;
  O := BuildThumbnailExtractionOptions(P, 256, 256);
  Assert.IsFalse(O.RespectAnamorphic,
    'Thumbnail must follow the toggle off');
end;

procedure TTestThumbnailRender.BuildOptions_MaxSideFromRequestedCellSize;
var
  P: TThumbnailParams;
  O: TExtractionOptions;
begin
  P := Default(TThumbnailParams);
  O := BuildThumbnailExtractionOptions(P, 100, 50);
  Assert.AreEqual(PickThumbnailExtractionMaxSide(100, 50), O.MaxSide,
    'MaxSide must come from the requested cell size, not MaxFrameSide');
end;

{ RenderThumbnail guards }

procedure TTestThumbnailRender.RenderThumbnail_NilExtractor_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  P := MakeEnabledThumbnailParams;
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(nil, Prober, 'x.mp4', 256, 256, P, Cache, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_NilProber_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Probe: IProbeCache;
begin
  P := MakeEnabledThumbnailParams;
  Extractor := TFakeExtractor.Create(640, 480);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, nil, 'x.mp4', 256, 256, P, Cache, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_NilCache_ReturnsNil;
var
  P: TThumbnailParams;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  P := MakeEnabledThumbnailParams;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, nil, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_NilProbeCache_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
begin
  { Probe cache is required — without it the pipeline cannot resolve video
    metadata and must fail fast, consistent with the other nil guards. }
  P := MakeEnabledThumbnailParams;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, Cache, nil));
end;

procedure TTestThumbnailRender.RenderThumbnail_Disabled_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  {Default(TThumbnailParams).Enabled is False — exactly the contract this
   test pins.}
  P := Default(TThumbnailParams);
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, Cache, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_ZeroWidth_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  P := MakeEnabledThumbnailParams;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 0, 256, P, Cache, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_ZeroHeight_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  P := MakeEnabledThumbnailParams;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 0, P, Cache, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_ProbeInvalid_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  { The prober reports failure (Default TVideoInfo has Duration 0, so
    IsValid is False). The pipeline must return nil without extracting. }
  P := MakeEnabledThumbnailParams;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(Default(TVideoInfo));
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, Cache, Probe));
end;

{ RenderThumbnail pipeline }

procedure TTestThumbnailRender.RenderThumbnail_SingleMode_ReturnsBitmap;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
  Bmp: TBitmap;
begin
  P := MakeEnabledThumbnailParams;
  P.Mode := tnmSingle;
  P.Position := 50;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Bmp := RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, Cache, Probe);
  try
    Assert.IsNotNull(Bmp, 'Single-mode render must produce a bitmap');
    Assert.IsTrue((Bmp.Width > 0) and (Bmp.Height > 0));
    Assert.IsTrue((Bmp.Width <= 256) and (Bmp.Height <= 256),
      'Result must fit the requested cell size');
  finally
    Bmp.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_SingleMode_ExtractorFails_ReturnsNil;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
begin
  { In single mode a nil extraction is a hard failure with no fallback. }
  P := MakeEnabledThumbnailParams;
  P.Mode := tnmSingle;
  Extractor := TFakeExtractor.Create(0, 0, True);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Assert.IsNull(RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, Cache, Probe));
end;

procedure TTestThumbnailRender.RenderThumbnail_GridMode_ReturnsBitmap;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
  Bmp: TBitmap;
begin
  P := MakeEnabledThumbnailParams;
  P.Mode := tnmGrid;
  P.GridFrames := 4;
  Extractor := TFakeExtractor.Create(320, 240);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Bmp := RenderThumbnail(Extractor, Prober, 'x.mp4', 512, 512, P, Cache, Probe);
  try
    Assert.IsNotNull(Bmp, 'Grid-mode render must produce a combined bitmap');
    Assert.IsTrue((Bmp.Width > 0) and (Bmp.Height > 0));
  finally
    Bmp.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_Downscale_ResultFitsRequested;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  Probe: IProbeCache;
  Bmp: TBitmap;
begin
  { The extractor yields a frame far larger than the requested cell; the
    pipeline must downscale the result to fit. }
  P := MakeEnabledThumbnailParams;
  P.Mode := tnmSingle;
  Extractor := TFakeExtractor.Create(1920, 1080);
  Prober := TFakeProber.Create(MakeValidInfo);
  Probe := MakeTempProbeCache;
  Cache := TNullFrameCache.Create;
  Bmp := RenderThumbnail(Extractor, Prober, 'x.mp4', 128, 128, P, Cache, Probe);
  try
    Assert.IsNotNull(Bmp);
    Assert.IsTrue((Bmp.Width <= 128) and (Bmp.Height <= 128),
      Format('Result %dx%d must fit within 128x128', [Bmp.Width, Bmp.Height]));
  finally
    Bmp.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_SecondCall_DoesNotReprobe;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Fake: TFakeProber;
  Prober: IVideoProber;
  Probe: IProbeCache;
  SrcFile: string;
  Bmp: TBitmap;
begin
  { A real source file makes ProbeKey resolvable, so the first probe result
    is persisted and the second RenderThumbnail call hits the probe cache
    instead of re-probing. }
  P := MakeEnabledThumbnailParams;
  P.Mode := tnmSingle;
  Extractor := TFakeExtractor.Create(640, 480);
  Fake := TFakeProber.Create(MakeValidInfo);
  Prober := Fake;
  Probe := MakeTempProbeCache;
  SrcFile := TPath.Combine(TPath.GetTempPath,
    'glimpse_thumb_src_' + IntToStr(Random(MaxInt)) + '.mp4');
  TFile.WriteAllText(SrcFile, 'placeholder');
  try
    Cache := TNullFrameCache.Create;
    Bmp := RenderThumbnail(Extractor, Prober, SrcFile, 256, 256, P, Cache, Probe);
    Bmp.Free;
    Bmp := RenderThumbnail(Extractor, Prober, SrcFile, 256, 256, P, Cache, Probe);
    Bmp.Free;
    Assert.AreEqual<Integer>(1, Fake.CallCount,
      'Second render must hit the probe cache, not re-probe');
  finally
    TFile.Delete(SrcFile);
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_UsesInjectedProbeCache;
var
  P: TThumbnailParams;
  Cache: IFrameCache;
  Extractor: IFrameExtractor;
  Prober: IVideoProber;
  FakeProbe: TFakeProbeCache;
  Probe: IProbeCache;
  Bmp: TBitmap;
begin
  {A fully in-memory IProbeCache substitute: RenderThumbnail must consult
   it for video metadata and render with no disk probe cache involved.}
  P := MakeEnabledThumbnailParams;
  P.Mode := tnmSingle;
  Extractor := TFakeExtractor.Create(640, 480);
  Prober := TFakeProber.Create(MakeValidInfo);
  FakeProbe := TFakeProbeCache.Create(MakeValidInfo);
  Probe := FakeProbe;
  Cache := TNullFrameCache.Create;
  Bmp := RenderThumbnail(Extractor, Prober, 'x.mp4', 256, 256, P, Cache, Probe);
  try
    Assert.IsNotNull(Bmp, 'Render must succeed against a substituted probe cache');
    Assert.AreEqual<Integer>(1, FakeProbe.ProbeCount,
      'RenderThumbnail must consult the injected IProbeCache');
  finally
    Bmp.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestThumbnailRender);

end.
