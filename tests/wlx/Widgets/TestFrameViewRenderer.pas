{Tests for TFrameViewRenderer: property round-trips, the animation step,
 and smoke tests that the paint paths run without raising. Visual
 correctness of the painting is verified manually in the plugin.}
unit TestFrameViewRenderer;

interface

uses
  DUnitX.TestFramework,
  Vcl.Graphics,
  FrameCellStore,
  FrameGeometry,
  FrameViewRenderer;

type
  [TestFixture]
  TTestFrameViewRenderer = class
  strict private
    FBmp: TBitmap;
    FStore: TFrameCellStore;
    FGeo: TFrameGeometry;
    FRenderer: TFrameViewRenderer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure BackColor_RoundTrips;
    [Test] procedure ShowTimecode_RoundTrips;
    [Test] procedure AdvanceAnimation_IncrementsStep;
    [Test] procedure AdvanceAnimation_WrapsToZero;
    [Test] procedure ApplyTimestampStyle_ReturnsTrueWhenChanged;
    [Test] procedure ApplyTimestampStyle_ReturnsFalseWhenUnchanged;
    [Test] procedure ApplyTimestampStyle_AssignsNewStyle;

    [Test] procedure Paint_EmptyStore_DoesNotRaise;
    [Test] procedure Paint_PlaceholderCells_DoesNotRaise;
    [Test] procedure Paint_LoadedCell_DoesNotRaise;
    [Test] procedure Paint_WithTimecodes_DoesNotRaise;
    [Test] procedure Paint_SingleViewMode_DoesNotRaise;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Types,
  TimecodeOverlay,
  FrameOffsets;

const
  CANVAS_W = 400;
  CANVAS_H = 300;

function MakeOffsets(ACount: Integer): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := (I + 1) * 10.0;
  end;
end;

{SetFrame takes ownership of the bitmap, so callers hand it over without
 freeing it.}
function MakeBitmap(AWidth, AHeight: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
end;

procedure TTestFrameViewRenderer.Setup;
begin
  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf24bit;
  FBmp.SetSize(CANVAS_W, CANVAS_H);
  FStore := TFrameCellStore.Create;
  FGeo := TFrameGeometry.Create(FStore);
  FGeo.SetViewport(CANVAS_W, CANVAS_H);
  FRenderer := TFrameViewRenderer.Create(FBmp.Canvas, FStore, FGeo);
end;

procedure TTestFrameViewRenderer.TearDown;
begin
  {Renderer borrows the canvas, store and geometry, so free it first.}
  FreeAndNil(FRenderer);
  FreeAndNil(FGeo);
  FreeAndNil(FStore);
  FreeAndNil(FBmp);
end;

procedure TTestFrameViewRenderer.BackColor_RoundTrips;
begin
  FRenderer.BackColor := TColor($00102030);
  Assert.AreEqual(Integer(TColor($00102030)), Integer(FRenderer.BackColor));
end;

procedure TTestFrameViewRenderer.ShowTimecode_RoundTrips;
begin
  FRenderer.ShowTimecode := False;
  Assert.IsFalse(FRenderer.ShowTimecode);
  FRenderer.ShowTimecode := True;
  Assert.IsTrue(FRenderer.ShowTimecode);
end;

procedure TTestFrameViewRenderer.AdvanceAnimation_IncrementsStep;
begin
  Assert.AreEqual(0, FRenderer.AnimStep);
  FRenderer.AdvanceAnimation;
  Assert.AreEqual(1, FRenderer.AnimStep);
  FRenderer.AdvanceAnimation;
  Assert.AreEqual(2, FRenderer.AnimStep);
end;

procedure TTestFrameViewRenderer.AdvanceAnimation_WrapsToZero;
var
  I: Integer;
begin
  {The spinner advances 45 degrees per tick, so it wraps after 360/45 = 8.}
  for I := 1 to 8 do
    FRenderer.AdvanceAnimation;
  Assert.AreEqual(0, FRenderer.AnimStep, 'the spinner step wraps back to zero');
end;

procedure TTestFrameViewRenderer.ApplyTimestampStyle_ReturnsTrueWhenChanged;
var
  S: TTimestampStyle;
begin
  S := FRenderer.TimestampStyle;
  S.FontSize := S.FontSize + 5;
  Assert.IsTrue(FRenderer.ApplyTimestampStyle(S));
end;

procedure TTestFrameViewRenderer.ApplyTimestampStyle_ReturnsFalseWhenUnchanged;
begin
  Assert.IsFalse(FRenderer.ApplyTimestampStyle(FRenderer.TimestampStyle));
end;

procedure TTestFrameViewRenderer.ApplyTimestampStyle_AssignsNewStyle;
var
  S: TTimestampStyle;
begin
  S := FRenderer.TimestampStyle;
  S.FontSize := 33;
  FRenderer.ApplyTimestampStyle(S);
  Assert.AreEqual(33, FRenderer.TimestampStyle.FontSize);
end;

procedure TTestFrameViewRenderer.Paint_EmptyStore_DoesNotRaise;
begin
  Assert.WillNotRaise(
    procedure begin FRenderer.Paint(Rect(0, 0, CANVAS_W, CANVAS_H), 0); end);
end;

procedure TTestFrameViewRenderer.Paint_PlaceholderCells_DoesNotRaise;
begin
  FStore.SetCellCount(6, nil);
  Assert.WillNotRaise(
    procedure begin FRenderer.Paint(Rect(0, 0, CANVAS_W, CANVAS_H), 0); end);
end;

procedure TTestFrameViewRenderer.Paint_LoadedCell_DoesNotRaise;
begin
  FStore.SetCellCount(2, nil);
  FStore.SetFrame(0, MakeBitmap(20, 15));
  Assert.WillNotRaise(
    procedure begin FRenderer.Paint(Rect(0, 0, CANVAS_W, CANVAS_H), 0); end);
end;

procedure TTestFrameViewRenderer.Paint_WithTimecodes_DoesNotRaise;
var
  S: TTimestampStyle;
begin
  {Force a visible corner so the timecode-overlay path actually runs.}
  S := FRenderer.TimestampStyle;
  S.Show := True;
  S.Corner := tcBottomRight;
  FRenderer.ApplyTimestampStyle(S);
  FStore.SetCellCount(3, MakeOffsets(3));
  Assert.WillNotRaise(
    procedure begin FRenderer.Paint(Rect(0, 0, CANVAS_W, CANVAS_H), 0); end);
end;

procedure TTestFrameViewRenderer.Paint_SingleViewMode_DoesNotRaise;
begin
  FGeo.ViewMode := vmSingle;
  FStore.SetCellCount(3, nil);
  Assert.WillNotRaise(
    procedure begin FRenderer.Paint(Rect(0, 0, CANVAS_W, CANVAS_H), 1); end);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameViewRenderer);

end.
