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
    [Test] procedure TestTryGetOrProbeHitsCache;
    [Test] procedure TestTryGetOrProbeMissReturnsInvalidAndSkipsCache;
    [Test] procedure TestGetTotalSizeEmpty;
    [Test] procedure TestGetTotalSizeAfterPut;
    [Test] procedure TestGetTotalSizeOnMissingDir;
    [Test] procedure TestClearWipesEntries;
    [Test] procedure TestClearOnMissingDirNoException;
    {Atomic write: Put writes to a sibling .tmp and renames into place. A
     successful Put must leave only the final .probe file; the .tmp must
     be gone. Earlier Lines.SaveToFile wrote straight to the target, so a
     mid-write crash left a partial file that TryGet treated as valid
     (cache poisoning until the source file's mtime changed).}
    [Test] procedure TestPutLeavesNoTempFiles;
    [Test] procedure TestPutOverwritesPreviousEntryAtomically;
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
      Info.Width := 720;
      Info.Height := 576;
      Info.SampleAspectN := 64;
      Info.SampleAspectD := 45;
      Info.DisplayWidth := 1024;
      Info.DisplayHeight := 576;
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
      Assert.AreEqual(720, Retrieved.Width);
      Assert.AreEqual(576, Retrieved.Height);
      Assert.AreEqual(64, Retrieved.SampleAspectN, 'SAR numerator must round-trip');
      Assert.AreEqual(45, Retrieved.SampleAspectD, 'SAR denominator must round-trip');
      Assert.AreEqual(1024, Retrieved.DisplayWidth, 'Display width must round-trip');
      Assert.AreEqual(576, Retrieved.DisplayHeight, 'Display height must round-trip');
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

procedure TTestProbeCache.TestTryGetOrProbeHitsCache;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
begin
  { Pre-populate the cache so TryGetOrProbe returns without invoking ffmpeg.
    Passing a bogus ffmpeg path proves the hit path never reaches the subprocess. }
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_hit.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 42.5;
      Info.Width := 1280;
      Info.Height := 720;
      Info.IsValid := True;
      Cache.Put(TmpFile, Info);

      Retrieved := Cache.TryGetOrProbe(TmpFile, '__no_such_ffmpeg__.exe');

      Assert.IsTrue(Retrieved.IsValid, 'Cached entry must be returned');
      Assert.AreEqual(Double(42.5), Retrieved.Duration, 0.001);
      Assert.AreEqual(1280, Retrieved.Width);
      Assert.AreEqual(720, Retrieved.Height);
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestTryGetOrProbeMissReturnsInvalidAndSkipsCache;
var
  Cache: TProbeCache;
  Retrieved, Check: TVideoInfo;
  TmpFile: string;
begin
  { Cache miss + bogus ffmpeg path: ProbeVideo should yield an invalid result,
    and Put() must refuse to persist it (Put is a no-op for invalid entries).
    The next TryGet must still miss. }
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_miss_probe.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Retrieved := Cache.TryGetOrProbe(TmpFile, '__no_such_ffmpeg__.exe');
      Assert.IsFalse(Retrieved.IsValid, 'Invalid probe result expected');

      Assert.IsFalse(Cache.TryGet(TmpFile, Check),
        'Invalid result must not have been cached');
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
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

procedure TTestProbeCache.TestGetTotalSizeEmpty;
var
  Cache: TProbeCache;
begin
  {Fresh cache dir, nothing put. Total must be zero.}
  Cache := TProbeCache.Create(FCacheDir);
  try
    Assert.AreEqual<Int64>(0, Cache.GetTotalSize);
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestGetTotalSizeAfterPut;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
  TmpFile: string;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_size_test.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 60;
      Info.Width := 1920;
      Info.Height := 1080;
      Info.IsValid := True;
      Cache.Put(TmpFile, Info);
      Assert.IsTrue(Cache.GetTotalSize > 0,
        'After Put the total size must be non-zero');
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestGetTotalSizeOnMissingDir;
var
  Cache: TProbeCache;
begin
  {Missing dir is the normal "first run" state; must return 0 not raise.}
  Cache := TProbeCache.Create(TPath.Combine(FCacheDir, 'never_created'));
  try
    Assert.AreEqual<Int64>(0, Cache.GetTotalSize);
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestClearWipesEntries;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
begin
  {Clear must drop every cached probe and leave subsequent TryGet missing.}
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_clear_test.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 60;
      Info.Width := 1920;
      Info.Height := 1080;
      Info.IsValid := True;
      Cache.Put(TmpFile, Info);
      Assert.IsTrue(Cache.TryGet(TmpFile, Retrieved), 'Pre-condition: cache hit');

      Cache.Clear;
      Assert.AreEqual<Int64>(0, Cache.GetTotalSize, 'Total size zero after Clear');
      Assert.IsFalse(Cache.TryGet(TmpFile, Retrieved), 'Cache must miss after Clear');
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestClearOnMissingDirNoException;
var
  Cache: TProbeCache;
begin
  {Clear on a never-created dir must be a no-op, not a crash.}
  Cache := TProbeCache.Create(TPath.Combine(FCacheDir, 'never_created'));
  try
    Cache.Clear;
    Assert.Pass('Clear on missing dir did not raise');
  finally
    Cache.Free;
  end;
end;

procedure TTestProbeCache.TestPutLeavesNoTempFiles;
var
  Cache: TProbeCache;
  Info: TVideoInfo;
  TmpFile: string;
  TempLeftovers: TArray<string>;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_atomic_' +
    TGuid.NewGuid.ToString + '.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      Info := Default(TVideoInfo);
      Info.Duration := 60.0;
      Info.Width := 640;
      Info.Height := 360;
      Info.IsValid := True;

      Cache.Put(TmpFile, Info);

      {Recursive scan; the temp file lives next to the .probe inside the
       sharded subdirectory.}
      TempLeftovers := TDirectory.GetFiles(FCacheDir, '*.tmp',
        TSearchOption.soAllDirectories);
      Assert.AreEqual<Integer>(0, Length(TempLeftovers),
        'Atomic Put must rename the temp into place; no .tmp may remain');
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

procedure TTestProbeCache.TestPutOverwritesPreviousEntryAtomically;
var
  Cache: TProbeCache;
  Info, Retrieved: TVideoInfo;
  TmpFile: string;
  TempLeftovers: TArray<string>;
begin
  TmpFile := TPath.Combine(TPath.GetTempPath, 'probe_test_overwrite_' +
    TGuid.NewGuid.ToString + '.tmp');
  TFile.WriteAllText(TmpFile, 'dummy');
  try
    Cache := TProbeCache.Create(FCacheDir);
    try
      {First put.}
      Info := Default(TVideoInfo);
      Info.Duration := 30.0;
      Info.Width := 320;
      Info.Height := 240;
      Info.IsValid := True;
      Cache.Put(TmpFile, Info);

      {Re-put with different values; MoveFileEx + MOVEFILE_REPLACE_EXISTING
       must overwrite cleanly without orphan .tmp files.}
      Info.Duration := 90.0;
      Info.Width := 1280;
      Info.Height := 720;
      Cache.Put(TmpFile, Info);

      Assert.IsTrue(Cache.TryGet(TmpFile, Retrieved));
      Assert.AreEqual(Double(90.0), Retrieved.Duration, 0.001,
        'Overwrite must take effect');
      Assert.AreEqual(1280, Retrieved.Width);

      TempLeftovers := TDirectory.GetFiles(FCacheDir, '*.tmp',
        TSearchOption.soAllDirectories);
      Assert.AreEqual<Integer>(0, Length(TempLeftovers),
        'No .tmp may remain after a successful overwrite');
    finally
      Cache.Free;
    end;
  finally
    TFile.Delete(TmpFile);
  end;
end;

end.
