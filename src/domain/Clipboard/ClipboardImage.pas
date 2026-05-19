{Clipboard publisher for bitmap images. pf32bit routes through the
 strategy array (allocate-all-or-abort, then publish each, per-format
 publish failures are logged but non-fatal). pf24bit routes through
 Vcl.Clipbrd.Clipboard.Assign and ignores AStrategies.}
unit ClipboardImage;

interface

uses
  System.SysUtils, System.UITypes, Vcl.Graphics,
  ClipboardFormatStrategies;

type
  {Test seam — production passes Clipboard.Open.}
  TClipboardOpenAction = reference to procedure;

  {Empty AStrategies returns True without touching the clipboard.
   AFailedFormatName is set when an Allocate fails; empty on success
   or on non-allocation failure (clipboard open exhausted retries).
   ABackground is composited onto semi-transparent pixels for formats
   without true alpha.}
function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap;
  ABackground: TColor;
  const AStrategies: TArray<IClipboardFormatStrategy>;
  out AFailedFormatName: string): Boolean;

{Retries 20 times with 10 ms sleeps; matches only EClipboardException
 so unrelated failures (EAccessViolation/EOutOfMemory) propagate.}
function TryClipboardOpenWithRetry: Boolean; overload;
function TryClipboardOpenWithRetry(const AOpenAction: TClipboardOpenAction): Boolean; overload;

implementation

uses
  Winapi.Windows, Vcl.Clipbrd, Logging;

procedure Log(const AMsg: string);
begin
  DebugLog('Clipboard', AMsg);
end;

function TryClipboardOpenWithRetry(const AOpenAction: TClipboardOpenAction): Boolean;
var
  I: Integer;
begin
  {OpenClipboard fails transiently when another opener held it before
   Windows propagated WM_DESTROYCLIPBOARD; common in console DUnitX runs
   without a message pump.}
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
    procedure
    begin
      Clipboard.Open;
    end);
end;

function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap;
  ABackground: TColor;
  const AStrategies: TArray<IClipboardFormatStrategy>;
  out AFailedFormatName: string): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  AFailedFormatName := '';
  if ABitmap = nil then
    Exit;

  if ABitmap.PixelFormat <> pf32bit then
  begin
    Clipboard.Assign(ABitmap);
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
  if not TryClipboardOpenWithRetry then
  begin
    Log('CopyBitmapToClipboard: TryClipboardOpenWithRetry exhausted retries');
    for J := High(AStrategies) downto 0 do
      AStrategies[J].Discard;
    Exit;
  end;
  try
    EmptyClipboard;
    for I := 0 to High(AStrategies) do
      AStrategies[I].Publish;
    Result := True;
  finally
    Clipboard.Close;
  end;
end;

end.
