{Shared cache key utilities: hashing, sharded directory paths, and
 invariant format settings used by both frame cache and probe cache.}
unit uCacheKey;

interface

uses
  System.SysUtils;

const
  SHARD_PREFIX_LEN = 2;

  {Returned copy is read-only; mutating it does not affect later calls.}
function InvFmt: TFormatSettings;

{lowercased-path + '|' + size + '|' + mtime (yyyymmddhhnnsszzz). Used as
 the leading prefix of both frame and probe cache keys.}
function BuildFileIdentityKey(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime): string;

function CacheHashKey(const AKeyString: string): string;

{<CacheDir>/<first SHARD_PREFIX_LEN chars of key>/<key>.<ext>}
function ShardedKeyPath(const ACacheDir, AKey, AExt: string): string;

function BuildFrameCacheKeyString(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): string;

implementation

uses
  System.IOUtils, System.Hash;

var
  {Module-private to prevent importers from overwriting the decimal
   separator; access via InvFmt.}
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

function BuildFrameCacheKeyString(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime; ATimeOffset: Double; AMaxSide: Integer; AUseKeyframes: Boolean): string;
begin
  Result := BuildFileIdentityKey(AFilePath, AFileSize, AFileTime) + '|' + Format('%.3f', [ATimeOffset], GInvFmt);
  if AMaxSide > 0 then
    Result := Result + '|s' + IntToStr(AMaxSide);
  if AUseKeyframes then
    Result := Result + '|kf';
end;

initialization

GInvFmt := TFormatSettings.Invariant;

end.
