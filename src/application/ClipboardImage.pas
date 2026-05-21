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

function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap;
  ABackground: TColor;
  const AStrategies: TArray<IClipboardFormatStrategy>;
  const AClipboard: IImageClipboard;
  out AFailedFormatName: string): Boolean;
var
  I, J: Integer;
  AnyPublished: Boolean;
begin
  Result := False;
  AFailedFormatName := '';
  if ABitmap = nil then
    Exit;

  if ABitmap.PixelFormat <> pf32bit then
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

  Log(Format('CopyBitmapToClipboard: %dx%d pf32bit, %d strategies',
    [ABitmap.Width, ABitmap.Height, Length(AStrategies)]));

  {Allocate phase: every enabled format must succeed or we abort the
   whole copy. Reverse-order Discard frees the most-recent first.}
  for I := 0 to High(AStrategies) do
    if not AStrategies[I].Allocate(ABitmap, ABackground) then
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
end;

end.
