{Text-width measurement interface for the status-bar renderer. Production
 wires TBitmapTextMeasurer (one bitmap reused across panels); tests inject
 a stub so layout rules can be exercised headlessly.}
unit uTextMeasurement;

interface

uses
  Vcl.Graphics;

type
  ITextMeasurer = interface
    ['{6B7C8D9E-AF10-4B11-9C12-D31E4F506718}']
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
  {Reconfigure only when the font tuple changes — a single-font Refresh over
   N panels reuses the same canvas. PixelsPerInch must precede Name/Size so
   the unit conversion uses the right DPI.}
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
