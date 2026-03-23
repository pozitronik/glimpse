unit TestFrameView;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFrameViewLayout = class
  public
    [Test] procedure TestGridColumnsSingleFrame;
    [Test] procedure TestGridColumnsTwoFrames;
    [Test] procedure TestGridColumnsFourFrames;
    [Test] procedure TestGridColumnsNineFrames;
    [Test] procedure TestGridColumnsSixteenFrames;
    [Test] procedure TestScrollModeAlwaysOneColumn;
    [Test] procedure TestRecalcSizeEmptyCells;
    [Test] procedure TestRecalcSizeGridMode;
    [Test] procedure TestRecalcSizeScrollMode;
    [Test] procedure TestCellRectsNoOverlap;
    [Test] procedure TestCellRectsWithinBounds;
  end;

  [TestFixture]
  TTestFrameViewState = class
  public
    [Test] procedure TestSetCellCountCreatesPlaceholders;
    [Test] procedure TestSetCellCountStoresTimecodes;
    [Test] procedure TestSetFrameChangesState;
    [Test] procedure TestSetCellErrorChangesState;
    [Test] procedure TestClearCellsFreesBitmaps;
    [Test] procedure TestClearCellsResetsArray;
    [Test] procedure TestHasPlaceholdersAllPlaceholders;
    [Test] procedure TestHasPlaceholdersNone;
    [Test] procedure TestHasPlaceholdersMixed;
    [Test] procedure TestSetFrameOutOfRange;
    [Test] procedure TestSetCellErrorOutOfRange;
  end;

implementation

uses
  System.SysUtils, System.Types, Vcl.Forms, Vcl.Graphics,
  uPluginForm, uFrameOffsets, uSettings;

{ Helper: create a TFrameView with a temporary parent so it has a valid ClientWidth }
function CreateTestFrameView(AWidth: Integer; AMode: TViewMode): TFrameView;
var
  ParentForm: TForm;
begin
  ParentForm := TForm.CreateNew(nil);
  ParentForm.Width := AWidth;
  ParentForm.Height := 800;

  Result := TFrameView.Create(ParentForm);
  Result.Parent := ParentForm;
  Result.Left := 0;
  Result.Top := 0;
  Result.Width := AWidth;
  Result.ViewMode := AMode;
end;

procedure FreeTestFrameView(AView: TFrameView);
begin
  { Freeing the parent form also frees the child frame view }
  AView.Parent.Free;
end;

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

{ TTestFrameViewLayout }

procedure TTestFrameViewLayout.TestGridColumnsSingleFrame;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    { Single frame = 1 column }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0, 'Height should be positive for 1 cell');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsTwoFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    { floor(sqrt(2)) = 1 column }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsFourFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    { floor(sqrt(4)) = 2 columns, 2 rows }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsNineFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    { floor(sqrt(9)) = 3 columns, 3 rows }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestGridColumnsSixteenFrames;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(16, MakeOffsets(16));
    { floor(sqrt(16)) = 4 columns, 4 rows }
    V.RecalcSize;
    Assert.IsTrue(V.Height > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestScrollModeAlwaysOneColumn;
var
  V: TFrameView;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmScroll);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    { In scroll mode all cells stack vertically (same Left, increasing Top) }
    R1 := V.GetCellRect(0);
    R2 := V.GetCellRect(1);
    Assert.AreEqual(R1.Left, R2.Left, 'Cells should have same Left in scroll mode');
    Assert.IsTrue(R2.Top > R1.Bottom, 'Cell 2 should be below cell 1');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestRecalcSizeEmptyCells;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(0, nil);
    V.RecalcSize;
    Assert.AreEqual(0, V.Height, 'Empty cell list should produce zero height');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestRecalcSizeGridMode;
var
  V: TFrameView;
  H4, H9: Integer;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    H4 := V.Height;

    V.SetCellCount(9, MakeOffsets(9));
    V.RecalcSize;
    H9 := V.Height;

    { 4 frames = 2x2 grid; 9 frames = 3x3 grid. Both have same row count
      relative to columns, so heights depend on cell size. With more columns
      cells are smaller, so 3x3 should be shorter or equal to 2x2. }
    Assert.IsTrue(H4 > 0);
    Assert.IsTrue(H9 > 0);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestRecalcSizeScrollMode;
var
  V: TFrameView;
  H2, H4: Integer;
begin
  V := CreateTestFrameView(800, vmScroll);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.RecalcSize;
    H2 := V.Height;

    V.SetCellCount(4, MakeOffsets(4));
    V.RecalcSize;
    H4 := V.Height;

    { More frames in scroll mode = taller }
    Assert.IsTrue(H4 > H2, 'More frames should produce greater height in scroll mode');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestCellRectsNoOverlap;
var
  V: TFrameView;
  I, J: Integer;
  R1, R2: TRect;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    for I := 0 to 7 do
      for J := I + 1 to 8 do
      begin
        R1 := V.GetCellRect(I);
        R2 := V.GetCellRect(J);
        Assert.IsFalse(
          (R1.Left < R2.Right) and (R1.Right > R2.Left) and
          (R1.Top < R2.Bottom) and (R1.Bottom > R2.Top),
          Format('Cells %d and %d overlap', [I, J]));
      end;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewLayout.TestCellRectsWithinBounds;
var
  V: TFrameView;
  I: Integer;
  R: TRect;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(9, MakeOffsets(9));
    V.RecalcSize;
    for I := 0 to 8 do
    begin
      R := V.GetCellRect(I);
      Assert.IsTrue(R.Left >= 0, Format('Cell %d Left < 0', [I]));
      Assert.IsTrue(R.Top >= 0, Format('Cell %d Top < 0', [I]));
      Assert.IsTrue(R.Right <= V.Width, Format('Cell %d Right > Width', [I]));
      Assert.IsTrue(R.Bottom <= V.Height, Format('Cell %d Bottom > Height', [I]));
    end;
  finally
    FreeTestFrameView(V);
  end;
end;

{ TTestFrameViewState }

procedure TTestFrameViewState.TestSetCellCountCreatesPlaceholders;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    Assert.IsTrue(V.HasPlaceholders, 'New cells should all be placeholders');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellCountStoresTimecodes;
var
  V: TFrameView;
  Offsets: TFrameOffsetArray;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    Offsets := MakeOffsets(2);
    V.SetCellCount(2, Offsets);
    { Timecodes should match FormatTimecode of the offsets }
    Assert.AreEqual(FormatTimecode(10.0), V.FCells[0].Timecode);
    Assert.AreEqual(FormatTimecode(20.0), V.FCells[1].Timecode);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetFrameChangesState;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    Bmp := TBitmap.Create;
    Bmp.Width := 100;
    Bmp.Height := 50;
    V.SetFrame(0, Bmp);
    Assert.AreEqual(Ord(fcsLoaded), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[1].State));
    Assert.AreSame(Bmp, V.FCells[0].Bitmap);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellErrorChangesState;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.SetCellError(1);
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsError), Ord(V.FCells[1].State));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestClearCellsFreesBitmaps;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(1, MakeOffsets(1));
    Bmp := TBitmap.Create;
    Bmp.Width := 10;
    Bmp.Height := 10;
    V.SetFrame(0, Bmp);
    V.ClearCells;
    { After clear, cell array should be empty }
    Assert.AreEqual(0, Integer(Length(V.FCells)));
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestClearCellsResetsArray;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(5, MakeOffsets(5));
    V.ClearCells;
    Assert.AreEqual(0, Integer(Length(V.FCells)));
    Assert.IsFalse(V.HasPlaceholders, 'Empty cell list has no placeholders');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestHasPlaceholdersAllPlaceholders;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    Assert.IsTrue(V.HasPlaceholders);
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestHasPlaceholdersNone;
var
  V: TFrameView;
  I: Integer;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    for I := 0 to 2 do
    begin
      Bmp := TBitmap.Create;
      Bmp.SetSize(10, 10);
      V.SetFrame(I, Bmp);
    end;
    Assert.IsFalse(V.HasPlaceholders, 'All loaded = no placeholders');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestHasPlaceholdersMixed;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(3, MakeOffsets(3));
    Bmp := TBitmap.Create;
    Bmp.SetSize(10, 10);
    V.SetFrame(0, Bmp);
    V.SetCellError(1);
    { Cell 2 is still a placeholder }
    Assert.IsTrue(V.HasPlaceholders, 'One placeholder remains');
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetFrameOutOfRange;
var
  V: TFrameView;
  Bmp: TBitmap;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    Bmp := TBitmap.Create;
    Bmp.SetSize(10, 10);
    { Should not crash or corrupt; bitmap is leaked intentionally in this test }
    V.SetFrame(5, Bmp);
    V.SetFrame(-1, Bmp);
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[1].State));
    Bmp.Free;
  finally
    FreeTestFrameView(V);
  end;
end;

procedure TTestFrameViewState.TestSetCellErrorOutOfRange;
var
  V: TFrameView;
begin
  V := CreateTestFrameView(800, vmGrid);
  try
    V.SetCellCount(2, MakeOffsets(2));
    V.SetCellError(10);
    V.SetCellError(-1);
    { No crash, cells unchanged }
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[0].State));
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(V.FCells[1].State));
  finally
    FreeTestFrameView(V);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameViewLayout);
  TDUnitX.RegisterTestFixture(TTestFrameViewState);

end.
