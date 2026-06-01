{Copies a finished bitmap to the clipboard. pf32bit routes through the
 strategy array (allocate-all-or-abort, then publish each; per-format
 publish failures are logged but non-fatal); pf24bit routes through
 IImageClipboard.AssignBitmap. The OS clipboard is reached only through
 IImageClipboard, so the orchestration is testable with a fake.}
unit ClipboardImage;

interface

uses
  System.UITypes, Vcl.Graphics,
  ClipboardFormatStrategies;

type
  {The OS clipboard surface CopyBitmapToClipboard needs. The VCL adapter
   is TVclImageClipboard in VclClipboard; tests supply a fake.}
  IImageClipboard = interface
    ['{2E8A5C19-6B4D-4F73-A1E0-9C5B3D7F8A24}']
    {One-shot pf24bit copy; opens, sets and closes the clipboard itself.}
    procedure AssignBitmap(ABitmap: Vcl.Graphics.TBitmap);
    {Opens the clipboard, retrying transient contention. False = gave up.}
    function TryOpen: Boolean;
    {Empties the clipboard; valid only between a successful TryOpen and Close.}
    procedure Empty;
    procedure Close;
  end;

{Empty AStrategies returns True without touching the clipboard.
 AFailedFormatName is set when an Allocate fails; empty on success
 or on non-allocation failure (clipboard open exhausted retries).
 ABackground is composited onto semi-transparent pixels for formats
 without true alpha.}
function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap;
  ABackground: TColor;
  const AStrategies: TArray<IClipboardFormatStrategy>;
  const AClipboard: IImageClipboard;
  out AFailedFormatName: string): Boolean;

implementation

uses
  System.SysUtils, Logging;

procedure Log(const AMsg: string);
begin
  DebugLog('Clipboard', AMsg);
end;

{Returns a fresh pf32bit copy of a pf24bit source with alpha=255 on every
 pixel. Needed because the DIBV5 / DIB / BITMAP strategies walk BGRA
 scanlines and would read garbage from a 3-bytes-per-pixel layout; the
 PNG / JPEG strategies are layout-agnostic but go through the same
 promoted bitmap so the orchestrator can stay uniform.}
function PromoteToPf32(ASource: Vcl.Graphics.TBitmap): Vcl.Graphics.TBitmap;
var
  Y, X, W, H: Integer;
  SrcRow, DstRow: PByte;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  try
    Result.PixelFormat := pf32bit;
    Result.AlphaFormat := afDefined;
    W := ASource.Width;
    H := ASource.Height;
    Result.SetSize(W, H);
    for Y := 0 to H - 1 do
    begin
      SrcRow := PByte(ASource.ScanLine[Y]);
      DstRow := PByte(Result.ScanLine[Y]);
      for X := 0 to W - 1 do
      begin
        DstRow^ := SrcRow^; Inc(SrcRow); Inc(DstRow); {B}
        DstRow^ := SrcRow^; Inc(SrcRow); Inc(DstRow); {G}
        DstRow^ := SrcRow^; Inc(SrcRow); Inc(DstRow); {R}
        DstRow^ := 255; Inc(DstRow); {A}
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap;
  ABackground: TColor;
  const AStrategies: TArray<IClipboardFormatStrategy>;
  const AClipboard: IImageClipboard;
  out AFailedFormatName: string): Boolean;
var
  I, J: Integer;
  AnyPublished: Boolean;
  Working: Vcl.Graphics.TBitmap;
begin
  Result := False;
  AFailedFormatName := '';
  if ABitmap = nil then
    Exit;

  {pf24bit + no strategies enabled — keep the legacy "just put a bitmap
   on the clipboard" behaviour so users who disabled every format toggle
   still get something pasteable. With any strategy enabled we route
   through the orchestrator instead so the toggles actually take effect.}
  if (ABitmap.PixelFormat <> pf32bit) and (Length(AStrategies) = 0) then
  begin
    AClipboard.AssignBitmap(ABitmap);
    Result := True;
    Exit;
  end;

  if Length(AStrategies) = 0 then
  begin
    Log('CopyBitmapToClipboard: empty strategy array, skipping publish');
    Result := True;
    Exit;
  end;

  if ABitmap.PixelFormat <> pf32bit then
    Working := PromoteToPf32(ABitmap)
  else
    Working := ABitmap;
  try
    Log(Format('CopyBitmapToClipboard: %dx%d (source pf=%d, working pf32bit), %d strategies',
      [Working.Width, Working.Height, Ord(ABitmap.PixelFormat), Length(AStrategies)]));

    {Allocate phase: every enabled format must succeed or we abort the
     whole copy. Reverse-order Discard frees the most-recent first.}
    for I := 0 to High(AStrategies) do
      if not AStrategies[I].Allocate(Working, ABackground) then
      begin
        AFailedFormatName := AStrategies[I].Name;
        Log(Format('CopyBitmapToClipboard: aborting publish - %s allocation failed',
          [AFailedFormatName]));
        for J := I - 1 downto 0 do
          AStrategies[J].Discard;
        Exit;
      end;

    {Publish phase: per-format failures are logged inside the strategy
     and do not abort the cycle.}
    if not AClipboard.TryOpen then
    begin
      Log('CopyBitmapToClipboard: clipboard open exhausted retries');
      for J := High(AStrategies) downto 0 do
        AStrategies[J].Discard;
      Exit;
    end;
    try
      AClipboard.Empty;
      {Per-format failures are non-fatal, but if every format fails the
       clipboard was emptied with nothing put back — report failure.}
      AnyPublished := False;
      for I := 0 to High(AStrategies) do
        if AStrategies[I].Publish then
          AnyPublished := True;
      Result := AnyPublished;
    finally
      AClipboard.Close;
    end;
  finally
    if Working <> ABitmap then
      Working.Free;
  end;
end;

end.
