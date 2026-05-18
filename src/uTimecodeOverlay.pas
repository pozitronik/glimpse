{Per-cell timecode overlay painters.

 The combined-image renderer supports two visually distinct timecode
 algorithms:

 - The "modern" path renders a flush-to-corner rectangle with an
   optional translucent background block and centred text. Matches what
   the WLX live view paints, so a saved combined sheet looks the same
   as the on-screen preview.

 - The "legacy" path renders the timecode as free-standing text inset
   by 4px from the cell edge with a 1px black drop shadow. Preserved
   pixel-exact for back-compat with WLX 1.0.x saved grids.

 Earlier code dispatched between the two paths by inspecting BackAlpha
 (treating 0 as a sentinel for "use legacy"). That conflated two
 distinct intents - "no background block on the modern path" versus
 "render the legacy algorithm entirely" - and meant a future fourth
 option (e.g. drop-shadow only on the modern path) would need yet
 another sentinel encoding. Mode now carries the choice explicitly;
 the painters are picked through this unit's factory.

 The two painter instances are cached unit-level so DrawCellTimecode
 does not allocate a fresh TInterfacedObject per cell on each render.
 The painters are stateless; sharing one instance across all callers
 is safe.}
unit uTimecodeOverlay;

interface

uses
  System.UITypes, System.Types,
  Vcl.Graphics,
  uTypes, uSettingsGroups;

type
  {Explicit selector between the two timecode rendering algorithms. Was
   previously inferred from BackAlpha (0 -> legacy, >0 -> modern) which
   conflated "user wanted no background block" with "render legacy
   shadow-only" - two distinct intents. Mode now carries the choice
   directly; BackAlpha controls only the background-block opacity within
   the modern path.

   - tsmModern: flush-to-corner rect with optional bg block + centred
     text (matches live view).
   - tsmLegacy: free-standing shadowed text inset by 4px (pixel-exact
     back-compat with WLX 1.0.x saved grids; ignores BackColor /
     BackAlpha).}
  TTimecodeStyleMode = (tsmModern, tsmLegacy);

  {Overlay style for per-cell timecodes. When Show=False nothing is drawn
   and the other fields are ignored. Mode picks the rendering
   algorithm; BackAlpha controls only the modern-path background block.}
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
    Mode: TTimecodeStyleMode;
    {Builds the rendering style from the persisted settings group.
     FontStyles is set to [] (WLX live-view convention); callers that
     want bold (WCX combined sheet) override Result.FontStyles := [fsBold]
     after the call. Mode is derived from BackAlpha via the historical
     sentinel-mapping helper. Show comes from the group; callers wanting
     to gate on a live-view toggle (WLX FFrameView.ShowTimecode) override
     Result.Show.}
    class function FromSettings(const AGroup: TTimestampSettingsGroup): TTimestampStyle; static;
  end;

  ITimecodeOverlayPainter = interface
    ['{4E8A1F3D-6B2C-49A7-B05E-C12F7D3A8B6E}']
    {Paints the timecode AText into ACellRect on ACanvas using AStyle.
     Implementations interpret ACellRect according to their algorithm:
     the modern painter derives a flush-to-corner sub-rectangle; the
     legacy painter positions text inset from the cell edge.}
    procedure Paint(ACanvas: TCanvas; const ACellRect: TRect;
      const AText: string; const AStyle: TTimestampStyle);
  end;

{Computes the historical Mode from a user-configured BackAlpha. Used
 by settings-driven construction sites to preserve the pre-Mode-field
 contract: BackAlpha=0 historically meant "render legacy"; any
 non-zero value meant "render modern". A future user-facing Mode
 setting would let this derivation be deleted.}
function TimecodeStyleModeFor(ABackAlpha: Byte): TTimecodeStyleMode;

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
 DrawLegacyTimecodeOverlay - its geometry (4px margin, non-centered
 text) diverges from the live view.}
procedure DrawTimecodeOverlay(ACanvas: TCanvas; const ARect: TRect; const AText: string; const AStyle: TTimestampStyle; ABgScratch: TBitmap = nil; ATextScratch: TBitmap = nil);

{Draws the "legacy-path" timecode overlay (black 1px drop shadow plus
 coloured text inset by 4px from the cell edge) into ACanvas using AStyle.
 Used by the combined-image renderer when AStyle.BackAlpha = 0 - a mode
 kept for pixel-exact back-compat with WLX 1.0.x saved grids.

 ACellRect is the cell the text should be positioned inside; the helper
 computes the exact text origin from AStyle.Corner. Set font/size/style
 is done internally so callers don't need to prime the canvas first.

 Opaque text (TextAlpha = 255) goes straight to ACanvas. Partial text
 opacity blits the shadow+text onto an offscreen bitmap and AlphaBlends
 the result back, preserving underlying pixel content that shadows would
 otherwise overwrite.}
procedure DrawLegacyTimecodeOverlay(ACanvas: TCanvas; const ACellRect: TRect; const AText: string; const AStyle: TTimestampStyle);

{Renders the per-cell timecode overlay for a combined-image cell. Picks
 between the modern path (flush-to-corner rect with background block, when
 AStyle.BackAlpha > 0) and the legacy path (free-standing shadowed text).
 Centralises the corner-rect math so the uniform-grid and smart-grid
 renders stay in lockstep.
 No-op when AStyle.Show is False or AStyle.Corner is tcNone - callers
 don't have to repeat that gating themselves.}
procedure DrawCellTimecode(ACanvas: TCanvas; const ACellRect: TRect; ATimeOffset: Double; const AStyle: TTimestampStyle);

  {Returns the painter responsible for AMode. The same instance is
   handed out across calls; never Free the result.}
function GetTimecodePainter(AMode: TTimecodeStyleMode): ITimecodeOverlayPainter;

implementation

uses
  Winapi.Windows, System.Math,
  uFrameOffsets;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   AlphaBlend / GDI calls) declares its own TBITMAP record alias that
   would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

type
  TModernRectPainter = class(TInterfacedObject, ITimecodeOverlayPainter)
  public
    procedure Paint(ACanvas: TCanvas; const ACellRect: TRect;
      const AText: string; const AStyle: TTimestampStyle);
  end;

  TLegacyShadowPainter = class(TInterfacedObject, ITimecodeOverlayPainter)
  public
    procedure Paint(ACanvas: TCanvas; const ACellRect: TRect;
      const AText: string; const AStyle: TTimestampStyle);
  end;

const
  TC_PADDING_H = 8; {horizontal padding inside the modern-path timecode rect}
  TC_MIN_H = 20;    {minimum height for the modern-path rect - live-view parity for small fonts}

var
  GModernPainter: ITimecodeOverlayPainter;
  GLegacyPainter: ITimecodeOverlayPainter;

class function TTimestampStyle.FromSettings(const AGroup: TTimestampSettingsGroup): TTimestampStyle;
begin
  Result.Show := AGroup.Show;
  Result.Corner := AGroup.Corner;
  Result.FontName := AGroup.FontName;
  Result.FontSize := AGroup.FontSize;
  Result.FontStyles := [];
  Result.BackColor := AGroup.BackColor;
  Result.BackAlpha := AGroup.BackAlpha;
  Result.TextColor := AGroup.TextColor;
  Result.TextAlpha := AGroup.TextAlpha;
  Result.Mode := TimecodeStyleModeFor(AGroup.BackAlpha);
end;

function TimecodeStyleModeFor(ABackAlpha: Byte): TTimecodeStyleMode;
begin
  if ABackAlpha = 0 then
    Result := tsmLegacy
  else
    Result := tsmModern;
end;

function GetTimecodePainter(AMode: TTimecodeStyleMode): ITimecodeOverlayPainter;
begin
  case AMode of
    tsmLegacy:
      Result := GLegacyPainter;
    else
      Result := GModernPainter;
  end;
end;

procedure DrawTimecodeOverlay(ACanvas: TCanvas; const ARect: TRect; const AText: string; const AStyle: TTimestampStyle; ABgScratch: TBitmap; ATextScratch: TBitmap);
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
      Winapi.Windows.AlphaBlend(ACanvas.Handle, ARect.Left, ARect.Top, ARect.Width, ARect.Height, BgBmp.Canvas.Handle, 0, 0, 1, 1, BF);
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
    DrawText(ACanvas.Handle, PChar(AText), -1, DrawR, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
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
    BitBlt(TextBmp.Canvas.Handle, 0, 0, ARect.Width, ARect.Height, ACanvas.Handle, ARect.Left, ARect.Top, SRCCOPY);
    TextBmp.Canvas.Font.Name := AStyle.FontName;
    TextBmp.Canvas.Font.Size := AStyle.FontSize;
    TextBmp.Canvas.Font.Style := AStyle.FontStyles;
    TextBmp.Canvas.Font.Color := AStyle.TextColor;
    TextBmp.Canvas.Brush.Style := bsClear;
    LocalR := Rect(0, 0, ARect.Width, ARect.Height);
    DrawText(TextBmp.Canvas.Handle, PChar(AText), -1, LocalR, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    BF.BlendOp := AC_SRC_OVER;
    BF.BlendFlags := 0;
    BF.SourceConstantAlpha := AStyle.TextAlpha;
    BF.AlphaFormat := 0;
    Winapi.Windows.AlphaBlend(ACanvas.Handle, ARect.Left, ARect.Top, ARect.Width, ARect.Height, TextBmp.Canvas.Handle, 0, 0, ARect.Width, ARect.Height, BF);
  finally
    if OwnsText then
      TextBmp.Free;
  end;
end;

procedure DrawLegacyTimecodeOverlay(ACanvas: TCanvas; const ACellRect: TRect; const AText: string; const AStyle: TTimestampStyle);
const
  TC_MARGIN = 4; {inset from the cell edge - historical WLX 1.0.x value}
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
  if R.Left < X then
    R.Left := X;
  if R.Top < Y then
    R.Top := Y;
  if R.Right > X + CellW then
    R.Right := X + CellW;
  if R.Bottom > Y + CellH then
    R.Bottom := Y + CellH;
  TextBmp := TBitmap.Create;
  try
    TextBmp.PixelFormat := pf24bit;
    TextBmp.SetSize(R.Width, R.Height);
    BitBlt(TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height, ACanvas.Handle, R.Left, R.Top, SRCCOPY);
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
    Winapi.Windows.AlphaBlend(ACanvas.Handle, R.Left, R.Top, R.Width, R.Height, TextBmp.Canvas.Handle, 0, 0, R.Width, R.Height, BF);
  finally
    TextBmp.Free;
  end;
end;

procedure DrawCellTimecode(ACanvas: TCanvas; const ACellRect: TRect; ATimeOffset: Double; const AStyle: TTimestampStyle);
begin
  if (not AStyle.Show) or (AStyle.Corner = tcNone) then
    Exit;
  GetTimecodePainter(AStyle.Mode).Paint(ACanvas, ACellRect,
    FormatTimecode(ATimeOffset), AStyle);
end;

{ TModernRectPainter }

procedure TModernRectPainter.Paint(ACanvas: TCanvas; const ACellRect: TRect;
  const AText: string; const AStyle: TTimestampStyle);
var
  TW, TH: Integer;
  R: TRect;
begin
  {Prime the canvas font so TextWidth/TextHeight match the rect the
   leaf overlay will then DrawText into.}
  ACanvas.Font.Name := AStyle.FontName;
  ACanvas.Font.Size := AStyle.FontSize;
  ACanvas.Font.Style := AStyle.FontStyles;

  TW := ACanvas.TextWidth(AText) + TC_PADDING_H;
  {Rect height floors at TC_MIN_H for live-view parity at small font
   sizes, but grows to fit when larger fonts would otherwise be clipped
   by DT_VCENTER inside a fixed rect.}
  TH := Max(ACanvas.TextHeight(AText) + 4, TC_MIN_H);
  case AStyle.Corner of
    tcTopLeft:
      R := Rect(ACellRect.Left, ACellRect.Top, ACellRect.Left + TW, ACellRect.Top + TH);
    tcTopRight:
      R := Rect(ACellRect.Right - TW, ACellRect.Top, ACellRect.Right, ACellRect.Top + TH);
    tcBottomRight:
      R := Rect(ACellRect.Right - TW, ACellRect.Bottom - TH, ACellRect.Right, ACellRect.Bottom);
    else {tcBottomLeft}
      R := Rect(ACellRect.Left, ACellRect.Bottom - TH, ACellRect.Left + TW, ACellRect.Bottom);
  end;
  DrawTimecodeOverlay(ACanvas, R, AText, AStyle);
end;

{ TLegacyShadowPainter }

procedure TLegacyShadowPainter.Paint(ACanvas: TCanvas; const ACellRect: TRect;
  const AText: string; const AStyle: TTimestampStyle);
begin
  DrawLegacyTimecodeOverlay(ACanvas, ACellRect, AText, AStyle);
end;

initialization

GModernPainter := TModernRectPainter.Create;
GLegacyPainter := TLegacyShadowPainter.Create;

finalization

GModernPainter := nil;
GLegacyPainter := nil;

end.
