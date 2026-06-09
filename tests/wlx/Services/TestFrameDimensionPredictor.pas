{Tests for TFrameDimensionPredictor. Its output feeds the Save/Copy view
 dropdown captions and the save dialog, so a wrong prediction either lies
 to the user or mismatches the rendered bitmap. The fixture mirrors the
 production wiring: a real TFrameView + TFrameRenderPipeline with
 TPluginSettings (defaults from a nonexistent INI) serving every policy
 interface, exactly as CreateFrameExporter wires it.}
unit TestFrameDimensionPredictor;

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Settings, FrameView, FrameRenderPipeline, FrameDimensionPredictor;

type
  [TestFixture]
  TTestFrameDimensionPredictor = class
  strict private
    FForm: TForm;
    FSettings: TPluginSettings;
    FView: TFrameView;
    FPipeline: TFrameRenderPipeline;
    FPredictor: TFrameDimensionPredictor;
    {ACellCount cells; the listed indices get a 160x90 pf24bit frame.}
    procedure BuildPredictor(ACellCount: Integer; const ALoadedIndices: array of Integer);
  public
    [TearDown] procedure TearDown;
    [Test] procedure EmptyView_PredictsZeroAndFormatsEmpty;
    [Test] procedure SingleMode_Native_UsesBitmapDimensions;
    [Test] procedure SingleMode_Native_NoBitmap_FallsBackTo320x240;
    [Test] procedure SingleMode_Live_UsesCellRect;
    [Test] procedure GridMode_Native_SingleCell_MatchesCellDimensions;
    [Test] procedure SmartGridMode_LoadedCells_PredictsPositive;
    [Test] procedure PredictDisplayedSize_NoCap_CappedEqualsRaw;
    [Test] procedure FormatPredictedSize_Uncapped_BracketsRawSize;
    [Test] procedure FormatPredictedSize_Capped_ShowsTransformGlyph;
  end;

implementation

uses
  System.SysUtils, System.Types, System.Math,
  Vcl.Graphics,
  Types, FrameOffsets, PlatformDetect;

procedure TTestFrameDimensionPredictor.BuildPredictor(ACellCount: Integer;
  const ALoadedIndices: array of Integer);
var
  Offsets: TFrameOffsetArray;
  I: Integer;
  Bmp: TBitmap;
begin
  FForm := TForm.CreateNew(nil);
  FView := TFrameView.Create(FForm);
  FView.Parent := FForm;
  FView.SetViewport(800, 600);
  FView.AspectRatio := 9 / 16;
  SetLength(Offsets, ACellCount);
  for I := 0 to ACellCount - 1 do
  begin
    Offsets[I].Index := I + 1;
    Offsets[I].TimeOffset := I * 1.0;
  end;
  FView.SetCellCount(ACellCount, Offsets);
  for I := 0 to High(ALoadedIndices) do
  begin
    {pf24bit: TFrameView.SetFrame's contract.}
    Bmp := TBitmap.Create;
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(160, 90);
    FView.SetFrame(ALoadedIndices[I], Bmp);
  end;
  {Nonexistent INI: pure defaults (border 0, no size cap). The settings
   object serves every policy interface, as in production wiring.}
  FSettings := TPluginSettings.Create('__nonexistent__.ini');
  FPipeline := TFrameRenderPipeline.Create(FView, FSettings, FSettings, FSettings, FSettings);
  FPredictor := TFrameDimensionPredictor.Create(FView, FSettings, FSettings, FPipeline);
end;

procedure TTestFrameDimensionPredictor.TearDown;
begin
  FreeAndNil(FPredictor);
  FreeAndNil(FPipeline);
  FreeAndNil(FSettings);
  FreeAndNil(FForm); {frees FView via ownership}
  FView := nil;
end;

procedure TTestFrameDimensionPredictor.EmptyView_PredictsZeroAndFormatsEmpty;
var
  W, H, CW, CH: Integer;
begin
  BuildPredictor(0, []);
  FPredictor.PredictCombinedSize(False, W, H);
  Assert.AreEqual(0, W);
  Assert.AreEqual(0, H);
  Assert.IsFalse(FPredictor.PredictDisplayedSize(False, W, H, CW, CH),
    'no cells: nothing to predict');
  Assert.AreEqual('', FPredictor.FormatPredictedSize(False),
    'caption suffix must vanish when there is nothing to show');
end;

procedure TTestFrameDimensionPredictor.SingleMode_Native_UsesBitmapDimensions;
var
  W, H: Integer;
begin
  BuildPredictor(3, [0]);
  FView.ViewMode := vmSingle;
  FView.CurrentFrameIndex := 0;
  FPredictor.PredictCombinedSize(False, W, H);
  Assert.AreEqual(160, W, 'native single-frame width = bitmap width');
  Assert.AreEqual(90, H, 'native single-frame height = bitmap height');
end;

procedure TTestFrameDimensionPredictor.SingleMode_Native_NoBitmap_FallsBackTo320x240;
var
  W, H: Integer;
begin
  BuildPredictor(3, []);
  FView.ViewMode := vmSingle;
  FView.CurrentFrameIndex := 0;
  FPredictor.PredictCombinedSize(False, W, H);
  Assert.AreEqual(320, W, 'unloaded cell falls back to the 320x240 placeholder');
  Assert.AreEqual(240, H);
end;

procedure TTestFrameDimensionPredictor.SingleMode_Live_UsesCellRect;
var
  W, H: Integer;
  R: TRect;
begin
  BuildPredictor(3, [0]);
  FView.ViewMode := vmSingle;
  FView.CurrentFrameIndex := 0;
  R := FView.GetCellRect(FView.CurrentFrameIndex);
  FPredictor.PredictCombinedSize(True, W, H);
  Assert.AreEqual(Max(1, R.Width), W, 'live single-frame size = on-screen cell rect');
  Assert.AreEqual(Max(1, R.Height), H);
end;

procedure TTestFrameDimensionPredictor.GridMode_Native_SingleCell_MatchesCellDimensions;
var
  W, H: Integer;
begin
  {One cell: columns resolve to 1 and the gap term vanishes, so with the
   default border of 0 the combined size equals the cell size exactly.}
  BuildPredictor(1, [0]);
  FView.ViewMode := vmGrid;
  FPredictor.PredictCombinedSize(False, W, H);
  Assert.AreEqual(160, W);
  Assert.AreEqual(90, H);
end;

procedure TTestFrameDimensionPredictor.SmartGridMode_LoadedCells_PredictsPositive;
var
  W, H: Integer;
begin
  BuildPredictor(4, [0, 1, 2, 3]);
  FView.ViewMode := vmSmartGrid;
  FPredictor.PredictCombinedSize(False, W, H);
  Assert.IsTrue(W > 0, 'smart grid with loaded cells must predict a real width');
  Assert.IsTrue(H > 0, 'smart grid with loaded cells must predict a real height');
end;

procedure TTestFrameDimensionPredictor.PredictDisplayedSize_NoCap_CappedEqualsRaw;
var
  W, H, CW, CH: Integer;
begin
  BuildPredictor(1, [0]);
  FView.ViewMode := vmGrid;
  Assert.IsTrue(FPredictor.PredictDisplayedSize(False, W, H, CW, CH));
  Assert.AreEqual(W, CW, 'CombinedMaxSide=0 means no clamp');
  Assert.AreEqual(H, CH);
end;

procedure TTestFrameDimensionPredictor.FormatPredictedSize_Uncapped_BracketsRawSize;
begin
  BuildPredictor(1, [0]);
  FView.ViewMode := vmGrid;
  Assert.AreEqual(' [160x90]', FPredictor.FormatPredictedSize(False));
end;

procedure TTestFrameDimensionPredictor.FormatPredictedSize_Capped_ShowsTransformGlyph;
begin
  BuildPredictor(1, [0]);
  FView.ViewMode := vmGrid;
  {Cap at 80: 160x90 scales by 0.5 to 80x45; the caption must show the
   raw -> capped transform with the platform glyph.}
  FSettings.CombinedMaxSide := 80;
  Assert.AreEqual(Format(' [%dx%d%s%dx%d]', [160, 90, ResolutionTransformGlyph, 80, 45]),
    FPredictor.FormatPredictedSize(False));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameDimensionPredictor);

end.
