{Renders multiple frame bitmaps into a single combined grid image.
 Pure rendering: no I/O, no settings dependency.}
unit uCombinedImage;

interface

uses
  System.UITypes, Vcl.Graphics, uFrameOffsets, uFFmpegExe;

type
  {Video metadata for the info banner. Populated by the caller from
   its own TVideoInfo + file system data.}
  TBannerInfo = record
    FileName: string;
    FileSizeBytes: Int64;
    DurationSec: Double;
    Width, Height: Integer;
    VideoCodec: string;
    VideoBitrateKbps: Integer;
    Fps: Double;
    AudioCodec: string;
    AudioSampleRate: Integer;
    AudioChannels: string;
    AudioBitrateKbps: Integer;
  end;

  {Formats banner info into human-readable text lines.
   Returns an empty array if AInfo has no meaningful data.}
function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;

{Builds a TBannerInfo from a filename and probed video metadata.
 Reads file size from disk; all other fields come from AVideoInfo.}
function BuildBannerInfo(const AFileName: string; const AVideoInfo: TVideoInfo): TBannerInfo;

{Prepends a dark info banner to an existing bitmap.
 Font is auto-scaled to fit the image width.
 @param ASrc Source bitmap (not freed; caller still owns it)
 @param ALines Text lines to display (empty array = no banner, returns copy of ASrc)
 @return New bitmap with banner above source content. Caller owns result.}
function PrependBanner(ASrc: TBitmap; const ALines: TArray<string>): TBitmap;

{Renders all frames into a single grid image.
 @param AFrames Array of frame bitmaps (nil entries are skipped)
 @param AOffsets Frame time offsets (used for timestamp overlay)
 @param ACols Number of columns (0 = auto based on frame count)
 @param AGap Pixel gap between cells
 @param ABackground Background fill color
 @param AShowTimestamp Whether to overlay timecodes on each cell
 @param AFontName Font face for timestamp text
 @param AFontSize Font size in points for timestamp text
 @return Combined bitmap, or nil if AFrames is empty. Caller owns result.}
function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; ACols, AGap: Integer; ABackground: TColor; AShowTimestamp: Boolean; const AFontName: string; AFontSize: Integer): TBitmap;

implementation

uses
  System.SysUtils, System.IOUtils, System.Math, System.Types;

const
  BANNER_BG_COLOR = TColor($00282828); {dark gray background}
  BANNER_TEXT_COLOR = TColor($00E0E0E0); {light gray text}
  BANNER_PADDING_H = 10; {horizontal padding}
  BANNER_PADDING_V = 6; {vertical padding (top and bottom)}
  BANNER_LINE_GAP = 2; {extra spacing between lines}
  BANNER_FONT_NAME = 'Segoe UI';
  BANNER_FONT_MIN = 8; {minimum font size in points}
  BANNER_FONT_MAX = 16; {maximum font size in points}
  BANNER_FONT_RATIO = 55; {image width divisor for font size}
  BANNER_ELLIPSIS = '...';

  {Formats a file size as a human-readable string}
function FormatFileSize(ABytes: Int64): string;
var
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create('en-US');
  if ABytes >= 1024 * 1024 * 1024 then
    Result := Format('%.2f GB', [ABytes / (1024.0 * 1024 * 1024)], Fmt)
  else if ABytes >= 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024.0 * 1024)], Fmt)
  else if ABytes >= 1024 then
    Result := Format('%.0f KB', [ABytes / 1024.0], Fmt)
  else
    Result := Format('%d B', [ABytes]);
end;

function BuildBannerInfo(const AFileName: string; const AVideoInfo: TVideoInfo): TBannerInfo;
begin
  Result := Default (TBannerInfo);
  Result.FileName := AFileName;
  if TFile.Exists(AFileName) then
    Result.FileSizeBytes := TFile.GetSize(AFileName);
  Result.DurationSec := AVideoInfo.Duration;
  Result.Width := AVideoInfo.Width;
  Result.Height := AVideoInfo.Height;
  Result.VideoCodec := AVideoInfo.VideoCodec;
  Result.VideoBitrateKbps := AVideoInfo.VideoBitrateKbps;
  Result.Fps := AVideoInfo.Fps;
  Result.AudioCodec := AVideoInfo.AudioCodec;
  Result.AudioSampleRate := AVideoInfo.AudioSampleRate;
  Result.AudioChannels := AVideoInfo.AudioChannels;
  Result.AudioBitrateKbps := AVideoInfo.AudioBitrateKbps;
end;

function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;
var
  Line1, Line2, Line3, Audio: string;
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create('en-US');
  {Line 1: filename and file size}
  Line1 := Format('File: %s', [ExtractFileName(AInfo.FileName)]);
  if AInfo.FileSizeBytes > 0 then
    Line1 := Line1 + Format('  |  Size: %s', [FormatFileSize(AInfo.FileSizeBytes)]);

  {Line 2: duration, resolution, fps}
  Line2 := '';
  if AInfo.DurationSec > 0 then
    Line2 := Format('Duration: %s', [FormatDurationHMS(AInfo.DurationSec)]);
  if (AInfo.Width > 0) and (AInfo.Height > 0) then
  begin
    if Line2 <> '' then
      Line2 := Line2 + '  |  ';
    Line2 := Line2 + Format('%dx%d', [AInfo.Width, AInfo.Height]);
  end;
  if AInfo.Fps > 0 then
  begin
    if Line2 <> '' then
      Line2 := Line2 + '  |  ';
    Line2 := Line2 + Format('%.3f fps', [AInfo.Fps], Fmt);
  end;

  {Line 3: video codec + audio info}
  Line3 := '';
  if AInfo.VideoCodec <> '' then
  begin
    Line3 := Format('Video: %s', [AInfo.VideoCodec]);
    if AInfo.VideoBitrateKbps > 0 then
      Line3 := Line3 + Format('  %d kbps', [AInfo.VideoBitrateKbps]);
  end;
  if AInfo.AudioCodec <> '' then
  begin
    Audio := Format('Audio: %s', [AInfo.AudioCodec]);
    if AInfo.AudioSampleRate > 0 then
      Audio := Audio + Format('  %d Hz', [AInfo.AudioSampleRate]);
    if AInfo.AudioChannels <> '' then
      Audio := Audio + Format('  %s', [AInfo.AudioChannels]);
    if AInfo.AudioBitrateKbps > 0 then
      Audio := Audio + Format('  %d kbps', [AInfo.AudioBitrateKbps]);
    if Line3 <> '' then
      Line3 := Line3 + '  |  ';
    Line3 := Line3 + Audio;
  end;

  Result := [Line1, Line2, Line3];
end;

{Truncates text to fit within MaxW pixels, appending ellipsis if needed}
function TruncateToFit(ACanvas: TCanvas; const AText: string; AMaxW: Integer): string;
var
  Len: Integer;
  EllW: Integer;
begin
  if ACanvas.TextWidth(AText) <= AMaxW then
    Exit(AText);

  EllW := ACanvas.TextWidth(BANNER_ELLIPSIS);
  Len := Length(AText);
  while (Len > 0) and (ACanvas.TextWidth(Copy(AText, 1, Len)) + EllW > AMaxW) do
    Dec(Len);
  Result := Copy(AText, 1, Len) + BANNER_ELLIPSIS;
end;

{Word-wraps AText into lines that each fit within AMaxW at the canvas's
 current font. Splits on whitespace and rejoins with single spaces, so the
 decorative double-spaces around '|' separators collapse on wrapped lines
 (an acceptable cost for keeping all text visible). A single token wider
 than AMaxW is character-truncated with ellipsis.}
function WrapTextToLines(ACanvas: TCanvas; const AText: string; AMaxW: Integer): TArray<string>;
var
  Words: TArray<string>;
  Current, Test: string;
  I: Integer;
begin
  if ACanvas.TextWidth(AText) <= AMaxW then
  begin
    SetLength(Result, 1);
    Result[0] := AText;
    Exit;
  end;

  Words := AText.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := AText;
    Exit;
  end;

  SetLength(Result, 0);
  Current := '';
  for I := 0 to High(Words) do
  begin
    if Current = '' then
      Test := Words[I]
    else
      Test := Current + ' ' + Words[I];

    if ACanvas.TextWidth(Test) <= AMaxW then
      Current := Test
    else
    begin
      {Flush the in-progress line if any, then place this word on a new line}
      if Current <> '' then
        Result := Result + [Current];

      if ACanvas.TextWidth(Words[I]) <= AMaxW then
        Current := Words[I]
      else
      begin
        {Pathological: a single token wider than the line - truncate it}
        Result := Result + [TruncateToFit(ACanvas, Words[I], AMaxW)];
        Current := '';
      end;
    end;
  end;

  if Current <> '' then
    Result := Result + [Current];
end;

{Returns the largest font size in [BANNER_FONT_MIN, AInitial] at which every
 line in ALines fits within AMaxW. Returns BANNER_FONT_MIN when no size in
 the range fits - the caller should then wrap overflowing lines.}
function FindFittingBannerFontSize(ACanvas: TCanvas; const ALines: TArray<string>; AInitial, AMaxW: Integer): Integer;
var
  Size, I: Integer;
  Fits: Boolean;
begin
  for Size := AInitial downto BANNER_FONT_MIN do
  begin
    ACanvas.Font.Size := Size;
    Fits := True;
    for I := 0 to High(ALines) do
      if ACanvas.TextWidth(ALines[I]) > AMaxW then
      begin
        Fits := False;
        Break;
      end;
    if Fits then
      Exit(Size);
  end;
  Result := BANNER_FONT_MIN;
end;

function PrependBanner(ASrc: TBitmap; const ALines: TArray<string>): TBitmap;
var
  InitialSize, FontSize, LineH, BannerH, MaxTextW, I: Integer;
  TempBmp: TBitmap;
  Wrapped, RenderLines: TArray<string>;
begin
  if (Length(ALines) = 0) or (ASrc = nil) then
  begin
    {Return a copy so the caller always gets an owned bitmap}
    Result := TBitmap.Create;
    if ASrc <> nil then
      Result.Assign(ASrc);
    Exit;
  end;

  {Initial size from the historical width-based ratio. The shrink loop
   below may pick something smaller if the actual text doesn't fit.}
  InitialSize := EnsureRange(ASrc.Width div BANNER_FONT_RATIO, BANNER_FONT_MIN, BANNER_FONT_MAX);
  MaxTextW := ASrc.Width - 2 * BANNER_PADDING_H;

  {Measure on a temp bitmap so the result canvas isn't dirtied with
   intermediate font states during the shrink probe.}
  TempBmp := TBitmap.Create;
  try
    TempBmp.Canvas.Font.Name := BANNER_FONT_NAME;

    {Globally pick the largest font size where every original line fits.
     If even the minimum doesn't fit, the offending lines get word-wrapped
     below at that minimum size.}
    FontSize := FindFittingBannerFontSize(TempBmp.Canvas, ALines, InitialSize, MaxTextW);
    TempBmp.Canvas.Font.Size := FontSize;

    {Build the final render list: pass each line through the wrapper,
     which is a no-op for lines that already fit.}
    RenderLines := [];
    for I := 0 to High(ALines) do
    begin
      Wrapped := WrapTextToLines(TempBmp.Canvas, ALines[I], MaxTextW);
      RenderLines := RenderLines + Wrapped;
    end;

    LineH := TempBmp.Canvas.TextHeight('Wg');
  finally
    TempBmp.Free;
  end;

  BannerH := BANNER_PADDING_V + Length(RenderLines) * (LineH + BANNER_LINE_GAP) - BANNER_LINE_GAP + BANNER_PADDING_V;

  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(ASrc.Width, BannerH + ASrc.Height);

  {Draw banner background}
  Result.Canvas.Brush.Color := BANNER_BG_COLOR;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, BannerH));

  {Draw text lines (already fitted by shrink + wrap; no truncation pass)}
  Result.Canvas.Font.Name := BANNER_FONT_NAME;
  Result.Canvas.Font.Size := FontSize;
  Result.Canvas.Font.Color := BANNER_TEXT_COLOR;
  Result.Canvas.Brush.Style := bsClear;
  for I := 0 to High(RenderLines) do
    Result.Canvas.TextOut(BANNER_PADDING_H, BANNER_PADDING_V + I * (LineH + BANNER_LINE_GAP), RenderLines[I]);

  {Draw source image below banner}
  Result.Canvas.Draw(0, BannerH, ASrc);
end;

function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; ACols, AGap: Integer; ABackground: TColor; AShowTimestamp: Boolean; const AFontName: string; AFontSize: Integer): TBitmap;
var
  Cols, Rows, CellW, CellH, I, Row, Col, X, Y: Integer;
  FrameCount: Integer;
  Tc: string;
  TH: Integer;
begin
  FrameCount := Length(AFrames);
  if FrameCount = 0 then
    Exit(nil);

  Cols := ACols;
  if Cols <= 0 then
    Cols := Ceil(Sqrt(FrameCount));
  if Cols > FrameCount then
    Cols := FrameCount;
  Rows := Ceil(FrameCount / Cols);

  {Use first non-nil frame dimensions as cell size}
  CellW := 320;
  CellH := 240;
  for I := 0 to FrameCount - 1 do
    if AFrames[I] <> nil then
    begin
      CellW := AFrames[I].Width;
      CellH := AFrames[I].Height;
      Break;
    end;

  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Cols * CellW + Max(Cols - 1, 0) * AGap, Rows * CellH + Max(Rows - 1, 0) * AGap);
  Result.Canvas.Brush.Color := ABackground;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then
      Continue;
    Row := I div Cols;
    Col := I mod Cols;
    X := Col * (CellW + AGap);
    Y := Row * (CellH + AGap);
    Result.Canvas.Draw(X, Y, AFrames[I]);

    if AShowTimestamp and (I < Length(AOffsets)) then
    begin
      Tc := FormatTimecode(AOffsets[I].TimeOffset);
      Result.Canvas.Font.Name := AFontName;
      Result.Canvas.Font.Size := AFontSize;
      Result.Canvas.Font.Style := [fsBold];
      TH := Result.Canvas.TextHeight(Tc);
      {Shadow for readability}
      Result.Canvas.Font.Color := clBlack;
      Result.Canvas.Brush.Style := bsClear;
      Result.Canvas.TextOut(X + 5, Y + CellH - TH - 4, Tc);
      {Foreground text}
      Result.Canvas.Font.Color := clWhite;
      Result.Canvas.TextOut(X + 4, Y + CellH - TH - 5, Tc);
    end;
  end;
end;

end.
