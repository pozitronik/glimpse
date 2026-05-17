{Strategy implementations for the clipboard format publishing pipeline.

 Each strategy encapsulates one Win32 clipboard format end-to-end:
 allocation of the format-specific payload, publication via
 SetClipboardData, and cleanup on either failure or pre-publish abort.
 uClipboardImage.CopyBitmapToClipboard orchestrates over an array of
 these strategies, produced by BuildClipboardFormatStrategies from the
 user-configured TClipboardFormatsGroup toggles.

 Adding a new format is one TXxxStrategy class plus one factory branch;
 the orchestrator does not change.

 Lifecycle contract (IClipboardFormatStrategy):
   Allocate -> (Publish XOR Discard)
   - Allocate: build payload. False means GlobalAlloc / encoder failure;
     the strategy is "empty" and Discard becomes a no-op.
   - Publish: SetClipboardData. On success the OS owns the handle and
     the strategy forgets it. On failure the strategy frees its own
     handle and returns False; the orchestrator logs and keeps going so
     other formats can still publish.
   - Discard: free the allocated payload without publishing. Safe to
     call repeatedly or on an empty strategy.

 The destructor calls Discard so an uncaught exception between Allocate
 and Publish does not leak the OS handle.}
unit uClipboardFormatStrategies;

interface

uses
  System.UITypes, System.Classes,
  Vcl.Graphics,
  Winapi.Windows,
  uSettingsGroups;

type
  IClipboardFormatStrategy = interface
    ['{D0B6E5F4-7A8C-9B0D-1E2F-3A4B5C6D7E8F}']
    {Human-readable name used in error messages and logs. Surfaced to
     the user in MessageDlg text when allocation fails, so the wording
     must match the corresponding caption on the Clipboard settings tab.}
    function Name: string;

    {Builds the format payload in memory. Returns True on success; False
     means GlobalAlloc / CreateDIBitmap / encoder failure and the strategy
     is "empty". Caller treats False as a fatal abort and calls Discard
     on every sibling strategy that previously succeeded (reverse order).
     ABackground is the colour to composite semi-transparent pixels onto
     for formats that need a flat opaque copy; strategies that carry true
     alpha (CF_DIBV5, PNG) ignore it.}
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;

    {Hands the payload to SetClipboardData. On success the system owns
     the handle and the strategy forgets it (returns True). On failure
     the strategy frees its own handle and returns False; the orchestrator
     logs the per-format failure but keeps going so any siblings still on
     the array still publish.}
    function Publish: Boolean;

    {Frees the allocated payload without publishing. Used when a sibling
     strategy's Allocate failed and the orchestrator aborts before opening
     the clipboard. Idempotent and safe on an empty (post-Publish or
     pre-Allocate) strategy.}
    procedure Discard;
  end;

{Builds the publish-order strategy array from the user's per-format
 toggles. Order: DIBV5 -> PNG -> DIB -> BITMAP (DIBV5 first because
 modern image editors prefer raw alpha pixels without decode cost;
 PNG second for web/chat apps; legacy formats last). Returns an empty
 array when every toggle is disabled — CopyBitmapToClipboard treats
 that as "silent skip, succeed" per the agreed UX.

 APngCompression carries the user's TPluginSettings.PngCompression
 value so the PNG strategy can match the file-save path's compression
 level for paste-as-PNG round-trip fidelity.}
function BuildClipboardFormatStrategies(
  const ASettings: TClipboardFormatsGroup;
  APngCompression: Integer): TArray<IClipboardFormatStrategy>;

implementation

uses
  System.SysUtils,
  uBitmapSaver, uDebugLog;

procedure Log(const AMsg: string);
begin
  DebugLog('Clipboard', AMsg);
end;

const
  {Win32 constants not always exported by Winapi.Windows under that
   name. LCS_sRGB is the 4-char-code 'sRGB' in big-endian;
   LCS_GM_GRAPHICS is the GamutMatching graphics rendering intent —
   both standard for screen bitmaps. Moved from uClipboardImage with
   the BuildAlphaDIBV5 logic.}
  LCS_sRGB = $73524742;
  LCS_GM_GRAPHICS = 2;

type
  {Common base — non-refcounted (returns -1 from _AddRef/_Release) is
   not appropriate here. Strategies are short-lived interface references
   in a function scope; refcounted lifetime via TInterfacedObject is
   the natural fit and lets the destructor cleanup run when the
   orchestrator's local TArray<IClipboardFormatStrategy> drops out of
   scope.}

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
    {HBITMAP, not HGLOBAL — cleanup goes through DeleteObject.}
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
  {Cached id returned by RegisterClipboardFormat('PNG'). RegisterClipboardFormat
   is idempotent (same name returns the same id within a session) so caching
   only saves the syscall, not correctness. Lazily initialised inside the
   PNG strategy's Publish path.}
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
    {Negative height = top-down DIB; scanline 0 of the source maps to
     the first row of pixel data right after the header.}
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
    {OS owns it now — release our reference so Discard does not double-free.}
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

{TFlattenedBitmapStrategy — CF_DIB. Builds a 24-bit BGR DIB with alpha
 pre-composited onto ABackground using straight-alpha. Bottom-up layout
 (positive biHeight) is the historical CF_DIB convention — conservative
 legacy consumers refuse top-down CF_DIB.}

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
  {24-bit DIB rows are padded to a 4-byte boundary.}
  RowBytesPadded := ((W * 3 + 3) div 4) * 4;
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
    Header^.biHeight := H; {bottom-up — see header comment}
    Header^.biPlanes := 1;
    Header^.biBitCount := 24;
    Header^.biCompression := BI_RGB;
    Header^.biSizeImage := ImageBytes;

    for Y := 0 to H - 1 do
    begin
      RowStart := PByte(Header);
      Inc(RowStart, HeaderSize + Y * RowBytesPadded);
      PixelDest := RowStart;
      {Bottom-up DIB: dest row Y maps to source row (H-1-Y).}
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
        {out = (src*A + bg*(255-A) + 127) div 255 — rounded straight-alpha
         composite. Gap pixels carry RGB=ABackground so they reduce to bg
         regardless of A; frame pixels (A=255) reduce to src.}
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

{TBitmapHandleStrategy — CF_BITMAP. Internally allocates a temp 24-bit
 DIB (same layout as TFlattenedBitmapStrategy) and feeds it to
 CreateDIBitmap. The HBITMAP keeps its own pixel storage; the temp DIB
 is freed inside Allocate.}

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
    {Temp DIB is no longer needed — CreateDIBitmap copied the pixels into
     the HBITMAP's own storage. Free unconditionally; either we returned
     early on failure or we already have the HBITMAP.}
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

{TCompressedPngStrategy — registered "PNG" clipboard format. Encodes
 the source bitmap to PNG bytes via uBitmapSaver.EncodeBitmapAsPng and
 publishes those bytes under the system-registered "PNG" format id.
 Modern image editors, browsers, and chat apps prefer this format and
 it carries true alpha at a fraction of the raw-pixel memory cost.}

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

{Factory}

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
