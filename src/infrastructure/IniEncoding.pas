{Encoding detection for INI files.

 Read: BOM (UTF-8/UTF-16 LE/UTF-16 BE) wins. Without BOM, try strict
 UTF-8; fall back to ANSI on failure — modern Notepad saves UTF-8
 without BOM so the strict probe must catch that before ANSI mangles
 non-ASCII bytes.

 Write: UTF-8 without BOM; the loader re-identifies on the next read.}
unit IniEncoding;

interface

uses
  System.SysUtils;

function DecodeIniBytes(const ABytes: TBytes): string;

function EncodeIniBytes(const AText: string): TBytes;

{Byte-structure check used instead of TEncoding.UTF8 because the RTL
 silently substitutes replacement chars on invalid input.}
function IsValidUTF8(const ABytes: TBytes): Boolean;

{False with empty AResult signals the caller to try a different encoding.}
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
