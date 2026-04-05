{ Configuration dialog for the WCX plugin.
  Shown via ConfigurePacker when the user clicks Configure in TC. }
unit uWcxSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls, Vcl.ComCtrls,
  Vcl.Dialogs,
  Winapi.Windows,
  uWcxSettings;

type
  TWcxSettingsForm = class(TForm)
    GbxExtraction: TGroupBox;
    LblFrameCount: TLabel;
    EdtFrameCount: TEdit;
    UdFrameCount: TUpDown;
    LblSkipEdges: TLabel;
    EdtSkipEdges: TEdit;
    UdSkipEdges: TUpDown;
    LblSkipEdgesUnit: TLabel;
    GbxOutput: TGroupBox;
    LblOutputMode: TLabel;
    CbxOutputMode: TComboBox;
    LblFormat: TLabel;
    CbxFormat: TComboBox;
    LblJpegQuality: TLabel;
    EdtJpegQuality: TEdit;
    UdJpegQuality: TUpDown;
    GbxCombined: TGroupBox;
    LblColumns: TLabel;
    EdtColumns: TEdit;
    UdColumns: TUpDown;
    LblCellGap: TLabel;
    EdtCellGap: TEdit;
    UdCellGap: TUpDown;
    ChkTimestamp: TCheckBox;
    LblFFmpegPath: TLabel;
    EdtFFmpegPath: TEdit;
    BtnBrowse: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    procedure CbxOutputModeChange(Sender: TObject);
    procedure BtnBrowseClick(Sender: TObject);
  private
    procedure SettingsToControls(ASettings: TWcxSettings);
    procedure ControlsToSettings(ASettings: TWcxSettings);
    procedure UpdateCombinedState;
  end;

{ Shows the WCX settings dialog. Returns True if the user clicked OK. }
function ShowWcxSettingsDialog(AParentWnd: HWND;
  ASettings: TWcxSettings): Boolean;

implementation

{$R *.dfm}

uses
  uBitmapSaver, uPathExpand;

procedure TWcxSettingsForm.SettingsToControls(ASettings: TWcxSettings);
begin
  UdFrameCount.Position := ASettings.FramesCount;
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;

  if ASettings.OutputMode = womCombined then
    CbxOutputMode.ItemIndex := 1
  else
    CbxOutputMode.ItemIndex := 0;

  if ASettings.SaveFormat = sfJPEG then
    CbxFormat.ItemIndex := 1
  else
    CbxFormat.ItemIndex := 0;
  UdJpegQuality.Position := ASettings.JpegQuality;

  UdColumns.Position := ASettings.CombinedColumns;
  UdCellGap.Position := ASettings.CellGap;
  ChkTimestamp.Checked := ASettings.ShowTimestamp;

  EdtFFmpegPath.Text := ASettings.FFmpegExePath;

  UpdateCombinedState;
end;

procedure TWcxSettingsForm.ControlsToSettings(ASettings: TWcxSettings);
begin
  ASettings.FramesCount := UdFrameCount.Position;
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;

  if CbxOutputMode.ItemIndex = 1 then
    ASettings.OutputMode := womCombined
  else
    ASettings.OutputMode := womSeparate;

  if CbxFormat.ItemIndex = 1 then
    ASettings.SaveFormat := sfJPEG
  else
    ASettings.SaveFormat := sfPNG;
  ASettings.JpegQuality := UdJpegQuality.Position;

  ASettings.CombinedColumns := UdColumns.Position;
  ASettings.CellGap := UdCellGap.Position;
  ASettings.ShowTimestamp := ChkTimestamp.Checked;

  ASettings.FFmpegExePath := EdtFFmpegPath.Text;
end;

procedure TWcxSettingsForm.UpdateCombinedState;
var
  IsCombined: Boolean;
begin
  IsCombined := CbxOutputMode.ItemIndex = 1;
  GbxCombined.Enabled := IsCombined;
  EdtColumns.Enabled := IsCombined;
  UdColumns.Enabled := IsCombined;
  EdtCellGap.Enabled := IsCombined;
  UdCellGap.Enabled := IsCombined;
  ChkTimestamp.Enabled := IsCombined;
end;

procedure TWcxSettingsForm.CbxOutputModeChange(Sender: TObject);
begin
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.BtnBrowseClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files|*.*';
    Dlg.Title := 'Select ffmpeg.exe';
    if EdtFFmpegPath.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(EdtFFmpegPath.Text));
    if Dlg.Execute then
      EdtFFmpegPath.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

{ Public API }

function ShowWcxSettingsDialog(AParentWnd: HWND;
  ASettings: TWcxSettings): Boolean;
var
  Dlg: TWcxSettingsForm;
begin
  Result := False;
  Dlg := TWcxSettingsForm.Create(nil);
  try
    Dlg.SettingsToControls(ASettings);
    if Dlg.ShowModal = mrOk then
    begin
      Dlg.ControlsToSettings(ASettings);
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
