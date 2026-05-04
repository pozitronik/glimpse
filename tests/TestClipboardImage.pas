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
    [Test] procedure CopyBitmap_Pf32Bit_CfDibIsBottomUp;
    [Test] procedure CopyBitmap_Pf32Bit_PublishesCfBitmapSibling;
    {Retry contract for the open helper. Earlier the bare except absorbed
     every exception class and burned 200 ms retrying problems that were
     not transient clipboard contention.}
    [Test] procedure RetryOpener_SucceedsImmediately_ReturnsTrue;
    [Test] procedure RetryOpener_AlwaysClipboardException_GivesUp;
    [Test] procedure RetryOpener_NonClipboardException_Propagates;
    [Test] procedure RetryOpener_RecoversAfterTransientFailures;
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
   regressions in BuildFlatDIB.

   Source pixels are uniform, so the bottom-up DIB orientation does
   not affect the sample values; the orientation invariant is checked
   separately by CopyBitmap_Pf32Bit_CfDibIsBottomUp.}
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
      Inc(P, 1 * RowBytesPadded + 1 * 3); {sample at buffer offset (row 1, col 1)}
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

{Helper: writes a single distinguishing pixel at (X, Y) in the source so
 the bottom-up orientation test can verify which row of the DIB buffer
 holds which source row. Existing FillPf32Bit produces a uniform color
 which cannot detect orientation.}
procedure SetPf32Pixel(ABmp: Vcl.Graphics.TBitmap; AX, AY: Integer; AB, AG, AR, AAlpha: Byte);
var
  P: PByte;
begin
  P := PByte(ABmp.ScanLine[AY]);
  Inc(P, AX * 4);
  P^ := AB; Inc(P);
  P^ := AG; Inc(P);
  P^ := AR; Inc(P);
  P^ := AAlpha;
end;

procedure TTestClipboardImage.CopyBitmap_Pf32Bit_CfDibIsBottomUp;
var
  Bmp: Vcl.Graphics.TBitmap;
  Mem: HGLOBAL;
  Header: PBitmapInfoHeader;
  Pixels, P: PByte;
  RowBytesPadded: Integer;
  TopMarkerB, BottomMarkerB: Byte;
begin
  {Plant distinguishable markers at source rows 0 (top) and H-1 (bottom),
   then verify CF_DIB layout is bottom-up: pixel-buffer row 0 holds the
   bottom of the image and pixel-buffer row H-1 holds the top.

   biHeight must be positive (>0) for the bottom-up convention; older
   image viewers can refuse top-down CF_DIB or render it flipped.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.AlphaFormat := afDefined;
    Bmp.SetSize(4, 4);
    FillPf32Bit(Bmp, 0, 0, 0, 255); {start opaque black}
    SetPf32Pixel(Bmp, 0, 0, 200, 0, 0, 255); {top-left pixel: B=200}
    SetPf32Pixel(Bmp, 0, 3, 50, 0, 0, 255);  {bottom-left pixel: B=50}
    Assert.IsTrue(CopyBitmapToClipboard(Bmp, clBlack));
  finally
    Bmp.Free;
  end;

  ClipboardOpenWithRetry;
  try
    Mem := GetClipboardData(CF_DIB);
    Assert.IsTrue(Mem <> 0);
    Header := PBitmapInfoHeader(GlobalLock(Mem));
    try
      Assert.IsTrue(Header^.biHeight > 0,
        'biHeight must be positive (bottom-up DIB) for legacy compatibility');
      Pixels := PByte(Header);
      Inc(Pixels, Header^.biSize);
      RowBytesPadded := ((4 * 3 + 3) div 4) * 4;
      {Buffer row 0 = bottom of source = B=50}
      P := Pixels;
      BottomMarkerB := P^;
      {Buffer row H-1 = top of source = B=200}
      P := Pixels;
      Inc(P, 3 * RowBytesPadded);
      TopMarkerB := P^;
      Assert.AreEqual(50, Integer(BottomMarkerB),
        'Pixel-buffer row 0 should hold the SOURCE bottom row (B=50)');
      Assert.AreEqual(200, Integer(TopMarkerB),
        'Pixel-buffer row H-1 should hold the SOURCE top row (B=200)');
    finally
      GlobalUnlock(Mem);
    end;
  finally
    Clipboard.Close;
  end;
end;

procedure TTestClipboardImage.CopyBitmap_Pf32Bit_PublishesCfBitmapSibling;
var
  Bmp: Vcl.Graphics.TBitmap;
  Hbm: HBITMAP;
begin
  {Apps that distrust the OS's CF_DIB->CF_BITMAP synthesis (a small set
   of older Win32 image viewers) need the HBITMAP published explicitly.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(4, 4);
    FillPf32Bit(Bmp, 255, 0, 0, 200);
    Assert.IsTrue(CopyBitmapToClipboard(Bmp, clBlack));
  finally
    Bmp.Free;
  end;

  ClipboardOpenWithRetry;
  try
    Hbm := HBITMAP(GetClipboardData(CF_BITMAP));
    Assert.IsTrue(Hbm <> 0,
      'CF_BITMAP missing (apps that distrust DIB synthesis would refuse paste)');
  finally
    Clipboard.Close;
  end;
end;

{ -------- TryClipboardOpenWithRetry retry contract -------- }

procedure TTestClipboardImage.RetryOpener_SucceedsImmediately_ReturnsTrue;
var
  Calls: Integer;
begin
  Calls := 0;
  Assert.IsTrue(TryClipboardOpenWithRetry(
    procedure
    begin
      Inc(Calls);
    end));
  Assert.AreEqual(1, Calls, 'Successful first attempt must not retry');
end;

procedure TTestClipboardImage.RetryOpener_AlwaysClipboardException_GivesUp;
var
  Calls: Integer;
  Result: Boolean;
begin
  Calls := 0;
  Result := TryClipboardOpenWithRetry(
    procedure
    begin
      Inc(Calls);
      raise EClipboardException.Create('persistent contention');
    end);
  Assert.IsFalse(Result, 'Persistent EClipboardException must exhaust retries');
  Assert.AreEqual(20, Calls,
    'Retry budget is fixed at 20 attempts; if a future tweak changes that, update this assertion');
end;

procedure TTestClipboardImage.RetryOpener_NonClipboardException_Propagates;
begin
  {Bug-fix pin: the original bare except absorbed everything and burned
   200 ms retrying. The narrowed handler must let non-EClipboardException
   classes propagate. EArgumentException stands in for any unrelated
   exception (EOutOfMemory, EAccessViolation, EOSError) — they all share
   the same propagation contract, and using a non-special class here
   keeps the test's leak detection clean.}
  Assert.WillRaise(
    procedure
    begin
      TryClipboardOpenWithRetry(
        procedure
        begin
          raise EArgumentException.Create('non-transient');
        end);
    end,
    EArgumentException,
    'Non-clipboard exceptions must propagate, not be retried');
end;

procedure TTestClipboardImage.RetryOpener_RecoversAfterTransientFailures;
var
  Calls: Integer;
  Result: Boolean;
begin
  {Two transient failures, then a success. The helper must succeed and
   the call count proves the retry actually fired before the success.}
  Calls := 0;
  Result := TryClipboardOpenWithRetry(
    procedure
    begin
      Inc(Calls);
      if Calls < 3 then
        raise EClipboardException.Create('transient');
    end);
  Assert.IsTrue(Result, 'Recovery after a few transient failures must succeed');
  Assert.AreEqual(3, Calls);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardImage);

end.
