{Worker chunk planning and settings change detection.
 Pure computation: no threading, no UI, no I/O.}
unit uExtractionPlanner;

interface

uses
  uSettings;

type
  TWorkerChunk = record
    Start: Integer; {zero-based index into offset array}
    Len: Integer; {number of frames in this chunk}
  end;

  TSettingsChange = (scCacheChanged, scFFmpegPathChanged, scSkipEdgesChanged, scScaledExtractionChanged, scUseKeyframesChanged);
  TSettingsChanges = set of TSettingsChange;

  TSettingsSnapshot = record
    CacheEnabled: Boolean;
    CacheFolder: string;
    CacheMaxSizeMB: Integer;
    SkipEdgesPercent: Integer;
    FFmpegExePath: string;
    ScaledExtraction: Boolean;
    MinFrameSide: Integer;
    MaxFrameSide: Integer;
    UseKeyframes: Boolean;
  end;

  {Splits FrameCount frames into chunks for parallel extraction.
   MaxWorkers=0 means one worker per frame.
   MaxThreads caps the actual thread count (-1 = no limit, 0 = CPU core count).
   Result is never empty when FrameCount > 0.}
function PlanWorkerChunks(FrameCount, MaxWorkers, MaxThreads: Integer): TArray<TWorkerChunk>;

{Captures the settings fields relevant to change detection.}
function TakeSettingsSnapshot(ASettings: TPluginSettings): TSettingsSnapshot;

{Compares current settings against a previous snapshot.
 Returns the set of changes that require action.}
function DetectSettingsChanges(const AOld: TSettingsSnapshot; ASettings: TPluginSettings): TSettingsChanges;

{Calculates the extraction max side (bigger dimension) for scaled extraction.
 Returns 0 when scaling is not needed (video already fits, or feature disabled).
 AViewportW/H: available display area; AFrameCount: number of frames;
 AAspectRatio: height/width ratio of the video;
 ANativeW/H: native video dimensions;
 AMinSide/AMaxSide: user-configured boundaries for the bigger side.}
function CalcExtractionMaxSide(AViewportW, AViewportH, AFrameCount: Integer; AAspectRatio: Double; ANativeW, ANativeH, AMinSide, AMaxSide: Integer): Integer;

implementation

uses
  System.Math, uDefaults;

function PlanWorkerChunks(FrameCount, MaxWorkers, MaxThreads: Integer): TArray<TWorkerChunk>;
var
  WorkerCount, ThreadCap, ChunkSize, W, Start, Len: Integer;
begin
  if FrameCount <= 0 then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  if MaxWorkers = 0 then
    WorkerCount := FrameCount
  else
    WorkerCount := Min(MaxWorkers, FrameCount);

  {Apply thread cap: -1 = no limit, 0 = CPU core count, >0 = explicit}
  if MaxThreads >= 0 then
  begin
    if MaxThreads > 0 then
      ThreadCap := MaxThreads
    else
      ThreadCap := CPUCount;
    if WorkerCount > ThreadCap then
      WorkerCount := ThreadCap;
  end;

  if WorkerCount < 1 then
    WorkerCount := 1;

  ChunkSize := (FrameCount + WorkerCount - 1) div WorkerCount;
  SetLength(Result, WorkerCount);

  for W := 0 to WorkerCount - 1 do
  begin
    Start := W * ChunkSize;
    Len := Min(ChunkSize, FrameCount - Start);
    Result[W].Start := Start;
    Result[W].Len := Len;
  end;
end;

function CalcExtractionMaxSide(AViewportW, AViewportH, AFrameCount: Integer; AAspectRatio: Double; ANativeW, ANativeH, AMinSide, AMaxSide: Integer): Integer;
var
  AreaPerFrame, FrameW, FrameH: Double;
  BiggerSide, NativeBigger: Integer;
begin
  Result := 0;
  if (AViewportW <= 0) or (AViewportH <= 0) or (AFrameCount <= 0) then
    Exit;
  if AAspectRatio <= 0 then
    AAspectRatio := 9.0 / 16.0;

  {Area available per frame, then derive dimensions preserving aspect ratio}
  AreaPerFrame := (Int64(AViewportW) * AViewportH) / AFrameCount;
  {AspectRatio = H/W, so W = sqrt(Area / AR), H = sqrt(Area * AR)}
  FrameW := Sqrt(AreaPerFrame / AAspectRatio);
  FrameH := FrameW * AAspectRatio;
  BiggerSide := Round(Max(FrameW, FrameH));

  {Clamp to user-configured boundaries}
  BiggerSide := EnsureRange(BiggerSide, AMinSide, AMaxSide);

  {Round up to nearest bucket for cache key stability}
  BiggerSide := ((BiggerSide + SCALE_BUCKET - 1) div SCALE_BUCKET) * SCALE_BUCKET;

  {No point scaling if video is already small enough}
  NativeBigger := Max(ANativeW, ANativeH);
  if (NativeBigger > 0) and (NativeBigger <= BiggerSide) then
    Exit(0);

  Result := BiggerSide;
end;

function TakeSettingsSnapshot(ASettings: TPluginSettings): TSettingsSnapshot;
begin
  Result.CacheEnabled := ASettings.CacheEnabled;
  Result.CacheFolder := ASettings.CacheFolder;
  Result.CacheMaxSizeMB := ASettings.CacheMaxSizeMB;
  Result.SkipEdgesPercent := ASettings.SkipEdgesPercent;
  Result.FFmpegExePath := ASettings.FFmpegExePath;
  Result.ScaledExtraction := ASettings.ScaledExtraction;
  Result.MinFrameSide := ASettings.MinFrameSide;
  Result.MaxFrameSide := ASettings.MaxFrameSide;
  Result.UseKeyframes := ASettings.UseKeyframes;
end;

function DetectSettingsChanges(const AOld: TSettingsSnapshot; ASettings: TPluginSettings): TSettingsChanges;
begin
  Result := [];

  if (ASettings.CacheEnabled <> AOld.CacheEnabled) or (ASettings.CacheFolder <> AOld.CacheFolder) or (ASettings.CacheMaxSizeMB <> AOld.CacheMaxSizeMB) then
    Include(Result, scCacheChanged);

  if (ASettings.FFmpegExePath <> AOld.FFmpegExePath) and (ASettings.FFmpegExePath <> '') then
    Include(Result, scFFmpegPathChanged);

  if ASettings.SkipEdgesPercent <> AOld.SkipEdgesPercent then
    Include(Result, scSkipEdgesChanged);

  if (ASettings.ScaledExtraction <> AOld.ScaledExtraction) or (ASettings.MinFrameSide <> AOld.MinFrameSide) or (ASettings.MaxFrameSide <> AOld.MaxFrameSide) then
    Include(Result, scScaledExtractionChanged);

  if ASettings.UseKeyframes <> AOld.UseKeyframes then
    Include(Result, scUseKeyframesChanged);
end;

end.
