unit TestWcxPresetTemplate;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxPresetTemplate = class
  public
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

    { NormalizeOutputName }
    [Test] procedure TestNormalizeOutputNameConvertsBackslash;
    [Test] procedure TestNormalizeOutputNameLeavesSlashesAlone;
    [Test] procedure TestBuildOutputFileNameNormalisesBackslash;
  end;

implementation

uses
  System.SysUtils,
  uWcxPresets, uWcxPresetTemplate;

{ Template expansion }

procedure TTestWcxPresetTemplate.TestExpandBasename;
begin
  Assert.AreEqual('Movie',
    ExpandTemplate('%basename%', 'C:\videos\Movie.mkv', 'p'));
end;

procedure TTestWcxPresetTemplate.TestExpandPresetName;
begin
  Assert.AreEqual('audio',
    ExpandTemplate('%name%', 'C:\videos\Movie.mkv', 'audio'));
end;

procedure TTestWcxPresetTemplate.TestExpandExtensionLowercased;
begin
  { Lowercasing prevents the same source-with-different-case (Movie.MKV vs
    Movie.mkv) producing different listings on a case-insensitive filesystem. }
  Assert.AreEqual('mkv',
    ExpandTemplate('%ext%', 'C:\videos\Movie.MKV', 'p'));
end;

procedure TTestWcxPresetTemplate.TestExpandAllVariablesTogether;
begin
  Assert.AreEqual('Movie_audio.mkv',
    ExpandTemplate('%basename%_%name%.%ext%', 'C:\videos\Movie.mkv', 'audio'));
end;

procedure TTestWcxPresetTemplate.TestExpandUnknownVariableUntouched;
begin
  { Forward-compat: future template tokens added later must not break old
    presets. Untouched tokens are surface noise, not crashes. }
  Assert.AreEqual('%duration%',
    ExpandTemplate('%duration%', 'C:\videos\Movie.mkv', 'p'));
end;

procedure TTestWcxPresetTemplate.TestExpandFileWithoutExtension;
begin
  Assert.AreEqual('README_',
    ExpandTemplate('%basename%_%ext%', 'C:\docs\README', 'p'));
end;

procedure TTestWcxPresetTemplate.TestExpandUnicodeFileName;
begin
  Assert.AreEqual('фильм',
    ExpandTemplate('%basename%', 'C:\кино\фильм.mkv', 'p'));
end;

{ BuildOutputFileName }

procedure TTestWcxPresetTemplate.TestBuildOutputUsesDefaultTemplateWhenEmpty;
var
  P: TWcxPreset;
begin
  P := Default(TWcxPreset);
  P.Name := 'audio';
  P.OutputExt := 'mp3';
  P.OutputName := '';
  Assert.AreEqual('Movie_audio.mp3', BuildOutputFileName(P, 'C:\videos\Movie.mkv'));
end;

procedure TTestWcxPresetTemplate.TestBuildOutputHonoursCustomTemplate;
var
  P: TWcxPreset;
begin
  P := Default(TWcxPreset);
  P.Name := 'audio';
  P.OutputExt := 'mp3';
  P.OutputName := 'audio_only_%basename%';
  Assert.AreEqual('audio_only_Movie.mp3', BuildOutputFileName(P, 'C:\videos\Movie.mkv'));
end;

procedure TTestWcxPresetTemplate.TestBuildOutputAppendsSingleDottedExtension;
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

{ NormalizeOutputName }

procedure TTestWcxPresetTemplate.TestNormalizeOutputNameConvertsBackslash;
begin
  { WCX SDK requires backslashes in entry filenames. Normalisation goes
    forward-slash → backslash so user input with '/' (which is more
    natural to type) ends up in the WCX-canonical form. }
  Assert.AreEqual('audio\track', NormalizeOutputName('audio/track'));
  Assert.AreEqual('a\b\c', NormalizeOutputName('a/b/c'));
  Assert.AreEqual('a\b\c', NormalizeOutputName('a/b\c'));
end;

procedure TTestWcxPresetTemplate.TestNormalizeOutputNameLeavesSlashesAlone;
begin
  { Backslashes (the canonical form) pass through unchanged. }
  Assert.AreEqual('audio\track', NormalizeOutputName('audio\track'));
  Assert.AreEqual('flat', NormalizeOutputName('flat'));
  Assert.AreEqual('', NormalizeOutputName(''));
end;

procedure TTestWcxPresetTemplate.TestBuildOutputFileNameNormalisesBackslash;
var
  P: TWcxPreset;
begin
  { Whichever separator the user typed, the listing entry FileName uses
    '\' (WCX-canonical) so TC actually sees the folder structure. }
  P := Default(TWcxPreset);
  P.Name := 'audio';
  P.OutputExt := 'mp3';
  P.OutputName := 'audio/%basename%';
  Assert.AreEqual('audio\Movie.mp3',
    BuildOutputFileName(P, 'C:\v\Movie.mkv'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxPresetTemplate);

end.
