{In-memory INI document model.

 Holds the parsed line list, preserves comments / blank lines /
 original section ordering across read-modify-write, and exposes the
 ReadString / WriteString / ReadSection / EraseSection-style API
 callers expect from a settings store. No file I/O — uUnicodeIniFile
 wraps this class with the disk read/write side. No encoding logic —
 callers pass already-decoded strings to ParseFromText and consume
 the emitted text from RenderToText.

 Lifted out of uUnicodeIniFile (M18 split) so the in-memory parse +
 mutate + emit machinery is testable without touching disk, and so
 the encoding decisions (uIniEncoding) and the file-I/O facade
 (uUnicodeIniFile) each own one concern.

 Duplicate sections (case-insensitive name match against an earlier
 section header) and duplicate keys (within the same section) are
 dropped during ParseFromText with a debug-log entry — first
 occurrence wins. Lenient ReadBool accepts True/False/Yes/No/On/Off/0/1.}
unit uIniDocument;

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

  TIniDocument = class
  strict private
    FLines: TList<TIniLine>;
    {Set by every mutating method; cleared by callers via ClearDirty.
     uUnicodeIniFile reads this in its destructor's auto-flush check
     and clears it after a successful UpdateFile.}
    FDirty: Boolean;

    function FindSectionHeaderIndex(const ASection: string): Integer;
    function FindKeyIndex(const ASection, AKey: string): Integer;
    function FindSectionEndIndex(const ASection: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    {Parses AText into the line list. Splits on CR / LF / CRLF
     uniformly. Replaces any prior content via Clear.}
    procedure ParseFromText(const AText: string);
    {Emits the current line list as a CRLF-terminated string suitable
     for the file writer. Reconstructs section headers and key=value
     lines from the parsed fields; comments and blank lines pass
     through verbatim.}
    function RenderToText: string;

    function ReadString(const ASection, AKey, ADefault: string): string;
    function ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
    {Lenient ReadBool: True/Yes/On/1 -> True; False/No/Off/0 -> False;
     anything else -> ADefault. Case-insensitive.}
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
    {Discards every line, leaving an empty document.}
    procedure Clear;

    property Dirty: Boolean read FDirty;
    {Cleared by uUnicodeIniFile.UpdateFile on successful flush.}
    procedure ClearDirty;
  end;

implementation

uses
  uDebugLog;

const
  CIniLog = 'IniFile';

procedure IniLog(const AMsg: string);
begin
  DebugLog(CIniLog, AMsg);
end;

constructor TIniDocument.Create;
begin
  inherited Create;
  FLines := TList<TIniLine>.Create;
end;

destructor TIniDocument.Destroy;
begin
  FLines.Free;
  inherited;
end;

{Splits AText on any line terminator, classifies each line into one of
 the four kinds, and appends to FLines. Tracks the current section so
 ilkKeyValue lines carry their owning section name. Duplicate sections
 (case-insensitive name match against an earlier section header) and
 duplicate keys (within the same section) are dropped with a debug log
 entry — first occurrence wins.}
procedure TIniDocument.ParseFromText(const AText: string);
var
  Lines: TStringList;
  I, EqPos: Integer;
  Raw, Trimmed, SectionName, Key, Value: string;
  CurSection: string;
  Line: TIniLine;
  KnownSections: TDictionary<string, Boolean>;
begin
  FLines.Clear;
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

function TIniDocument.RenderToText: string;
var
  Output: TStringBuilder;
  I: Integer;
  Line: TIniLine;
begin
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
    Result := Output.ToString;
  finally
    Output.Free;
  end;
end;

function TIniDocument.FindSectionHeaderIndex(const ASection: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FLines.Count - 1 do
    if (FLines[I].Kind = ilkSection) and SameText(FLines[I].SectionName, ASection) then
      Exit(I);
  Result := -1;
end;

function TIniDocument.FindKeyIndex(const ASection, AKey: string): Integer;
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
function TIniDocument.FindSectionEndIndex(const ASection: string): Integer;
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

function TIniDocument.ReadString(const ASection, AKey, ADefault: string): string;
var
  Idx: Integer;
begin
  Idx := FindKeyIndex(ASection, AKey);
  if Idx < 0 then
    Result := ADefault
  else
    Result := FLines[Idx].Value;
end;

function TIniDocument.ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
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

function TIniDocument.ReadBool(const ASection, AKey: string; ADefault: Boolean): Boolean;
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

procedure TIniDocument.WriteString(const ASection, AKey, AValue: string);
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

procedure TIniDocument.WriteInteger(const ASection, AKey: string; AValue: Integer);
begin
  WriteString(ASection, AKey, IntToStr(AValue));
end;

procedure TIniDocument.WriteBool(const ASection, AKey: string; AValue: Boolean);
begin
  if AValue then
    WriteString(ASection, AKey, '1')
  else
    WriteString(ASection, AKey, '0');
end;

procedure TIniDocument.ReadSections(AStrings: TStrings);
var
  I: Integer;
begin
  AStrings.Clear;
  for I := 0 to FLines.Count - 1 do
    if FLines[I].Kind = ilkSection then
      AStrings.Add(FLines[I].SectionName);
end;

procedure TIniDocument.ReadSection(const ASection: string; AStrings: TStrings);
var
  I: Integer;
begin
  AStrings.Clear;
  for I := 0 to FLines.Count - 1 do
    if (FLines[I].Kind = ilkKeyValue) and SameText(FLines[I].SectionName, ASection) then
      AStrings.Add(FLines[I].Key);
end;

function TIniDocument.ValueExists(const ASection, AKey: string): Boolean;
begin
  Result := FindKeyIndex(ASection, AKey) >= 0;
end;

function TIniDocument.SectionExists(const ASection: string): Boolean;
begin
  Result := FindSectionHeaderIndex(ASection) >= 0;
end;

procedure TIniDocument.DeleteKey(const ASection, AKey: string);
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

procedure TIniDocument.EraseSection(const ASection: string);
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

procedure TIniDocument.Clear;
begin
  FLines.Clear;
  FDirty := True;
end;

procedure TIniDocument.ClearDirty;
begin
  FDirty := False;
end;

end.
