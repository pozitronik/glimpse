unit TestWcxPresetEditorModel;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxPresetEditorModel = class
  public
    { Load / shape contracts }
    [Test] procedure TestEmptyOnConstruction;
    [Test] procedure TestLoadFromArrayThenToArrayRoundTrips;
    [Test] procedure TestLoadFromReplacesExistingContent;

    { Add }
    [Test] procedure TestAddIncrementsCount;
    [Test] procedure TestAddReturnsNewIndex;
    [Test] procedure TestAddPickedNameDoesNotCollide;
    [Test] procedure TestRepeatedAddProducesDistinctNames;

    { Remove }
    [Test] procedure TestRemoveDecrementsCount;
    [Test] procedure TestRemoveOutOfRangeIsNoOp;

    { Duplicate }
    [Test] procedure TestDuplicateInsertsRightAfterSource;
    [Test] procedure TestDuplicateGivesUniqueName;
    [Test] procedure TestDuplicateOutOfRangeReturnsMinusOne;

    { Move }
    [Test] procedure TestMoveUpSwapsWithPredecessor;
    [Test] procedure TestMoveUpAtTopIsNoOp;
    [Test] procedure TestMoveDownSwapsWithSuccessor;
    [Test] procedure TestMoveDownAtBottomIsNoOp;

    { Validate: rule coverage }
    [Test] procedure TestValidateAcceptsCleanModel;
    [Test] procedure TestValidateRejectsEmptyName;
    [Test] procedure TestValidateRejectsCaseInsensitiveDuplicateName;
    [Test] procedure TestValidateRejectsEmptyOutputExt;
    [Test] procedure TestValidateRejectsBadCharInOutputExt;
    [Test] procedure TestValidateRejectsBadCharInOutputName;
    [Test] procedure TestValidateRejectsForbiddenArgsToken;
    [Test] procedure TestValidateInvalidIndexPointsToOffender;
    { Virtual-path validation in OutputName mirrors the loader's rules
      so the editor catches bad templates before the user clicks Apply. }
    [Test] procedure TestValidateAcceptsVirtualPathInOutputName;
    [Test] procedure TestValidateRejectsTraversalInOutputName;
    [Test] procedure TestValidateRejectsLeadingSeparatorInOutputName;
  end;

implementation

uses
  System.SysUtils,
  uWcxPresets, uWcxPresetEditorModel;

function MakeP(const AName, AExt: string): TWcxPreset;
begin
  Result := Default(TWcxPreset);
  Result.Name := AName;
  Result.OutputExt := AExt;
  Result.Enabled := True;
end;

{ Load / shape }

procedure TTestWcxPresetEditorModel.TestEmptyOnConstruction;
var
  M: TPresetEditorModel;
begin
  M := TPresetEditorModel.Create;
  try
    Assert.AreEqual(0, M.Count);
    Assert.AreEqual(0, Integer(Length(M.ToArray)));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestLoadFromArrayThenToArrayRoundTrips;
var
  M: TPresetEditorModel;
  Source, Roundtrip: TWcxPresetArray;
begin
  SetLength(Source, 2);
  Source[0] := MakeP('a', 'mp3');
  Source[1] := MakeP('b', 'mp4');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    Assert.AreEqual(2, M.Count);
    Roundtrip := M.ToArray;
    Assert.AreEqual('a', Roundtrip[0].Name);
    Assert.AreEqual('b', Roundtrip[1].Name);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestLoadFromReplacesExistingContent;
var
  M: TPresetEditorModel;
  First, Second: TWcxPresetArray;
begin
  SetLength(First, 2);
  First[0] := MakeP('a', 'mp3');
  First[1] := MakeP('b', 'mp3');
  SetLength(Second, 1);
  Second[0] := MakeP('c', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(First);
    M.LoadFrom(Second);
    Assert.AreEqual(1, M.Count, 'Second LoadFrom must replace, not append');
    Assert.AreEqual('c', M.Get(0).Name);
  finally
    M.Free;
  end;
end;

{ Add }

procedure TTestWcxPresetEditorModel.TestAddIncrementsCount;
var
  M: TPresetEditorModel;
begin
  M := TPresetEditorModel.Create;
  try
    M.Add;
    Assert.AreEqual(1, M.Count);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestAddReturnsNewIndex;
var
  M: TPresetEditorModel;
begin
  M := TPresetEditorModel.Create;
  try
    Assert.AreEqual(0, M.Add);
    Assert.AreEqual(1, M.Add);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestAddPickedNameDoesNotCollide;
var
  M: TPresetEditorModel;
  Existing: TWcxPresetArray;
begin
  { Pre-seed a preset called "new_preset" so the auto-name picker has to
    skip the bare prefix. }
  SetLength(Existing, 1);
  Existing[0] := MakeP('new_preset', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Existing);
    M.Add;
    Assert.AreNotEqual('new_preset', M.Get(1).Name,
      'Auto-name must not collide with an existing entry');
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestRepeatedAddProducesDistinctNames;
var
  M: TPresetEditorModel;
  I, J: Integer;
begin
  M := TPresetEditorModel.Create;
  try
    for I := 1 to 5 do
      M.Add;
    {Pairwise distinct via the case-insensitive comparison the editor uses
     for collision checks.}
    for I := 0 to M.Count - 1 do
      for J := I + 1 to M.Count - 1 do
        Assert.IsFalse(SameText(M.Get(I).Name, M.Get(J).Name),
          Format('Duplicate auto-name at indices %d and %d', [I, J]));
  finally
    M.Free;
  end;
end;

{ Remove }

procedure TTestWcxPresetEditorModel.TestRemoveDecrementsCount;
var
  M: TPresetEditorModel;
begin
  M := TPresetEditorModel.Create;
  try
    M.Add; M.Add;
    M.Remove(0);
    Assert.AreEqual(1, M.Count);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestRemoveOutOfRangeIsNoOp;
var
  M: TPresetEditorModel;
begin
  { Defensive: a stray click on Remove with no selection must not raise. }
  M := TPresetEditorModel.Create;
  try
    M.Add;
    M.Remove(-1);
    M.Remove(99);
    Assert.AreEqual(1, M.Count);
  finally
    M.Free;
  end;
end;

{ Duplicate }

procedure TTestWcxPresetEditorModel.TestDuplicateInsertsRightAfterSource;
var
  M: TPresetEditorModel;
  Source: TWcxPresetArray;
  NewIndex: Integer;
begin
  { The duplicate lands at SourceIndex+1 so the user sees the copy next
    to the original — important when the list gets long. }
  SetLength(Source, 3);
  Source[0] := MakeP('a', 'mp3');
  Source[1] := MakeP('b', 'mp3');
  Source[2] := MakeP('c', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    NewIndex := M.Duplicate(0);
    Assert.AreEqual(1, NewIndex);
    Assert.AreEqual('b', M.Get(2).Name, 'Element after the duplicate must shift right');
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestDuplicateGivesUniqueName;
var
  M: TPresetEditorModel;
  Source: TWcxPresetArray;
begin
  SetLength(Source, 1);
  Source[0] := MakeP('audio', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    M.Duplicate(0);
    Assert.AreNotEqual(M.Get(0).Name, M.Get(1).Name,
      'Duplicate must rename the copy so save-time validation does not fail');
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestDuplicateOutOfRangeReturnsMinusOne;
var
  M: TPresetEditorModel;
begin
  M := TPresetEditorModel.Create;
  try
    Assert.AreEqual(-1, M.Duplicate(5));
  finally
    M.Free;
  end;
end;

{ Move }

procedure TTestWcxPresetEditorModel.TestMoveUpSwapsWithPredecessor;
var
  M: TPresetEditorModel;
  Source: TWcxPresetArray;
begin
  SetLength(Source, 3);
  Source[0] := MakeP('a', 'mp3');
  Source[1] := MakeP('b', 'mp3');
  Source[2] := MakeP('c', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    Assert.AreEqual(1, M.MoveUp(2));
    Assert.AreEqual('a', M.Get(0).Name);
    Assert.AreEqual('c', M.Get(1).Name);
    Assert.AreEqual('b', M.Get(2).Name);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestMoveUpAtTopIsNoOp;
var
  M: TPresetEditorModel;
  Source: TWcxPresetArray;
begin
  SetLength(Source, 2);
  Source[0] := MakeP('a', 'mp3');
  Source[1] := MakeP('b', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    Assert.AreEqual(0, M.MoveUp(0));
    Assert.AreEqual('a', M.Get(0).Name);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestMoveDownSwapsWithSuccessor;
var
  M: TPresetEditorModel;
  Source: TWcxPresetArray;
begin
  SetLength(Source, 3);
  Source[0] := MakeP('a', 'mp3');
  Source[1] := MakeP('b', 'mp3');
  Source[2] := MakeP('c', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    Assert.AreEqual(1, M.MoveDown(0));
    Assert.AreEqual('b', M.Get(0).Name);
    Assert.AreEqual('a', M.Get(1).Name);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestMoveDownAtBottomIsNoOp;
var
  M: TPresetEditorModel;
  Source: TWcxPresetArray;
begin
  SetLength(Source, 2);
  Source[0] := MakeP('a', 'mp3');
  Source[1] := MakeP('b', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(Source);
    Assert.AreEqual(1, M.MoveDown(1));
    Assert.AreEqual('b', M.Get(1).Name);
  finally
    M.Free;
  end;
end;

{ Validate }

procedure TTestWcxPresetEditorModel.TestValidateAcceptsCleanModel;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('audio', 'mp3');
  P[0].Args := '-vn -c:a libmp3lame';
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsTrue(M.Validate(BadIdx, Reason));
    Assert.AreEqual(-1, BadIdx);
    Assert.AreEqual('', Reason);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsEmptyName;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('', 'mp3');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
    Assert.IsTrue(Reason.Contains('Name'));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsCaseInsensitiveDuplicateName;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  { Section names in the INI are case-insensitive on Windows; the listing
    dedupe also compares case-insensitively. The editor must catch
    "Audio" vs "audio" before save so the saved file does not silently
    collapse to one entry on the next load. }
  SetLength(P, 2);
  P[0] := MakeP('Audio', 'mp3');
  P[1] := MakeP('audio', 'mp4');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
    Assert.AreEqual(1, BadIdx, 'Second occurrence is the offender');
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsEmptyOutputExt;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('a', '');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
    Assert.IsTrue(Reason.Contains('OutputExt'));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsBadCharInOutputExt;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('a', 'mp3\x');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsBadCharInOutputName;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('a', 'mp3');
  P[0].OutputName := '..\..\evil';
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsForbiddenArgsToken;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('a', 'mp3');
  P[0].Args := '-i other.mkv';
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
    Assert.IsTrue(Reason.Contains('Args'),
      'Reason must point at Args so the editor knows which field to focus');
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateInvalidIndexPointsToOffender;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  { Two clean presets followed by one bad; the index must point at the
    third so the editor can scroll-and-focus the broken row. }
  SetLength(P, 3);
  P[0] := MakeP('a', 'mp3');
  P[1] := MakeP('b', 'mp4');
  P[2] := MakeP('', 'jpg');
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
    Assert.AreEqual(2, BadIdx);
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateAcceptsVirtualPathInOutputName;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  { Slashes in OutputName are now legitimate — virtual subfolders. }
  SetLength(P, 1);
  P[0] := MakeP('audio', 'mp3');
  P[0].OutputName := 'audio/%basename%';
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsTrue(M.Validate(BadIdx, Reason));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsTraversalInOutputName;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  { Editor must catch traversal before save so the user sees the error
    in the dialog rather than discovering a missing entry on next open. }
  SetLength(P, 1);
  P[0] := MakeP('audio', 'mp3');
  P[0].OutputName := '../escape';
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
    Assert.AreEqual(0, BadIdx);
    Assert.IsTrue(Reason.Contains('OutputName'));
  finally
    M.Free;
  end;
end;

procedure TTestWcxPresetEditorModel.TestValidateRejectsLeadingSeparatorInOutputName;
var
  M: TPresetEditorModel;
  P: TWcxPresetArray;
  BadIdx: Integer;
  Reason: string;
begin
  SetLength(P, 1);
  P[0] := MakeP('audio', 'mp3');
  P[0].OutputName := '/audio';
  M := TPresetEditorModel.Create;
  try
    M.LoadFrom(P);
    Assert.IsFalse(M.Validate(BadIdx, Reason));
  finally
    M.Free;
  end;
end;

end.
