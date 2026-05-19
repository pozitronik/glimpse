{Render pipeline for saved / clipboard combined images. Owns layout
 math, cell scaling, smart-grid + uniform-grid renderers, banner
 attachment, the combined-size cap, and override-frames source selection.

 Owns: override-frames array (set/cleared by host around re-extract) and
 the banner info snapshot.
 References (non-owned): TFrameView and the four narrow policy interfaces.}
unit FrameRenderPipeline;

interface

uses
  System.Types,
  Vcl.Graphics,
  FrameView, SettingsInterfaces, BannerInfo,
  CombinedGrid, TimecodeOverlay, FrameOffsets;

type
  TFrameRenderPipeline = class
  strict private
    FFrameView: TFrameView;
    FRenderColorPolicy: IRenderColorPolicy;
    FBannerStyleProvider: IBannerStyleProvider;
    FTimecodeStyleProvider: ITimecodeStyleProvider;
    FSavePolicy: ISaveFormatPolicy;
    FBannerInfo: TBannerInfo;
    {Indexed parallel to FFrameView cells. Non-owned (typically owned by
     TFrameCache). When SaveAtLiveResolution is off, save paths prefer
     entries from this array over live FFrameView bitmaps; nil entries
     fall back to the live cell. Length 0 disables.}
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
    {Returns the bitmap save/copy paths should consume for cell AIndex,
     honouring FOverrideFrames when set and the live-resolution toggle
     is off. ALiveResolutionIntent True routes through RenderCellAtLiveSize
     separately today; the param is reserved for symmetry so a future
     unified caller need not special-case the intent flag.}
    function PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): TBitmap;
    {Counts columns in the live layout by counting cells sharing cell 0's
     top coordinate. Generalises across vmGrid (column count), vmFilmstrip
     (FrameCount), and vmScroll (1). Not called for vmSmartGrid or
     vmSingle (which have their own paths).}
    function CountLiveGridColumns: Integer;
    {Centralises panel-inner / smart-grid parameters so render and
     PredictCombinedSize cannot drift.}
    procedure GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
    procedure ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
    {Resolves cell pixel size and column count for uniform-grid render
     in live or native mode. Centralised so render and predict stay in
     lockstep across per-mode column rules and the cell-bitmap fallback.}
    procedure ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
    {Mirrors TFrameView.PaintLoadedFrame (vmGrid live view) so saved cells
     look identical to what the user sees when SaveAtLiveResolution is on.
     Caller owns the returned bitmap.}
    function ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    {Mirrors TFrameView.PaintCropToFill (vmSmartGrid live view) so saved
     smart-grid cells preserve aspect ratio without letterbox bands.
     Caller owns the returned bitmap.}
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
    {Set before invoking a save/copy when SaveAtLiveResolution is off and
     the caller has re-extracted at native (or capped) resolution; clear
     immediately after. Bitmaps are not owned by the pipeline.}
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Types, BannerPainter, BitmapResize, ViewModeLayout;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   SetStretchBltMode/SetBrushOrgEx) declares a TBITMAP alias that would
   otherwise shadow Vcl.Graphics.TBitmap and break the signatures here.}
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
  {Columns=0 means auto (ceil(sqrt(N))); callers override when needed.}
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
  APanelInnerW := Max(1, FFrameView.BaseW - 2 * FFrameView.CellMargin);
  APanelInnerH := Max(1, FFrameView.BaseH - 2 * FFrameView.CellMargin);
  {16:9 fallback for when the FrameView has not been sized yet (save
   triggered before the lister fully laid out).}
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
    {Pixel-faithful to the live view: output equals panel size; border
     still wraps the inner area so saved images and live view stay
     visually consistent.}
    InnerW := PanelInnerW;
    InnerH := PanelInnerH;
  end else begin
    {Native: anchor inner_W to the widest row, then preserve the panel's
     inner aspect ratio so rows look the same as on screen. Frames passed
     by the renderer take precedence so override-frames are honoured; the
     predictor passes nil so we fall back to FrameView cells.}
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
    Exit;
  ABmp.Free;
  ABmp := Shrunk;
end;

procedure TFrameRenderPipeline.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FBannerInfo := AInfo;
end;

end.
