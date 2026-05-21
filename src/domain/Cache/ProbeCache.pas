{Persistent disk cache for TVideoInfo. Always enabled; stored separately
 from the frame cache so clearing frames does not invalidate probes.}
unit ProbeCache;

interface

uses
  VideoProbing, VideoInfo;

type
  {Probe-result cache surface used by the WLX/WCX/thumbnail render paths.}
  IProbeCache = interface
    ['{3F6A9C12-4E7B-4D58-9A2C-1B8E5D7F0A63}']
    function TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
    {Only caches valid results.}
    procedure Put(const AFilePath: string; const AInfo: TVideoInfo);
    {Cache-then-probe convenience. On a cache miss delegates to AProber
     and persists a valid result.}
    function TryGetOrProbe(const AFilePath: string; const AProber: IVideoProber): TVideoInfo;
  end;

  {Separate from IProbeCache so probe callers do not see admin ops.}
  IProbeCacheManager = interface
    ['{7D2E4B81-5C39-4A6F-B0D1-6E3A8F92C415}']
    function GetTotalSize: Int64;
    {Best-effort: directory locks are swallowed.}
    procedure Clear;
  end;

  TProbeCache = class(TInterfacedObject, IProbeCache, IProbeCacheManager)
  strict private
    FCacheDir: string;
    class function BuildKeyString(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime): string; static;
    function ProbeKey(const AFilePath: string): string;
  public
    constructor Create(const ACacheDir: string);
    function TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
    procedure Put(const AFilePath: string; const AInfo: TVideoInfo);
    function TryGetOrProbe(const AFilePath: string; const AProber: IVideoProber): TVideoInfo;
    function GetTotalSize: Int64;
    procedure Clear;
  end;

{Fixed %TEMP%\Glimpse\probes directory backing the production probe cache.}
function DefaultProbeCacheDir: string;
{Production probe cache, rooted at DefaultProbeCacheDir.}
function CreateProbeCache: IProbeCache;
{Same cache through its admin facet, for size/clear callers.}
function CreateProbeCacheManager: IProbeCacheManager;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, CacheKey;

const
  MOVEFILE_REPLACE_EXISTING = 1;
  {Identifies a Glimpse-written probe file and its format revision; a
   file lacking this marker is foreign or pre-versioning and rejected.}
  PROBE_FORMAT_KEY = 'GlimpseProbe';
  PROBE_FORMAT_VERSION = '1';

function MoveFileEx(lpExistingFileName, lpNewFileName: PChar; dwFlags: Cardinal): LongBool; stdcall; external 'kernel32.dll' name 'MoveFileExW';

function DefaultProbeCacheDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'Glimpse' + PathDelim + 'probes');
end;

{TVideoInfo persistence: conversion to and from the probe file's
 name=value lines.}

procedure SerializeVideoInfo(ADest: TStrings; const AInfo: TVideoInfo);
begin
  ADest.Add(PROBE_FORMAT_KEY + '=' + PROBE_FORMAT_VERSION);
  ADest.Add('Duration=' + FloatToStr(AInfo.Duration, InvFmt));
  ADest.Add('Width=' + IntToStr(AInfo.Width));
  ADest.Add('Height=' + IntToStr(AInfo.Height));
  ADest.Add('SampleAspectN=' + IntToStr(AInfo.SampleAspectN));
  ADest.Add('SampleAspectD=' + IntToStr(AInfo.SampleAspectD));
  ADest.Add('DisplayWidth=' + IntToStr(AInfo.DisplayWidth));
  ADest.Add('DisplayHeight=' + IntToStr(AInfo.DisplayHeight));
  ADest.Add('VideoCodec=' + AInfo.VideoCodec);
  ADest.Add('VideoBitrateKbps=' + IntToStr(AInfo.VideoBitrateKbps));
  ADest.Add('Fps=' + FloatToStr(AInfo.Fps, InvFmt));
  ADest.Add('Bitrate=' + IntToStr(AInfo.Bitrate));
  ADest.Add('AudioCodec=' + AInfo.AudioCodec);
  ADest.Add('AudioSampleRate=' + IntToStr(AInfo.AudioSampleRate));
  ADest.Add('AudioChannels=' + AInfo.AudioChannels);
  ADest.Add('AudioBitrateKbps=' + IntToStr(AInfo.AudioBitrateKbps));
end;

function DeserializeVideoInfo(ASource: TStrings): TVideoInfo;
begin
  Result := Default(TVideoInfo);
  Result.Duration := StrToFloatDef(ASource.Values['Duration'], -1, InvFmt);
  Result.Width := StrToIntDef(ASource.Values['Width'], 0);
  Result.Height := StrToIntDef(ASource.Values['Height'], 0);
  Result.SampleAspectN := StrToIntDef(ASource.Values['SampleAspectN'], 1);
  Result.SampleAspectD := StrToIntDef(ASource.Values['SampleAspectD'], 1);
  Result.DisplayWidth := StrToIntDef(ASource.Values['DisplayWidth'], 0);
  Result.DisplayHeight := StrToIntDef(ASource.Values['DisplayHeight'], 0);
  {Pre-SAR cache entries lack explicit DisplayWidth/Height; rederive.}
  if (Result.DisplayWidth <= 0) or (Result.DisplayHeight <= 0) then
    Result.RecalcDisplayDimensions;
  Result.VideoCodec := ASource.Values['VideoCodec'];
  Result.VideoBitrateKbps := StrToIntDef(ASource.Values['VideoBitrateKbps'], 0);
  Result.Fps := StrToFloatDef(ASource.Values['Fps'], 0, InvFmt);
  Result.Bitrate := StrToIntDef(ASource.Values['Bitrate'], 0);
  Result.AudioCodec := ASource.Values['AudioCodec'];
  Result.AudioSampleRate := StrToIntDef(ASource.Values['AudioSampleRate'], 0);
  Result.AudioChannels := ASource.Values['AudioChannels'];
  Result.AudioBitrateKbps := StrToIntDef(ASource.Values['AudioBitrateKbps'], 0);
end;

{Atomic write via a sibling .tmp + MoveFileEx so a crash mid-write
 cannot leave a partial file that poisons future reads.}
procedure AtomicWriteTextFile(const APath: string; ALines: TStrings);
var
  TempPath: string;
begin
  TempPath := APath + '.' + TGUID.NewGuid.ToString + '.tmp';
  try
    TDirectory.CreateDirectory(ExtractFilePath(APath));
    ALines.SaveToFile(TempPath, TEncoding.UTF8);
    if not MoveFileEx(PChar(TempPath), PChar(APath), MOVEFILE_REPLACE_EXISTING) then
    begin
      try
        if TFile.Exists(TempPath) then
          TFile.Delete(TempPath);
      except
        {Best-effort temp cleanup}
      end;
    end;
  except
    try
      if TFile.Exists(TempPath) then
        TFile.Delete(TempPath);
    except
      {Best-effort temp cleanup}
    end;
  end;
end;

{TProbeCache}

constructor TProbeCache.Create(const ACacheDir: string);
begin
  inherited Create;
  FCacheDir := ACacheDir;
end;

class function TProbeCache.BuildKeyString(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime): string;
begin
  Result := BuildFileIdentityKey(AFilePath, AFileSize, AFileTime);
end;

function TProbeCache.ProbeKey(const AFilePath: string): string;
var
  FileSize: Int64;
  FileTime: TDateTime;
begin
  Result := '';
  try
    if not TFile.Exists(AFilePath) then
      Exit;
    FileSize := TFile.GetSize(AFilePath);
    FileTime := TFile.GetLastWriteTime(AFilePath);
    Result := CacheHashKey(BuildKeyString(AFilePath, FileSize, FileTime));
  except
    {File inaccessible}
  end;
end;

function TProbeCache.TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
var
  Key, Path: string;
  Lines: TStringList;
begin
  Result := False;
  AInfo := Default (TVideoInfo);
  AInfo.Duration := -1;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Path := ShardedKeyPath(FCacheDir, Key, '.probe');
  if not TFile.Exists(Path) then
    Exit;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Path, TEncoding.UTF8);
    except
      Exit;
    end;
    {Reject a foreign or pre-versioning file: without the marker its
     name=value lines cannot be trusted as a real probe result.}
    if Lines.Values[PROBE_FORMAT_KEY] <> PROBE_FORMAT_VERSION then
      Exit;
    AInfo := DeserializeVideoInfo(Lines);
    Result := AInfo.IsValid;
  finally
    Lines.Free;
  end;
end;

function TProbeCache.TryGetOrProbe(const AFilePath: string; const AProber: IVideoProber): TVideoInfo;
begin
  if TryGet(AFilePath, Result) then
    Exit;
  Result := AProber.ProbeVideo(AFilePath);
  Put(AFilePath, Result);
end;

function TProbeCache.GetTotalSize: Int64;
var
  Files: TArray<string>;
  F: string;
begin
  Result := 0;
  if not TDirectory.Exists(FCacheDir) then
    Exit;
  try
    Files := TDirectory.GetFiles(FCacheDir, '*.probe', TSearchOption.soAllDirectories);
  except
    Exit;
  end;
  for F in Files do
    try
      Result := Result + TFile.GetSize(F);
    except
      {File vanished mid-walk; skip}
    end;
end;

procedure TProbeCache.Clear;
begin
  try
    if TDirectory.Exists(FCacheDir) then
      TDirectory.Delete(FCacheDir, True);
    TDirectory.CreateDirectory(FCacheDir);
  except
    {Best-effort: directory may be locked}
  end;
end;

procedure TProbeCache.Put(const AFilePath: string; const AInfo: TVideoInfo);
var
  Key, Path: string;
  Lines: TStringList;
begin
  if not AInfo.IsValid then
    Exit;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Path := ShardedKeyPath(FCacheDir, Key, '.probe');

  Lines := TStringList.Create;
  try
    SerializeVideoInfo(Lines, AInfo);
    AtomicWriteTextFile(Path, Lines);
  finally
    Lines.Free;
  end;
end;

function CreateProbeCache: IProbeCache;
begin
  Result := TProbeCache.Create(DefaultProbeCacheDir);
end;

function CreateProbeCacheManager: IProbeCacheManager;
begin
  Result := TProbeCache.Create(DefaultProbeCacheDir);
end;

end.
