{Encoding-aware INI file handler.
 TIniFile in the RTL routes through Win32 GetPrivateProfileString, which
 only understands UTF-16 LE with BOM or ANSI; UTF-8 (with or without BOM)
 is read as ANSI and mojibakes any non-ASCII content. Modern Notepad on
 Win11 defaults to UTF-8, so the gap is real.
 This unit reads UTF-8 / UTF-16 LE / UTF-16 BE (BOM-detected) and falls
 back to ANSI on no-BOM files that fail strict UTF-8 decoding. Writes
 emit UTF-8 without BOM (cleaner output; the loader still detects
 plain UTF-8 via the strict-decode heuristic) and CRLF line endings.
 The in-memory model preserves comments, blank lines, and original
 ordering across read-modify-write so hand-edited files survive Save
 unchanged. Lenient ReadBool accepts True/False/Yes/No/On/Off/0/1.
 Duplicate sections and duplicate keys: first occurrence wins; subsequent
 ones are reported via uDebugLog when logging is enabled.}
unit uUnicodeIniFile;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TIniLineKind = (ilkSection, ilkKeyValue, ilkComment, ilkBlank);

  TIniLine = record
    Kind: TIniLineKind;
    {For ilkSection: the section name (no brackets).
     For ilkKeyValue: the section the key belongs to (case preserved
     as the section header was originally written).}
    SectionName: string;
    Key: string;
    Value: string;
    {For ilkComment / ilkBlank: the verbatim line text (without the
     trailing line terminator). For ilkSection / ilkKeyValue, unused
     because the line is reconstructed from the parsed fields on save.}
    RawText: string;
  end;

  TUnicodeIniFile = class
  strict private
    FFileName: string;
    FLines: TList<TIniLine>;
    {Set by every mutating method; cleared by UpdateFile. Drives the
     auto-flush-on-destroy behaviour so callers used to TIniFile's
     "writes hit the disk" model do not lose data when they Free
     without calling UpdateFile explicitly.}
    FDirty: Boolean;

    procedure LoadFromDisk;
    procedure ParseLines(const AText: string);
    function FindSectionHeaderIndex(const ASection: string): Integer;
    function FindKeyIndex(const ASection, AKey: string): Integer;
    function FindSectionEndIndex(const ASection: string): Integer;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;

    function ReadString(const ASection, AKey, ADefault: string): string;
    function ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
    {Lenient ReadBool: True/Yes/On/1 → True; False/No/Off/0 → False;
     anything else → ADefault. Case-insensitive.}
    function ReadBool(const ASection, AKey: string; ADefault: Boolean): Boolean;

    procedure WriteString(const ASection, AKey, AValue: string);
    procedure WriteInteger(const ASection, AKey: string; AValue: Integer);
    procedure WriteBool(const ASection, AKey: string; AValue: Boolean);

    procedure ReadSections(AStrings: TStrings);
    procedure ReadSection(const ASection: string; AStrings: TStrings);
    function ValueExists(const ASection, AKey: string): Boolean;
    function SectionExists(const ASection: string): Boolean;
    procedure DeleteKey(const ASection, AKey: string);
    procedure EraseSection(const ASection: string);
    {Discards every line, leaving an empty in-memory document. Used
     when callers want to fully rewrite the file from scratch.}
    procedure Clear;
    {Persists the in-memory state to FFileName as UTF-8 without BOM
     and CRLF line endings. Silent no-op when FFileName is empty
     (mirrors the TIniFile sentinel).}
    procedure UpdateFile;

    property FileName: string read FFileName;
  end;

{Decodes ABytes into a Delphi string.
 Detection priority: UTF-8 BOM, UTF-16 LE BOM, UTF-16 BE BOM. With no
 BOM, attempts strict UTF-8 first; if any byte sequence is invalid,
 falls back to ANSI (system codepage). Pure function; exposed for
 testing and for callers that want the same heuristic without a full
 INI parse.}
function DecodeIniBytes(const ABytes: TBytes): string;

implementation

uses
  System.IOUtils,
  Winapi.Windows,
  uDebugLog;

const
  CIniLog = 'IniFile';

procedure IniLog(const AMsg: string);
begin
  DebugLog(CIniLog, AMsg);
end;

{Validates the UTF-8 byte structure: every byte either is ASCII (0xxxxxxx),
 starts a 2/3/4-byte sequence (110xxxxx / 1110xxxx / 11110xxx), or is a
 continuation (10xxxxxx) in the right position. Anything else means the
 input is not strict UTF-8.
 Used instead of TEncoding+round-trip because TEncoding.UTF8 silently
 substitutes replacement chars on invalid input (no raise, no signal),
 and the re-encode round-trip approach proved unreliable across Delphi
 RTL versions in our testing.}
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

constructor TUnicodeIniFile.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FLines := TList<TIniLine>.Create;
  if (FFileName <> '') and TFile.Exists(FFileName) then
    LoadFromDisk;
end;

destructor TUnicodeIniFile.Destroy;
begin
  {Auto-flush pending writes so a "create / write / free" caller does
   not lose data. Mirrors TIniFile's expected behaviour.}
  if FDirty then
    try
      UpdateFile;
    except
      {Swallow to avoid throwing during destruction; callers that need
       guaranteed flush should call UpdateFile explicitly and handle
       the exception.}
    end;
  FLines.Free;
  inherited;
end;

procedure TUnicodeIniFile.LoadFromDisk;
var
  Bytes: TBytes;
  Text: string;
begin
  Bytes := TFile.ReadAllBytes(FFileName);
  Text := DecodeIniBytes(Bytes);
  ParseLines(Text);
end;

{Splits AText on any line terminator, classifies each line into one of
 the four kinds, and appends to FLines. Tracks the current section so
 ilkKeyValue lines carry their owning section name. Duplicate sections
 (case-insensitive name match against an earlier section header) and
 duplicate keys (within the same section) are dropped with a debug log
 entry — first occurrence wins.}
procedure TUnicodeIniFile.ParseLines(const AText: string);
var
  Lines: TStringList;
  I, EqPos: Integer;
  Raw, Trimmed, SectionName, Key, Value: string;
  CurSection: string;
  Line: TIniLine;
  KnownSections: TDictionary<string, Boolean>;
begin
  CurSection := '';
  Lines := TStringList.Create;
  KnownSections := TDictionary<string, Boolean>.Create;
  try
    {TStringList.Text splits on CR / LF / CRLF uniformly.}
    Lines.Text := AText;
    for I := 0 to Lines.Count - 1 do
    begin
      Raw := Lines[I];
      Trimmed := Trim(Raw);
      Line := Default(TIniLine);
      if Trimmed = '' then
      begin
        Line.Kind := ilkBlank;
        Line.RawText := Raw;
        FLines.Add(Line);
        Continue;
      end;
      if (Trimmed[1] = ';') then
      begin
        Line.Kind := ilkComment;
        Line.RawText := Raw;
        FLines.Add(Line);
        Continue;
      end;
      if (Trimmed[1] = '[') and (Trimmed[Length(Trimmed)] = ']') then
      begin
        SectionName := Trim(Copy(Trimmed, 2, Length(Trimmed) - 2));
        if KnownSections.ContainsKey(AnsiLowerCase(SectionName)) then
        begin
          IniLog(Format('Duplicate section "%s" ignored', [SectionName]));
          {Subsequent keys inside this duplicate section are also ignored
           by routing CurSection to a sentinel that no real section can
           equal, so FindKeyIndex never matches them.}
          CurSection := #1 + SectionName;
          Continue;
        end;
        KnownSections.Add(AnsiLowerCase(SectionName), True);
        CurSection := SectionName;
        Line.Kind := ilkSection;
        Line.SectionName := SectionName;
        FLines.Add(Line);
        Continue;
      end;
      EqPos := Pos('=', Raw);
      if EqPos < 2 then
      begin
        {No '=' or '=' at column 1: not a key. Preserve as a comment so
         round-trip leaves the line intact.}
        Line.Kind := ilkComment;
        Line.RawText := Raw;
        FLines.Add(Line);
        Continue;
      end;
      Key := Trim(Copy(Raw, 1, EqPos - 1));
      Value := Copy(Raw, EqPos + 1, MaxInt);
      {Trim leading whitespace from value (TIniFile does the same) but
       preserve trailing whitespace as data — TIniFile preserves it too.}
      while (Length(Value) > 0) and CharInSet(Value[1], [' ', #9]) do
        Delete(Value, 1, 1);
      if (CurSection <> '') and (CurSection[1] <> #1) and (FindKeyIndex(CurSection, Key) >= 0) then
      begin
        IniLog(Format('Duplicate key "%s" in section "%s" ignored', [Key, CurSection]));
        Continue;
      end;
      if (CurSection = '') or (CurSection[1] = #1) then
        Continue;
      Line.Kind := ilkKeyValue;
      Line.SectionName := CurSection;
      Line.Key := Key;
      Line.Value := Value;
      FLines.Add(Line);
    end;
  finally
    KnownSections.Free;
    Lines.Free;
  end;
end;

function TUnicodeIniFile.FindSectionHeaderIndex(const ASection: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FLines.Count - 1 do
    if (FLines[I].Kind = ilkSection) and SameText(FLines[I].SectionName, ASection) then
      Exit(I);
  Result := -1;
end;

function TUnicodeIniFile.FindKeyIndex(const ASection, AKey: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FLines.Count - 1 do
    if (FLines[I].Kind = ilkKeyValue) and SameText(FLines[I].SectionName, ASection) and SameText(FLines[I].Key, AKey) then
      Exit(I);
  Result := -1;
end;

{Returns the index of the LAST line belonging to ASection (header or
 key). Used by WriteString to know where to insert a new key. Returns
 -1 when the section does not exist.}
function TUnicodeIniFile.FindSectionEndIndex(const ASection: string): Integer;
var
  I, Header: Integer;
begin
  Header := FindSectionHeaderIndex(ASection);
  if Header < 0 then
    Exit(-1);
  Result := Header;
  for I := Header + 1 to FLines.Count - 1 do
  begin
    if FLines[I].Kind = ilkSection then
      Break;
    if (FLines[I].Kind = ilkKeyValue) and SameText(FLines[I].SectionName, ASection) then
      Result := I;
  end;
end;

function TUnicodeIniFile.ReadString(const ASection, AKey, ADefault: string): string;
var
  Idx: Integer;
begin
  Idx := FindKeyIndex(ASection, AKey);
  if Idx < 0 then
    Result := ADefault
  else
    Result := FLines[Idx].Value;
end;

function TUnicodeIniFile.ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
var
  Raw: string;
  Parsed: Integer;
begin
  Raw := ReadString(ASection, AKey, '');
  if (Raw <> '') and TryStrToInt(Raw, Parsed) then
    Result := Parsed
  else
    Result := ADefault;
end;

function TUnicodeIniFile.ReadBool(const ASection, AKey: string; ADefault: Boolean): Boolean;
var
  Raw: string;
begin
  Raw := AnsiLowerCase(Trim(ReadString(ASection, AKey, '')));
  if Raw = '' then
    Exit(ADefault);
  if (Raw = 'true') or (Raw = 'yes') or (Raw = 'on') or (Raw = '1') then
    Exit(True);
  if (Raw = 'false') or (Raw = 'no') or (Raw = 'off') or (Raw = '0') then
    Exit(False);
  Result := ADefault;
end;

procedure TUnicodeIniFile.WriteString(const ASection, AKey, AValue: string);
var
  KeyIdx, EndIdx: Integer;
  Line: TIniLine;
  PrependBlank: Boolean;
begin
  FDirty := True;
  KeyIdx := FindKeyIndex(ASection, AKey);
  if KeyIdx >= 0 then
  begin
    Line := FLines[KeyIdx];
    Line.Value := AValue;
    FLines[KeyIdx] := Line;
    Exit;
  end;

  EndIdx := FindSectionEndIndex(ASection);
  if EndIdx < 0 then
  begin
    {Section does not exist; append a new section header followed by
     the key. Insert a blank line before the new header for visual
     separation, but only when the file already has content.}
    PrependBlank := FLines.Count > 0;
    if PrependBlank then
    begin
      Line := Default(TIniLine);
      Line.Kind := ilkBlank;
      FLines.Add(Line);
    end;
    Line := Default(TIniLine);
    Line.Kind := ilkSection;
    Line.SectionName := ASection;
    FLines.Add(Line);
    Line := Default(TIniLine);
    Line.Kind := ilkKeyValue;
    Line.SectionName := ASection;
    Line.Key := AKey;
    Line.Value := AValue;
    FLines.Add(Line);
    Exit;
  end;

  {Section exists, key does not: insert the new key right after the
   last existing line of the section.}
  Line := Default(TIniLine);
  Line.Kind := ilkKeyValue;
  Line.SectionName := ASection;
  Line.Key := AKey;
  Line.Value := AValue;
  FLines.Insert(EndIdx + 1, Line);
end;

procedure TUnicodeIniFile.WriteInteger(const ASection, AKey: string; AValue: Integer);
begin
  WriteString(ASection, AKey, IntToStr(AValue));
end;

procedure TUnicodeIniFile.WriteBool(const ASection, AKey: string; AValue: Boolean);
begin
  if AValue then
    WriteString(ASection, AKey, '1')
  else
    WriteString(ASection, AKey, '0');
end;

procedure TUnicodeIniFile.ReadSections(AStrings: TStrings);
var
  I: Integer;
begin
  AStrings.Clear;
  for I := 0 to FLines.Count - 1 do
    if FLines[I].Kind = ilkSection then
      AStrings.Add(FLines[I].SectionName);
end;

procedure TUnicodeIniFile.ReadSection(const ASection: string; AStrings: TStrings);
var
  I: Integer;
begin
  AStrings.Clear;
  for I := 0 to FLines.Count - 1 do
    if (FLines[I].Kind = ilkKeyValue) and SameText(FLines[I].SectionName, ASection) then
      AStrings.Add(FLines[I].Key);
end;

function TUnicodeIniFile.ValueExists(const ASection, AKey: string): Boolean;
begin
  Result := FindKeyIndex(ASection, AKey) >= 0;
end;

function TUnicodeIniFile.SectionExists(const ASection: string): Boolean;
begin
  Result := FindSectionHeaderIndex(ASection) >= 0;
end;

procedure TUnicodeIniFile.DeleteKey(const ASection, AKey: string);
var
  Idx: Integer;
begin
  Idx := FindKeyIndex(ASection, AKey);
  if Idx >= 0 then
  begin
    FLines.Delete(Idx);
    FDirty := True;
  end;
end;

procedure TUnicodeIniFile.EraseSection(const ASection: string);
var
  Header, I: Integer;
begin
  Header := FindSectionHeaderIndex(ASection);
  if Header < 0 then
    Exit;
  FDirty := True;
  {Walk forward from the header collecting every line that belongs to
   this section (header itself + key-value lines). Remove them in
   reverse so indices stay valid during deletion.}
  I := Header + 1;
  while I < FLines.Count do
  begin
    if FLines[I].Kind = ilkSection then
      Break;
    if (FLines[I].Kind = ilkKeyValue) and SameText(FLines[I].SectionName, ASection) then
    begin
      FLines.Delete(I);
      Continue;
    end;
    Inc(I);
  end;
  FLines.Delete(Header);
end;

procedure TUnicodeIniFile.Clear;
begin
  FLines.Clear;
  FDirty := True;
end;

procedure TUnicodeIniFile.UpdateFile;
var
  Output: TStringBuilder;
  I: Integer;
  Line: TIniLine;
  Bytes: TBytes;
begin
  if FFileName = '' then
    Exit;
  Output := TStringBuilder.Create;
  try
    for I := 0 to FLines.Count - 1 do
    begin
      Line := FLines[I];
      case Line.Kind of
        ilkSection:
          Output.Append('[').Append(Line.SectionName).Append(']');
        ilkKeyValue:
          Output.Append(Line.Key).Append('=').Append(Line.Value);
        ilkComment, ilkBlank:
          Output.Append(Line.RawText);
      end;
      Output.Append(#13#10);
    end;
    {UTF-8 without BOM. Cleaner output; the loader's no-BOM heuristic
     re-identifies the file as UTF-8 on the next read because every byte
     sequence is valid UTF-8 by construction.}
    Bytes := TEncoding.UTF8.GetBytes(Output.ToString);
    TFile.WriteAllBytes(FFileName, Bytes);
    FDirty := False;
  finally
    Output.Free;
  end;
end;

end.
