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

    { RenderThumbnail guard conditions (no ffmpeg required) }
    [Test] procedure RenderThumbnail_NilFFmpeg_ReturnsNil;
    [Test] procedure RenderThumbnail_NilSettings_ReturnsNil;
    [Test] procedure RenderThumbnail_NilCache_ReturnsNil;
    [Test] procedure RenderThumbnail_Disabled_ReturnsNil;
    [Test] procedure RenderThumbnail_ZeroWidth_ReturnsNil;
    [Test] procedure RenderThumbnail_ZeroHeight_ReturnsNil;
    [Test] procedure RenderThumbnail_BadFFmpegPath_ReturnsNil;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Vcl.Graphics,
  uTypes, uSettings, uDefaults, uFFmpegExe, uCache, uFrameOffsets,
  uThumbnailRender;

{ -------- CalcThumbnailOffsets — single mode -------- }

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

{ -------- CalcThumbnailOffsets — grid mode -------- }

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

{ -------- error cases -------- }

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

{ -------- PickThumbnailExtractionMaxSide -------- }

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

{ -------- RenderThumbnail guards -------- }

procedure TTestThumbnailRender.RenderThumbnail_NilFFmpeg_ReturnsNil;
var
  S: TPluginSettings;
  Cache: IFrameCache;
begin
  S := TPluginSettings.Create('');
  try
    Cache := TNullFrameCache.Create;
    Assert.IsNull(RenderThumbnail(nil, 'x.mp4', 256, 256, S, Cache));
  finally
    S.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_NilSettings_ReturnsNil;
var
  Cache: IFrameCache;
  Ff: TFFmpegExe;
begin
  Cache := TNullFrameCache.Create;
  Ff := TFFmpegExe.Create('ffmpeg.exe');
  try
    Assert.IsNull(RenderThumbnail(Ff, 'x.mp4', 256, 256, nil, Cache));
  finally
    Ff.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_NilCache_ReturnsNil;
var
  S: TPluginSettings;
  Ff: TFFmpegExe;
begin
  S := TPluginSettings.Create('');
  Ff := TFFmpegExe.Create('ffmpeg.exe');
  try
    Assert.IsNull(RenderThumbnail(Ff, 'x.mp4', 256, 256, S, nil));
  finally
    Ff.Free;
    S.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_Disabled_ReturnsNil;
var
  S: TPluginSettings;
  Cache: IFrameCache;
  Ff: TFFmpegExe;
begin
  S := TPluginSettings.Create('');
  Ff := TFFmpegExe.Create('ffmpeg.exe');
  try
    S.ThumbnailsEnabled := False;
    Cache := TNullFrameCache.Create;
    Assert.IsNull(RenderThumbnail(Ff, 'x.mp4', 256, 256, S, Cache));
  finally
    Ff.Free;
    S.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_ZeroWidth_ReturnsNil;
var
  S: TPluginSettings;
  Cache: IFrameCache;
  Ff: TFFmpegExe;
begin
  S := TPluginSettings.Create('');
  Ff := TFFmpegExe.Create('ffmpeg.exe');
  try
    Cache := TNullFrameCache.Create;
    Assert.IsNull(RenderThumbnail(Ff, 'x.mp4', 0, 256, S, Cache));
  finally
    Ff.Free;
    S.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_ZeroHeight_ReturnsNil;
var
  S: TPluginSettings;
  Cache: IFrameCache;
  Ff: TFFmpegExe;
begin
  S := TPluginSettings.Create('');
  Ff := TFFmpegExe.Create('ffmpeg.exe');
  try
    Cache := TNullFrameCache.Create;
    Assert.IsNull(RenderThumbnail(Ff, 'x.mp4', 256, 0, S, Cache));
  finally
    Ff.Free;
    S.Free;
  end;
end;

procedure TTestThumbnailRender.RenderThumbnail_BadFFmpegPath_ReturnsNil;
var
  S: TPluginSettings;
  Cache: IFrameCache;
  Ff: TFFmpegExe;
begin
  { Probe will fail (or yield IsValid=False) on a bogus ffmpeg path; the
    function must return nil rather than raise. This is the closest we
    can get to integration testing without shipping a sample video. }
  S := TPluginSettings.Create('');
  Ff := TFFmpegExe.Create('Z:\nonexistent\ffmpeg.exe');
  try
    Cache := TNullFrameCache.Create;
    Assert.IsNull(RenderThumbnail(Ff, 'Z:\nonexistent.mp4', 256, 256, S, Cache));
  finally
    Ff.Free;
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestThumbnailRender);

end.
