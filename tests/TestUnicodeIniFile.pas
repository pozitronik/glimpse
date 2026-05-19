unit TestUnicodeIniFile;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnicodeIniFile = class
  private
    FTempDir: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    { DecodeIniBytes — pure encoding detection. }
    [Test] procedure TestDecodeEmptyReturnsEmpty;
    [Test] procedure TestDecodeUTF8WithBomStripsBom;
    [Test] procedure TestDecodeUTF16LEWithBom;
    [Test] procedure TestDecodeUTF16BEWithBom;
    [Test] procedure TestDecodeUTF8WithoutBomViaHeuristic;
    [Test] procedure TestDecodeAnsiFallbackOnInvalidUTF8;
    [Test] procedure TestDecodeAsciiUnchanged;

    { Round-trip via TUnicodeIniFile. }
    [Test] procedure TestReadStringMissingReturnsDefault;
    [Test] procedure TestWriteThenReadString;
    [Test] procedure TestWriteThenReadInteger;
    [Test] procedure TestUpdateFileRoundTripNoBOM;
    [Test] procedure TestPersistsCyrillicLossless;

    { Lenient ReadBool. }
    [Test] procedure TestReadBoolAcceptsTrueLowercase;
    [Test] procedure TestReadBoolAcceptsYesNoOnOff;
    [Test] procedure TestReadBoolAcceptsZeroOne;
    [Test] procedure TestReadBoolUnknownReturnsDefault;

    { Comment / blank-line preservation. }
    [Test] procedure TestCommentLinePreservedAcrossSave;
    [Test] procedure TestBlankLinePreservedAcrossSave;
    [Test] procedure TestSectionOrderPreserved;

    { Section / key management. }
    [Test] procedure TestReadSectionsLowestToHighest;
    [Test] procedure TestReadSectionListsKeysInSection;
    [Test] procedure TestValueExistsTrueAndFalse;
    [Test] procedure TestSectionExistsTrueAndFalse;
    [Test] procedure TestDeleteKeyRemovesIt;
    [Test] procedure TestEraseSectionRemovesHeaderAndKeys;
    [Test] procedure TestClearWipesEverything;

    { Insertion behaviour. }
    [Test] procedure TestNewKeyInExistingSectionAppendsThere;
    [Test] procedure TestNewSectionAppendsToEnd;
    [Test] procedure TestExistingKeyOverwriteKeepsPosition;

    { Duplicate handling. }
    [Test] procedure TestDuplicateSectionFirstWins;
    [Test] procedure TestDuplicateKeyFirstWins;

    { Edge cases. }
    [Test] procedure TestMissingFileGivesEmptyDocument;
    [Test] procedure TestEmptyPathSaveSilentlyNoOp;
    [Test] procedure TestSemicolonAtLineStartIsComment;
    [Test] procedure TestEqualsAtColumnOneIsCommentLike;
    {Destructor must not auto-flush: writes are lost if UpdateFile is
     not called. Pin the explicit-flush contract callers depend on.}
    [Test] procedure TestDestroyWithoutUpdateFile_DoesNotFlush;
    {Substitution: TUnicodeIniFile must be usable through a
     TCustomIniFile reference — Write/Read round-trip via the base
     reference proves every abstract member is overridden correctly.}
    [Test] procedure TestSubstitutesAsTCustomIniFile;
    {Pin the "Key=Value" emission format of ReadSectionValues.}
    [Test] procedure TestReadSectionValuesEmitsKeyEqualsValuePairs;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles,
  uUnicodeIniFile;

procedure TTestUnicodeIniFile.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'glimpse_uini_' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestUnicodeIniFile.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

{ DecodeIniBytes }

procedure TTestUnicodeIniFile.TestDecodeEmptyReturnsEmpty;
var
  B: TBytes;
begin
  SetLength(B, 0);
  Assert.AreEqual('', DecodeIniBytes(B));
end;

procedure TTestUnicodeIniFile.TestDecodeUTF8WithBomStripsBom;
var
  Bytes: TBytes;
begin
  { EF BB BF + "abc" → "abc" with no BOM character in the result. }
  SetLength(Bytes, 6);
  Bytes[0] := $EF; Bytes[1] := $BB; Bytes[2] := $BF;
  Bytes[3] := Ord('a'); Bytes[4] := Ord('b'); Bytes[5] := Ord('c');
  Assert.AreEqual('abc', DecodeIniBytes(Bytes));
end;

procedure TTestUnicodeIniFile.TestDecodeUTF16LEWithBom;
var
  Bytes: TBytes;
begin
  { FF FE + "abc" little-endian (each char is two bytes, low first). }
  SetLength(Bytes, 8);
  Bytes[0] := $FF; Bytes[1] := $FE;
  Bytes[2] := Ord('a'); Bytes[3] := 0;
  Bytes[4] := Ord('b'); Bytes[5] := 0;
  Bytes[6] := Ord('c'); Bytes[7] := 0;
  Assert.AreEqual('abc', DecodeIniBytes(Bytes));
end;

procedure TTestUnicodeIniFile.TestDecodeUTF16BEWithBom;
var
  Bytes: TBytes;
begin
  { FE FF + "abc" big-endian (each char is two bytes, high first). }
  SetLength(Bytes, 8);
  Bytes[0] := $FE; Bytes[1] := $FF;
  Bytes[2] := 0; Bytes[3] := Ord('a');
  Bytes[4] := 0; Bytes[5] := Ord('b');
  Bytes[6] := 0; Bytes[7] := Ord('c');
  Assert.AreEqual('abc', DecodeIniBytes(Bytes));
end;

procedure TTestUnicodeIniFile.TestDecodeUTF8WithoutBomViaHeuristic;
var
  Bytes: TBytes;
  Expected: string;
begin
  { "звук" in UTF-8 is D0 B7 D0 B2 D1 83 D0 BA — valid UTF-8 byte
    sequences. The heuristic should pick UTF-8 strict and decode it
    correctly without a BOM. Using #$NNNN escapes (Cyrillic codepoints)
    instead of a string literal so this assertion does not depend on
    the source file's encoding. }
  SetLength(Bytes, 8);
  Bytes[0] := $D0; Bytes[1] := $B7;
  Bytes[2] := $D0; Bytes[3] := $B2;
  Bytes[4] := $D1; Bytes[5] := $83;
  Bytes[6] := $D0; Bytes[7] := $BA;
  Expected := #$0437 + #$0432 + #$0443 + #$043A;
  Assert.AreEqual(Expected, DecodeIniBytes(Bytes));
end;

procedure TTestUnicodeIniFile.TestDecodeAnsiFallbackOnInvalidUTF8;
var
  Bytes: TBytes;
  Decoded: string;
begin
  { 0xC0 alone is an incomplete UTF-8 start byte (claims a 2-byte
    sequence but no continuation follows). Strict UTF-8 must reject;
    the heuristic falls back to ANSI. ANSI decoding never fails — the
    output character depends on the system codepage. We assert only
    that decoding succeeds (returns a non-empty string) since the
    actual codepoint varies across hosts. }
  SetLength(Bytes, 1);
  Bytes[0] := $C0;
  Decoded := DecodeIniBytes(Bytes);
  Assert.AreEqual(1, Length(Decoded), 'ANSI fallback must produce one Char from one byte');
end;

procedure TTestUnicodeIniFile.TestDecodeAsciiUnchanged;
var
  Bytes: TBytes;
begin
  { Pure ASCII decodes identically as UTF-8 (no high bytes to
    distinguish encodings). The heuristic picks UTF-8 strict and
    succeeds. }
  SetLength(Bytes, 5);
  Bytes[0] := Ord('h'); Bytes[1] := Ord('e'); Bytes[2] := Ord('l');
  Bytes[3] := Ord('l'); Bytes[4] := Ord('o');
  Assert.AreEqual('hello', DecodeIniBytes(Bytes));
end;

{ TUnicodeIniFile }

procedure TTestUnicodeIniFile.TestReadStringMissingReturnsDefault;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Assert.AreEqual('fallback', Ini.ReadString('s', 'k', 'fallback'));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestWriteThenReadString;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'k', 'value');
    Assert.AreEqual('value', Ini.ReadString('s', 'k', ''));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestWriteThenReadInteger;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteInteger('s', 'n', 42);
    Assert.AreEqual(42, Ini.ReadInteger('s', 'n', 0));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestUpdateFileRoundTripNoBOM;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
begin
  Path := TPath.Combine(FTempDir, 'rt.ini');
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.WriteString('s', 'k', 'value');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  { File on disk must NOT start with a BOM. The loader's no-BOM
    heuristic re-identifies UTF-8 via strict-decode; for ASCII content
    that never triggers any failure path. }
  Bytes := TFile.ReadAllBytes(Path);
  Assert.IsTrue(Length(Bytes) >= 1);
  Assert.AreNotEqual($EF, Bytes[0],
    'UTF-8 BOM bytes must not appear at the start of the saved file');

  { Read it back — value survives the trip. }
  Ini := TUnicodeIniFile.Create(Path);
  try
    Assert.AreEqual('value', Ini.ReadString('s', 'k', ''));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestPersistsCyrillicLossless;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Section, Key, Value: string;
begin
  { The mojibake bug that motivated this whole unit. After Save and
    reload, Cyrillic must come back identical — no Р·РІСѓРє. Using
    #$NNNN escapes for the same encoding-independence reason as the
    decode test. Section "звук" / key "имя" / value "значение". }
  Section := #$0437 + #$0432 + #$0443 + #$043A;
  Key := #$0438 + #$043C + #$044F;
  Value := #$0437 + #$043D + #$0430 + #$0447 + #$0435 + #$043D + #$0438 + #$0435;
  Path := TPath.Combine(FTempDir, 'cyr.ini');
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.WriteString(Section, Key, Value);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Ini := TUnicodeIniFile.Create(Path);
  try
    Assert.AreEqual(Value, Ini.ReadString(Section, Key, ''));
  finally
    Ini.Free;
  end;
end;

{ Lenient ReadBool }

procedure TTestUnicodeIniFile.TestReadBoolAcceptsTrueLowercase;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'k', 'true');
    Assert.IsTrue(Ini.ReadBool('s', 'k', False));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestReadBoolAcceptsYesNoOnOff;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'a', 'YES');
    Ini.WriteString('s', 'b', 'No');
    Ini.WriteString('s', 'c', 'on');
    Ini.WriteString('s', 'd', 'OFF');
    Assert.IsTrue(Ini.ReadBool('s', 'a', False));
    Assert.IsFalse(Ini.ReadBool('s', 'b', True));
    Assert.IsTrue(Ini.ReadBool('s', 'c', False));
    Assert.IsFalse(Ini.ReadBool('s', 'd', True));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestReadBoolAcceptsZeroOne;
var
  Ini: TUnicodeIniFile;
begin
  { Backwards-compat with TIniFile-written values (0/1 only). }
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'a', '1');
    Ini.WriteString('s', 'b', '0');
    Assert.IsTrue(Ini.ReadBool('s', 'a', False));
    Assert.IsFalse(Ini.ReadBool('s', 'b', True));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestReadBoolUnknownReturnsDefault;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'k', 'maybe');
    Assert.IsTrue(Ini.ReadBool('s', 'k', True), 'Unknown value returns default (True)');
    Assert.IsFalse(Ini.ReadBool('s', 'k', False), 'Unknown value returns default (False)');
  finally
    Ini.Free;
  end;
end;

{ Comment and blank-line preservation }

procedure TTestUnicodeIniFile.TestCommentLinePreservedAcrossSave;
var
  Path, Body: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
begin
  { Hand-written file with a leading comment. Read, modify a value, save:
    the comment must still be there in the output. Drives the "this
    unit exists for hand-editable INIs" use case. }
  Bytes := TEncoding.UTF8.GetBytes(
    '; my header comment'#13#10 +
    '[s]'#13#10 +
    'k=before'#13#10);
  Path := TPath.Combine(FTempDir, 'comment.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.WriteString('s', 'k', 'after');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Body := TFile.ReadAllText(Path);
  Assert.IsTrue(Body.Contains('; my header comment'),
    'Comment must survive read-modify-write');
  Assert.IsTrue(Body.Contains('k=after'));
end;

procedure TTestUnicodeIniFile.TestBlankLinePreservedAcrossSave;
var
  Path, Body: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
  Lines: TStringList;
  BlankCount, I: Integer;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '[a]'#13#10 +
    'k=1'#13#10 +
    ''#13#10 +
    '[b]'#13#10 +
    'k=2'#13#10);
  Path := TPath.Combine(FTempDir, 'blank.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.WriteString('a', 'k', '99');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Body := TFile.ReadAllText(Path);
  Lines := TStringList.Create;
  try
    Lines.Text := Body;
    BlankCount := 0;
    for I := 0 to Lines.Count - 1 do
      if Trim(Lines[I]) = '' then
        Inc(BlankCount);
    Assert.IsTrue(BlankCount >= 1, 'At least one blank line must survive');
  finally
    Lines.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestSectionOrderPreserved;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
  Sections: TStringList;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '[zeta]'#13#10 + 'k=1'#13#10 +
    '[alpha]'#13#10 + 'k=2'#13#10 +
    '[mid]'#13#10 + 'k=3'#13#10);
  Path := TPath.Combine(FTempDir, 'order.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    Assert.AreEqual('zeta', Sections[0]);
    Assert.AreEqual('alpha', Sections[1]);
    Assert.AreEqual('mid', Sections[2]);
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

{ Section / key management }

procedure TTestUnicodeIniFile.TestReadSectionsLowestToHighest;
var
  Ini: TUnicodeIniFile;
  Sections: TStringList;
begin
  Ini := TUnicodeIniFile.Create('');
  Sections := TStringList.Create;
  try
    Ini.WriteString('a', 'k', 'v');
    Ini.WriteString('b', 'k', 'v');
    Ini.ReadSections(Sections);
    Assert.AreEqual(2, Sections.Count);
    Assert.AreEqual('a', Sections[0]);
    Assert.AreEqual('b', Sections[1]);
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestReadSectionListsKeysInSection;
var
  Ini: TUnicodeIniFile;
  Keys: TStringList;
begin
  Ini := TUnicodeIniFile.Create('');
  Keys := TStringList.Create;
  try
    Ini.WriteString('s', 'first', '1');
    Ini.WriteString('s', 'second', '2');
    Ini.WriteString('other', 'noise', '0');
    Ini.ReadSection('s', Keys);
    Assert.AreEqual(2, Keys.Count);
    Assert.AreEqual('first', Keys[0]);
    Assert.AreEqual('second', Keys[1]);
  finally
    Keys.Free;
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestValueExistsTrueAndFalse;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'present', 'v');
    Assert.IsTrue(Ini.ValueExists('s', 'present'));
    Assert.IsFalse(Ini.ValueExists('s', 'absent'));
    Assert.IsFalse(Ini.ValueExists('no_such_section', 'present'));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestSectionExistsTrueAndFalse;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'k', 'v');
    Assert.IsTrue(Ini.SectionExists('s'));
    Assert.IsFalse(Ini.SectionExists('nope'));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestDeleteKeyRemovesIt;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'k', 'v');
    Assert.IsTrue(Ini.ValueExists('s', 'k'));
    Ini.DeleteKey('s', 'k');
    Assert.IsFalse(Ini.ValueExists('s', 'k'));
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestEraseSectionRemovesHeaderAndKeys;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'a', '1');
    Ini.WriteString('s', 'b', '2');
    Ini.WriteString('keep', 'k', 'v');
    Ini.EraseSection('s');
    Assert.IsFalse(Ini.SectionExists('s'));
    Assert.IsFalse(Ini.ValueExists('s', 'a'));
    Assert.IsTrue(Ini.SectionExists('keep'), 'Other sections must survive');
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestClearWipesEverything;
var
  Ini: TUnicodeIniFile;
  Sections: TStringList;
begin
  Ini := TUnicodeIniFile.Create('');
  Sections := TStringList.Create;
  try
    Ini.WriteString('a', 'k', 'v');
    Ini.WriteString('b', 'k', 'v');
    Ini.Clear;
    Ini.ReadSections(Sections);
    Assert.AreEqual(0, Sections.Count);
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

{ Insertion behaviour }

procedure TTestUnicodeIniFile.TestNewKeyInExistingSectionAppendsThere;
var
  Ini: TUnicodeIniFile;
  Keys: TStringList;
begin
  { When a key is added to an existing section, it goes at the END of
    that section, not at the end of the file. Critical for keeping
    related keys grouped after a partial update. }
  Ini := TUnicodeIniFile.Create('');
  Keys := TStringList.Create;
  try
    Ini.WriteString('a', 'k1', '1');
    Ini.WriteString('b', 'k1', '1');
    Ini.WriteString('a', 'k2', '2');
    Ini.ReadSection('a', Keys);
    Assert.AreEqual(2, Keys.Count);
    Assert.AreEqual('k1', Keys[0]);
    Assert.AreEqual('k2', Keys[1]);
  finally
    Keys.Free;
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestNewSectionAppendsToEnd;
var
  Ini: TUnicodeIniFile;
  Sections: TStringList;
begin
  Ini := TUnicodeIniFile.Create('');
  Sections := TStringList.Create;
  try
    Ini.WriteString('a', 'k', 'v');
    Ini.WriteString('b', 'k', 'v');
    Ini.WriteString('c', 'k', 'v');
    Ini.ReadSections(Sections);
    Assert.AreEqual('c', Sections[2], 'Newly added section lands at the end');
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestExistingKeyOverwriteKeepsPosition;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
  Body: string;
  IdxK1, IdxK2: Integer;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '[s]'#13#10 +
    'k1=before'#13#10 +
    'k2=other'#13#10);
  Path := TPath.Combine(FTempDir, 'overwrite.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.WriteString('s', 'k1', 'after');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Body := TFile.ReadAllText(Path);
  IdxK1 := Pos('k1=after', Body);
  IdxK2 := Pos('k2=other', Body);
  Assert.IsTrue(IdxK1 > 0, 'k1 must persist with new value');
  Assert.IsTrue(IdxK1 < IdxK2, 'k1 must keep its position before k2');
end;

{ Duplicate handling }

procedure TTestUnicodeIniFile.TestDuplicateSectionFirstWins;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
  Sections: TStringList;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '[s]'#13#10 +
    'k=first'#13#10 +
    '[s]'#13#10 +
    'k=second'#13#10);
  Path := TPath.Combine(FTempDir, 'dupe_section.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    Assert.AreEqual(1, Sections.Count, 'Duplicate section header is ignored');
    Assert.AreEqual('first', Ini.ReadString('s', 'k', ''),
      'First-occurrence key wins');
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestDuplicateKeyFirstWins;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '[s]'#13#10 +
    'k=first'#13#10 +
    'k=second'#13#10);
  Path := TPath.Combine(FTempDir, 'dupe_key.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  try
    Assert.AreEqual('first', Ini.ReadString('s', 'k', ''));
  finally
    Ini.Free;
  end;
end;

{ Edge cases }

procedure TTestUnicodeIniFile.TestMissingFileGivesEmptyDocument;
var
  Ini: TUnicodeIniFile;
  Sections: TStringList;
begin
  Ini := TUnicodeIniFile.Create(TPath.Combine(FTempDir, 'no_such.ini'));
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    Assert.AreEqual(0, Sections.Count);
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestEmptyPathSaveSilentlyNoOp;
var
  Ini: TUnicodeIniFile;
begin
  Ini := TUnicodeIniFile.Create('');
  try
    Ini.WriteString('s', 'k', 'v');
    Ini.UpdateFile;
    Assert.Pass('No exception');
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestSemicolonAtLineStartIsComment;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
  Body: string;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '[s]'#13#10 +
    '; this is a comment'#13#10 +
    'k=v'#13#10);
  Path := TPath.Combine(FTempDir, 'sc.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  try
    Assert.AreEqual('v', Ini.ReadString('s', 'k', ''));
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Body := TFile.ReadAllText(Path);
  Assert.IsTrue(Body.Contains('; this is a comment'));
end;

procedure TTestUnicodeIniFile.TestEqualsAtColumnOneIsCommentLike;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Bytes: TBytes;
  Body: string;
begin
  { A line starting with '=' has no key — treat as a non-key line and
    preserve verbatim so a hand-written file does not silently lose it.
    TIniFile would behave erratically; we choose deterministic preserve. }
  Bytes := TEncoding.UTF8.GetBytes(
    '[s]'#13#10 +
    '=stranded'#13#10);
  Path := TPath.Combine(FTempDir, 'eq.ini');
  TFile.WriteAllBytes(Path, Bytes);
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
  Body := TFile.ReadAllText(Path);
  Assert.IsTrue(Body.Contains('=stranded'),
    'Unparseable line preserved verbatim');
end;

procedure TTestUnicodeIniFile.TestSubstitutesAsTCustomIniFile;
var
  Path: string;
  Concrete: TUnicodeIniFile;
  Base: TCustomIniFile;
begin
  {Construct as TUnicodeIniFile, assign to a TCustomIniFile reference,
   exercise the abstract API through that reference. Every Read/Write
   the base declares must dispatch into the line-list model via our
   override; the round-trip is the substitution proof.}
  Path := TPath.Combine(FTempDir, 'subst.ini');
  Concrete := TUnicodeIniFile.Create(Path);
  try
    Base := Concrete;
    Base.WriteString('s', 'k1', 'via-base');
    Base.WriteInteger('s', 'n', 42);
    Base.WriteBool('s', 'b', True);

    Assert.AreEqual('via-base', Base.ReadString('s', 'k1', ''),
      'String written through TCustomIniFile ref must round-trip');
    Assert.AreEqual<Integer>(42, Base.ReadInteger('s', 'n', 0));
    Assert.IsTrue(Base.ReadBool('s', 'b', False));

    Assert.IsTrue(Base.SectionExists('s'), 'SectionExists via base ref');
    Assert.IsTrue(Base.ValueExists('s', 'k1'), 'ValueExists via base ref');

    Base.DeleteKey('s', 'n');
    Assert.IsFalse(Base.ValueExists('s', 'n'), 'DeleteKey via base ref');

    Base.EraseSection('s');
    Assert.IsFalse(Base.SectionExists('s'), 'EraseSection via base ref');
  finally
    Concrete.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestReadSectionValuesEmitsKeyEqualsValuePairs;
var
  Path: string;
  Ini: TUnicodeIniFile;
  Pairs: TStringList;
begin
  Path := TPath.Combine(FTempDir, 'rsv.ini');
  Ini := TUnicodeIniFile.Create(Path);
  try
    Ini.WriteString('audio', 'codec', 'aac');
    Ini.WriteInteger('audio', 'rate', 48000);
    Pairs := TStringList.Create;
    try
      Ini.ReadSectionValues('audio', Pairs);
      Assert.AreEqual<Integer>(2, Pairs.Count,
        'ReadSectionValues emits one line per key');
      Assert.AreEqual('codec=aac', Pairs[0]);
      Assert.AreEqual('rate=48000', Pairs[1]);
    finally
      Pairs.Free;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TTestUnicodeIniFile.TestDestroyWithoutUpdateFile_DoesNotFlush;
var
  Path: string;
  Writer, Reader: TUnicodeIniFile;
begin
  Path := TPath.Combine(FTempDir, 'no_flush_on_destroy.ini');
  {Sanity: file does not exist yet.}
  Assert.IsFalse(TFile.Exists(Path), 'Pre-condition: target file absent');

  Writer := TUnicodeIniFile.Create(Path);
  try
    Writer.WriteString('test', 'transient', 'should-not-persist');
    {Deliberately do NOT call UpdateFile.}
  finally
    Writer.Free;
  end;

  {Pins the explicit-flush contract: Free without UpdateFile must
   leave the disk untouched. The caller owns the flush — Destroy
   does not auto-write.}
  Assert.IsFalse(TFile.Exists(Path),
    'Destroy must not write to disk when UpdateFile was never called');

  {Belt-and-braces: a follow-up reader on the same path sees no key
   either, confirming the absence of disk state.}
  Reader := TUnicodeIniFile.Create(Path);
  try
    Assert.AreEqual('absent', Reader.ReadString('test', 'transient', 'absent'),
      'Reader must see the documented default — the prior writer''s value never persisted');
  finally
    Reader.Free;
  end;
end;

end.
