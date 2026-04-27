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
    {Storage pixel grid dimensions (what's actually encoded).}
    Width, Height: Integer;
    {Display dimensions (storage * SAR). Equal to Width/Height for
     non-anamorphic sources. When they differ, FormatBannerLines renders
     "<sw>x<sh> -> <dw>x<dh>" so the banner reflects both the source's
     stored geometry and the corrected geometry the saved frames carry.}
    DisplayWidth, DisplayHeight: Integer;
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

  {Grid geometry for the combined image. Columns = 0 means "auto" (ceil(sqrt(n)));
   Border is the outer margin painted with Background around the whole grid.
   BackgroundAlpha controls how opaque the gap/border fill is in the rendered
   bitmap: 255 keeps the historical pf24bit output unchanged; values < 255
   produce a pf32bit bitmap whose gap/border pixels carry that alpha while
   frame pixels stay fully opaque.}
  TCombinedGridStyle = record
    Columns: Integer;
    CellGap: Integer;
    Border: Integer;
    Background: TColor;
    BackgroundAlpha: Byte;
  end;

  {Overlay style for per-cell timecodes. When Show=False nothing is drawn and
   the other fields are ignored. BackAlpha=0 selects the legacy shadow-only
   rendering (pixel-exact back-compat); values > 0 switch to the modern
   flush-rect rendering that matches the live view's overlay.}
  TTimestampStyle = record
    Show: Boolean;
    Corner: TTimestampCorner;
    FontName: string;
    FontSize: Integer;
    FontStyles: TFontStyles;
    BackColor: TColor;
    BackAlpha: Byte;
    TextColor: TColor;
    TextAlpha: Byte;
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

{Draws the "modern-path" timecode overlay (flush-rect background block plus
 centred text) into ACanvas at ARect using AStyle. Handles every combination
 of opaque/partial background and opaque/partial text alpha required by both
 the WLX live view and the WCX combined-image renderer.

 Optional scratch bitmaps let callers reuse persistent buffers across
 repeated calls (the live view repaints every cell on every frame). When
 nil, the helper allocates local buffers for the duration of the call.
 ABgScratch needs to be a 1x1 pf24bit bitmap (or may start empty; the
 helper resizes on demand). ATextScratch is grown to fit the rect.

 The legacy shadow-only rendering (BackAlpha = 0) is handled by
 DrawLegacyTimecodeOverlay — its geometry (4px margin, non-centered
 text) diverges from the live view.}
procedure DrawTimecodeOverlay(ACanvas: TCanvas; const ARect: TRect;
  const AText: string; const AStyle: TTimestampStyle;
  ABgScratch: TBitmap = nil; ATextScratch: TBitmap = nil);

{Draws the "legacy-path" timecode overlay (black 1px drop shadow plus
 coloured text inset by 4px from the cell edge) into ACanvas using AStyle.
 Used by the combined-image renderer when AStyle.BackAlpha = 0 — a mode
 kept for pixel-exact back-compat with WLX 1.0.x saved grids.

 ACellRect is the cell the text should be positioned inside; the helper
 computes the exact text origin from AStyle.Corner. Set font/size/style
 is done internally so callers don't need to prime the canvas first.

 Opaque text (TextAlpha = 255) goes straight to ACanvas. Partial text
 opacity blits the shadow+text onto an offscreen bitmap and AlphaBlends
 the result back, preserving underlying pixel content that shadows would
 otherwise overwrite.}
procedure DrawLegacyTimecodeOverlay(ACanvas: TCanvas; const ACellRect: TRect;
  const AText: string; const AStyle: TTimestampStyle);

{Returns the historical defaults for the grid layout (auto columns, no gap,
 no border, black background). Callers override individual fields as needed.}
function DefaultCombinedGridStyle: TCombinedGridStyle;

{Returns the historical defaults for the timestamp overlay (hidden, bottom-left,
 Consolas 9pt, black legacy-shadow background, white text). Callers override
 individual fields as needed.}
function DefaultTimestampStyle: TTimestampStyle;

{Renders all frames into a single grid image.
 @param AFrames Array of frame bitmaps (nil entries are skipped)
 @param AOffsets Frame time offsets (used for the timestamp overlay)
 @param AGrid Grid geometry (columns, gap, border, background)
 @param ATimestamp Per-cell timecode overlay style; ignored when Show=False
 @return Combined bitmap, or nil if AFrames is empty. Caller owns result.}
function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray;
  const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;

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
  Result.DisplayWidth := AVideoInfo.DisplayWidth;
  Result.DisplayHeight := AVideoInfo.DisplayHeight;
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
    {Anamorphic: storage and display dimensions diverge. Show both so the
     banner explains why the saved combined image is wider than the raw
     "WxH" reported by mediainfo et al.}
    if (AInfo.DisplayWidth > 0) and (AInfo.DisplayHeight > 0) and
      ((AInfo.DisplayWidth <> AInfo.Width) or (AInfo.DisplayHeight <> AInfo.Height)) then
      Line2 := Line2 + Format('%dx%d -> %dx%d',
        [AInfo.Width, AInfo.Height, AInfo.DisplayWidth, AInfo.DisplayHeight])
    else
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

procedure DrawTimecodeOverlay(ACanvas: TCanvas; const ARect: TRect;
  const AText: string; const AStyle: TTimestampStyle;
  ABgScratch: TBitmap; ATextScratch: TBitmap);
var
  BF: TBlendFunction;
  BgBmp, TextBmp: TBitmap;
  OwnsBg, OwnsText: Boolean;
  DrawR, LocalR: TRect;
begin
  {Background block: opaque => FillRect; partial => stretch a 1x1 color
   bitmap via AlphaBlend; zero => skip (used when only text is desired)}
  if AStyle.BackAlpha = 255 then
  begin
    ACanvas.Brush.Color := AStyle.BackColor;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.FillRect(ARect);
  end else if AStyle.BackAlpha > 0 then
  begin
    OwnsBg := ABgScratch = nil;
    if OwnsBg then
      BgBmp := TBitmap.Create
    else
      BgBmp := ABgScratch;
    try
      if (BgBmp.Width <> 1) or (BgBmp.Height <> 1) then
      begin
        BgBmp.PixelFormat := pf24bit;
        BgBmp.SetSize(1, 1);
      end;
      BgBmp.Canvas.Pixels[0, 0] := AStyle.BackColor;
      BF.BlendOp := AC_SRC_OVER;
      BF.BlendFlags := 0;
      BF.SourceConstantAlpha := AStyle.BackAlpha;
      BF.AlphaFormat := 0;
      Winapi.Windows.AlphaBlend(ACanvas.Handle, ARect.Left, ARect.Top,
        ARect.Width, ARect.Height, BgBmp.Canvas.Handle, 0, 0, 1, 1, BF);
    finally
      if OwnsBg then
        BgBmp.Free;
    end;
  end;

  if AStyle.TextAlpha = 0 then
    Exit;

  ACanvas.Font.Name := AStyle.FontName;
  ACanvas.Font.Size := AStyle.FontSize;
  ACanvas.Font.Style := AStyle.FontStyles;

  if AStyle.TextAlpha = 255 then
  begin
    {Fast path: opaque text painted straight onto ACanvas.}
    ACanvas.Font.Color := AStyle.TextColor;
    ACanvas.Brush.Style := bsClear;
    DrawR := ARect;
    DrawText(ACanvas.Handle, PChar(AText), -1, DrawR,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    Exit;
  end;

  {Partial text opacity: blit the rect into an offscreen bitmap, DrawText
   onto it, then AlphaBlend it back with SourceConstantAlpha so the text
   blends with pixels already painted underneath (frame, background block).}
  OwnsText := ATextScratch = nil;
  if OwnsText then
    TextBmp := TBitmap.Create
  else
    TextBmp := ATextScratch;
  try
    TextBmp.PixelFormat := pf24bit;
    if (TextBmp.Width < ARect.Width) or (TextBmp.Height < ARect.Height) then
      TextBmp.SetSize(Max(ARect.Width, TextBmp.Width), Max(ARect.Height, TextBmp.Height));
    BitBlt(TextBmp.Canvas.Handle, 0, 0, ARect.Width, ARect.Height,
      ACanvas.Handle, ARect.Left, ARect.Top, SRCCOPY);
    TextBmp.Canvas.Font.Name := AStyle.FontName;
    TextBmp.Canvas.Font.Size := AStyle.FontSize;
    TextBmp.Canvas.Font.Style := AStyle.FontStyles;
    TextBmp.Canvas.Font.Color := AStyle.TextColor;
    TextBmp.Canvas.Brush.Style := bsClear;
    LocalR := Rect(0, 0, ARect.Width, ARect.Height);
    DrawText(TextBmp.Canvas.Handle, PChar(AText), -1, LocalR,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    BF.BlendOp := AC_SRC_OVER;
    BF.BlendFlags := 0;
    BF.SourceConstantAlpha := AStyle.TextAlpha;
    BF.AlphaFormat := 0;
    Winapi.Windows.AlphaBlend(ACanvas.Handle, ARect.Left, ARect.Top,
      ARect.Width, ARect.Height, TextBmp.Canvas.Handle, 0, 0,
      ARect.Width, ARect.Height, BF);
  finally
    if OwnsText then
      TextBmp.Free;
  end;
end;

procedure DrawLegacyTimecodeOverlay(ACanvas: TCanvas; const ACellRect: TRect;
  const AText: string; const AStyle: TTimestampStyle);
const
  TC_MARGIN = 4; {inset from the cell edge — historical WLX 1.0.x value}
var
  TW, TH, TX, TY: Integer;
  X, Y, CellW, CellH: Integer;
  R: TRect;
  TextBmp: TBitmap;
  BF: TBlendFunction;
begin
  if AStyle.TextAlpha = 0 then
    Exit;

  ACanvas.Font.Name := AStyle.FontName;
  ACanvas.Font.Size := AStyle.FontSize;
  ACanvas.Font.Style := AStyle.FontStyles;

  TW := ACanvas.TextWidth(AText);
  TH := ACanvas.TextHeight(AText);

  X := ACellRect.Left;
  Y := ACellRect.Top;
  CellW := ACellRect.Width;
  CellH := ACellRect.Height;
  case AStyle.Corner of
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

  if AStyle.TextAlpha = 255 then
  begin
    {Opaque fast path: shadow then foreground, 1px offset.}
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := clBlack;
    ACanvas.TextOut(TX + 1, TY + 1, AText);
    ACanvas.Font.Color := AStyle.TextColor;
    ACanvas.TextOut(TX, TY, AText);
    Exit;
  end;

  {Partial opacity: render shadow + text onto an offscreen snapshot of the
   text region, then AlphaBlend the result back. R spans one extra pixel
   on the bottom-right to include the shadow offset, clipped to the cell.}
  R := Rect(TX, TY, TX + TW + 2, TY + TH + 2);
  if R.Left < X then R.Left := X;
  if R.Top < Y then R.Top := Y;
  if R.Right > X + CellW then R.Right := X + CellW;
  if R.Bottom > Y + CellH then R.Bottom := Y + CellH;
  TextBmp := TBitmap.Create;
  try
    TextBmp.PixelFormat := pf24bit;
    TextBmp.SetSize(R.Width, R.Height);
    BitBlt(TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height,
      ACanvas.Handle, R.Left, R.Top, SRCCOPY);
    TextBmp.Canvas.Font.Name := AStyle.FontName;
    TextBmp.Canvas.Font.Size := AStyle.FontSize;
    TextBmp.Canvas.Font.Style := AStyle.FontStyles;
    TextBmp.Canvas.Brush.Style := bsClear;
    TextBmp.Canvas.Font.Color := clBlack;
    TextBmp.Canvas.TextOut(TX + 1 - R.Left, TY + 1 - R.Top, AText);
    TextBmp.Canvas.Font.Color := AStyle.TextColor;
    TextBmp.Canvas.TextOut(TX - R.Left, TY - R.Top, AText);
    BF.BlendOp := AC_SRC_OVER;
    BF.BlendFlags := 0;
    BF.SourceConstantAlpha := AStyle.TextAlpha;
    BF.AlphaFormat := 0;
    Winapi.Windows.AlphaBlend(ACanvas.Handle, R.Left, R.Top,
      R.Width, R.Height, TextBmp.Canvas.Handle, 0, 0,
      R.Width, R.Height, BF);
  finally
    TextBmp.Free;
  end;
end;

function DefaultCombinedGridStyle: TCombinedGridStyle;
begin
  Result.Columns := 0;
  Result.CellGap := 0;
  Result.Border := DEF_COMBINED_BORDER;
  Result.Background := clBlack;
  Result.BackgroundAlpha := DEF_BACKGROUND_ALPHA;
end;

{Lifts the rendered pf24bit grid into a pf32bit bitmap. Frame cell rects
 get alpha=255 (opaque); everything else (gaps, border) carries
 ABackgroundAlpha. Called by RenderCombinedImage when alpha < 255 so the
 historical pf24bit fast path is unaffected for opaque output.}
function LiftToAlphaAware(ASource: TBitmap; const AGrid: TCombinedGridStyle;
  const AFrames: TArray<TBitmap>; ACols, ACellW, ACellH, ABorder: Integer): TBitmap;
type
  TQuadRow = array [0 .. 0] of TRGBQuad;
  PQuadRow = ^TQuadRow;
  TTripleRow = array [0 .. 0] of TRGBTriple;
  PTripleRow = ^TTripleRow;
var
  Bg: TRGBQuad;
  X, Y, I, Row, Col, FrameX, FrameY, Px, Py: Integer;
  DstRow: PQuadRow;
  SrcRow: PTripleRow;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf32bit;
    Result.AlphaFormat := afDefined;
    Result.SetSize(ASource.Width, ASource.Height);

    Bg.rgbBlue := GetBValue(AGrid.Background);
    Bg.rgbGreen := GetGValue(AGrid.Background);
    Bg.rgbRed := GetRValue(AGrid.Background);
    Bg.rgbReserved := AGrid.BackgroundAlpha;

    {Initial fill: gap/border colour + BackgroundAlpha. Outside-cell pixels
     never get touched again, so the gap/border becomes alpha-aware here.}
    for Y := 0 to Result.Height - 1 do
    begin
      DstRow := PQuadRow(Result.ScanLine[Y]);
      for X := 0 to Result.Width - 1 do
        DstRow^[X] := Bg;
    end;

    {Each non-nil frame's cell rect: copy RGB from the pf24bit source,
     alpha=255. Captures both the frame pixels and any timecode overlay
     that was drawn within the cell rect.}
    for I := 0 to High(AFrames) do
    begin
      if AFrames[I] = nil then
        Continue;
      Row := I div ACols;
      Col := I mod ACols;
      FrameX := ABorder + Col * (ACellW + AGrid.CellGap);
      FrameY := ABorder + Row * (ACellH + AGrid.CellGap);
      for Py := 0 to ACellH - 1 do
      begin
        if (FrameY + Py < 0) or (FrameY + Py >= Result.Height) then
          Continue;
        SrcRow := PTripleRow(ASource.ScanLine[FrameY + Py]);
        DstRow := PQuadRow(Result.ScanLine[FrameY + Py]);
        for Px := 0 to ACellW - 1 do
        begin
          if (FrameX + Px < 0) or (FrameX + Px >= Result.Width) then
            Continue;
          DstRow^[FrameX + Px].rgbBlue := SrcRow^[FrameX + Px].rgbtBlue;
          DstRow^[FrameX + Px].rgbGreen := SrcRow^[FrameX + Px].rgbtGreen;
          DstRow^[FrameX + Px].rgbRed := SrcRow^[FrameX + Px].rgbtRed;
          DstRow^[FrameX + Px].rgbReserved := 255;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function DefaultTimestampStyle: TTimestampStyle;
begin
  Result.Show := False;
  Result.Corner := DEF_TIMESTAMP_CORNER;
  Result.FontName := 'Consolas';
  Result.FontSize := 9;
  Result.FontStyles := [fsBold];
  Result.BackColor := DEF_TC_BACK_COLOR;
  Result.BackAlpha := 0;
  Result.TextColor := DEF_TIMESTAMP_TEXT_COLOR;
  Result.TextAlpha := DEF_TIMESTAMP_TEXT_ALPHA;
end;

function RenderCombinedImage(const AFrames: TArray<TBitmap>; const AOffsets: TFrameOffsetArray;
  const AGrid: TCombinedGridStyle; const ATimestamp: TTimestampStyle): TBitmap;
const
  TC_PADDING_H = 8; {horizontal padding inside the modern-path timecode rect}
  TC_MIN_H = 20; {minimum height for the modern-path timecode rect (live-view parity for small fonts)}
var
  Cols, Rows, CellW, CellH, I, Row, Col, X, Y: Integer;
  FrameCount: Integer;
  Tc: string;
  TW, TH: Integer;
  Border: Integer;
  R: TRect;
  Lifted: TBitmap;
begin
  FrameCount := Length(AFrames);
  if FrameCount = 0 then
    Exit(nil);

  Border := AGrid.Border;
  if Border < 0 then
    Border := 0;

  Cols := AGrid.Columns;
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
  Result.SetSize(Cols * CellW + Max(Cols - 1, 0) * AGrid.CellGap + 2 * Border, Rows * CellH + Max(Rows - 1, 0) * AGrid.CellGap + 2 * Border);
  Result.Canvas.Brush.Color := AGrid.Background;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then
      Continue;
    Row := I div Cols;
    Col := I mod Cols;
    X := Border + Col * (CellW + AGrid.CellGap);
    Y := Border + Row * (CellH + AGrid.CellGap);
    Result.Canvas.Draw(X, Y, AFrames[I]);

    if ATimestamp.Show and (ATimestamp.Corner <> tcNone) and (I < Length(AOffsets)) then
    begin
      Tc := FormatTimecode(AOffsets[I].TimeOffset);
      {Prime the canvas font so TextWidth/TextHeight match the final render in
       both branches below.}
      Result.Canvas.Font.Name := ATimestamp.FontName;
      Result.Canvas.Font.Size := ATimestamp.FontSize;
      Result.Canvas.Font.Style := ATimestamp.FontStyles;

      if ATimestamp.BackAlpha > 0 then
      begin
        {Modern path: flush-to-corner rect with bg block and centered text (matches live view).
         Rect height floors at TC_MIN_H for live-view parity at small font sizes, but grows to
         fit when larger fonts would otherwise be clipped by DT_VCENTER inside a fixed rect.}
        TW := Result.Canvas.TextWidth(Tc) + TC_PADDING_H;
        TH := Max(Result.Canvas.TextHeight(Tc) + 4, TC_MIN_H);
        case ATimestamp.Corner of
          tcTopLeft:
            R := Rect(X, Y, X + TW, Y + TH);
          tcTopRight:
            R := Rect(X + CellW - TW, Y, X + CellW, Y + TH);
          tcBottomRight:
            R := Rect(X + CellW - TW, Y + CellH - TH, X + CellW, Y + CellH);
          else {tcBottomLeft}
            R := Rect(X, Y + CellH - TH, X + TW, Y + CellH);
        end;

        DrawTimecodeOverlay(Result.Canvas, R, Tc, ATimestamp);
      end else begin
        DrawLegacyTimecodeOverlay(Result.Canvas,
          Rect(X, Y, X + CellW, Y + CellH), Tc, ATimestamp);
      end;
    end;
  end;

  {Optional alpha-aware output. When BackgroundAlpha is 255 the pf24bit
   Result is exactly the historical output (no behaviour change). For
   alpha < 255 we lift into pf32bit so PNG savers preserve the gap/border
   transparency; frame pixels stay at alpha=255 because they are
   conceptually opaque content.}
  if AGrid.BackgroundAlpha < 255 then
  begin
    Lifted := LiftToAlphaAware(Result, AGrid, AFrames, Cols, CellW, CellH, Border);
    Result.Free;
    Result := Lifted;
  end;
end;

end.
