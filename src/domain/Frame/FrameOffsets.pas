{Pure frame-offset calculation and timecode formatting.}
unit FrameOffsets;

interface

type
  TFrameOffset = record
    Index: Integer;
    TimeOffset: Double;
  end;

  TFrameOffsetArray = array of TFrameOffset;

  {Formula: offset_i = EffStart + EffDuration * (2i - 1) / (2N)
   ASkipEdgesPercent: 0..49 (raises otherwise).
   Raises on invalid duration or zero frame count.}
function CalculateFrameOffsets(ADuration: Double; AFrameCount: Integer; ASkipEdgesPercent: Integer = 0): TFrameOffsetArray;

{Each frame lives in its slice; midpoint plus capped jitter.
 ARandomnessPercent 1..100 (clamped). Pulls from global Random; caller
 must Randomize at startup.}
function CalculateRandomFrameOffsets(ADuration: Double; AFrameCount, ASkipEdgesPercent, ARandomnessPercent: Integer): TFrameOffsetArray;

{Centralises the random vs deterministic decision so WLX and WCX stay
 in lockstep when this evolves.}
function BuildFrameOffsets(ADuration: Double; AFrameCount, ASkipEdgesPercent, ARandomPercent: Integer; ARandom: Boolean): TFrameOffsetArray;

{HH:MM:SS.mmm}
function FormatTimecode(ASeconds: Double): string;

{HH-MM-SS.mmm for filenames.}
function FormatTimecodeForFilename(ASeconds: Double): string;

{H:MM:SS or M:SS; '?' for non-positive values.}
function FormatDurationHMS(ASeconds: Double): string;

{Scales by magnitude: 'S.mmm s' / 'M:SS.mmm' / 'H:MM:SS' (ms dropped
 for hours to keep the status-bar column tight). Cardinal handles
 GetTickCount's full ~49.7-day range.}
function FormatLoadTimeMs(AElapsedMs: Cardinal): string;

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

  {Silent clamp so hand-edited INI values get sensible behaviour.}
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

function FormatLoadTimeMs(AElapsedMs: Cardinal): string;
var
  H, M, S, Ms: Integer;
begin
  H := AElapsedMs div 3600000;
  M := (AElapsedMs mod 3600000) div 60000;
  S := (AElapsedMs mod 60000) div 1000;
  Ms := AElapsedMs mod 1000;
  if H > 0 then
    Result := Format('%d:%.2d:%.2d', [H, M, S])
  else if M > 0 then
    Result := Format('%d:%.2d.%.3d', [M, S, Ms])
  else
    Result := Format('%d.%.3d s', [S, Ms]);
end;

end.
