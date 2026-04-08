{Hex color string conversion utilities.
 Handles #RRGGBB and #RRGGBBAA formats used in INI settings.}
unit uColorConv;

interface

uses
  System.UITypes;

{Parses #RRGGBB from a hex string starting at position 1.
 Returns True on success, setting AColor.}
function TryParseHexRGB(const AHex: string; out AColor: TColor): Boolean;

{Parses a 7-char hex color string (#RRGGBB). Returns ADefault on failure.}
function HexToColor(const AValue: string; ADefault: TColor): TColor;

{Converts a TColor to #RRGGBB hex string.}
function ColorToHex(AColor: TColor): string;

{Parses a 9-char hex color+alpha string (#RRGGBBAA).
 Returns defaults on failure.}
procedure HexToColorAlpha(const AValue: string; ADefColor: TColor; ADefAlpha: Byte; out AColor: TColor; out AAlpha: Byte);

{Converts a TColor and alpha byte to #RRGGBBAA hex string.}
function ColorAlphaToHex(AColor: TColor; AAlpha: Byte): string;

implementation

uses
  System.SysUtils;

function TryParseHexRGB(const AHex: string; out AColor: TColor): Boolean;
var
  R, G, B: Integer;
begin
  Result := False;
  try
    R := StrToInt('$' + Copy(AHex, 2, 2));
    G := StrToInt('$' + Copy(AHex, 4, 2));
    B := StrToInt('$' + Copy(AHex, 6, 2));
    {TColor is stored as $00BBGGRR}
    AColor := TColor(R or (G shl 8) or (B shl 16));
    Result := True;
  except
    on EConvertError do; {Invalid hex digits}
  end;
end;

function HexToColor(const AValue: string; ADefault: TColor): TColor;
var
  Hex: string;
begin
  Hex := AValue.Trim;
  if (Length(Hex) = 7) and (Hex[1] = '#') and TryParseHexRGB(Hex, Result) then
    Exit;
  Result := ADefault;
end;

function ColorToHex(AColor: TColor): string;
var
  C: Integer;
begin
  C := Integer(AColor);
  Result := Format('#%.2X%.2X%.2X', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF]);
end;

procedure HexToColorAlpha(const AValue: string; ADefColor: TColor; ADefAlpha: Byte; out AColor: TColor; out AAlpha: Byte);
var
  Hex: string;
begin
  Hex := AValue.Trim;
  if (Length(Hex) = 9) and (Hex[1] = '#') and TryParseHexRGB(Hex, AColor) then
  begin
    try
      AAlpha := Byte(StrToInt('$' + Copy(Hex, 8, 2)));
      Exit;
    except
      on EConvertError do; {Invalid hex digits for alpha}
    end;
  end;
  AColor := ADefColor;
  AAlpha := ADefAlpha;
end;

function ColorAlphaToHex(AColor: TColor; AAlpha: Byte): string;
var
  C: Integer;
begin
  C := Integer(AColor);
  Result := Format('#%.2X%.2X%.2X%.2X', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF, AAlpha]);
end;

end.
