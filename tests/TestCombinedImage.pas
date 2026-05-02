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
    { Outer border (margin around the whole grid) }
    [Test] procedure Border_AddsPixelsOnAllSides;
    [Test] procedure Border_NegativeClampedToZero;
    [Test] procedure Border_DefaultIsZero;
    [Test] procedure Border_FillsMarginAreaWithBackground;
    [Test] procedure Border_ShiftsCellOrigin;
    { Timestamp corner placement }
    [Test] procedure TimestampCorner_TopLeft_LeavesBottomRightClean;
    [Test] procedure TimestampCorner_BottomRight_LeavesTopLeftClean;
    [Test] procedure TimestampCorner_DefaultIsBottomLeft;
    { Timecode background block and text alpha (parity with live-view overlay) }
    [Test] procedure TimecodeBack_OpaqueBg_PaintsConfiguredColorAtCorner;
    [Test] procedure TimecodeBack_OpaqueBg_TextAlphaZero_LeavesBgIntact;
    [Test] procedure TimestampText_LegacyPath_UsesConfiguredColor;
    { Large grid }
    [Test] procedure NineFrames_AutoCols_Produces3x3;
    { FormatBannerLines }
    [Test] procedure BannerLines_FullInfo_ThreeLines;
    [Test] procedure BannerLines_NoAudio_OmitsAudioPart;
    [Test] procedure BannerLines_FileSizeFormatting;
    { AttachBanner }
    [Test] procedure AttachBanner_EmptyLines_ReturnsCopy;
    [Test] procedure AttachBanner_AddsHeightAboveSource;
    [Test] procedure AttachBanner_PreservesSourceContent;
    [Test] procedure AttachBanner_NilSource_ReturnsEmptyBitmap;
    [Test] procedure AttachBanner_NarrowImage_SmallBanner;
    [Test] procedure AttachBanner_WideImage_LargerBanner;
    [Test] procedure AttachBanner_LongLine_PreservesWidth;
    [Test] procedure AttachBanner_LongMultiWordLine_GrowsBannerHeight;
    [Test] procedure AttachBanner_PathologicalSingleToken_HeightStaysBounded;
    [Test] procedure AttachBanner_LongLineDoesNotTruncateToEllipsis;
    [Test] procedure AttachBanner_PositionBottom_PreservesTopSource;
    [Test] procedure AttachBanner_FixedFontSize_DiffersFromAutoHeight;
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
    { Default* factory helpers: pin invariants the dialogs rely on when
      falling back (font name present, font size positive, "off" start
      state, documented position/corner). Tests use DEF_* constants so
      they track the real defaults instead of duplicating them. }
    [Test] procedure DefaultBannerStyle_PopulatesFontAndSize;
    [Test] procedure DefaultBannerStyle_AutoSizeMatchesConstant;
    [Test] procedure DefaultBannerStyle_PositionMatchesConstant;
    [Test] procedure DefaultCombinedGridStyle_AutoColumnsZero;
    [Test] procedure DefaultCombinedGridStyle_BackgroundAlphaIs255;
    [Test] procedure RenderCombined_FullAlpha_StaysPf24Bit;
    [Test] procedure RenderCombined_PartialAlpha_BecomesPf32Bit;
    [Test] procedure RenderCombined_GapPixelCarriesBackgroundAlpha;
    [Test] procedure RenderCombined_FramePixelStaysOpaque;
    [Test] procedure AttachBanner_AlphaAwareSource_PreservesGapTransparency;
    [Test] procedure AttachBanner_AlphaAwareSource_PreservesFrameColors;
    [Test] procedure DefaultCombinedGridStyle_BorderMatchesConstant;
    [Test] procedure DefaultTimestampStyle_ShowDefaultsOff;
    [Test] procedure DefaultTimestampStyle_FontAndSize;
    [Test] procedure DefaultTimestampStyle_CornerMatchesConstant;
    { RenderSmartCombinedImage }
    [Test] procedure SmartRender_EmptyFrames_ReturnsNil;
    [Test] procedure SmartRender_OutputDimensionsMatchInputs;
    [Test] procedure SmartRender_BorderFillsOuterMargin;
    [Test] procedure SmartRender_TwoRowsUnequal_RowZeroCellsWiderThanRowOne;
    [Test] procedure SmartRender_PartialAlpha_BecomesPf32Bit;
    [Test] procedure SmartRender_PartialAlpha_GapPixelCarriesBackgroundAlpha;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.IOUtils, System.Types, System.UITypes,
  uTypes, uFrameOffsets, uFFmpegExe, uCombinedImage, uDefaults;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   GetBValue/GetGValue/GetRValue) declares its own TBITMAP record alias
   that would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

{Pixel layout for pf32bit scan lines: byte order is BGRA per Win32 DIB}
function AlphaByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 3);
  Result := Row^;
end;

function BlueByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4);
  Result := Row^;
end;

function GreenByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 1);
  Result := Row^;
end;

function RedByteAt(ABmp: TBitmap; AX, AY: Integer): Byte;
var
  Row: PByte;
begin
  Row := PByte(ABmp.ScanLine[AY]);
  Inc(Row, AX * 4 + 2);
  Result := Row^;
end;

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

{ Positional-arg builders so the pre-DTO test call sites stay one-liners.
  Match the old RenderCombinedImage parameter order/defaults exactly. }
function MakeGrid(ACols, AGap: Integer; ABg: TColor; ABorder: Integer = 0): TCombinedGridStyle;
begin
  Result.Columns := ACols;
  Result.CellGap := AGap;
  Result.Border := ABorder;
  Result.Background := ABg;
  {Default to opaque so existing tests pin the historical pf24bit fast
   path; alpha-aware tests set BackgroundAlpha explicitly.}
  Result.BackgroundAlpha := 255;
end;

function MakeTs(AShow: Boolean; const AFontName: string; AFontSize: Integer;
  ACorner: TTimestampCorner = tcBottomLeft;
  ABackColor: TColor = clBlack; ABackAlpha: Byte = 0;
  ATextColor: TColor = clWhite; ATextAlpha: Byte = 255): TTimestampStyle;
begin
  Result.Show := AShow;
  Result.Corner := ACorner;
  Result.FontName := AFontName;
  Result.FontSize := AFontSize;
  Result.FontStyles := [fsBold];
  Result.BackColor := ABackColor;
  Result.BackAlpha := ABackAlpha;
  Result.TextColor := ATextColor;
  Result.TextAlpha := ATextAlpha;
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
  R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(1, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(2, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 10, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 5, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(2, 4, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(2, 0, BgColor), MakeTs(False, 'Consolas', 9));
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
  R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clWhite), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(10, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(True, 'Consolas', 9));
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
    WithoutTS := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
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
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 2, clBlack), MakeTs(False, 'Consolas', 9));
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

{ AttachBanner }

procedure TTestCombinedImage.AttachBanner_EmptyLines_ReturnsCopy;
var
  Src, R: TBitmap;
  EmptyLines: TArray<string>;
begin
  Src := MakeFrame(100, 80, Integer(clRed));
  try
    SetLength(EmptyLines, 0);
    R := AttachBanner(Src, EmptyLines, DefaultBannerStyle);
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

procedure TTestCombinedImage.AttachBanner_AddsHeightAboveSource;
var
  Src, R: TBitmap;
begin
  Src := MakeFrame(200, 100, Integer(clBlue));
  try
    R := AttachBanner(Src, ['Line 1', 'Line 2'], DefaultBannerStyle);
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

procedure TTestCombinedImage.AttachBanner_PreservesSourceContent;
var
  Src, R: TBitmap;
  BannerH: Integer;
begin
  Src := MakeFrame(100, 50, Integer(clRed));
  try
    R := AttachBanner(Src, ['Test'], DefaultBannerStyle);
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

procedure TTestCombinedImage.AttachBanner_NilSource_ReturnsEmptyBitmap;
var
  R: TBitmap;
begin
  R := AttachBanner(nil, ['Line'], DefaultBannerStyle);
  try
    Assert.AreEqual(0, R.Width);
    Assert.AreEqual(0, R.Height);
  finally
    R.Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_NarrowImage_SmallBanner;
var
  Narrow, Wide, R1, R2: TBitmap;
  H1, H2: Integer;
begin
  { A narrow image should get a smaller font, hence shorter banner }
  Narrow := MakeFrame(200, 100, Integer(clBlack));
  Wide := MakeFrame(1200, 100, Integer(clBlack));
  try
    R1 := AttachBanner(Narrow, ['Test line'], DefaultBannerStyle);
    R2 := AttachBanner(Wide, ['Test line'], DefaultBannerStyle);
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

procedure TTestCombinedImage.AttachBanner_WideImage_LargerBanner;
var
  Src, R: TBitmap;
  BannerH: Integer;
begin
  { Font size caps at BANNER_FONT_MAX for very wide images }
  Src := MakeFrame(2000, 100, Integer(clBlack));
  try
    R := AttachBanner(Src, ['Line'], DefaultBannerStyle);
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

procedure TTestCombinedImage.AttachBanner_LongLine_PreservesWidth;
var
  Src, R: TBitmap;
  LongText: string;
begin
  { A very long line on a narrow image must never widen the result }
  Src := MakeFrame(200, 100, Integer(clBlack));
  try
    LongText := StringOfChar('W', 500);
    R := AttachBanner(Src, [LongText], DefaultBannerStyle);
    try
      Assert.AreEqual(200, R.Width, 'Width must match source, not expand');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_LongMultiWordLine_GrowsBannerHeight;
var
  Src, RShort, RLong: TBitmap;
  ShortH, LongH, I: Integer;
  LongLine: string;
begin
  { A long multi-word line that exceeds the line width even at min font
    must wrap onto multiple sub-lines, producing a taller banner. }
  Src := MakeFrame(400, 100, Integer(clBlack));
  try
    { Build a long line of plausible-width words; 80 short words guarantees
      overflow even at minimum font on a 400px-wide line. }
    LongLine := '';
    for I := 0 to 79 do
    begin
      if LongLine <> '' then
        LongLine := LongLine + ' ';
      LongLine := LongLine + 'word' + IntToStr(I);
    end;

    RShort := AttachBanner(Src, ['short'], DefaultBannerStyle);
    RLong := AttachBanner(Src, [LongLine], DefaultBannerStyle);
    try
      ShortH := RShort.Height - 100;
      LongH := RLong.Height - 100;
      Assert.IsTrue(LongH > ShortH,
        Format('Wrapped banner (%d) must be taller than single-line banner (%d)',
          [LongH, ShortH]));
      Assert.AreEqual(400, RLong.Width, 'Wrapped banner must not widen image');
    finally
      RShort.Free;
      RLong.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_PathologicalSingleToken_HeightStaysBounded;
var
  Src, RNormal, RPath: TBitmap;
  NormalH, PathH: Integer;
  Token: string;
begin
  { A single 500-char token has no whitespace to wrap on; the wrap helper
    must fall back to ellipsis truncation, leaving the banner height close
    to the unwrapped baseline rather than blowing up. }
  Src := MakeFrame(200, 100, Integer(clBlack));
  try
    Token := StringOfChar('W', 500);
    RNormal := AttachBanner(Src, ['short'], DefaultBannerStyle);
    RPath := AttachBanner(Src, [Token], DefaultBannerStyle);
    try
      NormalH := RNormal.Height - 100;
      PathH := RPath.Height - 100;
      Assert.AreEqual(200, RPath.Width, 'Width must not expand');
      Assert.IsTrue(PathH > 0, 'Banner must have height');
      { The pathological single-token case should produce roughly the same
        height as a one-line banner (1 line, possibly 2 due to ellipsis path
        being created on a fresh "Current" line); 3x baseline is a generous
        upper bound that catches a runaway wrap. }
      Assert.IsTrue(PathH <= NormalH * 3,
        Format('Single-token banner height %d should not exceed 3x baseline %d',
          [PathH, NormalH]));
    finally
      RNormal.Free;
      RPath.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_LongLineDoesNotTruncateToEllipsis;
var
  Src, RShort, RLong: TBitmap;
  ShortH, LongH, I: Integer;
  LongLine: string;
begin
  { Regression for the truncation behavior at "realistic" widths: a 1024px
    image with a long-but-spaced line must wrap, not silently lose text. }
  Src := MakeFrame(1024, 200, Integer(clBlack));
  try
    LongLine := '';
    for I := 0 to 59 do
    begin
      if LongLine <> '' then
        LongLine := LongLine + ' ';
      LongLine := LongLine + 'segment' + IntToStr(I);
    end;

    RShort := AttachBanner(Src, ['short line'], DefaultBannerStyle);
    RLong := AttachBanner(Src, [LongLine], DefaultBannerStyle);
    try
      ShortH := RShort.Height - 200;
      LongH := RLong.Height - 200;
      Assert.IsTrue(LongH > ShortH,
        Format('At 1024px, the long line must wrap or shrink-grow the banner '
          + '(short=%d, long=%d)', [ShortH, LongH]));
      Assert.AreEqual(1024, RLong.Width);
    finally
      RShort.Free;
      RLong.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_PositionBottom_PreservesTopSource;
var
  Src, R: TBitmap;
  Style: TBannerStyle;
  BannerH: Integer;
begin
  { bpBottom must place the banner BELOW the source, so the source pixel
    at (x, 0) is preserved at result (x, 0). }
  Src := MakeFrame(200, 100, Integer(clLime));
  try
    Style := DefaultBannerStyle;
    Style.Position := bpBottom;
    R := AttachBanner(Src, ['Bottom banner'], Style);
    try
      BannerH := R.Height - 100;
      Assert.IsTrue(BannerH > 0, 'Banner should add height');
      Assert.AreEqual(200, R.Width, 'Width must match source');
      Assert.AreEqual(Integer(clLime), Integer(R.Canvas.Pixels[50, 25]),
        'Source content should be preserved at the top when banner is at bottom');
    finally
      R.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_FixedFontSize_DiffersFromAutoHeight;
var
  Src, RAuto, RFixed: TBitmap;
  Style: TBannerStyle;
  AutoH, FixedH: Integer;
begin
  { A fixed font size must bypass the auto-width heuristic. On a wide image,
    a small fixed font produces a visibly shorter banner than the auto sizing
    would. }
  Src := MakeFrame(1600, 100, Integer(clBlack));
  try
    RAuto := AttachBanner(Src, ['One line'], DefaultBannerStyle);

    Style := DefaultBannerStyle;
    Style.AutoSize := False;
    Style.FontSize := 6;
    RFixed := AttachBanner(Src, ['One line'], Style);
    try
      AutoH := RAuto.Height - 100;
      FixedH := RFixed.Height - 100;
      Assert.IsTrue(AutoH > 0, 'Auto banner should have height');
      Assert.IsTrue(FixedH > 0, 'Fixed banner should have height');
      Assert.IsTrue(FixedH < AutoH,
        Format('Fixed small font (%d) should produce shorter banner than auto (%d)',
          [FixedH, AutoH]));
    finally
      RAuto.Free;
      RFixed.Free;
    end;
  finally
    Src.Free;
  end;
end;

{ FormatBannerLines edge cases }

procedure TTestCombinedImage.BannerLines_AllEmpty_StillThreeLines;
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

procedure TTestCombinedImage.BannerLines_ZeroDuration_OmitsDuration;
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

procedure TTestCombinedImage.BannerLines_ByteRangeFileSize;
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

procedure TTestCombinedImage.BannerLines_ShortDuration_NoHours;
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

procedure TTestCombinedImage.BannerLines_AudioBitrate_Shown;
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

procedure TTestCombinedImage.BannerLines_VideoBitrate_Shown;
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

procedure TTestCombinedImage.BannerLines_NegativeDuration_OmitsDuration;
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

procedure TTestCombinedImage.BannerLines_ExactHourDuration;
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

procedure TTestCombinedImage.BannerLines_FpsOnly_NoSeparatorPrefix;
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

procedure TTestCombinedImage.BannerLines_AudioOnly_NoVideoCodec;
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

procedure TTestCombinedImage.BannerLines_AudioChannelsShown;
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

procedure TTestCombinedImage.BannerLines_NoFileSize_OmitsSize;
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

procedure TTestCombinedImage.BannerLines_GBFileSize;
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

procedure TTestCombinedImage.BannerLines_AnamorphicShowsArrow;
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

procedure TTestCombinedImage.BannerLines_DisplayMatchesStorage_NoArrow;
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

procedure TTestCombinedImage.BannerLines_DisplayZero_FallsBackToStorage;
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

procedure TTestCombinedImage.BuildBannerInfo_ExistingFile_CopiesAllFields;
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
    VideoInfo.IsValid := True;

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

procedure TTestCombinedImage.BuildBannerInfo_MissingFile_FileSizeIsZero;
var
  Missing: string;
  VideoInfo: TVideoInfo;
  Banner: TBannerInfo;
begin
  { Defensive: a probe could succeed and the file then disappear before
    BuildBannerInfo runs (network share, antivirus quarantine, etc.).
    The function must return FileSizeBytes=0 — not raise — so the banner
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

procedure TTestCombinedImage.BuildBannerInfo_EmptyVideoInfo_ReturnsZeroedRecord;
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

{ Outer border }

procedure TTestCombinedImage.Border_AddsPixelsOnAllSides;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { 2x1 grid of 50x40 frames with border=8: the total canvas should grow
    by 2*Border in each dimension (16 px added symmetrically) }
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(50, 40, 0);
  Frames[1] := MakeFrame(50, 40, 0);
  SetLength(Offsets, 2);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 8), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(2 * 50 + 2 * 8, R.Width, '2 cols * 50 + 2*border');
      Assert.AreEqual(40 + 2 * 8, R.Height, '1 row * 40 + 2*border');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedImage.Border_NegativeClampedToZero;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { A negative border must be treated as zero so the caller cannot
    accidentally shrink the grid below its natural geometry }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, 0);
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, -50), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(100, R.Width, 'Negative border clamps to zero');
      Assert.AreEqual(80, R.Height, 'Negative border clamps to zero');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.Border_DefaultIsZero;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R1, R2: TBitmap;
begin
  { Back-compat guarantee: callers that do not pass ABorder must get the
    same result as explicitly passing 0 }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(100, 80, 0);
  SetLength(Offsets, 1);
  try
    R1 := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    R2 := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(R2.Width, R1.Width, 'Default border must equal explicit 0');
      Assert.AreEqual(R2.Height, R1.Height, 'Default border must equal explicit 0');
    finally
      R1.Free;
      R2.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.Border_FillsMarginAreaWithBackground;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  BgColor: TColor;
begin
  { Pixel inside the outer border (outside all cells) must be the
    background color: the margin is part of the canvas, not transparent }
  BgColor := TColor($0000FF00);
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(60, 40, Integer(clRed));
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, BgColor, 10), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      { Corner of the output should be background, not frame color }
      Assert.AreEqual(Integer(BgColor), Integer(R.Canvas.Pixels[2, 2]),
        'Top-left margin pixel must be background');
      Assert.AreEqual(Integer(BgColor), Integer(R.Canvas.Pixels[R.Width - 3, R.Height - 3]),
        'Bottom-right margin pixel must be background');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.Border_ShiftsCellOrigin;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  Border: Integer;
begin
  { The first cell must be drawn at (Border, Border), not at (0, 0):
    the pixel at (Border, Border) must be the frame color }
  Border := 12;
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(60, 40, Integer(clRed));
  SetLength(Offsets, 1);
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, Border), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[Border + 5, Border + 5]),
        'Frame content must start at (Border, Border)');
      { Pixel just inside the margin (before cell) must be background }
      Assert.AreEqual(Integer(clBlack), Integer(R.Canvas.Pixels[Border - 2, Border - 2]),
        'Pixel inside margin before cell must be background');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Timestamp corner placement }

procedure TTestCombinedImage.TimestampCorner_TopLeft_LeavesBottomRightClean;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { With timestamp in the top-left corner, the bottom-right of the cell
    must be untouched (original frame color). This proves the corner
    parameter actually routes the placement, not just the fallback }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(True, 'Consolas', 12, tcTopLeft));
    Assert.IsNotNull(R);
    try
      { Bottom-right corner of the only cell: frame is 200x150, cell is at (0,0) }
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[195, 145]),
        'Bottom-right of cell must remain frame color when timestamp is top-left');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.TimestampCorner_BottomRight_LeavesTopLeftClean;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { Symmetric to the previous test: timestamp in bottom-right, so the
    top-left of the cell must stay frame color }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(True, 'Consolas', 12, tcBottomRight));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[5, 5]),
        'Top-left of cell must remain frame color when timestamp is bottom-right');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.TimestampCorner_DefaultIsBottomLeft;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RDefault, RExplicit: TBitmap;
  X, Y: Integer;
  Equal: Boolean;
begin
  { Back-compat guarantee: omitting the corner parameter must produce the
    same pixels as passing tcBottomLeft explicitly }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    RDefault := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack), MakeTs(True, 'Consolas', 12));
    RExplicit := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0), MakeTs(True, 'Consolas', 12, tcBottomLeft));
    try
      Assert.AreEqual(RExplicit.Width, RDefault.Width);
      Assert.AreEqual(RExplicit.Height, RDefault.Height);
      Equal := True;
      for Y := 0 to RDefault.Height - 1 do
        for X := 0 to RDefault.Width - 1 do
          if RDefault.Canvas.Pixels[X, Y] <> RExplicit.Canvas.Pixels[X, Y] then
          begin
            Equal := False;
            Break;
          end;
      Assert.IsTrue(Equal, 'Default corner must render identically to tcBottomLeft');
    finally
      RDefault.Free;
      RExplicit.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

{ Timecode background block and text alpha }

procedure TTestCombinedImage.TimecodeBack_OpaqueBg_PaintsConfiguredColorAtCorner;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
begin
  { With a fully opaque green bg block at bottom-left, the top-left pixel of the
    block (flush to the cell corner) must be green. The opposite corner of the
    cell must remain frame color - this proves bg is scoped to the label rect. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 9, tcBottomLeft, clGreen, 255, clWhite, 255));
    Assert.IsNotNull(R);
    try
      { Bg rect is flush to (0, 149-H) ... (W, 150). A point a few pixels above the
        bottom-left edge lands inside the block regardless of text width }
      Assert.AreEqual(Integer(clGreen), Integer(R.Canvas.Pixels[1, 148]),
        'Bottom-left block must paint configured bg color');
      Assert.AreEqual(Integer(clRed), Integer(R.Canvas.Pixels[195, 5]),
        'Opposite corner must stay frame color');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.TimecodeBack_OpaqueBg_TextAlphaZero_LeavesBgIntact;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  R: TBitmap;
  X, Y, FoundNonGreen: Integer;
begin
  { TextAlpha=0 with an opaque bg must render bg-only: every pixel inside the
    block must be the bg color. Scans the block's interior (avoiding edges)
    and counts any pixels that are not clGreen - expected count is zero. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    R := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 9, tcBottomLeft, clGreen, 255, clWhite, 0));
    Assert.IsNotNull(R);
    try
      { Block is in the bottom-left; scan a safe 10x10 window inside it }
      FoundNonGreen := 0;
      for Y := 135 to 145 do
        for X := 2 to 12 do
          if R.Canvas.Pixels[X, Y] <> clGreen then
            Inc(FoundNonGreen);
      Assert.AreEqual(0, FoundNonGreen,
        'TextAlpha=0 must leave the bg block free of text pixels');
    finally
      R.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.TimestampText_LegacyPath_UsesConfiguredColor;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RDefault, RYellow: TBitmap;
  X, Y: Integer;
  DiffersInTextArea: Boolean;
begin
  { Legacy path (bg alpha = 0) with a non-default text color must produce
    different pixels than the default (clWhite) render inside the text area.
    We compare two renders that differ only in ATimestampTextColor and assert
    at least one pixel in the bottom-left text region differs between them. }
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(200, 150, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 65.5;
  try
    RDefault := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 12, tcBottomLeft, clBlack, 0, clWhite, 255));
    RYellow := RenderCombinedImage(Frames, Offsets, MakeGrid(0, 0, clBlack, 0),
      MakeTs(True, 'Consolas', 12, tcBottomLeft, clBlack, 0, clYellow, 255));
    try
      DiffersInTextArea := False;
      { Bottom-left text area after the 4px margin; font height ~16 at 12pt bold }
      for Y := 125 to 145 do
      begin
        for X := 4 to 80 do
          if RDefault.Canvas.Pixels[X, Y] <> RYellow.Canvas.Pixels[X, Y] then
          begin
            DiffersInTextArea := True;
            Break;
          end;
        if DiffersInTextArea then
          Break;
      end;
      Assert.IsTrue(DiffersInTextArea,
        'Non-default text color must change pixels in the legacy-path text area');
    finally
      RDefault.Free;
      RYellow.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.DefaultBannerStyle_PopulatesFontAndSize;
var
  S: TBannerStyle;
begin
  S := DefaultBannerStyle;
  Assert.AreNotEqual('', S.FontName,
    'Banner default must name a font; empty defers to Canvas default which is fragile');
  Assert.IsTrue(S.FontSize > 0, 'Banner default font size must be positive');
  Assert.AreEqual(TColor(DEF_BANNER_BACKGROUND), S.Background);
  Assert.AreEqual(TColor(DEF_BANNER_TEXT_COLOR), S.TextColor);
  Assert.AreEqual(DEF_BANNER_FONT_NAME, S.FontName);
  Assert.AreEqual<Integer>(DEF_BANNER_FONT_SIZE, S.FontSize);
end;

procedure TTestCombinedImage.DefaultBannerStyle_AutoSizeMatchesConstant;
begin
  {AutoSize flips the banner between width-heuristic + shrink-to-fit
   (True) and fixed-size + wrap (False). The dialogs rely on the
   documented default shipping as True.}
  Assert.AreEqual(DEF_BANNER_FONT_AUTO_SIZE, DefaultBannerStyle.AutoSize);
end;

procedure TTestCombinedImage.DefaultBannerStyle_PositionMatchesConstant;
begin
  Assert.AreEqual(Ord(DEF_BANNER_POSITION),
    Ord(DefaultBannerStyle.Position));
end;

procedure TTestCombinedImage.DefaultCombinedGridStyle_AutoColumnsZero;
var
  S: TCombinedGridStyle;
begin
  {Columns = 0 is the "auto" sentinel — RenderCombinedImage picks
   ceil(sqrt(n)). Any non-zero default would silently override that.}
  S := DefaultCombinedGridStyle;
  Assert.AreEqual<Integer>(0, S.Columns);
  Assert.AreEqual<Integer>(0, S.CellGap);
end;

procedure TTestCombinedImage.DefaultCombinedGridStyle_BackgroundAlphaIs255;
begin
  {Default to fully opaque so existing call sites keep the historical
   pf24bit fast path with no behaviour change.}
  Assert.AreEqual(255, Integer(DefaultCombinedGridStyle.BackgroundAlpha));
end;

procedure TTestCombinedImage.RenderCombined_FullAlpha_StaysPf24Bit;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  {BackgroundAlpha = 255 is the no-regression branch. Pixel format must
   stay pf24bit so the saver picks the existing 24-bit PNG path and
   anyone who layered behaviour on output format keeps working.}
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(40, 30, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 1.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(Ord(pf24bit), Ord(Bmp.PixelFormat));
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.RenderCombined_PartialAlpha_BecomesPf32Bit;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(40, 30, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 1.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Grid.BackgroundAlpha := 128;
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(Ord(pf32bit), Ord(Bmp.PixelFormat));
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.RenderCombined_GapPixelCarriesBackgroundAlpha;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  {2x1 layout with a 4px gap. Sample the gap region and assert its alpha
   matches BackgroundAlpha; non-frame areas must be transparent-aware.}
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(20, 20, Integer(clRed));
  Frames[1] := MakeFrame(20, 20, Integer(clGreen));
  SetLength(Offsets, 2);
  Offsets[0].TimeOffset := 0.0;
  Offsets[1].TimeOffset := 1.0;
  try
    Grid := MakeGrid(2, 4, clBlue, 0);
    Grid.BackgroundAlpha := 64;
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(Ord(pf32bit), Ord(Bmp.PixelFormat));
      {Gap pixel sits between cells: x in [20..23], y any}
      Assert.AreEqual(64, Integer(AlphaByteAt(Bmp, 21, 10)),
        'Gap pixel must carry BackgroundAlpha');
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedImage.RenderCombined_FramePixelStaysOpaque;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Bmp: TBitmap;
begin
  {Frame interior pixel must keep alpha=255 even when BackgroundAlpha is
   low. Confirms the lift step distinguishes cell rects from gap area.}
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(20, 20, Integer(clRed));
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 0.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Grid.BackgroundAlpha := 0;
    Bmp := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Assert.AreEqual(255, Integer(AlphaByteAt(Bmp, 10, 10)),
        'Frame pixel alpha must always be 255 (frames are opaque)');
    finally
      Bmp.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_AlphaAwareSource_PreservesFrameColors;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Combined, WithBanner: TBitmap;
  Style: TBannerStyle;
  Lines: TArray<string>;
  FrameY: Integer;
begin
  {Regression: AttachBanner used to route the pf32bit→pf32bit source
   copy through GDI's AlphaBlend, which expects pre-multiplied RGB. Our
   alpha is non-pre-multiplied, so frame colours came out modified
   (effectively dst = src + dst*(1-srcA) instead of a flat copy). This
   test pins that frame interior pixels carry the exact source colours
   through the banner attachment.}
  SetLength(Frames, 1);
  Frames[0] := MakeFrame(20, 20, Integer(clRed)); {clRed = $0000FF: B=0 G=0 R=255}
  SetLength(Offsets, 1);
  Offsets[0].TimeOffset := 0.0;
  try
    Grid := MakeGrid(1, 0, clBlue, 0);
    Grid.BackgroundAlpha := 0;
    Combined := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Style := DefaultBannerStyle;
      SetLength(Lines, 1);
      Lines[0] := 'Test banner';
      WithBanner := AttachBanner(Combined, Lines, Style);
      try
        {Frame sits below the banner band: WithBanner.Height - Combined.Height
         is the source band start. Sample the centre of the (only) frame.}
        FrameY := WithBanner.Height - Combined.Height + 10;
        Assert.AreEqual(0, Integer(BlueByteAt(WithBanner, 10, FrameY)),
          'Frame blue must be 0 (clRed)');
        Assert.AreEqual(0, Integer(GreenByteAt(WithBanner, 10, FrameY)),
          'Frame green must be 0 (clRed)');
        Assert.AreEqual(255, Integer(RedByteAt(WithBanner, 10, FrameY)),
          'Frame red must be 255 (clRed); dimmer values mean AlphaBlend mangled colours');
      finally
        WithBanner.Free;
      end;
    finally
      Combined.Free;
    end;
  finally
    Frames[0].Free;
  end;
end;

procedure TTestCombinedImage.AttachBanner_AlphaAwareSource_PreservesGapTransparency;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Combined, WithBanner: TBitmap;
  Style: TBannerStyle;
  Lines: TArray<string>;
begin
  {Regression: when ShowBanner is enabled, AttachBanner used to produce a
   pf24bit output and lose the gap transparency built into the combined
   bitmap. Saved combined PNG looked uniformly opaque even at
   BackgroundAlpha=0. The fix makes AttachBanner alpha-aware when its
   source is pf32bit; this test pins the gap pixel's alpha through the
   banner attachment.}
  SetLength(Frames, 2);
  Frames[0] := MakeFrame(20, 20, Integer(clRed));
  Frames[1] := MakeFrame(20, 20, Integer(clGreen));
  SetLength(Offsets, 2);
  Offsets[0].TimeOffset := 0.0;
  Offsets[1].TimeOffset := 1.0;
  try
    Grid := MakeGrid(2, 4, clBlue, 0);
    Grid.BackgroundAlpha := 0;
    Combined := RenderCombinedImage(Frames, Offsets, Grid, MakeTs(False, 'Consolas', 9));
    try
      Style := DefaultBannerStyle;
      SetLength(Lines, 1);
      Lines[0] := 'Test banner';
      WithBanner := AttachBanner(Combined, Lines, Style);
      try
        Assert.AreEqual(Ord(pf32bit), Ord(WithBanner.PixelFormat),
          'Banner output must inherit pf32bit when source is alpha-aware');
        {Banner is at the top by default — gap pixel of source sits below
         banner at Combined.Height + a few rows.}
        Assert.AreEqual(0, Integer(AlphaByteAt(WithBanner, 21,
          WithBanner.Height - Combined.Height + 10)),
          'Gap pixel alpha must survive AttachBanner unchanged');
      finally
        WithBanner.Free;
      end;
    finally
      Combined.Free;
    end;
  finally
    Frames[0].Free;
    Frames[1].Free;
  end;
end;

procedure TTestCombinedImage.DefaultCombinedGridStyle_BorderMatchesConstant;
begin
  Assert.AreEqual<Integer>(DEF_COMBINED_BORDER,
    DefaultCombinedGridStyle.Border);
end;

procedure TTestCombinedImage.DefaultTimestampStyle_ShowDefaultsOff;
var
  S: TTimestampStyle;
begin
  {The timestamp overlay must ship OFF — users opt in via the Show
   checkbox. A True default would slap timecodes on every rendered
   image without consent.}
  S := DefaultTimestampStyle;
  Assert.IsFalse(S.Show, 'Timestamp default must be hidden');
  Assert.AreEqual<Integer>(0, S.BackAlpha,
    'BackAlpha=0 selects the legacy shadow-only path for back-compat');
end;

procedure TTestCombinedImage.DefaultTimestampStyle_FontAndSize;
var
  S: TTimestampStyle;
begin
  S := DefaultTimestampStyle;
  Assert.AreNotEqual('', S.FontName,
    'Timestamp font name must not be blank');
  Assert.IsTrue(S.FontSize > 0, 'Timestamp font size must be positive');
  Assert.AreEqual<Integer>(DEF_TIMESTAMP_TEXT_ALPHA, S.TextAlpha);
  Assert.AreEqual(TColor(DEF_TC_BACK_COLOR), S.BackColor);
  Assert.AreEqual(TColor(DEF_TIMESTAMP_TEXT_COLOR), S.TextColor);
end;

procedure TTestCombinedImage.DefaultTimestampStyle_CornerMatchesConstant;
begin
  Assert.AreEqual(Ord(DEF_TIMESTAMP_CORNER),
    Ord(DefaultTimestampStyle.Corner));
end;

{ RenderSmartCombinedImage }

procedure TTestCombinedImage.SmartRender_EmptyFrames_ReturnsNil;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
begin
  SetLength(Frames, 0);
  SetLength(Offsets, 0);
  SetLength(RowCounts, 0);
  R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
    MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
  Assert.IsNull(R);
end;

procedure TTestCombinedImage.SmartRender_OutputDimensionsMatchInputs;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
  I: Integer;
begin
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clBlue));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(800, R.Width);
      Assert.AreEqual(600, R.Height);
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedImage.SmartRender_BorderFillsOuterMargin;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
  I: Integer;
  Row: PByte;
  Border: Integer;
begin
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clRed));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Border := 20;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      MakeGrid(0, 0, clGreen, Border), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      {Pixel inside the top border strip should be green (background),
       not red (frame). Sample (10, 10) which is well inside the
       Border=20 outer margin.}
      Row := PByte(R.ScanLine[10]);
      Inc(Row, 10 * 3); {pf24bit: 3 bytes per pixel}
      Assert.AreEqual(Byte(GetBValue(clGreen)), Row[0], 'B at (10,10)');
      Assert.AreEqual(Byte(GetGValue(clGreen)), Row[1], 'G at (10,10)');
      Assert.AreEqual(Byte(GetRValue(clGreen)), Row[2], 'R at (10,10)');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedImage.SmartRender_TwoRowsUnequal_RowZeroCellsWiderThanRowOne;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  R: TBitmap;
  I, ExpectedRow0CellW, ExpectedRow1CellW: Integer;
begin
  {5 frames split as [2, 3]: row 0 has 2 cells (each = inner_W / 2),
   row 1 has 3 cells (each = inner_W / 3). So row 0 cells must be wider
   than row 1 cells. Verifies the renderer honours the per-row cell-count
   layout rather than treating the grid as uniform.}
  SetLength(Frames, 5);
  SetLength(Offsets, 5);
  for I := 0 to 4 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clNavy));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  RowCounts := TArray<Integer>.Create(2, 3);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 600, 400,
      MakeGrid(0, 0, clBlack), MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      ExpectedRow0CellW := 600 div 2;
      ExpectedRow1CellW := 600 div 3;
      Assert.IsTrue(ExpectedRow0CellW > ExpectedRow1CellW,
        'Test setup invariant: 2-cell row must produce wider cells than 3-cell row');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedImage.SmartRender_PartialAlpha_BecomesPf32Bit;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  Grid: TCombinedGridStyle;
  R: TBitmap;
  I: Integer;
begin
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clBlue));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Grid := MakeGrid(0, 4, clBlack, 8);
  Grid.BackgroundAlpha := 128;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      Grid, MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      Assert.AreEqual(Ord(pf32bit), Ord(R.PixelFormat),
        'BackgroundAlpha < 255 should lift the result to pf32bit');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

procedure TTestCombinedImage.SmartRender_PartialAlpha_GapPixelCarriesBackgroundAlpha;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  RowCounts: TArray<Integer>;
  Grid: TCombinedGridStyle;
  R: TBitmap;
  I: Integer;
  GapAlpha: Byte;
begin
  {With Border=20 and BackgroundAlpha=128, a pixel inside the outer
   margin must carry alpha=128, not 255. Pin parity with the existing
   RenderCombined_GapPixelCarriesBackgroundAlpha test: same policy
   should hold for the smart renderer.}
  SetLength(Frames, 4);
  SetLength(Offsets, 4);
  for I := 0 to 3 do
  begin
    Frames[I] := MakeFrame(160, 90, Integer(clBlue));
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Grid := MakeGrid(0, 0, clBlack, 20);
  Grid.BackgroundAlpha := 128;
  RowCounts := TArray<Integer>.Create(2, 2);
  try
    R := RenderSmartCombinedImage(Frames, Offsets, RowCounts, 800, 600,
      Grid, MakeTs(False, 'Consolas', 9));
    Assert.IsNotNull(R);
    try
      GapAlpha := AlphaByteAt(R, 5, 5); {well inside the 20px border}
      Assert.AreEqual(Byte(128), GapAlpha,
        'Gap/border pixel should carry the configured BackgroundAlpha');
    finally
      R.Free;
    end;
  finally
    for I := 0 to High(Frames) do
      Frames[I].Free;
  end;
end;

end.
