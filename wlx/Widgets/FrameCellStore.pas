{The frame-cell collection: cell state, bitmap lifecycle and per-cell
 selection. A plain non-visual class, so it is unit-testable on its own;
 TFrameView owns one and delegates its cell operations to it.}
unit FrameCellStore;

interface

uses
  Vcl.Graphics,
  FrameOffsets;

type
  TFrameCellState = (fcsPlaceholder, fcsLoaded, fcsError);

  TFrameCell = record
    State: TFrameCellState;
    Bitmap: TBitmap;
    Timecode: string;
    TimeOffset: Double;
    Selected: Boolean;
  end;

  TFrameCellStore = class
  strict private
    FCells: TArray<TFrameCell>;
  public
    destructor Destroy; override;

    {Resizes to ACount placeholder cells, freeing any retained bitmaps.
     Timecodes and offsets are seeded from AOffsets where present.
     Selection is cleared: a cell-count change signals a new file or
     frame set, so stale selections must not bleed through.}
    procedure SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
    {Stores a private pf24bit copy of ABitmap, then frees ABitmap. An
     out-of-range index frees ABitmap and returns. Raises
     EArgumentException when ABitmap is not pf24bit, since the scanline
     copy below assumes three bytes per pixel.}
    procedure SetFrame(AIndex: Integer; ABitmap: TBitmap);
    procedure SetCellError(AIndex: Integer);
    {Frees every bitmap and empties the collection.}
    procedure Clear;

    function Count: Integer;
    function State(AIndex: Integer): TFrameCellState;
    function Bitmap(AIndex: Integer): TBitmap;
    function TimeOffset(AIndex: Integer): Double;
    function Timecode(AIndex: Integer): string;
    function HasPlaceholders: Boolean;
    function HasLoadedCells: Boolean;

    function Selected(AIndex: Integer): Boolean;
    procedure ToggleSelection(AIndex: Integer);
    procedure SelectAll;
    procedure DeselectAll;
    function SelectedCount: Integer;
  end;

implementation

uses
  System.SysUtils;

destructor TFrameCellStore.Destroy;
begin
  Clear;
  inherited;
end;

procedure TFrameCellStore.SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
var
  I: Integer;
begin
  {Free bitmaps from any retained cells before resizing; otherwise
   reducing ACount loses references to the bitmaps in slots [ACount..]
   and shrinking-then-regrowing leaks them.}
  for I := 0 to High(FCells) do
    FCells[I].Bitmap.Free;
  SetLength(FCells, ACount);
  for I := 0 to ACount - 1 do
  begin
    FCells[I].State := fcsPlaceholder;
    FCells[I].Bitmap := nil;
    FCells[I].Selected := False;
    if (AOffsets <> nil) and (I < Length(AOffsets)) then
    begin
      FCells[I].Timecode := FormatTimecode(AOffsets[I].TimeOffset);
      FCells[I].TimeOffset := AOffsets[I].TimeOffset;
    end else begin
      FCells[I].Timecode := '';
      FCells[I].TimeOffset := 0;
    end;
  end;
end;

procedure TFrameCellStore.SetFrame(AIndex: Integer; ABitmap: TBitmap);
var
  Copy: TBitmap;
  Y, BytesPerRow: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FCells)) then
  begin
    ABitmap.Free;
    Exit;
  end;

  {Contract: ABitmap must be pf24bit. The extraction worker always
   produces pf24bit, but a hard runtime check catches a future regression
   loudly instead of silently corrupting the cell. The scanline memcpy
   below would otherwise read 3 bytes per pixel out of a 4-bytes-per-
   pixel source, mis-aligning every pixel after the first.}
  if ABitmap.PixelFormat <> pf24bit then
  begin
    ABitmap.Free;
    raise EArgumentException.CreateFmt(
      'TFrameCellStore.SetFrame requires pf24bit input, got pixel-format ord=%d',
      [Ord(ABitmap.PixelFormat)]);
  end;

  {Copy pixel data via raw memory, bypassing GDI entirely.
   Canvas.Draw on a bitmap created by another thread intermittently
   fails because the GDI DC handle is not reliably usable cross-thread.}
  Copy := TBitmap.Create;
  Copy.PixelFormat := pf24bit;
  Copy.SetSize(ABitmap.Width, ABitmap.Height);
  BytesPerRow := ABitmap.Width * 3;
  for Y := 0 to ABitmap.Height - 1 do
    Move(ABitmap.ScanLine[Y]^, Copy.ScanLine[Y]^, BytesPerRow);
  ABitmap.Free;

  FCells[AIndex].State := fcsLoaded;
  FCells[AIndex].Bitmap := Copy;
end;

procedure TFrameCellStore.SetCellError(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
    FCells[AIndex].State := fcsError;
end;

procedure TFrameCellStore.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FreeAndNil(FCells[I].Bitmap);
  SetLength(FCells, 0);
end;

function TFrameCellStore.Count: Integer;
begin
  Result := Length(FCells);
end;

function TFrameCellStore.State(AIndex: Integer): TFrameCellState;
begin
  {Out-of-range guard: callers occasionally pass -1 ("no cell at point")
   from the mouse hit-test, exactly as Selected documents.}
  if (AIndex < 0) or (AIndex >= Length(FCells)) then
    Exit(Default(TFrameCellState));
  Result := FCells[AIndex].State;
end;

function TFrameCellStore.Bitmap(AIndex: Integer): TBitmap;
begin
  if (AIndex < 0) or (AIndex >= Length(FCells)) then
    Exit(nil);
  Result := FCells[AIndex].Bitmap;
end;

function TFrameCellStore.TimeOffset(AIndex: Integer): Double;
begin
  if (AIndex < 0) or (AIndex >= Length(FCells)) then
    Exit(0);
  Result := FCells[AIndex].TimeOffset;
end;

function TFrameCellStore.Timecode(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= Length(FCells)) then
    Exit('');
  Result := FCells[AIndex].Timecode;
end;

function TFrameCellStore.HasPlaceholders: Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    if FCells[I].State = fcsPlaceholder then
      Exit(True);
  Result := False;
end;

function TFrameCellStore.HasLoadedCells: Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    if FCells[I].State = fcsLoaded then
      Exit(True);
  Result := False;
end;

function TFrameCellStore.Selected(AIndex: Integer): Boolean;
begin
  {Defensive guard: callers (mouse hit-test, paint loops) occasionally
   pass -1 for "no cell at point". Without the range check the reader
   crashes in Debug (range error) or returns garbage in Release.}
  Result := (AIndex >= 0) and (AIndex < Length(FCells)) and FCells[AIndex].Selected;
end;

procedure TFrameCellStore.ToggleSelection(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
    FCells[AIndex].Selected := not FCells[AIndex].Selected;
end;

procedure TFrameCellStore.SelectAll;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FCells[I].Selected := True;
end;

procedure TFrameCellStore.DeselectAll;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FCells[I].Selected := False;
end;

function TFrameCellStore.SelectedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCells) do
    if FCells[I].Selected then
      Inc(Result);
end;

end.
