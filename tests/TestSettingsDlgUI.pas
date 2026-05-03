unit TestSettingsDlgUI;

{Tests for uSettingsDlgUI -- the VCL-touching helpers shared by the WLX
 and WCX settings dialogs. Coverage is intentionally limited to the two
 readout formatters (RefreshTimestampFontEdit / RefreshBannerFontEdit)
 because the Pick* helpers call AFontDialog.Execute / AColorDialog.Execute,
 which open real Windows dialogs and cannot be driven headlessly.}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsDlgUI = class
  public
    [Test] procedure Timestamp_FormatsNameAndSize;
    [Test] procedure Timestamp_HandlesEmptyName;
    [Test] procedure Banner_AutoOff_FormatsAsPoints;
    [Test] procedure Banner_AutoOn_FormatsAsAuto;
    [Test] procedure Banner_AutoOn_IgnoresSizeArgument;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  uSettingsDlgUI;

{Helpers: each test creates a parent form so VCL controls have a window
 handle, then frees the form which disposes its children.}

procedure TTestSettingsDlgUI.Timestamp_FormatsNameAndSize;
var
  Form: TForm;
  Edit: TEdit;
begin
  Form := TForm.CreateNew(nil);
  try
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    RefreshTimestampFontEdit(Edit, 'Consolas', 9);
    Assert.AreEqual('Consolas, 9 pt', Edit.Text);
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDlgUI.Timestamp_HandlesEmptyName;
var
  Form: TForm;
  Edit: TEdit;
begin
  {Empty name is not a valid font but the formatter has no business
   rejecting it -- it renders whatever the caller hands in. Pinning this
   contract so a future "validate name" change does not silently break
   the read-only display path.}
  Form := TForm.CreateNew(nil);
  try
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    RefreshTimestampFontEdit(Edit, '', 12);
    Assert.AreEqual(', 12 pt', Edit.Text);
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDlgUI.Banner_AutoOff_FormatsAsPoints;
var
  Form: TForm;
  Edit: TEdit;
begin
  Form := TForm.CreateNew(nil);
  try
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    RefreshBannerFontEdit(Edit, False, 'Segoe UI', 10);
    Assert.AreEqual('Segoe UI, 10 pt', Edit.Text);
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDlgUI.Banner_AutoOn_FormatsAsAuto;
var
  Form: TForm;
  Edit: TEdit;
begin
  Form := TForm.CreateNew(nil);
  try
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    RefreshBannerFontEdit(Edit, True, 'Segoe UI', 10);
    Assert.AreEqual('Segoe UI, auto', Edit.Text);
  finally
    Form.Free;
  end;
end;

procedure TTestSettingsDlgUI.Banner_AutoOn_IgnoresSizeArgument;
var
  Form: TForm;
  Edit: TEdit;
begin
  {Size 0 is sentinel for "unset" inside the dialog. With auto on the
   formatter must not show "0 pt" -- it must use the auto-suffix instead.
   Pinning the contract that auto wins over size when both are present.}
  Form := TForm.CreateNew(nil);
  try
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    RefreshBannerFontEdit(Edit, True, 'Segoe UI', 0);
    Assert.AreEqual('Segoe UI, auto', Edit.Text);
  finally
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsDlgUI);

end.
