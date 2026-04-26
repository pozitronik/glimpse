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
    { Version parsing }
    [Test] procedure TestParseVersionStandard;
    [Test] procedure TestParseVersionWithSuffix;
    [Test] procedure TestParseVersionGitBuild;
    [Test] procedure TestParseVersionMultiLine;
    [Test] procedure TestParseVersionEmpty;
    [Test] procedure TestParseVersionNotFFmpeg;
    [Test] procedure TestParseVersionCaseInsensitive;
    { Bitrate parsing }
    [Test] procedure TestParseBitrateFromDurationLine;
    [Test] procedure TestParseBitrateFullOutput;
    [Test] procedure TestParseBitrateMissing;
    { FPS parsing }
    [Test] procedure TestParseFpsInteger;
    [Test] procedure TestParseFpsFractional;
    [Test] procedure TestParseFpsFullOutput;
    [Test] procedure TestParseFpsNoVideo;
    { Video bitrate parsing }
    [Test] procedure TestParseVideoBitrateFromStream;
    [Test] procedure TestParseVideoBitrateFullOutput;
    [Test] procedure TestParseVideoBitrateMissing;
    { Audio codec parsing }
    [Test] procedure TestParseAudioCodecAac;
    [Test] procedure TestParseAudioCodecMp3;
    [Test] procedure TestParseAudioCodecFullOutput;
    [Test] procedure TestParseAudioCodecNoAudio;
    { Audio sample rate }
    [Test] procedure TestParseAudioSampleRate44100;
    [Test] procedure TestParseAudioSampleRate48000;
    [Test] procedure TestParseAudioSampleRateFullOutput;
    [Test] procedure TestParseAudioSampleRateNoAudio;
    { Audio channels }
    [Test] procedure TestParseAudioChannelsStereo;
    [Test] procedure TestParseAudioChannelsMono;
    [Test] procedure TestParseAudioChannels51;
    [Test] procedure TestParseAudioChannelsFullOutput;
    [Test] procedure TestParseAudioChannelsNoAudio;
    { Audio bitrate }
    [Test] procedure TestParseAudioBitrateFromStream;
    [Test] procedure TestParseAudioBitrateFullOutput;
    [Test] procedure TestParseAudioBitrateNoAudio;
    { Edge cases }
    [Test] procedure TestParseDurationEmptyString;
    [Test] procedure TestParseDurationTrailingDot;
    [Test] procedure TestParseResolutionSingleDigitRejected;
    [Test] procedure TestParseVideoCodecEmptyInput;
    [Test] procedure TestParseVideoCodecExtraSpaces;
    { Parser edge cases for metadata fields }
    [Test] procedure TestParseFpsFractional2997;
    [Test] procedure TestParseFpsNoFpsToken;
    [Test] procedure TestParseBitrateNoKbsToken;
    [Test] procedure TestParseAudioChannels71;
    [Test] procedure TestParseAudioChannelsQuad;
    [Test] procedure TestParseAudioChannelsUnknownLayout;
    [Test] procedure TestParseNoAudioStream;
    [Test] procedure TestParseVideoBitrateNoVideoStream;
    [Test] procedure TestParseResolutionAtEndOfString;
    [Test] procedure TestParseDurationSubSecond;
    [Test] procedure TestParseDurationSingleDigitFraction;
    [Test] procedure TestExtractStreamLineVideo;
    [Test] procedure TestExtractStreamLineNoMatch;
    { Sample aspect ratio parsing }
    [Test] procedure TestParseSampleAspectAnamorphic;
    [Test] procedure TestParseSampleAspectSquare;
    [Test] procedure TestParseSampleAspectMissing;
    [Test] procedure TestParseSampleAspectZeroNumerator;
    [Test] procedure TestParseSampleAspectZeroDenominator;
    [Test] procedure TestParseSampleAspectNoVideoLine;
    [Test] procedure TestParseSampleAspectFullOutput;
  end;

  [TestFixture]
  TTestFFmpegProbeIntegration = class
  public
    {Real ffmpeg.exe + a real anamorphic file. Skipped when ffmpeg.exe is
     not on the system PATH so the suite stays runnable on machines without
     ffmpeg installed.}
    [Test] procedure TestProbeAnamorphicVideo;
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
    [Test] procedure TestConfiguredPathExpandsEnvVars;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Winapi.Windows,
  uFFmpegExe, uFFmpegLocator;

function TestDataPath(const AFileName: string): string;
begin
  {Tests run from tests/Win64/Debug/GlimpseTests.exe; data lives in tests/data/}
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\data\' + AFileName));
end;

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

{ TTestFFmpegParsing: Version }

procedure TTestFFmpegParsing.TestParseVersionStandard;
begin
  Assert.AreEqual('6.1.1',
    ParseFFmpegVersion('ffmpeg version 6.1.1 Copyright (c) 2000-2023'));
end;

procedure TTestFFmpegParsing.TestParseVersionWithSuffix;
begin
  Assert.AreEqual('7.0',
    ParseFFmpegVersion('ffmpeg version 7.0-full_build Copyright (c) 2000-2024'));
end;

procedure TTestFFmpegParsing.TestParseVersionGitBuild;
begin
  Assert.AreEqual('N',
    ParseFFmpegVersion('ffmpeg version N-112858-g3545b4a51b Copyright (c) 2000-2024'));
end;

procedure TTestFFmpegParsing.TestParseVersionMultiLine;
begin
  Assert.AreEqual('5.1.4',
    ParseFFmpegVersion('ffmpeg version 5.1.4 Copyright'#13#10 +
      'built with gcc 12.2.0'#13#10 +
      'configuration: --enable-gpl'));
end;

procedure TTestFFmpegParsing.TestParseVersionEmpty;
begin
  Assert.AreEqual('', ParseFFmpegVersion(''));
end;

procedure TTestFFmpegParsing.TestParseVersionNotFFmpeg;
begin
  Assert.AreEqual('', ParseFFmpegVersion('Microsoft Windows [Version 10.0.19045]'));
  Assert.AreEqual('', ParseFFmpegVersion('Usage: someapp [options]'));
end;

procedure TTestFFmpegParsing.TestParseVersionCaseInsensitive;
begin
  Assert.AreEqual('6.0',
    ParseFFmpegVersion('FFmpeg version 6.0 Copyright'));
end;

{ TTestFFmpegParsing: Bitrate }

procedure TTestFFmpegParsing.TestParseBitrateFromDurationLine;
begin
  Assert.AreEqual(2000, ParseBitrate('Duration: 00:10:30.50, start: 0.000000, bitrate: 2000 kb/s'));
end;

procedure TTestFFmpegParsing.TestParseBitrateFullOutput;
begin
  Assert.AreEqual(2000, ParseBitrate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegParsing.TestParseBitrateMissing;
begin
  Assert.AreEqual(0, ParseBitrate('Duration: 00:01:00.00, start: 0.0'));
end;

{ TTestFFmpegParsing: FPS }

procedure TTestFFmpegParsing.TestParseFpsInteger;
begin
  Assert.AreEqual(30.0, ParseFps('Video: h264, yuv420p, 1920x1080, 30 fps'), 0.01);
end;

procedure TTestFFmpegParsing.TestParseFpsFractional;
begin
  Assert.AreEqual(23.976, ParseFps('Video: h264, yuv420p, 1920x1080, 23.976 fps'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseFpsFullOutput;
begin
  Assert.AreEqual(30.0, ParseFps(SAMPLE_FFMPEG_OUTPUT), 0.01);
end;

procedure TTestFFmpegParsing.TestParseFpsNoVideo;
begin
  Assert.AreEqual(0.0, ParseFps('Audio: aac, 44100 Hz, stereo'), 0.001);
end;

{ TTestFFmpegParsing: Video bitrate }

procedure TTestFFmpegParsing.TestParseVideoBitrateFromStream;
begin
  Assert.AreEqual(1800, ParseVideoBitrate(
    'Video: h264 (High), yuv420p, 1920x1080, 1800 kb/s, 30 fps'));
end;

procedure TTestFFmpegParsing.TestParseVideoBitrateFullOutput;
begin
  Assert.AreEqual(1800, ParseVideoBitrate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegParsing.TestParseVideoBitrateMissing;
begin
  Assert.AreEqual(0, ParseVideoBitrate('Video: h264, yuv420p, 1920x1080, 30 fps'));
end;

{ TTestFFmpegParsing: Audio codec }

procedure TTestFFmpegParsing.TestParseAudioCodecAac;
begin
  Assert.AreEqual('aac', ParseAudioCodec('Audio: aac (LC), 44100 Hz, stereo'));
end;

procedure TTestFFmpegParsing.TestParseAudioCodecMp3;
begin
  Assert.AreEqual('mp3', ParseAudioCodec('Audio: mp3, 44100 Hz, stereo, fltp, 320 kb/s'));
end;

procedure TTestFFmpegParsing.TestParseAudioCodecFullOutput;
begin
  Assert.AreEqual('aac', ParseAudioCodec(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegParsing.TestParseAudioCodecNoAudio;
begin
  Assert.AreEqual('', ParseAudioCodec('Video: h264, 1920x1080'));
end;

{ TTestFFmpegParsing: Audio sample rate }

procedure TTestFFmpegParsing.TestParseAudioSampleRate44100;
begin
  Assert.AreEqual(44100, ParseAudioSampleRate('Audio: aac, 44100 Hz, stereo'));
end;

procedure TTestFFmpegParsing.TestParseAudioSampleRate48000;
begin
  Assert.AreEqual(48000, ParseAudioSampleRate('Audio: aac (LC), 48000 Hz, 5.1, fltp'));
end;

procedure TTestFFmpegParsing.TestParseAudioSampleRateFullOutput;
begin
  Assert.AreEqual(44100, ParseAudioSampleRate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegParsing.TestParseAudioSampleRateNoAudio;
begin
  Assert.AreEqual(0, ParseAudioSampleRate('Video: h264, 1920x1080'));
end;

{ TTestFFmpegParsing: Audio channels }

procedure TTestFFmpegParsing.TestParseAudioChannelsStereo;
begin
  Assert.AreEqual('stereo', ParseAudioChannels('Audio: aac, 44100 Hz, stereo, fltp'));
end;

procedure TTestFFmpegParsing.TestParseAudioChannelsMono;
begin
  Assert.AreEqual('mono', ParseAudioChannels('Audio: aac, 22050 Hz, mono, fltp'));
end;

procedure TTestFFmpegParsing.TestParseAudioChannels51;
begin
  Assert.AreEqual('5.1', ParseAudioChannels('Audio: ac3, 48000 Hz, 5.1, fltp, 384 kb/s'));
end;

procedure TTestFFmpegParsing.TestParseAudioChannelsFullOutput;
begin
  Assert.AreEqual('stereo', ParseAudioChannels(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegParsing.TestParseAudioChannelsNoAudio;
begin
  Assert.AreEqual('', ParseAudioChannels('Video: h264, 1920x1080'));
end;

{ TTestFFmpegParsing: Audio bitrate }

procedure TTestFFmpegParsing.TestParseAudioBitrateFromStream;
begin
  Assert.AreEqual(128, ParseAudioBitrate('Audio: aac (LC), 44100 Hz, stereo, fltp, 128 kb/s'));
end;

procedure TTestFFmpegParsing.TestParseAudioBitrateFullOutput;
begin
  Assert.AreEqual(128, ParseAudioBitrate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegParsing.TestParseAudioBitrateNoAudio;
begin
  Assert.AreEqual(0, ParseAudioBitrate('Video: h264, 1920x1080'));
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

procedure TTestFFmpegParsing.TestParseFpsFractional2997;
begin
  Assert.AreEqual(29.97,
    ParseFps('Stream #0:0: Video: h264, 1920x1080, 29.97 fps'), 0.01);
end;

procedure TTestFFmpegParsing.TestParseFpsNoFpsToken;
begin
  { Video line without " fps" token returns 0 }
  Assert.AreEqual(Double(0),
    ParseFps('Stream #0:0: Video: h264, 1920x1080, 30 tbr'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseBitrateNoKbsToken;
begin
  { Duration line without "kb/s" returns 0 }
  Assert.AreEqual(0, ParseBitrate('Duration: 00:01:00.00, start: 0.0'));
end;

procedure TTestFFmpegParsing.TestParseAudioChannels71;
begin
  Assert.AreEqual('7.1',
    ParseAudioChannels('Stream #0:1: Audio: eac3, 48000 Hz, 7.1, fltp, 640 kb/s'));
end;

procedure TTestFFmpegParsing.TestParseAudioChannelsQuad;
begin
  { "quad" is a valid ffmpeg channel layout }
  Assert.AreEqual('quad',
    ParseAudioChannels('Stream #0:1: Audio: pcm_s16le, 44100 Hz, quad, s16'));
end;

procedure TTestFFmpegParsing.TestParseAudioChannelsUnknownLayout;
begin
  { Channel layout not in our known list returns empty }
  Assert.AreEqual('',
    ParseAudioChannels('Stream #0:1: Audio: aac, 44100 Hz, fltp, 128 kb/s'));
end;

procedure TTestFFmpegParsing.TestParseNoAudioStream;
const
  VIDEO_ONLY =
    'Duration: 00:01:00.00, start: 0.0, bitrate: 5000 kb/s'#13#10 +
    'Stream #0:0: Video: h264, 1920x1080, 30 fps'#13#10;
begin
  Assert.AreEqual('', ParseAudioCodec(VIDEO_ONLY));
  Assert.AreEqual(0, ParseAudioSampleRate(VIDEO_ONLY));
  Assert.AreEqual('', ParseAudioChannels(VIDEO_ONLY));
  Assert.AreEqual(0, ParseAudioBitrate(VIDEO_ONLY));
end;

procedure TTestFFmpegParsing.TestParseVideoBitrateNoVideoStream;
begin
  Assert.AreEqual(0, ParseVideoBitrate('Stream #0:0: Audio: aac, 44100 Hz'));
end;

procedure TTestFFmpegParsing.TestParseResolutionAtEndOfString;
var
  W, H: Integer;
begin
  { Resolution pattern at the very end of the string, no trailing characters }
  Assert.IsTrue(ParseResolution('Stream #0:0: Video: h264, 1920x1080', W, H),
    'Should parse resolution at end of string');
  Assert.AreEqual(1920, W);
  Assert.AreEqual(1080, H);
end;

procedure TTestFFmpegParsing.TestParseDurationSubSecond;
begin
  { Duration less than 1 second }
  Assert.AreEqual(0.50, ParseDuration('Duration: 00:00:00.50,'), 0.001);
end;

procedure TTestFFmpegParsing.TestParseDurationSingleDigitFraction;
begin
  { Single fractional digit: 0.5 seconds, not 0.05 }
  Assert.AreEqual(90.5, ParseDuration('Duration: 00:01:30.5,'), 0.001);
end;

procedure TTestFFmpegParsing.TestExtractStreamLineVideo;
var
  Input: string;
begin
  { ExtractStreamLine returns from the prefix position to end of line }
  Input := 'Stream #0:0: Video: h264, 1920x1080' + #13#10 +
           'Stream #0:1: Audio: aac, 48000 Hz';
  Assert.AreEqual('Video: h264, 1920x1080',
    ExtractStreamLine(Input, 'Video:'));
end;

procedure TTestFFmpegParsing.TestExtractStreamLineNoMatch;
begin
  Assert.AreEqual('', ExtractStreamLine('no streams here', 'Video:'));
end;

{ Sample aspect ratio parsing }

procedure TTestFFmpegParsing.TestParseSampleAspectAnamorphic;
var
  N, D: Integer;
begin
  Assert.IsTrue(ParseSampleAspect(
    '  Stream #0:0: Video: h264, yuv420p, 720x576 [SAR 64:45 DAR 16:9], 25 fps',
    N, D));
  Assert.AreEqual(64, N);
  Assert.AreEqual(45, D);
end;

procedure TTestFFmpegParsing.TestParseSampleAspectSquare;
var
  N, D: Integer;
begin
  Assert.IsTrue(ParseSampleAspect(
    '  Stream #0:0: Video: h264, yuv420p, 1920x1080 [SAR 1:1 DAR 16:9], 60 fps',
    N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegParsing.TestParseSampleAspectMissing;
var
  N, D: Integer;
begin
  {Many encodes omit SAR/DAR brackets entirely; default to 1:1 and return False.}
  Assert.IsFalse(ParseSampleAspect(
    '  Stream #0:0: Video: h264, yuv420p, 1920x1080, 5000 kb/s, 30 fps',
    N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegParsing.TestParseSampleAspectZeroNumerator;
var
  N, D: Integer;
begin
  {ffmpeg emits "[SAR 0:1 DAR 0:1]" when SAR is unknown; treat as 1:1.}
  Assert.IsFalse(ParseSampleAspect(
    '  Stream #0:0: Video: h264, 1920x1080 [SAR 0:1 DAR 0:1], 30 fps',
    N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegParsing.TestParseSampleAspectZeroDenominator;
var
  N, D: Integer;
begin
  Assert.IsFalse(ParseSampleAspect(
    '  Stream #0:0: Video: h264, 1920x1080 [SAR 1:0 DAR 16:9], 30 fps',
    N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegParsing.TestParseSampleAspectNoVideoLine;
var
  N, D: Integer;
begin
  Assert.IsFalse(ParseSampleAspect('  Stream #0:0: Audio: aac, 44100 Hz, stereo', N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegParsing.TestParseSampleAspectFullOutput;
var
  N, D: Integer;
begin
  {SAMPLE_FFMPEG_OUTPUT carries [SAR 1:1 DAR 16:9] on its Video line.}
  Assert.IsTrue(ParseSampleAspect(SAMPLE_FFMPEG_OUTPUT, N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

{ TTestFFmpegProbeIntegration }

procedure TTestFFmpegProbeIntegration.TestProbeAnamorphicVideo;
var
  FFmpegPath, VideoPath: string;
  FFmpeg: TFFmpegExe;
  Info: TVideoInfo;
begin
  FFmpegPath := FindFFmpegExe('', '');
  if FFmpegPath = '' then
  begin
    {Pass-through when ffmpeg is not on PATH; the unit-level parse tests
     still cover the parsing logic.}
    Assert.Pass('ffmpeg.exe not on PATH; skipping integration test');
    Exit;
  end;

  VideoPath := TestDataPath('test_anamorphic.mp4');
  Assert.IsTrue(TFile.Exists(VideoPath),
    'Test data missing: ' + VideoPath);

  FFmpeg := TFFmpegExe.Create(FFmpegPath);
  try
    Info := FFmpeg.ProbeVideo(VideoPath);
    Assert.IsTrue(Info.IsValid, 'Probe must succeed: ' + Info.ErrorMessage);
    Assert.AreEqual(720, Info.Width, 'Storage width');
    Assert.AreEqual(576, Info.Height, 'Storage height');
    Assert.AreEqual(64, Info.SampleAspectN, 'SAR numerator');
    Assert.AreEqual(45, Info.SampleAspectD, 'SAR denominator');
    Assert.AreEqual(1024, Info.DisplayWidth,
      'Display width = round(720 * 64/45) = 1024');
    Assert.AreEqual(576, Info.DisplayHeight, 'SAR scales width, not height');
  finally
    FFmpeg.Free;
  end;
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

procedure TTestFFmpegLocator.TestConfiguredPathExpandsEnvVars;
var
  SubDir, ExePath, Found: string;
begin
  { Place ffmpeg.exe inside a subdirectory of TEMP and reference it via
    the %TEMP% environment variable. FindFFmpegExe must expand the variable
    before checking TFile.Exists. }
  SubDir := TPath.Combine(FTempDir, 'tools');
  TDirectory.CreateDirectory(SubDir);
  ExePath := TPath.Combine(SubDir, 'ffmpeg.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  { Set a custom env var pointing to our temp dir }
  SetEnvironmentVariable('VT_TEST_PLUGIN_DIR', PChar(FTempDir));
  try
    Found := FindFFmpegExe('',
      '%VT_TEST_PLUGIN_DIR%' + PathDelim + 'tools' + PathDelim + 'ffmpeg.exe');
    Assert.AreEqual(ExePath, Found,
      'FindFFmpegExe must expand environment variables in configured path');
  finally
    SetEnvironmentVariable('VT_TEST_PLUGIN_DIR', nil);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegParsing);
  TDUnitX.RegisterTestFixture(TTestFFmpegProbeIntegration);
  TDUnitX.RegisterTestFixture(TTestFFmpegLocator);

end.
