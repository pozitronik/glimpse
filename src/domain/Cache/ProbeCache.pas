{Persistent disk cache for TVideoInfo. Always enabled; stored separately
 from the frame cache so clearing frames does not invalidate probes.}
unit ProbeCache;

interface

uses
  VideoProbing, VideoInfo;

type
  TProbeCache = class
  strict private
    FCacheDir: string;
    class function BuildKeyString(const AFilePath: string; AFileSize: Int64; AFileTime: TDateTime): string; static;
    function ProbeKey(const AFilePath: string): string;
  public
    constructor Create(const ACacheDir: string);
    function TryGet(const AFilePath: string; out AInfo: TVideoInfo): Boolean;
    {Only caches valid results.}
    procedure Put(const AFilePath: string; const AInfo: TVideoInfo);
    {Cache-then-probe convenience shared by WLX/WCX/thumbnail paths. On a
     cache miss delegates to AProber and persists a valid result.}
    function TryGetOrProbe(const AFilePath: string; const AProber: IVideoProber): TVideoInfo;
    function GetTotalSize: Int64;
    {Best-effort: directory locks are swallowed.}
    procedure Clear;
  end;

function DefaultProbeCacheDir: string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, CacheKey;

const
  MOVEFILE_REPLACE_EXISTING = 1;

function MoveFileEx(lpExistingFileName, lpNewFileName: PChar; dwFlags: Cardinal): LongBool; stdcall; external 'kernel32.dll' name 'MoveFileExW';

function DefaultProbeCacheDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'Glimpse' + PathDelim + 'probes');
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
    AInfo.Duration := StrToFloatDef(Lines.Values['Duration'], -1, InvFmt);
    AInfo.Width := StrToIntDef(Lines.Values['Width'], 0);
    AInfo.Height := StrToIntDef(Lines.Values['Height'], 0);
    AInfo.SampleAspectN := StrToIntDef(Lines.Values['SampleAspectN'], 1);
    AInfo.SampleAspectD := StrToIntDef(Lines.Values['SampleAspectD'], 1);
    AInfo.DisplayWidth := StrToIntDef(Lines.Values['DisplayWidth'], 0);
    AInfo.DisplayHeight := StrToIntDef(Lines.Values['DisplayHeight'], 0);
    {Pre-SAR cache entries lack explicit DisplayWidth/Height; rederive.}
    if (AInfo.DisplayWidth <= 0) or (AInfo.DisplayHeight <= 0) then
      AInfo.RecalcDisplayDimensions;
    AInfo.VideoCodec := Lines.Values['VideoCodec'];
    AInfo.VideoBitrateKbps := StrToIntDef(Lines.Values['VideoBitrateKbps'], 0);
    AInfo.Fps := StrToFloatDef(Lines.Values['Fps'], 0, InvFmt);
    AInfo.Bitrate := StrToIntDef(Lines.Values['Bitrate'], 0);
    AInfo.AudioCodec := Lines.Values['AudioCodec'];
    AInfo.AudioSampleRate := StrToIntDef(Lines.Values['AudioSampleRate'], 0);
    AInfo.AudioChannels := Lines.Values['AudioChannels'];
    AInfo.AudioBitrateKbps := StrToIntDef(Lines.Values['AudioBitrateKbps'], 0);
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
  Key, Path, Dir, TempPath: string;
  Lines: TStringList;
begin
  if not AInfo.IsValid then
    Exit;

  Key := ProbeKey(AFilePath);
  if Key = '' then
    Exit;

  Path := ShardedKeyPath(FCacheDir, Key, '.probe');
  Dir := ExtractFilePath(Path);

  Lines := TStringList.Create;
  try
    Lines.Add('Duration=' + FloatToStr(AInfo.Duration, InvFmt));
    Lines.Add('Width=' + IntToStr(AInfo.Width));
    Lines.Add('Height=' + IntToStr(AInfo.Height));
    Lines.Add('SampleAspectN=' + IntToStr(AInfo.SampleAspectN));
    Lines.Add('SampleAspectD=' + IntToStr(AInfo.SampleAspectD));
    Lines.Add('DisplayWidth=' + IntToStr(AInfo.DisplayWidth));
    Lines.Add('DisplayHeight=' + IntToStr(AInfo.DisplayHeight));
    Lines.Add('VideoCodec=' + AInfo.VideoCodec);
    Lines.Add('VideoBitrateKbps=' + IntToStr(AInfo.VideoBitrateKbps));
    Lines.Add('Fps=' + FloatToStr(AInfo.Fps, InvFmt));
    Lines.Add('Bitrate=' + IntToStr(AInfo.Bitrate));
    Lines.Add('AudioCodec=' + AInfo.AudioCodec);
    Lines.Add('AudioSampleRate=' + IntToStr(AInfo.AudioSampleRate));
    Lines.Add('AudioChannels=' + AInfo.AudioChannels);
    Lines.Add('AudioBitrateKbps=' + IntToStr(AInfo.AudioBitrateKbps));
    {Atomic write via sibling .tmp + MoveFileEx so a crash mid-write
     cannot leave a partial .probe that poisons future TryGets.}
    TempPath := Path + '.' + TGUID.NewGuid.ToString + '.tmp';
    try
      TDirectory.CreateDirectory(Dir);
      Lines.SaveToFile(TempPath, TEncoding.UTF8);
      if not MoveFileEx(PChar(TempPath), PChar(Path), MOVEFILE_REPLACE_EXISTING) then
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
  finally
    Lines.Free;
  end;
end;

end.
