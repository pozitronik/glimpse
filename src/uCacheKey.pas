{Shared cache key utilities: hashing, sharded directory paths, and
 invariant format settings used by both frame cache and probe cache.}
unit uCacheKey;

interface

uses
  System.SysUtils;

const
  SHARD_PREFIX_LEN = 2; {directory sharding depth: first N chars of the hash key}

  {Returns the invariant format settings used for deterministic key strings
   (decimal separator '.', no thousand grouping). Callers must treat the
   result as read-only; mutating any returned copy has no effect on the
   next call. Earlier this was a public mutable global, so any unit could
   silently rewrite the decimal separator and break key generation
   process-wide.}
function InvFmt: TFormatSettings;

{Composes the "file identity" portion of a cache key string:
 lowercased-path + '|' + size + '|' + mtime (formatted as
 yyyymmddhhnnsszzz). Used by both TFrameCache and TProbeCache as the
 leading prefix of their respective key strings; subclass-specific
 fields (time offset, max side, etc.) get appended by the caller.
 Centralising the format here keeps the two caches' identity rules
 in lockstep — a change to how mtime is encoded only happens once.}
function BuildFileIdentityKey(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime): string;

{Computes an MD5 hash of AKeyString, returned as a lowercase hex string.}
function CacheHashKey(const AKeyString: string): string;

{Builds a sharded file path: <CacheDir>/<first N chars of key>/<key>.<ext>}
function ShardedKeyPath(const ACacheDir, AKey, AExt: string): string;

implementation

uses
  System.IOUtils, System.Hash;

var
  {Module-private: initialised once at unit load (see initialization). Not
   exposed in the interface because the previous mutable-global form let
   any importer overwrite the decimal separator.}
  GInvFmt: TFormatSettings;

function InvFmt: TFormatSettings;
begin
  Result := GInvFmt;
end;

function BuildFileIdentityKey(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime): string;
begin
  Result := AnsiLowerCase(AFilePath) + '|' + IntToStr(AFileSize) + '|' +
    FormatDateTime('yyyymmddhhnnsszzz', AFileTime);
end;

function CacheHashKey(const AKeyString: string): string;
begin
  Result := THashMD5.GetHashString(AKeyString);
end;

function ShardedKeyPath(const ACacheDir, AKey, AExt: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ACacheDir, Copy(AKey, 1, SHARD_PREFIX_LEN)), AKey + AExt);
end;

initialization

GInvFmt := TFormatSettings.Invariant;

end.
