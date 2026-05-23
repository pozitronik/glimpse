{Bitmap scaling primitives used by the combined-image render pipeline.
 Letterbox preserves source aspect inside a fixed dst rect with a
 background fill; crop-to-fill matches dst aspect by centre-cropping
 the source. Both produce pf24bit output for thread-safe rendering.}
unit CellBitmapScaler;

interface

uses
  System.UITypes,
  Vcl.Graphics,
  SettingsInterfaces;

type
  TCellBitmapScaler = class
  strict private
    FRenderColorPolicy: IRenderColorPolicy;
  public
    {ARenderColorPolicy is borrowed and supplies the fallback background
     for ScaleBitmapCropToFill when its source is empty.}
    constructor Create(const ARenderColorPolicy: IRenderColorPolicy);
    {Caller owns the returned bitmap. Mirrors TFrameView.PaintLoadedFrame
     (vmGrid live view) so saved cells look identical to what the user
     sees when SaveAtLiveResolution is on.}
    function ScaleBitmapLetterbox(ASrc: Vcl.Graphics.TBitmap; AW, AH: Integer; ABg: TColor): Vcl.Graphics.TBitmap;
    {Caller owns the returned bitmap. Mirrors TFrameView.PaintCropToFill
     (vmSmartGrid live view) so saved smart-grid cells preserve aspect
     ratio without letterbox bands.}
    function ScaleBitmapCropToFill(ASrc: Vcl.Graphics.TBitmap; AW, AH: Integer): Vcl.Graphics.TBitmap;
  end;

implementation

uses
  Winapi.Windows, System.Types, System.Math;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows declares a TBITMAP
   alias that would otherwise shadow Vcl.Graphics.TBitmap.}
  TBitmap = Vcl.Graphics.TBitmap;

constructor TCellBitmapScaler.Create(const ARenderColorPolicy: IRenderColorPolicy);
begin
  inherited Create;
  FRenderColorPolicy := ARenderColorPolicy;
end;

function TCellBitmapScaler.ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
var
  Scale: Double;
  DW, DH: Integer;
  DstR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    Result.Canvas.Brush.Color := ABg;
    Result.Canvas.FillRect(Rect(0, 0, AW, AH));
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
      Exit;
    Scale := Min(AW / ASrc.Width, AH / ASrc.Height);
    DW := Max(1, Round(ASrc.Width * Scale));
    DH := Max(1, Round(ASrc.Height * Scale));
    DstR.Left := (AW - DW) div 2;
    DstR.Top := (AH - DH) div 2;
    DstR.Right := DstR.Left + DW;
    DstR.Bottom := DstR.Top + DH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.StretchDraw(DstR, ASrc);
  except
    Result.Free;
    raise;
  end;
end;

function TCellBitmapScaler.ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
var
  Scale: Double;
  SrcW, SrcH: Integer;
  SrcR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
    begin
      Result.Canvas.Brush.Color := FRenderColorPolicy.GetBackground;
      Result.Canvas.FillRect(Rect(0, 0, AW, AH));
      Exit;
    end;
    Scale := Max(AW / ASrc.Width, AH / ASrc.Height);
    SrcW := Min(ASrc.Width, Round(AW / Scale));
    SrcH := Min(ASrc.Height, Round(AH / Scale));
    SrcR.Left := (ASrc.Width - SrcW) div 2;
    SrcR.Top := (ASrc.Height - SrcH) div 2;
    SrcR.Right := SrcR.Left + SrcW;
    SrcR.Bottom := SrcR.Top + SrcH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, AW, AH), ASrc.Canvas, SrcR);
  except
    Result.Free;
    raise;
  end;
end;

end.
