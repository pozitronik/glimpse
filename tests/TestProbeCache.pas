unit TestProbeCache;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestProbeCache = class
  private
    FCacheDir: string;
    procedure CleanUp;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestMissOnEmpty;
    [Test] procedure TestPutThenGet;
    [Test] procedure TestAllFieldsRoundTrip;
    [Test] procedure TestInvalidResultNotCached;
    [Test] procedure TestMissOnNonexistentFile;
    [Test] procedure TestStaleAfterFileChange;
    [Test] procedure TestShardedDirectory;
    [Test] procedure TestDefaultProbeCacheDir;
    [Test] procedure TestFloatLocaleIndependence;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  uFFmpegExe, uProbeCache;

{ TTestProbeCache }

procedure TTestProbeCache.Setup;
begin
  FCacheDir := TPath.Combine(TPath.GetTempPath,
    'glimpse_probe_test_' + IntToStr(Random(MaxInt)));
end;

procedure TTestProbeCache.TearDown;
begin
  CleanUp;
end;

procedure TTestProbeCache.CleanUp;
begin
  if TDirectory.Exists(FCacheDir) then
    TDirectory.Delete(FCacheDir, True);
end;

procedure TTestProbeCache.TestMissOnEmpty;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
  TmpFile: string;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_miss.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Assert.IsFalse(Cache.TryGet(TmpFile, Info));
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestPutThenGet;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_put.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 120.5;
      Info.Width := 1920;
      Info.Height := 1080;
      Info.IsValid := True;

      Cache.Put(TmpFile, Info);
      Assert.IsTrue(Cache.TryGet(TmpFile, Retrieved));
      Assert.AreEqual(Double(120.5), Retrieved.Duration, 0.001);
      Assert.AreEqual(1920, Retrieved.Width);
      Assert.AreEqual(1080, Retrieved.Height);
      Assert.IsTrue(Retrieved.IsValid);
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestAllFieldsRoundTrip;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_fields.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 3661.123;
      Info.Width := 3840;
      Info.Height := 2160;
      Info.VideoCodec := 'h264';
      Info.VideoBitrateKbps := 5000;
      Info.Fps := 23.976;
      Info.Bitrate := 5500;
      Info.AudioCodec := 'aac';
      Info.AudioSampleRate := 48000;
      Info.AudioChannels := '5.1';
      Info.AudioBitrateKbps := 192;
      Info.IsValid := True;

      Cache.Put(TmpFile, Info);
      Assert.IsTrue(Cache.TryGet(TmpFile, Retrieved));

      Assert.AreEqual(Double(3661.123), Retrieved.Duration, 0.001);
      Assert.AreEqual(3840, Retrieved.Width);
      Assert.AreEqual(2160, Retrieved.Height);
      Assert.AreEqual('h264', Retrieved.VideoCodec);
      Assert.AreEqual(5000, Retrieved.VideoBitrateKbps);
      Assert.AreEqual(Double(23.976), Retrieved.Fps, 0.001);
      Assert.AreEqual(5500, Retrieved.Bitrate);
      Assert.AreEqual('aac', Retrieved.AudioCodec);
      Assert.AreEqual(48000, Retrieved.AudioSampleRate);
      Assert.AreEqual('5.1', Retrieved.AudioChannels);
      Assert.AreEqual(192, Retrieved.AudioBitrateKbps);
      Assert.IsTrue(Retrieved.IsValid);
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestInvalidResultNotCached;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_invalid.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := -1;
      Info.IsValid := False;
      Info.ErrorMessage := 'Could not parse';

      Cache.Put(TmpFile, Info);
      Assert.IsFalse(Cache.TryGet(TmpFile, Retrieved));
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestMissOnNonexistentFile;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
begin
  Cache := TProbeCache.Create(FCacheDir);
  try
    Assert.IsFalse(Cache.TryGet('Z:\nonexistent\video.mp4', Info));
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestStaleAfterFileChange;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_stale.tmp');
  TFile.WriteAllText(TmpFile, 'original');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 60.0;
      Info.Width := 1280;
      Info.Height := 720;
      Info.IsValid := True;

      Cache.Put(TmpFile, Info);
      Assert.IsTrue(Cache.TryGet(TmpFile, Retrieved));

      { Modify the file so its timestamp changes }
      Sleep(50);
      TFile.WriteAllText(TmpFile, 'modified content');

      { Cache should miss because file metadata changed }
      Assert.IsFalse(Cache.TryGet(TmpFile, Retrieved));
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestShardedDirectory;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
  TmpFile: string;
  Dirs: TArray<string>;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_shard.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 10.0;
      Info.IsValid := True;

      Cache.Put(TmpFile, Info);

      { Verify a 2-char shard subdirectory was created }
      Dirs := TDirectory.GetDirectories(FCacheDir);
      Assert.AreEqual(1, Integer(Length(Dirs)));
      Assert.AreEqual(2, Integer(Length(ExtractFileName(Dirs[0]))));
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestDefaultProbeCacheDir;
var
  Dir: string;
begin
  Dir := DefaultProbeCacheDir;
  Assert.IsTrue(Dir.Contains('Glimpse'));
  Assert.IsTrue(Dir.Contains('probes'));
end;

procedure TTestProbeCache.TestFloatLocaleIndependence;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
  SavedSep: Char;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_locale.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    { Write with comma decimal separator }
    SavedSep := FormatSettings.DecimalSeparator;
    try
      FormatSettings.DecimalSeparator := ',';
      Cache := TProbeCache.Create(FCacheDir);
      try
        Info := Default(TVideoInfo);
        Info.Duration := 123.456;
        Info.Fps := 29.97;
        Info.IsValid := True;
        Cache.Put(TmpFile, Info);
      finally
        Cache.Free;
      end;

      { Read with period decimal separator }
      FormatSettings.DecimalSeparator := '.';
      Cache := TProbeCache.Create(FCacheDir);
      try
        Assert.IsTrue(Cache.TryGet(TmpFile, Retrieved));
        Assert.AreEqual(Double(123.456), Retrieved.Duration, 0.001);
        Assert.AreEqual(Double(29.97), Retrieved.Fps, 0.001);
      finally
        Cache.Free;
      end;
    finally
      FormatSettings.DecimalSeparator := SavedSep;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

end.
