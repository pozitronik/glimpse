{Combined-image render coordinator. Composes layout math
 (`TFrameRenderLayout`), bitmap scaling (`TCellBitmapScaler`), and
 override-frames source selection (`TOverrideFramesSource`) into a
 single render flow that produces the bitmap a save / clipboard path
 ultimately writes. Owns the render flow itself plus banner attachment
 and the post-render size cap.

 Owned: the three sub-collaborators above, plus the banner info snapshot
 (set/cleared by host around banner-bearing renders).
 References (non-owned): TFrameView and the four narrow policy interfaces.
 Backwards-compat: the public surface retains thin delegating wrappers
 for the layout / scaling / override-frames methods so existing callers
 (FrameSaver, FrameCopier, FrameDimensionPredictor, FrameExporter) and
 tests can continue to talk to the pipeline.}
unit FrameRenderPipeline;

interface

uses
  System.Types,
  Vcl.Graphics,
  FrameView, FrameCellStore, SettingsInterfaces, BannerInfo,
  CombinedGrid, TimecodeOverlay, FrameOffsets,
  FrameRenderLayout, CellBitmapScaler, OverrideFramesSource;

type
  TFrameRenderPipeline = class
  strict private
    FFrameView: TFrameView;
    FRenderColorPolicy: IRenderColorPolicy;
    FBannerStyleProvider: IBannerStyleProvider;
    FTimecodeStyleProvider: ITimecodeStyleProvider;
    FSizePolicy: IRenderSizePolicy;
    FBannerInfo: TBannerInfo;
    FLayout: TFrameRenderLayout;
    FScaler: TCellBitmapScaler;
    FOverrideSource: TOverrideFramesSource;
    {Per-render background-alpha override; -1 = use the color policy's value.
     Set/cleared by the copier around the file-reference combined render so a
     PNG file reference can carry a different gap/border opacity than the
     Save tab without disturbing the persisted setting.}
    FBackgroundAlphaOverride: Integer;
    function CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray;
      ALiveResolutionIntent: Boolean): Integer;
    procedure BuildGridStyle(out AGrid: TCombinedGridStyle);
    procedure BuildTimestampStyle(out ATs: TTimestampStyle);
  public
    constructor Create(AFrameView: TFrameView;
      const ARenderColorPolicy: IRenderColorPolicy;
      const ABannerStyleProvider: IBannerStyleProvider;
      const ATimecodeStyleProvider: ITimecodeStyleProvider;
      const ASizePolicy: IRenderSizePolicy);
    destructor Destroy; override;
    {Delegating wrappers — see TOverrideFramesSource for the contract.}
    function PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): TBitmap;
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
    {Override the combined background alpha for the next render(s). AAlpha is
     0..255. Cleared via ClearBackgroundAlphaOverride.}
    procedure SetBackgroundAlphaOverride(AAlpha: Integer);
    procedure ClearBackgroundAlphaOverride;
    {Delegating wrappers — see TFrameRenderLayout for the contract.}
    function CountLiveGridColumns: Integer;
    procedure GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
    procedure ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
    procedure ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
    {Delegating wrappers — see TCellBitmapScaler for the contract.}
    function ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    function ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
    {vmSmartGrid uses crop-to-fill; other modes use letterbox-fit.}
    function RenderCellAtLiveSize(AIndex: Integer): TBitmap;
    function RenderGridCombinedAtLiveResolution: TBitmap;
    function RenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
    function RenderCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
    function RenderWithBanner(ABmp: TBitmap): TBitmap;
    {No-op when GetCombinedMaxSide is 0 (unlimited) or the bitmap already
     fits. Frees the original and replaces with a downscaled copy when
     capping fires.}
    procedure ApplyCombinedSizeCap(var ABmp: TBitmap);
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
  end;

implementation

uses
  System.SysUtils, System.Math,
  Types, BannerPainter, BitmapResize, ViewModeLayout;

{ TFrameRenderPipeline }

constructor TFrameRenderPipeline.Create(AFrameView: TFrameView;
  const ARenderColorPolicy: IRenderColorPolicy;
  const ABannerStyleProvider: IBannerStyleProvider;
  const ATimecodeStyleProvider: ITimecodeStyleProvider;
  const ASizePolicy: IRenderSizePolicy);
begin
  inherited Create;
  FFrameView := AFrameView;
  FRenderColorPolicy := ARenderColorPolicy;
  FBannerStyleProvider := ABannerStyleProvider;
  FTimecodeStyleProvider := ATimecodeStyleProvider;
  FSizePolicy := ASizePolicy;
  FLayout := TFrameRenderLayout.Create(AFrameView, ARenderColorPolicy);
  FScaler := TCellBitmapScaler.Create(ARenderColorPolicy);
  FOverrideSource := TOverrideFramesSource.Create(AFrameView);
  FBackgroundAlphaOverride := -1;
end;

destructor TFrameRenderPipeline.Destroy;
begin
  FOverrideSource.Free;
  FScaler.Free;
  FLayout.Free;
  inherited;
end;

function TFrameRenderPipeline.PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): TBitmap;
begin
  Result := FOverrideSource.PickSaveBitmap(AIndex, ALiveResolutionIntent);
end;

procedure TFrameRenderPipeline.SetOverrideFrames(const AFrames: TArray<TBitmap>);
begin
  FOverrideSource.SetOverrideFrames(AFrames);
end;

procedure TFrameRenderPipeline.ClearOverrideFrames;
begin
  FOverrideSource.ClearOverrideFrames;
end;

procedure TFrameRenderPipeline.SetBackgroundAlphaOverride(AAlpha: Integer);
begin
  FBackgroundAlphaOverride := AAlpha;
end;

procedure TFrameRenderPipeline.ClearBackgroundAlphaOverride;
begin
  FBackgroundAlphaOverride := -1;
end;

function TFrameRenderPipeline.CountLiveGridColumns: Integer;
begin
  Result := FLayout.CountLiveGridColumns;
end;

procedure TFrameRenderPipeline.GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
begin
  FLayout.GetSmartGridParameters(APanelInnerW, APanelInnerH, AAspectRatio);
end;

procedure TFrameRenderPipeline.ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
begin
  FLayout.ComputeSmartCombinedLayout(AForceLiveRes, AFrames, AOutputW, AOutputH, ARowCounts);
end;

procedure TFrameRenderPipeline.ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
begin
  FLayout.ComputeUniformLayoutInputs(AForceLiveRes, ACols, ACellW, ACellH);
end;

function TFrameRenderPipeline.ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
begin
  Result := FScaler.ScaleBitmapLetterbox(ASrc, AW, AH, ABg);
end;

function TFrameRenderPipeline.ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
begin
  Result := FScaler.ScaleBitmapCropToFill(ASrc, AW, AH);
end;

function TFrameRenderPipeline.CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray;
  ALiveResolutionIntent: Boolean): Integer;
var
  I: Integer;
begin
  Result := FFrameView.CellCount;
  SetLength(AFrames, Result);
  SetLength(AOffsets, Result);
  for I := 0 to Result - 1 do
  begin
    AFrames[I] := FOverrideSource.PickSaveBitmap(I, ALiveResolutionIntent);
    AOffsets[I].TimeOffset := FFrameView.CellTimeOffset(I);
  end;
end;

procedure TFrameRenderPipeline.BuildGridStyle(out AGrid: TCombinedGridStyle);
var
  Alpha: Integer;
begin
  {Columns=0 means auto (ceil(sqrt(N))); callers override when needed.}
  if FBackgroundAlphaOverride >= 0 then
    Alpha := FBackgroundAlphaOverride
  else
    Alpha := FRenderColorPolicy.GetBackgroundAlpha;
  AGrid := TCombinedGridStyle.FromFields(0,
    FRenderColorPolicy.GetCellGap, FRenderColorPolicy.GetCombinedBorder,
    FRenderColorPolicy.GetBackground, Byte(Alpha));
end;

procedure TFrameRenderPipeline.BuildTimestampStyle(out ATs: TTimestampStyle);
begin
  ATs := TTimestampStyle.FromSettings(FTimecodeStyleProvider.GetTimestamp);
  {Live-view "show timecode" toggle wins over the persisted setting so
   the saved render matches what the user is looking at.}
  ATs.Show := FFrameView.ShowTimecode;
end;

function TFrameRenderPipeline.RenderCellAtLiveSize(AIndex: Integer): TBitmap;
var
  Src: TBitmap;
  R: TRect;
  W, H: Integer;
begin
  Src := FFrameView.CellBitmap(AIndex);
  R := FFrameView.GetCellRect(AIndex);
  W := Max(1, R.Width);
  H := Max(1, R.Height);
  if FFrameView.ViewMode = vmSmartGrid then
    Result := FScaler.ScaleBitmapCropToFill(Src, W, H)
  else
    Result := FScaler.ScaleBitmapLetterbox(Src, W, H, FRenderColorPolicy.GetBackground);
end;

function TFrameRenderPipeline.RenderGridCombinedAtLiveResolution: TBitmap;
var
  Frames, Scaled: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  CellW, CellH, Cols, I, N: Integer;
begin
  N := CollectFramesAndOffsets(Frames, Offsets, True);
  if N = 0 then
    Exit(nil);

  FLayout.ComputeUniformLayoutInputs(True, Cols, CellW, CellH);

  BuildGridStyle(Grid);
  Grid.Columns := Cols;
  BuildTimestampStyle(Ts);

  SetLength(Scaled, N);
  try
    for I := 0 to N - 1 do
      if Frames[I] <> nil then
        Scaled[I] := FScaler.ScaleBitmapLetterbox(Frames[I], CellW, CellH, FRenderColorPolicy.GetBackground)
      else
        Scaled[I] := nil;

    Result := RenderCombinedImage(Scaled, Offsets, Grid, Ts);
  finally
    for I := 0 to High(Scaled) do
      Scaled[I].Free;
  end;
end;

function TFrameRenderPipeline.RenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  RowCounts: TArray<Integer>;
  N, OutputW, OutputH: Integer;
begin
  N := CollectFramesAndOffsets(Frames, Offsets, ALiveResolutionIntent);
  if N = 0 then
    Exit(nil);

  FLayout.ComputeSmartCombinedLayout(ALiveResolutionIntent, Frames, OutputW, OutputH, RowCounts);
  if Length(RowCounts) = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);
  Result := RenderSmartCombinedImage(Frames, Offsets, RowCounts, OutputW, OutputH, Grid, Ts);
end;

function TFrameRenderPipeline.RenderCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  N, Cols, CellW, CellH: Integer;
begin
  if FFrameView.ViewMode = vmSmartGrid then
    Exit(RenderSmartCombinedFromCells(ALiveResolutionIntent));

  {The three uniform-row modes (vmGrid, vmFilmstrip, vmScroll) share the
   same live-resolution path via CountLiveGridColumns.}
  if ALiveResolutionIntent and (FFrameView.ViewMode in [vmGrid, vmFilmstrip, vmScroll]) then
    Exit(RenderGridCombinedAtLiveResolution);

  N := CollectFramesAndOffsets(Frames, Offsets, ALiveResolutionIntent);
  if N = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);

  FLayout.ComputeUniformLayoutInputs(False, Cols, CellW, CellH);
  Grid.Columns := Cols;
  Result := RenderCombinedImage(Frames, Offsets, Grid, Ts);
end;

function TFrameRenderPipeline.RenderWithBanner(ABmp: TBitmap): TBitmap;
begin
  if FBannerStyleProvider.GetShowBanner then
  begin
    {try/finally so a raising AttachBanner (the OOM path callers catch)
     still frees ABmp — callers pass it inline with no variable to free.}
    try
      Result := AttachBanner(ABmp, FormatBannerLines(FBannerInfo),
        TBannerStyle.FromSettings(FBannerStyleProvider.GetBanner));
    finally
      ABmp.Free;
    end;
  end
  else
    Result := ABmp;
end;

procedure TFrameRenderPipeline.ApplyCombinedSizeCap(var ABmp: TBitmap);
var
  Shrunk: TBitmap;
begin
  if (ABmp = nil) or (FSizePolicy.GetCombinedMaxSide <= 0) then
    Exit;
  Shrunk := DownscaleBitmapToFit(ABmp, FSizePolicy.GetCombinedMaxSide);
  if Shrunk = nil then
    Exit;
  ABmp.Free;
  ABmp := Shrunk;
end;

procedure TFrameRenderPipeline.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FBannerInfo := AInfo;
end;

end.
