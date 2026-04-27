{Clipboard publisher for alpha-aware bitmaps. Pushes pf32bit sources as
 CF_DIBV5 so paste targets that honour ARGB (Paint.NET, GIMP, Krita,
 Affinity Photo) receive the alpha channel. Falls back to Vcl.Clipbrd's
 standard 24-bit handling for pf24bit sources so the existing copy paths
 keep their current behaviour.

 Apps that prefer CF_BITMAP / CF_DIB (Paint, Photoshop's default paste)
 receive a Windows-synthesised opaque copy automatically — alpha is lost on
 that path but the image is still pasteable. We deliberately do NOT publish
 CF_BITMAP as a sibling: paste targets that call GetPriorityClipboardFormat
 with CF_BITMAP first would pick that one and never inspect CF_DIBV5,
 dropping alpha for clients that would otherwise honour it.}
unit uClipboardImage;

interface

uses
  Vcl.Graphics;

{Pushes ABitmap to the system clipboard. When ABitmap is pf32bit the
 pixels are written as CF_DIBV5 with explicit ARGB bit-masks; otherwise
 the call routes through Vcl.Clipbrd.Clipboard.Assign which yields
 CF_BITMAP / CF_DIB. Returns True on success.}
function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap): Boolean;

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

function TryClipboardOpenWithRetry: Boolean;
var
  I: Integer;
begin
  {OpenClipboard fails transiently when another opener held it a moment
   ago and Windows has not yet propagated WM_DESTROYCLIPBOARD — common in
   console DUnitX runs (no message pump) and host processes that pump
   messages on a different thread. A short retry loop is the conventional
   remedy. Vcl.Clipbrd raises EClipboardException on its own OpenClipboard
   failure, so we catch and retry.}
  for I := 1 to 20 do
  begin
    try
      Clipboard.Open;
      Exit(True);
    except
      Sleep(10);
    end;
  end;
  Result := False;
end;

function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap): Boolean;
var
  HeaderSize, RowBytes, ImageBytes, TotalBytes, Y: Integer;
  Mem: HGLOBAL;
  Header: PBitmapV5Header;
  PixelDest, ScanSrc: PByte;
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

  HeaderSize := SizeOf(TBitmapV5Header);
  RowBytes := ABitmap.Width * 4;
  ImageBytes := RowBytes * ABitmap.Height;
  TotalBytes := HeaderSize + ImageBytes;

  Mem := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if Mem = 0 then
    Exit;

  Header := PBitmapV5Header(GlobalLock(Mem));
  if Header = nil then
  begin
    GlobalFree(Mem);
    Exit;
  end;

  try
    FillChar(Header^, HeaderSize, 0);
    Header^.bV5Size := HeaderSize;
    Header^.bV5Width := ABitmap.Width;
    {Negative height = top-down DIB; scanline 0 of the source maps to
     the first row of pixel data right after the header.}
    Header^.bV5Height := -ABitmap.Height;
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

    {Pixel data follows the header. ABitmap.ScanLine[0] is the topmost
     row in a pf32bit DIB, matching our top-down (negative-height) DIB.}
    PixelDest := PByte(Header);
    Inc(PixelDest, HeaderSize);
    for Y := 0 to ABitmap.Height - 1 do
    begin
      ScanSrc := PByte(ABitmap.ScanLine[Y]);
      Move(ScanSrc^, PixelDest^, RowBytes);
      Inc(PixelDest, RowBytes);
    end;
  finally
    GlobalUnlock(Mem);
  end;

  {Route through Vcl.Clipbrd.Clipboard.Open/Close so the clipboard owner is
   VCL's persistent hidden HWND. OpenClipboard(0) with a null owner window
   leaves the clipboard ownerless after EmptyClipboard, which makes
   SetClipboardData unreliable in some host processes (e.g. Total Commander's
   Lister). Using the same pump that Clipboard.Assign uses keeps the pf32bit
   path consistent with the working pf24bit path above.}
  if not TryClipboardOpenWithRetry then
  begin
    GlobalFree(Mem);
    Exit;
  end;
  try
    EmptyClipboard;
    if SetClipboardData(CF_DIBV5, Mem) = 0 then
    begin
      GlobalFree(Mem);
      Exit;
    end;
    {SetClipboardData transferred ownership of Mem to the system; do not
     free it ourselves — the OS releases it on the next EmptyClipboard.}
    Result := True;
  finally
    Clipboard.Close;
  end;
end;

end.
