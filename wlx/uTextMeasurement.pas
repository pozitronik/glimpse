{Text-width measurement interface for the status-bar renderer.

 The renderer's MeasureText used to construct a fresh TBitmap on every
 call (once per panel per Refresh under AutoWidthLive=True), and the
 TBitmap dependency made the renderer impossible to unit-test without a
 windowed VCL canvas.

 ITextMeasurer abstracts the measurement so:
 - Production wires TBitmapTextMeasurer, which keeps a single TBitmap
 alive for the measurer's lifetime and only reconfigures its canvas
 font when (FontName, FontSize, Ppi) changes — so a Refresh with N
 panels under one font costs one bitmap and N TextWidth calls, not N
 bitmap constructions.
 - Tests inject TStubTextMeasurer (or any IClass implementation) that
 returns Length(AText) * sentinel, letting the renderer's layout /
 stretch / skip rules be exercised headlessly.}
unit uTextMeasurement;

interface

uses
  Vcl.Graphics;

type
  ITextMeasurer = interface
    ['{6B7C8D9E-AF10-4B11-9C12-D31E4F506718}']
    {Returns the pixel width of AText rendered with the supplied font
     at APpi (the surface's CurrentPPI for high-DPI awareness). Does not
     include any padding the caller wants to add around the measurement.}
    function MeasureWidth(const AText, AFontName: string; AFontSize, APpi: Integer): Integer;
  end;

  TBitmapTextMeasurer = class(TInterfacedObject, ITextMeasurer)
  strict private
    FBmp: TBitmap;
    FLastFontName: string;
    FLastFontSize: Integer;
    FLastPpi: Integer;
  public
    destructor Destroy; override;
    function MeasureWidth(const AText, AFontName: string; AFontSize, APpi: Integer): Integer;
  end;

implementation

uses
  System.SysUtils;

destructor TBitmapTextMeasurer.Destroy;
begin
  FreeAndNil(FBmp);
  inherited;
end;

function TBitmapTextMeasurer.MeasureWidth(const AText, AFontName: string; AFontSize, APpi: Integer): Integer;
begin
  if FBmp = nil then
    FBmp := TBitmap.Create;
  {Reconfigure canvas only when the font tuple actually changes — a
   single-font Refresh pass over N panels reuses the same canvas state.
   Sets PixelsPerInch before Name/Size so the Font.Size unit conversion
   uses the correct DPI from the first assignment.}
  if (FLastFontName <> AFontName) or (FLastFontSize <> AFontSize) or (FLastPpi <> APpi) then
  begin
    FBmp.Canvas.Font.PixelsPerInch := APpi;
    FBmp.Canvas.Font.Name := AFontName;
    FBmp.Canvas.Font.Size := AFontSize;
    FLastFontName := AFontName;
    FLastFontSize := AFontSize;
    FLastPpi := APpi;
  end;
  Result := FBmp.Canvas.TextWidth(AText);
end;

end.
