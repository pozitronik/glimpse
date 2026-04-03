{ Worker chunk planning and settings change detection.
  Pure computation: no threading, no UI, no I/O. }
unit uExtractionPlanner;

interface

uses
  uSettings;

type
  TWorkerChunk = record
    Start: Integer;  { zero-based index into offset array }
    Len: Integer;    { number of frames in this chunk }
  end;

  TSettingsChange = (scCacheChanged, scFFmpegPathChanged, scSkipEdgesChanged);
  TSettingsChanges = set of TSettingsChange;

  TSettingsSnapshot = record
    CacheEnabled: Boolean;
    CacheFolder: string;
    CacheMaxSizeMB: Integer;
    SkipEdgesPercent: Integer;
    FFmpegExePath: string;
  end;

{ Splits FrameCount frames into chunks for parallel extraction.
  MaxWorkers=0 means one worker per frame; result is never empty
  when FrameCount > 0. }
function PlanWorkerChunks(FrameCount, MaxWorkers: Integer): TArray<TWorkerChunk>;

{ Captures the settings fields relevant to change detection. }
function TakeSettingsSnapshot(ASettings: TPluginSettings): TSettingsSnapshot;

{ Compares current settings against a previous snapshot.
  Returns the set of changes that require action. }
function DetectSettingsChanges(const AOld: TSettingsSnapshot;
  ASettings: TPluginSettings): TSettingsChanges;

implementation

uses
  System.Math;

function PlanWorkerChunks(FrameCount, MaxWorkers: Integer): TArray<TWorkerChunk>;
var
  WorkerCount, ChunkSize, W, Start, Len: Integer;
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

function TakeSettingsSnapshot(ASettings: TPluginSettings): TSettingsSnapshot;
begin
  Result.CacheEnabled := ASettings.CacheEnabled;
  Result.CacheFolder := ASettings.CacheFolder;
  Result.CacheMaxSizeMB := ASettings.CacheMaxSizeMB;
  Result.SkipEdgesPercent := ASettings.SkipEdgesPercent;
  Result.FFmpegExePath := ASettings.FFmpegExePath;
end;

function DetectSettingsChanges(const AOld: TSettingsSnapshot;
  ASettings: TPluginSettings): TSettingsChanges;
begin
  Result := [];

  if (ASettings.CacheEnabled <> AOld.CacheEnabled)
    or (ASettings.CacheFolder <> AOld.CacheFolder)
    or (ASettings.CacheMaxSizeMB <> AOld.CacheMaxSizeMB) then
    Include(Result, scCacheChanged);

  if (ASettings.FFmpegExePath <> AOld.FFmpegExePath)
    and (ASettings.FFmpegExePath <> '') then
    Include(Result, scFFmpegPathChanged);

  if ASettings.SkipEdgesPercent <> AOld.SkipEdgesPercent then
    Include(Result, scSkipEdgesChanged);
end;

end.
