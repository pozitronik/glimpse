/// ffmpeg-not-found dialog shown when the plugin cannot locate ffmpeg.exe.
/// Created entirely in code (no DFM) to avoid resource complications in DLL context.
unit uFFmpegSetupDlg;

interface

type
  TFFmpegSetupResult = (fsrCancel, fsrBrowsed);

/// Shows the ffmpeg setup dialog.
/// Returns fsrBrowsed if user selected a valid path (written to APath).
/// Returns fsrCancel if dismissed. ADontAskAgain reflects the checkbox state.
function ShowFFmpegSetupDialog(out APath: string;
  out ADontAskAgain: Boolean): TFFmpegSetupResult;

implementation

uses
  System.SysUtils, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Dialogs,
  Vcl.Graphics, Winapi.Windows;

type
  TSetupForm = class(TForm)
  private
    FChkDontAsk: TCheckBox;
    FSelectedPath: string;
    procedure OnBrowseClick(Sender: TObject);
  public
    property SelectedPath: string read FSelectedPath;
    property ChkDontAsk: TCheckBox read FChkDontAsk write FChkDontAsk;
  end;

procedure TSetupForm.OnBrowseClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      FSelectedPath := Dlg.FileName;
      ModalResult := mrOK;
    end;
  finally
    Dlg.Free;
  end;
end;

function ShowFFmpegSetupDialog(out APath: string;
  out ADontAskAgain: Boolean): TFFmpegSetupResult;
var
  Form: TSetupForm;
  LblTitle, LblMsg: TLabel;
  BtnBrowse, BtnCancel: TButton;
begin
  Result := fsrCancel;
  APath := '';
  ADontAskAgain := False;

  Form := TSetupForm.CreateNew(nil);
  try
    Form.Caption := 'VideoThumb';
    Form.ClientWidth := 380;
    Form.ClientHeight := 170;
    Form.Position := poScreenCenter;
    Form.BorderStyle := bsDialog;
    Form.BorderIcons := [biSystemMenu];

    LblTitle := TLabel.Create(Form);
    LblTitle.Parent := Form;
    LblTitle.Left := 20;
    LblTitle.Top := 16;
    LblTitle.Caption := 'VideoThumb requires ffmpeg';
    LblTitle.Font.Style := [fsBold];
    LblTitle.Font.Size := 10;

    LblMsg := TLabel.Create(Form);
    LblMsg.Parent := Form;
    LblMsg.Left := 20;
    LblMsg.Top := 44;
    LblMsg.Caption := 'ffmpeg was not found on this system.';

    BtnBrowse := TButton.Create(Form);
    BtnBrowse.Parent := Form;
    BtnBrowse.Left := 20;
    BtnBrowse.Top := 76;
    BtnBrowse.Width := 200;
    BtnBrowse.Height := 28;
    BtnBrowse.Caption := 'Browse for ffmpeg.exe...';
    BtnBrowse.OnClick := Form.OnBrowseClick;

    BtnCancel := TButton.Create(Form);
    BtnCancel.Parent := Form;
    BtnCancel.Left := 230;
    BtnCancel.Top := 76;
    BtnCancel.Width := 130;
    BtnCancel.Height := 28;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    Form.ChkDontAsk := TCheckBox.Create(Form);
    Form.ChkDontAsk.Parent := Form;
    Form.ChkDontAsk.Left := 20;
    Form.ChkDontAsk.Top := 124;
    Form.ChkDontAsk.Width := 300;
    Form.ChkDontAsk.Caption := 'Don''t ask again';

    if Form.ShowModal = mrOK then
    begin
      APath := Form.SelectedPath;
      Result := fsrBrowsed;
    end;

    ADontAskAgain := Form.ChkDontAsk.Checked;
  finally
    Form.Free;
  end;
end;

end.
