unit TestWcxPresetValidation;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxPresetValidation = class
  public
    { Validation }
    [Test] procedure TestValidateEmptyAccepted;
    [Test] procedure TestValidateRejectsLowerInput;
    [Test] procedure TestValidateRejectsUpperInput;
    [Test] procedure TestValidateRejectsOverwriteFlags;
    [Test] procedure TestValidateRejectsAllPipeChannels;
    [Test] procedure TestValidateAcceptsLookalikeFlags;
    [Test] procedure TestValidateRejectsQuotedForbiddenToken;

    { OutputName virtual-path validation: '/' or '\' for subfolders. }
    [Test] procedure TestValidateOutputNameAcceptsEmpty;
    [Test] procedure TestValidateOutputNameAcceptsFlat;
    [Test] procedure TestValidateOutputNameAcceptsVirtualFolder;
    [Test] procedure TestValidateOutputNameAcceptsBackslash;
    [Test] procedure TestValidateOutputNameAcceptsDeepNesting;
    [Test] procedure TestValidateOutputNameAcceptsTemplateTokens;
    [Test] procedure TestValidateOutputNameRejectsLeadingSlash;
    [Test] procedure TestValidateOutputNameRejectsLeadingBackslash;
    [Test] procedure TestValidateOutputNameRejectsParentTraversal;
    [Test] procedure TestValidateOutputNameRejectsDotSegment;
    [Test] procedure TestValidateOutputNameRejectsEmptySegment;
    [Test] procedure TestValidateOutputNameRejectsForbiddenCharInSegment;

    { ValidateOutputExt — shared single source of truth }
    [Test] procedure TestValidateOutputExtAcceptsPlainExt;
    [Test] procedure TestValidateOutputExtRejectsEmptyWithReason;
    [Test] procedure TestValidateOutputExtRejectsForbiddenCharWithReason;
    [Test] procedure TestValidateOutputExtRejectsSpaceWithReason;
  end;

implementation

uses
  System.SysUtils,
  uWcxPresetValidation;

{ Validation }

procedure TTestWcxPresetValidation.TestValidateEmptyAccepted;
var
  Reason: string;
begin
  Assert.IsTrue(ValidatePresetArgs('', Reason));
  Assert.AreEqual('', Reason);
end;

procedure TTestWcxPresetValidation.TestValidateRejectsLowerInput;
var
  Reason: string;
begin
  Assert.IsFalse(ValidatePresetArgs('-i other.mkv', Reason));
  Assert.IsTrue(Reason <> '');
end;

procedure TTestWcxPresetValidation.TestValidateRejectsUpperInput;
var
  Reason: string;
begin
  { Case-insensitive flag matching guards against the user trying to slip
    a forbidden flag past via capitalisation. }
  Assert.IsFalse(ValidatePresetArgs('-I other.mkv', Reason));
end;

procedure TTestWcxPresetValidation.TestValidateRejectsOverwriteFlags;
var
  Reason: string;
begin
  Assert.IsFalse(ValidatePresetArgs('-y', Reason), '-y must be rejected');
  Assert.IsFalse(ValidatePresetArgs('-n', Reason), '-n must be rejected');
end;

procedure TTestWcxPresetValidation.TestValidateRejectsAllPipeChannels;
var
  Reason: string;
begin
  Assert.IsFalse(ValidatePresetArgs('pipe:0', Reason));
  Assert.IsFalse(ValidatePresetArgs('pipe:1', Reason));
  Assert.IsFalse(ValidatePresetArgs('pipe:2', Reason));
end;

procedure TTestWcxPresetValidation.TestValidateAcceptsLookalikeFlags;
var
  Reason: string;
begin
  { Tokenisation is exact; a longer flag that merely starts with "-i" must
    not trip the rule because ffmpeg sees a different option entirely. }
  Assert.IsTrue(ValidatePresetArgs('-init_hw_device cuda', Reason));
  Assert.IsTrue(ValidatePresetArgs('pipe:3', Reason),
    'Only pipe:0/1/2 are stdio; higher channels are inert and must pass');
end;

procedure TTestWcxPresetValidation.TestValidateRejectsQuotedForbiddenToken;
var
  Reason: string;
begin
  { Quoting "-y" doesn't change what ffmpeg receives — the tokeniser strips
    the quotes and the rule still fires. }
  Assert.IsFalse(ValidatePresetArgs('"-y"', Reason));
end;

{ OutputName virtual-path validation }

procedure TTestWcxPresetValidation.TestValidateOutputNameAcceptsEmpty;
var
  R: string;
begin
  { Empty falls back to the default template at expansion time. }
  Assert.IsTrue(ValidateOutputName('', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameAcceptsFlat;
var
  R: string;
begin
  Assert.IsTrue(ValidateOutputName('foo', R));
  Assert.IsTrue(ValidateOutputName('audio_track_1', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameAcceptsVirtualFolder;
var
  R: string;
begin
  { Single-level subfolder. }
  Assert.IsTrue(ValidateOutputName('audio/track', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameAcceptsBackslash;
var
  R: string;
begin
  { '\' is the Windows-native form; users will type it from muscle memory.
    Validation accepts it as equivalent to '/'. }
  Assert.IsTrue(ValidateOutputName('audio\track', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameAcceptsDeepNesting;
var
  R: string;
begin
  Assert.IsTrue(ValidateOutputName('a/b/c/d/e', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameAcceptsTemplateTokens;
var
  R: string;
begin
  { Template tokens (%basename%, etc.) survive validation since they
    expand later. The token markers themselves are valid filename chars. }
  Assert.IsTrue(ValidateOutputName('%basename%/audio_%name%', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameRejectsLeadingSlash;
var
  R: string;
begin
  { Leading separator would look like a "rooted" virtual path; without
    rejecting it the listing entry name would start with '/' which TC
    treats as ambiguous. }
  Assert.IsFalse(ValidateOutputName('/audio/foo', R));
  Assert.IsTrue(R.Contains('Leading'));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameRejectsLeadingBackslash;
var
  R: string;
begin
  Assert.IsFalse(ValidateOutputName('\audio\foo', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameRejectsParentTraversal;
var
  R: string;
begin
  { Traversal segments would let a preset escape the virtual archive root
    when TC creates the destination directory tree. }
  Assert.IsFalse(ValidateOutputName('../foo', R));
  Assert.IsFalse(ValidateOutputName('audio/../etc', R));
  Assert.IsFalse(ValidateOutputName('foo/..', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameRejectsDotSegment;
var
  R: string;
begin
  { '.' is meaningless and confusing — reject so users don't think it
    means "current folder" relative to anything. }
  Assert.IsFalse(ValidateOutputName('./foo', R));
  Assert.IsFalse(ValidateOutputName('foo/./bar', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameRejectsEmptySegment;
var
  R: string;
begin
  { Double separator is a typo with no useful interpretation. }
  Assert.IsFalse(ValidateOutputName('audio//track', R));
  Assert.IsFalse(ValidateOutputName('audio\\track', R));
end;

procedure TTestWcxPresetValidation.TestValidateOutputNameRejectsForbiddenCharInSegment;
var
  R: string;
begin
  { Windows-illegal characters within any segment break filesystem
    creation when TC tries to materialise the virtual folder. }
  Assert.IsFalse(ValidateOutputName('audio:tracks/foo', R));
  Assert.IsFalse(ValidateOutputName('foo/bar*baz', R));
  Assert.IsFalse(ValidateOutputName('foo/bar?baz', R));
  Assert.IsFalse(ValidateOutputName('foo/bar<baz', R));
end;

{ ValidateOutputExt — shared single source of truth }

procedure TTestWcxPresetValidation.TestValidateOutputExtAcceptsPlainExt;
var
  Reason: string;
begin
  Assert.IsTrue(ValidateOutputExt('mp3', Reason));
  Assert.AreEqual('', Reason);
end;

procedure TTestWcxPresetValidation.TestValidateOutputExtRejectsEmptyWithReason;
var
  Reason: string;
begin
  Assert.IsFalse(ValidateOutputExt('', Reason));
  Assert.AreEqual('OutputExt is required', Reason);
end;

procedure TTestWcxPresetValidation.TestValidateOutputExtRejectsForbiddenCharWithReason;
var
  Reason: string;
begin
  {Slash is in the forbidden set; first hit produces the named-character
   reason the editor surfaces to the user.}
  Assert.IsFalse(ValidateOutputExt('mp3/', Reason));
  Assert.AreEqual('OutputExt contains an invalid character: "/"', Reason);
end;

procedure TTestWcxPresetValidation.TestValidateOutputExtRejectsSpaceWithReason;
var
  Reason: string;
begin
  {Spaces are illegal in extensions — the forbidden set includes ' ' and
   tab. Empty-after-trim path is exercised by TestValidateOutputExtRejectsEmpty.}
  Assert.IsFalse(ValidateOutputExt('mp 3', Reason));
  Assert.AreEqual('OutputExt contains an invalid character: " "', Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxPresetValidation);

end.
