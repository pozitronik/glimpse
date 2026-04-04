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

initialization
  TDUnitX.RegisterTestFixture(TTestExtractionPlanner);

end.
