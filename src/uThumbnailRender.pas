{ Synchronous thumbnail renderer for the WLX TC panel preview path.
  Probes a video, extracts one frame (single mode) or several (grid mode),
  optionally combines them, and downscales to TC's requested cell size.
  Pure pipeline: no UI, no async; safe to call from a TC worker thread. }
unit uThumbnailRender;

interface

uses
  Winapi.Windows, Vcl.Graphics,
  uTypes, uSettings, uFFmpegExe, uProbeCache, uCache, uFrameOffsets;

{ Computes the time offsets to extract for a thumbnail.
  Single mode: one offset at APositionPercent% of duration.
  Grid mode: AGridFrames evenly-spaced offsets honoring ASkipEdgesPercent.
  @raises EArgumentException if ADuration <= 0 or AGridFrames < 1 in grid mode. }
function CalcThumbnailOffsets(ADuration: Double; AMode: TThumbnailMode;
  APositionPercent, AGridFrames, ASkipEdgesPercent: Integer): TFrameOffsetArray;

{ Picks the cache-stable extraction MaxSide for a TC-requested cell size.
  Buckets to SCALE_BUCKET so neighboring TC sizes share cache entries.
  Returns the larger dimension (the one ffmpeg will fit to). }
function PickThumbnailExtractionMaxSide(AReqWidth, AReqHeight: Integer): Integer;

{ Renders a thumbnail bitmap for the given video file.
  Returns nil if disabled, on probe failure, or on extraction failure.
  Caller owns the returned bitmap.
  ACache may be a TNullFrameCache if caching is off; never pass nil.
  AProbeCache consolidates probe results across the thumbnail panel and the
  lister form so folder scrolling does not re-spawn ffmpeg for files already
  probed once; never pass nil. }
function RenderThumbnail(const AFFmpeg: TFFmpegExe; const AFileName: string;
  AReqWidth, AReqHeight: Integer; const ASettings: TPluginSettings;
  const ACache: IFrameCache; const AProbeCache: TProbeCache): TBitmap;

implementation

uses
  System.SysUtils, System.Math,
  uDefaults, uCombinedImage, uBitmapResize;

function CalcThumbnailOffsets(ADuration: Double; AMode: TThumbnailMode;
  APositionPercent, AGridFrames, ASkipEdgesPercent: Integer): TFrameOffsetArray;
var
  Pct: Integer;
  Offset: Double;
begin
  if ADuration <= 0 then
    raise EArgumentException.Create('Duration must be positive');

  if AMode = tnmSingle then
  begin
    Pct := EnsureRange(APositionPercent, 0, 100);
    { Pull back from the very end so ffmpeg always has a frame to decode;
      pulling back from the start by a few ms keeps Position=0 valid too. }
    Offset := ADuration * Pct / 100.0;
    if Offset >= ADuration then
      Offset := ADuration * 0.99;
    if Offset < 0 then
      Offset := 0;
    SetLength(Result, 1);
    Result[0].Index := 1;
    Result[0].TimeOffset := Offset;
    Exit;
  end;

  { Grid mode: reuse the existing planner for evenly spaced frames }
  if AGridFrames < 1 then
    raise EArgumentException.Create('Grid frames count must be at least 1');
  Result := CalculateFrameOffsets(ADuration, AGridFrames, ASkipEdgesPercent);
end;

function PickThumbnailExtractionMaxSide(AReqWidth, AReqHeight: Integer): Integer;
var
  Bigger: Integer;
begin
  Bigger := Max(AReqWidth, AReqHeight);
  if Bigger <= 0 then
    Exit(SCALE_BUCKET);
  { Bucket up so e.g. 96, 100, 128 all share the same cache entry }
  Result := ((Bigger + SCALE_BUCKET - 1) div SCALE_BUCKET) * SCALE_BUCKET;
end;

{ Resolves the cache + extract pair for a single offset. The cache lookup
  is keyed by offset and MaxSide; on miss, ffmpeg runs, the result is stored,
  and the bitmap is returned. Caller owns the result; nil = failure. }
function FetchOrExtract(const AFFmpeg: TFFmpegExe; const AFileName: string;
  AOffset: Double; const AOptions: TExtractionOptions;
  const ACache: IFrameCache; ATimeoutMs: DWORD): TBitmap;
begin
  Result := ACache.TryGet(AFileName, AOffset, AOptions.MaxSide,
    AOptions.UseKeyframes);
  if Result <> nil then
    Exit;

  Result := AFFmpeg.ExtractFrame(AFileName, AOffset, AOptions, ATimeoutMs);
  if Result <> nil then
    ACache.Put(AFileName, AOffset, Result, AOptions.MaxSide,
      AOptions.UseKeyframes);
end;

{ Downscales ABmp into a fresh bitmap that fits within AReqW x AReqH while
  preserving aspect ratio. Returns ABmp itself when no scaling is needed,
  in which case the caller still owns ABmp; otherwise frees ABmp and returns
  the new bitmap. Single ownership transfer keeps caller code simple. }
function DownscaleAndAdopt(ABmp: TBitmap; AReqW, AReqH: Integer): TBitmap;
var
  Scale: Double;
  NewW, NewH, Cap: Integer;
  Down: TBitmap;
begin
  Result := ABmp;
  if (ABmp = nil) or (AReqW <= 0) or (AReqH <= 0) then
    Exit;
  if (ABmp.Width <= AReqW) and (ABmp.Height <= AReqH) then
    Exit;

  { Compute the long side that makes both dimensions fit }
  Scale := Min(AReqW / ABmp.Width, AReqH / ABmp.Height);
  NewW := Max(1, Round(ABmp.Width * Scale));
  NewH := Max(1, Round(ABmp.Height * Scale));
  Cap := Max(NewW, NewH);

  Down := DownscaleBitmapToFit(ABmp, Cap);
  if Down <> nil then
  begin
    ABmp.Free;
    Result := Down;
  end;
end;

function RenderThumbnail(const AFFmpeg: TFFmpegExe; const AFileName: string;
  AReqWidth, AReqHeight: Integer; const ASettings: TPluginSettings;
  const ACache: IFrameCache; const AProbeCache: TProbeCache): TBitmap;
var
  Info: TVideoInfo;
  Offsets: TFrameOffsetArray;
  Frames: TArray<TBitmap>;
  Options: TExtractionOptions;
  I: Integer;
begin
  Result := nil;
  if (AFFmpeg = nil) or (ASettings = nil) or (ACache = nil) or (AProbeCache = nil) then
    Exit;
  if not ASettings.ThumbnailsEnabled then
    Exit;
  if (AReqWidth <= 0) or (AReqHeight <= 0) then
    Exit;

  { Single try/except wraps the whole pipeline so any failure releases
    in-progress bitmaps. Thumbnail errors must never propagate to TC. }
  try
    Info := AProbeCache.TryGetOrProbe(AFileName, AFFmpeg.ExePath);
    if not Info.IsValid then
      Exit;

    try
      Offsets := CalcThumbnailOffsets(Info.Duration, ASettings.ThumbnailMode,
        ASettings.ThumbnailPosition, ASettings.ThumbnailGridFrames,
        ASettings.SkipEdgesPercent);
    except
      on EArgumentException do
        Exit;
    end;
    if Length(Offsets) = 0 then
      Exit;

    { Build extraction options. Reuse user's HW accel and keyframes settings.
      BMP pipe is preferred for speed (we have memory headroom for tiny thumbs).
      MaxSide is bucketed from the requested cell size, not the user-configured
      MaxFrameSide, so thumbnail extractions stay small. }
    Options := Default(TExtractionOptions);
    Options.UseBmpPipe := True;
    Options.HwAccel := ASettings.HwAccel;
    Options.UseKeyframes := ASettings.UseKeyframes;
    Options.MaxSide := PickThumbnailExtractionMaxSide(AReqWidth, AReqHeight);

    SetLength(Frames, Length(Offsets));
    try
      for I := 0 to High(Offsets) do
      begin
        Frames[I] := FetchOrExtract(AFFmpeg, AFileName, Offsets[I].TimeOffset,
          Options, ACache, DEF_THUMBNAIL_TIMEOUT_MS);
        { Single mode: a missing frame is a hard failure (no fallback).
          Grid mode: we still try to render whatever frames we got; nil cells
          are tolerated by RenderCombinedImage. }
        if (ASettings.ThumbnailMode = tnmSingle) and (Frames[I] = nil) then
          Exit;
      end;

      if ASettings.ThumbnailMode = tnmSingle then
      begin
        { Detach the only frame; the finally block leaves it alone }
        Result := Frames[0];
        Frames[0] := nil;
      end
      else
      begin
        { Combine into a grid. Gap=0 keeps tiny thumbnails tight; timecode
          overlay is suppressed because thumbnail cells are too small to read. }
        Result := RenderCombinedImage(Frames, Offsets, 0, 0,
          ASettings.Background, False,
          ASettings.TimestampFontName, ASettings.TimestampFontSize);
        if Result = nil then
          Exit;
      end;
    finally
      { Free any frames we still own (all combined-mode frames; for single
        mode, the surviving frame was detached and Frames[0] is nil). }
      for I := 0 to High(Frames) do
        Frames[I].Free;
    end;

    Result := DownscaleAndAdopt(Result, AReqWidth, AReqHeight);
  except
    { Anything that escaped the inner cleanup must not leak Result }
    FreeAndNil(Result);
  end;
end;

end.
