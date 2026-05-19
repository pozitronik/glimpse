{Tests for src/uSettingsDialogHelpers (step 104, M25).

 Covers DisplayFFmpegInfo's path-classification logic across the
 probe-state branches that don't require actually launching ffmpeg
 (fpsNoPath / fpsFileMissing). fpsInvalid and fpsValid both require
 invoking the file as a process via ValidateFFmpeg, which is slow and
 has Windows side effects; covered transitively via the integration
 path (ValidateFFmpeg has its own tests in TestFFmpegExe).

 BrowseForFFmpegExe is intentionally not covered — TOpenDialog is not
 driveable headlessly.

 Fixture uses the now-standard hidden TForm + child controls pattern
 (step-50 onward) for label + edit so handles allocate.}
unit TestSettingsDialogHelpers;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsDialogHelpers = class
  public
    [Test] procedure Display_EmptyInputEmptyFallback_ReportsNotFound;
    [Test] procedure Display_NonExistentInput_ReportsFileMissingWithPath;
    [Test] procedure Display_EmptyInputNonExistentFallback_ReportsFileMissing;
    [Test] procedure Display_EmptyInputUsesFallbackPath_NotInputPath;
    [Test] procedure Display_NonEmptyInputUsesInputPath_NotFallback;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  uSettingsDialogHelpers;

function MakeLabel(AParent: TWinControl): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
end;

function MakeEdit(AParent: TWinControl): TEdit;
begin
  Result := TEdit.Create(AParent);
  Result.Parent := AParent;
end;

procedure TTestSettingsDialogHelpers.Display_EmptyInputEmptyFallback_ReportsNotFound;
var
  Form: TForm;
  Lbl: TLabel;
  Edt: TEdit;
begin
  Form := TForm.CreateNew(nil);
  try
    Lbl := MakeLabel(Form);
    Edt := MakeEdit(Form);

    DisplayFFmpegInfo('', '', Lbl, Edt);
    Assert.AreEqual('Not found', Lbl.Caption,
      'fpsNoPath maps to "Not found" with empty value');
    Assert.AreEqual('', Edt.Text);
    Assert.IsFalse(Edt.Visible,
      'ApplyInfoParts hides the edit when the value is empty');
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDialogHelpers.Display_NonExistentInput_ReportsFileMissingWithPath;
var
  Form: TForm;
  Lbl: TLabel;
  Edt: TEdit;
  FakePath: string;
begin
  Form := TForm.CreateNew(nil);
  try
    Lbl := MakeLabel(Form);
    Edt := MakeEdit(Form);
    FakePath := TPath.Combine(TPath.GetTempPath, 'no-such-ffmpeg-' + TGUID.NewGuid.ToString + '.exe');

    DisplayFFmpegInfo(FakePath, '', Lbl, Edt);
    Assert.AreEqual('Not found:', Lbl.Caption,
      'fpsFileMissing label is "Not found:" (with the colon)');
    Assert.AreEqual(FakePath, Edt.Text,
      'fpsFileMissing surfaces the offending path in the edit');
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDialogHelpers.Display_EmptyInputNonExistentFallback_ReportsFileMissing;
var
  Form: TForm;
  Lbl: TLabel;
  Edt: TEdit;
  FakeFallback: string;
begin
  Form := TForm.CreateNew(nil);
  try
    Lbl := MakeLabel(Form);
    Edt := MakeEdit(Form);
    FakeFallback := TPath.Combine(TPath.GetTempPath, 'fallback-' + TGUID.NewGuid.ToString + '.exe');

    DisplayFFmpegInfo('', FakeFallback, Lbl, Edt);
    Assert.AreEqual('Not found:', Lbl.Caption,
      'Empty input falls back to AFallbackPath; non-existent fallback still surfaces as fpsFileMissing');
    Assert.AreEqual(FakeFallback, Edt.Text);
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDialogHelpers.Display_EmptyInputUsesFallbackPath_NotInputPath;
var
  Form: TForm;
  Lbl: TLabel;
  Edt: TEdit;
  FakeFallback: string;
begin
  Form := TForm.CreateNew(nil);
  try
    Lbl := MakeLabel(Form);
    Edt := MakeEdit(Form);
    FakeFallback := TPath.Combine(TPath.GetTempPath, 'fb-' + TGUID.NewGuid.ToString + '.exe');

    {Empty input -> helper consults the fallback path. Pin: the edit
     shows the FALLBACK path, not an empty string or the input.}
    DisplayFFmpegInfo('', FakeFallback, Lbl, Edt);
    Assert.AreEqual(FakeFallback, Edt.Text,
      'When input is empty, fallback is the source of truth for the displayed path');
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDialogHelpers.Display_NonEmptyInputUsesInputPath_NotFallback;
var
  Form: TForm;
  Lbl: TLabel;
  Edt: TEdit;
  Input, Fallback: string;
begin
  Form := TForm.CreateNew(nil);
  try
    Lbl := MakeLabel(Form);
    Edt := MakeEdit(Form);
    Input := TPath.Combine(TPath.GetTempPath, 'input-' + TGUID.NewGuid.ToString + '.exe');
    Fallback := TPath.Combine(TPath.GetTempPath, 'fb-' + TGUID.NewGuid.ToString + '.exe');

    {Non-empty input -> helper uses Input, NEVER touches Fallback even
     when Input is missing. Pin: the edit shows the INPUT path.}
    DisplayFFmpegInfo(Input, Fallback, Lbl, Edt);
    Assert.AreEqual(Input, Edt.Text,
      'When input is non-empty, input is the source of truth; fallback is ignored');
  finally
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsDialogHelpers);

end.
