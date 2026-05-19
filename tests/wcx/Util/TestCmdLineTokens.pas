unit TestCmdLineTokens;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCmdLineTokens = class
  public
    { Tokeniser }
    [Test] procedure TestTokenizeEmpty;
    [Test] procedure TestTokenizeWhitespaceSplit;
    [Test] procedure TestTokenizeRespectsDoubleQuotes;
    [Test] procedure TestTokenizeStripsQuoteCharacters;
    [Test] procedure TestTokenizeCollapsesMultipleSpaces;
    [Test] procedure TestTokenizeAcceptsTabsAsSeparators;
  end;

implementation

uses
  System.SysUtils,
  CmdLineTokens;

{ Tokeniser }

procedure TTestCmdLineTokens.TestTokenizeEmpty;
begin
  Assert.AreEqual(0, Integer(Length(TokenizeArgs(''))));
  Assert.AreEqual(0, Integer(Length(TokenizeArgs('   '))));
end;

procedure TTestCmdLineTokens.TestTokenizeWhitespaceSplit;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('-vn -c:a libmp3lame');
  Assert.AreEqual(3, Integer(Length(Tokens)));
  Assert.AreEqual('-vn', Tokens[0]);
  Assert.AreEqual('-c:a', Tokens[1]);
  Assert.AreEqual('libmp3lame', Tokens[2]);
end;

procedure TTestCmdLineTokens.TestTokenizeRespectsDoubleQuotes;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('-metadata "title=My Movie" -y');
  Assert.AreEqual(3, Integer(Length(Tokens)));
  Assert.AreEqual('-metadata', Tokens[0]);
  Assert.AreEqual('title=My Movie', Tokens[1]);
  Assert.AreEqual('-y', Tokens[2]);
end;

procedure TTestCmdLineTokens.TestTokenizeStripsQuoteCharacters;
var
  Tokens: TArray<string>;
begin
  { Quotes are syntax, not data — they must not survive into the token,
    or downstream comparisons (e.g. validation) would never match. }
  Tokens := TokenizeArgs('"-y"');
  Assert.AreEqual(1, Integer(Length(Tokens)));
  Assert.AreEqual('-y', Tokens[0]);
end;

procedure TTestCmdLineTokens.TestTokenizeCollapsesMultipleSpaces;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('  a    b  c  ');
  Assert.AreEqual(3, Integer(Length(Tokens)));
  Assert.AreEqual('a', Tokens[0]);
  Assert.AreEqual('b', Tokens[1]);
  Assert.AreEqual('c', Tokens[2]);
end;

procedure TTestCmdLineTokens.TestTokenizeAcceptsTabsAsSeparators;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('a'#9'b'#9#9'c');
  Assert.AreEqual(3, Integer(Length(Tokens)));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCmdLineTokens);

end.
