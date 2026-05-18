{Clipboard publisher for bitmap images.

 For pf32bit sources CopyBitmapToClipboard orchestrates over a caller-
 supplied array of IClipboardFormatStrategy implementations (see
 uClipboardFormatStrategies). Each strategy owns one Win32 clipboard
 format end-to-end (allocation, publication, cleanup). The orchestrator
 here:
   1. Allocates every strategy's payload in publish order.
   2. Aborts (reverse-order Discard of previously allocated strategies,
      returns False, names the failing format in AFailedFormatName) if
      any allocation fails — every enabled format must succeed or the
      whole copy fails loudly. No silent skipping.
   3. Opens the clipboard once, EmptyClipboard, then walks the array
      again calling Publish on each. Per-format Publish failures are
      logged but do not abort the cycle so other formats still publish.

 For pf24bit sources we route through Vcl.Clipbrd.Clipboard.Assign,
 which yields CF_BITMAP / CF_DIB the standard way; alpha never applies
 to that path and the strategy toggles do not gate it (24-bit single
 frames are tiny and not the memory bottleneck).

 The CF_HDROP "paste as file reference" path lives separately in
 uClipboardFileDrop — it has nothing to do with bitmap formats and
 belongs with its own tests.}
unit uClipboardImage;

interface

uses
  System.SysUtils, System.UITypes, Vcl.Graphics,
  uClipboardFormatStrategies;

type
  {Action that opens the clipboard. Defaults to Vcl.Clipbrd.Clipboard.Open
   in production; tests inject throwers so the retry policy can be
   exercised without owning the global clipboard.}
  TClipboardOpenAction = reference to procedure;

  {Publishes ABitmap to the system clipboard via the supplied strategy
   array (see uClipboardFormatStrategies.BuildClipboardFormatStrategies).

   pf32bit sources go through the orchestrator over AStrategies.
   pf24bit sources are routed to Vcl.Clipbrd.Clipboard.Assign and
   AStrategies is ignored — 24-bit single frames are too small to
   benefit from per-format gating.

   When AStrategies is empty (all toggles off), returns True without
   touching the clipboard — per the agreed UX, the user has explicitly
   disabled every format so we do nothing rather than fail.

   Returns True when at least one strategy successfully published
   (or the pf24bit path completed, or the array was empty). Returns
   False when any enabled strategy's Allocate failed; AFailedFormatName
   names the failing strategy so the caller can surface an actionable
   error. On non-allocation failure (clipboard open exhausted retries
   etc.) Result is False and AFailedFormatName is left empty.

   ABackground is the colour semi-transparent pixels are flattened
   against for formats that need a flat opaque copy (CF_DIB, CF_BITMAP);
   strategies that carry true alpha (CF_DIBV5, PNG) ignore it.}
function CopyBitmapToClipboard(ABitmap: Vcl.Graphics.TBitmap;
  ABackground: TColor;
  const AStrategies: TArray<IClipboardFormatStrategy>;
  out AFailedFormatName: string): Boolean;

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
  Winapi.Windows, Vcl.Clipbrd, uDebugLog;

procedure Log(const AMsg: string);
begin
  DebugLog('Clipboard', AMsg);
end;

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
    {Existing 24-bit path: Vcl.Clipbrd writes CF_BITMAP / CF_DIB, which
     legacy paste targets understand. Alpha never applies here and the
     per-format toggles do not gate this path — 24-bit single frames are
     tiny and never the memory bottleneck. Intentional asymmetry with
     the pf32bit branch below.}
    Clipboard.Assign(ABitmap);
    Result := True;
    Exit;
  end;

  if Length(AStrategies) = 0 then
  begin
    {Every per-format toggle is off. Per the agreed UX, silently
     succeed rather than fail — the user explicitly opted out of
     publishing anything.}
    Log('CopyBitmapToClipboard: empty strategy array, skipping publish');
    Result := True;
    Exit;
  end;

  Log(Format('CopyBitmapToClipboard: %dx%d pf32bit, %d strategies',
    [ABitmap.Width, ABitmap.Height, Length(AStrategies)]));

  {Allocate phase. Every enabled format must allocate successfully or
   we abort the whole copy. Reverse-order Discard mirrors RAII so the
   most-recently-allocated payload is freed first, which is the easier
   order for future readers to reason about.}
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

  {Publish phase. The clipboard is opened once and EmptyClipboard
   clears any prior contents before we walk the strategies. Per-format
   Publish failures are logged inside the strategy and do not abort the
   cycle — getting some formats on the clipboard is strictly better
   than getting none.}
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
