{Parser for the user-editable status-bar template string. Each panel of
 the live status bar corresponds to one '%name%' or '%name attr=value%'
 token. Whitespace and any other characters between tokens are silently
 ignored: the model is "one token per cell", not "tokens interleaved
 with literal text".

 Unknown identifiers parse into tkUnknown tokens that carry their raw
 source text, so the renderer can paint the typo back to the user
 instead of silently dropping it.

 Casing rule: a token whose identifier is fully uppercase (e.g.
 %VIEW_MODE%) sets the Casing field to tcUpper, instructing the renderer
 to uppercase the produced text. Mixed-case or lowercase identifiers
 leave the value untouched. Case at the identifier level is otherwise
 ignored — the kind lookup is case-insensitive.

 Pure: no VCL, no settings, no global state. TestStatusBarTemplate
 exercises every branch end-to-end.}
unit uStatusBarTemplate;

interface

uses
  uStatusBarTokens;

type
  {Casing flag derived from the token identifier:
     tcAsIs  - identifier was lower- or mixed-case; render value verbatim
     tcUpper - identifier was fully uppercase; renderer uppercases value}
  TStatusBarTokenCase = (tcAsIs, tcUpper);

  {Panel text alignment derived from the optional align=... attribute.
   Prefixed sba* to avoid clashing with VCL's TAlignment.taLeftJustify
   et al; the renderer maps these onto Vcl.Classes.TAlignment.}
  TStatusBarTokenAlign = (sbaLeft, sbaRight, sbaCenter);

  TStatusBarTokenAttr = record
    Name: string;   {lowercased at parse time, so callers compare directly}
    Value: string;  {preserved as written; semantics belong to the consumer}
  end;

  TStatusBarToken = record
    Kind: TStatusBarTokenKind;
    Casing: TStatusBarTokenCase;
    {Original "%...%" source span, captured verbatim. Painted by the
     renderer when Kind = tkUnknown so the user can spot typos in their
     template; otherwise informational.}
    RawText: string;
    Attributes: TArray<TStatusBarTokenAttr>;
    {Attribute lookup is case-insensitive on Name. Returns ADefault when
     missing.}
    function AttrValue(const AName: string; const ADefault: string = ''): string;
    {True iff AName is present (case-insensitive).}
    function HasAttr(const AName: string): Boolean;
    {Convenience around AttrValue('width'): returns True with the parsed
     positive integer when an explicit pixel width is set; returns False
     for missing, 'auto', or unparseable values (caller falls back to
     auto-measurement).}
    function TryGetWidth(out AWidth: Integer): Boolean;
    {Reads the optional align=left|right|center attribute. Defaults to
     sbaLeft for missing or unrecognised values (silent fallback rather
     than error — keeps the bar usable for a typo).}
    function GetAlignment: TStatusBarTokenAlign;
  end;

  TStatusBarTokenArray = TArray<TStatusBarToken>;

{Parses ATemplate into an array of tokens. Never raises: malformed
 fragments (unclosed '%', '%' followed by no identifier, '%%') become
 tkUnknown carrying their raw text. Anything outside of '%...%' spans
 (including whitespace between tokens) is dropped silently.}
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
      {Anything outside a '%...%' span is silently skipped.}
      Inc(Pos);
      Continue;
    end;

    RawStart := Pos;
    Inc(Pos); {past opening '%'}

    if (Pos > Len) or (not IsIdentStart(ATemplate[Pos])) then
    begin
      {Empty identifier ('%%' or '% '...) or trailing '%'. Scan to the
       next '%' (inclusive) and emit the whole span as tkUnknown so the
       user sees the broken fragment instead of losing it silently.}
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

    {Read zero or more name=value attributes until the closing '%'.}
    while Pos <= Len do
    begin
      while (Pos <= Len) and (ATemplate[Pos] <> '%') and ATemplate[Pos].IsWhiteSpace do
        Inc(Pos);
      if (Pos > Len) or (ATemplate[Pos] = '%') then
        Break;
      if not IsIdentStart(ATemplate[Pos]) then
      begin
        {Junk in attribute position; advance one char to avoid spinning
         and keep scanning for either an attribute or the closing '%'.}
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
       missing closing '%' instead of getting a token with no panel.}
      Tok.Kind := tkUnknown;
      Tok.Attributes := nil;
      Tok.RawText := Copy(ATemplate, RawStart, Len - RawStart + 1);
      Pos := Len + 1;
    end;

    Result := Result + [Tok];
  end;
end;

end.
