{Bitmap downscaling helper for the WCX combined-image path. The grid is
 rendered at full source resolution then shrunk to fit the longer-side
 cap. The per-frame separate path scales at extraction time via ffmpeg.}
unit BitmapResize;

interface

uses
  Winapi.Windows, Vcl.Graphics;

{Returns True iff a downscale would happen. ACW/ACH receive the post-cap
 size, or AW/AH when no downscale is needed.}
function ComputeCappedSize(AW, AH, ACap: Integer; out ACW, ACH: Integer): Boolean;

{Returns nil when no downscaling is required (cap <= 0, empty bitmap,
 or already fits). Caller owns the result.}
function DownscaleBitmapToFit(ABmp: TBitmap; AMaxSide: Integer): TBitmap;

implementation

uses
  System.Math, System.Types;

{Manual bilinear preserves the alpha channel; GDI's HALFTONE CopyRect
 does not reliably write alpha across all driver/Windows combinations.}
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
      {Clamp to last row so 1-pixel-tall sources collapse to nearest-
       neighbour instead of dereferencing ScanLine[-1].}
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

function ComputeCappedSize(AW, AH, ACap: Integer; out ACW, ACH: Integer): Boolean;
var
  Long: Integer;
  Scale: Double;
begin
  ACW := AW;
  ACH := AH;
  Result := False;
  if (ACap <= 0) or (AW <= 0) or (AH <= 0) then
    Exit;
  Long := Max(AW, AH);
  if Long <= ACap then
    Exit;
  Scale := ACap / Long;
  ACW := Max(1, Round(AW * Scale));
  ACH := Max(1, Round(AH * Scale));
  Result := True;
end;

function DownscaleBitmapToFit(ABmp: TBitmap; AMaxSide: Integer): TBitmap;
var
  W, H, NewW, NewH: Integer;
begin
  Result := nil;
  if ABmp = nil then
    Exit;

  W := ABmp.Width;
  H := ABmp.Height;
  if not ComputeCappedSize(W, H, AMaxSide, NewW, NewH) then
    Exit;

  if ABmp.PixelFormat = pf32bit then
  begin
    Result := ResampleAlphaAwareBilinear(ABmp, NewW, NewH);
    Exit;
  end;

  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(NewW, NewH);
    {HALFTONE averages source pixels properly; default BLACKONWHITE ANDs
     channel values independently and corrupts colours on downscale.}
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, NewW, NewH), ABmp.Canvas, Rect(0, 0, W, H));
  except
    Result.Free;
    raise;
  end;
end;

end.
