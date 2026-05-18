{LRU eviction policy over an ICacheStorage.

 Pure policy class: holds a max-size budget, asks storage to enumerate
 its entries, sorts by AccessTime ascending, and deletes oldest entries
 until the total size is within budget. Makes no thread-safety claim;
 the caller (TFrameCache) acquires its own lock around Evict so that
 concurrent Writes can't add entries mid-scan.

 Kept separate from TDiskCacheStorage so a future FIFO or size-based
 policy can be slotted in without touching disk code, and so the
 algorithm can be tested in isolation against a TMemoryCacheStorage
 fake — no temp files, no NTFS access-time quirks.}
unit uLruEvictionPolicy;

interface

uses
  uCacheStorage;

type
  TLruEvictionPolicy = class
  strict private
    FMaxSizeBytes: Int64;
  public
    constructor Create(AMaxSizeBytes: Int64);
    {Walks AStorage.List, sums sizes, and deletes oldest-access entries
     until the total fits within the budget. A no-op when total <= budget.
     Deletion failures inside AStorage.Delete are silent (best-effort)
     and the policy keeps trying further entries — getting closer to
     budget is strictly better than aborting on the first stuck file.}
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

  {Sort by access time ascending (oldest first). TArray.Sort would be
   more compact but the array is local and we want CompareDateTime
   semantics rather than raw Double comparison on TDateTime — small
   sub-millisecond drifts in NTFS access time are ignored by
   CompareDateTime, matching the original TFrameCache.Evict behavior.}
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
