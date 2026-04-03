{ ffmpeg-not-found dialog shown when the plugin cannot locate ffmpeg.exe. }
unit uFFmpegSetupDlg;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls,
  Vcl.Dialogs, Winapi.Windows;

type
  TFFmpegSetupResult = (fsrCancel, fsrBrowsed);

  TFFmpegSetupForm = class(TForm)
    LblTitle: TLabel;
    LblMsg: TLabel;
    BtnBrowse: TButton;
    BtnCancel: TButton;
    procedure BtnBrowseClick(Sender: TObject);
  private
    FSelectedPath: string;
  public
    property SelectedPath: string read FSelectedPath;
  end;

{ Shows the ffmpeg setup dialog.
  Returns fsrBrowsed if user selected a valid path (written to APath).
  Returns fsrCancel if dismissed. }
function ShowFFmpegSetupDialog(out APath: string): TFFmpegSetupResult;

implementation

{$R *.dfm}

uses
  uFFmpegExe;

procedure TFFmpegSetupForm.BtnBrowseClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  Ver: string;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      Ver := ValidateFFmpeg(Dlg.FileName);
      if Ver = '' then
      begin
        MessageBox(Handle,
          PChar('The selected file is not a valid ffmpeg executable.'),
          'VideoThumb', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      FSelectedPath := Dlg.FileName;
      ModalResult := mrOK;
    end;
  finally
    Dlg.Free;
  end;
end;

function ShowFFmpegSetupDialog(out APath: string): TFFmpegSetupResult;
var
  Form: TFFmpegSetupForm;
begin
  Result := fsrCancel;
  APath := '';

  Form := TFFmpegSetupForm.Create(nil);
  try
    if Form.ShowModal = mrOK then
    begin
      APath := Form.SelectedPath;
      Result := fsrBrowsed;
    end;
  finally
    Form.Free;
  end;
end;

end.
