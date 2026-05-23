{Layout math for the combined-image render pipeline. Computes column
 counts, smart-grid row counts, and uniform-grid cell dimensions for both
 the live-resolution and native-resolution paths. Stateless beyond the
 injected FrameView reference and color policy.}
unit FrameRenderLayout;

interface

uses
  System.Types,
  Vcl.Graphics,
  FrameView, SettingsInterfaces;

type
  TFrameRenderLayout = class
  strict private
    FFrameView: TFrameView;
    FRenderColorPolicy: IRenderColorPolicy;
  public
    {AFrameView and ARenderColorPolicy are borrowed; the layout does
     not own either.}
    constructor Create(AFrameView: TFrameView;
      const ARenderColorPolicy: IRenderColorPolicy);
    {Counts columns in the live layout by counting cells sharing cell 0's
     top coordinate. Generalises across vmGrid (column count), vmFilmstrip
     (FrameCount), and vmScroll (1). Not called for vmSmartGrid or
     vmSingle (which have their own paths).}
    function CountLiveGridColumns: Integer;
    {Centralises panel-inner / smart-grid parameters so render and predict
     cannot drift.}
    procedure GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
    procedure ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
    {Resolves cell pixel size and column count for uniform-grid render
     in live or native mode. Centralised so render and predict stay in
     lockstep across per-mode column rules and the cell-bitmap fallback.}
    procedure ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
  end;

implementation

uses
  System.Math,
  Types, ViewModeLayout;

constructor TFrameRenderLayout.Create(AFrameView: TFrameView;
  const ARenderColorPolicy: IRenderColorPolicy);
begin
  inherited Create;
  FFrameView := AFrameView;
  FRenderColorPolicy := ARenderColorPolicy;
end;

function TFrameRenderLayout.CountLiveGridColumns: Integer;
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

procedure TFrameRenderLayout.GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
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

procedure TFrameRenderLayout.ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
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

procedure TFrameRenderLayout.ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
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

end.
