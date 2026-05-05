unit TestWcxPresets;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxPresets = class
  private
    FTempDir: string;
    function WriteIni(const AFileName, AContent: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    { Loading }
    [Test] procedure TestLoadMissingFileReturnsEmpty;
    [Test] procedure TestLoadEmptyFileReturnsEmpty;
    [Test] procedure TestLoadSinglePresetMinimalFields;
    [Test] procedure TestLoadDisabledPresetSkipped;
    [Test] procedure TestLoadEnabledDefaultsToTrue;
    [Test] procedure TestLoadOutputExtMissingSkipped;
    [Test] procedure TestLoadOutputExtLeadingDotStripped;
    [Test] procedure TestLoadOutputExtPathSeparatorRejected;
    [Test] procedure TestLoadOutputNamePathSeparatorRejected;
    [Test] procedure TestLoadEmptyArgsAccepted;
    [Test] procedure TestLoadForbiddenInputFlagSkipped;
    [Test] procedure TestLoadForbiddenOverwriteFlagsSkipped;
    [Test] procedure TestLoadForbiddenPipeTokensSkipped;
    [Test] procedure TestLoadMixedValidAndInvalidPreservesValid;
    [Test] procedure TestLoadDescriptionDefaultsEmpty;
    [Test] procedure TestLoadPreservesSectionOrder;

    { Tokeniser }
    [Test] procedure TestTokenizeEmpty;
    [Test] procedure TestTokenizeWhitespaceSplit;
    [Test] procedure TestTokenizeRespectsDoubleQuotes;
    [Test] procedure TestTokenizeStripsQuoteCharacters;
    [Test] procedure TestTokenizeCollapsesMultipleSpaces;
    [Test] procedure TestTokenizeAcceptsTabsAsSeparators;

    { Validation }
    [Test] procedure TestValidateEmptyAccepted;
    [Test] procedure TestValidateRejectsLowerInput;
    [Test] procedure TestValidateRejectsUpperInput;
    [Test] procedure TestValidateRejectsOverwriteFlags;
    [Test] procedure TestValidateRejectsAllPipeChannels;
    [Test] procedure TestValidateAcceptsLookalikeFlags;
    [Test] procedure TestValidateRejectsQuotedForbiddenToken;

    { Template expansion }
    [Test] procedure TestExpandBasename;
    [Test] procedure TestExpandPresetName;
    [Test] procedure TestExpandExtensionLowercased;
    [Test] procedure TestExpandAllVariablesTogether;
    [Test] procedure TestExpandUnknownVariableUntouched;
    [Test] procedure TestExpandFileWithoutExtension;
    [Test] procedure TestExpandUnicodeFileName;

    { BuildOutputFileName }
    [Test] procedure TestBuildOutputUsesDefaultTemplateWhenEmpty;
    [Test] procedure TestBuildOutputHonoursCustomTemplate;
    [Test] procedure TestBuildOutputAppendsSingleDottedExtension;

    { Deduplication }
    [Test] procedure TestDedupeEmptyInput;
    [Test] procedure TestDedupeNoCollisionsUnchanged;
    [Test] procedure TestDedupeTwoWayCollision;
    [Test] procedure TestDedupeThreeWayCollision;
    [Test] procedure TestDedupeSkipsLiteralOccupiedSlot;
    [Test] procedure TestDedupeIsCaseInsensitive;
    [Test] procedure TestDedupeNamesWithoutExtension;

    { Path derivation }
    [Test] procedure TestPresetsIniPathSiblingOfSettings;
    [Test] procedure TestPresetsIniPathEmptyInputReturnsEmpty;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  uWcxPresets;

{ Helpers }

function TTestWcxPresets.WriteIni(const AFileName, AContent: string): string;
var
  Bytes: TBytes;
begin
  Result := TPath.Combine(FTempDir, AFileName);
  { Write as plain ANSI bytes — TIniFile reads either ANSI or UTF-16 depending
    on a BOM, and the test content is ASCII-only. Using TFile.WriteAllText with
    TEncoding.UTF8 would emit a BOM that biases TIniFile's Unicode detection
    and is unnecessary noise for these tests. }
  Bytes := TEncoding.ANSI.GetBytes(AContent);
  TFile.WriteAllBytes(Result, Bytes);
end;

procedure TTestWcxPresets.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'glimpse_wcxpresets_' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestWcxPresets.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

{ Loading }

procedure TTestWcxPresets.TestLoadMissingFileReturnsEmpty;
var
  Presets: TWcxPresetArray;
begin
  Presets := LoadPresets(TPath.Combine(FTempDir, 'nope.ini'));
  Assert.AreEqual(0, Integer(Length(Presets)), 'Missing file must return empty array, not raise');
end;

procedure TTestWcxPresets.TestLoadEmptyFileReturnsEmpty;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('empty.ini', '');
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)));
end;

procedure TTestWcxPresets.TestLoadSinglePresetMinimalFields;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('single.ini',
    '[audio_mp3]'#13#10 +
    'OutputExt=mp3'#13#10 +
    'Args=-vn -c:a libmp3lame -q:a 4'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)));
  Assert.AreEqual('audio_mp3', Presets[0].Name);
  Assert.AreEqual('mp3', Presets[0].OutputExt);
  Assert.AreEqual('-vn -c:a libmp3lame -q:a 4', Presets[0].Args);
  Assert.IsTrue(Presets[0].Enabled, 'Enabled defaults to True when key absent');
  Assert.AreEqual('', Presets[0].OutputName, 'OutputName left empty when not specified');
end;

procedure TTestWcxPresets.TestLoadDisabledPresetSkipped;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('disabled.ini',
    '[a]'#13#10 +
    'Enabled=False'#13#10 +
    'OutputExt=mp3'#13#10 +
    '[b]'#13#10 +
    'OutputExt=mp4'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)), 'Disabled preset must be skipped at load');
  Assert.AreEqual('b', Presets[0].Name);
end;

procedure TTestWcxPresets.TestLoadEnabledDefaultsToTrue;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('endef.ini',
    '[a]'#13#10 +
    'OutputExt=mp3'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)));
  Assert.IsTrue(Presets[0].Enabled);
end;

procedure TTestWcxPresets.TestLoadOutputExtMissingSkipped;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('noext.ini',
    '[a]'#13#10 +
    'Args=-vn'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)), 'OutputExt is required');
end;

procedure TTestWcxPresets.TestLoadOutputExtLeadingDotStripped;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('dotext.ini',
    '[a]'#13#10 +
    'OutputExt=.mp3'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)));
  Assert.AreEqual('mp3', Presets[0].OutputExt,
    'Leading dot must be normalised away so BuildOutputFileName never produces double dots');
end;

procedure TTestWcxPresets.TestLoadOutputExtPathSeparatorRejected;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('badext.ini',
    '[a]'#13#10 +
    'OutputExt=mp3\evil'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)),
    'Path separators in OutputExt would let presets escape the destination dir');
end;

procedure TTestWcxPresets.TestLoadOutputNamePathSeparatorRejected;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('badname.ini',
    '[a]'#13#10 +
    'OutputExt=mp3'#13#10 +
    'OutputName=..\..\evil'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)));
end;

procedure TTestWcxPresets.TestLoadEmptyArgsAccepted;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  { Empty Args means "let ffmpeg pick default codec from OutputExt".
    A meaningful, well-defined preset shape, must not be rejected. }
  Path := WriteIni('emptyargs.ini',
    '[autotrans]'#13#10 +
    'OutputExt=mp4'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)));
  Assert.AreEqual('', Presets[0].Args);
end;

procedure TTestWcxPresets.TestLoadForbiddenInputFlagSkipped;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('badi.ini',
    '[a]'#13#10 +
    'OutputExt=mp4'#13#10 +
    'Args=-i other.mkv -c copy'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)),
    '-i would override the input file the extractor injects, must be rejected');
end;

procedure TTestWcxPresets.TestLoadForbiddenOverwriteFlagsSkipped;
var
  Path: string;
  PresetsY, PresetsN: TWcxPresetArray;
begin
  Path := WriteIni('bady.ini',
    '[a]'#13#10 +
    'OutputExt=mp4'#13#10 +
    'Args=-y -c copy'#13#10);
  PresetsY := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(PresetsY)), '-y conflicts with tempfile-and-rename overwrite policy');

  Path := WriteIni('badn.ini',
    '[a]'#13#10 +
    'OutputExt=mp4'#13#10 +
    'Args=-n -c copy'#13#10);
  PresetsN := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(PresetsN)), '-n likewise overrides extractor-managed overwrite');
end;

procedure TTestWcxPresets.TestLoadForbiddenPipeTokensSkipped;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('badpipe.ini',
    '[a]'#13#10 +
    'OutputExt=mp4'#13#10 +
    'Args=-c copy pipe:1'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)),
    'pipe:1 would clash with the -progress channel the extractor uses');
end;

procedure TTestWcxPresets.TestLoadMixedValidAndInvalidPreservesValid;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('mix.ini',
    '[good_a]'#13#10 +
    'OutputExt=mp3'#13#10 +
    'Args=-vn'#13#10 +
    '[bad_input]'#13#10 +
    'OutputExt=mp4'#13#10 +
    'Args=-i other.mkv'#13#10 +
    '[good_b]'#13#10 +
    'OutputExt=jpg'#13#10 +
    'Args=-frames:v 1'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(2, Integer(Length(Presets)), 'Bad section must not poison the rest of the file');
  Assert.AreEqual('good_a', Presets[0].Name);
  Assert.AreEqual('good_b', Presets[1].Name);
end;

procedure TTestWcxPresets.TestLoadDescriptionDefaultsEmpty;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('desc.ini',
    '[a]'#13#10 +
    'OutputExt=mp3'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual('', Presets[0].Description);
end;

procedure TTestWcxPresets.TestLoadPreservesSectionOrder;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  { Listing order is user-visible (TC shows entries in iteration order) and
    drives dedupe priority (first-defined wins the bare name). Pin it. }
  Path := WriteIni('order.ini',
    '[zeta]'#13#10 +
    'OutputExt=mp3'#13#10 +
    '[alpha]'#13#10 +
    'OutputExt=mp3'#13#10 +
    '[mid]'#13#10 +
    'OutputExt=mp3'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(3, Integer(Length(Presets)));
  Assert.AreEqual('zeta', Presets[0].Name);
  Assert.AreEqual('alpha', Presets[1].Name);
  Assert.AreEqual('mid', Presets[2].Name);
end;

{ Tokeniser }

procedure TTestWcxPresets.TestTokenizeEmpty;
begin
  Assert.AreEqual(0, Integer(Length(TokenizeArgs(''))));
  Assert.AreEqual(0, Integer(Length(TokenizeArgs('   '))));
end;

procedure TTestWcxPresets.TestTokenizeWhitespaceSplit;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('-vn -c:a libmp3lame');
  Assert.AreEqual(3, Integer(Length(Tokens)));
  Assert.AreEqual('-vn', Tokens[0]);
  Assert.AreEqual('-c:a', Tokens[1]);
  Assert.AreEqual('libmp3lame', Tokens[2]);
end;

procedure TTestWcxPresets.TestTokenizeRespectsDoubleQuotes;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('-metadata "title=My Movie" -y');
  Assert.AreEqual(3, Integer(Length(Tokens)));
  Assert.AreEqual('-metadata', Tokens[0]);
  Assert.AreEqual('title=My Movie', Tokens[1]);
  Assert.AreEqual('-y', Tokens[2]);
end;

procedure TTestWcxPresets.TestTokenizeStripsQuoteCharacters;
var
  Tokens: TArray<string>;
begin
  { Quotes are syntax, not data — they must not survive into the token,
    or downstream comparisons (e.g. validation) would never match. }
  Tokens := TokenizeArgs('"-y"');
  Assert.AreEqual(1, Integer(Length(Tokens)));
  Assert.AreEqual('-y', Tokens[0]);
end;

procedure TTestWcxPresets.TestTokenizeCollapsesMultipleSpaces;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('  a    b  c  ');
  Assert.AreEqual(3, Integer(Length(Tokens)));
  Assert.AreEqual('a', Tokens[0]);
  Assert.AreEqual('b', Tokens[1]);
  Assert.AreEqual('c', Tokens[2]);
end;

procedure TTestWcxPresets.TestTokenizeAcceptsTabsAsSeparators;
var
  Tokens: TArray<string>;
begin
  Tokens := TokenizeArgs('a'#9'b'#9#9'c');
  Assert.AreEqual(3, Integer(Length(Tokens)));
end;

{ Validation }

procedure TTestWcxPresets.TestValidateEmptyAccepted;
var
  Reason: string;
begin
  Assert.IsTrue(ValidatePresetArgs('', Reason));
  Assert.AreEqual('', Reason);
end;

procedure TTestWcxPresets.TestValidateRejectsLowerInput;
var
  Reason: string;
begin
  Assert.IsFalse(ValidatePresetArgs('-i other.mkv', Reason));
  Assert.IsTrue(Reason <> '');
end;

procedure TTestWcxPresets.TestValidateRejectsUpperInput;
var
  Reason: string;
begin
  { Case-insensitive flag matching guards against the user trying to slip
    a forbidden flag past via capitalisation. }
  Assert.IsFalse(ValidatePresetArgs('-I other.mkv', Reason));
end;

procedure TTestWcxPresets.TestValidateRejectsOverwriteFlags;
var
  Reason: string;
begin
  Assert.IsFalse(ValidatePresetArgs('-y', Reason), '-y must be rejected');
  Assert.IsFalse(ValidatePresetArgs('-n', Reason), '-n must be rejected');
end;

procedure TTestWcxPresets.TestValidateRejectsAllPipeChannels;
var
  Reason: string;
begin
  Assert.IsFalse(ValidatePresetArgs('pipe:0', Reason));
  Assert.IsFalse(ValidatePresetArgs('pipe:1', Reason));
  Assert.IsFalse(ValidatePresetArgs('pipe:2', Reason));
end;

procedure TTestWcxPresets.TestValidateAcceptsLookalikeFlags;
var
  Reason: string;
begin
  { Tokenisation is exact; a longer flag that merely starts with "-i" must
    not trip the rule because ffmpeg sees a different option entirely. }
  Assert.IsTrue(ValidatePresetArgs('-init_hw_device cuda', Reason));
  Assert.IsTrue(ValidatePresetArgs('pipe:3', Reason),
    'Only pipe:0/1/2 are stdio; higher channels are inert and must pass');
end;

procedure TTestWcxPresets.TestValidateRejectsQuotedForbiddenToken;
var
  Reason: string;
begin
  { Quoting "-y" doesn't change what ffmpeg receives — the tokeniser strips
    the quotes and the rule still fires. }
  Assert.IsFalse(ValidatePresetArgs('"-y"', Reason));
end;

{ Template expansion }

procedure TTestWcxPresets.TestExpandBasename;
begin
  Assert.AreEqual('Movie',
    ExpandTemplate('%basename%', 'C:\videos\Movie.mkv', 'p'));
end;

procedure TTestWcxPresets.TestExpandPresetName;
begin
  Assert.AreEqual('audio',
    ExpandTemplate('%name%', 'C:\videos\Movie.mkv', 'audio'));
end;

procedure TTestWcxPresets.TestExpandExtensionLowercased;
begin
  { Lowercasing prevents the same source-with-different-case (Movie.MKV vs
    Movie.mkv) producing different listings on a case-insensitive filesystem. }
  Assert.AreEqual('mkv',
    ExpandTemplate('%ext%', 'C:\videos\Movie.MKV', 'p'));
end;

procedure TTestWcxPresets.TestExpandAllVariablesTogether;
begin
  Assert.AreEqual('Movie_audio.mkv',
    ExpandTemplate('%basename%_%name%.%ext%', 'C:\videos\Movie.mkv', 'audio'));
end;

procedure TTestWcxPresets.TestExpandUnknownVariableUntouched;
begin
  { Forward-compat: future template tokens added later must not break old
    presets. Untouched tokens are surface noise, not crashes. }
  Assert.AreEqual('%duration%',
    ExpandTemplate('%duration%', 'C:\videos\Movie.mkv', 'p'));
end;

procedure TTestWcxPresets.TestExpandFileWithoutExtension;
begin
  Assert.AreEqual('README_',
    ExpandTemplate('%basename%_%ext%', 'C:\docs\README', 'p'));
end;

procedure TTestWcxPresets.TestExpandUnicodeFileName;
begin
  Assert.AreEqual('фильм',
    ExpandTemplate('%basename%', 'C:\кино\фильм.mkv', 'p'));
end;

{ BuildOutputFileName }

procedure TTestWcxPresets.TestBuildOutputUsesDefaultTemplateWhenEmpty;
var
  P: TWcxPreset;
begin
  P := Default(TWcxPreset);
  P.Name := 'audio';
  P.OutputExt := 'mp3';
  P.OutputName := '';
  Assert.AreEqual('Movie_audio.mp3', BuildOutputFileName(P, 'C:\videos\Movie.mkv'));
end;

procedure TTestWcxPresets.TestBuildOutputHonoursCustomTemplate;
var
  P: TWcxPreset;
begin
  P := Default(TWcxPreset);
  P.Name := 'audio';
  P.OutputExt := 'mp3';
  P.OutputName := 'audio_only_%basename%';
  Assert.AreEqual('audio_only_Movie.mp3', BuildOutputFileName(P, 'C:\videos\Movie.mkv'));
end;

procedure TTestWcxPresets.TestBuildOutputAppendsSingleDottedExtension;
var
  P: TWcxPreset;
  Result: string;
begin
  { The single-dot rule lets the loader's leading-dot strip on OutputExt
    be the only place that boundary is enforced; BuildOutputFileName must
    never produce ".." or omit the dot. }
  P := Default(TWcxPreset);
  P.Name := 'p';
  P.OutputExt := 'mp4';
  P.OutputName := 'foo';
  Result := BuildOutputFileName(P, 'C:\v\x.mkv');
  Assert.AreEqual('foo.mp4', Result);
end;

{ Deduplication }

procedure TTestWcxPresets.TestDedupeEmptyInput;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames([]);
  Assert.AreEqual(0, Integer(Length(Out_)));
end;

procedure TTestWcxPresets.TestDedupeNoCollisionsUnchanged;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['a.jpg', 'b.jpg', 'c.png']);
  Assert.AreEqual(3, Integer(Length(Out_)));
  Assert.AreEqual('a.jpg', Out_[0]);
  Assert.AreEqual('b.jpg', Out_[1]);
  Assert.AreEqual('c.png', Out_[2]);
end;

procedure TTestWcxPresets.TestDedupeTwoWayCollision;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['poster.jpg', 'poster.jpg']);
  Assert.AreEqual('poster.jpg', Out_[0], 'First-defined keeps bare name');
  Assert.AreEqual('poster(2).jpg', Out_[1]);
end;

procedure TTestWcxPresets.TestDedupeThreeWayCollision;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['poster.jpg', 'poster.jpg', 'poster.jpg']);
  Assert.AreEqual('poster.jpg', Out_[0]);
  Assert.AreEqual('poster(2).jpg', Out_[1]);
  Assert.AreEqual('poster(3).jpg', Out_[2]);
end;

procedure TTestWcxPresets.TestDedupeSkipsLiteralOccupiedSlot;
var
  Out_: TArray<string>;
begin
  { Literal "poster(2).jpg" is taken first; the natural collision suffix
    must increment past it. Order of definition matters: first-defined
    keeps the literal, the auto-deduped entry shifts to (3). }
  Out_ := DeduplicateFileNames(['poster(2).jpg', 'poster.jpg', 'poster.jpg']);
  Assert.AreEqual('poster(2).jpg', Out_[0]);
  Assert.AreEqual('poster.jpg', Out_[1]);
  Assert.AreEqual('poster(3).jpg', Out_[2],
    'Auto-dedupe must skip the literal (2) slot and land on (3)');
end;

procedure TTestWcxPresets.TestDedupeIsCaseInsensitive;
var
  Out_: TArray<string>;
begin
  { Windows treats "Poster.jpg" and "poster.jpg" as the same file, so the
    listing must, too — otherwise extracting both back-to-back would
    overwrite the first silently. }
  Out_ := DeduplicateFileNames(['Poster.jpg', 'poster.jpg']);
  Assert.AreEqual('Poster.jpg', Out_[0]);
  Assert.AreEqual('poster(2).jpg', Out_[1]);
end;

procedure TTestWcxPresets.TestDedupeNamesWithoutExtension;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['foo', 'foo']);
  Assert.AreEqual('foo', Out_[0]);
  Assert.AreEqual('foo(2)', Out_[1]);
end;

procedure TTestWcxPresets.TestPresetsIniPathSiblingOfSettings;
begin
  { Flat name in the same directory as the WCX settings INI; using a
    fixed filename rather than ChangeFileExt keeps the path independent
    of whatever name TC ended up giving the settings INI. }
  Assert.AreEqual('C:\plugins\wcx\presets.ini',
    PresetsIniPath('C:\plugins\wcx\Glimpse.ini'));
  Assert.AreEqual('C:\plugins\wcx\presets.ini',
    PresetsIniPath('C:\plugins\wcx\anything-else.ini'));
end;

procedure TTestWcxPresets.TestPresetsIniPathEmptyInputReturnsEmpty;
begin
  { When SetDefaultParams never fired and the settings path is unset, the
    sentinel '' must propagate so callers short-circuit on the documented
    "no presets" condition rather than synthesise a stray "presets.ini"
    in the current working directory. }
  Assert.AreEqual('', PresetsIniPath(''));
end;

end.
