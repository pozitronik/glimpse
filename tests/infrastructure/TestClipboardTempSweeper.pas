{Tests for ClipboardTempSweeper.SweepClipboardTempFolder against a real temp
 directory. ANow and the protected path are injected so the cross-instance
 guards (skip the clipboard-referenced file, honour the min-age floor) and
 the prefix-only matching are deterministic — no clipboard, no wall clock.}
unit TestClipboardTempSweeper;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardTempSweeper = class
  strict private
    FDir: string;
    FNow: TDateTime;
    {Creates AName in FDir with a last-write time AAgeSeconds in the past
     relative to FNow. Returns the full path.}
    function MakeAgedFile(const AName: string; AAgeSeconds: Integer): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure None_DeletesNothing;
    [Test] procedure MissingFolder_ReturnsZero;
    [Test] procedure OnlyMatchesGlimpsePrefix;
    [Test] procedure All_DeletesAgedKeepsFresh;
    [Test] procedure OlderThan_DeletesOnlyPastThreshold;
    [Test] procedure ProtectedFile_NeverDeleted;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  ClipboardTemp, ClipboardTempSweeper;

procedure TTestClipboardTempSweeper.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'VT_SweepTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
  {Fixed reference instant so file ages are exact regardless of test speed.}
  FNow := EncodeDate(2026, 1, 1) + EncodeTime(12, 0, 0, 0);
end;

procedure TTestClipboardTempSweeper.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function TTestClipboardTempSweeper.MakeAgedFile(const AName: string; AAgeSeconds: Integer): string;
begin
  Result := TPath.Combine(FDir, AName);
  TFile.WriteAllText(Result, 'x');
  TFile.SetLastWriteTime(Result, IncSecond(FNow, -AAgeSeconds));
end;

procedure TTestClipboardTempSweeper.None_DeletesNothing;
var
  F: string;
begin
  F := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'a' + CLIPBOARD_TEMP_EXT, 100000);
  Assert.AreEqual(0, SweepClipboardTempFolder(FDir, ccsNone, 0, 0, '', FNow));
  Assert.IsTrue(TFile.Exists(F), 'ccsNone must leave files untouched');
end;

procedure TTestClipboardTempSweeper.MissingFolder_ReturnsZero;
begin
  Assert.AreEqual(0,
    SweepClipboardTempFolder(TPath.Combine(FDir, 'nope'), ccsAll, 0, 0, '', FNow));
end;

procedure TTestClipboardTempSweeper.OnlyMatchesGlimpsePrefix;
var
  Ours, Foreign: string;
begin
  {A foreign PNG (and any non-matching name) must never be touched, even
   under "clean everything".}
  Ours := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'mine' + CLIPBOARD_TEMP_EXT, 100000);
  Foreign := MakeAgedFile('someone_else.png', 100000);

  Assert.AreEqual(1, SweepClipboardTempFolder(FDir, ccsAll, 0, 0, '', FNow));
  Assert.IsFalse(TFile.Exists(Ours), 'our temp file should be swept');
  Assert.IsTrue(TFile.Exists(Foreign), 'foreign file must survive');
end;

procedure TTestClipboardTempSweeper.All_DeletesAgedKeepsFresh;
var
  Aged, Fresh: string;
begin
  Aged := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'old' + CLIPBOARD_TEMP_EXT, 600);
  Fresh := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'new' + CLIPBOARD_TEMP_EXT, 30);

  {Floor = 120s: the 30s-old file is protected, the 600s-old one is not.}
  Assert.AreEqual(1, SweepClipboardTempFolder(FDir, ccsAll, 0, 120, '', FNow));
  Assert.IsFalse(TFile.Exists(Aged));
  Assert.IsTrue(TFile.Exists(Fresh), 'min-age floor must spare the fresh file');
end;

procedure TTestClipboardTempSweeper.OlderThan_DeletesOnlyPastThreshold;
var
  Young, Old: string;
begin
  {Threshold 1 hour; floor 0 to isolate the threshold behaviour.}
  Young := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'young' + CLIPBOARD_TEMP_EXT, 1800);
  Old := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'old' + CLIPBOARD_TEMP_EXT, 7200);

  Assert.AreEqual(1, SweepClipboardTempFolder(FDir, ccsOlderThan, 3600, 0, '', FNow));
  Assert.IsTrue(TFile.Exists(Young), 'within threshold must survive');
  Assert.IsFalse(TFile.Exists(Old), 'past threshold must be swept');
end;

procedure TTestClipboardTempSweeper.ProtectedFile_NeverDeleted;
var
  Protected, Other: string;
begin
  {The file currently on the clipboard is spared even when old enough and
   above the floor, so a pending paste across instances still resolves.}
  Protected := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'onclip' + CLIPBOARD_TEMP_EXT, 100000);
  Other := MakeAgedFile(CLIPBOARD_TEMP_PREFIX + 'other' + CLIPBOARD_TEMP_EXT, 100000);

  Assert.AreEqual(1, SweepClipboardTempFolder(FDir, ccsAll, 0, 0, Protected, FNow));
  Assert.IsTrue(TFile.Exists(Protected), 'clipboard-referenced file must survive');
  Assert.IsFalse(TFile.Exists(Other));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardTempSweeper);

end.
