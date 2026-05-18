unit TestLruEvictionPolicy;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLruEvictionPolicy = class
  public
    [Test] procedure EmptyStorage_DoesNothing;
    [Test] procedure UnderBudget_EvictsNothing;
    [Test] procedure ExactlyAtBudget_EvictsNothing;
    [Test] procedure OverBudget_EvictsOldestFirst;
    [Test] procedure EvictsUntilWithinBudget_StopsAfterSufficientReclaim;
    [Test] procedure ZeroBudget_EvictsEverything;
    [Test] procedure DeleteFailureDoesNotAbortPolicy;
    [Test] procedure SortStabilityForEqualAccessTimes;
    [Test] procedure NilStorage_DoesNothing;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uCacheStorage, uLruEvictionPolicy;

type
  {Test-only in-memory ICacheStorage. Lets the policy be exercised
   without touching disk. Test methods drive entry state directly via
   AddEntry / FailNextDelete — the policy only sees the ICacheStorage
   surface.}
  TMemoryCacheStorage = class(TInterfacedObject, ICacheStorage)
  strict private
    FEntries: TDictionary<string, TCacheEntryInfo>;
    FFailNextDelete: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    {Test seam: insert an entry with explicit size + access timestamp.}
    procedure AddEntry(const AKey: string; ASize: Int64; AAccessTime: TDateTime);
    {Test seam: causes the next Delete call to silently no-op,
     simulating an OS-level deletion failure.}
    procedure FailNextDelete;
    function HasEntry(const AKey: string): Boolean;
    function EntryCount: Integer;

    {ICacheStorage}
    function Read(const AKey: string): TBytes;
    procedure Write(const AKey: string; const AData: TBytes);
    procedure Delete(const AKey: string);
    procedure Clear;
    procedure Touch(const AKey: string);
    function List: TArray<TCacheEntryInfo>;
  end;

{TMemoryCacheStorage}

constructor TMemoryCacheStorage.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TCacheEntryInfo>.Create;
end;

destructor TMemoryCacheStorage.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TMemoryCacheStorage.AddEntry(const AKey: string; ASize: Int64; AAccessTime: TDateTime);
var
  Info: TCacheEntryInfo;
begin
  Info.Key := AKey;
  Info.Size := ASize;
  Info.AccessTime := AAccessTime;
  FEntries.AddOrSetValue(AKey, Info);
end;

procedure TMemoryCacheStorage.FailNextDelete;
begin
  FFailNextDelete := True;
end;

function TMemoryCacheStorage.HasEntry(const AKey: string): Boolean;
begin
  Result := FEntries.ContainsKey(AKey);
end;

function TMemoryCacheStorage.EntryCount: Integer;
begin
  Result := FEntries.Count;
end;

function TMemoryCacheStorage.Read(const AKey: string): TBytes;
begin
  Result := nil;
end;

procedure TMemoryCacheStorage.Write(const AKey: string; const AData: TBytes);
begin
  {Not exercised by the LRU policy tests}
end;

procedure TMemoryCacheStorage.Delete(const AKey: string);
begin
  if FFailNextDelete then
  begin
    FFailNextDelete := False;
    Exit;
  end;
  FEntries.Remove(AKey);
end;

procedure TMemoryCacheStorage.Clear;
begin
  FEntries.Clear;
end;

procedure TMemoryCacheStorage.Touch(const AKey: string);
var
  Info: TCacheEntryInfo;
begin
  if FEntries.TryGetValue(AKey, Info) then
  begin
    Info.AccessTime := Now;
    FEntries[AKey] := Info;
  end;
end;

function TMemoryCacheStorage.List: TArray<TCacheEntryInfo>;
var
  I: Integer;
  Info: TCacheEntryInfo;
begin
  SetLength(Result, FEntries.Count);
  I := 0;
  for Info in FEntries.Values do
  begin
    Result[I] := Info;
    Inc(I);
  end;
end;

{TTestLruEvictionPolicy}

procedure TTestLruEvictionPolicy.EmptyStorage_DoesNothing;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Policy := TLruEvictionPolicy.Create(1024);
  try
    Policy.Evict(Iface);
    Assert.AreEqual(0, Storage.EntryCount, 'Empty storage stays empty');
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.UnderBudget_EvictsNothing;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Storage.AddEntry('a', 100, EncodeDate(2020, 1, 1));
  Storage.AddEntry('b', 200, EncodeDate(2020, 1, 2));
  Policy := TLruEvictionPolicy.Create(1000);
  try
    Policy.Evict(Iface);
    Assert.AreEqual(2, Storage.EntryCount, 'No entry crosses the budget; nothing to evict');
    Assert.IsTrue(Storage.HasEntry('a'));
    Assert.IsTrue(Storage.HasEntry('b'));
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.ExactlyAtBudget_EvictsNothing;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Storage.AddEntry('a', 400, EncodeDate(2020, 1, 1));
  Storage.AddEntry('b', 600, EncodeDate(2020, 1, 2));
  Policy := TLruEvictionPolicy.Create(1000);
  try
    Policy.Evict(Iface);
    Assert.AreEqual(2, Storage.EntryCount, 'Total == budget is not over-budget');
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.OverBudget_EvictsOldestFirst;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Storage.AddEntry('oldest', 400, EncodeDate(2020, 1, 1));
  Storage.AddEntry('middle', 400, EncodeDate(2020, 6, 1));
  Storage.AddEntry('newest', 400, EncodeDate(2021, 1, 1));
  Policy := TLruEvictionPolicy.Create(1000);  {1200 total, 200 over budget}
  try
    Policy.Evict(Iface);
    Assert.AreEqual(2, Storage.EntryCount, 'One eviction was enough to drop under budget');
    Assert.IsFalse(Storage.HasEntry('oldest'), 'Oldest goes first');
    Assert.IsTrue(Storage.HasEntry('middle'), 'Middle survives');
    Assert.IsTrue(Storage.HasEntry('newest'), 'Newest survives');
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.EvictsUntilWithinBudget_StopsAfterSufficientReclaim;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Storage.AddEntry('a', 300, EncodeDate(2020, 1, 1));
  Storage.AddEntry('b', 300, EncodeDate(2020, 2, 1));
  Storage.AddEntry('c', 300, EncodeDate(2020, 3, 1));
  Storage.AddEntry('d', 300, EncodeDate(2020, 4, 1));  {1200 total}
  Policy := TLruEvictionPolicy.Create(500);  {Need to evict at least 700 -> 3 entries removed}
  try
    Policy.Evict(Iface);
    Assert.AreEqual(1, Storage.EntryCount, 'Three oldest evicted, newest survives');
    Assert.IsTrue(Storage.HasEntry('d'), 'Newest is the survivor');
    Assert.IsFalse(Storage.HasEntry('a'));
    Assert.IsFalse(Storage.HasEntry('b'));
    Assert.IsFalse(Storage.HasEntry('c'));
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.ZeroBudget_EvictsEverything;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Storage.AddEntry('a', 100, EncodeDate(2020, 1, 1));
  Storage.AddEntry('b', 100, EncodeDate(2020, 2, 1));
  Storage.AddEntry('c', 100, EncodeDate(2020, 3, 1));
  Policy := TLruEvictionPolicy.Create(0);
  try
    Policy.Evict(Iface);
    Assert.AreEqual(0, Storage.EntryCount, 'Zero budget reclaims everything');
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.DeleteFailureDoesNotAbortPolicy;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  Storage.AddEntry('oldest', 400, EncodeDate(2020, 1, 1));
  Storage.AddEntry('middle', 400, EncodeDate(2020, 2, 1));
  Storage.AddEntry('newest', 400, EncodeDate(2020, 3, 1));  {1200 total, budget 700}
  Storage.FailNextDelete;  {oldest's Delete will silently no-op}
  Policy := TLruEvictionPolicy.Create(700);
  try
    Policy.Evict(Iface);
    {Policy deducted oldest's size from running total and moved on to middle,
     so middle is also deleted. Result: oldest survives (delete failed),
     middle is gone, newest survives.}
    Assert.IsTrue(Storage.HasEntry('oldest'), 'Failed delete leaves the entry behind');
    Assert.IsFalse(Storage.HasEntry('middle'), 'Policy continues to next-oldest after a failure');
    Assert.IsTrue(Storage.HasEntry('newest'));
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.SortStabilityForEqualAccessTimes;
var
  Storage: TMemoryCacheStorage;
  Iface: ICacheStorage;
  Policy: TLruEvictionPolicy;
  RemainingCount: Integer;
begin
  Storage := TMemoryCacheStorage.Create;
  Iface := Storage;
  {Three entries with the same access time. The sort treats them as
   ordering-indistinguishable; the policy must still evict enough to
   meet budget and must not crash.}
  Storage.AddEntry('a', 400, EncodeDate(2020, 1, 1));
  Storage.AddEntry('b', 400, EncodeDate(2020, 1, 1));
  Storage.AddEntry('c', 400, EncodeDate(2020, 1, 1));  {1200 total, budget 500 -> evict 2}
  Policy := TLruEvictionPolicy.Create(500);
  try
    Policy.Evict(Iface);
    RemainingCount := Storage.EntryCount;
    Assert.AreEqual(1, RemainingCount, 'Two entries evicted; the survivor is undefined but the count is deterministic');
  finally
    Policy.Free;
  end;
end;

procedure TTestLruEvictionPolicy.NilStorage_DoesNothing;
var
  Policy: TLruEvictionPolicy;
begin
  Policy := TLruEvictionPolicy.Create(1000);
  try
    Policy.Evict(nil);
    {Reaching this line without raising is the assertion. A defensive
     nil-check in Evict guards against a future code path where the
     storage hasn't been wired up yet.}
    Assert.Pass('Nil storage is silently accepted');
  finally
    Policy.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLruEvictionPolicy);

end.
