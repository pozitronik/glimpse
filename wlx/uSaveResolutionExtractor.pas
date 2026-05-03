{Synchronous frame re-extraction for the "Save at view resolution = OFF"
 path. The save toggle promises native (or capped) frame resolution; the
 live-view cells are already at viewport-scaled size, so the save path
 needs to fetch a higher-resolution copy on demand. This unit owns that
 fetch:

 - Cache hits (a previous save at the same MaxSide cached the bitmap)
   skip ffmpeg.
 - Cache misses run ffmpeg via the injected IFrameExtractor and write
   the result back to the cache.
 - Returned bitmaps are caller-owned; caller must Free each non-nil
   entry after use.

 Pulled out of TPluginForm so the policy and the extraction loop both
 become unit-testable: TSaveResolutionExtractor accepts mock IFrameCache
 and IFrameExtractor in tests, NeedsReExtractForSave is a pure function,
 and the form keeps only the UI-coupled progress wiring.}
unit uSaveResolutionExtractor;

interface

uses
  System.SysUtils,
  Vcl.Graphics,
  uTypes, uCache, uFrameOffsets, uFrameExtractor;

type
  {Per-call inputs that the extractor needs but does not own. Carried as
   a record so the public method's signature stays narrow as more options
   accumulate.}
  TSaveResolutionContext = record
    FileName: string;
    Offsets: TFrameOffsetArray;
    {Length of the live FrameView's cell array. The result array is sized
     to match so save renderers can index by cell index directly.}
    CellCount: Integer;
    {Forwarded into TExtractionOptions alongside the save-time MaxSide cap.}
    UseBmpPipe: Boolean;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
    RespectAnamorphic: Boolean;
  end;

  {Optional progress hooks. Caller wires these to its progress bar /
   status text / message pump as appropriate. Nil callbacks are no-ops.}
  TSaveResolutionProgress = reference to procedure(ACurrent, ATotal: Integer);
  TSaveResolutionLabel = reference to procedure(const AText: string);
  TSaveResolutionPump = reference to procedure;

  TSaveResolutionExtractor = class
  strict private
    FCache: IFrameCache;
    FExtractor: IFrameExtractor;
    FOnProgress: TSaveResolutionProgress;
    FOnLabel: TSaveResolutionLabel;
    FOnDone: TSaveResolutionPump;
    FOnPump: TSaveResolutionPump;
  public
    {Both dependencies are injected so tests can supply mocks. ACache is
     consulted for hits before each ffmpeg call, and (when not nil from
     ffmpeg) populated with new entries. AExtractor.ExtractFrame is the
     fallback when the cache misses.}
    constructor Create(const ACache: IFrameCache; const AExtractor: IFrameExtractor);

    {Synchronously builds save-resolution bitmaps for the cells listed in
     AIndices. Cache hits skip ffmpeg; misses call AExtractor.ExtractFrame
     with the same options the live extractor uses, except MaxSide is
     forced to ATargetMaxSide (0 = native).
     The returned array has length ACtx.CellCount; only entries listed in
     AIndices are populated (success → bitmap, failure → nil). Caller
     owns and must Free each non-nil bitmap.}
    function ExtractAtTarget(const ACtx: TSaveResolutionContext;
      ATargetMaxSide: Integer; const AIndices: TArray<Integer>): TArray<TBitmap>;

    property OnProgress: TSaveResolutionProgress read FOnProgress write FOnProgress;
    property OnLabel: TSaveResolutionLabel read FOnLabel write FOnLabel;
    property OnDone: TSaveResolutionPump read FOnDone write FOnDone;
    {Called between iterations so the caller can pump messages and keep
     the UI responsive on long videos.}
    property OnPump: TSaveResolutionPump read FOnPump write FOnPump;
  end;

{Pure decision: returns True when WithReExtract should re-fetch frames
 at save resolution rather than using the live cells as-is. Pulled out
 so the policy can be unit-tested without instantiating the extractor.

 The four short-circuits, in order:
   - Toggle ON ("save at view resolution") → use live cells, never re-extract.
   - Empty index list → nothing for the action to consume; skip.
   - Target equals last extraction MaxSide → live cells already match.
   - Otherwise → re-extract.}
function NeedsReExtractForSave(ASaveAtLiveResolution: Boolean;
  AIndicesCount, ATargetMaxSide, ALastExtractionMaxSide: Integer): Boolean;

implementation

function NeedsReExtractForSave(ASaveAtLiveResolution: Boolean;
  AIndicesCount, ATargetMaxSide, ALastExtractionMaxSide: Integer): Boolean;
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

function TSaveResolutionExtractor.ExtractAtTarget(const ACtx: TSaveResolutionContext;
  ATargetMaxSide: Integer; const AIndices: TArray<Integer>): TArray<TBitmap>;
var
  Options: TExtractionOptions;
  I, Idx, Total: Integer;
  Key: TFrameCacheKey;
  Bmp: TBitmap;
begin
  SetLength(Result, ACtx.CellCount);
  if (Length(ACtx.Offsets) = 0) or (Length(AIndices) = 0) or (ACtx.FileName = '')
    or (FCache = nil) or (FExtractor = nil) then
    Exit;

  {Build options the same way the live StartExtraction does, with MaxSide
   forced to the save target rather than the viewport-derived live cap.
   The cache key picks up the new MaxSide automatically — re-extracted
   frames live in their own cache slots, so the live view is unaffected.}
  Options := Default(TExtractionOptions);
  Options.UseBmpPipe := ACtx.UseBmpPipe;
  Options.MaxSide := ATargetMaxSide;
  Options.HwAccel := ACtx.HwAccel;
  Options.UseKeyframes := ACtx.UseKeyframes;
  Options.RespectAnamorphic := ACtx.RespectAnamorphic;

  Total := Length(AIndices);
  if Assigned(FOnLabel) then
    FOnLabel(Format('Re-extracting %d frame(s) at full resolution...', [Total]));
  if Assigned(FOnProgress) then
    FOnProgress(0, Total);

  try
    for I := 0 to Total - 1 do
    begin
      Idx := AIndices[I];
      if (Idx < 0) or (Idx >= Length(ACtx.Offsets)) then
        Continue;

      Key := TFrameCacheKey.Create(ACtx.FileName, ACtx.Offsets[Idx].TimeOffset,
        ATargetMaxSide, ACtx.UseKeyframes);
      Bmp := FCache.TryGet(Key);
      if Bmp = nil then
      begin
        Bmp := FExtractor.ExtractFrame(ACtx.FileName, ACtx.Offsets[Idx].TimeOffset, Options);
        if Bmp <> nil then
          FCache.Put(Key, Bmp);
      end;

      Result[Idx] := Bmp;

      if Assigned(FOnProgress) then
        FOnProgress(I + 1, Total);
      if Assigned(FOnPump) then
        FOnPump;
    end;
  finally
    if Assigned(FOnDone) then
      FOnDone;
  end;
end;

end.
