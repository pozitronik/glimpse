{Unit tests for TFrameCellStore.InvertSelection: the per-cell flag flip
 behind the new bindable Invert-selection command. Kept in a dedicated
 unit so the existing TestFrameCellStore is left untouched.}
unit TestFrameCellStoreInvert;

interface

uses
  DUnitX.TestFramework,
  FrameCellStore;

type
  [TestFixture]
  TTestFrameCellStoreInvert = class
  strict private
    FStore: TFrameCellStore;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure Invert_FromEmpty_SelectsAll;
    [Test] procedure Invert_FromAll_ClearsAll;
    [Test] procedure Invert_Partial_FlipsEachCell;
    [Test] procedure Invert_Twice_RestoresOriginal;
    [Test] procedure Invert_EmptyStore_NoOp;
  end;

implementation

uses
  System.SysUtils;

procedure TTestFrameCellStoreInvert.Setup;
begin
  FStore := TFrameCellStore.Create;
end;

procedure TTestFrameCellStoreInvert.TearDown;
begin
  FreeAndNil(FStore);
end;

procedure TTestFrameCellStoreInvert.Invert_FromEmpty_SelectsAll;
begin
  FStore.SetCellCount(4, nil);
  FStore.InvertSelection;
  Assert.AreEqual(4, FStore.SelectedCount);
end;

procedure TTestFrameCellStoreInvert.Invert_FromAll_ClearsAll;
begin
  FStore.SetCellCount(4, nil);
  FStore.SelectAll;
  FStore.InvertSelection;
  Assert.AreEqual(0, FStore.SelectedCount);
end;

procedure TTestFrameCellStoreInvert.Invert_Partial_FlipsEachCell;
begin
  FStore.SetCellCount(4, nil);
  {Select cells 0 and 2; after inversion only 1 and 3 must be selected.}
  FStore.ToggleSelection(0);
  FStore.ToggleSelection(2);
  FStore.InvertSelection;
  Assert.IsFalse(FStore.Selected(0), 'cell 0 should be deselected');
  Assert.IsTrue(FStore.Selected(1), 'cell 1 should be selected');
  Assert.IsFalse(FStore.Selected(2), 'cell 2 should be deselected');
  Assert.IsTrue(FStore.Selected(3), 'cell 3 should be selected');
  Assert.AreEqual(2, FStore.SelectedCount);
end;

procedure TTestFrameCellStoreInvert.Invert_Twice_RestoresOriginal;
begin
  FStore.SetCellCount(5, nil);
  FStore.ToggleSelection(1);
  FStore.ToggleSelection(3);
  FStore.InvertSelection;
  FStore.InvertSelection;
  Assert.IsTrue(FStore.Selected(1), 'cell 1 restored after double invert');
  Assert.IsTrue(FStore.Selected(3), 'cell 3 restored after double invert');
  Assert.AreEqual(2, FStore.SelectedCount);
end;

procedure TTestFrameCellStoreInvert.Invert_EmptyStore_NoOp;
begin
  FStore.InvertSelection;
  Assert.AreEqual(0, FStore.SelectedCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameCellStoreInvert);

end.
