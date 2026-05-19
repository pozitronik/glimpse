{In-memory INI document. Preserves comments, blanks, and section order
 across read-modify-write. No file I/O; no encoding logic. Duplicate
 sections and keys are dropped on parse (first wins) with a debug log
 entry. Lenient ReadBool accepts True/False/Yes/No/On/Off/0/1.}
unit uIniDocument;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TIniLineKind = (ilkSection, ilkKeyValue, ilkComment, ilkBlank);

  TIniLine = record
    Kind: TIniLineKind;
    SectionName: string;
    Key: string;
    Value: string;
    {Verbatim line text for ilkComment/ilkBlank; unused for section/key
     which are reconstructed on save.}
    RawText: string;
  end;

  TIniDocument = class
  strict private
    FLines: TList<TIniLine>;
    FDirty: Boolean;

    function FindSectionHeaderIndex(const ASection: string): Integer;
    function FindKeyIndex(const ASection, AKey: string): Integer;
    function FindSectionEndIndex(const ASection: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure ParseFromText(const AText: string);
    function RenderToText: string;

    function ReadString(const ASection, AKey, ADefault: string): string;
    function ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
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
    procedure Clear;

    property Dirty: Boolean read FDirty;
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
          {Sentinel CurSection so keys inside this duplicate section are
           also ignored — no real section can equal #1+name.}
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
        {Preserve malformed lines as comments so round-trip stays intact.}
        Line.Kind := ilkComment;
        Line.RawText := Raw;
        FLines.Add(Line);
        Continue;
      end;
      Key := Trim(Copy(Raw, 1, EqPos - 1));
      Value := Copy(Raw, EqPos + 1, MaxInt);
      {Match TIniFile: trim leading, preserve trailing whitespace.}
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
    {Blank line before new header for visual separation, only when file
     already has content.}
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
