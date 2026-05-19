{Tests for TArchiveHandle's cursor management. Each test pins one
 cursor invariant; populating Listing uses a no-op entry stub so the
 assertions stay focused on the cursor, not on extraction (covered
 in TestWcxEntryExtractors).}
unit TestWcxArchiveHandle;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxArchiveHandle = class
  public
    [Test] procedure TestEntryCountEmptyListingReturnsZero;
    [Test] procedure TestEntryCountPopulatedListingReturnsLength;
    [Test] procedure TestIsExhaustedAfterCreationTrueForEmptyListing;
    [Test] procedure TestIsExhaustedPopulatedListingFalseAtStart;
    [Test] procedure TestAdvanceCursorWalksToExhaustion;
    [Test] procedure TestResetCursorRestartsAtZero;
    [Test] procedure TestCurrentEntryReturnsEntryUnderCursor;
  end;

implementation

uses
  System.SysUtils,
  WcxEntryExtractors, WcxArchiveHandle;

type
  {Minimal IWcxEntryExtractor stub for cursor tests. Extract and
   ReportedSize are not exercised here — the cursor invariants are
   indifferent to entry behaviour.}
  TStubEntry = class(TInterfacedObject, IWcxEntryExtractor)
  strict private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    function GetFileName: string;
    function ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
    function Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
  end;

constructor TStubEntry.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

function TStubEntry.GetFileName: string;
begin
  Result := FFileName;
end;

function TStubEntry.ReportedSize(const AContext: IWcxExtractionContext; AListingIndex: Integer): Int64;
begin
  Result := 0;
end;

function TStubEntry.Extract(const AContext: IWcxExtractionContext; const ADestPath, ADestName: string): Integer;
begin
  Result := 0;
end;

{Builds a Listing array of the requested length. Entries are stub
 instances; they own themselves via interface refcounting (the array
 holds the strong reference).}
function MakeListing(ACount: Integer): TWcxEntryExtractorArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
    Result[I] := TStubEntry.Create(Format('entry%d', [I]));
end;

procedure TTestWcxArchiveHandle.TestEntryCountEmptyListingReturnsZero;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle.Create;
  try
    Assert.AreEqual(0, H.EntryCount);
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveHandle.TestEntryCountPopulatedListingReturnsLength;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle.Create;
  try
    H.Listing := MakeListing(3);
    Assert.AreEqual(3, H.EntryCount);
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveHandle.TestIsExhaustedAfterCreationTrueForEmptyListing;
var
  H: TArchiveHandle;
begin
  {Empty listing: cursor at 0, EntryCount=0, so 0 >= 0 is True.
   ReadHeader/ReadHeaderExW rely on this to bail out immediately when
   the archive has no entries.}
  H := TArchiveHandle.Create;
  try
    Assert.IsTrue(H.IsExhausted);
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveHandle.TestIsExhaustedPopulatedListingFalseAtStart;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle.Create;
  try
    H.Listing := MakeListing(2);
    Assert.IsFalse(H.IsExhausted);
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveHandle.TestAdvanceCursorWalksToExhaustion;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle.Create;
  try
    H.Listing := MakeListing(2);
    H.AdvanceCursor;
    Assert.IsFalse(H.IsExhausted, 'after one advance, cursor at 1, still inside 2-entry listing');
    H.AdvanceCursor;
    Assert.IsTrue(H.IsExhausted, 'after second advance, cursor at 2, equal to EntryCount');
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveHandle.TestResetCursorRestartsAtZero;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle.Create;
  try
    H.Listing := MakeListing(2);
    H.AdvanceCursor;
    H.ResetCursor;
    Assert.AreEqual(0, H.CurrentEntryIndex);
    Assert.IsFalse(H.IsExhausted);
  finally
    H.Free;
  end;
end;

procedure TTestWcxArchiveHandle.TestCurrentEntryReturnsEntryUnderCursor;
var
  H: TArchiveHandle;
begin
  H := TArchiveHandle.Create;
  try
    H.Listing := MakeListing(2);
    Assert.AreEqual('entry0', H.CurrentEntry.FileName);
    H.AdvanceCursor;
    Assert.AreEqual('entry1', H.CurrentEntry.FileName);
  finally
    H.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxArchiveHandle);

end.
