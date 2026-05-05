{Bitmap downscaling helper.
 Used by the WCX combined-image path: the grid is rendered at full
 source resolution (so cell gaps stay intact) and then shrunk so the
 longer side fits the user-configured limit. The per-frame separate
 path achieves the same goal at extraction time via ffmpeg's scale
 filter (force_original_aspect_ratio=decrease).}
unit uBitmapResize;

interface

uses
  Winapi.Windows, Vcl.Graphics;

{Downscales ABmp so its longer side fits within AMaxSide.
 Aspect ratio is preserved; orientation does not matter because the
 cap applies to whichever dimension is larger.

 Returns a new TBitmap on success. Returns nil when no downscaling is
 required so the caller can keep the original bitmap as-is:
 - AMaxSide is zero or negative;
 - the bitmap is empty or has invalid dimensions;
 - the bitmap already fits within the cap (no upscaling).

 Caller owns the returned bitmap.}
function DownscaleBitmapToFit(ABmp: TBitmap; AMaxSide: Integer): TBitmap;

implementation

uses
  System.Math, System.Types;

{Manual bilinear downscale that preserves the alpha channel. Used when the
 source is pf32bit; GDI's HALFTONE CopyRect path doesn't reliably write the
 alpha byte across all driver/Windows combinations, so we sample explicitly.}
function ResampleAlphaAwareBilinear(ASrc: TBitmap; ANewW, ANewH: Integer): TBitmap;
type
  TQuadRow = array [0 .. 0] of TRGBQuad;
  PQuadRow = ^TQuadRow;
var
  X, Y, IX, IY, IX1, IY1: Integer;
  SrcX, SrcY, FracX, FracY, W00, W10, W01, W11: Double;
  R0, R1: PQuadRow;
  Dst: PQuadRow;
  RR, GG, BB, AA: Double;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf32bit;
    Result.AlphaFormat := afDefined;
    Result.SetSize(ANewW, ANewH);

    for Y := 0 to ANewH - 1 do
    begin
      SrcY := (Y + 0.5) * ASrc.Height / ANewH - 0.5;
      IY := Trunc(SrcY);
      if IY < 0 then
        IY := 0;
      if IY > ASrc.Height - 1 then
        IY := ASrc.Height - 1;
      {Next-row index for bilinear interpolation. Clamping to the last row
       collapses the row pair to nearest-neighbour at the bottom edge and on
       1-pixel-tall sources (where ASrc.Height-2 = -1 would otherwise drive
       IY to -1 and dereference ScanLine[-1]).}
      IY1 := IY + 1;
      if IY1 > ASrc.Height - 1 then
        IY1 := ASrc.Height - 1;
      FracY := SrcY - IY;
      if FracY < 0 then
        FracY := 0;
      if FracY > 1 then
        FracY := 1;
      R0 := PQuadRow(ASrc.ScanLine[IY]);
      R1 := PQuadRow(ASrc.ScanLine[IY1]);
      Dst := PQuadRow(Result.ScanLine[Y]);
      for X := 0 to ANewW - 1 do
      begin
        SrcX := (X + 0.5) * ASrc.Width / ANewW - 0.5;
        IX := Trunc(SrcX);
        if IX < 0 then
          IX := 0;
        if IX > ASrc.Width - 1 then
          IX := ASrc.Width - 1;
        IX1 := IX + 1;
        if IX1 > ASrc.Width - 1 then
          IX1 := ASrc.Width - 1;
        FracX := SrcX - IX;
        if FracX < 0 then
          FracX := 0;
        if FracX > 1 then
          FracX := 1;
        W00 := (1 - FracX) * (1 - FracY);
        W10 := FracX * (1 - FracY);
        W01 := (1 - FracX) * FracY;
        W11 := FracX * FracY;
        RR := R0^[IX].rgbRed * W00 + R0^[IX1].rgbRed * W10 + R1^[IX].rgbRed * W01 + R1^[IX1].rgbRed * W11;
        GG := R0^[IX].rgbGreen * W00 + R0^[IX1].rgbGreen * W10 + R1^[IX].rgbGreen * W01 + R1^[IX1].rgbGreen * W11;
        BB := R0^[IX].rgbBlue * W00 + R0^[IX1].rgbBlue * W10 + R1^[IX].rgbBlue * W01 + R1^[IX1].rgbBlue * W11;
        AA := R0^[IX].rgbReserved * W00 + R0^[IX1].rgbReserved * W10 + R1^[IX].rgbReserved * W01 + R1^[IX1].rgbReserved * W11;
        Dst^[X].rgbRed := Round(RR);
        Dst^[X].rgbGreen := Round(GG);
        Dst^[X].rgbBlue := Round(BB);
        Dst^[X].rgbReserved := Round(AA);
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function DownscaleBitmapToFit(ABmp: TBitmap; AMaxSide: Integer): TBitmap;
var
  W, H, NewW, NewH, BmpLong: Integer;
  Scale: Double;
begin
  Result := nil;

  if ABmp = nil then
    Exit;
  if AMaxSide <= 0 then
    Exit;

  W := ABmp.Width;
  H := ABmp.Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  BmpLong := Max(W, H);
  if BmpLong <= AMaxSide then
    Exit;

  Scale := AMaxSide / BmpLong;
  NewW := Max(1, Round(W * Scale));
  NewH := Max(1, Round(H * Scale));

  if ABmp.PixelFormat = pf32bit then
  begin
    Result := ResampleAlphaAwareBilinear(ABmp, NewW, NewH);
    Exit;
  end;

  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(NewW, NewH);
    {HALFTONE averages source pixels properly; the default BLACKONWHITE
     ANDs channel values independently, corrupting colors on downscale}
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, NewW, NewH), ABmp.Canvas, Rect(0, 0, W, H));
  except
    Result.Free;
    raise;
  end;
end;

end.
