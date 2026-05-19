{Parses the user-editable status-bar template string into one token per
 panel. Whitespace and any other characters between tokens are silently
 ignored. Unknown identifiers parse into tkUnknown tokens that carry
 their raw source text so the renderer paints the typo back instead of
 silently dropping it. A fully-uppercase identifier (e.g. %VIEW_MODE%)
 sets Casing := tcUpper.}
unit StatusBarTemplate;

interface

uses
  StatusBarTokens;

type
  TStatusBarTokenCase = (tcAsIs, tcUpper);

  {Prefixed sba* to avoid clashing with VCL's TAlignment.taLeftJustify;
   the renderer maps these onto Vcl.Classes.TAlignment.}
  TStatusBarTokenAlign = (sbaLeft, sbaRight, sbaCenter);

  TStatusBarTokenAttr = record
    Name: string;   {lowercased at parse time, so callers compare directly}
    Value: string;  {preserved as written; semantics belong to the consumer}
  end;

  TStatusBarToken = record
    Kind: TStatusBarTokenKind;
    Casing: TStatusBarTokenCase;
    {Original "%...%" source span. Painted by the renderer when
     Kind = tkUnknown so the user can spot template typos.}
    RawText: string;
    Attributes: TArray<TStatusBarTokenAttr>;
    function AttrValue(const AName: string; const ADefault: string = ''): string;
    function HasAttr(const AName: string): Boolean;
    {Returns True with the parsed positive integer when an explicit width
     is set; False for missing, 'auto', or unparseable values.}
    function TryGetWidth(out AWidth: Integer): Boolean;
    {Defaults to sbaLeft for missing or unrecognised values.}
    function GetAlignment: TStatusBarTokenAlign;
  end;

  TStatusBarTokenArray = TArray<TStatusBarToken>;

{Never raises: malformed fragments (unclosed '%', '%' with no identifier,
 '%%') become tkUnknown carrying their raw text so the user sees the
 broken fragment instead of losing it.}
function ParseStatusBarTemplate(const ATemplate: string): TStatusBarTokenArray;

implementation

uses
  System.SysUtils, System.Character;

{TStatusBarToken}

function TStatusBarToken.AttrValue(const AName: string;
  const ADefault: string): string;
var
  I: Integer;
begin
  for I := 0 to High(Attributes) do
    if SameText(Attributes[I].Name, AName) then
      Exit(Attributes[I].Value);
  Result := ADefault;
end;

function TStatusBarToken.HasAttr(const AName: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Attributes) do
    if SameText(Attributes[I].Name, AName) then
      Exit(True);
  Result := False;
end;

function TStatusBarToken.GetAlignment: TStatusBarTokenAlign;
var
  V: string;
begin
  V := AttrValue(ATTR_ALIGN, '');
  if SameText(V, ATTR_ALIGN_RIGHT) then
    Result := sbaRight
  else if SameText(V, ATTR_ALIGN_CENTER) then
    Result := sbaCenter
  else
    Result := sbaLeft;
end;

function TStatusBarToken.TryGetWidth(out AWidth: Integer): Boolean;
var
  V: string;
  N: Integer;
begin
  Result := False;
  AWidth := 0;
  V := AttrValue(ATTR_WIDTH, '');
  if (V = '') or SameText(V, ATTR_WIDTH_AUTO) then
    Exit;
  if not TryStrToInt(V, N) then
    Exit;
  if N <= 0 then
    Exit;
  AWidth := N;
  Result := True;
end;

{Parser}

function IsIdentStart(C: Char): Boolean;
begin
  Result := C.IsLetter or (C = '_');
end;

function IsIdentCont(C: Char): Boolean;
begin
  Result := C.IsLetterOrDigit or (C = '_');
end;

function IsAllUpper(const S: string): Boolean;
var
  I: Integer;
  HasLetter: Boolean;
begin
  HasLetter := False;
  for I := 1 to Length(S) do
    if S[I].IsLetter then
    begin
      HasLetter := True;
      if S[I] <> S[I].ToUpper then
        Exit(False);
    end;
  Result := HasLetter;
end;

function ParseStatusBarTemplate(const ATemplate: string): TStatusBarTokenArray;
var
  Pos, Len, IdentStart, AttrNameStart, AttrValueStart, RawStart, ScanPos: Integer;
  Tok: TStatusBarToken;
  Ident: string;
  Attr: TStatusBarTokenAttr;
  Found: Boolean;
begin
  Result := nil;
  Len := Length(ATemplate);
  Pos := 1;
  while Pos <= Len do
  begin
    if ATemplate[Pos] <> '%' then
    begin
      Inc(Pos);
      Continue;
    end;

    RawStart := Pos;
    Inc(Pos); {past opening '%'}

    if (Pos > Len) or (not IsIdentStart(ATemplate[Pos])) then
    begin
      {Empty identifier ('%%', '% '...) or trailing '%'. Scan to the
       next '%' (inclusive) and emit the whole span as tkUnknown so the
       user sees the broken fragment.}
      Found := False;
      ScanPos := Pos;
      while ScanPos <= Len do
      begin
        if ATemplate[ScanPos] = '%' then
        begin
          Found := True;
          Break;
        end;
        Inc(ScanPos);
      end;
      Tok := Default(TStatusBarToken);
      Tok.Kind := tkUnknown;
      Tok.Casing := tcAsIs;
      if Found then
      begin
        Tok.RawText := Copy(ATemplate, RawStart, ScanPos - RawStart + 1);
        Pos := ScanPos + 1;
      end
      else
      begin
        Tok.RawText := Copy(ATemplate, RawStart, Len - RawStart + 1);
        Pos := Len + 1;
      end;
      Result := Result + [Tok];
      Continue;
    end;

    IdentStart := Pos;
    while (Pos <= Len) and IsIdentCont(ATemplate[Pos]) do
      Inc(Pos);
    Ident := Copy(ATemplate, IdentStart, Pos - IdentStart);

    Tok := Default(TStatusBarToken);
    if not StatusBarTokenKindByName(Ident, Tok.Kind) then
      Tok.Kind := tkUnknown;
    if IsAllUpper(Ident) then
      Tok.Casing := tcUpper
    else
      Tok.Casing := tcAsIs;

    while Pos <= Len do
    begin
      while (Pos <= Len) and (ATemplate[Pos] <> '%') and ATemplate[Pos].IsWhiteSpace do
        Inc(Pos);
      if (Pos > Len) or (ATemplate[Pos] = '%') then
        Break;
      if not IsIdentStart(ATemplate[Pos]) then
      begin
        {Junk in attribute position; advance one char to avoid spinning.}
        Inc(Pos);
        Continue;
      end;
      AttrNameStart := Pos;
      while (Pos <= Len) and IsIdentCont(ATemplate[Pos]) do
        Inc(Pos);
      Attr.Name := LowerCase(Copy(ATemplate, AttrNameStart, Pos - AttrNameStart));
      Attr.Value := '';
      if (Pos <= Len) and (ATemplate[Pos] = '=') then
      begin
        Inc(Pos);
        AttrValueStart := Pos;
        while (Pos <= Len) and (ATemplate[Pos] <> '%') and (not ATemplate[Pos].IsWhiteSpace) do
          Inc(Pos);
        Attr.Value := Copy(ATemplate, AttrValueStart, Pos - AttrValueStart);
      end;
      Tok.Attributes := Tok.Attributes + [Attr];
    end;

    if (Pos <= Len) and (ATemplate[Pos] = '%') then
    begin
      Tok.RawText := Copy(ATemplate, RawStart, Pos - RawStart + 1);
      Inc(Pos);
    end
    else
    begin
      {Unclosed '%name...': degrade to tkUnknown so the user notices the
       missing closing '%' instead of getting a panel-less token.}
      Tok.Kind := tkUnknown;
      Tok.Attributes := nil;
      Tok.RawText := Copy(ATemplate, RawStart, Len - RawStart + 1);
      Pos := Len + 1;
    end;

    Result := Result + [Tok];
  end;
end;

end.
