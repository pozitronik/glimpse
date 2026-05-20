{LRU eviction over ICacheStorage. Not thread-safe: caller owns the lock.}
unit LruEvictionPolicy;

interface

uses
  CacheStorage;

type
  {Cache-eviction strategy over ICacheStorage. Injected into TFrameCache
   so the cache can be tested with a substitute policy.}
  IEvictionPolicy = interface
    ['{9C4D7A21-3E8F-4B5A-A1D6-2F7E0C8B6534}']
    procedure Evict(const AStorage: ICacheStorage);
  end;

  TLruEvictionPolicy = class(TInterfacedObject, IEvictionPolicy)
  strict private
    FMaxSizeBytes: Int64;
  public
    constructor Create(AMaxSizeBytes: Int64);
    {Deletes oldest entries until total fits the budget. Best-effort:
     delete failures are silent and the loop continues — getting closer
     to budget beats aborting on the first stuck file.}
    procedure Evict(const AStorage: ICacheStorage);

    property MaxSizeBytes: Int64 read FMaxSizeBytes;
  end;

implementation

uses
  System.DateUtils, System.Generics.Collections, System.Generics.Defaults;

constructor TLruEvictionPolicy.Create(AMaxSizeBytes: Int64);
begin
  inherited Create;
  FMaxSizeBytes := AMaxSizeBytes;
end;

procedure TLruEvictionPolicy.Evict(const AStorage: ICacheStorage);
var
  Entries: TArray<TCacheEntryInfo>;
  Total: Int64;
  I: Integer;
begin
  if AStorage = nil then
    Exit;
  Entries := AStorage.List;
  Total := 0;
  for I := 0 to High(Entries) do
    Total := Total + Entries[I].Size;
  if Total <= FMaxSizeBytes then
    Exit;

  {CompareDateTime (not raw Double) ignores sub-millisecond NTFS access-
   time drift, matching the original TFrameCache.Evict behavior.}
  TArray.Sort<TCacheEntryInfo>(Entries,
    TComparer<TCacheEntryInfo>.Construct(
      function(const A, B: TCacheEntryInfo): Integer
      begin
        Result := CompareDateTime(A.AccessTime, B.AccessTime);
      end));

  for I := 0 to High(Entries) do
  begin
    if Total <= FMaxSizeBytes then
      Break;
    AStorage.Delete(Entries[I].Key);
    Total := Total - Entries[I].Size;
  end;
end;

end.
