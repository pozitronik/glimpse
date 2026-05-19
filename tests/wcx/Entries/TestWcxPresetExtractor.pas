unit TestWcxPresetExtractor;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxPresetExtractor = class
  public
    { QuoteArg: Microsoft CommandLineToArgvW round-trip rules }
    [Test] procedure TestQuoteArgUnchangedWhenNoSpecials;
    [Test] procedure TestQuoteArgEmptyStringWrapsInQuotes;
    [Test] procedure TestQuoteArgWithSpacesGetsWrapped;
    [Test] procedure TestQuoteArgWithTabGetsWrapped;
    [Test] procedure TestQuoteArgEmbeddedQuoteEscaped;
    [Test] procedure TestQuoteArgBackslashesBeforeQuoteDoubled;
    [Test] procedure TestQuoteArgTrailingBackslashesDoubledBeforeClose;
    [Test] procedure TestQuoteArgBackslashesNotBeforeQuoteUntouched;
    { BuildPresetCmdLine: prefix shape and ordering }
    [Test] procedure TestBuildCmdHasFixedFlagsBeforeInput;
    [Test] procedure TestBuildCmdInjectsInputAfterDashI;
    [Test] procedure TestBuildCmdAppendsTempPathAtEnd;
    [Test] procedure TestBuildCmdQuotesPathsWithSpaces;
    [Test] procedure TestBuildCmdEmptyArgsStillProducesValidLine;
    [Test] procedure TestBuildCmdUserTokensInsertedBetweenInputAndOutput;
    [Test] procedure TestBuildCmdQuotedUserTokenSurvivesRoundTrip;
    { ParseProgressLine: ffmpeg -progress key=value parsing }
    [Test] procedure TestParseProgressOutTimeUsHalfDuration;
    [Test] procedure TestParseProgressOutTimeMsTreatedAsMicroseconds;
    [Test] procedure TestParseProgressEndAlwaysOneHundred;
    [Test] procedure TestParseProgressEndIgnoresZeroDuration;
    [Test] procedure TestParseProgressContinueIsNoise;
    [Test] procedure TestParseProgressUnknownKeyIsNoise;
    [Test] procedure TestParseProgressNAValueIgnored;
    [Test] procedure TestParseProgressNonNumericValueIgnored;
    [Test] procedure TestParseProgressZeroDurationSkipsMetered;
    [Test] procedure TestParseProgressClampsAboveDuration;
    [Test] procedure TestParseProgressClampsNegativeUs;
    [Test] procedure TestParseProgressKeyCaseInsensitive;
    [Test] procedure TestParseProgressMissingEqualsRejected;
    { MakeTempPath: ".tmp" must go BEFORE the extension so ffmpeg's
      container-from-extension inference still works. }
    [Test] procedure TestMakeTempPathInsertsTmpBeforeExtension;
    [Test] procedure TestMakeTempPathHandlesPathWithDirectory;
    [Test] procedure TestMakeTempPathHandlesNoExtension;
    [Test] procedure TestMakeTempPathHandlesMultipleDots;
    { ExtractPreset failure-path coverage. The success path needs a
      live ffmpeg and a sample video; the bad-binary path exercises the
      exception handler + Result.ErrorMessage assembly without any
      external dependencies. }
    [Test] procedure TestExtractPresetBadBinaryReportsLaunchFailure;
  end;

implementation

uses
  System.SysUtils,
  WcxPresets, WcxPresetExtractor;

{ QuoteArg }

procedure TTestWcxPresetExtractor.TestQuoteArgUnchangedWhenNoSpecials;
begin
  Assert.AreEqual('-vn', QuoteArg('-vn'));
  Assert.AreEqual('foo.mp3', QuoteArg('foo.mp3'));
  Assert.AreEqual('libmp3lame', QuoteArg('libmp3lame'));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgEmptyStringWrapsInQuotes;
begin
  { Empty-arg quoting matters when ffmpeg is given an empty-named option
    value: without the explicit "" Windows would lose the slot entirely. }
  Assert.AreEqual('""', QuoteArg(''));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgWithSpacesGetsWrapped;
begin
  Assert.AreEqual('"C:\Program Files\ffmpeg.exe"',
    QuoteArg('C:\Program Files\ffmpeg.exe'));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgWithTabGetsWrapped;
begin
  Assert.AreEqual('"a' + #9 + 'b"', QuoteArg('a' + #9 + 'b'));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgEmbeddedQuoteEscaped;
begin
  { An embedded quote must be backslash-escaped so CommandLineToArgvW
    parses it as data rather than a quote-state toggle. }
  Assert.AreEqual('"a\"b"', QuoteArg('a"b'));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgBackslashesBeforeQuoteDoubled;
begin
  { 1 backslash before " becomes 2 backslashes + escaped quote:
    a\"b  ->  "a\\\"b"  (visualised: a, two backslashes, escaped quote, b) }
  Assert.AreEqual('"a\\\"b"', QuoteArg('a\"b'));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgTrailingBackslashesDoubledBeforeClose;
begin
  { Trailing backslashes inside an arg requiring quotes must double before
    the closing quote — otherwise the closing " gets escaped and the parser
    keeps reading. }
  Assert.AreEqual('"a b\\"', QuoteArg('a b\'));
end;

procedure TTestWcxPresetExtractor.TestQuoteArgBackslashesNotBeforeQuoteUntouched;
begin
  { Plain backslashes that do not precede a quote are literal data and
    must not double — Windows paths would explode otherwise. The path here
    contains a space so quoting kicks in and the rules become observable. }
  Assert.AreEqual('"C:\dir with space\file"',
    QuoteArg('C:\dir with space\file'),
    'Mid-path backslashes stay single inside a quoted arg');
  { Path without spaces takes the no-quote-needed shortcut and passes
    through verbatim — confirms the NeedsQuote gate is doing its job. }
  Assert.AreEqual('C:\dir\sub\',
    QuoteArg('C:\dir\sub\'),
    'Path with no spaces or quotes does not need wrapping');
end;

{ BuildPresetCmdLine }

function MakePreset(const AArgs, AExt: string): TWcxPreset;
begin
  Result := Default(TWcxPreset);
  Result.Name := 'p';
  Result.OutputName := 'p';
  Result.OutputExt := AExt;
  Result.Args := AArgs;
  Result.Enabled := True;
end;

procedure TTestWcxPresetExtractor.TestBuildCmdHasFixedFlagsBeforeInput;
var
  Cmd: string;
begin
  { The fixed prefix order is part of the contract. -progress pipe:1 must
    precede -i so ffmpeg's option parser binds it as a global flag rather
    than an output option. }
  Cmd := BuildPresetCmdLine('ffmpeg.exe', 'in.mkv', MakePreset('', 'mp3'), 'out.mp3.tmp');
  Assert.IsTrue(Pos('-hide_banner', Cmd) > 0);
  Assert.IsTrue(Pos('-nostdin', Cmd) > 0);
  Assert.IsTrue(Pos('-loglevel error', Cmd) > 0);
  Assert.IsTrue(Pos('-progress pipe:1', Cmd) > 0);
  Assert.IsTrue(Pos('-y', Cmd) > 0);
  Assert.IsTrue(Pos('-progress pipe:1', Cmd) < Pos('-i', Cmd),
    '-progress must precede -i so ffmpeg treats it as a global flag');
end;

procedure TTestWcxPresetExtractor.TestBuildCmdInjectsInputAfterDashI;
var
  Cmd: string;
begin
  Cmd := BuildPresetCmdLine('ffmpeg.exe', 'in.mkv', MakePreset('', 'mp3'), 'out.mp3.tmp');
  Assert.IsTrue(Pos('-i in.mkv', Cmd) > 0);
end;

procedure TTestWcxPresetExtractor.TestBuildCmdAppendsTempPathAtEnd;
var
  Cmd: string;
begin
  Cmd := BuildPresetCmdLine('ffmpeg.exe', 'in.mkv', MakePreset('', 'mp3'), 'out.mp3.tmp');
  Assert.IsTrue(Cmd.EndsWith('out.mp3.tmp'));
end;

procedure TTestWcxPresetExtractor.TestBuildCmdQuotesPathsWithSpaces;
var
  Cmd: string;
begin
  Cmd := BuildPresetCmdLine('C:\Program Files\ffmpeg.exe',
    'D:\my movies\clip.mkv', MakePreset('', 'mp3'),
    'D:\my movies\clip.mp3.tmp');
  Assert.IsTrue(Pos('"C:\Program Files\ffmpeg.exe"', Cmd) > 0,
    'Exe path with spaces must be quoted');
  Assert.IsTrue(Pos('"D:\my movies\clip.mkv"', Cmd) > 0,
    'Input path with spaces must be quoted');
  Assert.IsTrue(Pos('"D:\my movies\clip.mp3.tmp"', Cmd) > 0,
    'Output path with spaces must be quoted');
end;

procedure TTestWcxPresetExtractor.TestBuildCmdEmptyArgsStillProducesValidLine;
var
  Cmd: string;
begin
  { Empty Args means ffmpeg picks default codec from the output extension —
    a meaningful preset shape. The command line must still be valid. }
  Cmd := BuildPresetCmdLine('ffmpeg.exe', 'in.mkv', MakePreset('', 'mp4'), 'out.mp4.tmp');
  Assert.IsTrue(Pos('-i in.mkv', Cmd) > 0);
  Assert.IsTrue(Cmd.EndsWith('out.mp4.tmp'));
end;

procedure TTestWcxPresetExtractor.TestBuildCmdUserTokensInsertedBetweenInputAndOutput;
var
  Cmd: string;
  IPos, VnPos, OutPos: Integer;
begin
  Cmd := BuildPresetCmdLine('ffmpeg.exe', 'in.mkv',
    MakePreset('-vn -c:a libmp3lame', 'mp3'), 'out.mp3.tmp');
  IPos := Pos('-i in.mkv', Cmd);
  VnPos := Pos('-vn', Cmd);
  OutPos := Pos('out.mp3.tmp', Cmd);
  Assert.IsTrue((IPos > 0) and (VnPos > IPos) and (OutPos > VnPos),
    'User tokens must come between -i input and the output path');
  Assert.IsTrue(Pos('-c:a libmp3lame', Cmd) > 0);
end;

procedure TTestWcxPresetExtractor.TestBuildCmdQuotedUserTokenSurvivesRoundTrip;
var
  Cmd: string;
begin
  { A user arg like `-metadata "title=My Movie"` tokenises to two tokens:
    `-metadata` and `title=My Movie`. The latter contains a space and must
    be re-quoted on the way out so ffmpeg sees it as a single argument. }
  Cmd := BuildPresetCmdLine('ffmpeg.exe', 'in.mkv',
    MakePreset('-metadata "title=My Movie" -c copy', 'mp4'), 'out.mp4.tmp');
  Assert.IsTrue(Pos('-metadata "title=My Movie"', Cmd) > 0,
    'Tokeniser strips quotes; QuoteArg must restore them for spaced tokens');
  Assert.IsTrue(Pos('-c copy', Cmd) > 0);
end;

{ ParseProgressLine }

procedure TTestWcxPresetExtractor.TestParseProgressOutTimeUsHalfDuration;
var
  P: Integer;
begin
  { 5 seconds in microseconds against a 10-second duration is 50%. }
  Assert.IsTrue(ParseProgressLine('out_time_us=5000000', 10.0, P));
  Assert.AreEqual(50, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressOutTimeMsTreatedAsMicroseconds;
var
  P: Integer;
begin
  { ffmpeg's "out_time_ms" key is a known misnomer — the value is
    microseconds, identical to out_time_us. Both keys must be accepted
    and parsed the same way or progress jumps wildly between ffmpeg
    builds that emit one or the other. }
  Assert.IsTrue(ParseProgressLine('out_time_ms=5000000', 10.0, P));
  Assert.AreEqual(50, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressEndAlwaysOneHundred;
var
  P: Integer;
begin
  Assert.IsTrue(ParseProgressLine('progress=end', 10.0, P));
  Assert.AreEqual(100, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressEndIgnoresZeroDuration;
var
  P: Integer;
begin
  { Even when no duration is known, progress=end remains meaningful as
    the terminal tick — the bridge then sees 100% at least once. }
  Assert.IsTrue(ParseProgressLine('progress=end', 0, P));
  Assert.AreEqual(100, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressContinueIsNoise;
var
  P: Integer;
begin
  Assert.IsFalse(ParseProgressLine('progress=continue', 10.0, P));
end;

procedure TTestWcxPresetExtractor.TestParseProgressUnknownKeyIsNoise;
var
  P: Integer;
begin
  Assert.IsFalse(ParseProgressLine('frame=42', 10.0, P));
  Assert.IsFalse(ParseProgressLine('fps=24.5', 10.0, P));
  Assert.IsFalse(ParseProgressLine('bitrate=N/A', 10.0, P));
end;

procedure TTestWcxPresetExtractor.TestParseProgressNAValueIgnored;
var
  P: Integer;
begin
  { ffmpeg emits N/A early in the run before it has the numbers. Treating
    it as 0% would jitter the bar back to start; treating it as noise is
    correct. }
  Assert.IsFalse(ParseProgressLine('out_time_us=N/A', 10.0, P));
end;

procedure TTestWcxPresetExtractor.TestParseProgressNonNumericValueIgnored;
var
  P: Integer;
begin
  Assert.IsFalse(ParseProgressLine('out_time_us=garbage', 10.0, P));
end;

procedure TTestWcxPresetExtractor.TestParseProgressZeroDurationSkipsMetered;
var
  P: Integer;
begin
  { No duration means percent is undefined for the metered case. }
  Assert.IsFalse(ParseProgressLine('out_time_us=5000000', 0, P));
  Assert.IsFalse(ParseProgressLine('out_time_us=5000000', -1, P));
end;

procedure TTestWcxPresetExtractor.TestParseProgressClampsAboveDuration;
var
  P: Integer;
begin
  { Out-of-range time (e.g. probe duration was wrong) must clamp to 100
    rather than overshoot — TC's progress UI clips silently but the bridge
    would emit oscillating values. }
  Assert.IsTrue(ParseProgressLine('out_time_us=20000000', 10.0, P));
  Assert.AreEqual(100, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressClampsNegativeUs;
var
  P: Integer;
begin
  Assert.IsTrue(ParseProgressLine('out_time_us=-5000000', 10.0, P));
  Assert.AreEqual(0, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressKeyCaseInsensitive;
var
  P: Integer;
begin
  { ffmpeg always emits lowercase, but defensive parsing means a future
    ffmpeg fork emitting different case still works. }
  Assert.IsTrue(ParseProgressLine('OUT_TIME_US=5000000', 10.0, P));
  Assert.AreEqual(50, P);
  Assert.IsTrue(ParseProgressLine('Progress=End', 10.0, P));
  Assert.AreEqual(100, P);
end;

procedure TTestWcxPresetExtractor.TestParseProgressMissingEqualsRejected;
var
  P: Integer;
begin
  Assert.IsFalse(ParseProgressLine('out_time_us 5000000', 10.0, P));
  Assert.IsFalse(ParseProgressLine('', 10.0, P));
end;

{ MakeTempPath }

procedure TTestWcxPresetExtractor.TestMakeTempPathInsertsTmpBeforeExtension;
begin
  { ffmpeg picks the output container from the file extension. With ".tmp"
    appended after, ffmpeg sees ".tmp" and refuses with "Unable to choose
    an output format" — the bug that motivated this function. }
  Assert.AreEqual('poster.tmp.jpg', MakeTempPath('poster.jpg'));
  Assert.AreEqual('audio.tmp.mp3', MakeTempPath('audio.mp3'));
end;

procedure TTestWcxPresetExtractor.TestMakeTempPathHandlesPathWithDirectory;
begin
  Assert.AreEqual('C:\out\poster.tmp.jpg',
    MakeTempPath('C:\out\poster.jpg'));
end;

procedure TTestWcxPresetExtractor.TestMakeTempPathHandlesNoExtension;
begin
  { Edge case for extensionless outputs (preset validation requires an
    OutputExt so this should not happen via the normal path, but the
    helper must still be defined). }
  Assert.AreEqual('noext.tmp', MakeTempPath('noext'));
end;

procedure TTestWcxPresetExtractor.TestMakeTempPathHandlesMultipleDots;
begin
  { Only the last extension is replaced; earlier dots are part of the
    basename and survive. Important for filenames like "My.Movie.poster.jpg". }
  Assert.AreEqual('My.Movie.poster.tmp.jpg',
    MakeTempPath('My.Movie.poster.jpg'));
end;

procedure TTestWcxPresetExtractor.TestExtractPresetBadBinaryReportsLaunchFailure;
var
  Preset: TWcxPreset;
  R: TPresetExtractResult;
begin
  {Pointing ExtractPreset at a non-existent ffmpeg binary must surface
   a structured failure (Success=False, ErrorMessage filled in) rather
   than escape as an unhandled exception. Whether the failure travels
   the exception-handler path (RunProcess raises) or the exit-code path
   (RunProcess returns non-zero) is an implementation detail; the
   externally observable contract is "non-success, non-empty message".}
  Preset := MakePreset('-vn', 'mp3');
  R := ExtractPreset('Z:\nonexistent\ffmpeg.exe', 'Z:\input.mkv',
    'Z:\output.mp3', Preset, 10.0, nil, 0, 5000);
  Assert.IsFalse(R.Success, 'bad ffmpeg path must not report success');
  Assert.IsTrue(R.ErrorMessage <> '',
    'ErrorMessage must be populated so the caller can surface it');
end;

end.
