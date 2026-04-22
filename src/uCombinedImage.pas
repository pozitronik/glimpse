{Renders multiple frame bitmaps into a single combined grid image.
 Pure rendering: no I/O, no settings dependency.}
unit uCombinedImage;

interface

uses
  Winapi.Windows, System.UITypes, Vcl.Graphics, uFrameOffsets, uFFmpegExe, uTypes;

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

  {Visual style and placement for the info banner. When AutoSize is True the
   renderer picks a font size using the historical width-based heuristic and
   shrinks to fit; when False it uses FontSize as a fixed point size and wraps
   overflowing lines instead of shrinking.}
  TBannerStyle = record
    Background: TColor;
    TextColor: TColor;
    FontName: string;
    FontSize: Integer;
    AutoSize: Boolean;
    Position: TBannerPosition;
  end;

  {Formats banner info into human-readable text lines.
   Returns an empty array if AInfo has no meaningful data.}
function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;

{Builds a TBannerInfo from a filename and probed video metadata.
 Reads file size from disk; all other fields come from AVideoInfo.}
function BuildBannerInfo(const AFileName: string; const AVideoInfo: TVideoInfo): TBannerInfo;

{Returns the historical defaults (dark bg, light text, Segoe UI, auto size, top).
 Useful for tests and as a fallback when a caller has no configured style.}
function DefaultBannerStyle: TBannerStyle;

{Attaches a solid-color info banner above or below an existing bitmap.
 @param ASrc Source bitmap (not freed; caller still owns it)
 @param ALines Text lines to display (empty array = no banner, returns copy of ASrc)
 @param AStyle Colors, font, and placement (top/bottom)
 @return New bitmap with banner attached. Caller owns result.}
function AttachBanner(ASrc: TBitmap; const ALines: TArray<string>; const AStyle: TBannerStyle): TBitmap;

{Renders all frames into a single grid image.
 @param AFrames Array of frame bitmaps (nil entries are skipped)
 @param AOffsets Frame time offsets (used for timestamp overlay)
 @param ACols Number of columns (0 = auto based on frame count)
 @param AGap Pixel gap between cells
 @param ABackground Background fill color
 @param AShowTimestamp Whether to overlay timecodes on each cell
 @param AFontName Font face for timestamp text
 @param AFontSize Font size in points for timestamp text
 @param ABorder Outer margin (pixels) painted with ABackground around the whole grid
 @param ATimestampCorner Corner where the timecode overlay is drawn on each cell
 @param ATimecodeBackColor Fill color for the optional timecode background block
 @param ATimecodeBackAlpha Opacity [0..255] for the background block; 0 selects the
        legacy shadow-only rendering for pixel-exact back-compat, values > 0 switch
        to the modern flush-rect rendering matching the live view's overlay
 @param ATimestampTextColor Foreground color for the timecode text
 @param ATimestampTextAlpha Opacity [0..255] for the timecode text
 @return Combined bitmap, or nil if AFrames is empty. Caller owns result.}
function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; ACols, AGap: Integer; ABackground: TColor; AShowTimestamp: Boolean; const AFontName: string; AFontSize: Integer; ABorder: Integer = 0; ATimestampCorner: TTimestampCorner = tcBottomLeft; ATimecodeBackColor: TColor = clBlack; ATimecodeBackAlpha: Byte = 0; ATimestampTextColor: TColor = clWhite; ATimestampTextAlpha: Byte = 255): TBitmap;

implementation

uses
  System.SysUtils, System.IOUtils, System.Math, System.Types,
  uDefaults;

const
  BANNER_PADDING_H = 10; {horizontal padding}
  BANNER_PADDING_V = 6; {vertical padding (top and bottom)}
  BANNER_LINE_GAP = 2; {extra spacing between lines}
  BANNER_FONT_MIN = 8; {minimum font size for auto-scale}
  BANNER_FONT_MAX = 16; {maximum font size for auto-scale}
  BANNER_FONT_RATIO = 55; {image width divisor for auto-scale font size}
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

function DefaultBannerStyle: TBannerStyle;
begin
  Result.Background := DEF_BANNER_BACKGROUND;
  Result.TextColor := DEF_BANNER_TEXT_COLOR;
  Result.FontName := DEF_BANNER_FONT_NAME;
  Result.FontSize := DEF_BANNER_FONT_SIZE;
  Result.AutoSize := DEF_BANNER_FONT_AUTO_SIZE;
  Result.Position := DEF_BANNER_POSITION;
end;

function AttachBanner(ASrc: TBitmap; const ALines: TArray<string>; const AStyle: TBannerStyle): TBitmap;
var
  FontSize, LineH, BannerH, MaxTextW, BannerY, SrcY, I: Integer;
  TempBmp: TBitmap;
  Wrapped, RenderLines: TArray<string>;
  FontName: string;
begin
  if (Length(ALines) = 0) or (ASrc = nil) then
  begin
    {Return a copy so the caller always gets an owned bitmap}
    Result := TBitmap.Create;
    if ASrc <> nil then
      Result.Assign(ASrc);
    Exit;
  end;

  FontName := AStyle.FontName;
  if FontName.Trim = '' then
    FontName := DEF_BANNER_FONT_NAME;
  MaxTextW := ASrc.Width - 2 * BANNER_PADDING_H;

  {Measure on a temp bitmap so the result canvas isn't dirtied with
   intermediate font states during the shrink probe.}
  TempBmp := TBitmap.Create;
  try
    TempBmp.Canvas.Font.Name := FontName;

    if AStyle.AutoSize then
      {Auto mode: historical width-based ratio, then shrink until every
       line fits (or bottom out at BANNER_FONT_MIN and rely on wrapping).}
      FontSize := FindFittingBannerFontSize(TempBmp.Canvas, ALines, EnsureRange(ASrc.Width div BANNER_FONT_RATIO, BANNER_FONT_MIN, BANNER_FONT_MAX), MaxTextW)
    else
      {Fixed mode: user-chosen size; overflow is handled by wrapping only.}
      FontSize := AStyle.FontSize;
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

  if AStyle.Position = bpBottom then
  begin
    SrcY := 0;
    BannerY := ASrc.Height;
  end
  else
  begin
    BannerY := 0;
    SrcY := BannerH;
  end;

  {Draw banner background}
  Result.Canvas.Brush.Color := AStyle.Background;
  Result.Canvas.FillRect(Rect(0, BannerY, Result.Width, BannerY + BannerH));

  {Draw text lines (already fitted by shrink + wrap; no truncation pass)}
  Result.Canvas.Font.Name := FontName;
  Result.Canvas.Font.Size := FontSize;
  Result.Canvas.Font.Color := AStyle.TextColor;
  Result.Canvas.Brush.Style := bsClear;
  for I := 0 to High(RenderLines) do
    Result.Canvas.TextOut(BANNER_PADDING_H, BannerY + BANNER_PADDING_V + I * (LineH + BANNER_LINE_GAP), RenderLines[I]);

  {Draw source image in the remaining region}
  Result.Canvas.Draw(0, SrcY, ASrc);
end;

function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray; ACols, AGap: Integer; ABackground: TColor; AShowTimestamp: Boolean; const AFontName: string; AFontSize: Integer; ABorder: Integer; ATimestampCorner: TTimestampCorner; ATimecodeBackColor: TColor; ATimecodeBackAlpha: Byte; ATimestampTextColor: TColor; ATimestampTextAlpha: Byte): TBitmap;
const
  TC_MARGIN = 4; {distance from the cell edge to the timecode bounding box (legacy path)}
  TC_PADDING_H = 8; {horizontal padding inside the modern-path timecode rect}
  TC_MIN_H = 20; {minimum height for the modern-path timecode rect (live-view parity for small fonts)}
var
  Cols, Rows, CellW, CellH, I, Row, Col, X, Y: Integer;
  FrameCount: Integer;
  Tc: string;
  TW, TH, TX, TY: Integer;
  Border: Integer;
  R, LocalR: TRect;
  BF: TBlendFunction;
  BgBmp, TextBmp: Vcl.Graphics.TBitmap;
begin
  FrameCount := Length(AFrames);
  if FrameCount = 0 then
    Exit(nil);

  Border := ABorder;
  if Border < 0 then
    Border := 0;

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
  Result.SetSize(Cols * CellW + Max(Cols - 1, 0) * AGap + 2 * Border, Rows * CellH + Max(Rows - 1, 0) * AGap + 2 * Border);
  Result.Canvas.Brush.Color := ABackground;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then
      Continue;
    Row := I div Cols;
    Col := I mod Cols;
    X := Border + Col * (CellW + AGap);
    Y := Border + Row * (CellH + AGap);
    Result.Canvas.Draw(X, Y, AFrames[I]);

    if AShowTimestamp and (ATimestampCorner <> tcNone) and (I < Length(AOffsets)) then
    begin
      Tc := FormatTimecode(AOffsets[I].TimeOffset);
      Result.Canvas.Font.Name := AFontName;
      Result.Canvas.Font.Size := AFontSize;
      Result.Canvas.Font.Style := [fsBold];

      if ATimecodeBackAlpha > 0 then
      begin
        {Modern path: flush-to-corner rect with bg block and centered text (matches live view).
         Rect height floors at TC_MIN_H for live-view parity at small font sizes, but grows to
         fit when larger fonts would otherwise be clipped by DT_VCENTER inside a fixed rect.}
        TW := Result.Canvas.TextWidth(Tc) + TC_PADDING_H;
        TH := Max(Result.Canvas.TextHeight(Tc) + 4, TC_MIN_H);
        case ATimestampCorner of
          tcTopLeft:
            R := Rect(X, Y, X + TW, Y + TH);
          tcTopRight:
            R := Rect(X + CellW - TW, Y, X + CellW, Y + TH);
          tcBottomRight:
            R := Rect(X + CellW - TW, Y + CellH - TH, X + CellW, Y + CellH);
          else {tcBottomLeft}
            R := Rect(X, Y + CellH - TH, X + TW, Y + CellH);
        end;

        if ATimecodeBackAlpha = 255 then
        begin
          Result.Canvas.Brush.Color := ATimecodeBackColor;
          Result.Canvas.Brush.Style := bsSolid;
          Result.Canvas.FillRect(R);
        end else begin
          {Partial opacity bg: stretch a 1x1 color bitmap via AlphaBlend}
          BgBmp := Vcl.Graphics.TBitmap.Create;
          try
            BgBmp.PixelFormat := pf24bit;
            BgBmp.SetSize(1, 1);
            BgBmp.Canvas.Pixels[0, 0] := ATimecodeBackColor;
            BF.BlendOp := AC_SRC_OVER;
            BF.BlendFlags := 0;
            BF.SourceConstantAlpha := ATimecodeBackAlpha;
            BF.AlphaFormat := 0;
            Winapi.Windows.AlphaBlend(Result.Canvas.Handle, R.Left, R.Top, R.Width, R.Height, BgBmp.Canvas.Handle, 0, 0, 1, 1, BF);
          finally
            BgBmp.Free;
          end;
        end;

        if ATimestampTextAlpha > 0 then
        begin
          if ATimestampTextAlpha = 255 then
          begin
            Result.Canvas.Font.Color := ATimestampTextColor;
            Result.Canvas.Brush.Style := bsClear;
            DrawText(Result.Canvas.Handle, PChar(Tc), -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
          end else begin
            {Partial text opacity: render onto an offscreen copy of the rect, then AlphaBlend back}
            TextBmp := Vcl.Graphics.TBitmap.Create;
            try
              TextBmp.PixelFormat := pf24bit;
              TextBmp.SetSize(R.Width, R.Height);
              BitBlt(TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height, Result.Canvas.Handle, R.Left, R.Top, SRCCOPY);
              TextBmp.Canvas.Font.Name := AFontName;
              TextBmp.Canvas.Font.Size := AFontSize;
              TextBmp.Canvas.Font.Style := [fsBold];
              TextBmp.Canvas.Font.Color := ATimestampTextColor;
              TextBmp.Canvas.Brush.Style := bsClear;
              LocalR := Rect(0, 0, R.Width, R.Height);
              DrawText(TextBmp.Canvas.Handle, PChar(Tc), -1, LocalR, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
              BF.BlendOp := AC_SRC_OVER;
              BF.BlendFlags := 0;
              BF.SourceConstantAlpha := ATimestampTextAlpha;
              BF.AlphaFormat := 0;
              Winapi.Windows.AlphaBlend(Result.Canvas.Handle, R.Left, R.Top, R.Width, R.Height, TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height, BF);
            finally
              TextBmp.Free;
            end;
          end;
        end;
      end else begin
        {Legacy path: shadow + text at TC_MARGIN from the cell edge.
         Preserves pixel-exact back-compat when text defaults are in effect
         (clWhite foreground, full opacity, black shadow).}
        TW := Result.Canvas.TextWidth(Tc);
        TH := Result.Canvas.TextHeight(Tc);
        case ATimestampCorner of
          tcTopLeft:
            begin
              TX := X + TC_MARGIN;
              TY := Y + TC_MARGIN;
            end;
          tcTopRight:
            begin
              TX := X + CellW - TW - TC_MARGIN;
              TY := Y + TC_MARGIN;
            end;
          tcBottomRight:
            begin
              TX := X + CellW - TW - TC_MARGIN;
              TY := Y + CellH - TH - TC_MARGIN;
            end;
          else {tcBottomLeft}
            begin
              TX := X + TC_MARGIN;
              TY := Y + CellH - TH - TC_MARGIN;
            end;
        end;

        if ATimestampTextAlpha = 255 then
        begin
          {Shadow for readability (1-pixel offset to the lower-right of the foreground text)}
          Result.Canvas.Brush.Style := bsClear;
          Result.Canvas.Font.Color := clBlack;
          Result.Canvas.TextOut(TX + 1, TY + 1, Tc);
          {Foreground text}
          Result.Canvas.Font.Color := ATimestampTextColor;
          Result.Canvas.TextOut(TX, TY, Tc);
        end else if ATimestampTextAlpha > 0 then
        begin
          {Partial opacity with shadow: render shadow + text onto an offscreen copy of the region,
           then AlphaBlend back. The region spans the shadow's extra pixel on the bottom-right.}
          R := Rect(TX, TY, TX + TW + 2, TY + TH + 2);
          if R.Left < X then R.Left := X;
          if R.Top < Y then R.Top := Y;
          if R.Right > X + CellW then R.Right := X + CellW;
          if R.Bottom > Y + CellH then R.Bottom := Y + CellH;
          TextBmp := Vcl.Graphics.TBitmap.Create;
          try
            TextBmp.PixelFormat := pf24bit;
            TextBmp.SetSize(R.Width, R.Height);
            BitBlt(TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height, Result.Canvas.Handle, R.Left, R.Top, SRCCOPY);
            TextBmp.Canvas.Font.Name := AFontName;
            TextBmp.Canvas.Font.Size := AFontSize;
            TextBmp.Canvas.Font.Style := [fsBold];
            TextBmp.Canvas.Brush.Style := bsClear;
            TextBmp.Canvas.Font.Color := clBlack;
            TextBmp.Canvas.TextOut(TX + 1 - R.Left, TY + 1 - R.Top, Tc);
            TextBmp.Canvas.Font.Color := ATimestampTextColor;
            TextBmp.Canvas.TextOut(TX - R.Left, TY - R.Top, Tc);
            BF.BlendOp := AC_SRC_OVER;
            BF.BlendFlags := 0;
            BF.SourceConstantAlpha := ATimestampTextAlpha;
            BF.AlphaFormat := 0;
            Winapi.Windows.AlphaBlend(Result.Canvas.Handle, R.Left, R.Top, R.Width, R.Height, TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height, BF);
          finally
            TextBmp.Free;
          end;
        end;
      end;
    end;
  end;
end;

end.
