{Per-cell timecode overlay painters.

 Two algorithms:
 - Modern: flush-to-corner rect with optional translucent background
   block and centred text (matches WLX live view).
 - Legacy: free-standing text inset 4px with 1px black drop shadow
   (pixel-exact back-compat with WLX 1.0.x saved grids).

 Painters are stateless TInterfacedObject instances cached unit-level
 so DrawCellTimecode does not allocate per cell on every render.}
unit TimecodeOverlay;

interface

uses
  System.UITypes, System.Types,
  Vcl.Graphics,
  Types, SettingsGroups;

type
  {tsmModern: flush-to-corner rect with optional bg block + centred text.
   tsmLegacy: free-standing shadowed text inset 4px (ignores BackColor
   and BackAlpha).}
  TTimecodeStyleMode = (tsmModern, tsmLegacy);

  {When Show=False nothing is drawn and other fields are ignored. Mode
   picks the algorithm; BackAlpha controls only the modern-path
   background block.}
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
    {FontStyles defaults to [] (WLX live-view convention); callers that
     want bold (WCX combined sheet) override after the call. Mode is
     derived from BackAlpha via TimecodeStyleModeFor. Callers wanting to
     gate on a live-view toggle override Result.Show.}
    class function FromSettings(const AGroup: TTimestampSettingsGroup): TTimestampStyle; static;
  end;

  ITimecodeOverlayPainter = interface
    ['{4E8A1F3D-6B2C-49A7-B05E-C12F7D3A8B6E}']
    {The modern painter derives a flush-to-corner sub-rectangle from
     ACellRect; the legacy painter positions text inset from the cell edge.}
    procedure Paint(ACanvas: TCanvas; const ACellRect: TRect;
      const AText: string; const AStyle: TTimestampStyle);
  end;

{Historical sentinel-mapping: BackAlpha=0 means legacy, anything else
 means modern.}
function TimecodeStyleModeFor(ABackAlpha: Byte): TTimecodeStyleMode;

{Modern-path overlay: flush-rect background block plus centred text.
 Optional scratch bitmaps let callers reuse persistent buffers across
 repeated calls (the live view repaints every cell every frame); when
 nil, the helper allocates local buffers for the call.}
procedure DrawTimecodeOverlay(ACanvas: TCanvas; const ARect: TRect; const AText: string; const AStyle: TTimestampStyle; ABgScratch: TBitmap = nil; ATextScratch: TBitmap = nil);

{Legacy-path overlay: 1px black drop shadow plus coloured text inset
 4px from the cell edge. Used when BackAlpha=0 — pixel-exact back-compat
 with WLX 1.0.x. Partial text opacity blits shadow+text onto an offscreen
 bitmap and AlphaBlends back so underlying pixels survive.}
procedure DrawLegacyTimecodeOverlay(ACanvas: TCanvas; const ACellRect: TRect; const AText: string; const AStyle: TTimestampStyle);

{No-op when AStyle.Show is False or AStyle.Corner is tcNone — callers
 don't need to repeat that gate.}
procedure DrawCellTimecode(ACanvas: TCanvas; const ACellRect: TRect; ATimeOffset: Double; const AStyle: TTimestampStyle);

{Same instance per mode across calls; never Free the result.}
function GetTimecodePainter(AMode: TTimecodeStyleMode): ITimecodeOverlayPainter;

implementation

uses
  Winapi.Windows, System.Math,
  FrameOffsets;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows declares a TBITMAP
   alias that would otherwise shadow Vcl.Graphics.TBitmap throughout
   this implementation.}
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
  TC_PADDING_H = 8;
  {Minimum modern-path rect height for live-view parity at small fonts.}
  TC_MIN_H = 20;

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
  {Opaque -> FillRect; partial -> AlphaBlend a 1x1 colour bitmap; zero -> skip.}
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
    ACanvas.Font.Color := AStyle.TextColor;
    ACanvas.Brush.Style := bsClear;
    DrawR := ARect;
    DrawText(ACanvas.Handle, PChar(AText), -1, DrawR, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    Exit;
  end;

  {Partial text opacity: blit the rect into an offscreen bitmap, DrawText
   onto it, then AlphaBlend back so the text blends with pixels painted
   underneath (frame, background block).}
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
  {Historical WLX 1.0.x inset from cell edge.}
  TC_MARGIN = 4;
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
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := clBlack;
    ACanvas.TextOut(TX + 1, TY + 1, AText);
    ACanvas.Font.Color := AStyle.TextColor;
    ACanvas.TextOut(TX, TY, AText);
    Exit;
  end;

  {R spans one extra pixel bottom-right to include the shadow offset,
   clipped to the cell.}
  R := Rect(TX, TY, TX + TW + 2, TY + TH + 2);
  if R.Left < X then
    R.Left := X;
  if R.Top < Y then
    R.Top := Y;
  if R.Right > X + CellW then
    R.Right := X + CellW;
  if R.Bottom > Y + CellH then
    R.Bottom := Y + CellH;
  {A cell smaller than the text inset collapses R after clamping; a
   non-positive scratch bitmap is invalid and there is nothing to draw.}
  if (R.Width <= 0) or (R.Height <= 0) then
    Exit;
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
   leaf overlay will DrawText into.}
  ACanvas.Font.Name := AStyle.FontName;
  ACanvas.Font.Size := AStyle.FontSize;
  ACanvas.Font.Style := AStyle.FontStyles;

  TW := ACanvas.TextWidth(AText) + TC_PADDING_H;
  {Floors at TC_MIN_H for live-view parity at small fonts, but grows to
   fit when larger fonts would otherwise be clipped by DT_VCENTER.}
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
