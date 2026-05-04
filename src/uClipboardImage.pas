{Clipboard publisher for alpha-aware bitmaps.

 For pf32bit sources we publish two formats side-by-side:
 - CF_DIBV5 carries the full ARGB pixels for paste targets that honour
   alpha (Paint.NET, GIMP, Krita, Affinity Photo, modern browsers).
 - CF_DIB carries an opaque copy with alpha already composited onto the
   caller-provided background colour, so legacy targets (Paint, Word,
   older imaging tools) that only understand CF_DIB receive a
   ready-to-paste image instead of Windows' default alpha-strip
   synthesis (which renders semi-transparent pixels as broken/black in
   many such targets).

 An app that prioritises CF_DIB over CF_DIBV5 still loses the alpha
 channel — this is unavoidable, but those apps would not have honoured
 CF_DIBV5 in the first place, so they get a working composited paste
 instead of a broken one.

 For pf24bit sources we route through Vcl.Clipbrd.Clipboard.Assign,
 which yields CF_BITMAP / CF_DIB the standard way; alpha never applies
 to that path.}
unit uClipboardImage;

interface

uses
  System.SysUtils, System.UITypes, Vcl.Graphics;

type
  {Action that opens the clipboard. Defaults to Vcl.Clipbrd.Clipboard.Open
   in production; tests inject throwers so the retry policy can be
   exercised without owning the global clipboard.}
  TClipboardOpenAction = reference to procedure;

{Pushes ABitmap to the system clipboard.

 When ABitmap is pf32bit the helper publishes both CF_DIBV5 (full
 alpha) and CF_DIB (alpha composited onto ABackground) so paste works
 in both modern and legacy targets. ABackground is the colour
 semi-transparent pixels are flattened against; for our use it should
 match the configured background of the rendered combined image so the
 opaque copy looks identical to a BackgroundAlpha=255 render.

 When ABitmap is not pf32bit the call falls through to
 Vcl.Clipbrd.Clipboard.Assign and ABackground is ignored.

 Returns True on success.}
function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap; ABackground: TColor = TColor($000000)): Boolean;

{Retries the clipboard open up to 20 times with 10 ms sleeps when it
 surfaces an EClipboardException, returning True on the first successful
 open and False once the retry budget is exhausted. The action overload
 is the test seam; the no-arg overload calls Vcl.Clipbrd.Clipboard.Open.
 Earlier the bare except swallowed every exception including
 EAccessViolation / EOutOfMemory and burned 200 ms retrying problems
 that were never going to fix themselves; the retry now matches only
 the documented transient failure (EClipboardException), and any other
 exception propagates to the caller.}
function TryClipboardOpenWithRetry: Boolean; overload;
function TryClipboardOpenWithRetry(const AOpenAction: TClipboardOpenAction): Boolean; overload;

implementation

uses
  Winapi.Windows, Vcl.Clipbrd;

const
  {Win32 constants not always exported by Winapi.Windows under that name.
   LCS_sRGB is the 4-char-code 'sRGB' in big-endian; LCS_GM_GRAPHICS is
   the GamutMatching graphics rendering intent — both standard for screen
   bitmaps.}
  LCS_sRGB        = $73524742;
  LCS_GM_GRAPHICS = 2;

function TryClipboardOpenWithRetry(const AOpenAction: TClipboardOpenAction): Boolean;
var
  I: Integer;
begin
  {OpenClipboard fails transiently when another opener held it a moment
   ago and Windows has not yet propagated WM_DESTROYCLIPBOARD — common in
   console DUnitX runs (no message pump) and host processes that pump
   messages on a different thread. A short retry loop is the conventional
   remedy. Vcl.Clipbrd raises EClipboardException on its own OpenClipboard
   failure, so we catch and retry — but only that. Other exception classes
   (EAccessViolation, EOutOfMemory, ...) are not transient clipboard
   contention and must propagate to the caller.}
  for I := 1 to 20 do
  begin
    try
      AOpenAction;
      Exit(True);
    except
      on E: EClipboardException do
        Sleep(10);
    end;
  end;
  Result := False;
end;

function TryClipboardOpenWithRetry: Boolean;
begin
  Result := TryClipboardOpenWithRetry(
    procedure begin Clipboard.Open; end);
end;

{Builds an HGLOBAL holding a CF_DIBV5 buffer (BITMAPV5HEADER + ARGB
 pixels) for ASrc. Returns 0 on allocation failure. The system takes
 ownership when the handle is passed to SetClipboardData; on any other
 path the caller must GlobalFree the result.}
function BuildAlphaDIBV5(ASrc: Vcl.Graphics.TBitmap): HGLOBAL;
var
  HeaderSize, RowBytes, ImageBytes, TotalBytes, Y: Integer;
  Header: PBitmapV5Header;
  PixelDest, ScanSrc: PByte;
begin
  HeaderSize := SizeOf(TBitmapV5Header);
  RowBytes := ASrc.Width * 4;
  ImageBytes := RowBytes * ASrc.Height;
  TotalBytes := HeaderSize + ImageBytes;

  Result := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if Result = 0 then
    Exit;

  Header := PBitmapV5Header(GlobalLock(Result));
  if Header = nil then
  begin
    GlobalFree(Result);
    Result := 0;
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
    GlobalUnlock(Result);
  end;
end;

{Builds an HGLOBAL holding a CF_DIB buffer (BITMAPINFOHEADER + 24-bit
 BGR pixels) for ASrc, with alpha pre-composited onto ABackground using
 the straight-alpha formula  out = src*A + bg*(255-A)  per channel.
 Returns 0 on allocation failure. Same ownership rules as the V5 path.

 The DIB is laid out bottom-up (positive biHeight): row 0 of the pixel
 buffer is the bottom row of the image. This is the historical CF_DIB
 convention; legacy / conservative consumers (older Win32 image
 viewers like Imagine) sometimes refuse top-down CF_DIB or render it
 flipped. Modern consumers handle both, so bottom-up is the safe
 default for the legacy-fallback format.}
function BuildFlatDIB(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): HGLOBAL;
var
  HeaderSize, RowBytesPadded, ImageBytes, TotalBytes, X, Y: Integer;
  Header: PBitmapInfoHeader;
  RowStart, PixelDest, ScanSrc: PByte;
  BgR, BgG, BgB, SrcB, SrcG, SrcR, SrcA: Byte;
  W, H: Integer;
begin
  W := ASrc.Width;
  H := ASrc.Height;
  HeaderSize := SizeOf(TBitmapInfoHeader);
  {pf24bit DIB rows are padded to a 4-byte boundary.}
  RowBytesPadded := ((W * 3 + 3) div 4) * 4;
  ImageBytes := RowBytesPadded * H;
  TotalBytes := HeaderSize + ImageBytes;

  Result := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if Result = 0 then
    Exit;

  Header := PBitmapInfoHeader(GlobalLock(Result));
  if Header = nil then
  begin
    GlobalFree(Result);
    Result := 0;
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
        SrcB := ScanSrc^; Inc(ScanSrc);
        SrcG := ScanSrc^; Inc(ScanSrc);
        SrcR := ScanSrc^; Inc(ScanSrc);
        SrcA := ScanSrc^; Inc(ScanSrc);
        {out = (src*A + bg*(255-A) + 127) div 255 — rounded straight-alpha
         composite. For our specific bitmaps the gap pixels carry RGB
         equal to ABackground, so the result there reduces to bg
         regardless of A; frame pixels (A=255) reduce to src. This makes
         the flattened image visually identical to a BackgroundAlpha=255
         render of the same content.}
        PixelDest^ := Byte((SrcB * SrcA + BgB * (255 - SrcA) + 127) div 255); Inc(PixelDest);
        PixelDest^ := Byte((SrcG * SrcA + BgG * (255 - SrcA) + 127) div 255); Inc(PixelDest);
        PixelDest^ := Byte((SrcR * SrcA + BgR * (255 - SrcA) + 127) div 255); Inc(PixelDest);
      end;
      {Padding bytes (if any) are left uninitialised; CF_DIB consumers
       only read the first W*3 bytes of each row.}
    end;
  finally
    GlobalUnlock(Result);
  end;
end;

{Creates a Windows HBITMAP from the pixel data inside ABitmap, with
 alpha composited onto ABackground (same compositing as BuildFlatDIB).
 Returns 0 on failure. The clipboard takes ownership when the handle
 is passed to SetClipboardData; on any other path the caller must
 DeleteObject the result.

 Published as CF_BITMAP alongside CF_DIBV5/CF_DIB so paste targets that
 distrust Windows-synthesised handles (some older Win32 image viewers)
 see a real device-dependent bitmap directly.}
function BuildFlatHBITMAP(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): HBITMAP;
var
  Mem: HGLOBAL;
  Header: PBitmapInfoHeader;
  PixelBits: PByte;
  ScreenDC: HDC;
begin
  Result := 0;
  Mem := BuildFlatDIB(ASrc, ABackground);
  if Mem = 0 then
    Exit;

  Header := PBitmapInfoHeader(GlobalLock(Mem));
  if Header = nil then
  begin
    GlobalFree(Mem);
    Exit;
  end;

  try
    PixelBits := PByte(Header);
    Inc(PixelBits, Header^.biSize);
    ScreenDC := GetDC(0);
    if ScreenDC <> 0 then
    try
      Result := CreateDIBitmap(ScreenDC, Header^, CBM_INIT, PixelBits,
        PBitmapInfo(Header)^, DIB_RGB_COLORS);
    finally
      ReleaseDC(0, ScreenDC);
    end;
  finally
    GlobalUnlock(Mem);
    {The DIB buffer was a temporary input to CreateDIBitmap; the HBITMAP
     it produced owns its own pixel storage. Always free the source.}
    GlobalFree(Mem);
  end;
end;

function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap; ABackground: TColor = TColor($000000)): Boolean;
var
  MemV5, MemFlat: HGLOBAL;
  HbmFlat: HBITMAP;
begin
  Result := False;
  if ABitmap = nil then
    Exit;

  if ABitmap.PixelFormat <> pf32bit then
  begin
    {Existing 24-bit path: Vcl.Clipbrd writes CF_BITMAP / CF_DIB, which
     legacy paste targets understand. Alpha never applies here.}
    Clipboard.Assign(ABitmap);
    Result := True;
    Exit;
  end;

  MemV5 := BuildAlphaDIBV5(ABitmap);
  if MemV5 = 0 then
    Exit;

  MemFlat := BuildFlatDIB(ABitmap, ABackground);
  if MemFlat = 0 then
  begin
    GlobalFree(MemV5);
    Exit;
  end;

  {The HBITMAP is built up-front so we can publish it as CF_BITMAP
   alongside the DIB formats. CreateDIBitmap can fail in low-resource
   conditions; if it does we silently skip the CF_BITMAP publish and
   rely on the OS to synthesise one from CF_DIB on demand.}
  HbmFlat := BuildFlatHBITMAP(ABitmap, ABackground);

  {Route through Vcl.Clipbrd.Clipboard.Open/Close so the clipboard owner
   is VCL's persistent hidden HWND. OpenClipboard(0) with a null owner
   window leaves the clipboard ownerless after EmptyClipboard, which
   makes SetClipboardData unreliable in some host processes (e.g. TC's
   Lister). Same pump as the working pf24bit Clipboard.Assign path.}
  if not TryClipboardOpenWithRetry then
  begin
    GlobalFree(MemV5);
    GlobalFree(MemFlat);
    if HbmFlat <> 0 then
      DeleteObject(HbmFlat);
    Exit;
  end;
  try
    EmptyClipboard;
    if SetClipboardData(CF_DIBV5, MemV5) = 0 then
    begin
      GlobalFree(MemV5);
      GlobalFree(MemFlat);
      if HbmFlat <> 0 then
        DeleteObject(HbmFlat);
      Exit;
    end;
    {SetClipboardData transferred ownership of MemV5 to the system.}
    if SetClipboardData(CF_DIB, MemFlat) = 0 then
    begin
      {CF_DIBV5 is already on the clipboard; failing to add the legacy
       sibling just means legacy paste will fall back to whatever the
       OS synthesises. Keep going so we still try CF_BITMAP.}
      GlobalFree(MemFlat);
    end;
    if (HbmFlat <> 0) and (SetClipboardData(CF_BITMAP, HbmFlat) = 0) then
      DeleteObject(HbmFlat);
    Result := True;
  finally
    Clipboard.Close;
  end;
end;

end.
