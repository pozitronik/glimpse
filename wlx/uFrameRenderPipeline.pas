{Render pipeline for saved / clipboard combined images.

 Extracted from TFrameExporter so the layout math, the cell-scaling
 helpers, the smart-grid and uniform-grid renderers, the banner
 attachment, the combined-size cap, and the override-frames source
 selection all live in one cohesive unit, separated from the save and
 clipboard orchestration concerns.

 The pipeline owns:
 - the override-frames array (set/cleared by the host before/after a
   re-extract; the render paths prefer overrides over live cells when
   present), and
 - the banner info snapshot (updated by UpdateBannerInfo before a
   render, applied by RenderWithBanner).

 References (non-owned): TFrameView (the live grid) and the persisted
 TPluginSettings record. Lifetime is bound to the owning facade
 (TFrameExporter constructs and destroys the pipeline).}
unit uFrameRenderPipeline;

interface

uses
  System.Types,
  Vcl.Graphics,
  uFrameView, uSettingsInterfaces, uBannerInfo,
  uCombinedGrid, uTimecodeOverlay, uFrameOffsets;

type
  {Step 109 (N3, ISP): depends on 4 narrow per-concern interfaces
   instead of the whole TPluginSettings god object.
     IRenderColorPolicy     - Background/Alpha/CellGap/CombinedBorder
                              for grid layout + scaling.
     IBannerStyleProvider   - Banner record + ShowBanner toggle for
                              banner attachment.
     ITimecodeStyleProvider - Timestamp record for overlay rendering.
     ISaveFormatPolicy      - CombinedMaxSide for the post-render cap.}
  TFrameRenderPipeline = class
  strict private
    FFrameView: TFrameView;
    FRenderColorPolicy: IRenderColorPolicy;
    FBannerStyleProvider: IBannerStyleProvider;
    FTimecodeStyleProvider: ITimecodeStyleProvider;
    FSavePolicy: ISaveFormatPolicy;
    FBannerInfo: TBannerInfo;
    {Optional save-resolution bitmaps supplied by the caller before a
     save/copy operation, indexed parallel to FFrameView cells. Bitmaps
     are non-owned references (typically owned by TFrameCache). When the
     SaveAtLiveResolution toggle is off, save paths prefer entries from
     this array over the live FFrameView bitmaps; nil entries fall back
     to the live cell. Set length 0 to disable.
     Lifetime: the caller (TPluginForm) sets this before invoking a save
     method and clears it after, so the pipeline never owns the memory.}
    FOverrideFrames: TArray<TBitmap>;
    function CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray;
      ALiveResolutionIntent: Boolean): Integer;
    procedure BuildGridStyle(out AGrid: TCombinedGridStyle);
    procedure BuildTimestampStyle(out ATs: TTimestampStyle);
  public
    constructor Create(AFrameView: TFrameView;
      const ARenderColorPolicy: IRenderColorPolicy;
      const ABannerStyleProvider: IBannerStyleProvider;
      const ATimecodeStyleProvider: ITimecodeStyleProvider;
      const ASavePolicy: ISaveFormatPolicy);
    {Returns the bitmap that the save/copy paths should consume for cell
     AIndex, honouring FOverrideFrames when set and the toggle is off.
     ALiveResolutionIntent: True means "render at on-screen cell size"
     (callers route to RenderCellAtLiveSize separately and never invoke
     PickSaveBitmap in that path today; the param is reserved for
     symmetry with the other render-path entry points so a future
     unified caller doesn't have to special-case the intent flag).
     False means "native frame size" - the override array wins when
     populated, falling back to the live cell.}
    function PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): TBitmap;
    {Counts the columns the live layout is currently using by iterating
     cells and counting those that share cell 0's top coordinate.
     Generalises across the three uniform-row modes:
     vmGrid      - cells in row 0 share Top, returns column count.
     vmFilmstrip - all cells share Top (one row), returns FrameCount.
     vmScroll    - only cell 0 has that Top (one column), returns 1.
     Used by the live-resolution save path; not called for vmSmartGrid
     (which has its own renderer) or vmSingle (which routes to SaveFrame).}
    function CountLiveGridColumns: Integer;
    {Pulls the panel-inner dimensions and the smart-grid arrangement
     parameters that RenderSmartCombinedFromCells and PredictCombinedSize
     both need. Centralises the FrameView fallback to a 16:9 box and the
     per-mode column policy in a single place so render and predict
     cannot disagree.}
    procedure GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
    procedure ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
    {Resolves cell pixel size and column count for a uniform-grid render
     in either live (panel-pixel) or native (frame-pixel) mode. Used by
     RenderGridCombinedAtLiveResolution, RenderCombinedFromCells (native
     branch) and PredictCombinedSize so a future change to the per-mode
     column rule or to the cell-bitmap fallback applies everywhere.}
    procedure ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
    {Letterbox-scales ASrc to fit AW x AH, filling unused area with ABg.
     Mirrors TFrameView.PaintLoadedFrame (vmGrid live view) so saved cells
     look identical to what the user sees when SaveAtLiveResolution is on.
     Caller owns the returned bitmap.}
    function ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    {Crop-to-fill scaling. Mirrors TFrameView.PaintCropToFill (vmSmartGrid
     live view) so saved smart-grid cells preserve aspect ratio without
     letterbox bands. Caller owns the returned bitmap.}
    function ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
    {Renders a single cell at the size and fitting mode the live view is
     currently using for that cell. vmSmartGrid uses crop-to-fill; every
     other mode uses letterbox-fit. Used by single-frame save and clipboard
     copy when SaveAtLiveResolution is on.}
    function RenderCellAtLiveSize(AIndex: Integer): TBitmap;
    function RenderGridCombinedAtLiveResolution: TBitmap;
    {ALiveResolutionIntent: True = panel-pixel cells (live view sizing),
     False = anchor-to-widest native cell sizes. Replaces the previous
     internal read of FSettings.SaveAtLiveResolution so CopyView /
     CopyFrame can route their per-call intent through without temp-
     flipping the settings field.}
    function RenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
    {ALiveResolutionIntent: True dispatches to the always-live
     RenderGridCombinedAtLiveResolution for uniform-row modes. Replaces
     the previous internal read of FSettings.SaveAtLiveResolution.}
    function RenderCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
    function RenderWithBanner(ABmp: TBitmap): TBitmap;
    {Shrinks ABmp in place when ISaveFormatPolicy.GetCombinedMaxSide > 0
     and the bitmap's longer side exceeds the cap. The original is freed
     and replaced with a downscaled copy. No-op when the cap is 0
     (unlimited) or the bitmap already fits. Centralises the policy used
     by SaveView and CopyView.}
    procedure ApplyCombinedSizeCap(var ABmp: TBitmap);
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
    {Caller-supplied save-resolution bitmaps. Set before invoking a save
     or copy method when SaveAtLiveResolution is off and the caller has
     re-extracted at native (or capped) resolution; clear immediately
     after. Pass an empty array (or nil) to release. Bitmaps are not
     owned by the pipeline.}
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  uTypes, uBannerPainter, uBitmapResize, uViewModeLayout;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for the
   GDI helpers SetStretchBltMode/SetBrushOrgEx) declares its own TBITMAP
   record alias, which would otherwise shadow Vcl.Graphics.TBitmap and
   cause method signatures here to mismatch the interface declarations.}
  TBitmap = Vcl.Graphics.TBitmap;

{ TFrameRenderPipeline }

constructor TFrameRenderPipeline.Create(AFrameView: TFrameView;
  const ARenderColorPolicy: IRenderColorPolicy;
  const ABannerStyleProvider: IBannerStyleProvider;
  const ATimecodeStyleProvider: ITimecodeStyleProvider;
  const ASavePolicy: ISaveFormatPolicy);
begin
  inherited Create;
  FFrameView := AFrameView;
  FRenderColorPolicy := ARenderColorPolicy;
  FBannerStyleProvider := ABannerStyleProvider;
  FTimecodeStyleProvider := ATimecodeStyleProvider;
  FSavePolicy := ASavePolicy;
end;

{Picks which bitmap to feed into the save/copy renderers for cell AIndex.
 With FOverrideFrames set and the live-resolution toggle off, prefers the
 override entry (typically a cache-owned save-resolution bitmap); a nil
 override entry falls back to the live cell so partial coverage degrades
 gracefully. With the toggle on, always uses the live cell since the
 toggle's contract is to mirror what is on screen.}
function TFrameRenderPipeline.PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): TBitmap;
begin
  Result := nil;
  if (not ALiveResolutionIntent) and (AIndex >= 0) and (AIndex < Length(FOverrideFrames)) and (FOverrideFrames[AIndex] <> nil) then
    Exit(FOverrideFrames[AIndex]);
  if (AIndex >= 0) and (AIndex < FFrameView.CellCount) and (FFrameView.CellState(AIndex) = fcsLoaded) then
    Result := FFrameView.CellBitmap(AIndex);
end;

procedure TFrameRenderPipeline.SetOverrideFrames(const AFrames: TArray<TBitmap>);
begin
  FOverrideFrames := AFrames;
end;

procedure TFrameRenderPipeline.ClearOverrideFrames;
begin
  SetLength(FOverrideFrames, 0);
end;

{Builds the frames + offsets arrays for the renderer.
 Frame source is PickSaveBitmap so override entries (when set) take
 precedence over the live cells. Offsets always come from the live view.
 nil entries for placeholder/error/missing cells are passed through; the
 renderer skips them.}
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
    AFrames[I] := PickSaveBitmap(I, ALiveResolutionIntent);
    AOffsets[I].TimeOffset := FFrameView.CellTimeOffset(I);
  end;
end;

procedure TFrameRenderPipeline.BuildGridStyle(out AGrid: TCombinedGridStyle);
begin
  {Columns=0 means "auto" (ceil(sqrt(N))); callers override when needed.}
  AGrid := TCombinedGridStyle.FromFields(0,
    FRenderColorPolicy.GetCellGap, FRenderColorPolicy.GetCombinedBorder,
    FRenderColorPolicy.GetBackground, FRenderColorPolicy.GetBackgroundAlpha);
end;

procedure TFrameRenderPipeline.BuildTimestampStyle(out ATs: TTimestampStyle);
begin
  ATs := TTimestampStyle.FromSettings(FTimecodeStyleProvider.GetTimestamp);
  {Live-view "show timecode" toggle wins over the persisted setting so
   the saved render matches what the user is looking at.}
  ATs.Show := FFrameView.ShowTimecode;
end;

function TFrameRenderPipeline.CountLiveGridColumns: Integer;
var
  R0: TRect;
  I: Integer;
begin
  Result := 0;
  if FFrameView.CellCount = 0 then
    Exit(1);
  R0 := FFrameView.GetCellRect(0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.GetCellRect(I).Top = R0.Top then
      Inc(Result);
  if Result < 1 then
    Result := 1;
end;

function TFrameRenderPipeline.ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
var
  Scale: Double;
  DW, DH: Integer;
  DstR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    Result.Canvas.Brush.Color := ABg;
    Result.Canvas.FillRect(Rect(0, 0, AW, AH));
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
      Exit;
    Scale := Min(AW / ASrc.Width, AH / ASrc.Height);
    DW := Max(1, Round(ASrc.Width * Scale));
    DH := Max(1, Round(ASrc.Height * Scale));
    DstR.Left := (AW - DW) div 2;
    DstR.Top := (AH - DH) div 2;
    DstR.Right := DstR.Left + DW;
    DstR.Bottom := DstR.Top + DH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.StretchDraw(DstR, ASrc);
  except
    Result.Free;
    raise;
  end;
end;

function TFrameRenderPipeline.ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
var
  Scale: Double;
  SrcW, SrcH: Integer;
  SrcR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
    begin
      Result.Canvas.Brush.Color := FRenderColorPolicy.GetBackground;
      Result.Canvas.FillRect(Rect(0, 0, AW, AH));
      Exit;
    end;
    Scale := Max(AW / ASrc.Width, AH / ASrc.Height);
    SrcW := Min(ASrc.Width, Round(AW / Scale));
    SrcH := Min(ASrc.Height, Round(AH / Scale));
    SrcR.Left := (ASrc.Width - SrcW) div 2;
    SrcR.Top := (ASrc.Height - SrcH) div 2;
    SrcR.Right := SrcR.Left + SrcW;
    SrcR.Bottom := SrcR.Top + SrcH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, AW, AH), ASrc.Canvas, SrcR);
  except
    Result.Free;
    raise;
  end;
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
    Result := ScaleBitmapCropToFill(Src, W, H)
  else
    Result := ScaleBitmapLetterbox(Src, W, H, FRenderColorPolicy.GetBackground);
end;

procedure TFrameRenderPipeline.GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
begin
  {Panel inner area drives the smart-grid arrangement. Falls back to a
   16:9 box when the FrameView has not been sized yet (e.g., save
   triggered before the lister fully laid out).}
  APanelInnerW := Max(1, FFrameView.BaseW - 2 * FFrameView.CellMargin);
  APanelInnerH := Max(1, FFrameView.BaseH - 2 * FFrameView.CellMargin);
  if (APanelInnerW <= 1) or (APanelInnerH <= 1) then
  begin
    APanelInnerW := 1600;
    APanelInnerH := 900;
  end;
  AAspectRatio := FFrameView.AspectRatio;
  if AAspectRatio <= 0 then
    AAspectRatio := 9.0 / 16.0;
end;

procedure TFrameRenderPipeline.ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
var
  N, I, Border, Gap, MaxCells, NativeW, InnerW, InnerH: Integer;
  PanelInnerW, PanelInnerH: Integer;
  AspectRatio: Double;
  Bmp: TBitmap;
begin
  AOutputW := 0;
  AOutputH := 0;
  SetLength(ARowCounts, 0);

  N := Length(AFrames);
  if N = 0 then
    N := FFrameView.CellCount;
  if N = 0 then
    Exit;

  Border := Max(0, FRenderColorPolicy.GetCombinedBorder);
  Gap := Max(0, FRenderColorPolicy.GetCellGap);

  GetSmartGridParameters(PanelInnerW, PanelInnerH, AspectRatio);
  ARowCounts := ComputeSmartGridRows(N, PanelInnerW, PanelInnerH, Gap, AspectRatio);
  if Length(ARowCounts) = 0 then
    Exit;

  if AForceLiveRes then
  begin
    {Pixel-faithful to the live view: total output = panel size, inner
     area = panel inner. Border setting still wraps the inner area so
     saved images and live view stay visually consistent.}
    InnerW := PanelInnerW;
    InnerH := PanelInnerH;
  end else begin
    {Native: anchor inner_W to the widest row, then preserve the panel's
     inner aspect ratio so rows look the same as on screen. NativeW comes
     from the first non-nil frame; uniform across a video. Frames passed
     by the renderer are preferred so override-frames (set by re-extract)
     are honoured; the predictor passes nil so we fall back to FrameView
     cells.}
    MaxCells := 1;
    for I := 0 to High(ARowCounts) do
      if ARowCounts[I] > MaxCells then
        MaxCells := ARowCounts[I];

    NativeW := 320;
    if Length(AFrames) > 0 then
    begin
      for I := 0 to High(AFrames) do
        if (AFrames[I] <> nil) and (AFrames[I].Width > 0) then
        begin
          NativeW := AFrames[I].Width;
          Break;
        end;
    end else begin
      for I := 0 to N - 1 do
      begin
        Bmp := FFrameView.CellBitmap(I);
        if (Bmp <> nil) and (Bmp.Width > 0) then
        begin
          NativeW := Bmp.Width;
          Break;
        end;
      end;
    end;

    InnerW := MaxCells * NativeW + Max(MaxCells - 1, 0) * Gap;
    InnerH := Max(1, Round(InnerW * (PanelInnerH / PanelInnerW)));
  end;

  AOutputW := InnerW + 2 * Border;
  AOutputH := InnerH + 2 * Border;
end;

procedure TFrameRenderPipeline.ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
var
  N, I: Integer;
  CellRect: TRect;
  Bmp: TBitmap;
begin
  N := FFrameView.CellCount;
  if AForceLiveRes then
  begin
    CellRect := FFrameView.GetCellRect(0);
    ACellW := Max(1, CellRect.Width);
    ACellH := Max(1, CellRect.Height);
    ACols := CountLiveGridColumns;
  end else begin
    {Native cell size from first non-nil cell bitmap; matches the
     fallback RenderCombinedImage uses when scanning AFrames internally.}
    ACellW := 320;
    ACellH := 240;
    for I := 0 to N - 1 do
    begin
      Bmp := FFrameView.CellBitmap(I);
      if Bmp <> nil then
      begin
        ACellW := Bmp.Width;
        ACellH := Bmp.Height;
        Break;
      end;
    end;
    case FFrameView.ViewMode of
      vmFilmstrip:
        ACols := N;
      vmScroll:
        ACols := 1;
    else
      ACols := CountLiveGridColumns;
    end;
  end;
  if ACols < 1 then
    ACols := 1;
end;

{Live-resolution variant of the uniform-grid render: cell pixel size
 matches what the live view is currently showing on screen, and the
 column count tracks the live layout. Used by vmGrid, vmFilmstrip, and
 vmScroll save/copy when SaveAtLiveResolution is on. Frames are
 pre-letterboxed to the live cell dimensions, then fed to the same
 uniform-grid renderer the native path uses. This keeps alpha lifting,
 timecode rendering, and border/gap math centralised.}
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

  ComputeUniformLayoutInputs(True, Cols, CellW, CellH);

  BuildGridStyle(Grid);
  Grid.Columns := Cols;
  BuildTimestampStyle(Ts);

  SetLength(Scaled, N);
  try
    for I := 0 to N - 1 do
      if Frames[I] <> nil then
        Scaled[I] := ScaleBitmapLetterbox(Frames[I], CellW, CellH, FRenderColorPolicy.GetBackground)
      else
        Scaled[I] := nil;

    Result := RenderCombinedImage(Scaled, Offsets, Grid, Ts);
  finally
    for I := 0 to High(Scaled) do
      Scaled[I].Free;
  end;
end;

{Renders the live smart-grid arrangement to a combined image. Row counts
 come from ComputeSmartGridRows fed with the panel's inner aspect ratio,
 so the saved arrangement matches what the user sees at the moment of
 save. Output dimensions follow the FSettings.SaveAtLiveResolution toggle:
 - True: panel inner area + Border (pixel-faithful to the live view)
 - False: anchor to the row with the most cells, sized at native frame
 width; total inner aspect ratio still tracks the panel so rows look
 the same shape as on screen.}
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

  ComputeSmartCombinedLayout(ALiveResolutionIntent, Frames, OutputW, OutputH, RowCounts);
  if Length(RowCounts) = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);
  Result := RenderSmartCombinedImage(Frames, Offsets, RowCounts, OutputW, OutputH, Grid, Ts);
end;

{Renders the frames into a single combined image laid out per the
 live view mode. Cell pixel size follows the SaveAtLiveResolution
 toggle in every mode:

 - vmSmartGrid: smart layout (panel-aspect-driven row counts);
 panel-pixel cells when the toggle is on, anchor-to-widest native
 cells when off. Handled by RenderSmartCombinedFromCells.
 - vmGrid / vmFilmstrip / vmScroll: uniform-row grid. When the toggle
 is on, all three route through RenderGridCombinedAtLiveResolution
 so cell pixels match the on-screen layout (vmFilmstrip = one wide
 row, vmScroll = one tall column, vmGrid = current column count).
 When off, they render at native cell size with Columns pinned to
 the view's natural shape.
 - vmSingle: caller (SaveView/CopyView) routes to single-frame paths
 before reaching this function, so vmSingle never reaches the
 regular grid renderer here.

 Returns nil only when there are no cells; placeholder/error cells are
 passed through as nil bitmaps and skipped by the renderer.}
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

  {The uniform-row modes (vmGrid, vmFilmstrip, vmScroll) all share the
   same live-resolution path: it picks Columns from the live layout
   via CountLiveGridColumns, which generalises across the three.}
  if ALiveResolutionIntent and (FFrameView.ViewMode in [vmGrid, vmFilmstrip, vmScroll]) then
    Exit(RenderGridCombinedAtLiveResolution);

  N := CollectFramesAndOffsets(Frames, Offsets, ALiveResolutionIntent);
  if N = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);

  {Native-resolution path for the uniform-row modes. Cell pixel size
   comes from the first non-nil frame; columns follow the live layout
   so the saved image preserves the on-screen arrangement (filmstrip =
   one wide row, scroll = one tall column, vmGrid = current live column
   count). ComputeUniformLayoutInputs centralises both rules so render
   and PredictCombinedSize stay in lockstep.}
  ComputeUniformLayoutInputs(False, Cols, CellW, CellH);
  Grid.Columns := Cols;
  Result := RenderCombinedImage(Frames, Offsets, Grid, Ts);
end;

function TFrameRenderPipeline.RenderWithBanner(ABmp: TBitmap): TBitmap;
begin
  if FBannerStyleProvider.GetShowBanner then
  begin
    Result := AttachBanner(ABmp, FormatBannerLines(FBannerInfo),
      TBannerStyle.FromSettings(FBannerStyleProvider.GetBanner));
    ABmp.Free;
  end
  else
    Result := ABmp;
end;

procedure TFrameRenderPipeline.ApplyCombinedSizeCap(var ABmp: TBitmap);
var
  Shrunk: TBitmap;
begin
  if (ABmp = nil) or (FSavePolicy.GetCombinedMaxSide <= 0) then
    Exit;
  Shrunk := DownscaleBitmapToFit(ABmp, FSavePolicy.GetCombinedMaxSide);
  if Shrunk = nil then
    Exit; {Already fits - keep the original.}
  ABmp.Free;
  ABmp := Shrunk;
end;

procedure TFrameRenderPipeline.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FBannerInfo := AInfo;
end;

end.
