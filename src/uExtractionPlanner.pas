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

  TSettingsChange = (scCacheChanged, scFFmpegPathChanged, scSkipEdgesChanged, scScaledExtractionChanged, scUseKeyframesChanged, scRespectAnamorphicChanged, scRandomExtractionChanged, scCacheRandomChanged);
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
    RespectAnamorphic: Boolean;
    RandomExtraction: Boolean;
    RandomPercent: Integer;
    CacheRandomFrames: Boolean;
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

{Picks the per-frame MaxSide ffmpeg cap to use when saving with the
 "Save at view resolution" toggle off. The save path wants the highest
 sensible resolution for the saved image: native when it fits the
 user-configured cap, otherwise the cap.
 Returns 0 (= no scaling, ffmpeg yields native) when AScaledExtraction is
 off, or when the source's bigger side already fits within AMaxFrameSide
 (so capping would be a no-op).
 Returns AMaxFrameSide when the source exceeds the cap, instructing the
 extractor to downscale to the cap's bigger side.
 Decoupled from the live-view CalcExtractionMaxSide because the save
 path is not driven by viewport area: the user expects the highest
 quality the cap allows, not the smallest size that fits the panel.}
function PickSaveMaxSide(ANativeW, ANativeH: Integer; AScaledExtraction: Boolean; AMaxFrameSide: Integer): Integer;

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

function PickSaveMaxSide(ANativeW, ANativeH: Integer; AScaledExtraction: Boolean; AMaxFrameSide: Integer): Integer;
var
  NativeBigger: Integer;
begin
  Result := 0;
  if not AScaledExtraction then
    Exit;
  if AMaxFrameSide <= 0 then
    Exit;
  NativeBigger := Max(ANativeW, ANativeH);
  {Unknown native dimensions (probe failed or not yet populated): we have
   no basis to decide whether the cap would change anything, so yield 0
   and let the caller pass through to ffmpeg with no scale filter.}
  if NativeBigger <= 0 then
    Exit;
  {Cap would be a no-op (native already fits), keep native.}
  if NativeBigger <= AMaxFrameSide then
    Exit;
  Result := AMaxFrameSide;
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
  Result.RespectAnamorphic := ASettings.RespectAnamorphic;
  Result.RandomExtraction := ASettings.RandomExtraction;
  Result.RandomPercent := ASettings.RandomPercent;
  Result.CacheRandomFrames := ASettings.CacheRandomFrames;
end;

function DetectSettingsChanges(const AOld: TSettingsSnapshot; ASettings: TPluginSettings): TSettingsChanges;
begin
  Result := [];

  if (ASettings.CacheEnabled <> AOld.CacheEnabled) or (ASettings.CacheFolder <> AOld.CacheFolder) or (ASettings.CacheMaxSizeMB <> AOld.CacheMaxSizeMB) then
    Include(Result, scCacheChanged);

  {Any change to the path counts, including clearing a custom path back to
   '' (auto-detect). The earlier "and ASettings.FFmpegExePath <> ''" guard
   silently swallowed the revert-to-auto case so the user's change had no
   visible effect until next file load.}
  if ASettings.FFmpegExePath <> AOld.FFmpegExePath then
    Include(Result, scFFmpegPathChanged);

  if ASettings.SkipEdgesPercent <> AOld.SkipEdgesPercent then
    Include(Result, scSkipEdgesChanged);

  if (ASettings.ScaledExtraction <> AOld.ScaledExtraction) or (ASettings.MinFrameSide <> AOld.MinFrameSide) or (ASettings.MaxFrameSide <> AOld.MaxFrameSide) then
    Include(Result, scScaledExtractionChanged);

  if ASettings.UseKeyframes <> AOld.UseKeyframes then
    Include(Result, scUseKeyframesChanged);

  if ASettings.RespectAnamorphic <> AOld.RespectAnamorphic then
    Include(Result, scRespectAnamorphicChanged);

  {Random extraction: enabling/disabling or moving the slider while
   enabled both warrant a re-extract. Slider movement while disabled
   does not, since the slider only matters when active or when the user
   invokes Shuffle on demand.}
  if (ASettings.RandomExtraction <> AOld.RandomExtraction) or (ASettings.RandomExtraction and (ASettings.RandomPercent <> AOld.RandomPercent)) then
    Include(Result, scRandomExtractionChanged);

  if ASettings.CacheRandomFrames <> AOld.CacheRandomFrames then
    Include(Result, scCacheRandomChanged);
end;

end.
