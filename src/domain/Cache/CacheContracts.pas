{Domain-owned cache collaborator abstractions. TFrameCache (domain Cache
 unit) depends on these; the infrastructure concretes TDiskCacheStorage,
 TFileSystemStat (CacheStorage) and TLruEvictionPolicy (LruEvictionPolicy)
 implement them, so the dependency points inward.}
unit CacheContracts;

interface

uses
  System.SysUtils;

type
  TCacheEntryInfo = record
    Key: string;
    Size: Int64;
    AccessTime: TDateTime;
  end;

  {Read returns empty bytes on miss or failure (indistinguishable by
   design). Write is atomic — readers see prior or new bytes, never
   torn. Delete/Clear are best-effort.}
  ICacheStorage = interface
    ['{C7A4F1E8-5B2D-4E3A-9F6C-1D8E2A5B7C9F}']
    function Read(const AKey: string): TBytes;
    procedure Write(const AKey: string; const AData: TBytes);
    procedure Delete(const AKey: string);
    procedure Clear;
    procedure Touch(const AKey: string);
    function List: TArray<TCacheEntryInfo>;
  end;

  {Source-file identity for cache-key derivation. The production
   implementation does the filesystem stat; a stub lets the frame cache
   be tested without a real source file on disk.}
  IFileStat = interface
    ['{8BB1203C-22F5-4CDF-9163-46CC76524D76}']
    {False when the file does not exist or cannot be stat'd.}
    function TryStat(const APath: string; out ASize: Int64; out AModified: TDateTime): Boolean;
  end;

  {Cache-eviction strategy over ICacheStorage. Injected into TFrameCache
   so the cache can be tested with a substitute policy.}
  IEvictionPolicy = interface
    ['{9C4D7A21-3E8F-4B5A-A1D6-2F7E0C8B6534}']
    procedure Evict(const AStorage: ICacheStorage);
  end;

implementation

end.
