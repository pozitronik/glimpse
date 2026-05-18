{ffmpeg stderr-output parsing primitives.

 Stateless pure functions that scan ffmpeg's `-i` stderr output and
 extract individual metadata fields (duration, resolution, codec,
 bitrates, audio properties, SAR). Lifted out of uFFmpegExe so the
 parsing surface lives independently of the process orchestration
 (uFFmpegExe owns the ffmpeg subprocess; this unit owns "given a
 stderr text blob, what does it say").

 Every function is a pure projection of a text string to a typed
 value. No I/O. No globals. Easy to test against canned strings.

 Implementation helpers (ScanNumberBefore, SkipSpacesBack,
 ScanNumberBeforeToken, ParseStreamBitrate) stay private — callers
 should reach for the higher-level Parse* functions.

 LenientUTF8Decode also lives here because every Parse* caller needs
 to convert the raw stderr TBytes to a string first; bundling the
 decoder removes the cross-unit hop.}
unit uFFmpegProbeParser;

interface

uses
  System.SysUtils;

{Decodes bytes as UTF-8, replacing invalid sequences instead of raising.
 ffmpeg may embed legacy-encoded metadata (e.g. CP1251 titles) that is
 not valid UTF-8; strict decoding would raise EEncodingError.}
function LenientUTF8Decode(const ABytes: TBytes): string;

{Parses duration from ffmpeg stderr output. Returns seconds, or -1 if not found.}
function ParseDuration(const AText: string): Double;

{Parses video resolution from ffmpeg stderr output.}
function ParseResolution(const AText: string; out AWidth, AHeight: Integer): Boolean;

{Parses sample aspect ratio (SAR) numerator and denominator from ffmpeg
 stderr output. Looks for the "[SAR <N>:<D> ..." marker on the Video: line.
 When the marker is missing or the values are zero/invalid, AN/AD are set
 to 1:1 (square pixels) and the function returns False.}
function ParseSampleAspect(const AText: string; out AN, AD: Integer): Boolean;

{Parses video codec name from ffmpeg stderr output.}
function ParseVideoCodec(const AText: string): string;

{Parses overall bitrate from ffmpeg stderr Duration line. Returns kb/s, or 0.}
function ParseBitrate(const AText: string): Integer;

{Parses video framerate from ffmpeg stderr Video stream line. Returns fps, or 0.}
function ParseFps(const AText: string): Double;

{Parses video stream bitrate from ffmpeg stderr. Returns kb/s, or 0.}
function ParseVideoBitrate(const AText: string): Integer;

{Parses audio codec from ffmpeg stderr Audio stream line.}
function ParseAudioCodec(const AText: string): string;

{Parses audio sample rate from ffmpeg stderr. Returns Hz, or 0.}
function ParseAudioSampleRate(const AText: string): Integer;

{Parses audio channel layout from ffmpeg stderr (mono, stereo, 5.1, etc.).}
function ParseAudioChannels(const AText: string): string;

{Parses audio bitrate from ffmpeg stderr Audio stream line. Returns kb/s, or 0.}
function ParseAudioBitrate(const AText: string): Integer;

{Extracts the first line containing APrefix from ffmpeg output.}
function ExtractStreamLine(const AText, APrefix: string): string;

implementation

uses
  System.Math, Winapi.Windows;

function LenientUTF8Decode(const ABytes: TBytes): string;
var
  Enc: TEncoding;
begin
  if Length(ABytes) = 0 then
    Exit('');
  Enc := TUTF8Encoding.Create(CP_UTF8, 0, 0);
  try
    Result := Enc.GetString(ABytes);
  finally
    Enc.Free;
  end;
end;

function ParseDuration(const AText: string): Double;
var
  P: Integer;
  TimeStr: string;
  Parts: TArray<string>;
  H, M, S: Integer;
  DotPos: Integer;
  FracStr: string;
  Frac: Double;
begin
  Result := -1;

  P := Pos('Duration:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Duration:');

  {Skip whitespace}
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);

  {Read until comma, newline, or end}
  TimeStr := '';
  while (P <= Length(AText)) and not CharInSet(AText[P], [',', #13, #10]) do
  begin
    TimeStr := TimeStr + AText[P];
    Inc(P);
  end;
  TimeStr := Trim(TimeStr);

  if (TimeStr = '') or SameText(TimeStr, 'N/A') then
    Exit;

  {Expected: HH:MM:SS.ff}
  Parts := TimeStr.Split([':']);
  if Length(Parts) <> 3 then
    Exit;

  H := StrToIntDef(Parts[0], -1);
  M := StrToIntDef(Parts[1], -1);
  if (H < 0) or (M < 0) then
    Exit;

  DotPos := Pos('.', Parts[2]);
  if DotPos > 0 then
  begin
    S := StrToIntDef(Copy(Parts[2], 1, DotPos - 1), -1);
    FracStr := Copy(Parts[2], DotPos + 1, Length(Parts[2]) - DotPos);
    if (FracStr = '') or (S < 0) then
      Exit;
    Frac := StrToIntDef(FracStr, 0) / Power(10, Length(FracStr));
  end else begin
    S := StrToIntDef(Parts[2], -1);
    Frac := 0;
  end;

  if S < 0 then
    Exit;

  Result := H * 3600.0 + M * 60.0 + S + Frac;
end;

function ParseResolution(const AText: string; out AWidth, AHeight: Integer): Boolean;
var
  VideoPos, P, I: Integer;
  WidthStr, HeightStr: string;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;

  VideoPos := Pos('Video:', AText);
  if VideoPos = 0 then
    Exit;

  {Scan for NNNxNNN pattern after "Video:"}
  P := VideoPos + 6;
  while P < Length(AText) do
  begin
    if (AText[P] = 'x') and CharInSet(AText[P - 1], ['0' .. '9']) and CharInSet(AText[P + 1], ['0' .. '9']) then
    begin
      {Walk backwards for width digits}
      I := P - 1;
      while (I > VideoPos) and CharInSet(AText[I], ['0' .. '9']) do
        Dec(I);
      WidthStr := Copy(AText, I + 1, P - I - 1);

      {Walk forwards for height digits}
      I := P + 1;
      while (I <= Length(AText)) and CharInSet(AText[I], ['0' .. '9']) do
        Inc(I);
      HeightStr := Copy(AText, P + 1, I - P - 1);

      AWidth := StrToIntDef(WidthStr, 0);
      AHeight := StrToIntDef(HeightStr, 0);

      {Require at least 2-digit width and height to avoid false matches like "0x1A"}
      if (Length(WidthStr) >= 2) and (Length(HeightStr) >= 2) and (AWidth > 0) and (AHeight > 0) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(P);
  end;
end;

function ParseSampleAspect(const AText: string; out AN, AD: Integer): Boolean;
const
  Marker = '[SAR ';
var
  VideoPos, MarkerPos, ColonPos, EndPos, NumStart: Integer;
begin
  Result := False;
  AN := 1;
  AD := 1;

  VideoPos := Pos('Video:', AText);
  if VideoPos = 0 then
    Exit;

  MarkerPos := Pos(Marker, AText, VideoPos);
  if MarkerPos = 0 then
    Exit;

  {Walk digits up to ':' starting after the marker}
  NumStart := MarkerPos + Length(Marker);
  ColonPos := NumStart;
  while (ColonPos <= Length(AText)) and CharInSet(AText[ColonPos], ['0' .. '9']) do
    Inc(ColonPos);
  if (ColonPos > Length(AText)) or (ColonPos = NumStart) or (AText[ColonPos] <> ':') then
    Exit;
  AN := StrToIntDef(Copy(AText, NumStart, ColonPos - NumStart), 0);

  {Walk digits after ':'}
  EndPos := ColonPos + 1;
  while (EndPos <= Length(AText)) and CharInSet(AText[EndPos], ['0' .. '9']) do
    Inc(EndPos);
  if EndPos = ColonPos + 1 then
  begin
    AN := 1;
    Exit;
  end;
  AD := StrToIntDef(Copy(AText, ColonPos + 1, EndPos - ColonPos - 1), 0);

  if (AN <= 0) or (AD <= 0) then
  begin
    AN := 1;
    AD := 1;
    Exit;
  end;

  Result := True;
end;

function ParseVideoCodec(const AText: string): string;
var
  P, Start: Integer;
begin
  Result := '';

  P := Pos('Video:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Video:');

  {Skip whitespace}
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);

  {Read word characters}
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_']) do
    Inc(P);

  if P > Start then
    Result := Copy(AText, Start, P - Start);
end;

function ParseBitrate(const AText: string): Integer;
var
  P, Start: Integer;
  NumStr: string;
begin
  Result := 0;
  {Look for "bitrate:" on the Duration line (before any Stream lines)}
  P := Pos('bitrate:', AText);
  if P = 0 then
    Exit;
  P := P + Length('bitrate:');
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['0' .. '9']) do
    Inc(P);
  if P > Start then
  begin
    NumStr := Copy(AText, Start, P - Start);
    Result := StrToIntDef(NumStr, 0);
  end;
end;

{Extracts the first line containing APrefix from multi-line ffmpeg output}
function ExtractStreamLine(const AText, APrefix: string): string;
var
  P, LineEnd: Integer;
begin
  Result := '';
  P := Pos(APrefix, AText);
  if P = 0 then
    Exit;
  LineEnd := P;
  while (LineEnd <= Length(AText)) and not CharInSet(AText[LineEnd], [#13, #10]) do
    Inc(LineEnd);
  Result := Copy(AText, P, LineEnd - P);
end;

{Scans backward from position P through characters in ADigitChars,
 returning the extracted number string. P is unchanged.}
function ScanNumberBefore(const ALine: string; P: Integer; const ADigitChars: TSysCharSet): string;
var
  Start: Integer;
begin
  Result := '';
  Start := P;
  while (Start > 0) and CharInSet(ALine[Start], ADigitChars) do
    Dec(Start);
  Inc(Start);
  if Start <= P then
    Result := Copy(ALine, Start, P - Start + 1);
end;

{Skips whitespace backward from position P, returns updated position}
function SkipSpacesBack(const ALine: string; P: Integer): Integer;
begin
  while (P > 0) and (ALine[P] = ' ') do
    Dec(P);
  Result := P;
end;

{Composite helper used by the "value AToken" parsers (ParseFps, ParseAudioSampleRate):
 find AToken in ALine, skip any whitespace immediately before it, then scan
 backward for digits (or AAllowedChars) and return the literal in AValue.
 Returns True on a non-empty digit run.

 Does NOT fit ParseStreamBitrate — that one needs the LAST occurrence of
 'kb/s' (codec metadata can mention bitrates earlier on the same line),
 so it keeps its own right-to-left walk.}
function ScanNumberBeforeToken(const ALine, AToken: string;
  const AAllowedChars: TSysCharSet; out AValue: string): Boolean;
var
  P: Integer;
begin
  AValue := '';
  Result := False;
  P := Pos(AToken, ALine);
  if P < 2 then
    Exit;
  P := SkipSpacesBack(ALine, P - 1);
  AValue := ScanNumberBefore(ALine, P, AAllowedChars);
  Result := AValue <> '';
end;

function ParseFps(const AText: string): Double;
var
  Line, NumStr: string;
begin
  Result := 0;
  Line := ExtractStreamLine(AText, 'Video:');
  if Line = '' then
    Exit;
  if ScanNumberBeforeToken(Line, ' fps', ['0' .. '9', '.'], NumStr) then
    Result := StrToFloatDef(NumStr, 0, TFormatSettings.Invariant);
end;

{Parses bitrate (kb/s) from a single stream line}
function ParseStreamBitrate(const ALine: string): Integer;
var
  P: Integer;
  NumStr: string;
begin
  Result := 0;
  {Find last occurrence of "kb/s" on the line}
  P := Length(ALine);
  while P > 4 do
  begin
    if (ALine[P] = 's') and (Copy(ALine, P - 3, 4) = 'kb/s') then
    begin
      P := SkipSpacesBack(ALine, P - 4);
      NumStr := ScanNumberBefore(ALine, P, ['0' .. '9']);
      if NumStr <> '' then
        Result := StrToIntDef(NumStr, 0);
      Exit;
    end;
    Dec(P);
  end;
end;

function ParseVideoBitrate(const AText: string): Integer;
begin
  Result := ParseStreamBitrate(ExtractStreamLine(AText, 'Video:'));
end;

function ParseAudioCodec(const AText: string): string;
var
  P, Start: Integer;
begin
  Result := '';
  P := Pos('Audio:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Audio:');
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_']) do
    Inc(P);
  if P > Start then
    Result := Copy(AText, Start, P - Start);
end;

function ParseAudioSampleRate(const AText: string): Integer;
var
  Line, NumStr: string;
begin
  Result := 0;
  Line := ExtractStreamLine(AText, 'Audio:');
  if Line = '' then
    Exit;
  if ScanNumberBeforeToken(Line, ' Hz', ['0' .. '9'], NumStr) then
    Result := StrToIntDef(NumStr, 0);
end;

function ParseAudioChannels(const AText: string): string;
var
  Line: string;
  Parts: TArray<string>;
  I: Integer;
  S: string;
begin
  Result := '';
  Line := ExtractStreamLine(AText, 'Audio:');
  if Line = '' then
    Exit;
  {Audio line format: "Audio: codec (profile) (fourcc), rate Hz, channels, fmt, bitrate"
   Channel layout is a comma-separated field: mono, stereo, 5.1, 7.1, etc.}
  Parts := Line.Split([',']);
  for I := 0 to High(Parts) do
  begin
    S := Parts[I].Trim.ToLower;
    if (S = 'mono') or (S = 'stereo') or (S = '5.1') or (S = '7.1') or (S = '5.1(side)') or (S = '7.1(side)') or (S = '4.0') or (S = '2.1') or (S = '6.1') or (S = '5.0') or (S = 'quad') then
    begin
      Result := Parts[I].Trim;
      Exit;
    end;
  end;
end;

function ParseAudioBitrate(const AText: string): Integer;
begin
  Result := ParseStreamBitrate(ExtractStreamLine(AText, 'Audio:'));
end;

end.
