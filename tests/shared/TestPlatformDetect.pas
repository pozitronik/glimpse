unit TestPlatformDetect;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPlatformDetect = class
  public
    [Test]
    procedure TestResolutionTransformGlyphHasSurroundingSpaces;
    [Test]
    procedure TestResolutionTransformGlyphIsArrowOnModernWindows;
    [Test]
    procedure TestResolutionTransformGlyphIsAsciiOnLegacyWindows;
    [Test]
    procedure TestResolutionTransformGlyphIsNotMojibake;
  end;

implementation

uses
  System.SysUtils,
  PlatformDetect;

procedure TTestPlatformDetect.TestResolutionTransformGlyphHasSurroundingSpaces;
var
  G: string;
begin
  G := ResolutionTransformGlyph;
  Assert.IsTrue(G.StartsWith(' '),
    'Glyph must include a leading space so callers can substitute it bare');
  Assert.IsTrue(G.EndsWith(' '),
    'Glyph must include a trailing space');
end;

procedure TTestPlatformDetect.TestResolutionTransformGlyphIsArrowOnModernWindows;
var
  G: string;
begin
  if IsLegacyWindows then
    Exit;
  G := ResolutionTransformGlyph;
  Assert.AreEqual(' ' + #$2192 + ' ', G,
    'Modern Windows must use U+2192; encoding regressions show up as multi-byte mojibake here');
end;

procedure TTestPlatformDetect.TestResolutionTransformGlyphIsAsciiOnLegacyWindows;
var
  G: string;
begin
  if not IsLegacyWindows then
    Exit;
  G := ResolutionTransformGlyph;
  Assert.AreEqual(' -> ', G,
    'Legacy Windows must use the ASCII fallback (Tahoma arrow coverage is patchy on XP)');
end;

procedure TTestPlatformDetect.TestResolutionTransformGlyphIsNotMojibake;
var
  G: string;
  I: Integer;
begin
  {Encoding-regression sentinel: the glyph must be either a single
   non-ASCII char (U+2192) sandwiched in spaces, or pure ASCII. A
   misencoded literal '→' in source surfaces as 3 separate Latin-1
   bytes (0xE2 0x86 0x92), each widened to its own UTF-16 code unit;
   the assertions below catch that pattern by counting non-ASCII
   characters between the spaces.}
  G := ResolutionTransformGlyph;
  if IsLegacyWindows then
    Exit;
  {Strip the surrounding spaces; the core must be exactly one char.}
  Assert.AreEqual<Integer>(3, Length(G),
    'Modern glyph string must be exactly " X " — three code units total');
  Assert.AreEqual<Integer>($2192, Ord(G[2]),
    'Middle character must be U+2192 (RIGHTWARDS ARROW), not the multi-byte mojibake form');
  for I := 1 to Length(G) do
    Assert.IsTrue((Ord(G[I]) = $20) or (Ord(G[I]) = $2192),
      Format('Unexpected character at position %d: U+%.4X', [I, Ord(G[I])]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPlatformDetect);

end.
