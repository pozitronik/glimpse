{Frame offset calculator for uniform time distribution.
 Pure computation: no I/O, no dependencies on UI or ffmpeg.}
unit uFrameOffsets;

interface

type
  TFrameOffset = record
    Index: Integer; {1-based frame number}
    TimeOffset: Double; {seconds from video start}
  end;

  TFrameOffsetArray = array of TFrameOffset;

  {Calculates evenly-spaced frame offsets across a video's duration.
   Formula: offset_i = EffStart + EffDuration * (2i - 1) / (2N)
   where EffStart and EffDuration account for edge guard skipping.
   @param ADuration Video duration in seconds (must be > 0)
   @param AFrameCount Number of frames to extract (must be >= 1)
   @param ASkipEdgesPercent Percentage of video to skip at start and end (0 = disabled, clamped to 0..49)
   @return Array of frame offsets with 1-based indices
   @raises EArgumentException if ADuration <= 0 or AFrameCount < 1}
function CalculateFrameOffsets(ADuration: Double; AFrameCount: Integer; ASkipEdgesPercent: Integer = 0): TFrameOffsetArray;

{Calculates randomised frame offsets within their respective slices.
 Each frame i lives in slice i (effective range divided into N equal
 slices); the chosen time is the slice midpoint plus a random jitter
 capped by the randomness window:
 slice_len    = effective_range / N
 midpoint_i   = effective_start + (i + 0.5) * slice_len
 window_half  = slice_len / 2 * (P / 100)
 t_i          = midpoint_i + Random(-window_half .. +window_half)
 Frame ordering is preserved by construction (P clamped to 1..100 keeps
 t_i strictly inside slice i, never crossing into a neighbour). Pulls
 randomness from the global Random — caller is responsible for calling
 Randomize once at startup to seed it.
 @param ADuration Video duration in seconds (must be > 0)
 @param AFrameCount Number of frames to extract (must be >= 1)
 @param ASkipEdgesPercent Same semantics as CalculateFrameOffsets
 @param ARandomnessPercent Jitter strength 1..100 (clamped). At 1, the
 window is 1% of the slice; at 100, the entire slice is in play.
 @raises EArgumentException for invalid inputs.}
function CalculateRandomFrameOffsets(ADuration: Double; AFrameCount, ASkipEdgesPercent, ARandomnessPercent: Integer): TFrameOffsetArray;

{Single source of truth for the random-vs-deterministic offset choice
 made by both plugins. ARandom selects between CalculateRandomFrameOffsets
 and CalculateFrameOffsets; the other parameters are forwarded as-is.
 Centralising the dispatch here keeps WLX and WCX in lockstep when the
 random/deterministic decision evolves (e.g. future stratified or
 deterministic-but-jittered modes).}
function BuildFrameOffsets(ADuration: Double; AFrameCount, ASkipEdgesPercent, ARandomPercent: Integer; ARandom: Boolean): TFrameOffsetArray;

{Formats a time in seconds as HH:MM:SS.mmm for display.}
function FormatTimecode(ASeconds: Double): string;

{Formats a time in seconds as HH-MM-SS.mmm for use in filenames.}
function FormatTimecodeForFilename(ASeconds: Double): string;

{Formats a duration in seconds as human-readable H:MM:SS or M:SS.
 Returns '?' for non-positive values.}
function FormatDurationHMS(ASeconds: Double): string;

implementation

uses
  System.SysUtils, System.Math;

function CalculateFrameOffsets(ADuration: Double; AFrameCount: Integer; ASkipEdgesPercent: Integer): TFrameOffsetArray;
var
  EffStart, EffEnd, EffDuration: Double;
  I: Integer;
begin
  if IsNaN(ADuration) or IsInfinite(ADuration) or (ADuration <= 0) then
    raise EArgumentException.Create('Duration must be a finite positive number');
  if AFrameCount < 1 then
    raise EArgumentException.Create('Frame count must be at least 1');
  if (ASkipEdgesPercent < 0) or (ASkipEdgesPercent > 49) then
    raise EArgumentException.CreateFmt('SkipEdgesPercent must be 0..49, got %d', [ASkipEdgesPercent]);

  if ASkipEdgesPercent > 0 then
  begin
    EffStart := ADuration * ASkipEdgesPercent / 100.0;
    EffEnd := ADuration * (100 - ASkipEdgesPercent) / 100.0;
  end else begin
    EffStart := 0;
    EffEnd := ADuration;
  end;
  EffDuration := EffEnd - EffStart;

  SetLength(Result, AFrameCount);
  for I := 0 to AFrameCount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := EffStart + EffDuration * (2 * (I + 1) - 1) / (2 * AFrameCount);
  end;
end;

function CalculateRandomFrameOffsets(ADuration: Double; AFrameCount, ASkipEdgesPercent, ARandomnessPercent: Integer): TFrameOffsetArray;
var
  EffStart, EffEnd, EffDuration, SliceLen, Midpoint, WindowHalf, Jitter: Double;
  P, I: Integer;
begin
  if IsNaN(ADuration) or IsInfinite(ADuration) or (ADuration <= 0) then
    raise EArgumentException.Create('Duration must be a finite positive number');
  if AFrameCount < 1 then
    raise EArgumentException.Create('Frame count must be at least 1');
  if (ASkipEdgesPercent < 0) or (ASkipEdgesPercent > 49) then
    raise EArgumentException.CreateFmt('SkipEdgesPercent must be 0..49, got %d', [ASkipEdgesPercent]);

  {Clamp randomness silently rather than raising: the slider in the UI
   is bounded already; callers that pass an out-of-range integer (e.g.
   from a hand-edited INI) should still get sensible behaviour.}
  P := EnsureRange(ARandomnessPercent, 1, 100);

  if ASkipEdgesPercent > 0 then
  begin
    EffStart := ADuration * ASkipEdgesPercent / 100.0;
    EffEnd := ADuration * (100 - ASkipEdgesPercent) / 100.0;
  end else begin
    EffStart := 0;
    EffEnd := ADuration;
  end;
  EffDuration := EffEnd - EffStart;
  SliceLen := EffDuration / AFrameCount;
  WindowHalf := SliceLen / 2.0 * (P / 100.0);

  SetLength(Result, AFrameCount);
  for I := 0 to AFrameCount - 1 do
  begin
    Midpoint := EffStart + (I + 0.5) * SliceLen;
    {Random returns [0, 1). Map to [-WindowHalf, +WindowHalf). The
     half-open upper bound (+WindowHalf is exclusive) introduces a
     sub-millisecond bias that is well below ffmpeg's seek granularity
     and visually irrelevant for frame selection; symmetry would cost a
     conditional branch for no observable benefit.}
    Jitter := (Random * 2.0 - 1.0) * WindowHalf;
    Result[I].Index := I + 1;
    Result[I].TimeOffset := Midpoint + Jitter;
  end;
end;

function BuildFrameOffsets(ADuration: Double; AFrameCount, ASkipEdgesPercent, ARandomPercent: Integer; ARandom: Boolean): TFrameOffsetArray;
begin
  if ARandom then
    Result := CalculateRandomFrameOffsets(ADuration, AFrameCount, ASkipEdgesPercent, ARandomPercent)
  else
    Result := CalculateFrameOffsets(ADuration, AFrameCount, ASkipEdgesPercent);
end;

function FormatTimecode(ASeconds: Double): string;
var
  TotalMs: Int64;
  H, M, S, Ms: Integer;
begin
  TotalMs := Round(ASeconds * 1000);
  if TotalMs < 0 then
    TotalMs := 0;

  H := TotalMs div 3600000;
  TotalMs := TotalMs mod 3600000;
  M := TotalMs div 60000;
  TotalMs := TotalMs mod 60000;
  S := TotalMs div 1000;
  Ms := TotalMs mod 1000;

  Result := Format('%.2d:%.2d:%.2d.%.3d', [H, M, S, Ms]);
end;

function FormatTimecodeForFilename(ASeconds: Double): string;
begin
  Result := StringReplace(FormatTimecode(ASeconds), ':', '-', [rfReplaceAll]);
end;

function FormatDurationHMS(ASeconds: Double): string;
var
  Total, H, M, S: Integer;
begin
  if ASeconds <= 0 then
    Exit('?');
  Total := Round(ASeconds);
  H := Total div 3600;
  M := (Total mod 3600) div 60;
  S := Total mod 60;
  if H > 0 then
    Result := Format('%d:%.2d:%.2d', [H, M, S])
  else
    Result := Format('%d:%.2d', [M, S]);
end;

end.
