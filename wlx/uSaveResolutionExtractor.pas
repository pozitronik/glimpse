{Synchronous frame re-extraction for the "Save at view resolution = OFF"
 path: live cells are viewport-scaled, so the save path fetches a
 higher-resolution copy on demand (cache hits skip ffmpeg, misses run
 it and populate the cache). Returned bitmaps are caller-owned.}
unit uSaveResolutionExtractor;

interface

uses
  System.SysUtils,
  Vcl.Graphics,
  uTypes, uCache, uFrameOffsets, uFrameExtractor, uProgressReporter;

type
  TSaveResolutionContext = record
    FileName: string;
    Offsets: TFrameOffsetArray;
    {Result array is sized to match so save renderers can index by cell index directly.}
    CellCount: Integer;
    UseBmpPipe: Boolean;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
    RespectAnamorphic: Boolean;
  end;

  TSaveResolutionExtractor = class
  strict private
    FCache: IFrameCache;
    FExtractor: IFrameExtractor;
    FReporter: IProgressReporter;
  public
    constructor Create(const ACache: IFrameCache; const AExtractor: IFrameExtractor);

    {Returns an array of length ACtx.CellCount; only AIndices entries are
     populated (success = bitmap, failure = nil). MaxSide = 0 means native.
     Caller owns and MUST Free each non-nil bitmap.}
    function ExtractAtTarget(const ACtx: TSaveResolutionContext; ATargetMaxSide: Integer; const AIndices: TArray<Integer>): TArray<TBitmap>;

    {Nil = no progress UI.}
    property Reporter: IProgressReporter read FReporter write FReporter;
  end;

{Pure policy: returns True when WithReExtract must re-fetch at save
 resolution. Short-circuits: SaveAtLiveResolution, empty AIndices, target
 equals last extraction.}
function NeedsReExtractForSave(ASaveAtLiveResolution: Boolean; AIndicesCount, ATargetMaxSide, ALastExtractionMaxSide: Integer): Boolean;

implementation

function NeedsReExtractForSave(ASaveAtLiveResolution: Boolean; AIndicesCount, ATargetMaxSide, ALastExtractionMaxSide: Integer): Boolean;
begin
  if ASaveAtLiveResolution then
    Exit(False);
  if AIndicesCount = 0 then
    Exit(False);
  if ATargetMaxSide = ALastExtractionMaxSide then
    Exit(False);
  Result := True;
end;

{TSaveResolutionExtractor}

constructor TSaveResolutionExtractor.Create(const ACache: IFrameCache; const AExtractor: IFrameExtractor);
begin
  inherited Create;
  FCache := ACache;
  FExtractor := AExtractor;
end;

function TSaveResolutionExtractor.ExtractAtTarget(const ACtx: TSaveResolutionContext; ATargetMaxSide: Integer; const AIndices: TArray<Integer>): TArray<TBitmap>;
var
  Options: TExtractionOptions;
  I, Idx, Total: Integer;
  Key: TFrameCacheKey;
  Bmp: TBitmap;
begin
  SetLength(Result, ACtx.CellCount);
  if (Length(ACtx.Offsets) = 0) or (Length(AIndices) = 0) or (ACtx.FileName = '') or (FCache = nil) or (FExtractor = nil) then
    Exit;

  {Build options as the live StartExtraction does, but force MaxSide to
   the save target. The cache key includes MaxSide, so re-extracted frames
   live in their own cache slots and the live view is unaffected.}
  Options := Default (TExtractionOptions);
  Options.UseBmpPipe := ACtx.UseBmpPipe;
  Options.MaxSide := ATargetMaxSide;
  Options.HwAccel := ACtx.HwAccel;
  Options.UseKeyframes := ACtx.UseKeyframes;
  Options.RespectAnamorphic := ACtx.RespectAnamorphic;

  Total := Length(AIndices);
  if FReporter <> nil then
    FReporter.Start(Format('Re-extracting %d frame(s) at full resolution...', [Total]), Total);

  try
    for I := 0 to Total - 1 do
    begin
      Idx := AIndices[I];
      if (Idx < 0) or (Idx >= Length(ACtx.Offsets)) then
        Continue;

      Key := TFrameCacheKey.Create(ACtx.FileName, ACtx.Offsets[Idx].TimeOffset, ATargetMaxSide, ACtx.UseKeyframes);
      Bmp := FCache.TryGet(Key);
      if Bmp = nil then
      begin
        Bmp := FExtractor.ExtractFrame(ACtx.FileName, ACtx.Offsets[Idx].TimeOffset, Options);
        if Bmp <> nil then
          FCache.Put(Key, Bmp);
      end;

      Result[Idx] := Bmp;

      if FReporter <> nil then
      begin
        FReporter.Advance(I + 1);
        FReporter.Pump;
      end;
    end;
  finally
    if FReporter <> nil then
      FReporter.Complete;
  end;
end;

end.
