{Per-format strategies for the clipboard publish pipeline.

 Lifecycle: Allocate -> (Publish XOR Discard).
 - Allocate False = GlobalAlloc/encoder failure; strategy is empty.
 - Publish on success transfers the handle to the OS; on failure the
   strategy frees its own handle and returns False.
 - Discard is idempotent.

 The destructor calls Discard so an exception between Allocate and
 Publish does not leak the OS handle.}
unit ClipboardFormatStrategies;

interface

uses
  System.UITypes, System.Classes,
  Vcl.Graphics,
  Winapi.Windows,
  SettingsGroups;

type
  IClipboardFormatStrategy = interface
    ['{D0B6E5F4-7A8C-9B0D-1E2F-3A4B5C6D7E8F}']
    {Name must match the Clipboard settings tab caption; it surfaces in
     user-facing error messages.}
    function Name: string;

    {ABackground is composited onto semi-transparent pixels for formats
     that need a flat opaque copy; alpha-aware formats ignore it.}
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;

    function Publish: Boolean;

    procedure Discard;
  end;

{Publish order: DIBV5 (alpha-aware editors prefer raw pixels), PNG
 (web/chat apps), DIB, BITMAP (legacy last). Empty array means every
 toggle is off; orchestrator silently succeeds.}
function BuildClipboardFormatStrategies(
  const ASettings: TClipboardFormatsGroup;
  APngCompression: Integer): TArray<IClipboardFormatStrategy>;

implementation

uses
  System.SysUtils,
  BitmapSaver, Logging;

procedure Log(const AMsg: string);
begin
  DebugLog('Clipboard', AMsg);
end;

const
  {Win32 constants not exported by Winapi.Windows. LCS_sRGB is the
   4-char-code 'sRGB' big-endian; LCS_GM_GRAPHICS is the GamutMatching
   rendering intent.}
  LCS_sRGB = $73524742;
  LCS_GM_GRAPHICS = 2;

type
  TAlphaAwareBitmapStrategy = class(TInterfacedObject, IClipboardFormatStrategy)
  private
    FHandle: HGLOBAL;
  public
    destructor Destroy; override;
    function Name: string;
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;
    function Publish: Boolean;
    procedure Discard;
  end;

  TFlattenedBitmapStrategy = class(TInterfacedObject, IClipboardFormatStrategy)
  private
    FHandle: HGLOBAL;
  public
    destructor Destroy; override;
    function Name: string;
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;
    function Publish: Boolean;
    procedure Discard;
  end;

  TBitmapHandleStrategy = class(TInterfacedObject, IClipboardFormatStrategy)
  private
    {HBITMAP cleanup is DeleteObject, not GlobalFree.}
    FHandle: HBITMAP;
  public
    destructor Destroy; override;
    function Name: string;
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;
    function Publish: Boolean;
    procedure Discard;
  end;

  TCompressedPngStrategy = class(TInterfacedObject, IClipboardFormatStrategy)
  private
    FHandle: HGLOBAL;
    FPngCompression: Integer;
  public
    constructor Create(APngCompression: Integer);
    destructor Destroy; override;
    function Name: string;
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;
    function Publish: Boolean;
    procedure Discard;
  end;

var
  {RegisterClipboardFormat is idempotent; caching saves a syscall.}
  GPngClipboardFormatId: UINT = 0;

function GetPngClipboardFormatId: UINT;
begin
  if GPngClipboardFormatId = 0 then
    GPngClipboardFormatId := RegisterClipboardFormat('PNG');
  Result := GPngClipboardFormatId;
end;

{TAlphaAwareBitmapStrategy — CF_DIBV5}

destructor TAlphaAwareBitmapStrategy.Destroy;
begin
  Discard;
  inherited;
end;

function TAlphaAwareBitmapStrategy.Name: string;
begin
  Result := 'Alpha-aware bitmap';
end;

function TAlphaAwareBitmapStrategy.Allocate(ASrc: Vcl.Graphics.TBitmap;
  ABackground: TColor): Boolean;
var
  HeaderSize, RowBytes, ImageBytes, TotalBytes, Y: Integer;
  Header: PBitmapV5Header;
  PixelDest, ScanSrc: PByte;
begin
  {ABackground intentionally unused — CF_DIBV5 carries true alpha.}
  Result := False;
  HeaderSize := SizeOf(TBitmapV5Header);
  RowBytes := ASrc.Width * 4;
  ImageBytes := RowBytes * ASrc.Height;
  TotalBytes := HeaderSize + ImageBytes;

  FHandle := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if FHandle = 0 then
  begin
    Log(Format('%s.Allocate: GlobalAlloc(%d bytes) failed for %dx%d (lastError=%d)',
      [Name, TotalBytes, ASrc.Width, ASrc.Height, GetLastError]));
    Exit;
  end;

  Header := PBitmapV5Header(GlobalLock(FHandle));
  if Header = nil then
  begin
    Log(Format('%s.Allocate: GlobalLock failed (lastError=%d)', [Name, GetLastError]));
    GlobalFree(FHandle);
    FHandle := 0;
    Exit;
  end;

  try
    FillChar(Header^, HeaderSize, 0);
    Header^.bV5Size := HeaderSize;
    Header^.bV5Width := ASrc.Width;
    {Negative height = top-down DIB so source scanline 0 maps to the
     first row after the header.}
    Header^.bV5Height := -ASrc.Height;
    Header^.bV5Planes := 1;
    Header^.bV5BitCount := 32;
    Header^.bV5Compression := BI_BITFIELDS;
    Header^.bV5SizeImage := ImageBytes;
    Header^.bV5RedMask := $00FF0000;
    Header^.bV5GreenMask := $0000FF00;
    Header^.bV5BlueMask := $000000FF;
    Header^.bV5AlphaMask := $FF000000;
    Header^.bV5CSType := LCS_sRGB;
    Header^.bV5Intent := LCS_GM_GRAPHICS;

    PixelDest := PByte(Header);
    Inc(PixelDest, HeaderSize);
    for Y := 0 to ASrc.Height - 1 do
    begin
      ScanSrc := PByte(ASrc.ScanLine[Y]);
      Move(ScanSrc^, PixelDest^, RowBytes);
      Inc(PixelDest, RowBytes);
    end;
  finally
    GlobalUnlock(FHandle);
  end;
  Result := True;
end;

function TAlphaAwareBitmapStrategy.Publish: Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  if SetClipboardData(CF_DIBV5, FHandle) <> 0 then
  begin
    {OS owns the handle now; clear so Discard does not double-free.}
    FHandle := 0;
    Result := True;
  end
  else
  begin
    Log(Format('%s.Publish: SetClipboardData(CF_DIBV5) failed (lastError=%d)',
      [Name, GetLastError]));
    GlobalFree(FHandle);
    FHandle := 0;
  end;
end;

procedure TAlphaAwareBitmapStrategy.Discard;
begin
  if FHandle <> 0 then
  begin
    GlobalFree(FHandle);
    FHandle := 0;
  end;
end;

{Bottom-up layout (positive biHeight) is required for CF_DIB; some
 legacy consumers refuse top-down.}

destructor TFlattenedBitmapStrategy.Destroy;
begin
  Discard;
  inherited;
end;

function TFlattenedBitmapStrategy.Name: string;
begin
  Result := 'Flattened bitmap for legacy apps';
end;

function TFlattenedBitmapStrategy.Allocate(ASrc: Vcl.Graphics.TBitmap;
  ABackground: TColor): Boolean;
var
  HeaderSize, RowBytesPadded, ImageBytes, TotalBytes, X, Y: Integer;
  Header: PBitmapInfoHeader;
  RowStart, PixelDest, ScanSrc: PByte;
  BgR, BgG, BgB, SrcB, SrcG, SrcR, SrcA: Byte;
  W, H: Integer;
begin
  Result := False;
  W := ASrc.Width;
  H := ASrc.Height;
  HeaderSize := SizeOf(TBitmapInfoHeader);
  RowBytesPadded := ((W * 3 + 3) div 4) * 4; {4-byte DIB row alignment}
  ImageBytes := RowBytesPadded * H;
  TotalBytes := HeaderSize + ImageBytes;

  FHandle := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if FHandle = 0 then
  begin
    Log(Format('%s.Allocate: GlobalAlloc(%d bytes) failed for %dx%d (lastError=%d)',
      [Name, TotalBytes, W, H, GetLastError]));
    Exit;
  end;

  Header := PBitmapInfoHeader(GlobalLock(FHandle));
  if Header = nil then
  begin
    Log(Format('%s.Allocate: GlobalLock failed (lastError=%d)', [Name, GetLastError]));
    GlobalFree(FHandle);
    FHandle := 0;
    Exit;
  end;

  try
    BgR := GetRValue(Cardinal(ABackground));
    BgG := GetGValue(Cardinal(ABackground));
    BgB := GetBValue(Cardinal(ABackground));

    FillChar(Header^, HeaderSize, 0);
    Header^.biSize := HeaderSize;
    Header^.biWidth := W;
    Header^.biHeight := H;
    Header^.biPlanes := 1;
    Header^.biBitCount := 24;
    Header^.biCompression := BI_RGB;
    Header^.biSizeImage := ImageBytes;

    for Y := 0 to H - 1 do
    begin
      RowStart := PByte(Header);
      Inc(RowStart, HeaderSize + Y * RowBytesPadded);
      PixelDest := RowStart;
      ScanSrc := PByte(ASrc.ScanLine[H - 1 - Y]);
      for X := 0 to W - 1 do
      begin
        SrcB := ScanSrc^;
        Inc(ScanSrc);
        SrcG := ScanSrc^;
        Inc(ScanSrc);
        SrcR := ScanSrc^;
        Inc(ScanSrc);
        SrcA := ScanSrc^;
        Inc(ScanSrc);
        {Rounded straight-alpha composite: out = (src*A + bg*(255-A) + 127) / 255}
        PixelDest^ := Byte((SrcB * SrcA + BgB * (255 - SrcA) + 127) div 255);
        Inc(PixelDest);
        PixelDest^ := Byte((SrcG * SrcA + BgG * (255 - SrcA) + 127) div 255);
        Inc(PixelDest);
        PixelDest^ := Byte((SrcR * SrcA + BgR * (255 - SrcA) + 127) div 255);
        Inc(PixelDest);
      end;
    end;
  finally
    GlobalUnlock(FHandle);
  end;
  Result := True;
end;

function TFlattenedBitmapStrategy.Publish: Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  if SetClipboardData(CF_DIB, FHandle) <> 0 then
  begin
    FHandle := 0;
    Result := True;
  end
  else
  begin
    Log(Format('%s.Publish: SetClipboardData(CF_DIB) failed (lastError=%d)',
      [Name, GetLastError]));
    GlobalFree(FHandle);
    FHandle := 0;
  end;
end;

procedure TFlattenedBitmapStrategy.Discard;
begin
  if FHandle <> 0 then
  begin
    GlobalFree(FHandle);
    FHandle := 0;
  end;
end;

destructor TBitmapHandleStrategy.Destroy;
begin
  Discard;
  inherited;
end;

function TBitmapHandleStrategy.Name: string;
begin
  Result := 'GDI bitmap handle';
end;

function TBitmapHandleStrategy.Allocate(ASrc: Vcl.Graphics.TBitmap;
  ABackground: TColor): Boolean;
var
  HeaderSize, RowBytesPadded, ImageBytes, TotalBytes, X, Y, W, H: Integer;
  Mem: HGLOBAL;
  Header: PBitmapInfoHeader;
  RowStart, PixelDest, ScanSrc: PByte;
  BgR, BgG, BgB, SrcB, SrcG, SrcR, SrcA: Byte;
  PixelBits: PByte;
  ScreenDC: HDC;
begin
  Result := False;
  W := ASrc.Width;
  H := ASrc.Height;
  HeaderSize := SizeOf(TBitmapInfoHeader);
  RowBytesPadded := ((W * 3 + 3) div 4) * 4;
  ImageBytes := RowBytesPadded * H;
  TotalBytes := HeaderSize + ImageBytes;

  Mem := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if Mem = 0 then
  begin
    Log(Format('%s.Allocate: GlobalAlloc(%d bytes) failed for %dx%d (lastError=%d)',
      [Name, TotalBytes, W, H, GetLastError]));
    Exit;
  end;

  Header := PBitmapInfoHeader(GlobalLock(Mem));
  if Header = nil then
  begin
    Log(Format('%s.Allocate: GlobalLock failed (lastError=%d)', [Name, GetLastError]));
    GlobalFree(Mem);
    Exit;
  end;

  try
    BgR := GetRValue(Cardinal(ABackground));
    BgG := GetGValue(Cardinal(ABackground));
    BgB := GetBValue(Cardinal(ABackground));

    FillChar(Header^, HeaderSize, 0);
    Header^.biSize := HeaderSize;
    Header^.biWidth := W;
    Header^.biHeight := H;
    Header^.biPlanes := 1;
    Header^.biBitCount := 24;
    Header^.biCompression := BI_RGB;
    Header^.biSizeImage := ImageBytes;

    for Y := 0 to H - 1 do
    begin
      RowStart := PByte(Header);
      Inc(RowStart, HeaderSize + Y * RowBytesPadded);
      PixelDest := RowStart;
      ScanSrc := PByte(ASrc.ScanLine[H - 1 - Y]);
      for X := 0 to W - 1 do
      begin
        SrcB := ScanSrc^;
        Inc(ScanSrc);
        SrcG := ScanSrc^;
        Inc(ScanSrc);
        SrcR := ScanSrc^;
        Inc(ScanSrc);
        SrcA := ScanSrc^;
        Inc(ScanSrc);
        PixelDest^ := Byte((SrcB * SrcA + BgB * (255 - SrcA) + 127) div 255);
        Inc(PixelDest);
        PixelDest^ := Byte((SrcG * SrcA + BgG * (255 - SrcA) + 127) div 255);
        Inc(PixelDest);
        PixelDest^ := Byte((SrcR * SrcA + BgR * (255 - SrcA) + 127) div 255);
        Inc(PixelDest);
      end;
    end;

    PixelBits := PByte(Header);
    Inc(PixelBits, Header^.biSize);
    ScreenDC := GetDC(0);
    if ScreenDC = 0 then
    begin
      Log(Format('%s.Allocate: GetDC(0) returned 0 (lastError=%d)', [Name, GetLastError]));
      Exit;
    end;
    try
      FHandle := CreateDIBitmap(ScreenDC, Header^, CBM_INIT, PixelBits,
        PBitmapInfo(Header)^, DIB_RGB_COLORS);
      if FHandle = 0 then
      begin
        Log(Format('%s.Allocate: CreateDIBitmap failed for %dx%d (lastError=%d)',
          [Name, W, H, GetLastError]));
        Exit;
      end;
    finally
      ReleaseDC(0, ScreenDC);
    end;
  finally
    GlobalUnlock(Mem);
    {CreateDIBitmap copied the pixels into the HBITMAP's own storage,
     so we can free the temp DIB unconditionally.}
    GlobalFree(Mem);
  end;
  Result := True;
end;

function TBitmapHandleStrategy.Publish: Boolean;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  if SetClipboardData(CF_BITMAP, FHandle) <> 0 then
  begin
    FHandle := 0;
    Result := True;
  end
  else
  begin
    Log(Format('%s.Publish: SetClipboardData(CF_BITMAP) failed (lastError=%d)',
      [Name, GetLastError]));
    DeleteObject(FHandle);
    FHandle := 0;
  end;
end;

procedure TBitmapHandleStrategy.Discard;
begin
  if FHandle <> 0 then
  begin
    DeleteObject(FHandle);
    FHandle := 0;
  end;
end;

constructor TCompressedPngStrategy.Create(APngCompression: Integer);
begin
  inherited Create;
  FPngCompression := APngCompression;
end;

destructor TCompressedPngStrategy.Destroy;
begin
  Discard;
  inherited;
end;

function TCompressedPngStrategy.Name: string;
begin
  Result := 'Compressed PNG';
end;

function TCompressedPngStrategy.Allocate(ASrc: Vcl.Graphics.TBitmap;
  ABackground: TColor): Boolean;
var
  Stream: TMemoryStream;
  TotalBytes: NativeUInt;
  Dest: Pointer;
begin
  {ABackground intentionally unused — PNG carries true alpha verbatim.}
  Result := False;
  Stream := TMemoryStream.Create;
  try
    try
      EncodeBitmapAsPng(ASrc, Stream, FPngCompression);
    except
      on E: Exception do
      begin
        Log(Format('%s.Allocate: EncodeBitmapAsPng raised %s: %s',
          [Name, E.ClassName, E.Message]));
        Exit;
      end;
    end;
    TotalBytes := Stream.Size;
    if TotalBytes = 0 then
    begin
      Log(Format('%s.Allocate: encoder produced zero bytes', [Name]));
      Exit;
    end;

    FHandle := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
    if FHandle = 0 then
    begin
      Log(Format('%s.Allocate: GlobalAlloc(%d bytes) failed (lastError=%d)',
        [Name, TotalBytes, GetLastError]));
      Exit;
    end;

    Dest := GlobalLock(FHandle);
    if Dest = nil then
    begin
      Log(Format('%s.Allocate: GlobalLock failed (lastError=%d)',
        [Name, GetLastError]));
      GlobalFree(FHandle);
      FHandle := 0;
      Exit;
    end;
    try
      Move(Stream.Memory^, Dest^, TotalBytes);
    finally
      GlobalUnlock(FHandle);
    end;
  finally
    Stream.Free;
  end;
  Result := True;
end;

function TCompressedPngStrategy.Publish: Boolean;
var
  FormatId: UINT;
begin
  Result := False;
  if FHandle = 0 then
    Exit;
  FormatId := GetPngClipboardFormatId;
  if FormatId = 0 then
  begin
    Log(Format('%s.Publish: RegisterClipboardFormat returned 0 (lastError=%d)',
      [Name, GetLastError]));
    GlobalFree(FHandle);
    FHandle := 0;
    Exit;
  end;
  if SetClipboardData(FormatId, FHandle) <> 0 then
  begin
    FHandle := 0;
    Result := True;
  end
  else
  begin
    Log(Format('%s.Publish: SetClipboardData(PNG=%d) failed (lastError=%d)',
      [Name, FormatId, GetLastError]));
    GlobalFree(FHandle);
    FHandle := 0;
  end;
end;

procedure TCompressedPngStrategy.Discard;
begin
  if FHandle <> 0 then
  begin
    GlobalFree(FHandle);
    FHandle := 0;
  end;
end;

function BuildClipboardFormatStrategies(
  const ASettings: TClipboardFormatsGroup;
  APngCompression: Integer): TArray<IClipboardFormatStrategy>;

  procedure Add(const AStrategy: IClipboardFormatStrategy);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AStrategy;
  end;

begin
  Result := nil;
  if ASettings.PublishAlphaAwareBitmap then
    Add(TAlphaAwareBitmapStrategy.Create);
  if ASettings.PublishCompressedPng then
    Add(TCompressedPngStrategy.Create(APngCompression));
  if ASettings.PublishFlattenedBitmap then
    Add(TFlattenedBitmapStrategy.Create);
  if ASettings.PublishBitmapHandle then
    Add(TBitmapHandleStrategy.Create);
end;

end.
