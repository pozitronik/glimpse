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
 distinct intents — "no background block on the modern path" versus
 "render the legacy algorithm entirely" — and meant a future fourth
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
  Vcl.Graphics, System.Types,
  uCombinedImage;

type
  ITimecodeOverlayPainter = interface
    ['{4E8A1F3D-6B2C-49A7-B05E-C12F7D3A8B6E}']
    {Paints the timecode AText into ACellRect on ACanvas using AStyle.
     Implementations interpret ACellRect according to their algorithm:
     the modern painter derives a flush-to-corner sub-rectangle; the
     legacy painter positions text inset from the cell edge.}
    procedure Paint(ACanvas: TCanvas; const ACellRect: TRect;
      const AText: string; const AStyle: TTimestampStyle);
  end;

  {Returns the painter responsible for AMode. The same instance is
   handed out across calls; never Free the result.}
function GetTimecodePainter(AMode: TTimecodeStyleMode): ITimecodeOverlayPainter;

implementation

uses
  System.Math,
  uTypes;

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
  TC_MIN_H = 20;    {minimum height for the modern-path rect — live-view parity for small fonts}

var
  GModernPainter: ITimecodeOverlayPainter;
  GLegacyPainter: ITimecodeOverlayPainter;

function GetTimecodePainter(AMode: TTimecodeStyleMode): ITimecodeOverlayPainter;
begin
  case AMode of
    tsmLegacy:
      Result := GLegacyPainter;
    else
      Result := GModernPainter;
  end;
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
