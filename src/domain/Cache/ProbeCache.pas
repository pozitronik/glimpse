{Persistent cache for TVideoInfo probe results, kept separate from the
 frame cache so clearing frames does not invalidate probes. Holds only
 cache policy: key derivation, the versioned name=value format,
 negative-result handling and the cache-then-probe convenience. Byte
 storage and source-file stat are injected, so the policy is testable
 without a real disk; ProbeCacheFactory composes the production storage.}
unit ProbeCache;

interface

uses
  VideoProbing, VideoInfo, CacheContracts;

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
    {Best-effort: storage-level failures are swallowed.}
    procedure Clear;
  end;

  {Storage and source-file stat are injected; ProbeCacheFactory composes
   the production TDiskCacheStorage + TFileSystemStat, tests pass fakes.}
  TProbeCache = class(TInterfacedObject, IProbeCache, IProbeCacheManager)
  strict private
    FStorage: ICacheStorage;
    FFileStat: IFileStat;
    {Returns '' when the source file cannot be stat'd. Its size and mtime
     are folded into the key so a changed source invalidates the entry.}
    function ProbeKey(const AFilePath: string): string;
  public
    constructor Create(const AStorage: ICacheStorage; const AFileStat: IFileStat);
    function TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
    procedure Put(const AFilePath: string; const AInfo: TVideoInfo);
    function TryGetOrProbe(const AFilePath: string; const AProber: IVideoProber): TVideoInfo;
    function GetTotalSize: Int64;
    procedure Clear;
  end;

implementation

uses
  System.SysUtils, System.Classes, CacheKey;

const
  {Identifies a Glimpse-written probe entry and its format revision; an
   entry lacking this marker is foreign or pre-versioning and rejected.}
  PROBE_FORMAT_KEY = 'GlimpseProbe';
  PROBE_FORMAT_VERSION = '1';

{TVideoInfo persistence: conversion to and from the probe entry's
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

{TProbeCache}

constructor TProbeCache.Create(const AStorage: ICacheStorage; const AFileStat: IFileStat);
begin
  inherited Create;
  FStorage := AStorage;
  FFileStat := AFileStat;
end;

function TProbeCache.ProbeKey(const AFilePath: string): string;
var
  FileSize: Int64;
  FileTime: TDateTime;
begin
  Result := '';
  if not FFileStat.TryStat(AFilePath, FileSize, FileTime) then
    Exit;
  Result := CacheHashKey(BuildFileIdentityKey(AFilePath, FileSize, FileTime));
end;

function TProbeCache.TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
var
  Key: string;
  Data: TBytes;
  Lines: TStringList;
begin
  Result := False;
  AInfo := Default(TVideoInfo);
  AInfo.Duration := -1;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Data := FStorage.Read(Key);
  if Length(Data) = 0 then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := TEncoding.UTF8.GetString(Data);
    {Reject a foreign or pre-versioning entry: without the marker its
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
  Entries: TArray<TCacheEntryInfo>;
  I: Integer;
begin
  Result := 0;
  Entries := FStorage.List;
  for I := 0 to High(Entries) do
    Result := Result + Entries[I].Size;
end;

procedure TProbeCache.Clear;
begin
  FStorage.Clear;
end;

procedure TProbeCache.Put(const AFilePath: string; const AInfo: TVideoInfo);
var
  Key: string;
  Lines: TStringList;
begin
  if not AInfo.IsValid then
    Exit;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Lines := TStringList.Create;
  try
    SerializeVideoInfo(Lines, AInfo);
    FStorage.Write(Key, TEncoding.UTF8.GetBytes(Lines.Text));
  finally
    Lines.Free;
  end;
end;

end.
