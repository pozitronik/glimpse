unit TestStatusBarTemplate;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestStatusBarTemplate = class
  public
    {Empty / trivial}
    [Test]
    procedure TestEmptyTemplateProducesNoTokens;
    [Test]
    procedure TestWhitespaceOnlyProducesNoTokens;

    {Single-token cases}
    [Test]
    procedure TestSingleRecognisedToken;
    [Test]
    procedure TestSingleTokenRawTextCaptured;
    [Test]
    procedure TestUnknownIdentifierBecomesUnknownToken;
    [Test]
    procedure TestUnknownIdentifierKeepsRawText;

    {Adjacency and surrounding noise}
    [Test]
    procedure TestAdjacentTokensProduceTwoEntries;
    [Test]
    procedure TestWhitespaceBetweenTokensIgnored;
    [Test]
    procedure TestStrayTextOutsideTokensDropped;

    {Casing rule}
    [Test]
    procedure TestLowercaseIdentifierIsTcAsIs;
    [Test]
    procedure TestMixedCaseIdentifierIsTcAsIs;
    [Test]
    procedure TestAllUppercaseIdentifierIsTcUpper;
    [Test]
    procedure TestAllUppercaseUnknownIdentifierIsTcUpper;

    {Attributes}
    [Test]
    procedure TestSingleAttributeParsed;
    [Test]
    procedure TestMultipleAttributesParsed;
    [Test]
    procedure TestAttributeNameLowercased;
    [Test]
    procedure TestAttributeValuePreservesCase;
    [Test]
    procedure TestAttributeOrderPreserved;
    [Test]
    procedure TestHasAttrFalseWhenMissing;
    [Test]
    procedure TestAttrValueFallsBackToDefault;
    [Test]
    procedure TestAttrValueLookupCaseInsensitive;
    [Test]
    procedure TestAttributeWithoutValueAccepted;

    {Width helper}
    [Test]
    procedure TestTryGetWidthReturnsTrueOnInteger;
    [Test]
    procedure TestTryGetWidthReturnsFalseOnAuto;
    [Test]
    procedure TestTryGetWidthReturnsFalseOnMissing;
    [Test]
    procedure TestTryGetWidthReturnsFalseOnGarbage;
    [Test]
    procedure TestTryGetWidthRejectsNonPositive;

    {Malformed input}
    [Test]
    procedure TestUnclosedTokenBecomesUnknown;
    [Test]
    procedure TestEmptyTokenBecomesUnknown;
    [Test]
    procedure TestLonePercentBecomesUnknown;
    [Test]
    procedure TestPercentSpacePercentDegradesGracefully;
  end;

implementation

uses
  System.SysUtils,
  uStatusBarTokens, uStatusBarTemplate;

function ParseSingle(const ATemplate: string): TStatusBarToken;
var
  Tokens: TStatusBarTokenArray;
begin
  Tokens := ParseStatusBarTemplate(ATemplate);
  Assert.AreEqual<Integer>(1, Length(Tokens),
    Format('Expected exactly one token from "%s"', [ATemplate]));
  Result := Tokens[0];
end;

procedure TTestStatusBarTemplate.TestEmptyTemplateProducesNoTokens;
begin
  Assert.AreEqual<Integer>(0, Length(ParseStatusBarTemplate('')));
end;

procedure TTestStatusBarTemplate.TestWhitespaceOnlyProducesNoTokens;
begin
  Assert.AreEqual<Integer>(0, Length(ParseStatusBarTemplate('   ')));
end;

procedure TTestStatusBarTemplate.TestSingleRecognisedToken;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%resolution%');
  Assert.AreEqual(Ord(tkResolution), Ord(Tok.Kind));
  Assert.AreEqual<Integer>(0, Length(Tok.Attributes));
end;

procedure TTestStatusBarTemplate.TestSingleTokenRawTextCaptured;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%resolution%');
  Assert.AreEqual('%resolution%', Tok.RawText);
end;

procedure TTestStatusBarTemplate.TestUnknownIdentifierBecomesUnknownToken;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%not_a_real_token%');
  Assert.AreEqual(Ord(tkUnknown), Ord(Tok.Kind));
end;

procedure TTestStatusBarTemplate.TestUnknownIdentifierKeepsRawText;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%foobar%');
  Assert.AreEqual('%foobar%', Tok.RawText,
    'Unknown tokens must round-trip raw source so the user sees their typo');
end;

procedure TTestStatusBarTemplate.TestAdjacentTokensProduceTwoEntries;
var
  Tokens: TStatusBarTokenArray;
begin
  Tokens := ParseStatusBarTemplate('%resolution%%frames%');
  Assert.AreEqual<Integer>(2, Length(Tokens));
  Assert.AreEqual(Ord(tkResolution), Ord(Tokens[0].Kind));
  Assert.AreEqual(Ord(tkFrames), Ord(Tokens[1].Kind));
end;

procedure TTestStatusBarTemplate.TestWhitespaceBetweenTokensIgnored;
var
  Tokens: TStatusBarTokenArray;
begin
  Tokens := ParseStatusBarTemplate('%resolution%   %frames%');
  Assert.AreEqual<Integer>(2, Length(Tokens));
  Assert.AreEqual(Ord(tkResolution), Ord(Tokens[0].Kind));
  Assert.AreEqual(Ord(tkFrames), Ord(Tokens[1].Kind));
end;

procedure TTestStatusBarTemplate.TestStrayTextOutsideTokensDropped;
var
  Tokens: TStatusBarTokenArray;
begin
  Tokens := ParseStatusBarTemplate('hello %resolution% world %frames% .');
  Assert.AreEqual<Integer>(2, Length(Tokens));
  Assert.AreEqual(Ord(tkResolution), Ord(Tokens[0].Kind));
  Assert.AreEqual(Ord(tkFrames), Ord(Tokens[1].Kind));
end;

procedure TTestStatusBarTemplate.TestLowercaseIdentifierIsTcAsIs;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%resolution%');
  Assert.AreEqual(Ord(tcAsIs), Ord(Tok.Casing));
end;

procedure TTestStatusBarTemplate.TestMixedCaseIdentifierIsTcAsIs;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%Resolution%');
  Assert.AreEqual(Ord(tcAsIs), Ord(Tok.Casing));
end;

procedure TTestStatusBarTemplate.TestAllUppercaseIdentifierIsTcUpper;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%RESOLUTION%');
  Assert.AreEqual(Ord(tcUpper), Ord(Tok.Casing));
  Assert.AreEqual(Ord(tkResolution), Ord(Tok.Kind),
    'Casing must not affect kind lookup');
end;

procedure TTestStatusBarTemplate.TestAllUppercaseUnknownIdentifierIsTcUpper;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%FOOBAR%');
  Assert.AreEqual(Ord(tcUpper), Ord(Tok.Casing));
  Assert.AreEqual(Ord(tkUnknown), Ord(Tok.Kind));
end;

procedure TTestStatusBarTemplate.TestSingleAttributeParsed;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension cap=true%');
  Assert.AreEqual(Ord(tkSaveDimension), Ord(Tok.Kind));
  Assert.AreEqual<Integer>(1, Length(Tok.Attributes));
  Assert.AreEqual('cap', Tok.Attributes[0].Name);
  Assert.AreEqual('true', Tok.Attributes[0].Value);
end;

procedure TTestStatusBarTemplate.TestMultipleAttributesParsed;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension cap=true width=200%');
  Assert.AreEqual<Integer>(2, Length(Tok.Attributes));
  Assert.AreEqual('true', Tok.AttrValue('cap'));
  Assert.AreEqual('200', Tok.AttrValue('width'));
end;

procedure TTestStatusBarTemplate.TestAttributeNameLowercased;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension CAP=true WIDTH=200%');
  Assert.AreEqual('cap', Tok.Attributes[0].Name);
  Assert.AreEqual('width', Tok.Attributes[1].Name);
end;

procedure TTestStatusBarTemplate.TestAttributeValuePreservesCase;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension cap=TrueValue%');
  Assert.AreEqual('TrueValue', Tok.Attributes[0].Value,
    'Attribute values are passed through verbatim — casing is the consumer''s problem');
end;

procedure TTestStatusBarTemplate.TestAttributeOrderPreserved;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension width=200 cap=true%');
  Assert.AreEqual('width', Tok.Attributes[0].Name);
  Assert.AreEqual('cap', Tok.Attributes[1].Name);
end;

procedure TTestStatusBarTemplate.TestHasAttrFalseWhenMissing;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension cap=true%');
  Assert.IsTrue(Tok.HasAttr('cap'));
  Assert.IsFalse(Tok.HasAttr('width'));
end;

procedure TTestStatusBarTemplate.TestAttrValueFallsBackToDefault;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%resolution%');
  Assert.AreEqual('fallback', Tok.AttrValue('width', 'fallback'));
end;

procedure TTestStatusBarTemplate.TestAttrValueLookupCaseInsensitive;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%save_dimension cap=true%');
  Assert.AreEqual('true', Tok.AttrValue('CAP'));
  Assert.AreEqual('true', Tok.AttrValue('Cap'));
end;

procedure TTestStatusBarTemplate.TestAttributeWithoutValueAccepted;
var
  Tok: TStatusBarToken;
begin
  {Bare attribute name with no '=' is parsed with empty value. Useful as
   a forward-compatible escape hatch (e.g. boolean flags) without making
   the parser stricter.}
  Tok := ParseSingle('%resolution flag%');
  Assert.AreEqual<Integer>(1, Length(Tok.Attributes));
  Assert.AreEqual('flag', Tok.Attributes[0].Name);
  Assert.AreEqual('', Tok.Attributes[0].Value);
end;

procedure TTestStatusBarTemplate.TestTryGetWidthReturnsTrueOnInteger;
var
  Tok: TStatusBarToken;
  W: Integer;
begin
  Tok := ParseSingle('%resolution width=120%');
  Assert.IsTrue(Tok.TryGetWidth(W));
  Assert.AreEqual(120, W);
end;

procedure TTestStatusBarTemplate.TestTryGetWidthReturnsFalseOnAuto;
var
  Tok: TStatusBarToken;
  W: Integer;
begin
  Tok := ParseSingle('%resolution width=auto%');
  Assert.IsFalse(Tok.TryGetWidth(W),
    '"auto" is the explicit signal that the renderer must measure');
end;

procedure TTestStatusBarTemplate.TestTryGetWidthReturnsFalseOnMissing;
var
  Tok: TStatusBarToken;
  W: Integer;
begin
  Tok := ParseSingle('%resolution%');
  Assert.IsFalse(Tok.TryGetWidth(W));
end;

procedure TTestStatusBarTemplate.TestTryGetWidthReturnsFalseOnGarbage;
var
  Tok: TStatusBarToken;
  W: Integer;
begin
  Tok := ParseSingle('%resolution width=ten%');
  Assert.IsFalse(Tok.TryGetWidth(W),
    'Unparseable width must fall through to auto rather than crash');
end;

procedure TTestStatusBarTemplate.TestTryGetWidthRejectsNonPositive;
var
  Tok: TStatusBarToken;
  W: Integer;
begin
  Tok := ParseSingle('%resolution width=0%');
  Assert.IsFalse(Tok.TryGetWidth(W));
  Tok := ParseSingle('%resolution width=-5%');
  Assert.IsFalse(Tok.TryGetWidth(W));
end;

procedure TTestStatusBarTemplate.TestUnclosedTokenBecomesUnknown;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%resolution');
  Assert.AreEqual(Ord(tkUnknown), Ord(Tok.Kind),
    'Unclosed token must surface as tkUnknown so the user notices the missing %');
  Assert.AreEqual('%resolution', Tok.RawText);
end;

procedure TTestStatusBarTemplate.TestEmptyTokenBecomesUnknown;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%%');
  Assert.AreEqual(Ord(tkUnknown), Ord(Tok.Kind));
  Assert.AreEqual('%%', Tok.RawText);
end;

procedure TTestStatusBarTemplate.TestLonePercentBecomesUnknown;
var
  Tok: TStatusBarToken;
begin
  Tok := ParseSingle('%');
  Assert.AreEqual(Ord(tkUnknown), Ord(Tok.Kind));
  Assert.AreEqual('%', Tok.RawText);
end;

procedure TTestStatusBarTemplate.TestPercentSpacePercentDegradesGracefully;
var
  Tokens: TStatusBarTokenArray;
begin
  {'% %' has no identifier between the percents. Parser must not crash
   nor enter an infinite loop; one tkUnknown spanning the broken
   fragment is the contract.}
  Tokens := ParseStatusBarTemplate('% %');
  Assert.IsTrue(Length(Tokens) >= 1);
  Assert.AreEqual(Ord(tkUnknown), Ord(Tokens[0].Kind));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStatusBarTemplate);

end.
