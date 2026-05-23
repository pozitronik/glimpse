{Predicts rendered combined-image dimensions for a one-shot resolution
 choice. Reuses the render pipeline's layout helpers so prediction and
 render cannot drift apart.}
unit FrameDimensionPredictor;

interface

uses
  FrameView, SettingsInterfaces,
  FrameRenderPipeline;

type
  TFrameDimensionPredictor = class
  strict private
    FFrameView: TFrameView;
    FRenderColorPolicy: IRenderColorPolicy;
    FSizePolicy: IRenderSizePolicy;
    FRenderPipeline: TFrameRenderPipeline;
  public
    constructor Create(AFrameView: TFrameView;
      const ARenderColorPolicy: IRenderColorPolicy;
      const ASizePolicy: IRenderSizePolicy;
      ARenderPipeline: TFrameRenderPipeline);
    {Pre-banner, pre-cap pixel dimensions. Banner height is omitted (variable
     and hard to predict without a canvas). Returns 0,0 when no cells.}
    procedure PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
    {ACappedW/H equal AW/H when CombinedMaxSide does not clamp.}
    function PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
    {Bracketed dimension suffix for the Save/Copy view dropdown items.}
    function FormatPredictedSize(AForceLiveRes: Boolean): string;
  end;

implementation

uses
  System.SysUtils, System.Types, System.Math,
  Vcl.Graphics,
  Types, CombinedGrid, BitmapResize, PlatformDetect;

constructor TFrameDimensionPredictor.Create(AFrameView: TFrameView;
  const ARenderColorPolicy: IRenderColorPolicy;
  const ASizePolicy: IRenderSizePolicy;
  ARenderPipeline: TFrameRenderPipeline);
begin
  inherited Create;
  FFrameView := AFrameView;
  FRenderColorPolicy := ARenderColorPolicy;
  FSizePolicy := ASizePolicy;
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

  {vmSingle: "view"-level resolution is the focused frame's dimensions.}
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
  ComputeCappedSize(AW, AH, FSizePolicy.GetCombinedMaxSide, ACappedW, ACappedH);
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
