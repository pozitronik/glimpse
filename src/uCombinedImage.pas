{ Renders multiple frame bitmaps into a single combined grid image.
  Pure rendering: no I/O, no settings dependency. }
unit uCombinedImage;

interface

uses
  System.UITypes, Vcl.Graphics, uFrameOffsets;

{ Renders all frames into a single grid image.
  @param AFrames Array of frame bitmaps (nil entries are skipped)
  @param AOffsets Frame time offsets (used for timestamp overlay)
  @param ACols Number of columns (0 = auto based on frame count)
  @param AGap Pixel gap between cells
  @param ABackground Background fill color
  @param AShowTimestamp Whether to overlay timecodes on each cell
  @param AFontName Font face for timestamp text
  @param AFontSize Font size in points for timestamp text
  @return Combined bitmap, or nil if AFrames is empty. Caller owns result. }
function RenderCombinedImage(const AFrames: TArray<TBitmap>;
  const AOffsets: TFrameOffsetArray; ACols, AGap: Integer;
  ABackground: TColor; AShowTimestamp: Boolean;
  const AFontName: string; AFontSize: Integer): TBitmap;

implementation

uses
  System.SysUtils, System.Math, System.Types;

function RenderCombinedImage(const AFrames: TArray<TBitmap>;
  const AOffsets: TFrameOffsetArray; ACols, AGap: Integer;
  ABackground: TColor; AShowTimestamp: Boolean;
  const AFontName: string; AFontSize: Integer): TBitmap;
var
  Cols, Rows, CellW, CellH, I, Row, Col, X, Y: Integer;
  FrameCount: Integer;
  Tc: string;
  TH: Integer;
begin
  FrameCount := Length(AFrames);
  if FrameCount = 0 then
    Exit(nil);

  Cols := ACols;
  if Cols <= 0 then
    Cols := Ceil(Sqrt(FrameCount));
  if Cols > FrameCount then
    Cols := FrameCount;
  Rows := Ceil(FrameCount / Cols);

  { Use first non-nil frame dimensions as cell size }
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
  Result.SetSize(Cols * CellW + Max(Cols - 1, 0) * AGap,
                 Rows * CellH + Max(Rows - 1, 0) * AGap);
  Result.Canvas.Brush.Color := ABackground;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));

  for I := 0 to FrameCount - 1 do
  begin
    if AFrames[I] = nil then Continue;
    Row := I div Cols;
    Col := I mod Cols;
    X := Col * (CellW + AGap);
    Y := Row * (CellH + AGap);
    Result.Canvas.Draw(X, Y, AFrames[I]);

    if AShowTimestamp and (I < Length(AOffsets)) then
    begin
      Tc := FormatTimecode(AOffsets[I].TimeOffset);
      Result.Canvas.Font.Name := AFontName;
      Result.Canvas.Font.Size := AFontSize;
      Result.Canvas.Font.Style := [fsBold];
      TH := Result.Canvas.TextHeight(Tc);
      { Shadow for readability }
      Result.Canvas.Font.Color := clBlack;
      Result.Canvas.Brush.Style := bsClear;
      Result.Canvas.TextOut(X + 5, Y + CellH - TH - 4, Tc);
      { Foreground text }
      Result.Canvas.Font.Color := clWhite;
      Result.Canvas.TextOut(X + 4, Y + CellH - TH - 5, Tc);
    end;
  end;
end;

end.
