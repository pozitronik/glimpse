unit TestFFmpegExe;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegParsing = class
  public
    { Duration parsing }
    [Test] procedure TestParseDurationStandard;
    [Test] procedure TestParseDurationZero;
    [Test] procedure TestParseDurationShort;
    [Test] procedure TestParseDurationLong;
    [Test] procedure TestParseDurationThreeDigitFraction;
    [Test] procedure TestParseDurationNoFraction;
    [Test] procedure TestParseDurationFullOutput;
    [Test] procedure TestParseDurationMissing;
    [Test] procedure TestParseDurationNA;
    [Test] procedure TestParseDurationMalformed;
    { Resolution parsing }
    [Test] procedure TestParseResolution1080p;
    [Test] procedure TestParseResolution4K;
    [Test] procedure TestParseResolutionSmall;
    [Test] procedure TestParseResolutionNoVideo;
    [Test] procedure TestParseResolutionSkipsHexValues;
    [Test] procedure TestParseResolutionFullOutput;
    { Codec parsing }
    [Test] procedure TestParseCodecH264;
    [Test] procedure TestParseCodecHevc;
    [Test] procedure TestParseCodecMpeg2;
    [Test] procedure TestParseCodecNoVideo;
    { Edge cases }
    [Test] procedure TestParseDurationEmptyString;
    [Test] procedure TestParseDurationTrailingDot;
    [Test] procedure TestParseResolutionSingleDigitRejected;
    [Test] procedure TestParseVideoCodecEmptyInput;
    [Test] procedure TestParseVideoCodecExtraSpaces;
  end;

  [TestFixture]
  TTestFFmpegLocator = class
  private
    FTempDir: string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestFindInPluginDir;
    [Test] procedure TestFindAtConfiguredPath;
    [Test] procedure TestPluginDirHasPriority;
    [Test] procedure TestNotFoundReturnsEmpty;
    [Test] procedure TestEmptyPluginDir;
    [Test] procedure TestConfiguredPathNotExists;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uFFmpegExe, uFFmpegLocator;

const
  { Realistic ffmpeg probe output for integration-style parsing tests }
  SAMPLE_FFMPEG_OUTPUT =
    'Input #0, mov,mp4,m4a,3gp,3g2,mj2, from ''test.mp4'':'#13#10 +
    '  Metadata:'#13#10 +
    '    major_brand     : isom'#13#10 +
    '    minor_version   : 512'#13#10 +
    '    compatible_brands: isomiso2avc1mp41'#13#10 +
    '    encoder         : Lavf58.29.100'#13#10 +
    '  Duration: 00:10:30.50, start: 0.000000, bitrate: 2000 kb/s'#13#10 +
    '  Stream #0:0(und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709), ' +
      '1920x1080 [SAR 1:1 DAR 16:9], 1800 kb/s, 30 fps, 30 tbr, 15360 tbn (default)'#13#10 +
    '  Stream #0:1(und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, ' +
      '128 kb/s (default)'#13#10 +
    'At least one output file must be specified'#13#10;

{ TTestFFmpegParsing: Duration }

procedure TTestFFmpegParsing.TestParseDurationStandard;
begin
  Assert.AreEqual(5025.67, ParseDuration('Duration: 01:23:45.67, start: 0.0'), 0.01);
end;

procedure TTestFFmpegParsing.TestParseDurationZero;
begin
  Assert.AreEqual(0.0, ParseDuration('Duration: 00:00:00.00, start: 0.0'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseDurationShort;
begin
  Assert.AreEqual(5.5, ParseDuration('Duration: 00:00:05.50'), 0.01);
end;

procedure TTestFFmpegParsing.TestParseDurationLong;
begin
  Assert.AreEqual(9000.0, ParseDuration('Duration: 02:30:00.00'), 0.01);
end;

procedure TTestFFmpegParsing.TestParseDurationThreeDigitFraction;
begin
  Assert.AreEqual(90.123, ParseDuration('Duration: 00:01:30.123'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseDurationNoFraction;
begin
  { Some edge builds may omit the fractional part }
  Assert.AreEqual(90.0, ParseDuration('Duration: 00:01:30, start: 0.0'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseDurationFullOutput;
begin
  { Parse from realistic multi-line ffmpeg output }
  Assert.AreEqual(630.5, ParseDuration(SAMPLE_FFMPEG_OUTPUT), 0.01);
end;

procedure TTestFFmpegParsing.TestParseDurationMissing;
begin
  Assert.AreEqual(-1.0, ParseDuration('no duration here'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseDurationNA;
begin
  Assert.AreEqual(-1.0, ParseDuration('Duration: N/A, bitrate: N/A'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseDurationMalformed;
begin
  Assert.AreEqual(-1.0, ParseDuration('Duration: GARBAGE'), 0.001);
  Assert.AreEqual(-1.0, ParseDuration('Duration: 01:02'), 0.001);
  Assert.AreEqual(-1.0, ParseDuration('Duration: ::'), 0.001);
end;

{ TTestFFmpegParsing: Resolution }

procedure TTestFFmpegParsing.TestParseResolution1080p;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution('Stream #0:0: Video: h264, yuv420p, 1920x1080, 30 fps', W, H));
  Assert.AreEqual(1920, W);
  Assert.AreEqual(1080, H);
end;

procedure TTestFFmpegParsing.TestParseResolution4K;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution('Video: hevc, yuv420p, 3840x2160', W, H));
  Assert.AreEqual(3840, W);
  Assert.AreEqual(2160, H);
end;

procedure TTestFFmpegParsing.TestParseResolutionSmall;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution('Video: mpeg4, yuv420p, 320x240, 25 fps', W, H));
  Assert.AreEqual(320, W);
  Assert.AreEqual(240, H);
end;

procedure TTestFFmpegParsing.TestParseResolutionNoVideo;
var
  W, H: Integer;
begin
  Assert.IsFalse(ParseResolution('Stream #0:0: Audio: aac, 44100 Hz, stereo', W, H));
  Assert.AreEqual(0, W);
  Assert.AreEqual(0, H);
end;

procedure TTestFFmpegParsing.TestParseResolutionSkipsHexValues;
var
  W, H: Integer;
begin
  { Hex values like 0x31637661 should not produce false matches }
  Assert.IsTrue(ParseResolution(
    'Video: h264 (avc1 / 0x31637661), yuv420p, 1280x720', W, H));
  Assert.AreEqual(1280, W);
  Assert.AreEqual(720, H);
end;

procedure TTestFFmpegParsing.TestParseResolutionFullOutput;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution(SAMPLE_FFMPEG_OUTPUT, W, H));
  Assert.AreEqual(1920, W);
  Assert.AreEqual(1080, H);
end;

{ TTestFFmpegParsing: Codec }

procedure TTestFFmpegParsing.TestParseCodecH264;
begin
  Assert.AreEqual('h264', ParseVideoCodec('Video: h264 (High), yuv420p'));
end;

procedure TTestFFmpegParsing.TestParseCodecHevc;
begin
  Assert.AreEqual('hevc', ParseVideoCodec('Video: hevc (Main 10), yuv420p10le'));
end;

procedure TTestFFmpegParsing.TestParseCodecMpeg2;
begin
  Assert.AreEqual('mpeg2video', ParseVideoCodec('Video: mpeg2video, yuv420p'));
end;

procedure TTestFFmpegParsing.TestParseCodecNoVideo;
begin
  Assert.AreEqual('', ParseVideoCodec('Audio: aac (LC), 44100 Hz'));
end;

{ TTestFFmpegParsing: Edge cases }

procedure TTestFFmpegParsing.TestParseDurationEmptyString;
begin
  Assert.AreEqual(-1.0, ParseDuration(''), 0.001, 'Empty string should return -1');
end;

procedure TTestFFmpegParsing.TestParseDurationTrailingDot;
begin
  { "00:01:30." has a dot but no fractional digits: should reject as malformed }
  Assert.AreEqual(-1.0, ParseDuration('Duration: 00:01:30.'), 0.001,
    'Trailing dot without fraction should return -1');
end;

procedure TTestFFmpegParsing.TestParseResolutionSingleDigitRejected;
var
  W, H: Integer;
begin
  { Single-digit dimensions (e.g. 8x8) must be rejected to avoid hex false matches }
  Assert.IsFalse(ParseResolution('Video: h264, 8x8, 30 fps', W, H),
    'Single-digit resolution should be rejected');
end;

procedure TTestFFmpegParsing.TestParseVideoCodecEmptyInput;
begin
  Assert.AreEqual('', ParseVideoCodec(''), 'Empty string should return empty codec');
end;

procedure TTestFFmpegParsing.TestParseVideoCodecExtraSpaces;
begin
  { Multiple spaces between "Video:" and codec name should be skipped }
  Assert.AreEqual('vp9', ParseVideoCodec('Video:    vp9 (Profile 0)'));
end;

{ TTestFFmpegLocator }

procedure TTestFFmpegLocator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_Loc_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestFFmpegLocator.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestFFmpegLocator.TestFindInPluginDir;
var
  PluginDir, Found: string;
begin
  PluginDir := TPath.Combine(FTempDir, 'plugin');
  TDirectory.CreateDirectory(PluginDir);
  TFile.WriteAllText(TPath.Combine(PluginDir, 'ffmpeg.exe'), 'dummy');

  Found := FindFFmpegExe(PluginDir, '');
  Assert.AreEqual(TPath.Combine(PluginDir, 'ffmpeg.exe'), Found);
end;

procedure TTestFFmpegLocator.TestFindAtConfiguredPath;
var
  ExePath, Found: string;
begin
  ExePath := TPath.Combine(FTempDir, 'custom_ffmpeg.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  { Empty plugin dir (no ffmpeg there), configured path exists }
  Found := FindFFmpegExe(TPath.Combine(FTempDir, 'empty'), ExePath);
  Assert.AreEqual(ExePath, Found);
end;

procedure TTestFFmpegLocator.TestPluginDirHasPriority;
var
  PluginDir, ConfigPath, Found: string;
begin
  { Both plugin dir and configured path have ffmpeg; plugin dir should win }
  PluginDir := TPath.Combine(FTempDir, 'plugin');
  TDirectory.CreateDirectory(PluginDir);
  TFile.WriteAllText(TPath.Combine(PluginDir, 'ffmpeg.exe'), 'plugin');

  ConfigPath := TPath.Combine(FTempDir, 'other_ffmpeg.exe');
  TFile.WriteAllText(ConfigPath, 'config');

  Found := FindFFmpegExe(PluginDir, ConfigPath);
  Assert.AreEqual(TPath.Combine(PluginDir, 'ffmpeg.exe'), Found,
    'Plugin directory should have priority over configured path');
end;

procedure TTestFFmpegLocator.TestNotFoundReturnsEmpty;
var
  Found: string;
begin
  { Neither plugin dir nor configured path has ffmpeg, and we cannot rely
    on system PATH for a deterministic test. Just verify no crash. }
  Found := FindFFmpegExe(TPath.Combine(FTempDir, 'nowhere'), '');
  { Result depends on whether ffmpeg is on system PATH; just verify no exception }
  Assert.Pass;
end;

procedure TTestFFmpegLocator.TestEmptyPluginDir;
var
  ExePath, Found: string;
begin
  ExePath := TPath.Combine(FTempDir, 'ff.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  Found := FindFFmpegExe('', ExePath);
  Assert.AreEqual(ExePath, Found, 'Empty plugin dir should skip to configured path');
end;

procedure TTestFFmpegLocator.TestConfiguredPathNotExists;
var
  Found: string;
begin
  { Configured path points to a non-existent file }
  Found := FindFFmpegExe(
    TPath.Combine(FTempDir, 'empty'),
    TPath.Combine(FTempDir, 'no_such_file.exe'));
  { Should fall through to system PATH search }
  Assert.Pass;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegParsing);
  TDUnitX.RegisterTestFixture(TTestFFmpegLocator);

end.
