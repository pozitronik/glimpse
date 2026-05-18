{Unit tests for uCommandDescriptors lookup helpers.

 Pure data tests: no TPluginForm machinery. Each test constructs a small
 TCommandTable in-place with no-op executor closures and exercises one
 lookup case (hit, miss, paNone filter, empty table). Goal is to pin the
 helper contracts that DispatchCommand / UpdateToolbarButtons /
 OnContextMenuPopup / ExecuteHotkey all depend on.}
unit TestCommandDescriptors;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCommandDescriptors = class
  public
    [Test] procedure TestFindByTagReturnsTrueWhenPresent;
    [Test] procedure TestFindByTagReturnsFalseWhenAbsent;
    [Test] procedure TestFindByActionSkipsPaNone;
    [Test] procedure TestFindByActionReturnsTrueWhenPresent;
    [Test] procedure TestFindByActionReturnsFalseWhenAbsent;
    [Test] procedure TestEmptyTableLookups;
  end;

implementation

uses
  System.SysUtils, uHotkeys, uCommandDescriptors;

{Helper: builds a 3-row table with no-op executors and distinct tags +
 actions. Lets each test name the slot it's exercising without rebuilding
 the same scaffolding inline.}
function MakeSampleTable: TCommandTable;
begin
  SetLength(Result, 3);
  Result[0].Tag := 1001;
  Result[0].ActionEnum := paSaveFrame;
  Result[0].EnabledPolicy := epRequiresExtract;
  Result[0].Executor := procedure begin end;
  Result[1].Tag := 1002;
  Result[1].ActionEnum := paCopyFrame;
  Result[1].EnabledPolicy := epRequiresExtract;
  Result[1].Executor := procedure begin end;
  Result[2].Tag := 1003;
  {DeselectAll's row: assigned tag but ActionEnum=paNone since the action
   has no hotkey. FindByAction must not return this row for a paNone
   query — otherwise unbound keystrokes would silently invoke DeselectAll.}
  Result[2].ActionEnum := paNone;
  Result[2].EnabledPolicy := epRequiresSelection;
  Result[2].Executor := procedure begin end;
end;

procedure TTestCommandDescriptors.TestFindByTagReturnsTrueWhenPresent;
var
  Tbl: TCommandTable;
  Desc: TCommandDescriptor;
begin
  Tbl := MakeSampleTable;
  Assert.IsTrue(FindCommandByTag(Tbl, 1002, Desc), 'lookup should hit row 1');
  Assert.AreEqual(Cardinal(1002), Desc.Tag);
  Assert.AreEqual(Ord(paCopyFrame), Ord(Desc.ActionEnum));
  Assert.AreEqual(Ord(epRequiresExtract), Ord(Desc.EnabledPolicy));
end;

procedure TTestCommandDescriptors.TestFindByTagReturnsFalseWhenAbsent;
var
  Tbl: TCommandTable;
  Desc: TCommandDescriptor;
begin
  Tbl := MakeSampleTable;
  Assert.IsFalse(FindCommandByTag(Tbl, 9999, Desc), 'unknown tag must miss');
  {Out parameter must be zero-initialised on miss so callers can't read
   stale data from a previous successful lookup.}
  Assert.AreEqual(Cardinal(0), Desc.Tag);
end;

procedure TTestCommandDescriptors.TestFindByActionSkipsPaNone;
var
  Tbl: TCommandTable;
  Desc: TCommandDescriptor;
begin
  Tbl := MakeSampleTable;
  {Sample table row 2 has ActionEnum=paNone. A paNone lookup must NOT
   match it — see the FindCommandByAction docstring.}
  Assert.IsFalse(FindCommandByAction(Tbl, paNone, Desc),
    'paNone lookup must not match descriptors with ActionEnum=paNone');
end;

procedure TTestCommandDescriptors.TestFindByActionReturnsTrueWhenPresent;
var
  Tbl: TCommandTable;
  Desc: TCommandDescriptor;
begin
  Tbl := MakeSampleTable;
  Assert.IsTrue(FindCommandByAction(Tbl, paCopyFrame, Desc));
  Assert.AreEqual(Cardinal(1002), Desc.Tag);
  Assert.AreEqual(Ord(paCopyFrame), Ord(Desc.ActionEnum));
end;

procedure TTestCommandDescriptors.TestFindByActionReturnsFalseWhenAbsent;
var
  Tbl: TCommandTable;
  Desc: TCommandDescriptor;
begin
  Tbl := MakeSampleTable;
  {paShuffleExtraction is not in the sample table.}
  Assert.IsFalse(FindCommandByAction(Tbl, paShuffleExtraction, Desc));
  Assert.AreEqual(Cardinal(0), Desc.Tag);
end;

procedure TTestCommandDescriptors.TestEmptyTableLookups;
var
  Tbl: TCommandTable;
  Desc: TCommandDescriptor;
begin
  SetLength(Tbl, 0);
  Assert.IsFalse(FindCommandByTag(Tbl, 1, Desc), 'empty table must miss every tag');
  Assert.IsFalse(FindCommandByAction(Tbl, paSaveFrame, Desc),
    'empty table must miss every action');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCommandDescriptors);

end.
