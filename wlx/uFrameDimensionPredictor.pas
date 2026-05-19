{Predicts the rendered combined-image dimensions for a one-shot
 resolution choice, mirroring the layout math in
 RenderCombinedFromCells / RenderSmartCombinedFromCells /
 RenderGridCombinedAtLiveResolution. Used by the toolbar dropdown to
 label the Save view / Copy view variants with their predicted output
 size and by the status-bar resolution panel.

 Extracted from TFrameExporter so the prediction concern (read-only,
 pure layout math) lives separately from the actual render and save/
 copy orchestration. The predictor reuses the render pipeline's layout
 helpers (ComputeSmartCombinedLayout, ComputeUniformLayoutInputs) so
 prediction and render cannot drift apart.

 Lifetime: bound to the owning facade (TFrameExporter constructs and
 destroys). The render-pipeline reference is non-owned.}
unit uFrameDimensionPredictor;

interface

uses
  uFrameView, uSettingsInterfaces,
  uFrameRenderPipeline;

type
  {Step 109 (N3, ISP): depends only on IRenderColorPolicy (CellGap +
   CombinedBorder for the layout math) and ISaveFormatPolicy
   (CombinedMaxSide for the cap clamp).}
  TFrameDimensionPredictor = class
  strict private
    FFrameView: TFrameView;
    FRenderColorPolicy: IRenderColorPolicy;
    FSavePolicy: ISaveFormatPolicy;
    FRenderPipeline: TFrameRenderPipeline;
  public
    constructor Create(AFrameView: TFrameView;
      const ARenderColorPolicy: IRenderColorPolicy;
      const ASavePolicy: ISaveFormatPolicy;
      ARenderPipeline: TFrameRenderPipeline);
    {Predicts the pixel dimensions the rendered combined image would have
     for a one-shot resolution choice, before banner attachment and before
     the CombinedMaxSide cap. Banner height is intentionally omitted (it
     adds a small variable height that is hard to predict without setting
     up a canvas). Returns 0,0 when there are no cells.}
    procedure PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
    {Predicts the rendered combined-image dimensions and the post-cap
     dimensions for a one-shot resolution choice. ACappedW/H equal AW/H
     when the CombinedMaxSide cap does not apply (cap=0 or image
     already fits). Returns False when no frames are loaded yet.}
    function PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
    {Returns the bracketed dimension suffix used on the Save/Copy view
     dropdown menu items, e.g. " [1920x1080]" or
     " [19200x10800 -> 8192x4608]" when CombinedMaxSide caps the output.
     Empty string when no frames are loaded yet.}
    function FormatPredictedSize(AForceLiveRes: Boolean): string;
  end;

implementation

uses
  System.SysUtils, System.Types, System.Math,
  Vcl.Graphics,
  uTypes, uCombinedGrid, uBitmapResize, uPlatformDetect;

constructor TFrameDimensionPredictor.Create(AFrameView: TFrameView;
  const ARenderColorPolicy: IRenderColorPolicy;
  const ASavePolicy: ISaveFormatPolicy;
  ARenderPipeline: TFrameRenderPipeline);
begin
  inherited Create;
  FFrameView := AFrameView;
  FRenderColorPolicy := ARenderColorPolicy;
  FSavePolicy := ASavePolicy;
  FRenderPipeline := ARenderPipeline;
end;

procedure TFrameDimensionPredictor.PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
var
  N, Cols, CellW, CellH, Border, Gap: Integer;
  CellRect: TRect;
  RowCounts: TArray<Integer>;
  Bmp: TBitmap;
  EmptyFrames: TArray<TBitmap>;
  Sz: TPoint;
begin
  AW := 0;
  AH := 0;
  N := FFrameView.CellCount;
  if N = 0 then
    Exit;

  {vmSingle: SaveView/CopyView degenerate to single-frame paths so the
   "view"-level resolution is the focused frame's dimensions.}
  if FFrameView.ViewMode = vmSingle then
  begin
    if AForceLiveRes then
    begin
      CellRect := FFrameView.GetCellRect(FFrameView.CurrentFrameIndex);
      AW := Max(1, CellRect.Width);
      AH := Max(1, CellRect.Height);
    end else begin
      AW := 320;
      AH := 240;
      Bmp := FFrameView.CellBitmap(FFrameView.CurrentFrameIndex);
      if (Bmp <> nil) and (Bmp.Width > 0) then
      begin
        AW := Bmp.Width;
        AH := Bmp.Height;
      end;
    end;
    Exit;
  end;

  if FFrameView.ViewMode = vmSmartGrid then
  begin
    SetLength(EmptyFrames, 0);
    FRenderPipeline.ComputeSmartCombinedLayout(AForceLiveRes, EmptyFrames, AW, AH, RowCounts);
    Exit;
  end;

  {Uniform-row modes (vmGrid, vmFilmstrip, vmScroll).}
  Border := Max(0, FRenderColorPolicy.GetCombinedBorder);
  Gap := Max(0, FRenderColorPolicy.GetCellGap);
  FRenderPipeline.ComputeUniformLayoutInputs(AForceLiveRes, Cols, CellW, CellH);
  Sz := ComputeCombinedImageSize(N, Cols, CellW, CellH, Border, Gap);
  AW := Sz.X;
  AH := Sz.Y;
end;

function TFrameDimensionPredictor.PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
begin
  AW := 0;
  AH := 0;
  ACappedW := 0;
  ACappedH := 0;
  Result := False;
  PredictCombinedSize(AForceLiveRes, AW, AH);
  if (AW <= 0) or (AH <= 0) then
    Exit;
  ComputeCappedSize(AW, AH, FSavePolicy.GetCombinedMaxSide, ACappedW, ACappedH);
  Result := True;
end;

function TFrameDimensionPredictor.FormatPredictedSize(AForceLiveRes: Boolean): string;
var
  W, H, CW, CH: Integer;
begin
  Result := '';
  if not PredictDisplayedSize(AForceLiveRes, W, H, CW, CH) then
    Exit;
  if (CW <> W) or (CH <> H) then
    Result := Format(' [%dx%d%s%dx%d]', [W, H, ResolutionTransformGlyph, CW, CH])
  else
    Result := Format(' [%dx%d]', [W, H]);
end;

end.
