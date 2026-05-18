{Rolling line accumulator for streaming byte input.

 Pipe readers deliver bytes in arbitrary chunks — a single read can
 contain half a line, multiple lines, or a line plus the beginning of
 the next. TLineSplitter buffers the rolling partial across reads,
 dispatches each completed line via a callback, and lets the caller
 flush the trailing tail when the stream ends.

 Was previously a private record inside uRunProcess. Hoisted to its
 own infrastructure unit so:

 1. The byte-to-line decoder lives independently of process spawning
    (uRunProcess owns the pipe + the process; this unit owns the
    parsing).

 2. The Feed / Flush contracts are testable directly rather than only
    via end-to-end RunProcess tests.

 Line termination contract:
   - Lines end at #10 (LF).
   - A trailing #13 (CR) before the #10 is stripped — handles both
     Unix and CRLF streams.
   - Empty lines (LF immediately after the previous LF, or a flushed
     tail of zero bytes after CR stripping) are swallowed silently,
     since callers do not care about progress-noise blank lines.

 Decoding: bytes are interpreted as UTF-8 with replacement; invalid
 sequences do not raise. Pipe streams can carry intermittent garbage
 (Win32 console codepage drift, stderr from sub-tools); the
 replacement decoder keeps the splitter alive in that case.}
unit uLineSplitter;

interface

uses
  System.SysUtils;

type
  TLineSplitter = record
    Partial: TBytes;
    {Appends ABytesRead bytes from ABuffer to the rolling partial and
     dispatches every newly completed line via AOnLine. Bytes after the
     last #10 are kept as the new partial for the next Feed.}
    procedure Feed(const ABuffer; ABytesRead: Integer; const AOnLine: TProc<string>);
    {Dispatches whatever bytes are buffered in Partial as one final
     line (with the CR-trim rule). Used at end-of-stream so the tail
     without a terminating #10 still reaches the callback. Clears
     Partial.}
    procedure Flush(const AOnLine: TProc<string>);
  end;

implementation

{Decodes a line as UTF-8 with replacement so embedded invalid sequences
 do not raise. Used by both Feed (per dispatched line) and Flush
 (for the tail). Kept implementation-private; callers do not need it.}
function DecodeLine(const ABytes: TBytes; AStart, ALength: Integer): string;
var
  Enc: TEncoding;
begin
  if ALength <= 0 then
    Exit('');
  Enc := TUTF8Encoding.Create(CP_UTF8, 0, 0);
  try
    Result := Enc.GetString(ABytes, AStart, ALength);
  finally
    Enc.Free;
  end;
end;

procedure TLineSplitter.Feed(const ABuffer; ABytesRead: Integer; const AOnLine: TProc<string>);
var
  Combined: TBytes;
  PrevLen, I, LineStart, LineLen: Integer;
begin
  if ABytesRead <= 0 then
    Exit;
  PrevLen := Length(Partial);
  SetLength(Combined, PrevLen + ABytesRead);
  if PrevLen > 0 then
    Move(Partial[0], Combined[0], PrevLen);
  Move(ABuffer, Combined[PrevLen], ABytesRead);
  Partial := nil;

  LineStart := 0;
  for I := 0 to High(Combined) do
  begin
    if Combined[I] = $0A then
    begin
      LineLen := I - LineStart;
      {Strip the trailing #13 if present so callers see a clean line.}
      if (LineLen > 0) and (Combined[I - 1] = $0D) then
        Dec(LineLen);
      if LineLen > 0 then
        AOnLine(DecodeLine(Combined, LineStart, LineLen));
      LineStart := I + 1;
    end;
  end;

  {Anything past the last #10 is the new partial line; carries forward
   to the next Feed.}
  if LineStart <= High(Combined) then
  begin
    SetLength(Partial, Length(Combined) - LineStart);
    Move(Combined[LineStart], Partial[0], Length(Partial));
  end;
end;

procedure TLineSplitter.Flush(const AOnLine: TProc<string>);
var
  TailLen: Integer;
begin
  TailLen := Length(Partial);
  if (TailLen > 0) and (Partial[TailLen - 1] = $0D) then
    Dec(TailLen);
  if TailLen > 0 then
    AOnLine(DecodeLine(Partial, 0, TailLen));
  Partial := nil;
end;

end.
