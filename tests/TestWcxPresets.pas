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

    { Path derivation }
    [Test] procedure TestPresetsIniPathSiblingOfSettings;
    [Test] procedure TestPresetsIniPathEmptyInputReturnsEmpty;

    { LoadAllPresets: editor variant that surfaces disabled and invalid
      entries so they can be repaired in the GUI. }
    [Test] procedure TestLoadAllIncludesDisabled;
    [Test] procedure TestLoadAllIncludesInvalidArgsForRepair;
    [Test] procedure TestLoadAllPreservesOrder;
    [Test] procedure TestLoadAllMissingFileReturnsEmpty;

    { SavePresets round-trip and ordering. }
    [Test] procedure TestSavePresetsRoundTrip;
    [Test] procedure TestSavePresetsPreservesArrayOrder;
    [Test] procedure TestSavePresetsOmitsEmptyOptionalKeys;
    [Test] procedure TestSavePresetsEmptyArrayProducesEmptyFile;
    [Test] procedure TestSavePresetsEmptyPathSilentlyIgnored;
    [Test] procedure TestSavePresetsEnabledFlagPersists;

    { Virtual-path end-to-end through LoadPresets. }
    [Test] procedure TestLoadPresetsAcceptsVirtualPath;
    [Test] procedure TestLoadPresetsRejectsTraversal;
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

{ LoadAllPresets: editor variant }

procedure TTestWcxPresets.TestLoadAllIncludesDisabled;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  { LoadPresets drops disabled entries because they have no place in the
    visible archive listing. The editor must see them so the user can
    flip the toggle back on; LoadAllPresets is the editor's hook. }
  Path := WriteIni('all_disabled.ini',
    '[a]'#13#10 +
    'Enabled=False'#13#10 +
    'OutputExt=mp3'#13#10 +
    '[b]'#13#10 +
    'OutputExt=mp4'#13#10);
  Presets := LoadAllPresets(Path);
  Assert.AreEqual(2, Integer(Length(Presets)));
  Assert.AreEqual('a', Presets[0].Name);
  Assert.IsFalse(Presets[0].Enabled, 'Disabled state must survive LoadAll');
  Assert.AreEqual('b', Presets[1].Name);
end;

procedure TTestWcxPresets.TestLoadAllIncludesInvalidArgsForRepair;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  { A preset with -i in Args would be rejected by the listing-time
    LoadPresets. The editor must still surface it so the user can
    delete the bad token rather than discover the entry vanished. }
  Path := WriteIni('all_bad_args.ini',
    '[broken]'#13#10 +
    'OutputExt=mp4'#13#10 +
    'Args=-i other.mkv -c copy'#13#10);
  Presets := LoadAllPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)));
  Assert.AreEqual('-i other.mkv -c copy', Presets[0].Args,
    'LoadAll keeps the original Args verbatim so the editor can show what is wrong');
end;

procedure TTestWcxPresets.TestLoadAllPreservesOrder;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  Path := WriteIni('all_order.ini',
    '[zeta]'#13#10 + 'OutputExt=mp3'#13#10 +
    '[alpha]'#13#10 + 'OutputExt=mp3'#13#10 +
    '[mid]'#13#10 + 'OutputExt=mp3'#13#10);
  Presets := LoadAllPresets(Path);
  Assert.AreEqual('zeta', Presets[0].Name);
  Assert.AreEqual('alpha', Presets[1].Name);
  Assert.AreEqual('mid', Presets[2].Name);
end;

procedure TTestWcxPresets.TestLoadAllMissingFileReturnsEmpty;
var
  Presets: TWcxPresetArray;
begin
  Presets := LoadAllPresets(TPath.Combine(FTempDir, 'no_such.ini'));
  Assert.AreEqual(0, Integer(Length(Presets)));
end;

{ SavePresets }

procedure TTestWcxPresets.TestSavePresetsRoundTrip;
var
  Path: string;
  Saved, Loaded: TWcxPresetArray;
begin
  { Round-trip property: presets that load cleanly via LoadPresets must
    survive Save then LoadPresets unchanged. Pin the exact field set so
    the editor never silently drops a key. }
  Path := TPath.Combine(FTempDir, 'rt.ini');
  SetLength(Saved, 2);
  Saved[0].Name := 'audio_mp3';
  Saved[0].Enabled := True;
  Saved[0].Description := 'MP3 rip';
  Saved[0].OutputExt := 'mp3';
  Saved[0].OutputName := '%basename%_audio';
  Saved[0].Args := '-vn -c:a libmp3lame -q:a 4';
  Saved[1].Name := 'poster';
  Saved[1].Enabled := True;
  Saved[1].OutputExt := 'jpg';
  Saved[1].OutputName := '%basename%_poster';
  Saved[1].Args := '-ss 00:00:05 -frames:v 1 -q:v 2';

  SavePresets(Path, Saved);
  Loaded := LoadPresets(Path);

  Assert.AreEqual(2, Integer(Length(Loaded)));
  Assert.AreEqual('audio_mp3', Loaded[0].Name);
  Assert.AreEqual('MP3 rip', Loaded[0].Description);
  Assert.AreEqual('mp3', Loaded[0].OutputExt);
  Assert.AreEqual('%basename%_audio', Loaded[0].OutputName);
  Assert.AreEqual('-vn -c:a libmp3lame -q:a 4', Loaded[0].Args);
  Assert.IsTrue(Loaded[0].Enabled);
  Assert.AreEqual('poster', Loaded[1].Name);
end;

procedure TTestWcxPresets.TestSavePresetsPreservesArrayOrder;
var
  Path: string;
  Saved, Loaded: TWcxPresetArray;
begin
  { Ordering matters: the listing-time dedupe gives the bare name to the
    first-defined preset. The editor's drag-reorder semantics depend on
    Save preserving the array order verbatim. }
  Path := TPath.Combine(FTempDir, 'order.ini');
  SetLength(Saved, 3);
  Saved[0].Name := 'zeta'; Saved[0].OutputExt := 'mp3'; Saved[0].Enabled := True;
  Saved[1].Name := 'alpha'; Saved[1].OutputExt := 'mp3'; Saved[1].Enabled := True;
  Saved[2].Name := 'mid'; Saved[2].OutputExt := 'mp3'; Saved[2].Enabled := True;

  SavePresets(Path, Saved);
  Loaded := LoadAllPresets(Path);

  Assert.AreEqual('zeta', Loaded[0].Name);
  Assert.AreEqual('alpha', Loaded[1].Name);
  Assert.AreEqual('mid', Loaded[2].Name);
end;

procedure TTestWcxPresets.TestSavePresetsOmitsEmptyOptionalKeys;
var
  Path, Body: string;
  P: TWcxPresetArray;
begin
  { Optional keys (Description, OutputName, Args) must be omitted entirely
    when empty so the saved INI stays minimal and round-trips through the
    same defaults the loader applies on a fresh read. }
  Path := TPath.Combine(FTempDir, 'omit.ini');
  SetLength(P, 1);
  P[0].Name := 'minimal'; P[0].OutputExt := 'mp4'; P[0].Enabled := True;
  SavePresets(Path, P);
  {No-encoding overload auto-detects via BOM; SavePresets emits UTF-16 LE
   so TIniFile reads it via the Win32 Unicode profile API.}
  Body := TFile.ReadAllText(Path);
  Assert.IsFalse(Body.Contains('Description='));
  Assert.IsFalse(Body.Contains('OutputName='));
  Assert.IsFalse(Body.Contains('Args='));
  Assert.IsTrue(Body.Contains('OutputExt=mp4'));
end;

procedure TTestWcxPresets.TestSavePresetsEmptyArrayProducesEmptyFile;
var
  Path: string;
  Body: string;
begin
  { Saving zero presets must produce a syntactically empty file rather
    than failing or leaving stale content from a prior write. }
  Path := TPath.Combine(FTempDir, 'empty.ini');
  TFile.WriteAllText(Path, 'leftover_content', TEncoding.UTF8);
  SavePresets(Path, nil);
  Body := TFile.ReadAllText(Path);
  Assert.AreEqual('', Body.Trim);
end;

procedure TTestWcxPresets.TestSavePresetsEmptyPathSilentlyIgnored;
var
  P: TWcxPresetArray;
begin
  { Mirror TWcxSettings.Save: an empty path is the documented "no place
    to write" sentinel, not an error to raise. }
  SetLength(P, 1);
  P[0].Name := 'a'; P[0].OutputExt := 'mp3'; P[0].Enabled := True;
  SavePresets('', P);
  Assert.Pass('No exception');
end;

procedure TTestWcxPresets.TestSavePresetsEnabledFlagPersists;
var
  Path: string;
  P, Loaded: TWcxPresetArray;
begin
  { Enabled=False must round-trip via LoadAll (LoadPresets drops it). }
  Path := TPath.Combine(FTempDir, 'enabled.ini');
  SetLength(P, 1);
  P[0].Name := 'off';
  P[0].OutputExt := 'mp3';
  P[0].Enabled := False;
  SavePresets(Path, P);
  Loaded := LoadAllPresets(Path);
  Assert.AreEqual(1, Integer(Length(Loaded)));
  Assert.IsFalse(Loaded[0].Enabled);
end;

{ Virtual-path end-to-end through LoadPresets }

procedure TTestWcxPresets.TestLoadPresetsAcceptsVirtualPath;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  { End-to-end: a preset with a slashed OutputName loads and survives
    validation. The in-memory OutputName preserves the user's typed form;
    BuildOutputFileName normalises at expansion time. }
  Path := WriteIni('vp.ini',
    '[audio]'#13#10 +
    'OutputExt=mp3'#13#10 +
    'OutputName=audio/%basename%_track'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(1, Integer(Length(Presets)));
  Assert.AreEqual('audio/%basename%_track', Presets[0].OutputName);
end;

procedure TTestWcxPresets.TestLoadPresetsRejectsTraversal;
var
  Path: string;
  Presets: TWcxPresetArray;
begin
  { A preset that would escape the virtual archive root is dropped at
    load with a debug-log warning, same as any other invalid preset. }
  Path := WriteIni('vp_bad.ini',
    '[audio]'#13#10 +
    'OutputExt=mp3'#13#10 +
    'OutputName=../escape/track'#13#10);
  Presets := LoadPresets(Path);
  Assert.AreEqual(0, Integer(Length(Presets)));
end;

end.
