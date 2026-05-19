{Rolling line accumulator for streaming byte input from pipes.

 Lines end at #10 (LF); a trailing CR before LF is stripped. Empty
 lines are swallowed. Bytes are decoded as UTF-8 with replacement so
 intermittent garbage on the pipe never raises.}
unit uLineSplitter;

interface

uses
  System.SysUtils;

type
  TLineSplitter = record
    Partial: TBytes;
    procedure Feed(const ABuffer; ABytesRead: Integer; const AOnLine: TProc<string>);
    {Dispatches the buffered tail as a final line; used at end-of-stream
     so a terminator-less tail still reaches the callback.}
    procedure Flush(const AOnLine: TProc<string>);
  end;

implementation

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
      if (LineLen > 0) and (Combined[I - 1] = $0D) then
        Dec(LineLen);
      if LineLen > 0 then
        AOnLine(DecodeLine(Combined, LineStart, LineLen));
      LineStart := I + 1;
    end;
  end;

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
