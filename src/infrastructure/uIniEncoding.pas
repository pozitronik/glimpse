{Encoding-detection and byte-string conversion for INI files.

 Lifted out of uUnicodeIniFile (M18 split) so the pure
 bytes-and-strings layer lives independently of the line-list parser
 and the file-I/O facade. Every function here is a pure projection
 over byte buffers; no globals, no I/O.

 Detection contract (preserved verbatim from the pre-split inline
 implementation):

 - UTF-8 BOM (EF BB BF) -> strip BOM, decode as UTF-8.
 - UTF-16 LE BOM (FF FE) -> strip BOM, decode as UTF-16 LE.
 - UTF-16 BE BOM (FE FF) -> strip BOM, decode as UTF-16 BE.
 - No BOM -> try strict UTF-8 (every byte sequence must form a valid
   UTF-8 codepoint); if that fails, fall back to ANSI (system
   codepage). Modern Notepad on Win11 saves "UTF-8" without BOM, so
   the strict-decode probe catches that case before the ANSI fallback
   can mangle non-ASCII content.

 Write side: EncodeIniBytes emits UTF-8 without BOM — the loader's
 no-BOM heuristic re-identifies the output as UTF-8 on the next
 read because every byte sequence is valid UTF-8 by construction.}
unit uIniEncoding;

interface

uses
  System.SysUtils;

{Decodes ABytes into a Delphi string per the BOM-then-strict-UTF-8
 heuristic documented in the unit header.}
function DecodeIniBytes(const ABytes: TBytes): string;

{Encodes AText to UTF-8 bytes (no BOM). The lossless inverse of
 DecodeIniBytes for any text the loader produced from a well-formed
 source — round-tripping a file through DecodeIniBytes -> EncodeIniBytes
 yields bytes the loader will re-identify as UTF-8.}
function EncodeIniBytes(const AText: string): TBytes;

{Validates the UTF-8 byte structure: every byte either is ASCII (0xxxxxxx),
 starts a 2/3/4-byte sequence (110xxxxx / 1110xxxx / 11110xxx), or is a
 continuation (10xxxxxx) in the right position. Anything else means the
 input is not strict UTF-8.

 Used instead of TEncoding+round-trip because TEncoding.UTF8 silently
 substitutes replacement chars on invalid input (no raise, no signal),
 and the re-encode round-trip approach proved unreliable across Delphi
 RTL versions in our testing.}
function IsValidUTF8(const ABytes: TBytes): Boolean;

{Strict UTF-8 decode: returns True with AResult populated only when
 ABytes is well-formed UTF-8. False (and an empty AResult) when any
 byte sequence is invalid — the caller then knows to try a different
 encoding (ANSI in DecodeIniBytes's case).}
function TryStrictUTF8(const ABytes: TBytes; out AResult: string): Boolean;

implementation

function IsValidUTF8(const ABytes: TBytes): Boolean;
var
  I, N, ContBytes: Integer;
  B: Byte;
begin
  I := 0;
  N := Length(ABytes);
  while I < N do
  begin
    B := ABytes[I];
    if B < $80 then
      ContBytes := 0
    else if (B and $E0) = $C0 then
      ContBytes := 1
    else if (B and $F0) = $E0 then
      ContBytes := 2
    else if (B and $F8) = $F0 then
      ContBytes := 3
    else
      Exit(False);
    Inc(I);
    while ContBytes > 0 do
    begin
      if (I >= N) or ((ABytes[I] and $C0) <> $80) then
        Exit(False);
      Inc(I);
      Dec(ContBytes);
    end;
  end;
  Result := True;
end;

function TryStrictUTF8(const ABytes: TBytes; out AResult: string): Boolean;
begin
  AResult := '';
  if not IsValidUTF8(ABytes) then
    Exit(False);
  AResult := TEncoding.UTF8.GetString(ABytes);
  Result := True;
end;

function DecodeIniBytes(const ABytes: TBytes): string;
var
  Strict: string;
  Enc: TEncoding;
begin
  Result := '';
  if Length(ABytes) = 0 then
    Exit;

  {UTF-8 BOM EF BB BF}
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    Enc := TEncoding.UTF8;
    Result := Enc.GetString(ABytes, 3, Length(ABytes) - 3);
    Exit;
  end;

  {UTF-16 LE BOM FF FE}
  if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    Enc := TEncoding.Unicode;
    Result := Enc.GetString(ABytes, 2, Length(ABytes) - 2);
    Exit;
  end;

  {UTF-16 BE BOM FE FF}
  if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    Enc := TEncoding.BigEndianUnicode;
    Result := Enc.GetString(ABytes, 2, Length(ABytes) - 2);
    Exit;
  end;

  {No BOM. Try strict UTF-8 — modern Notepad's "UTF-8" save option
   omits the BOM. If even one byte sequence is invalid, the file is
   almost certainly ANSI in the system codepage (real Cyrillic / Latin-1
   content fails strict UTF-8 with very high probability).}
  if TryStrictUTF8(ABytes, Strict) then
    Result := Strict
  else
    Result := TEncoding.ANSI.GetString(ABytes);
end;

function EncodeIniBytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

end.
