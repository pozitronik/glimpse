{Shared cache key utilities: hashing, sharded directory paths, and
 invariant format settings used by both frame cache and probe cache.}
unit uCacheKey;

interface

uses
  System.SysUtils;

const
  SHARD_PREFIX_LEN = 2; {directory sharding depth: first N chars of the hash key}

var
  {Invariant format settings for deterministic key strings}
  InvFmt: TFormatSettings;

  {Computes an MD5 hash of AKeyString, returned as a lowercase hex string.}
function CacheHashKey(const AKeyString: string): string;

{Builds a sharded file path: <CacheDir>/<first N chars of key>/<key>.<ext>}
function ShardedKeyPath(const ACacheDir, AKey, AExt: string): string;

implementation

uses
  System.IOUtils, System.Hash;

function CacheHashKey(const AKeyString: string): string;
begin
  Result := THashMD5.GetHashString(AKeyString).ToLower;
end;

function ShardedKeyPath(const ACacheDir, AKey, AExt: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ACacheDir, Copy(AKey, 1, SHARD_PREFIX_LEN)), AKey + AExt);
end;

initialization

InvFmt := TFormatSettings.Invariant;

end.
