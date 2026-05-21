{Tests for TExportTargetResolver: frame-index resolution, selection-aware
 action-cell picking, and save-index set building.}
unit TestExportTargetResolver;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResolveFrameIndex = class
  public
    [Test] procedure TestContextCellPreferred;
    [Test] procedure TestFallsBackToCurrentFrame;
    [Test] procedure TestFallsBackToZero;
    [Test] procedure TestReturnsFalseWhenEmpty;
    [Test] procedure TestReturnsFalseWhenNotLoaded;
    [Test] procedure TestNegativeContextIgnored;
    [Test] procedure TestOutOfRangeContextIgnored;
  end;

  [TestFixture]
  TTestPickActionCell = class
  public
    [Test] procedure SelectionWinsOverContextCell;
    [Test] procedure ContextCellUsedWhenNoSelection;
    [Test] procedure ContextCellOutOfRangeFallsThrough;
    [Test] procedure ContextCellNotLoadedFallsThrough;
    [Test] procedure SelectionUsedWhenNoContext;
    [Test] procedure FirstSelectedLoadedCellWins;
    [Test] procedure UnloadedSelectedCellSkipped;
    [Test] procedure FallsBackToCurrentFrameInSingleView;
    [Test] procedure CurrentFrameIgnoredOutsideSingleView;
    [Test] procedure FallsBackToCellZero;
    [Test] procedure ReturnsMinusOneWhenNothingLoaded;
    [Test] procedure ReturnsMinusOneWhenNoCells;
  end;

  [TestFixture]
  TTestBuildSaveIndices = class
  public
    [Test] procedure TestSingleResolvesContextCell;
    [Test] procedure TestSingleEmptyWhenNoLoadedFrames;
    [Test] procedure TestAllLoadedSkipsUnloadedCells;
    [Test] procedure TestAllLoadedEmptyWhenNothingLoaded;
    [Test] procedure TestSelectedOrAllUsesSelectionWhenAny;
    [Test] procedure TestSelectedOrAllFallsBackToAllWhenNoSelection;
    [Test] procedure TestSelectedOrAllSkipsUnloadedSelected;
  end;

implementation

uses
  Vcl.Forms, Vcl.Graphics,
  Types, FrameView, FrameOffsets, ExportTargetResolver;

{Creates a temporary TFrameView parented to a form: ACellCount cells with
 the listed indices loaded with placeholder bitmaps.}
function CreateTestFrameView(AForm: TForm; ACellCount: Integer;
  const ALoadedIndices: array of Integer): TFrameView;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
  Bmp: TBitmap;
begin
  Result := TFrameView.Create(AForm);
  Result.Parent := AForm;
  Result.SetViewport(800, 600);
  Result.AspectRatio := 9 / 16;

  SetLength(Offsets, ACellCount);
  for I := 0 to ACellCount - 1 do
  begin
    Offsets[I].Index := I + 1;
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Result.SetCellCount(ACellCount, Offsets);

  for I := 0 to High(ALoadedIndices) do
  begin
    {pf24bit: TFrameView.SetFrame's contract; default pfDevice would
     trip the runtime check.}
    Bmp := TBitmap.Create;
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(160, 90);
    Result.SetFrame(ALoadedIndices[I], Bmp);
  end;
end;

{ TTestResolveFrameIndex }

procedure TTestResolveFrameIndex.TestContextCellPreferred;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2, 4]);
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.IsTrue(Resolver.ResolveFrameIndex(2, Idx));
      Assert.AreEqual(2, Idx);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestFallsBackToCurrentFrame;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 3]);
    View.CurrentFrameIndex := 3;
    Resolver := TExportTargetResolver.Create(View);
    try
      { Context index -1 => falls back to CurrentFrameIndex }
      Assert.IsTrue(Resolver.ResolveFrameIndex(-1, Idx));
      Assert.AreEqual(3, Idx);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestFallsBackToZero;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0]);
    View.CurrentFrameIndex := -1;
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.IsTrue(Resolver.ResolveFrameIndex(-1, Idx));
      Assert.AreEqual(0, Idx);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestReturnsFalseWhenEmpty;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.IsFalse(Resolver.ResolveFrameIndex(-1, Idx));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestReturnsFalseWhenNotLoaded;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    { 3 cells, none loaded }
    View := CreateTestFrameView(Form, 3, []);
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.IsFalse(Resolver.ResolveFrameIndex(1, Idx));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestNegativeContextIgnored;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    View.CurrentFrameIndex := 1;
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.IsTrue(Resolver.ResolveFrameIndex(-5, Idx));
      Assert.AreEqual(1, Idx);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestOutOfRangeContextIgnored;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    View.CurrentFrameIndex := 2;
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.IsTrue(Resolver.ResolveFrameIndex(99, Idx));
      Assert.AreEqual(2, Idx);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestPickActionCell }

procedure TTestPickActionCell.SelectionWinsOverContextCell;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(1); { selection = [1] }
    Resolver := TExportTargetResolver.Create(View);
    try
      { Right-click on cell 3 with cell 1 selected -> menu acts on 1.
        Selection is the more deliberate gesture and wins regardless of
        where the right-click landed; matches TC's context-menu rule. }
      Assert.AreEqual(1, Resolver.PickActionCell(3));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ContextCellUsedWhenNoSelection;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    { No selection, right-click on cell 3 -> menu acts on 3.
      Confirms the context cell is the fallback when selection is empty. }
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(3, Resolver.PickActionCell(3));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ContextCellOutOfRangeFallsThrough;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(2); { selection = [2] }
    Resolver := TExportTargetResolver.Create(View);
    try
      { Out-of-range context falls through to selection }
      Assert.AreEqual(2, Resolver.PickActionCell(99));
      Assert.AreEqual(2, Resolver.PickActionCell(-5));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ContextCellNotLoadedFallsThrough;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    { Cells 0, 1, 2 exist; only 0 and 2 are loaded; cell 1 is a placeholder }
    View := CreateTestFrameView(Form, 3, [0, 2]);
    View.ToggleSelection(2); { selection = [2] }
    Resolver := TExportTargetResolver.Create(View);
    try
      { Context points at cell 1 which is in range but not loaded -> falls
        through to first selected loaded cell (2) }
      Assert.AreEqual(2, Resolver.PickActionCell(1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.SelectionUsedWhenNoContext;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(3); { selection = [3] }
    Resolver := TExportTargetResolver.Create(View);
    try
      { No context, single-selected cell wins over cell-0 fallback }
      Assert.AreEqual(3, Resolver.PickActionCell(-1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.FirstSelectedLoadedCellWins;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(2);
    View.ToggleSelection(4); { selection = [2, 4]; Copy frame picks 2 }
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(2, Resolver.PickActionCell(-1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.UnloadedSelectedCellSkipped;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    { Cells 0..4 exist; only 2 and 4 are loaded }
    View := CreateTestFrameView(Form, 5, [2, 4]);
    View.ToggleSelection(1); { selected but not loaded }
    View.ToggleSelection(2); { selected and loaded }
    Resolver := TExportTargetResolver.Create(View);
    try
      { First-loaded-selected wins (2), the unloaded selected (1) is skipped }
      Assert.AreEqual(2, Resolver.PickActionCell(-1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.FallsBackToCurrentFrameInSingleView;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ViewMode := vmSingle;
    View.CurrentFrameIndex := 3;
    { No selection, no context -> CurrentFrameIndex in single-view mode }
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(3, Resolver.PickActionCell(-1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.CurrentFrameIgnoredOutsideSingleView;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    {Default view mode is vmGrid (not single-view), so CurrentFrameIndex
     should not influence the pick — falls back to cell 0 instead.}
    View.CurrentFrameIndex := 3;
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(0, Resolver.PickActionCell(-1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.FallsBackToCellZero;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    { No selection, no context, not single-view -> cell 0 }
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(0, Resolver.PickActionCell(-1));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ReturnsMinusOneWhenNothingLoaded;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    { 5 placeholder cells, none loaded -> nothing usable }
    View := CreateTestFrameView(Form, 5, []);
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(-1, Resolver.PickActionCell(-1));
      Assert.AreEqual(-1, Resolver.PickActionCell(2));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ReturnsMinusOneWhenNoCells;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Resolver := TExportTargetResolver.Create(View);
    try
      Assert.AreEqual(-1, Resolver.PickActionCell(-1));
      Assert.AreEqual(-1, Resolver.PickActionCell(0));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestBuildSaveIndices }

procedure TTestBuildSaveIndices.TestSingleResolvesContextCell;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2, 4]);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesSingle(2);
      Assert.AreEqual(1, Integer(Length(Indices)),
        'Single must return exactly one element when context resolves');
      Assert.AreEqual(2, Indices[0]);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestBuildSaveIndices.TestSingleEmptyWhenNoLoadedFrames;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  {Cells exist but none are loaded -> ResolveFrameIndex returns False;
   Single must hand back an empty array so WithReExtract no-ops.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, []);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesSingle(0);
      Assert.AreEqual(0, Integer(Length(Indices)));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestBuildSaveIndices.TestAllLoadedSkipsUnloadedCells;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [1, 3]);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesAllLoaded;
      Assert.AreEqual(2, Integer(Length(Indices)));
      Assert.AreEqual(1, Indices[0]);
      Assert.AreEqual(3, Indices[1]);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestBuildSaveIndices.TestAllLoadedEmptyWhenNothingLoaded;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, []);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesAllLoaded;
      Assert.AreEqual(0, Integer(Length(Indices)));
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestBuildSaveIndices.TestSelectedOrAllUsesSelectionWhenAny;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  {When at least one cell is selected, only loaded selected cells
   must be returned — mirrors the SaveFrames selection-aware semantics.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(1);
    View.ToggleSelection(3);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesSelectedOrAll;
      Assert.AreEqual(2, Integer(Length(Indices)));
      Assert.AreEqual(1, Indices[0]);
      Assert.AreEqual(3, Indices[1]);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestBuildSaveIndices.TestSelectedOrAllFallsBackToAllWhenNoSelection;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesSelectedOrAll;
      Assert.AreEqual(4, Integer(Length(Indices)),
        'No selection -> every loaded cell');
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestBuildSaveIndices.TestSelectedOrAllSkipsUnloadedSelected;
var
  Form: TForm;
  View: TFrameView;
  Resolver: TExportTargetResolver;
  Indices: TArray<Integer>;
begin
  {Selection over an unloaded cell must be ignored: the action cannot
   read a frame that does not exist yet, so re-extraction would hand it
   a nil bitmap.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2]);
    View.ToggleSelection(0);
    View.ToggleSelection(1); {unloaded, must drop}
    View.ToggleSelection(2);
    Resolver := TExportTargetResolver.Create(View);
    try
      Indices := Resolver.BuildSaveIndicesSelectedOrAll;
      Assert.AreEqual(2, Integer(Length(Indices)));
      Assert.AreEqual(0, Indices[0]);
      Assert.AreEqual(2, Indices[1]);
    finally
      Resolver.Free;
    end;
  finally
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestResolveFrameIndex);
  TDUnitX.RegisterTestFixture(TTestPickActionCell);
  TDUnitX.RegisterTestFixture(TTestBuildSaveIndices);

end.
