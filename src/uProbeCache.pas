{ Persistent disk cache for video probe results (TVideoInfo).
  Eliminates the 0.5-2s ffmpeg probe on re-opens by reading cached metadata
  from a small text file instead of spawning a subprocess.
  Stored separately from the frame cache so clearing frames does not
  invalidate probe data. Always enabled, no user-facing toggle. }
unit uProbeCache;

interface

uses
  uFFmpegExe;

type
  TProbeCache = class
  strict private
    FCacheDir: string;
    class function BuildKeyString(const AFilePath: string;
      AFileSize: Int64; AFileTime: TDateTime): string; static;
    class function HashKey(const AKeyString: string): string; static;
    function KeyToPath(const AKey: string): string;
    function ProbeKey(const AFilePath: string): string;
  public
    constructor Create(const ACacheDir: string);
    { Returns True and populates AInfo if a valid cached probe exists for AFilePath.
      Returns False on cache miss (file not cached, stale, or unreadable). }
    function TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
    { Stores a successful probe result for AFilePath. Only caches valid results. }
    procedure Put(const AFilePath: string; const AInfo: TVideoInfo);
  end;

{ Default probe cache directory, separate from the frame cache. }
function DefaultProbeCacheDir: string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Hash;

const
  SHARD_PREFIX_LEN = 2;

var
  InvFmt: TFormatSettings;

function DefaultProbeCacheDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'Glimpse' + PathDelim + 'probes');
end;

{ TProbeCache }

constructor TProbeCache.Create(const ACacheDir: string);
begin
  inherited Create;
  FCacheDir := ACacheDir;
end;

class function TProbeCache.BuildKeyString(const AFilePath: string;
  AFileSize: Int64; AFileTime: TDateTime): string;
begin
  Result := AnsiLowerCase(AFilePath) + '|' +
    IntToStr(AFileSize) + '|' +
    FormatDateTime('yyyymmddhhnnsszzz', AFileTime);
end;

class function TProbeCache.HashKey(const AKeyString: string): string;
begin
  Result := THashMD5.GetHashString(AKeyString).ToLower;
end;

function TProbeCache.KeyToPath(const AKey: string): string;
begin
  Result := TPath.Combine(
    TPath.Combine(FCacheDir, Copy(AKey, 1, SHARD_PREFIX_LEN)),
    AKey + '.probe');
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
    Result := HashKey(BuildKeyString(AFilePath, FileSize, FileTime));
  except
    { File inaccessible }
  end;
end;

function TProbeCache.TryGet(const AFilePath: string;
  out AInfo: TVideoInfo): Boolean;
var
  Key, Path: string;
  Lines: TStringList;
begin
  Result := False;
  AInfo := Default(TVideoInfo);
  AInfo.Duration := -1;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Path := KeyToPath(Key);
  if not TFile.Exists(Path) then
    Exit;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Path, TEncoding.UTF8);
    except
      Exit;
    end;
    AInfo.Duration := StrToFloatDef(Lines.Values['Duration'], -1, InvFmt);
    AInfo.Width := StrToIntDef(Lines.Values['Width'], 0);
    AInfo.Height := StrToIntDef(Lines.Values['Height'], 0);
    AInfo.VideoCodec := Lines.Values['VideoCodec'];
    AInfo.VideoBitrateKbps := StrToIntDef(Lines.Values['VideoBitrateKbps'], 0);
    AInfo.Fps := StrToFloatDef(Lines.Values['Fps'], 0, InvFmt);
    AInfo.Bitrate := StrToIntDef(Lines.Values['Bitrate'], 0);
    AInfo.AudioCodec := Lines.Values['AudioCodec'];
    AInfo.AudioSampleRate := StrToIntDef(Lines.Values['AudioSampleRate'], 0);
    AInfo.AudioChannels := Lines.Values['AudioChannels'];
    AInfo.AudioBitrateKbps := StrToIntDef(Lines.Values['AudioBitrateKbps'], 0);
    AInfo.IsValid := AInfo.Duration > 0;
    Result := AInfo.IsValid;
  finally
    Lines.Free;
  end;
end;

procedure TProbeCache.Put(const AFilePath: string; const AInfo: TVideoInfo);
var
  Key, Path, Dir: string;
  Lines: TStringList;
begin
  if not AInfo.IsValid then
    Exit;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Path := KeyToPath(Key);
  Dir := ExtractFilePath(Path);

  Lines := TStringList.Create;
  try
    Lines.Add('Duration=' + FloatToStr(AInfo.Duration, InvFmt));
    Lines.Add('Width=' + IntToStr(AInfo.Width));
    Lines.Add('Height=' + IntToStr(AInfo.Height));
    Lines.Add('VideoCodec=' + AInfo.VideoCodec);
    Lines.Add('VideoBitrateKbps=' + IntToStr(AInfo.VideoBitrateKbps));
    Lines.Add('Fps=' + FloatToStr(AInfo.Fps, InvFmt));
    Lines.Add('Bitrate=' + IntToStr(AInfo.Bitrate));
    Lines.Add('AudioCodec=' + AInfo.AudioCodec);
    Lines.Add('AudioSampleRate=' + IntToStr(AInfo.AudioSampleRate));
    Lines.Add('AudioChannels=' + AInfo.AudioChannels);
    Lines.Add('AudioBitrateKbps=' + IntToStr(AInfo.AudioBitrateKbps));
    try
      TDirectory.CreateDirectory(Dir);
      Lines.SaveToFile(Path, TEncoding.UTF8);
    except
      { Write failure is non-fatal; next open will just probe again }
    end;
  finally
    Lines.Free;
  end;
end;

initialization
  InvFmt := TFormatSettings.Invariant;

end.
