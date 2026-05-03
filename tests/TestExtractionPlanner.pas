unit TestExtractionPlanner;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExtractionPlanner = class
  private
    FTempIniPath: string;
    FTempDir: string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestPlanSingleWorker;
    [Test] procedure TestPlanMultipleWorkers;
    [Test] procedure TestPlanZeroWorkersOnePerFrame;
    [Test] procedure TestPlanWorkersExceedFrames;
    [Test] procedure TestPlanSingleFrame;
    [Test] procedure TestPlanChunksSumToTotal;
    [Test] procedure TestPlanChunksNoGaps;
    [Test] procedure TestPlanZeroFrames;
    [Test] procedure TestPlanNegativeMaxWorkers;
    [Test] procedure TestPlanMaxThreadsCapsOnePerFrame;
    [Test] procedure TestPlanMaxThreadsCapsExplicitWorkers;
    [Test] procedure TestPlanMaxThreadsZeroUsesCpuCount;
    [Test] procedure TestPlanMaxThreadsNegativeNoLimit;
    [Test] procedure TestTakeSettingsSnapshotCaptures;
    [Test] procedure TestDetectSettingsChangesNoChange;
    [Test] procedure TestDetectSettingsChangesCacheEnabled;
    [Test] procedure TestDetectSettingsChangesCacheFolder;
    [Test] procedure TestDetectSettingsChangesCacheMaxSize;
    [Test] procedure TestDetectSettingsChangesFFmpegPath;
    [Test] procedure TestDetectSettingsChangesSkipEdges;
    [Test] procedure TestDetectSettingsChangesMultiple;
    [Test] procedure TestDetectSettingsChangesScaledExtraction;
    [Test] procedure TestDetectSettingsChangesMinFrameSide;
    [Test] procedure TestDetectSettingsChangesMaxFrameSide;
    [Test] procedure TestDetectSettingsChangesUseKeyframes;
    [Test] procedure TestDetectSettingsChangesRespectAnamorphic;

    { CalcExtractionMaxSide tests }
    [Test] procedure TestCalcMaxSideLandscape;
    [Test] procedure TestCalcMaxSidePortrait;
    [Test] procedure TestCalcMaxSideClampsToMin;
    [Test] procedure TestCalcMaxSideClampsToMax;
    [Test] procedure TestCalcMaxSideBucketed;
    [Test] procedure TestCalcMaxSideNoUpscale;
    [Test] procedure TestCalcMaxSideZeroFrames;
    [Test] procedure TestCalcMaxSideZeroViewport;
    [Test] procedure TestCalcMaxSideSingleFrame;

    { PickSaveMaxSide tests }
    [Test] procedure TestPickSaveMaxSideScalingOff;
    [Test] procedure TestPickSaveMaxSideNativeBelowCap;
    [Test] procedure TestPickSaveMaxSideNativeEqualsCap;
    [Test] procedure TestPickSaveMaxSideNativeAboveCap;
    [Test] procedure TestPickSaveMaxSideZeroCap;
    [Test] procedure TestPickSaveMaxSideZeroNative;
    [Test] procedure TestPickSaveMaxSidePortraitNative;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, uSettings, uExtractionPlanner;

procedure TTestExtractionPlanner.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_PlanTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
  FTempIniPath := TPath.Combine(FTempDir, 'test.ini');
end;

procedure TTestExtractionPlanner.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestExtractionPlanner.TestPlanSingleWorker;
var
  Chunks: TArray<TWorkerChunk>;
begin
  Chunks := PlanWorkerChunks(4, 1, 0);
  Assert.AreEqual(1, Integer(Length(Chunks)));
  Assert.AreEqual(0, Chunks[0].Start);
  Assert.AreEqual(4, Chunks[0].Len);
end;

procedure TTestExtractionPlanner.TestPlanMultipleWorkers;
var
  Chunks: TArray<TWorkerChunk>;
begin
  Chunks := PlanWorkerChunks(10, 3, 0);
  Assert.AreEqual(3, Integer(Length(Chunks)));
  { CeilDiv(10,3)=4: chunks of 4, 4, 2 }
  Assert.AreEqual(0, Chunks[0].Start);
  Assert.AreEqual(4, Chunks[0].Len);
  Assert.AreEqual(4, Chunks[1].Start);
  Assert.AreEqual(4, Chunks[1].Len);
  Assert.AreEqual(8, Chunks[2].Start);
  Assert.AreEqual(2, Chunks[2].Len);
end;

procedure TTestExtractionPlanner.TestPlanZeroWorkersOnePerFrame;
var
  Chunks: TArray<TWorkerChunk>;
  I: Integer;
begin
  Chunks := PlanWorkerChunks(4, 0, 0);
  Assert.AreEqual(4, Integer(Length(Chunks)));
  for I := 0 to 3 do
  begin
    Assert.AreEqual(I, Chunks[I].Start);
    Assert.AreEqual(1, Chunks[I].Len);
  end;
end;

procedure TTestExtractionPlanner.TestPlanWorkersExceedFrames;
var
  Chunks: TArray<TWorkerChunk>;
begin
  { 5 workers for 2 frames: only 2 chunks }
  Chunks := PlanWorkerChunks(2, 5, 0);
  Assert.AreEqual(2, Integer(Length(Chunks)));
  Assert.AreEqual(0, Chunks[0].Start);
  Assert.AreEqual(1, Chunks[0].Len);
  Assert.AreEqual(1, Chunks[1].Start);
  Assert.AreEqual(1, Chunks[1].Len);
end;

procedure TTestExtractionPlanner.TestPlanSingleFrame;
var
  Chunks: TArray<TWorkerChunk>;
begin
  Chunks := PlanWorkerChunks(1, 4, 0);
  Assert.AreEqual(1, Integer(Length(Chunks)));
  Assert.AreEqual(0, Chunks[0].Start);
  Assert.AreEqual(1, Chunks[0].Len);
end;

procedure TTestExtractionPlanner.TestPlanChunksSumToTotal;
var
  Chunks: TArray<TWorkerChunk>;
  Total, I: Integer;
begin
  Chunks := PlanWorkerChunks(20, 3, 0);
  Total := 0;
  for I := 0 to High(Chunks) do
    Inc(Total, Chunks[I].Len);
  Assert.AreEqual(20, Total, 'Sum of chunk lengths must equal total frames');
end;

procedure TTestExtractionPlanner.TestPlanChunksNoGaps;
var
  Chunks: TArray<TWorkerChunk>;
  I: Integer;
begin
  Chunks := PlanWorkerChunks(20, 3, 0);
  for I := 1 to High(Chunks) do
    Assert.AreEqual(Chunks[I - 1].Start + Chunks[I - 1].Len, Chunks[I].Start,
      Format('Chunk %d should start where chunk %d ends', [I, I - 1]));
end;

procedure TTestExtractionPlanner.TestPlanZeroFrames;
var
  Chunks: TArray<TWorkerChunk>;
begin
  Chunks := PlanWorkerChunks(0, 4, 0);
  Assert.AreEqual(0, Integer(Length(Chunks)));
end;

procedure TTestExtractionPlanner.TestPlanNegativeMaxWorkers;
var
  Chunks: TArray<TWorkerChunk>;
  Total, I: Integer;
begin
  { Negative MaxWorkers should clamp to 1 worker }
  Chunks := PlanWorkerChunks(6, -3, 0);
  Assert.AreEqual(1, Integer(Length(Chunks)), 'Negative workers should clamp to 1');
  Total := 0;
  for I := 0 to High(Chunks) do
    Inc(Total, Chunks[I].Len);
  Assert.AreEqual(6, Total, 'All frames must be assigned');
end;

procedure TTestExtractionPlanner.TestPlanMaxThreadsCapsOnePerFrame;
var
  Chunks: TArray<TWorkerChunk>;
  Total, I: Integer;
begin
  { MaxWorkers=0 (one per frame), 20 frames, but MaxThreads=4 }
  Chunks := PlanWorkerChunks(20, 0, 4);
  Assert.AreEqual(4, Integer(Length(Chunks)), 'Should cap at 4 threads');
  Total := 0;
  for I := 0 to High(Chunks) do
    Inc(Total, Chunks[I].Len);
  Assert.AreEqual(20, Total, 'All frames must be assigned');
end;

procedure TTestExtractionPlanner.TestPlanMaxThreadsCapsExplicitWorkers;
var
  Chunks: TArray<TWorkerChunk>;
begin
  { MaxWorkers=8 but MaxThreads=3: capped to 3 }
  Chunks := PlanWorkerChunks(20, 8, 3);
  Assert.AreEqual(3, Integer(Length(Chunks)), 'Should cap explicit workers to MaxThreads');
end;

procedure TTestExtractionPlanner.TestPlanMaxThreadsZeroUsesCpuCount;
var
  Chunks: TArray<TWorkerChunk>;
begin
  { MaxWorkers=0 (one per frame), 999 frames, MaxThreads=0 (auto=CPU count).
    Should cap at CPUCount. }
  Chunks := PlanWorkerChunks(999, 0, 0);
  Assert.IsTrue(Integer(Length(Chunks)) <= CPUCount,
    Format('Should not exceed CPU count (%d), got %d', [CPUCount, Length(Chunks)]));
  Assert.IsTrue(Integer(Length(Chunks)) >= 1, 'Should have at least 1 chunk');
end;

procedure TTestExtractionPlanner.TestPlanMaxThreadsNegativeNoLimit;
var
  Chunks: TArray<TWorkerChunk>;
begin
  { MaxWorkers=0 (one per frame), 20 frames, MaxThreads=-1 (no limit).
    Should create one chunk per frame. }
  Chunks := PlanWorkerChunks(20, 0, -1);
  Assert.AreEqual(20, Integer(Length(Chunks)), 'No limit should allow one worker per frame');
end;

procedure TTestExtractionPlanner.TestTakeSettingsSnapshotCaptures;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    S.CacheEnabled := True;
    S.CacheFolder := 'C:\cache';
    S.CacheMaxSizeMB := 500;
    S.SkipEdgesPercent := 5;
    S.FFmpegExePath := 'C:\ffmpeg.exe';
    Snap := TakeSettingsSnapshot(S);
    Assert.IsTrue(Snap.CacheEnabled);
    Assert.AreEqual('C:\cache', Snap.CacheFolder);
    Assert.AreEqual(500, Snap.CacheMaxSizeMB);
    Assert.AreEqual(5, Snap.SkipEdgesPercent);
    Assert.AreEqual('C:\ffmpeg.exe', Snap.FFmpegExePath);
    Assert.IsFalse(Snap.ScaledExtraction);
    Assert.AreEqual(120, Snap.MinFrameSide);
    Assert.AreEqual(1920, Snap.MaxFrameSide);
    Assert.IsFalse(Snap.UseKeyframes);
    Assert.IsTrue(Snap.RespectAnamorphic, 'Snapshot must capture default-on RespectAnamorphic');
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesNoChange;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(Changes = [], 'No changes expected');
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesCacheEnabled;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.CacheEnabled := not S.CacheEnabled;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scCacheChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesCacheFolder;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.CacheFolder := 'D:\new_cache';
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scCacheChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesCacheMaxSize;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.CacheMaxSizeMB := S.CacheMaxSizeMB + 100;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scCacheChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesFFmpegPath;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.FFmpegExePath := 'C:\new\ffmpeg.exe';
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scFFmpegPathChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesSkipEdges;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.SkipEdgesPercent := 10;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scSkipEdgesChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesMultiple;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.CacheEnabled := not S.CacheEnabled;
    S.SkipEdgesPercent := 15;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scCacheChanged in Changes, 'Cache change expected');
    Assert.IsTrue(scSkipEdgesChanged in Changes, 'SkipEdges change expected');
    Assert.IsFalse(scFFmpegPathChanged in Changes, 'No FFmpeg change expected');
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesScaledExtraction;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.ScaledExtraction := True;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scScaledExtractionChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesMinFrameSide;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.MinFrameSide := 200;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scScaledExtractionChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesMaxFrameSide;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.MaxFrameSide := 3840;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scScaledExtractionChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesUseKeyframes;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.UseKeyframes := True;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scUseKeyframesChanged in Changes);
  finally
    S.Free;
  end;
end;

procedure TTestExtractionPlanner.TestDetectSettingsChangesRespectAnamorphic;
var
  S: TPluginSettings;
  Snap: TSettingsSnapshot;
  Changes: TSettingsChanges;
begin
  {Toggling RespectAnamorphic must surface as a change so the form can
   re-extract and refresh the live-view aspect ratio.}
  S := TPluginSettings.Create(FTempIniPath);
  try
    Snap := TakeSettingsSnapshot(S);
    S.RespectAnamorphic := not Snap.RespectAnamorphic;
    Changes := DetectSettingsChanges(Snap, S);
    Assert.IsTrue(scRespectAnamorphicChanged in Changes);
  finally
    S.Free;
  end;
end;

{ CalcExtractionMaxSide tests }

procedure TTestExtractionPlanner.TestCalcMaxSideLandscape;
var
  R: Integer;
begin
  { 1024x768 viewport, 4 frames, 16:9 video (AR=0.5625), native 1920x1080 }
  R := CalcExtractionMaxSide(1024, 768, 4, 9/16, 1920, 1080, 120, 1920);
  Assert.IsTrue(R > 0, 'Should scale down 1920x1080 for 4 thumbnails');
  Assert.IsTrue(R <= 1920, 'Must not exceed max');
  Assert.IsTrue(R >= 120, 'Must not go below min');
  Assert.AreEqual(0, R mod 160, 'Must be bucketed to 160px step');
end;

procedure TTestExtractionPlanner.TestCalcMaxSidePortrait;
var
  R: Integer;
begin
  { 1024x768 viewport, 4 frames, 9:16 portrait video (AR=16/9), native 1080x1920 }
  R := CalcExtractionMaxSide(1024, 768, 4, 16/9, 1080, 1920, 120, 1920);
  Assert.IsTrue(R > 0, 'Should scale down 1080x1920 for 4 thumbnails');
  Assert.IsTrue(R <= 1920, 'Must not exceed max');
  Assert.AreEqual(0, R mod 160, 'Must be bucketed to 160px step');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideClampsToMin;
var
  R: Integer;
begin
  { Tiny viewport with many frames: raw result would be below MinFrameSide }
  R := CalcExtractionMaxSide(200, 150, 99, 9/16, 3840, 2160, 120, 1920);
  Assert.IsTrue(R >= 160, 'Result must be at least one bucket above min');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideClampsToMax;
var
  R: Integer;
begin
  { Large viewport, single frame: raw result would exceed MaxFrameSide }
  R := CalcExtractionMaxSide(3840, 2160, 1, 9/16, 7680, 4320, 120, 1920);
  Assert.IsTrue(R <= 1920, 'Result must not exceed MaxFrameSide');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideBucketed;
var
  R: Integer;
begin
  { Verify result is always a multiple of SCALE_BUCKET (160) }
  R := CalcExtractionMaxSide(1024, 768, 10, 9/16, 1920, 1080, 120, 1920);
  if R > 0 then
    Assert.AreEqual(0, R mod 160, 'Result must be a multiple of 160');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideNoUpscale;
var
  R: Integer;
begin
  { Video is smaller than the calculated target: no scaling needed }
  R := CalcExtractionMaxSide(1920, 1080, 1, 9/16, 320, 180, 120, 1920);
  Assert.AreEqual(0, R, 'Must return 0 when video is already small enough');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideZeroFrames;
var
  R: Integer;
begin
  R := CalcExtractionMaxSide(1024, 768, 0, 9/16, 1920, 1080, 120, 1920);
  Assert.AreEqual(0, R, 'Must return 0 for zero frames');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideZeroViewport;
var
  R: Integer;
begin
  R := CalcExtractionMaxSide(0, 0, 4, 9/16, 1920, 1080, 120, 1920);
  Assert.AreEqual(0, R, 'Must return 0 for zero viewport');
end;

procedure TTestExtractionPlanner.TestCalcMaxSideSingleFrame;
var
  R: Integer;
begin
  { Single frame in 1920x1080 viewport: bigger side should match the viewport }
  R := CalcExtractionMaxSide(1920, 1080, 1, 9/16, 3840, 2160, 120, 1920);
  Assert.IsTrue(R > 0, 'Should scale down 3840 to fit viewport');
  Assert.IsTrue(R <= 1920, 'Must not exceed max');
end;

{ PickSaveMaxSide tests: per-frame cap selection for the save-at-native path. }

procedure TTestExtractionPlanner.TestPickSaveMaxSideScalingOff;
begin
  { ScaledExtraction off: caller wants raw native, no cap regardless of MaxFrameSide. }
  Assert.AreEqual(0, PickSaveMaxSide(3840, 2160, False, 1920),
    'Scaling off must yield 0 (= ffmpeg passes native through)');
end;

procedure TTestExtractionPlanner.TestPickSaveMaxSideNativeBelowCap;
begin
  { 720x1280 native with cap 1920: cap is a no-op, return 0 so ffmpeg keeps native. }
  Assert.AreEqual(0, PickSaveMaxSide(720, 1280, True, 1920),
    'Native below cap must yield 0 (no scaling needed)');
end;

procedure TTestExtractionPlanner.TestPickSaveMaxSideNativeEqualsCap;
begin
  { 1080x1920 native with cap 1920: bigger side already at cap, keep native. }
  Assert.AreEqual(0, PickSaveMaxSide(1080, 1920, True, 1920),
    'Native equal to cap must yield 0 (no scaling needed)');
end;

procedure TTestExtractionPlanner.TestPickSaveMaxSideNativeAboveCap;
begin
  { 4K native with cap 1920: must downscale to cap. }
  Assert.AreEqual(1920, PickSaveMaxSide(3840, 2160, True, 1920),
    'Native above cap must yield the cap value');
end;

procedure TTestExtractionPlanner.TestPickSaveMaxSideZeroCap;
begin
  { Cap 0 is treated as "no cap": return 0 (native). Defensive guard. }
  Assert.AreEqual(0, PickSaveMaxSide(3840, 2160, True, 0),
    'Zero cap must yield 0 (defensive: treat as no cap)');
end;

procedure TTestExtractionPlanner.TestPickSaveMaxSideZeroNative;
begin
  { Native dimensions unknown (probe failed): return 0 so caller falls back to native ffmpeg pass. }
  Assert.AreEqual(0, PickSaveMaxSide(0, 0, True, 1920),
    'Zero native must yield 0 (no info to apply cap against)');
end;

procedure TTestExtractionPlanner.TestPickSaveMaxSidePortraitNative;
begin
  { Portrait video where height is the bigger side: cap compared against Max(W,H). }
  Assert.AreEqual(1920, PickSaveMaxSide(2160, 3840, True, 1920),
    'Portrait native above cap (height is bigger side) must yield cap');
  Assert.AreEqual(0, PickSaveMaxSide(720, 1280, True, 1920),
    'Portrait native below cap must yield 0');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExtractionPlanner);

end.
