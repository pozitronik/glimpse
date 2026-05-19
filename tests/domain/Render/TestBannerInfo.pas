{ Tests for BannerInfo: data fields, formatting and population from
  TVideoInfo + filesystem. Verifies edge cases of the text formatter and
  that BuildBannerInfo copies every field accurately. }
unit TestBannerInfo;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBannerInfo = class
  public
    { FormatBannerLines }
    [Test] procedure BannerLines_FullInfo_ThreeLines;
    [Test] procedure BannerLines_NoAudio_OmitsAudioPart;
    [Test] procedure BannerLines_FileSizeFormatting;
    { FormatBannerLines edge cases }
    [Test] procedure BannerLines_AllEmpty_StillThreeLines;
    [Test] procedure BannerLines_ZeroDuration_OmitsDuration;
    [Test] procedure BannerLines_ByteRangeFileSize;
    [Test] procedure BannerLines_ShortDuration_NoHours;
    [Test] procedure BannerLines_AudioBitrate_Shown;
    [Test] procedure BannerLines_VideoBitrate_Shown;
    [Test] procedure BannerLines_NegativeDuration_OmitsDuration;
    [Test] procedure BannerLines_ExactHourDuration;
    [Test] procedure BannerLines_FpsOnly_NoSeparatorPrefix;
    [Test] procedure BannerLines_AudioOnly_NoVideoCodec;
    [Test] procedure BannerLines_AudioChannelsShown;
    [Test] procedure BannerLines_NoFileSize_OmitsSize;
    [Test] procedure BannerLines_GBFileSize;
    [Test] procedure BannerLines_AnamorphicShowsArrow;
    [Test] procedure BannerLines_DisplayMatchesStorage_NoArrow;
    [Test] procedure BannerLines_DisplayZero_FallsBackToStorage;
    { BuildBannerInfo }
    [Test] procedure BuildBannerInfo_ExistingFile_CopiesAllFields;
    [Test] procedure BuildBannerInfo_MissingFile_FileSizeIsZero;
    [Test] procedure BuildBannerInfo_EmptyVideoInfo_ReturnsZeroedRecord;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  BannerInfo, VideoInfo;

{ FormatBannerLines }

procedure TTestBannerInfo.BannerLines_FullInfo_ThreeLines;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'C:\Videos\test.mp4';
  Info.FileSizeBytes := 1536 * 1024 * 1024; { 1.5 GB }
  Info.DurationSec := 3723.5; { 1:02:03 }
  Info.Width := 1920;
  Info.Height := 1080;
  Info.VideoCodec := 'h264';
  Info.VideoBitrateKbps := 5000;
  Info.Fps := 23.976;
  Info.AudioCodec := 'aac';
  Info.AudioSampleRate := 48000;
  Info.AudioChannels := 'stereo';
  Info.AudioBitrateKbps := 128;

  Lines := FormatBannerLines(Info);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.IsTrue(Lines[0].Contains('test.mp4'), 'Line 1 should contain filename');
  Assert.IsTrue(Lines[0].Contains('GB'), 'Line 1 should show file size');
  Assert.IsTrue(Lines[1].Contains('1920x1080'), 'Line 2 should show resolution');
  Assert.IsTrue(Pos('Duration:', Lines[1]) > 0,
    Format('Line 2 should show duration, got: [%s]', [Lines[1]]));
  Assert.IsTrue(Lines[1].Contains('23.976'), 'Line 2 should show fps');
  Assert.IsTrue(Lines[2].Contains('h264'), 'Line 3 should show video codec');
  Assert.IsTrue(Lines[2].Contains('aac'), 'Line 3 should show audio codec');
  Assert.IsTrue(Lines[2].Contains('48000'), 'Line 3 should show sample rate');
end;

procedure TTestBannerInfo.BannerLines_NoAudio_OmitsAudioPart;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'silent.mp4';
  Info.DurationSec := 60;
  Info.Width := 640;
  Info.Height := 480;
  Info.VideoCodec := 'h264';
  { AudioCodec empty = no audio }

  Lines := FormatBannerLines(Info);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.IsTrue(Lines[2].Contains('h264'), 'Line 3 should show video codec');
  Assert.IsFalse(Lines[2].Contains('Audio'), 'No audio section when codec is empty');
end;

procedure TTestBannerInfo.BannerLines_FileSizeFormatting;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { MB range }
  Info := Default(TBannerInfo);
  Info.FileName := 'small.mp4';
  Info.FileSizeBytes := 50 * 1024 * 1024;
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[0].Contains('MB'), 'Should format as MB');

  { KB range }
  Info.FileSizeBytes := 500 * 1024;
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[0].Contains('KB'), 'Should format as KB');
end;

{ FormatBannerLines edge cases }

procedure TTestBannerInfo.BannerLines_AllEmpty_StillThreeLines;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { Default-initialized record with no meaningful data }
  Info := Default(TBannerInfo);
  Lines := FormatBannerLines(Info);
  Assert.AreEqual(3, Integer(Length(Lines)),
    'Must always return exactly 3 lines');
  Assert.IsTrue(Lines[0].Contains('File:'),
    'Line 1 should still have the File: prefix');
end;

procedure TTestBannerInfo.BannerLines_ZeroDuration_OmitsDuration;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.DurationSec := 0;
  Info.Width := 640;
  Info.Height := 480;
  Lines := FormatBannerLines(Info);
  Assert.IsFalse(Lines[1].Contains('Duration:'),
    'Zero duration should omit the Duration field');
  Assert.IsTrue(Lines[1].Contains('640x480'),
    'Resolution should still appear');
end;

procedure TTestBannerInfo.BannerLines_ByteRangeFileSize;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { Files under 1 KB should format as bytes }
  Info := Default(TBannerInfo);
  Info.FileName := 'tiny.mp4';
  Info.FileSizeBytes := 512;
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[0].Contains('512 B'),
    'Sub-KB file size should format as bytes');
end;

procedure TTestBannerInfo.BannerLines_ShortDuration_NoHours;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { Duration under 1 hour should show M:SS without hours }
  Info := Default(TBannerInfo);
  Info.FileName := 'clip.mp4';
  Info.DurationSec := 125; { 2:05 }
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[1].Contains('2:05'),
    Format('Short duration should show M:SS, got: [%s]', [Lines[1]]));
  Assert.IsFalse(Lines[1].Contains('0:02:05'),
    'Should not have hour prefix for short clips');
end;

procedure TTestBannerInfo.BannerLines_AudioBitrate_Shown;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.AudioCodec := 'aac';
  Info.AudioBitrateKbps := 320;
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[2].Contains('320 kbps'),
    'Audio bitrate should appear in codec line');
end;

procedure TTestBannerInfo.BannerLines_VideoBitrate_Shown;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.VideoCodec := 'h264';
  Info.VideoBitrateKbps := 5000;
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[2].Contains('5000 kbps'),
    Format('Video bitrate should appear, got: [%s]', [Lines[2]]));
end;

procedure TTestBannerInfo.BannerLines_NegativeDuration_OmitsDuration;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.DurationSec := -10.0;
  Info.Width := 320;
  Info.Height := 240;
  Lines := FormatBannerLines(Info);
  Assert.IsFalse(Lines[1].Contains('Duration:'),
    'Negative duration should omit the Duration field');
  Assert.IsTrue(Lines[1].Contains('320x240'),
    'Resolution should still appear with negative duration');
end;

procedure TTestBannerInfo.BannerLines_ExactHourDuration;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'long.mp4';
  Info.DurationSec := 3600; { exactly 1 hour }
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[1].Contains('1:00:00'),
    Format('1 hour should show 1:00:00, got: [%s]', [Lines[1]]));
end;

procedure TTestBannerInfo.BannerLines_FpsOnly_NoSeparatorPrefix;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { FPS only, no duration, no resolution: line should start with fps, no leading separator }
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.Fps := 29.970;
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[1].Contains('29.970 fps'),
    Format('FPS should appear, got: [%s]', [Lines[1]]));
  Assert.IsFalse(Lines[1].StartsWith('  |'),
    'Line should not start with a separator when FPS is the only field');
end;

procedure TTestBannerInfo.BannerLines_AudioOnly_NoVideoCodec;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { Audio codec present, video codec empty: no pipe separator, no "Video:" prefix }
  Info := Default(TBannerInfo);
  Info.FileName := 'audio_only.mp4';
  Info.AudioCodec := 'mp3';
  Info.AudioSampleRate := 44100;
  Lines := FormatBannerLines(Info);
  Assert.IsFalse(Lines[2].Contains('Video:'),
    'No Video: prefix when video codec is empty');
  Assert.IsTrue(Lines[2].Contains('Audio: mp3'),
    Format('Audio codec should appear, got: [%s]', [Lines[2]]));
  Assert.IsTrue(Lines[2].Contains('44100 Hz'),
    'Audio sample rate should appear');
  Assert.IsFalse(Lines[2].Contains('|'),
    'No pipe separator when only audio is present');
end;

procedure TTestBannerInfo.BannerLines_AudioChannelsShown;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.AudioCodec := 'aac';
  Info.AudioChannels := '5.1(side)';
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[2].Contains('5.1(side)'),
    Format('Audio channels should appear, got: [%s]', [Lines[2]]));
end;

procedure TTestBannerInfo.BannerLines_NoFileSize_OmitsSize;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { FileSizeBytes = 0: no size section }
  Info := Default(TBannerInfo);
  Info.FileName := 'test.mp4';
  Info.FileSizeBytes := 0;
  Lines := FormatBannerLines(Info);
  Assert.IsFalse(Lines[0].Contains('Size:'),
    'Zero file size should omit Size field');
end;

procedure TTestBannerInfo.BannerLines_GBFileSize;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  Info := Default(TBannerInfo);
  Info.FileName := 'huge.mp4';
  Info.FileSizeBytes := Int64(3) * 1024 * 1024 * 1024; { 3 GB }
  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[0].Contains('3.00 GB'),
    Format('3 GB file should show GB, got: [%s]', [Lines[0]]));
end;

procedure TTestBannerInfo.BannerLines_AnamorphicShowsArrow;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { When Display dims differ from storage (anamorphic source), the banner
    must show both with an arrow so the user understands why the saved
    image is wider than the "WxH" reported by mediainfo et al. }
  Info := Default(TBannerInfo);
  Info.FileName := 'pal.mp4';
  Info.Width := 720;
  Info.Height := 576;
  Info.DisplayWidth := 1024;
  Info.DisplayHeight := 576;

  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[1].Contains('720x576 -> 1024x576'),
    Format('Anamorphic banner must show "Sw x Sh -> Dw x Dh", got: [%s]',
      [Lines[1]]));
end;

procedure TTestBannerInfo.BannerLines_DisplayMatchesStorage_NoArrow;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { Square-pixel source (Display = Storage): banner must show plain "WxH"
    with no arrow. Otherwise non-anamorphic videos would carry confusing
    "1920x1080 -> 1920x1080" noise. }
  Info := Default(TBannerInfo);
  Info.FileName := 'square.mp4';
  Info.Width := 1920;
  Info.Height := 1080;
  Info.DisplayWidth := 1920;
  Info.DisplayHeight := 1080;

  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[1].Contains('1920x1080'), 'Resolution still printed');
  Assert.IsFalse(Lines[1].Contains('->'),
    Format('Arrow must be absent when storage = display, got: [%s]',
      [Lines[1]]));
end;

procedure TTestBannerInfo.BannerLines_DisplayZero_FallsBackToStorage;
var
  Info: TBannerInfo;
  Lines: TArray<string>;
begin
  { Older callers may still build TBannerInfo by hand without populating
    Display dims. Falling back to plain "WxH" rather than emitting
    "WxH -> 0x0" keeps the banner sane in that case. }
  Info := Default(TBannerInfo);
  Info.FileName := 'legacy.mp4';
  Info.Width := 640;
  Info.Height := 480;
  { DisplayWidth/Height left at 0 }

  Lines := FormatBannerLines(Info);
  Assert.IsTrue(Lines[1].Contains('640x480'), 'Fallback shows storage dims');
  Assert.IsFalse(Lines[1].Contains('->'),
    'No arrow when display dims are unknown');
end;

procedure TTestBannerInfo.BuildBannerInfo_ExistingFile_CopiesAllFields;
var
  TempFile: string;
  VideoInfo: TVideoInfo;
  Banner: TBannerInfo;
begin
  { A real file on disk so BuildBannerInfo's TFile.GetSize branch runs.
    Every TVideoInfo field is set to a distinct sentinel so we can prove
    each is copied (not silently dropped or remapped). }
  TempFile := TPath.Combine(TPath.GetTempPath,
    'VT_BuildBanner_' + TGuid.NewGuid.ToString + '.bin');
  TFile.WriteAllBytes(TempFile, TBytes.Create($DE, $AD, $BE, $EF, $00, $11, $22));
  try
    VideoInfo := Default(TVideoInfo);
    VideoInfo.Duration := 123.5;
    VideoInfo.Width := 1920;
    VideoInfo.Height := 1080;
    VideoInfo.DisplayWidth := 1920;
    VideoInfo.DisplayHeight := 1080;
    VideoInfo.VideoCodec := 'h264';
    VideoInfo.VideoBitrateKbps := 4500;
    VideoInfo.Fps := 29.97;
    VideoInfo.AudioCodec := 'aac';
    VideoInfo.AudioSampleRate := 48000;
    VideoInfo.AudioChannels := 'stereo';
    VideoInfo.AudioBitrateKbps := 192;
    {IsValid is a derived method (Duration > 0); set Duration above to
     make IsValid return True.}

    Banner := BuildBannerInfo(TempFile, VideoInfo);

    Assert.AreEqual(TempFile, Banner.FileName);
    Assert.AreEqual<Int64>(7, Banner.FileSizeBytes);
    Assert.AreEqual(123.5, Banner.DurationSec, 0.001);
    Assert.AreEqual(1920, Banner.Width);
    Assert.AreEqual(1080, Banner.Height);
    Assert.AreEqual(1920, Banner.DisplayWidth);
    Assert.AreEqual(1080, Banner.DisplayHeight);
    Assert.AreEqual('h264', Banner.VideoCodec);
    Assert.AreEqual(4500, Banner.VideoBitrateKbps);
    Assert.AreEqual(29.97, Banner.Fps, 0.001);
    Assert.AreEqual('aac', Banner.AudioCodec);
    Assert.AreEqual(48000, Banner.AudioSampleRate);
    Assert.AreEqual('stereo', Banner.AudioChannels);
    Assert.AreEqual(192, Banner.AudioBitrateKbps);
  finally
    if TFile.Exists(TempFile) then
      TFile.Delete(TempFile);
  end;
end;

procedure TTestBannerInfo.BuildBannerInfo_MissingFile_FileSizeIsZero;
var
  Missing: string;
  VideoInfo: TVideoInfo;
  Banner: TBannerInfo;
begin
  { Defensive: a probe could succeed and the file then disappear before
    BuildBannerInfo runs (network share, antivirus quarantine, etc.).
    The function must return FileSizeBytes=0 - not raise - so the banner
    still renders with the rest of the metadata. }
  Missing := TPath.Combine(TPath.GetTempPath,
    'VT_BuildBanner_missing_' + TGuid.NewGuid.ToString + '.bin');
  Assert.IsFalse(TFile.Exists(Missing), 'Pre-condition: file must not exist');

  VideoInfo := Default(TVideoInfo);
  VideoInfo.Duration := 60.0;
  VideoInfo.Width := 640;
  VideoInfo.Height := 480;
  VideoInfo.VideoCodec := 'mpeg4';

  Banner := BuildBannerInfo(Missing, VideoInfo);

  Assert.AreEqual(Missing, Banner.FileName);
  Assert.AreEqual<Int64>(0, Banner.FileSizeBytes);
  { The other fields must still come through unchanged }
  Assert.AreEqual(60.0, Banner.DurationSec, 0.001);
  Assert.AreEqual(640, Banner.Width);
  Assert.AreEqual(480, Banner.Height);
  Assert.AreEqual('mpeg4', Banner.VideoCodec);
end;

procedure TTestBannerInfo.BuildBannerInfo_EmptyVideoInfo_ReturnsZeroedRecord;
var
  Banner: TBannerInfo;
begin
  { An empty filename + Default(TVideoInfo) must produce a fully-zeroed
    TBannerInfo. Belt-and-braces against accidental field initialization
    creeping in (e.g. someone setting Width := 1 by mistake). }
  Banner := BuildBannerInfo('', Default(TVideoInfo));
  Assert.AreEqual('', Banner.FileName);
  Assert.AreEqual<Int64>(0, Banner.FileSizeBytes);
  Assert.AreEqual(0.0, Banner.DurationSec, 0.001);
  Assert.AreEqual(0, Banner.Width);
  Assert.AreEqual(0, Banner.Height);
  Assert.AreEqual(0, Banner.DisplayWidth);
  Assert.AreEqual(0, Banner.DisplayHeight);
  Assert.AreEqual('', Banner.VideoCodec);
  Assert.AreEqual(0, Banner.VideoBitrateKbps);
  Assert.AreEqual(0.0, Banner.Fps, 0.001);
  Assert.AreEqual('', Banner.AudioCodec);
  Assert.AreEqual(0, Banner.AudioSampleRate);
  Assert.AreEqual('', Banner.AudioChannels);
  Assert.AreEqual(0, Banner.AudioBitrateKbps);
end;

end.
