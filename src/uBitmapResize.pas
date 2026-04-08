{ Bitmap downscaling helper.
  Used by the WCX combined-image path: the grid is rendered at full
  source resolution (so cell gaps stay intact) and then shrunk so the
  longer side fits the user-configured limit. The per-frame separate
  path achieves the same goal at extraction time via ffmpeg's scale
  filter (force_original_aspect_ratio=decrease). }
unit uBitmapResize;

interface

uses
  Winapi.Windows, Vcl.Graphics;

{ Downscales ABmp so its longer side fits within AMaxSide.
  Aspect ratio is preserved; orientation does not matter because the
  cap applies to whichever dimension is larger.

  Returns a new TBitmap on success. Returns nil when no downscaling is
  required so the caller can keep the original bitmap as-is:
    - AMaxSide is zero or negative;
    - the bitmap is empty or has invalid dimensions;
    - the bitmap already fits within the cap (no upscaling).

  Caller owns the returned bitmap. }
function DownscaleBitmapToFit(ABmp: TBitmap; AMaxSide: Integer): TBitmap;

implementation

uses
  System.Math, System.Types;

function DownscaleBitmapToFit(ABmp: TBitmap; AMaxSide: Integer): TBitmap;
var
  W, H, NewW, NewH, BmpLong: Integer;
  Scale: Double;
begin
  Result := nil;

  if ABmp = nil then Exit;
  if AMaxSide <= 0 then Exit;

  W := ABmp.Width;
  H := ABmp.Height;
  if (W <= 0) or (H <= 0) then Exit;

  BmpLong := Max(W, H);
  if BmpLong <= AMaxSide then Exit;

  Scale := AMaxSide / BmpLong;
  NewW := Max(1, Round(W * Scale));
  NewH := Max(1, Round(H * Scale));

  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(NewW, NewH);
    { HALFTONE averages source pixels properly; the default BLACKONWHITE
      ANDs channel values independently, corrupting colors on downscale }
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, NewW, NewH),
      ABmp.Canvas, Rect(0, 0, W, H));
  except
    Result.Free;
    raise;
  end;
end;

end.
