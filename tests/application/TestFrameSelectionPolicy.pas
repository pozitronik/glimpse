unit TestFrameSelectionPolicy;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResolveFrameIndex = class
  public
    {Empty grid -> False, AIndex untouched. The downstream caller treats
     False as "skip this action", so the AIndex contract just needs to
     not crash; we don't pin its value.}
    [Test] procedure EmptyGrid_ReturnsFalse;
    {Context cell in range and loaded wins — the right-click is the
     user's explicit choice.}
    [Test] procedure ContextInRangeAndLoaded_ReturnsContext;
    {Context out of range falls through to CurrentFrameIndex.}
    [Test] procedure ContextOutOfRange_FallsBackToCurrentFrame;
    {Both context and current out of range — falls back to cell 0.}
    [Test] procedure BothOutOfRange_FallsBackToZero;
    {Picked cell exists but is still placeholder/error -> returns False.
     The legacy callers treat this as "skip the action" (the bitmap
     isn't ready).}
    [Test] procedure PickedCellNotLoaded_ReturnsFalse;
    {Context cell in range but NOT loaded — falls through to current
     frame, which IS loaded, so returns True with the current index.}
    [Test] procedure ContextInRangeNotLoaded_DoesNotFallThrough;
  end;

  [TestFixture]
  TTestPickActionCell = class
  public
    {Priority 1: first selected loaded cell beats everything below.
     Pinning that selection wins over an explicit right-click is the
     core "selection-first" rule.}
    [Test] procedure SelectedLoadedCell_Wins;
    {Multiple selected cells -> the first one wins (deterministic).}
    [Test] procedure MultipleSelected_FirstWins;
    {Selected but NOT loaded -> the priority-1 branch falls through.
     Avoids serving placeholder/error cells.}
    [Test] procedure SelectedButNotLoaded_DoesNotWin;
    {Priority 2: explicit context (right-click) when no selection.}
    [Test] procedure NoSelection_ContextLoaded_ReturnsContext;
    {Context out of range or unloaded -> priority 2 falls through to 3.}
    [Test] procedure NoSelection_ContextOutOfRange_FallsThroughToSingleView;
    [Test] procedure NoSelection_ContextNotLoaded_FallsThroughToSingleView;
    {Priority 3: vmSingle's current frame.}
    [Test] procedure SingleViewLoaded_NoSelectionNoContext_ReturnsCurrent;
    {Not in vmSingle -> priority 3 is skipped (the focused cell is no
     more "natural" than any other in a grid layout).}
    [Test] procedure NotSingleView_CurrentNotElevated;
    {Priority 4: cell 0 fallback.}
    [Test] procedure FallbackToCellZero_WhenLoaded;
    {Priority 5: nothing loaded -> -1.}
    [Test] procedure NothingLoaded_ReturnsMinusOne;
    [Test] procedure EmptyGrid_ReturnsMinusOne;
  end;

  [TestFixture]
  TTestEscClearSelection = class
  public
    {All three conditions (Quick View, enabled, a non-empty selection) must
     hold for the first Esc to clear instead of close.}
    [Test] procedure QuickViewEnabledWithSelection_True;
    {Lister mode never intercepts Esc, even with selection and toggle on.}
    [Test] procedure NotQuickView_False;
    [Test] procedure Disabled_False;
    {Nothing selected: Esc falls through to its normal close behaviour.}
    [Test] procedure NoSelection_False;
  end;

implementation

uses
  System.SysUtils,
  FrameSelectionPolicy;

type
  {Test-double IFrameViewQuery: holds canned arrays for loaded/selected
   and scalar fields for CellCount / CurrentFrameIndex / IsSingleView.
   Construction takes the cell count; SetLoaded / SetSelected populate
   per-cell state. All other tests touch the scalar fields directly.}
  TStubFrameViewQuery = class(TInterfacedObject, IFrameViewQuery)
  strict private
    FCellCount: Integer;
    FCurrentFrameIndex: Integer;
    FIsSingleView: Boolean;
    FLoaded: TArray<Boolean>;
    FSelected: TArray<Boolean>;
  public
    constructor Create(ACellCount: Integer);
    function CellCount: Integer;
    function CurrentFrameIndex: Integer;
    function CellIsLoaded(AIndex: Integer): Boolean;
    function CellSelected(AIndex: Integer): Boolean;
    function IsSingleView: Boolean;
    procedure SetLoaded(AIndex: Integer; AValue: Boolean);
    procedure SetSelected(AIndex: Integer; AValue: Boolean);
    procedure LoadAll;
    property CurrentFrameIndexValue: Integer read FCurrentFrameIndex write FCurrentFrameIndex;
    property IsSingleViewValue: Boolean read FIsSingleView write FIsSingleView;
  end;

constructor TStubFrameViewQuery.Create(ACellCount: Integer);
begin
  inherited Create;
  FCellCount := ACellCount;
  FCurrentFrameIndex := -1;
  SetLength(FLoaded, ACellCount);
  SetLength(FSelected, ACellCount);
end;

function TStubFrameViewQuery.CellCount: Integer;
begin
  Result := FCellCount;
end;

function TStubFrameViewQuery.CurrentFrameIndex: Integer;
begin
  Result := FCurrentFrameIndex;
end;

function TStubFrameViewQuery.CellIsLoaded(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= Length(FLoaded)) then
    Exit(False);
  Result := FLoaded[AIndex];
end;

function TStubFrameViewQuery.CellSelected(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= Length(FSelected)) then
    Exit(False);
  Result := FSelected[AIndex];
end;

function TStubFrameViewQuery.IsSingleView: Boolean;
begin
  Result := FIsSingleView;
end;

procedure TStubFrameViewQuery.SetLoaded(AIndex: Integer; AValue: Boolean);
begin
  FLoaded[AIndex] := AValue;
end;

procedure TStubFrameViewQuery.SetSelected(AIndex: Integer; AValue: Boolean);
begin
  FSelected[AIndex] := AValue;
end;

procedure TStubFrameViewQuery.LoadAll;
var
  I: Integer;
begin
  for I := 0 to High(FLoaded) do
    FLoaded[I] := True;
end;

{ TTestResolveFrameIndex }

procedure TTestResolveFrameIndex.EmptyGrid_ReturnsFalse;
var
  View: IFrameViewQuery;
  Idx: Integer;
begin
  View := TStubFrameViewQuery.Create(0);
  Assert.IsFalse(TFrameSelectionPolicy.ResolveFrameIndex(View, 0, Idx));
end;

procedure TTestResolveFrameIndex.ContextInRangeAndLoaded_ReturnsContext;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
  Idx: Integer;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := 1;

  Assert.IsTrue(TFrameSelectionPolicy.ResolveFrameIndex(View, 3, Idx));
  Assert.AreEqual<Integer>(3, Idx, 'Context cell must win when in range and loaded');
end;

procedure TTestResolveFrameIndex.ContextOutOfRange_FallsBackToCurrentFrame;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
  Idx: Integer;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := 2;

  Assert.IsTrue(TFrameSelectionPolicy.ResolveFrameIndex(View, 99, Idx));
  Assert.AreEqual<Integer>(2, Idx);
end;

procedure TTestResolveFrameIndex.BothOutOfRange_FallsBackToZero;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
  Idx: Integer;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := -1;

  Assert.IsTrue(TFrameSelectionPolicy.ResolveFrameIndex(View, -1, Idx));
  Assert.AreEqual<Integer>(0, Idx);
end;

procedure TTestResolveFrameIndex.PickedCellNotLoaded_ReturnsFalse;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
  Idx: Integer;
begin
  Stub := TStubFrameViewQuery.Create(3);
  View := Stub;
  Stub.CurrentFrameIndexValue := 1;
  {No cell is loaded -> the final CellIsLoaded check fails.}
  Assert.IsFalse(TFrameSelectionPolicy.ResolveFrameIndex(View, 0, Idx));
end;

procedure TTestResolveFrameIndex.ContextInRangeNotLoaded_DoesNotFallThrough;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
  Idx: Integer;
begin
  {Documents an important subtle: ResolveFrameIndex does not skip
   not-loaded cells when picking the index. It just settles on one and
   then asks "loaded?" at the end. So context-in-range-but-unloaded
   sticks at the context index and returns False — does not "fall
   through" to current frame as PickActionCell would.}
  Stub := TStubFrameViewQuery.Create(3);
  View := Stub;
  Stub.SetLoaded(1, True);
  Stub.CurrentFrameIndexValue := 1;

  Assert.IsFalse(TFrameSelectionPolicy.ResolveFrameIndex(View, 0, Idx),
    'Context in range overrides; if context cell is not loaded, returns False');
end;

{ TTestPickActionCell }

procedure TTestPickActionCell.SelectedLoadedCell_Wins;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.SetSelected(2, True);
  Stub.CurrentFrameIndexValue := 4;
  Stub.IsSingleViewValue := True;

  {Context says 3, but selection wins.}
  Assert.AreEqual<Integer>(2,
    TFrameSelectionPolicy.PickActionCell(View, 3),
    'Selection beats explicit right-click context');
end;

procedure TTestPickActionCell.MultipleSelected_FirstWins;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.SetSelected(1, True);
  Stub.SetSelected(3, True);
  Stub.SetSelected(4, True);

  Assert.AreEqual<Integer>(1, TFrameSelectionPolicy.PickActionCell(View, -1),
    'Multi-selection collapses deterministically to the first selected cell');
end;

procedure TTestPickActionCell.SelectedButNotLoaded_DoesNotWin;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.SetSelected(2, True); {selected but not loaded}
  Stub.SetLoaded(4, True);
  Stub.CurrentFrameIndexValue := 4;
  Stub.IsSingleViewValue := True;

  {Priority 1 falls through; context=-1 skips 2; vmSingle current=4 wins.}
  Assert.AreEqual<Integer>(4, TFrameSelectionPolicy.PickActionCell(View, -1));
end;

procedure TTestPickActionCell.NoSelection_ContextLoaded_ReturnsContext;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := 0;
  Stub.IsSingleViewValue := False;

  Assert.AreEqual<Integer>(3, TFrameSelectionPolicy.PickActionCell(View, 3));
end;

procedure TTestPickActionCell.NoSelection_ContextOutOfRange_FallsThroughToSingleView;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := 2;
  Stub.IsSingleViewValue := True;

  Assert.AreEqual<Integer>(2, TFrameSelectionPolicy.PickActionCell(View, 99));
end;

procedure TTestPickActionCell.NoSelection_ContextNotLoaded_FallsThroughToSingleView;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.SetLoaded(2, True);
  Stub.CurrentFrameIndexValue := 2;
  Stub.IsSingleViewValue := True;

  Assert.AreEqual<Integer>(2, TFrameSelectionPolicy.PickActionCell(View, 3));
end;

procedure TTestPickActionCell.SingleViewLoaded_NoSelectionNoContext_ReturnsCurrent;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := 4;
  Stub.IsSingleViewValue := True;

  Assert.AreEqual<Integer>(4, TFrameSelectionPolicy.PickActionCell(View, -1));
end;

procedure TTestPickActionCell.NotSingleView_CurrentNotElevated;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := 4;
  Stub.IsSingleViewValue := False;

  {Priority 3 skipped (not vmSingle); priority 4 fires with cell 0.}
  Assert.AreEqual<Integer>(0, TFrameSelectionPolicy.PickActionCell(View, -1),
    'CurrentFrameIndex is only elevated in vmSingle; otherwise falls to cell 0');
end;

procedure TTestPickActionCell.FallbackToCellZero_WhenLoaded;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.LoadAll;
  Stub.CurrentFrameIndexValue := -1;
  Stub.IsSingleViewValue := False;

  Assert.AreEqual<Integer>(0, TFrameSelectionPolicy.PickActionCell(View, -1));
end;

procedure TTestPickActionCell.NothingLoaded_ReturnsMinusOne;
var
  Stub: TStubFrameViewQuery;
  View: IFrameViewQuery;
begin
  Stub := TStubFrameViewQuery.Create(5);
  View := Stub;
  Stub.CurrentFrameIndexValue := 2;
  Stub.IsSingleViewValue := True;

  Assert.AreEqual<Integer>(-1, TFrameSelectionPolicy.PickActionCell(View, 3));
end;

procedure TTestPickActionCell.EmptyGrid_ReturnsMinusOne;
var
  View: IFrameViewQuery;
begin
  View := TStubFrameViewQuery.Create(0);
  Assert.AreEqual<Integer>(-1, TFrameSelectionPolicy.PickActionCell(View, 0));
end;

{ TTestEscClearSelection }

procedure TTestEscClearSelection.QuickViewEnabledWithSelection_True;
begin
  Assert.IsTrue(TFrameSelectionPolicy.ShouldEscClearSelection(True, True, 1));
end;

procedure TTestEscClearSelection.NotQuickView_False;
begin
  Assert.IsFalse(TFrameSelectionPolicy.ShouldEscClearSelection(False, True, 3));
end;

procedure TTestEscClearSelection.Disabled_False;
begin
  Assert.IsFalse(TFrameSelectionPolicy.ShouldEscClearSelection(True, False, 3));
end;

procedure TTestEscClearSelection.NoSelection_False;
begin
  Assert.IsFalse(TFrameSelectionPolicy.ShouldEscClearSelection(True, True, 0));
end;

end.
