unit TestLineSplitter;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLineSplitterFeed = class
  public
    {Single full line in one Feed: the callback fires with the line text
     stripped of its terminator.}
    [Test] procedure TestSingleLineLFOnly;
    [Test] procedure TestSingleLineCRLF;
    {Multiple lines arriving in one chunk: each completed line fires the
     callback in order. Order is the contract pipe-reading consumers
     depend on (ffmpeg progress, stderr decoders).}
    [Test] procedure TestMultipleLinesInOneFeed;
    {Partial line carries over to the next Feed: the callback only fires
     once the closing LF arrives. Pin the rolling-buffer behaviour
     because the streaming consumers depend on no-line-prefix-leaks.}
    [Test] procedure TestPartialLineHeldUntilLF;
    [Test] procedure TestSplitCRLFAcrossFeeds;
    {Empty lines (LF-only or stripped to zero length) are swallowed
     silently — see contract note in uLineSplitter docstring. ffmpeg
     emits blank progress lines that would otherwise spam the callback.}
    [Test] procedure TestEmptyLinesSwallowed;
    {Zero-byte and negative Feed is a no-op. Pipe readers can call Feed
     with ABytesRead=0 on a non-blocking pipe with no data; the
     splitter must accept that without raising or losing state.}
    [Test] procedure TestZeroBytesIsNoOp;
    {UTF-8 multi-byte sequence (e.g. a non-ASCII character) must round-
     trip through the decoder. Was previously implicit in the production
     UTF8Encoding setup; now pinned.}
    [Test] procedure TestUtf8MultiByteSequence;
    {Invalid UTF-8 bytes (a lone 0xFF) do NOT raise; the decoder emits
     the replacement char and keeps going. The splitter is fed
     pipe-from-ffmpeg bytes that occasionally include garbage; raising
     would crash the consumer. Pinning the lenient behaviour.}
    [Test] procedure TestInvalidUtf8DoesNotRaise;
  end;

  [TestFixture]
  TTestLineSplitterFlush = class
  public
    {Trailing bytes without a terminating LF must be emitted by Flush
     so the caller sees the end-of-stream tail. ffmpeg's final stderr
     line often lacks a newline.}
    [Test] procedure TestFlushEmitsUnterminatedTail;
    [Test] procedure TestFlushStripsTrailingCR;
    [Test] procedure TestFlushOnEmptyPartialDoesNothing;
    [Test] procedure TestFlushClearsPartial;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uLineSplitter;

type
  {Captures every line the splitter dispatches so a test can assert on
   the order + content. The Feed/Flush callback type is `TProc<string>`
   — a method reference here would also work; closure is simpler for
   test scaffolding.}
  TLineCapture = class
  strict private
    FLines: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure OnLine(AValue: string);
    function Count: Integer;
    function Item(AIndex: Integer): string;
  end;

constructor TLineCapture.Create;
begin
  inherited Create;
  FLines := TList<string>.Create;
end;

destructor TLineCapture.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TLineCapture.OnLine(AValue: string);
begin
  FLines.Add(AValue);
end;

function TLineCapture.Count: Integer;
begin
  Result := FLines.Count;
end;

function TLineCapture.Item(AIndex: Integer): string;
begin
  Result := FLines[AIndex];
end;

{Helper: feeds the given raw bytes to the splitter and returns a
 fresh capture. Caller frees the capture.}
function FeedAndCapture(var ASplitter: TLineSplitter; const ABytes: TBytes): TLineCapture;
var
  Capture: TLineCapture;
begin
  Capture := TLineCapture.Create;
  if Length(ABytes) > 0 then
    ASplitter.Feed(ABytes[0], Length(ABytes), Capture.OnLine);
  Result := Capture;
end;

function StrToBytes(const AStr: AnsiString): TBytes;
begin
  SetLength(Result, Length(AStr));
  if Length(AStr) > 0 then
    Move(AStr[1], Result[0], Length(AStr));
end;

{ TTestLineSplitterFeed }

procedure TTestLineSplitterFeed.TestSingleLineLFOnly;
var
  S: TLineSplitter;
  Cap: TLineCapture;
begin
  S := Default(TLineSplitter);
  Cap := FeedAndCapture(S, StrToBytes('hello'#10));
  try
    Assert.AreEqual<Integer>(1, Cap.Count);
    Assert.AreEqual('hello', Cap.Item(0));
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestSingleLineCRLF;
var
  S: TLineSplitter;
  Cap: TLineCapture;
begin
  S := Default(TLineSplitter);
  Cap := FeedAndCapture(S, StrToBytes('hello'#13#10));
  try
    Assert.AreEqual<Integer>(1, Cap.Count);
    Assert.AreEqual('hello', Cap.Item(0),
      'CRLF terminator must surface as the line text without the CR');
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestMultipleLinesInOneFeed;
var
  S: TLineSplitter;
  Cap: TLineCapture;
begin
  S := Default(TLineSplitter);
  Cap := FeedAndCapture(S, StrToBytes('a'#10'b'#10'c'#10));
  try
    Assert.AreEqual<Integer>(3, Cap.Count);
    Assert.AreEqual('a', Cap.Item(0));
    Assert.AreEqual('b', Cap.Item(1));
    Assert.AreEqual('c', Cap.Item(2));
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestPartialLineHeldUntilLF;
var
  S: TLineSplitter;
  Cap1, Cap2: TLineCapture;
begin
  S := Default(TLineSplitter);
  Cap1 := FeedAndCapture(S, StrToBytes('hel'));
  try
    Assert.AreEqual<Integer>(0, Cap1.Count,
      'Partial line without LF must not dispatch');
  finally
    Cap1.Free;
  end;

  Cap2 := FeedAndCapture(S, StrToBytes('lo'#10));
  try
    Assert.AreEqual<Integer>(1, Cap2.Count);
    Assert.AreEqual('hello', Cap2.Item(0),
      'Partial line must be glued to the next Feed');
  finally
    Cap2.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestSplitCRLFAcrossFeeds;
var
  S: TLineSplitter;
  Cap1, Cap2: TLineCapture;
begin
  {CR arrives in chunk 1; LF arrives in chunk 2. The splitter must
   detect that #13#10 spans the two and strip the CR — otherwise a
   trailing CR survives in the dispatched line and breaks downstream
   parsers expecting plain text.}
  S := Default(TLineSplitter);
  Cap1 := FeedAndCapture(S, StrToBytes('hello'#13));
  try
    Assert.AreEqual<Integer>(0, Cap1.Count, 'CR without LF must not dispatch');
  finally
    Cap1.Free;
  end;

  Cap2 := FeedAndCapture(S, StrToBytes(#10'world'#10));
  try
    Assert.AreEqual<Integer>(2, Cap2.Count);
    Assert.AreEqual('hello', Cap2.Item(0),
      'CR carried over from previous Feed must be stripped before the LF lands');
    Assert.AreEqual('world', Cap2.Item(1));
  finally
    Cap2.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestEmptyLinesSwallowed;
var
  S: TLineSplitter;
  Cap: TLineCapture;
begin
  S := Default(TLineSplitter);
  {'a' LF LF 'b' LF: the empty middle line (LF immediately after a
   line's LF) is swallowed, so only 'a' and 'b' dispatch.}
  Cap := FeedAndCapture(S, StrToBytes('a'#10#10'b'#10));
  try
    Assert.AreEqual<Integer>(2, Cap.Count);
    Assert.AreEqual('a', Cap.Item(0));
    Assert.AreEqual('b', Cap.Item(1));
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestZeroBytesIsNoOp;
var
  S: TLineSplitter;
  Cap: TLineCapture;
  Dummy: Byte;
begin
  S := Default(TLineSplitter);
  Cap := TLineCapture.Create;
  try
    Dummy := 0;
    S.Feed(Dummy, 0, Cap.OnLine);
    Assert.AreEqual<Integer>(0, Cap.Count);
    {Internal partial must remain empty after a no-op feed.}
    Assert.AreEqual<Integer>(0, Length(S.Partial));
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestUtf8MultiByteSequence;
var
  S: TLineSplitter;
  Cap: TLineCapture;
  Bytes: TBytes;
begin
  {U+00E9 (é) encodes as 0xC3 0xA9 in UTF-8. Round-trip through the
   splitter must yield the multi-byte character intact.}
  S := Default(TLineSplitter);
  SetLength(Bytes, 4);
  Bytes[0] := $C3;
  Bytes[1] := $A9;
  Bytes[2] := $0A;
  Bytes[3] := 0;
  Cap := FeedAndCapture(S, Copy(Bytes, 0, 3));
  try
    Assert.AreEqual<Integer>(1, Cap.Count);
    {Use the explicit codepoint to avoid source-file encoding ambiguity
     (Delphi may compile a literal 'é' as ANSI 0xE9 depending on the
     file's BOM).}
    Assert.AreEqual(string(#$00E9), Cap.Item(0));
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFeed.TestInvalidUtf8DoesNotRaise;
var
  S: TLineSplitter;
  Cap: TLineCapture;
  Bytes: TBytes;
begin
  {Lone 0xFF is invalid UTF-8. The decoder must emit a replacement
   char and the Feed must complete normally rather than raising —
   pipe streams from external processes can carry codepage drift.}
  S := Default(TLineSplitter);
  SetLength(Bytes, 2);
  Bytes[0] := $FF;
  Bytes[1] := $0A;
  Cap := TLineCapture.Create;
  try
    Assert.WillNotRaise(
      procedure
      begin
        S.Feed(Bytes[0], Length(Bytes), Cap.OnLine);
      end,
      nil,
      'Invalid UTF-8 must decode to a replacement char, not raise');
    Assert.AreEqual<Integer>(1, Cap.Count,
      'Line still dispatches even with invalid bytes inside');
  finally
    Cap.Free;
  end;
end;

{ TTestLineSplitterFlush }

procedure TTestLineSplitterFlush.TestFlushEmitsUnterminatedTail;
var
  S: TLineSplitter;
  CapDuringFeed, CapDuringFlush: TLineCapture;
begin
  {ffmpeg's last stderr line often lacks a terminator. Flush must
   surface it so the caller sees the end-of-stream content.}
  S := Default(TLineSplitter);
  CapDuringFeed := FeedAndCapture(S, StrToBytes('tail'));
  try
    Assert.AreEqual<Integer>(0, CapDuringFeed.Count,
      'Sanity: Feed alone keeps the partial buffered');
  finally
    CapDuringFeed.Free;
  end;

  CapDuringFlush := TLineCapture.Create;
  try
    S.Flush(CapDuringFlush.OnLine);
    Assert.AreEqual<Integer>(1, CapDuringFlush.Count);
    Assert.AreEqual('tail', CapDuringFlush.Item(0));
  finally
    CapDuringFlush.Free;
  end;
end;

procedure TTestLineSplitterFlush.TestFlushStripsTrailingCR;
var
  S: TLineSplitter;
  CapFeed, CapFlush: TLineCapture;
begin
  S := Default(TLineSplitter);
  CapFeed := FeedAndCapture(S, StrToBytes('hello'#13));
  try
    Assert.AreEqual<Integer>(0, CapFeed.Count);
  finally
    CapFeed.Free;
  end;
  CapFlush := TLineCapture.Create;
  try
    S.Flush(CapFlush.OnLine);
    Assert.AreEqual<Integer>(1, CapFlush.Count);
    Assert.AreEqual('hello', CapFlush.Item(0),
      'Flushed tail must strip a trailing CR just like Feed strips it before LF');
  finally
    CapFlush.Free;
  end;
end;

procedure TTestLineSplitterFlush.TestFlushOnEmptyPartialDoesNothing;
var
  S: TLineSplitter;
  Cap: TLineCapture;
begin
  S := Default(TLineSplitter);
  Cap := TLineCapture.Create;
  try
    S.Flush(Cap.OnLine);
    Assert.AreEqual<Integer>(0, Cap.Count);
  finally
    Cap.Free;
  end;
end;

procedure TTestLineSplitterFlush.TestFlushClearsPartial;
var
  S: TLineSplitter;
  CapFeed, CapFlush1, CapFlush2: TLineCapture;
begin
  S := Default(TLineSplitter);
  CapFeed := FeedAndCapture(S, StrToBytes('first'));
  try
    Assert.AreEqual<Integer>(0, CapFeed.Count);
  finally
    CapFeed.Free;
  end;
  CapFlush1 := TLineCapture.Create;
  try
    S.Flush(CapFlush1.OnLine);
    Assert.AreEqual<Integer>(1, CapFlush1.Count);
  finally
    CapFlush1.Free;
  end;
  CapFlush2 := TLineCapture.Create;
  try
    {A second Flush must not re-emit the same tail. Partial was
     cleared by the first Flush.}
    S.Flush(CapFlush2.OnLine);
    Assert.AreEqual<Integer>(0, CapFlush2.Count);
  finally
    CapFlush2.Free;
  end;
end;

end.
