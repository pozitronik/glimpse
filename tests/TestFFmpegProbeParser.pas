unit TestFFmpegProbeParser;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegProbeParser = class
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
    {Pins the "tolerates extra whitespace before the token" property
     that ScanNumberBeforeToken introduced (step 54). The old open-coded
     parser did NOT skip whitespace for ParseAudioSampleRate and would
     return 0 for "48000   Hz"; the helper now handles either spacing.}
    [Test] procedure TestParseAudioSampleRateAllowsExtraSpaces;
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

implementation

uses
  System.SysUtils,
  uFFmpegProbeParser;

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

{ TTestFFmpegProbeParser: Duration }

procedure TTestFFmpegProbeParser.TestParseDurationStandard;
begin
  Assert.AreEqual(5025.67, ParseDuration('Duration: 01:23:45.67, start: 0.0'), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseDurationZero;
begin
  Assert.AreEqual(0.0, ParseDuration('Duration: 00:00:00.00, start: 0.0'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseDurationShort;
begin
  Assert.AreEqual(5.5, ParseDuration('Duration: 00:00:05.50'), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseDurationLong;
begin
  Assert.AreEqual(9000.0, ParseDuration('Duration: 02:30:00.00'), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseDurationThreeDigitFraction;
begin
  Assert.AreEqual(90.123, ParseDuration('Duration: 00:01:30.123'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseDurationNoFraction;
begin
  { Some edge builds may omit the fractional part }
  Assert.AreEqual(90.0, ParseDuration('Duration: 00:01:30, start: 0.0'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseDurationFullOutput;
begin
  { Parse from realistic multi-line ffmpeg output }
  Assert.AreEqual(630.5, ParseDuration(SAMPLE_FFMPEG_OUTPUT), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseDurationMissing;
begin
  Assert.AreEqual(-1.0, ParseDuration('no duration here'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseDurationNA;
begin
  Assert.AreEqual(-1.0, ParseDuration('Duration: N/A, bitrate: N/A'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseDurationMalformed;
begin
  Assert.AreEqual(-1.0, ParseDuration('Duration: GARBAGE'), 0.001);
  Assert.AreEqual(-1.0, ParseDuration('Duration: 01:02'), 0.001);
  Assert.AreEqual(-1.0, ParseDuration('Duration: ::'), 0.001);
end;

{ TTestFFmpegProbeParser: Resolution }

procedure TTestFFmpegProbeParser.TestParseResolution1080p;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution('Stream #0:0: Video: h264, yuv420p, 1920x1080, 30 fps', W, H));
  Assert.AreEqual(1920, W);
  Assert.AreEqual(1080, H);
end;

procedure TTestFFmpegProbeParser.TestParseResolution4K;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution('Video: hevc, yuv420p, 3840x2160', W, H));
  Assert.AreEqual(3840, W);
  Assert.AreEqual(2160, H);
end;

procedure TTestFFmpegProbeParser.TestParseResolutionSmall;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution('Video: mpeg4, yuv420p, 320x240, 25 fps', W, H));
  Assert.AreEqual(320, W);
  Assert.AreEqual(240, H);
end;

procedure TTestFFmpegProbeParser.TestParseResolutionNoVideo;
var
  W, H: Integer;
begin
  Assert.IsFalse(ParseResolution('Stream #0:0: Audio: aac, 44100 Hz, stereo', W, H));
  Assert.AreEqual(0, W);
  Assert.AreEqual(0, H);
end;

procedure TTestFFmpegProbeParser.TestParseResolutionSkipsHexValues;
var
  W, H: Integer;
begin
  { Hex values like 0x31637661 should not produce false matches }
  Assert.IsTrue(ParseResolution(
    'Video: h264 (avc1 / 0x31637661), yuv420p, 1280x720', W, H));
  Assert.AreEqual(1280, W);
  Assert.AreEqual(720, H);
end;

procedure TTestFFmpegProbeParser.TestParseResolutionFullOutput;
var
  W, H: Integer;
begin
  Assert.IsTrue(ParseResolution(SAMPLE_FFMPEG_OUTPUT, W, H));
  Assert.AreEqual(1920, W);
  Assert.AreEqual(1080, H);
end;

{ TTestFFmpegProbeParser: Codec }

procedure TTestFFmpegProbeParser.TestParseCodecH264;
begin
  Assert.AreEqual('h264', ParseVideoCodec('Video: h264 (High), yuv420p'));
end;

procedure TTestFFmpegProbeParser.TestParseCodecHevc;
begin
  Assert.AreEqual('hevc', ParseVideoCodec('Video: hevc (Main 10), yuv420p10le'));
end;

procedure TTestFFmpegProbeParser.TestParseCodecMpeg2;
begin
  Assert.AreEqual('mpeg2video', ParseVideoCodec('Video: mpeg2video, yuv420p'));
end;

procedure TTestFFmpegProbeParser.TestParseCodecNoVideo;
begin
  Assert.AreEqual('', ParseVideoCodec('Audio: aac (LC), 44100 Hz'));
end;

{ TTestFFmpegProbeParser: Bitrate }

procedure TTestFFmpegProbeParser.TestParseBitrateFromDurationLine;
begin
  Assert.AreEqual(2000, ParseBitrate('Duration: 00:10:30.50, start: 0.000000, bitrate: 2000 kb/s'));
end;

procedure TTestFFmpegProbeParser.TestParseBitrateFullOutput;
begin
  Assert.AreEqual(2000, ParseBitrate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegProbeParser.TestParseBitrateMissing;
begin
  Assert.AreEqual(0, ParseBitrate('Duration: 00:01:00.00, start: 0.0'));
end;

{ TTestFFmpegProbeParser: FPS }

procedure TTestFFmpegProbeParser.TestParseFpsInteger;
begin
  Assert.AreEqual(30.0, ParseFps('Video: h264, yuv420p, 1920x1080, 30 fps'), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseFpsFractional;
begin
  Assert.AreEqual(23.976, ParseFps('Video: h264, yuv420p, 1920x1080, 23.976 fps'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseFpsFullOutput;
begin
  Assert.AreEqual(30.0, ParseFps(SAMPLE_FFMPEG_OUTPUT), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseFpsNoVideo;
begin
  Assert.AreEqual(0.0, ParseFps('Audio: aac, 44100 Hz, stereo'), 0.001);
end;

{ TTestFFmpegProbeParser: Video bitrate }

procedure TTestFFmpegProbeParser.TestParseVideoBitrateFromStream;
begin
  Assert.AreEqual(1800, ParseVideoBitrate(
    'Video: h264 (High), yuv420p, 1920x1080, 1800 kb/s, 30 fps'));
end;

procedure TTestFFmpegProbeParser.TestParseVideoBitrateFullOutput;
begin
  Assert.AreEqual(1800, ParseVideoBitrate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegProbeParser.TestParseVideoBitrateMissing;
begin
  Assert.AreEqual(0, ParseVideoBitrate('Video: h264, yuv420p, 1920x1080, 30 fps'));
end;

{ TTestFFmpegProbeParser: Audio codec }

procedure TTestFFmpegProbeParser.TestParseAudioCodecAac;
begin
  Assert.AreEqual('aac', ParseAudioCodec('Audio: aac (LC), 44100 Hz, stereo'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioCodecMp3;
begin
  Assert.AreEqual('mp3', ParseAudioCodec('Audio: mp3, 44100 Hz, stereo, fltp, 320 kb/s'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioCodecFullOutput;
begin
  Assert.AreEqual('aac', ParseAudioCodec(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegProbeParser.TestParseAudioCodecNoAudio;
begin
  Assert.AreEqual('', ParseAudioCodec('Video: h264, 1920x1080'));
end;

{ TTestFFmpegProbeParser: Audio sample rate }

procedure TTestFFmpegProbeParser.TestParseAudioSampleRate44100;
begin
  Assert.AreEqual(44100, ParseAudioSampleRate('Audio: aac, 44100 Hz, stereo'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioSampleRate48000;
begin
  Assert.AreEqual(48000, ParseAudioSampleRate('Audio: aac (LC), 48000 Hz, 5.1, fltp'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioSampleRateFullOutput;
begin
  Assert.AreEqual(44100, ParseAudioSampleRate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegProbeParser.TestParseAudioSampleRateNoAudio;
begin
  Assert.AreEqual(0, ParseAudioSampleRate('Video: h264, 1920x1080'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioSampleRateAllowsExtraSpaces;
begin
  {The unified ScanNumberBeforeToken helper skips whitespace backward
   from the token, so an Audio line with extra spaces between the
   number and "Hz" still parses. This is a deliberate change from the
   pre-step-54 inline code which only handled the canonical one-space
   "48000 Hz" form.}
  Assert.AreEqual(48000,
    ParseAudioSampleRate('Audio: aac (LC), 48000   Hz, 5.1, fltp'),
    'ScanNumberBeforeToken must tolerate multiple spaces before the token');
end;

{ TTestFFmpegProbeParser: Audio channels }

procedure TTestFFmpegProbeParser.TestParseAudioChannelsStereo;
begin
  Assert.AreEqual('stereo', ParseAudioChannels('Audio: aac, 44100 Hz, stereo, fltp'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannelsMono;
begin
  Assert.AreEqual('mono', ParseAudioChannels('Audio: aac, 22050 Hz, mono, fltp'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannels51;
begin
  Assert.AreEqual('5.1', ParseAudioChannels('Audio: ac3, 48000 Hz, 5.1, fltp, 384 kb/s'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannelsFullOutput;
begin
  Assert.AreEqual('stereo', ParseAudioChannels(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannelsNoAudio;
begin
  Assert.AreEqual('', ParseAudioChannels('Video: h264, 1920x1080'));
end;

{ TTestFFmpegProbeParser: Audio bitrate }

procedure TTestFFmpegProbeParser.TestParseAudioBitrateFromStream;
begin
  Assert.AreEqual(128, ParseAudioBitrate('Audio: aac (LC), 44100 Hz, stereo, fltp, 128 kb/s'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioBitrateFullOutput;
begin
  Assert.AreEqual(128, ParseAudioBitrate(SAMPLE_FFMPEG_OUTPUT));
end;

procedure TTestFFmpegProbeParser.TestParseAudioBitrateNoAudio;
begin
  Assert.AreEqual(0, ParseAudioBitrate('Video: h264, 1920x1080'));
end;

{ TTestFFmpegProbeParser: Edge cases }

procedure TTestFFmpegProbeParser.TestParseDurationEmptyString;
begin
  Assert.AreEqual(-1.0, ParseDuration(''), 0.001, 'Empty string should return -1');
end;

procedure TTestFFmpegProbeParser.TestParseDurationTrailingDot;
begin
  { "00:01:30." has a dot but no fractional digits: should reject as malformed }
  Assert.AreEqual(-1.0, ParseDuration('Duration: 00:01:30.'), 0.001,
    'Trailing dot without fraction should return -1');
end;

procedure TTestFFmpegProbeParser.TestParseResolutionSingleDigitRejected;
var
  W, H: Integer;
begin
  { Single-digit dimensions (e.g. 8x8) must be rejected to avoid hex false matches }
  Assert.IsFalse(ParseResolution('Video: h264, 8x8, 30 fps', W, H),
    'Single-digit resolution should be rejected');
end;

procedure TTestFFmpegProbeParser.TestParseVideoCodecEmptyInput;
begin
  Assert.AreEqual('', ParseVideoCodec(''), 'Empty string should return empty codec');
end;

procedure TTestFFmpegProbeParser.TestParseVideoCodecExtraSpaces;
begin
  { Multiple spaces between "Video:" and codec name should be skipped }
  Assert.AreEqual('vp9', ParseVideoCodec('Video:    vp9 (Profile 0)'));
end;

procedure TTestFFmpegProbeParser.TestParseFpsFractional2997;
begin
  Assert.AreEqual(29.97,
    ParseFps('Stream #0:0: Video: h264, 1920x1080, 29.97 fps'), 0.01);
end;

procedure TTestFFmpegProbeParser.TestParseFpsNoFpsToken;
begin
  { Video line without " fps" token returns 0 }
  Assert.AreEqual(Double(0),
    ParseFps('Stream #0:0: Video: h264, 1920x1080, 30 tbr'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseBitrateNoKbsToken;
begin
  { Duration line without "kb/s" returns 0 }
  Assert.AreEqual(0, ParseBitrate('Duration: 00:01:00.00, start: 0.0'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannels71;
begin
  Assert.AreEqual('7.1',
    ParseAudioChannels('Stream #0:1: Audio: eac3, 48000 Hz, 7.1, fltp, 640 kb/s'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannelsQuad;
begin
  { "quad" is a valid ffmpeg channel layout }
  Assert.AreEqual('quad',
    ParseAudioChannels('Stream #0:1: Audio: pcm_s16le, 44100 Hz, quad, s16'));
end;

procedure TTestFFmpegProbeParser.TestParseAudioChannelsUnknownLayout;
begin
  { Channel layout not in our known list returns empty }
  Assert.AreEqual('',
    ParseAudioChannels('Stream #0:1: Audio: aac, 44100 Hz, fltp, 128 kb/s'));
end;

procedure TTestFFmpegProbeParser.TestParseNoAudioStream;
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

procedure TTestFFmpegProbeParser.TestParseVideoBitrateNoVideoStream;
begin
  Assert.AreEqual(0, ParseVideoBitrate('Stream #0:0: Audio: aac, 44100 Hz'));
end;

procedure TTestFFmpegProbeParser.TestParseResolutionAtEndOfString;
var
  W, H: Integer;
begin
  { Resolution pattern at the very end of the string, no trailing characters }
  Assert.IsTrue(ParseResolution('Stream #0:0: Video: h264, 1920x1080', W, H),
    'Should parse resolution at end of string');
  Assert.AreEqual(1920, W);
  Assert.AreEqual(1080, H);
end;

procedure TTestFFmpegProbeParser.TestParseDurationSubSecond;
begin
  { Duration less than 1 second }
  Assert.AreEqual(0.50, ParseDuration('Duration: 00:00:00.50,'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestParseDurationSingleDigitFraction;
begin
  { Single fractional digit: 0.5 seconds, not 0.05 }
  Assert.AreEqual(90.5, ParseDuration('Duration: 00:01:30.5,'), 0.001);
end;

procedure TTestFFmpegProbeParser.TestExtractStreamLineVideo;
var
  Input: string;
begin
  { ExtractStreamLine returns from the prefix position to end of line }
  Input := 'Stream #0:0: Video: h264, 1920x1080' + #13#10 +
           'Stream #0:1: Audio: aac, 48000 Hz';
  Assert.AreEqual('Video: h264, 1920x1080',
    ExtractStreamLine(Input, 'Video:'));
end;

procedure TTestFFmpegProbeParser.TestExtractStreamLineNoMatch;
begin
  Assert.AreEqual('', ExtractStreamLine('no streams here', 'Video:'));
end;

{ Sample aspect ratio parsing }

procedure TTestFFmpegProbeParser.TestParseSampleAspectAnamorphic;
var
  N, D: Integer;
begin
  Assert.IsTrue(ParseSampleAspect(
    '  Stream #0:0: Video: h264, yuv420p, 720x576 [SAR 64:45 DAR 16:9], 25 fps',
    N, D));
  Assert.AreEqual(64, N);
  Assert.AreEqual(45, D);
end;

procedure TTestFFmpegProbeParser.TestParseSampleAspectSquare;
var
  N, D: Integer;
begin
  Assert.IsTrue(ParseSampleAspect(
    '  Stream #0:0: Video: h264, yuv420p, 1920x1080 [SAR 1:1 DAR 16:9], 60 fps',
    N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegProbeParser.TestParseSampleAspectMissing;
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

procedure TTestFFmpegProbeParser.TestParseSampleAspectZeroNumerator;
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

procedure TTestFFmpegProbeParser.TestParseSampleAspectZeroDenominator;
var
  N, D: Integer;
begin
  Assert.IsFalse(ParseSampleAspect(
    '  Stream #0:0: Video: h264, 1920x1080 [SAR 1:0 DAR 16:9], 30 fps',
    N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegProbeParser.TestParseSampleAspectNoVideoLine;
var
  N, D: Integer;
begin
  Assert.IsFalse(ParseSampleAspect('  Stream #0:0: Audio: aac, 44100 Hz, stereo', N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

procedure TTestFFmpegProbeParser.TestParseSampleAspectFullOutput;
var
  N, D: Integer;
begin
  {SAMPLE_FFMPEG_OUTPUT carries [SAR 1:1 DAR 16:9] on its Video line.}
  Assert.IsTrue(ParseSampleAspect(SAMPLE_FFMPEG_OUTPUT, N, D));
  Assert.AreEqual(1, N);
  Assert.AreEqual(1, D);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegProbeParser);

end.
