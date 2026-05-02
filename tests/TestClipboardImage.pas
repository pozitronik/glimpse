unit TestClipboardImage;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardImage = class
  public
    [Test] procedure CopyBitmap_NilSource_ReturnsFalse;
    [Test] procedure CopyBitmap_Pf24Bit_DoesNotRaise;
    [Test] procedure CopyBitmap_Pf32Bit_RoundTripPreservesAlpha;
    [Test] procedure CopyBitmap_Pf32Bit_RoundTripPreservesColors;
    [Test] procedure CopyBitmap_Pf32Bit_PublishesCfDibSibling;
    [Test] procedure CopyBitmap_Pf32Bit_CfDibCompositesAlphaOntoBackground;
  end;

implementation

uses
  System.SysUtils, System.Types, Winapi.Windows, Vcl.Graphics, Vcl.Clipbrd,
  uClipboardImage;

{The console DUnitX runner has no message pump, so OpenClipboard can fail
 transiently right after the helper closed it. Same retry idiom the helper
 uses, applied to the verify step.}
procedure ClipboardOpenWithRetry;
var
  I: Integer;
begin
  for I := 1 to 20 do
  begin
    try
      Clipboard.Open;
      Exit;
    except
      Sleep(10);
    end;
  end;
  Clipboard.Open; {Last attempt — let the exception escape if it still fails}
end;

procedure FillPf32Bit(ABmp: Vcl.Graphics.TBitmap; AB, AG, AR, AAlpha: Byte);
var
  X, Y: Integer;
  Row: PByte;
begin
  ABmp.PixelFormat := pf32bit;
  ABmp.AlphaFormat := afDefined;
  for Y := 0 to ABmp.Height - 1 do
  begin
    Row := PByte(ABmp.ScanLine[Y]);
    for X := 0 to ABmp.Width - 1 do
    begin
      Row^ := AB; Inc(Row);
      Row^ := AG; Inc(Row);
      Row^ := AR; Inc(Row);
      Row^ := AAlpha; Inc(Row);
    end;
  end;
end;

procedure TTestClipboardImage.CopyBitmap_NilSource_ReturnsFalse;
begin
  Assert.IsFalse(CopyBitmapToClipboard(nil),
    'Nil source must yield False without touching the clipboard');
end;

procedure TTestClipboardImage.CopyBitmap_Pf24Bit_DoesNotRaise;
var
  Bmp: Vcl.Graphics.TBitmap;
begin
  {pf24bit falls through to Vcl.Clipbrd.Clipboard.Assign — that path is
   already exercised by everything that uses Clipboard.Assign; here we
   just pin that the helper does not raise on an opaque source.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(8, 4);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 8, 4));
    Assert.IsTrue(CopyBitmapToClipboard(Bmp));
  finally
    Bmp.Free;
  end;
end;

procedure TTestClipboardImage.CopyBitmap_Pf32Bit_RoundTripPreservesAlpha;
var
  Bmp: Vcl.Graphics.TBitmap;
  Mem: HGLOBAL;
  Header: PBitmapV5Header;
  Pixels: PByte;
  RowBytes: Integer;
  AlphaByte: Byte;
begin
  {Push a known pf32bit bitmap and read CF_DIBV5 back. We assert the
   alpha mask survived (0xFF000000) and one pixel's alpha matches the
   value we wrote — proves the helper's CF_DIBV5 layout is intact.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(4, 4);
    FillPf32Bit(Bmp, 0, 200, 0, 128); {green, alpha=128}
    Assert.IsTrue(CopyBitmapToClipboard(Bmp));
  finally
    Bmp.Free;
  end;

  ClipboardOpenWithRetry;
  try
    Mem := GetClipboardData(CF_DIBV5);
    Assert.IsTrue(Mem <> 0, 'CF_DIBV5 not present after CopyBitmapToClipboard');
    Header := PBitmapV5Header(GlobalLock(Mem));
    Assert.IsNotNull(Header);
    try
      Assert.AreEqual<Cardinal>($FF000000, Header^.bV5AlphaMask,
        'V5 alpha mask must declare the high byte');
      Assert.AreEqual<Cardinal>(BI_BITFIELDS, Header^.bV5Compression);
      Assert.AreEqual<Integer>(32, Integer(Header^.bV5BitCount));
      Pixels := PByte(Header);
      Inc(Pixels, Header^.bV5Size);
      RowBytes := Bmp.Width * 4;
      {Sample (1, 1): alpha byte at offset 3 of that pixel}
      AlphaByte := PByte(Pixels + 1 * RowBytes + 1 * 4 + 3)^;
      Assert.AreEqual(128, Integer(AlphaByte),
        'Alpha byte from CF_DIBV5 must match the source pixel');
    finally
      GlobalUnlock(Mem);
    end;
  finally
    Clipboard.Close;
  end;
end;

procedure TTestClipboardImage.CopyBitmap_Pf32Bit_RoundTripPreservesColors;
var
  Bmp: Vcl.Graphics.TBitmap;
  Mem: HGLOBAL;
  Header: PBitmapV5Header;
  Pixels: PByte;
  RowBytes: Integer;
  B, G, R: Byte;
begin
  {Asymmetric channel values catch any R<->B swap inside the helper: a
   purely-blue source must read back as B=255, G=0, R=0.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(4, 4);
    FillPf32Bit(Bmp, 255, 0, 0, 200); {pure blue, alpha=200}
    Assert.IsTrue(CopyBitmapToClipboard(Bmp));
  finally
    Bmp.Free;
  end;

  ClipboardOpenWithRetry;
  try
    Mem := GetClipboardData(CF_DIBV5);
    Assert.IsTrue(Mem <> 0);
    Header := PBitmapV5Header(GlobalLock(Mem));
    try
      Pixels := PByte(Header);
      Inc(Pixels, Header^.bV5Size);
      RowBytes := 4 * 4;
      B := PByte(Pixels + 1 * RowBytes + 2 * 4 + 0)^;
      G := PByte(Pixels + 1 * RowBytes + 2 * 4 + 1)^;
      R := PByte(Pixels + 1 * RowBytes + 2 * 4 + 2)^;
      Assert.AreEqual(255, Integer(B), 'Blue byte must be 255 (no R<->B swap)');
      Assert.AreEqual(0, Integer(G), 'Green byte must be 0');
      Assert.AreEqual(0, Integer(R), 'Red byte must be 0');
    finally
      GlobalUnlock(Mem);
    end;
  finally
    Clipboard.Close;
  end;
end;

procedure TTestClipboardImage.CopyBitmap_Pf32Bit_PublishesCfDibSibling;
var
  Bmp: Vcl.Graphics.TBitmap;
  MemV5, MemFlat: HGLOBAL;
begin
  {Both CF_DIBV5 and CF_DIB must be on the clipboard after copying a
   pf32bit source. The CF_DIB sibling is what makes paste work in
   legacy targets that do not understand CF_DIBV5; without it they
   either show a broken image or refuse the paste entirely.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(4, 4);
    FillPf32Bit(Bmp, 255, 0, 0, 128);
    Assert.IsTrue(CopyBitmapToClipboard(Bmp, clBlack));
  finally
    Bmp.Free;
  end;

  ClipboardOpenWithRetry;
  try
    MemV5 := GetClipboardData(CF_DIBV5);
    MemFlat := GetClipboardData(CF_DIB);
    Assert.IsTrue(MemV5 <> 0, 'CF_DIBV5 missing (alpha-aware paste broken)');
    Assert.IsTrue(MemFlat <> 0, 'CF_DIB sibling missing (legacy paste broken)');
  finally
    Clipboard.Close;
  end;
end;

procedure TTestClipboardImage.CopyBitmap_Pf32Bit_CfDibCompositesAlphaOntoBackground;
var
  Bmp: Vcl.Graphics.TBitmap;
  Mem: HGLOBAL;
  Header: PBitmapInfoHeader;
  Pixels, P: PByte;
  RowBytesPadded: Integer;
  B, G, R: Byte;
begin
  {Source: pure blue (B=255, G=0, R=0) at alpha=128.
   Background: pure red (clRed = R=255, G=0, B=0).
   Expected straight-alpha composite per channel:
     B = (255*128 + 0  *127 + 127) div 255 = 32767 div 255 = 128
     G = (0  *128 + 0  *127 + 127) div 255 = 127  div 255 = 0
     R = (0  *128 + 255*127 + 127) div 255 = 32512 div 255 = 127
   Pinning these exact values catches both R<->B swaps and rounding
   regressions in BuildFlatDIB.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(4, 4);
    FillPf32Bit(Bmp, 255, 0, 0, 128);
    Assert.IsTrue(CopyBitmapToClipboard(Bmp, clRed));
  finally
    Bmp.Free;
  end;

  ClipboardOpenWithRetry;
  try
    Mem := GetClipboardData(CF_DIB);
    Assert.IsTrue(Mem <> 0);
    Header := PBitmapInfoHeader(GlobalLock(Mem));
    Assert.IsNotNull(Header);
    try
      Pixels := PByte(Header);
      Inc(Pixels, Header^.biSize);
      RowBytesPadded := ((4 * 3 + 3) div 4) * 4; {12 bytes for W=4, no padding needed}
      P := Pixels;
      Inc(P, 1 * RowBytesPadded + 1 * 3); {sample at (1,1)}
      B := P^; Inc(P);
      G := P^; Inc(P);
      R := P^;
      Assert.AreEqual(128, Integer(B), 'B should be src.B * A/255 = 128');
      Assert.AreEqual(0, Integer(G), 'G should be 0 (src.G and bg.G both 0)');
      Assert.AreEqual(127, Integer(R), 'R should be bg.R * (255-A)/255 = 127');
    finally
      GlobalUnlock(Mem);
    end;
  finally
    Clipboard.Close;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardImage);

end.
