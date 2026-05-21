{Tests for TFrameCellStore: cell lifecycle, bitmap ownership and selection.}
unit TestFrameCellStore;

interface

uses
  DUnitX.TestFramework,
  FrameCellStore;

type
  [TestFixture]
  TTestFrameCellStore = class
  strict private
    FStore: TFrameCellStore;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure SetCellCount_CreatesPlaceholders;
    [Test] procedure SetCellCount_SetsCount;
    [Test] procedure SetCellCount_StoresTimecodesAndOffsets;
    [Test] procedure SetCellCount_NilOffsets_EmptyTimecodes;
    [Test] procedure SetCellCount_OffsetsShorterThanCount;
    [Test] procedure SetCellCount_ResetsSelection;
    [Test] procedure SetCellCount_ShrinkFreesDroppedBitmaps;

    [Test] procedure SetFrame_ChangesStateToLoaded;
    [Test] procedure SetFrame_StoresBitmapOfSameSize;
    [Test] procedure SetFrame_OutOfRange_DoesNotChangeCells;
    [Test] procedure SetFrame_NegativeIndex_DoesNotRaise;
    [Test] procedure SetFrame_Pf32bit_Raises;

    [Test] procedure SetCellError_ChangesStateToError;
    [Test] procedure SetCellError_OutOfRange_DoesNotRaise;

    [Test] procedure Clear_EmptiesCollection;
    [Test] procedure Clear_OnEmpty_DoesNotRaise;

    [Test] procedure HasPlaceholders_TrueWhenPlaceholderPresent;
    [Test] procedure HasPlaceholders_FalseWhenAllLoaded;
    [Test] procedure HasLoadedCells_FalseWhenEmpty;
    [Test] procedure HasLoadedCells_FalseWhenAllPlaceholders;
    [Test] procedure HasLoadedCells_TrueWhenOneLoaded;

    [Test] procedure Selected_DefaultsFalse;
    [Test] procedure ToggleSelection_FlipsSelectedState;
    [Test] procedure ToggleSelection_OutOfRange_DoesNotRaise;
    [Test] procedure Selected_NegativeIndex_ReturnsFalse;
    [Test] procedure Selected_IndexBeyondCount_ReturnsFalse;
    [Test] procedure ReadersOutOfRangeIndex_ReturnSafeDefaults;
    [Test] procedure SelectAll_SelectsEveryCell;
    [Test] procedure DeselectAll_ClearsEveryCell;
    [Test] procedure SelectedCount_CountsSelectedCells;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Graphics,
  FrameOffsets;

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

{SetFrame takes ownership of the bitmap on every path, so tests hand
 these over without freeing them.}
function MakeBitmap(AWidth, AHeight: Integer; AFormat: TPixelFormat): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := AFormat;
  Result.SetSize(AWidth, AHeight);
end;

procedure TTestFrameCellStore.Setup;
begin
  FStore := TFrameCellStore.Create;
end;

procedure TTestFrameCellStore.TearDown;
begin
  FreeAndNil(FStore);
end;

procedure TTestFrameCellStore.SetCellCount_CreatesPlaceholders;
var
  I: Integer;
begin
  FStore.SetCellCount(3, nil);
  for I := 0 to 2 do
    Assert.AreEqual(Ord(fcsPlaceholder), Ord(FStore.State(I)));
end;

procedure TTestFrameCellStore.SetCellCount_SetsCount;
begin
  FStore.SetCellCount(5, nil);
  Assert.AreEqual(5, FStore.Count);
end;

procedure TTestFrameCellStore.SetCellCount_StoresTimecodesAndOffsets;
begin
  FStore.SetCellCount(2, MakeOffsets(2));
  Assert.AreEqual(10.0, FStore.TimeOffset(0), 0.001);
  Assert.AreEqual(20.0, FStore.TimeOffset(1), 0.001);
  Assert.AreEqual(FormatTimecode(10.0), FStore.Timecode(0));
  Assert.AreEqual(FormatTimecode(20.0), FStore.Timecode(1));
end;

procedure TTestFrameCellStore.SetCellCount_NilOffsets_EmptyTimecodes;
begin
  FStore.SetCellCount(2, nil);
  Assert.AreEqual('', FStore.Timecode(0));
  Assert.AreEqual(0.0, FStore.TimeOffset(0), 0.001);
end;

procedure TTestFrameCellStore.SetCellCount_OffsetsShorterThanCount;
begin
  FStore.SetCellCount(3, MakeOffsets(1));
  Assert.AreEqual(FormatTimecode(10.0), FStore.Timecode(0));
  Assert.AreEqual('', FStore.Timecode(1), 'cell beyond the offset array gets an empty timecode');
  Assert.AreEqual('', FStore.Timecode(2));
end;

procedure TTestFrameCellStore.SetCellCount_ResetsSelection;
begin
  FStore.SetCellCount(2, nil);
  FStore.SelectAll;
  FStore.SetCellCount(2, nil);
  Assert.AreEqual(0, FStore.SelectedCount, 'a cell-count change must clear stale selection');
end;

procedure TTestFrameCellStore.SetCellCount_ShrinkFreesDroppedBitmaps;
begin
  {Loads a frame, then shrinks below it; the dropped slot's bitmap must
   be freed. A leak would surface in the run's memory-leak report.}
  FStore.SetCellCount(3, nil);
  FStore.SetFrame(2, MakeBitmap(8, 8, pf24bit));
  FStore.SetCellCount(1, nil);
  Assert.AreEqual(1, FStore.Count);
end;

procedure TTestFrameCellStore.SetFrame_ChangesStateToLoaded;
begin
  FStore.SetCellCount(2, nil);
  FStore.SetFrame(0, MakeBitmap(10, 10, pf24bit));
  Assert.AreEqual(Ord(fcsLoaded), Ord(FStore.State(0)));
  Assert.IsNotNull(FStore.Bitmap(0));
end;

procedure TTestFrameCellStore.SetFrame_StoresBitmapOfSameSize;
begin
  FStore.SetCellCount(1, nil);
  FStore.SetFrame(0, MakeBitmap(24, 16, pf24bit));
  Assert.AreEqual(24, FStore.Bitmap(0).Width);
  Assert.AreEqual(16, FStore.Bitmap(0).Height);
end;

procedure TTestFrameCellStore.SetFrame_OutOfRange_DoesNotChangeCells;
begin
  FStore.SetCellCount(1, nil);
  FStore.SetFrame(5, MakeBitmap(10, 10, pf24bit));
  Assert.AreEqual(1, FStore.Count);
  Assert.AreEqual(Ord(fcsPlaceholder), Ord(FStore.State(0)));
end;

procedure TTestFrameCellStore.SetFrame_NegativeIndex_DoesNotRaise;
begin
  FStore.SetCellCount(1, nil);
  Assert.WillNotRaise(
    procedure begin FStore.SetFrame(-1, MakeBitmap(10, 10, pf24bit)); end);
end;

procedure TTestFrameCellStore.SetFrame_Pf32bit_Raises;
begin
  FStore.SetCellCount(1, nil);
  {SetFrame frees the rejected bitmap before raising, so the test must
   not free it.}
  Assert.WillRaise(
    procedure begin FStore.SetFrame(0, MakeBitmap(10, 10, pf32bit)); end,
    EArgumentException);
end;

procedure TTestFrameCellStore.SetCellError_ChangesStateToError;
begin
  FStore.SetCellCount(2, nil);
  FStore.SetCellError(1);
  Assert.AreEqual(Ord(fcsError), Ord(FStore.State(1)));
end;

procedure TTestFrameCellStore.SetCellError_OutOfRange_DoesNotRaise;
begin
  FStore.SetCellCount(1, nil);
  Assert.WillNotRaise(procedure begin FStore.SetCellError(9); end);
end;

procedure TTestFrameCellStore.Clear_EmptiesCollection;
begin
  FStore.SetCellCount(4, nil);
  FStore.Clear;
  Assert.AreEqual(0, FStore.Count);
end;

procedure TTestFrameCellStore.Clear_OnEmpty_DoesNotRaise;
begin
  Assert.WillNotRaise(procedure begin FStore.Clear; end);
end;

procedure TTestFrameCellStore.HasPlaceholders_TrueWhenPlaceholderPresent;
begin
  FStore.SetCellCount(2, nil);
  FStore.SetFrame(0, MakeBitmap(10, 10, pf24bit));
  Assert.IsTrue(FStore.HasPlaceholders);
end;

procedure TTestFrameCellStore.HasPlaceholders_FalseWhenAllLoaded;
begin
  FStore.SetCellCount(2, nil);
  FStore.SetFrame(0, MakeBitmap(10, 10, pf24bit));
  FStore.SetFrame(1, MakeBitmap(10, 10, pf24bit));
  Assert.IsFalse(FStore.HasPlaceholders);
end;

procedure TTestFrameCellStore.HasLoadedCells_FalseWhenEmpty;
begin
  Assert.IsFalse(FStore.HasLoadedCells);
end;

procedure TTestFrameCellStore.HasLoadedCells_FalseWhenAllPlaceholders;
begin
  FStore.SetCellCount(3, nil);
  Assert.IsFalse(FStore.HasLoadedCells);
end;

procedure TTestFrameCellStore.HasLoadedCells_TrueWhenOneLoaded;
begin
  FStore.SetCellCount(3, nil);
  FStore.SetFrame(1, MakeBitmap(10, 10, pf24bit));
  Assert.IsTrue(FStore.HasLoadedCells);
end;

procedure TTestFrameCellStore.Selected_DefaultsFalse;
begin
  FStore.SetCellCount(2, nil);
  Assert.IsFalse(FStore.Selected(0));
end;

procedure TTestFrameCellStore.ToggleSelection_FlipsSelectedState;
begin
  FStore.SetCellCount(2, nil);
  FStore.ToggleSelection(0);
  Assert.IsTrue(FStore.Selected(0), 'first toggle selects');
  FStore.ToggleSelection(0);
  Assert.IsFalse(FStore.Selected(0), 'second toggle deselects');
end;

procedure TTestFrameCellStore.ToggleSelection_OutOfRange_DoesNotRaise;
begin
  FStore.SetCellCount(1, nil);
  Assert.WillNotRaise(procedure begin FStore.ToggleSelection(7); end);
end;

procedure TTestFrameCellStore.Selected_NegativeIndex_ReturnsFalse;
begin
  FStore.SetCellCount(2, nil);
  Assert.IsFalse(FStore.Selected(-1));
end;

procedure TTestFrameCellStore.Selected_IndexBeyondCount_ReturnsFalse;
begin
  FStore.SetCellCount(2, nil);
  Assert.IsFalse(FStore.Selected(99));
end;

procedure TTestFrameCellStore.ReadersOutOfRangeIndex_ReturnSafeDefaults;
begin
  {State/Bitmap/TimeOffset/Timecode must tolerate the -1 ("no cell at
   point") and beyond-count indices their callers occasionally pass,
   exactly as Selected does, instead of indexing FCells out of bounds.}
  FStore.SetCellCount(2, nil);
  Assert.AreEqual(Ord(fcsPlaceholder), Ord(FStore.State(-1)));
  Assert.AreEqual(Ord(fcsPlaceholder), Ord(FStore.State(99)));
  Assert.IsNull(FStore.Bitmap(-1));
  Assert.IsNull(FStore.Bitmap(99));
  Assert.AreEqual(0.0, FStore.TimeOffset(-1), 0.001);
  Assert.AreEqual(0.0, FStore.TimeOffset(99), 0.001);
  Assert.AreEqual('', FStore.Timecode(-1));
  Assert.AreEqual('', FStore.Timecode(99));
end;

procedure TTestFrameCellStore.SelectAll_SelectsEveryCell;
begin
  FStore.SetCellCount(3, nil);
  FStore.SelectAll;
  Assert.AreEqual(3, FStore.SelectedCount);
end;

procedure TTestFrameCellStore.DeselectAll_ClearsEveryCell;
begin
  FStore.SetCellCount(3, nil);
  FStore.SelectAll;
  FStore.DeselectAll;
  Assert.AreEqual(0, FStore.SelectedCount);
end;

procedure TTestFrameCellStore.SelectedCount_CountsSelectedCells;
begin
  FStore.SetCellCount(4, nil);
  FStore.ToggleSelection(0);
  FStore.ToggleSelection(2);
  Assert.AreEqual(2, FStore.SelectedCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameCellStore);

end.
