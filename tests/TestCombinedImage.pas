{ Tests for uCombinedImage: combined grid rendering.
  Verifies layout geometry, background fill, nil-frame handling,
  and auto-column calculation without any settings dependency. }
unit TestCombinedImage;

interface

uses
  DUnitX.TestFramework, Vcl.Graphics;

type
  [TestFixture]
  TTestCombinedImage = class
  private
    { Creates a solid-color bitmap for testing }
    function MakeFrame(AWidth, AHeight: Integer; AColor: Integer): TBitmap;
  public
    { Empty input }
    [Test] procedure EmptyFrames_ReturnsNil;
    { Single frame }
    [Test] procedure SingleFrame_OutputMatchesFrameSize;
    { Grid geometry }
    [Test] procedure TwoFrames_AutoCols_Produces2x1;
    [Test] procedure FourFrames_AutoCols_Produces2x2;
    [Test] procedure FourFrames_ExplicitOneCols_Produces1x4;
    [Test] procedure ThreeFrames_TwoCols_Produces2x2Grid;
    { Gap calculations }
    [Test] procedure SingleFrame_GapDoesNotAffectSize;
    [Test] procedure TwoFrames_GapAddsCorrectly;
    [Test] procedure FourFrames_2x2_WithGap;
    { Background fill }
    [Test] procedure BackgroundFillsEntireCanvas;
    { Nil frames in array }
    [Test] procedure NilFrame_UsesDefaultCellSize;
    [Test] procedure MixedNilFrames_SkippedInRendering;
    { Columns clamped to frame count }
    [Test] procedure ColsExceedFrameCount_ClampedToFrameCount;
    { Timestamp overlay (no crash, correct pixel format) }
    [Test] procedure TimestampEnabled_DoesNotCrash;
    [Test] procedure TimestampDisabled_NoTextDrawn;
    { Large grid }
    [Test] procedure NineFrames_AutoCols_Produces3x3;
    { FormatBannerLines }
    [Test] procedure BannerLines_FullInfo_ThreeLines;
    [Test] procedure BannerLines_NoAudio_OmitsAudioPart;
    [Test] procedure BannerLines_FileSizeFormatting;
    { PrependBanner }
    [Test] procedure PrependBanner_EmptyLines_ReturnsCopy;
    [Test] procedure PrependBanner_AddsHeightAboveSource;
    [Test] procedure PrependBanner_PreservesSourceContent;
    [Test] procedure PrependBanner_NilSource_ReturnsEmptyBitmap;
    [Test] procedure PrependBanner_NarrowImage_SmallBanner;
    [Test] procedure PrependBanner_WideImage_LargerBanner;
    [Test] procedure PrependBanner_LongLine_Truncated;
  end;

implementation

uses
  System.SysUtils, System.Types, System.UITypes,
  uFrameOffsets, uCombinedImage;

{ Helper }

function TTestCombinedImage.MakeFrame(AWidth, AHeight: Integer;
  AColor: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AWidth, AHeight);
  Result.Canvas.Brush.Color := TColor(AColor);
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));
end;

{ Empty input }

procedure TTestCombinedImage.EmptyFrames_ReturnsNil;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  SetLength(Frames, 0);
  SetLength(Offsets, 0);
  R := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, False, 'Consolas', 9);
  Assert.IsNull(R);
end;

{ Single frame }

procedure TTestCombinedImage.SingleFrame_OutputMatchesFrameSize;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 1.0;
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width);
      Assert.AreEqual(80, R.Height);
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Grid geometry }

procedure TTestCombinedImage.TwoFrames_AutoCols_Produces2x1;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Ceil(Sqrt(2)) = 2 columns, 1 row }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, '2 cols * 50px');
      Assert.AreEqual(40, R.Height, '1 row * 40px');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedImage.FourFrames_AutoCols_Produces2x2;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { Ceil(Sqrt(4)) = 2 columns, 2 rows }
  SetLength(Frames, 4);
  for I := 0 to 3 do
    Frames[I] := MakeFrame(60, 40, 0);
  SetLength(Offsets, 4);
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(120, R.Width, '2 cols * 60px');
      Assert.AreEqual(80, R.Height, '2 rows * 40px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 3 do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedImage.FourFrames_ExplicitOneCols_Produces1x4;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  SetLength(Frames, 4);
  for I := 0 to 3 do
    Frames[I] := MakeFrame(60, 40, 0);
  SetLength(Offsets, 4);
  try
    R := RenderCombinedImage(Frames, Offsets, 1, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(60, R.Width, '1 col * 60px');
      Assert.AreEqual(160, R.Height, '4 rows * 40px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 3 do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedImage.ThreeFrames_TwoCols_Produces2x2Grid;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { 3 frames / 2 cols = 2 rows (last cell empty) }
  SetLength(Frames, 3);
  for I := 0 to 2 do
    Frames[I] := MakeFrame(50, 30, 0);
  SetLength(Offsets, 3);
  try
    R := RenderCombinedImage(Frames, Offsets, 2, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, '2 cols * 50px');
      Assert.AreEqual(60, R.Height, '2 rows * 30px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 2 do
      Frames[I].Free;
  end;
end;

{ Gap calculations }

procedure TTestCombinedImage.SingleFrame_GapDoesNotAffectSize;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Gap between columns/rows only; 1 frame = 0 gaps }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, 0);
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 10, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, 'No gap for single frame');
      Assert.AreEqual(80, R.Height, 'No gap for single frame');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.TwoFrames_GapAddsCorrectly;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { 2 frames in 1 row: width = 2*50 + 1*gap }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 5, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(105, R.Width, '2*50 + 1*5');
      Assert.AreEqual(40, R.Height, '1 row, no vertical gap');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedImage.FourFrames_2x2_WithGap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { 2x2 grid, gap=4: W=2*30+1*4=64, H=2*20+1*4=44 }
  SetLength(Frames, 4);
  for I := 0 to 3 do
    Frames[I] := MakeFrame(30, 20, 0);
  SetLength(Offsets, 4);
  try
    R := RenderCombinedImage(Frames, Offsets, 2, 4, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(64, R.Width, '2*30 + 1*4');
      Assert.AreEqual(44, R.Height, '2*20 + 1*4');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 3 do
      Frames[I].Free;
  end;
end;

{ Background fill }

procedure TTestCombinedImage.BackgroundFillsEntireCanvas;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
  BgColor: TColor;
begin
  { 3 frames in 2 cols = 2x2 grid with one empty cell.
    The empty cell area should be filled with background color. }
  BgColor := TColor($0000FF00); { green }
  SetLength(Frames, 3);
  for I := 0 to 2 do
    Frames[I] := MakeFrame(20, 20, Integer(clRed));
  SetLength(Offsets, 3);
  try
    R := RenderCombinedImage(Frames, Offsets, 2, 0, BgColor, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      { Check pixel in the empty cell (row 1, col 1) }
      Assert.AreEqual(Integer(BgColor),
        Integer(R.Canvas.Pixels[30, 30]),
        'Empty cell should be background color');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 2 do
      Frames[I].Free;
  end;
end;

{ Nil frames }

procedure TTestCombinedImage.NilFrame_UsesDefaultCellSize;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { All frames nil: falls back to default 320x240 }
  SetLength(Frames, 1);
  Frames[0] := nil;
  SetLength(Offsets, 1);
  R := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, False, 'Consolas', 9);
  Assert.IsNotNull(R);
  try
    Assert.AreEqual(320, R.Width, 'Default cell width');
    Assert.AreEqual(240, R.Height, 'Default cell height');
  finally
    R.Free;
  end;
end;

procedure TTestCombinedImage.MixedNilFrames_SkippedInRendering;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Frame 0 is real, frame 1 is nil.
    Output should be 2x1 grid using frame 0 dimensions.
    The nil cell should remain background-colored. }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(40, 30, Integer(clRed));
  Frames[1] := nil;
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 0, clWhite, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(80, R.Width, '2 cols * 40px');
      Assert.AreEqual(30, R.Height, '1 row * 30px');
      { Nil cell should be white (background) }
      Assert.AreEqual(Integer(clWhite),
        Integer(R.Canvas.Pixels[60, 15]),
        'Nil frame cell should be background');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Column clamping }

procedure TTestCombinedImage.ColsExceedFrameCount_ClampedToFrameCount;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { 2 frames, cols=10: should clamp to 2 cols }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, 10, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, 'Clamped to 2 cols * 50px');
      Assert.AreEqual(40, R.Height, '1 row * 40px');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

{ Timestamp }

procedure TTestCombinedImage.TimestampEnabled_DoesNotCrash;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, 0);
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, True, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(pf24bit, R.PixelFormat);
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.TimestampDisabled_NoTextDrawn;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  WithoutTS: TBitmap;
begin
  { Render same frame with and without timestamps.
    Without timestamps, the bottom-left corner should match the frame color. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clBlue));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 10.0;
  try
    WithoutTS := RenderCombinedImage(Frames, Offsets, 0, 0, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(WithoutTS);
    try
      { Bottom-left pixel should be the frame color when no timestamp }
      Assert.AreEqual(Integer(clBlue),
        Integer(WithoutTS.Canvas.Pixels[5, 140]),
        'Frame pixel without timestamp should be original color');
    finally
      WithoutTS.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Large grid }

procedure TTestCombinedImage.NineFrames_AutoCols_Produces3x3;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  I: Integer;
begin
  { Ceil(Sqrt(9)) = 3 columns, 3 rows }
  SetLength(Frames, 9);
  for I := 0 to 8 do
    Frames[I] := MakeFrame(40, 30, 0);
  SetLength(Offsets, 9);
  try
    R := RenderCombinedImage(Frames, Offsets, 0, 2, clBlack, False, 'Consolas', 9);
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(3 * 40 + 2 * 2, R.Width, '3 cols * 40px + 2 gaps * 2px');
      Assert.AreEqual(3 * 30 + 2 * 2, R.Height, '3 rows * 30px + 2 gaps * 2px');
    finally
      R.Free;
    end;
  finally
    for I := 0 to 8 do
      Frames[I].Free;
  end;
end;

{ FormatBannerLines }

procedure TTestCombinedImage.BannerLines_FullInfo_ThreeLines;
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

procedure TTestCombinedImage.BannerLines_NoAudio_OmitsAudioPart;
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

procedure TTestCombinedImage.BannerLines_FileSizeFormatting;
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

{ PrependBanner }

procedure TTestCombinedImage.PrependBanner_EmptyLines_ReturnsCopy;
var
  Src, R: TBitmap;
  EmptyLines: TArray<string>;
begin
  Src := MakeFrame(100, 80, Integer(clRed));
  try
    SetLength(EmptyLines, 0);
    R := PrependBanner(Src, EmptyLines);
    try
      Assert.AreEqual(100, R.Width);
      Assert.AreEqual(80, R.Height);
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.PrependBanner_AddsHeightAboveSource;
var
  Src, R: TBitmap;
begin
  Src := MakeFrame(200, 100, Integer(clBlue));
  try
    R := PrependBanner(Src, ['Line 1', 'Line 2']);
    try
      Assert.AreEqual(200, R.Width, 'Width should match source');
      Assert.IsTrue(R.Height > 100, 'Height should exceed source by banner');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.PrependBanner_PreservesSourceContent;
var
  Src, R: TBitmap;
  BannerH: Integer;
begin
  Src := MakeFrame(100, 50, Integer(clRed));
  try
    R := PrependBanner(Src, ['Test']);
    try
      BannerH := R.Height - 50;
      Assert.IsTrue(BannerH > 0, 'Banner should add height');
      { Check a pixel in the source area (below banner) }
      Assert.AreEqual(Integer(clRed),
        Integer(R.Canvas.Pixels[50, BannerH + 25]),
        'Source content should be preserved below banner');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.PrependBanner_NilSource_ReturnsEmptyBitmap;
var
  R: TBitmap;
begin
  R := PrependBanner(nil, ['Line']);
  try
    Assert.AreEqual(0, R.Width);
    Assert.AreEqual(0, R.Height);
  finally
    R.Free;
  end;
end;

procedure TTestCombinedImage.PrependBanner_NarrowImage_SmallBanner;
var
  Narrow, Wide, R1, R2: TBitmap;
  H1, H2: Integer;
begin
  { A narrow image should get a smaller font, hence shorter banner }
  Narrow := MakeFrame(200, 100, Integer(clBlack));
  Wide := MakeFrame(1200, 100, Integer(clBlack));
  try
    R1 := PrependBanner(Narrow, ['Test line']);
    R2 := PrependBanner(Wide, ['Test line']);
    try
      H1 := R1.Height - 100;
      H2 := R2.Height - 100;
      Assert.IsTrue(H1 > 0, 'Narrow banner should have height');
      Assert.IsTrue(H2 > H1, 'Wide image banner should be taller than narrow');
    finally
      R1.Free;
      R2.Free;
    end;
  finally
    Narrow.Free;
    Wide.Free;
  end;
end;

procedure TTestCombinedImage.PrependBanner_WideImage_LargerBanner;
var
  Src, R: TBitmap;
  BannerH: Integer;
begin
  { Font size caps at BANNER_FONT_MAX for very wide images }
  Src := MakeFrame(2000, 100, Integer(clBlack));
  try
    R := PrependBanner(Src, ['Line']);
    try
      BannerH := R.Height - 100;
      Assert.IsTrue(BannerH > 0, 'Banner should have height');
      Assert.AreEqual(2000, R.Width, 'Width must match source');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.PrependBanner_LongLine_Truncated;
var
  Src, R: TBitmap;
  LongText: string;
begin
  { A very long line on a narrow image must not overflow }
  Src := MakeFrame(200, 100, Integer(clBlack));
  try
    LongText := StringOfChar('W', 500);
    R := PrependBanner(Src, [LongText]);
    try
      Assert.AreEqual(200, R.Width, 'Width must match source, not expand');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

end.
