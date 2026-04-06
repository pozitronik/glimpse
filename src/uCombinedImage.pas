{ Renders multiple frame bitmaps into a single combined grid image.
  Pure rendering: no I/O, no settings dependency. }
unit uCombinedImage;

interface

uses
  System.UITypes, Vcl.Graphics, uFrameOffsets;

type
  { Video metadata for the info banner. Populated by the caller from
    its own TVideoInfo + file system data. }
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

{ Formats banner info into human-readable text lines.
  Returns an empty array if AInfo has no meaningful data. }
function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;

{ Prepends a dark info banner to an existing bitmap.
  Font is auto-scaled to fit the image width.
  @param ASrc Source bitmap (not freed; caller still owns it)
  @param ALines Text lines to display (empty array = no banner, returns copy of ASrc)
  @return New bitmap with banner above source content. Caller owns result. }
function PrependBanner(ASrc: TBitmap;
  const ALines: TArray<string>): TBitmap;

{ Renders all frames into a single grid image.
  @param AFrames Array of frame bitmaps (nil entries are skipped)
  @param AOffsets Frame time offsets (used for timestamp overlay)
  @param ACols Number of columns (0 = auto based on frame count)
  @param AGap Pixel gap between cells
  @param ABackground Background fill color
  @param AShowTimestamp Whether to overlay timecodes on each cell
  @param AFontName Font face for timestamp text
  @param AFontSize Font size in points for timestamp text
  @return Combined bitmap, or nil if AFrames is empty. Caller owns result. }
function RenderCombinedImage(const AFrames: TArray<TBitmap>;
  const AOffsets: TFrameOffsetArray; ACols, AGap: Integer;
  ABackground: TColor; AShowTimestamp: Boolean;
  const AFontName: string; AFontSize: Integer): TBitmap;

implementation

uses
  System.SysUtils, System.Math, System.Types;

const
  BANNER_BG_COLOR    = TColor($00282828); { dark gray background }
  BANNER_TEXT_COLOR   = TColor($00E0E0E0); { light gray text }
  BANNER_PADDING_H   = 10;  { horizontal padding }
  BANNER_PADDING_V   = 6;   { vertical padding (top and bottom) }
  BANNER_LINE_GAP    = 2;   { extra spacing between lines }
  BANNER_FONT_NAME   = 'Segoe UI';
  BANNER_FONT_MIN    = 8;   { minimum font size in points }
  BANNER_FONT_MAX    = 16;  { maximum font size in points }
  BANNER_FONT_RATIO  = 55;  { image width divisor for font size }
  BANNER_ELLIPSIS    = '...';

{ Formats a file size as a human-readable string }
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

{ Formats duration in seconds to HH:MM:SS }
function FormatDurationHMS(ASec: Double): string;
var
  H, M, S: Integer;
  Total: Integer;
begin
  Total := Round(ASec);
  H := Total div 3600;
  M := (Total mod 3600) div 60;
  S := Total mod 60;
  if H > 0 then
    Result := Format('%d:%.2d:%.2d', [H, M, S])
  else
    Result := Format('%.2d:%.2d', [M, S]);
end;

function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;
var
  Line1, Line2, Line3, Audio: string;
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create('en-US');
  { Line 1: filename and file size }
  Line1 := Format('File: %s', [ExtractFileName(AInfo.FileName)]);
  if AInfo.FileSizeBytes > 0 then
    Line1 := Line1 + Format('  |  Size: %s', [FormatFileSize(AInfo.FileSizeBytes)]);

  { Line 2: duration, resolution, fps }
  Line2 := '';
  if AInfo.DurationSec > 0 then
    Line2 := Format('Duration: %s', [FormatDurationHMS(AInfo.DurationSec)]);
  if (AInfo.Width > 0) and (AInfo.Height > 0) then
  begin
    if Line2 <> '' then Line2 := Line2 + '  |  ';
    Line2 := Line2 + Format('%dx%d', [AInfo.Width, AInfo.Height]);
  end;
  if AInfo.Fps > 0 then
  begin
    if Line2 <> '' then Line2 := Line2 + '  |  ';
    Line2 := Line2 + Format('%.3f fps', [AInfo.Fps], Fmt);
  end;

  { Line 3: video codec + audio info }
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
    if Line3 <> '' then Line3 := Line3 + '  |  ';
    Line3 := Line3 + Audio;
  end;

  Result := [Line1, Line2, Line3];
end;

{ Truncates text to fit within MaxW pixels, appending ellipsis if needed }
function TruncateToFit(ACanvas: TCanvas; const AText: string;
  AMaxW: Integer): string;
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

function PrependBanner(ASrc: TBitmap;
  const ALines: TArray<string>): TBitmap;
var
  FontSize, LineH, BannerH, MaxTextW, I: Integer;
  TempBmp: TBitmap;
  Line: string;
begin
  if (Length(ALines) = 0) or (ASrc = nil) then
  begin
    { Return a copy so the caller always gets an owned bitmap }
    Result := TBitmap.Create;
    if ASrc <> nil then
      Result.Assign(ASrc);
    Exit;
  end;

  { Auto-scale font size from image width }
  FontSize := EnsureRange(ASrc.Width div BANNER_FONT_RATIO,
    BANNER_FONT_MIN, BANNER_FONT_MAX);
  MaxTextW := ASrc.Width - 2 * BANNER_PADDING_H;

  { Measure banner height using a temporary bitmap }
  TempBmp := TBitmap.Create;
  try
    TempBmp.Canvas.Font.Name := BANNER_FONT_NAME;
    TempBmp.Canvas.Font.Size := FontSize;
    LineH := TempBmp.Canvas.TextHeight('Wg');
  finally
    TempBmp.Free;
  end;
  BannerH := BANNER_PADDING_V + Length(ALines) * (LineH + BANNER_LINE_GAP)
    - BANNER_LINE_GAP + BANNER_PADDING_V;

  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(ASrc.Width, BannerH + ASrc.Height);

  { Draw banner background }
  Result.Canvas.Brush.Color := BANNER_BG_COLOR;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, BannerH));

  { Draw text lines, truncating if needed }
  Result.Canvas.Font.Name := BANNER_FONT_NAME;
  Result.Canvas.Font.Size := FontSize;
  Result.Canvas.Font.Color := BANNER_TEXT_COLOR;
  Result.Canvas.Brush.Style := bsClear;
  for I := 0 to Length(ALines) - 1 do
  begin
    Line := TruncateToFit(Result.Canvas, ALines[I], MaxTextW);
    Result.Canvas.TextOut(BANNER_PADDING_H,
      BANNER_PADDING_V + I * (LineH + BANNER_LINE_GAP), Line);
  end;

  { Draw source image below banner }
  Result.Canvas.Draw(0, BannerH, ASrc);
end;

function RenderCombinedImage(const AFrames: TArray<TBitmap>;
  const AOffsets: TFrameOffsetArray; ACols, AGap: Integer;
  ABackground: TColor; AShowTimestamp: Boolean;
  const AFontName: string; AFontSize: Integer): TBitmap;
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

  { Use first non-nil frame dimensions as cell size }
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
  Result.SetSize(Cols * CellW + Max(Cols - 1, 0) * AGap,
                 Rows * CellH + Max(Rows - 1, 0) * AGap);
  Result.Canvas.Brush.Color := ABackground;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then Continue;
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
      { Shadow for readability }
      Result.Canvas.Font.Color := clBlack;
      Result.Canvas.Brush.Style := bsClear;
      Result.Canvas.TextOut(X + 5, Y + CellH - TH - 4, Tc);
      { Foreground text }
      Result.Canvas.Font.Color := clWhite;
      Result.Canvas.TextOut(X + 4, Y + CellH - TH - 5, Tc);
    end;
  end;
end;

end.
