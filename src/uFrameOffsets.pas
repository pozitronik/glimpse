/// Frame offset calculator for uniform time distribution.
/// Pure computation: no I/O, no dependencies on UI or ffmpeg.
unit uFrameOffsets;

interface

type
  TFrameOffset = record
    Index: Integer;       { 1-based frame number }
    TimeOffset: Double;   { seconds from video start }
  end;

  TFrameOffsetArray = array of TFrameOffset;

/// Calculates evenly-spaced frame offsets across a video's duration.
///
/// Formula: offset_i = EffStart + EffDuration * (2i - 1) / (2N)
/// where EffStart and EffDuration account for edge guard skipping.
///
/// @param ADuration Video duration in seconds (must be > 0)
/// @param AFrameCount Number of frames to extract (must be >= 1)
/// @param ASkipEdgesPercent Percentage of video to skip at start and end (0 = disabled, clamped to 0..49)
/// @return Array of frame offsets with 1-based indices
/// @raises EArgumentException if ADuration <= 0 or AFrameCount < 1
function CalculateFrameOffsets(ADuration: Double; AFrameCount: Integer;
  ASkipEdgesPercent: Integer = 0): TFrameOffsetArray;

/// Formats a time in seconds as HH:MM:SS.mmm for display.
function FormatTimecode(ASeconds: Double): string;

/// Formats a time in seconds as HH-MM-SS.mmm for use in filenames.
function FormatTimecodeForFilename(ASeconds: Double): string;

implementation

uses
  System.SysUtils, System.Math;

function CalculateFrameOffsets(ADuration: Double; AFrameCount: Integer;
  ASkipEdgesPercent: Integer): TFrameOffsetArray;
var
  EffStart, EffEnd, EffDuration: Double;
  I: Integer;
begin
  if ADuration <= 0 then
    raise EArgumentException.Create('Duration must be positive');
  if AFrameCount < 1 then
    raise EArgumentException.Create('Frame count must be at least 1');

  ASkipEdgesPercent := EnsureRange(ASkipEdgesPercent, 0, 49);

  if ASkipEdgesPercent > 0 then
  begin
    EffStart := ADuration * ASkipEdgesPercent / 100.0;
    EffEnd := ADuration * (100 - ASkipEdgesPercent) / 100.0;
  end
  else
  begin
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

end.
