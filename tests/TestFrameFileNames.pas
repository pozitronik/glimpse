unit TestFrameFileNames;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFrameFileNames = class
  public
    [Test] procedure TestSaveFormatExtensionPNG;
    [Test] procedure TestSaveFormatExtensionJPEG;
    [Test] procedure TestGenerateFrameFileNamePNG;
    [Test] procedure TestGenerateFrameFileNameJPEG;
    [Test] procedure TestGenerateFrameFileNameWithPath;
    [Test] procedure TestGenerateFrameFileNameZeroOffset;
    [Test] procedure TestGenerateFrameFileNameLargeIndex;
    [Test] procedure TestGenerateFrameFileNameDoubleExtension;
    [Test] procedure TestGenerateFrameFileNameEmptyInput;
    [Test] procedure TestGenerateFrameFileNameIndexOver99;
    [Test] procedure TestGenerateFrameFileNameNegativeOffset;
    [Test] procedure TestGenerateFrameFileNameLargeOffset;
    [Test] procedure TestGenerateFrameFileNameSpacesInName;
  end;

implementation

uses
  uSettings, uFrameFileNames;

procedure TTestFrameFileNames.TestSaveFormatExtensionPNG;
begin
  Assert.AreEqual('.png', SaveFormatExtension(sfPNG));
end;

procedure TTestFrameFileNames.TestSaveFormatExtensionJPEG;
begin
  Assert.AreEqual('.jpg', SaveFormatExtension(sfJPEG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNamePNG;
begin
  { index 0 -> frame_01, 12.5s -> 00-00-12.500 }
  Assert.AreEqual('video_frame_01_00-00-12.500.png',
    GenerateFrameFileName('video.mp4', 0, 12.5, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameJPEG;
begin
  { index 3 -> frame_04, 61.123s -> 00-01-01.123 }
  Assert.AreEqual('movie_frame_04_00-01-01.123.jpg',
    GenerateFrameFileName('movie.avi', 3, 61.123, sfJPEG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameWithPath;
begin
  { Full path should be stripped to basename only }
  Assert.AreEqual('video_frame_01_00-00-01.000.png',
    GenerateFrameFileName('C:\dir\sub\video.mp4', 0, 1.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameZeroOffset;
begin
  Assert.AreEqual('clip_frame_01_00-00-00.000.png',
    GenerateFrameFileName('clip.mkv', 0, 0.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameLargeIndex;
begin
  { index 98 -> frame_99 (two digits) }
  Assert.AreEqual('v_frame_99_00-00-05.000.png',
    GenerateFrameFileName('v.mp4', 98, 5.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameDoubleExtension;
begin
  { Only the last extension should be stripped }
  Assert.AreEqual('video.part_frame_01_00-00-01.000.jpg',
    GenerateFrameFileName('video.part.mp4', 0, 1.0, sfJPEG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameEmptyInput;
begin
  { Empty filename produces just the frame suffix }
  Assert.AreEqual('_frame_01_00-00-01.000.png',
    GenerateFrameFileName('', 0, 1.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameIndexOver99;
begin
  { Index 99 -> frame_100; %.2d widens naturally beyond 2 digits }
  Assert.AreEqual('v_frame_100_00-00-01.000.png',
    GenerateFrameFileName('v.mp4', 99, 1.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameNegativeOffset;
begin
  { Negative offset clamps to zero in FormatTimecode }
  Assert.AreEqual('v_frame_01_00-00-00.000.png',
    GenerateFrameFileName('v.mp4', 0, -5.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameLargeOffset;
begin
  { 360000s = 100 hours; verifies hours exceed 2 digits gracefully }
  Assert.AreEqual('v_frame_01_100-00-00.000.png',
    GenerateFrameFileName('v.mp4', 0, 360000.0, sfPNG));
end;

procedure TTestFrameFileNames.TestGenerateFrameFileNameSpacesInName;
begin
  { Spaces in filename are preserved as-is }
  Assert.AreEqual('my video_frame_01_00-00-01.000.png',
    GenerateFrameFileName('my video.mp4', 0, 1.0, sfPNG));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameFileNames);

end.
