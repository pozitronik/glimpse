unit TestColorConv;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestColorConv = class
  public
    { TryParseHexRGB }
    [Test] procedure TryParse_ValidRed;
    [Test] procedure TryParse_ValidGreen;
    [Test] procedure TryParse_ValidBlue;
    [Test] procedure TryParse_Black;
    [Test] procedure TryParse_White;
    [Test] procedure TryParse_Empty;
    [Test] procedure TryParse_TooShort;
    [Test] procedure TryParse_NonHex;
    [Test] procedure TryParse_JustHash;
    [Test] procedure TryParse_LowerCase;
    { HexToColor }
    [Test] procedure HexToColor_Valid;
    [Test] procedure HexToColor_Invalid_ReturnsDefault;
    [Test] procedure HexToColor_NoHash_ReturnsDefault;
    [Test] procedure HexToColor_TrimmedSpaces;
    { ColorToHex }
    [Test] procedure ColorToHex_Red;
    [Test] procedure ColorToHex_Black;
    [Test] procedure ColorToHex_White;
    { HexToColor + ColorToHex round-trip }
    [Test] procedure RoundTrip_Color;
    { HexToColorAlpha }
    [Test] procedure HexToColorAlpha_Valid;
    [Test] procedure HexToColorAlpha_InvalidLength_ReturnsDefaults;
    [Test] procedure HexToColorAlpha_InvalidAlpha_ReturnsDefaults;
    { ColorAlphaToHex }
    [Test] procedure ColorAlphaToHex_FullOpaque;
    [Test] procedure ColorAlphaToHex_HalfAlpha;
    { HexToColorAlpha + ColorAlphaToHex round-trip }
    [Test] procedure RoundTrip_ColorAlpha;
  end;

implementation

uses
  System.UITypes, uColorConv;

{ TryParseHexRGB }

procedure TTestColorConv.TryParse_ValidRed;
var C: TColor;
begin
  Assert.IsTrue(TryParseHexRGB('#FF0000', C));
  Assert.AreEqual(Integer($000000FF), Integer(C));
end;

procedure TTestColorConv.TryParse_ValidGreen;
var C: TColor;
begin
  Assert.IsTrue(TryParseHexRGB('#00FF00', C));
  Assert.AreEqual(Integer($0000FF00), Integer(C));
end;

procedure TTestColorConv.TryParse_ValidBlue;
var C: TColor;
begin
  Assert.IsTrue(TryParseHexRGB('#0000FF', C));
  Assert.AreEqual(Integer($00FF0000), Integer(C));
end;

procedure TTestColorConv.TryParse_Black;
var C: TColor;
begin
  Assert.IsTrue(TryParseHexRGB('#000000', C));
  Assert.AreEqual(Integer($00000000), Integer(C));
end;

procedure TTestColorConv.TryParse_White;
var C: TColor;
begin
  Assert.IsTrue(TryParseHexRGB('#FFFFFF', C));
  Assert.AreEqual(Integer($00FFFFFF), Integer(C));
end;

procedure TTestColorConv.TryParse_Empty;
var C: TColor;
begin
  Assert.IsFalse(TryParseHexRGB('', C));
end;

procedure TTestColorConv.TryParse_TooShort;
var C: TColor;
begin
  Assert.IsFalse(TryParseHexRGB('#FF00', C));
end;

procedure TTestColorConv.TryParse_NonHex;
var C: TColor;
begin
  Assert.IsFalse(TryParseHexRGB('#GGHHII', C));
end;

procedure TTestColorConv.TryParse_JustHash;
var C: TColor;
begin
  Assert.IsFalse(TryParseHexRGB('#', C));
end;

procedure TTestColorConv.TryParse_LowerCase;
var C: TColor;
begin
  Assert.IsTrue(TryParseHexRGB('#ff8040', C));
  Assert.AreEqual(Integer($004080FF), Integer(C));
end;

{ HexToColor }

procedure TTestColorConv.HexToColor_Valid;
begin
  Assert.AreEqual(Integer($000000FF), Integer(HexToColor('#FF0000', TColor(0))));
end;

procedure TTestColorConv.HexToColor_Invalid_ReturnsDefault;
begin
  Assert.AreEqual(Integer($00AABBCC), Integer(HexToColor('garbage', TColor($00AABBCC))));
end;

procedure TTestColorConv.HexToColor_NoHash_ReturnsDefault;
begin
  Assert.AreEqual(Integer($00112233), Integer(HexToColor('FF0000', TColor($00112233))));
end;

procedure TTestColorConv.HexToColor_TrimmedSpaces;
begin
  Assert.AreEqual(Integer($000000FF), Integer(HexToColor('  #FF0000  ', TColor(0))));
end;

{ ColorToHex }

procedure TTestColorConv.ColorToHex_Red;
begin
  Assert.AreEqual('#FF0000', ColorToHex(TColor($000000FF)));
end;

procedure TTestColorConv.ColorToHex_Black;
begin
  Assert.AreEqual('#000000', ColorToHex(TColor($00000000)));
end;

procedure TTestColorConv.ColorToHex_White;
begin
  Assert.AreEqual('#FFFFFF', ColorToHex(TColor($00FFFFFF)));
end;

{ Round-trip }

procedure TTestColorConv.RoundTrip_Color;
var
  Original: TColor;
begin
  Original := TColor($00385FA2);
  Assert.AreEqual(Integer(Original), Integer(HexToColor(ColorToHex(Original), TColor(0))));
end;

{ HexToColorAlpha }

procedure TTestColorConv.HexToColorAlpha_Valid;
var
  C: TColor;
  A: Byte;
begin
  HexToColorAlpha('#FF000080', TColor(0), 0, C, A);
  Assert.AreEqual(Integer($000000FF), Integer(C));
  Assert.AreEqual(Byte($80), A);
end;

procedure TTestColorConv.HexToColorAlpha_InvalidLength_ReturnsDefaults;
var
  C: TColor;
  A: Byte;
begin
  HexToColorAlpha('#FF0000', TColor($00AABB), 42, C, A);
  Assert.AreEqual(Integer($00AABB), Integer(C));
  Assert.AreEqual(Byte(42), A);
end;

procedure TTestColorConv.HexToColorAlpha_InvalidAlpha_ReturnsDefaults;
var
  C: TColor;
  A: Byte;
begin
  HexToColorAlpha('#FF0000GG', TColor($00CCDD), 99, C, A);
  Assert.AreEqual(Integer($00CCDD), Integer(C));
  Assert.AreEqual(Byte(99), A);
end;

{ ColorAlphaToHex }

procedure TTestColorConv.ColorAlphaToHex_FullOpaque;
begin
  Assert.AreEqual('#FF0000FF', ColorAlphaToHex(TColor($000000FF), 255));
end;

procedure TTestColorConv.ColorAlphaToHex_HalfAlpha;
begin
  Assert.AreEqual('#00FF0080', ColorAlphaToHex(TColor($0000FF00), $80));
end;

{ Round-trip alpha }

procedure TTestColorConv.RoundTrip_ColorAlpha;
var
  OrigC: TColor;
  OrigA: Byte;
  C: TColor;
  A: Byte;
begin
  OrigC := TColor($00A0B0C0);
  OrigA := 200;
  HexToColorAlpha(ColorAlphaToHex(OrigC, OrigA), TColor(0), 0, C, A);
  Assert.AreEqual(Integer(OrigC), Integer(C));
  Assert.AreEqual(OrigA, A);
end;

end.
