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
    GbxGeneral: TGroupBox;
    LblFrameCount: TLabel;
    EdtFrameCount: TEdit;
    UdFrameCount: TUpDown;
    LblSkipEdges: TLabel;
    EdtSkipEdges: TEdit;
    UdSkipEdges: TUpDown;
    LblSkipEdgesUnit: TLabel;
    LblMaxWorkers: TLabel;
    EdtMaxWorkers: TEdit;
    UdMaxWorkers: TUpDown;
    ChkMaxWorkersAuto: TCheckBox;
    LblMaxThreads: TLabel;
    LblMaxThreadsAuto: TLabel;
    EdtMaxThreads: TEdit;
    UdMaxThreads: TUpDown;
    ChkUseBmpPipe: TCheckBox;
    LblExtensions: TLabel;
    EdtExtensions: TEdit;
    LblFFmpegPath: TLabel;
    EdtFFmpegPath: TEdit;
    BtnFFmpegPath: TButton;
    LblFFmpegInfo: TLabel;
    GbxOutput: TGroupBox;
    LblOutputMode: TLabel;
    CbxOutputMode: TComboBox;
    LblFormat: TLabel;
    CbxFormat: TComboBox;
    LblJpegQuality: TLabel;
    EdtJpegQuality: TEdit;
    UdJpegQuality: TUpDown;
    LblPngCompression: TLabel;
    EdtPngCompression: TEdit;
    UdPngCompression: TUpDown;
    ChkShowFileSizes: TCheckBox;
    GbxCombined: TGroupBox;
    LblColumns: TLabel;
    EdtColumns: TEdit;
    UdColumns: TUpDown;
    LblCellGap: TLabel;
    EdtCellGap: TEdit;
    UdCellGap: TUpDown;
    LblBackground: TLabel;
    PnlBackground: TPanel;
    BtnBackground: TButton;
    ChkTimestamp: TCheckBox;
    BtnDefaults: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    ColorDlg: TColorDialog;
    procedure CbxOutputModeChange(Sender: TObject);
    procedure BtnFFmpegPathClick(Sender: TObject);
    procedure EdtFFmpegPathChange(Sender: TObject);
    procedure ChkMaxWorkersAutoClick(Sender: TObject);
    procedure EdtMaxThreadsChange(Sender: TObject);
    procedure PnlBackgroundClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
  private
    procedure SettingsToControls(ASettings: TWcxSettings);
    procedure ControlsToSettings(ASettings: TWcxSettings);
    procedure UpdateCombinedState;
    procedure UpdateMaxWorkersControls;
    procedure UpdateFFmpegInfo;
  end;

{ Shows the WCX settings dialog. Returns True if the user clicked OK. }
function ShowWcxSettingsDialog(AParentWnd: HWND;
  ASettings: TWcxSettings): Boolean;

implementation

{$R *.dfm}

uses
  uBitmapSaver, uPathExpand, uFFmpegExe, uFFmpegLocator;

procedure TWcxSettingsForm.SettingsToControls(ASettings: TWcxSettings);
begin
  UdFrameCount.Position := ASettings.FramesCount;
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;

  ChkMaxWorkersAuto.Checked := ASettings.MaxWorkers = 0;
  if ASettings.MaxWorkers > 0 then
    UdMaxWorkers.Position := ASettings.MaxWorkers
  else
    UdMaxWorkers.Position := 1;
  if ASettings.MaxThreads > 0 then
    UdMaxThreads.Position := ASettings.MaxThreads
  else
    UdMaxThreads.Position := 0;
  ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  EdtExtensions.Text := ASettings.ExtensionList;
  EdtFFmpegPath.Text := ASettings.FFmpegExePath;

  if ASettings.OutputMode = womCombined then
    CbxOutputMode.ItemIndex := 1
  else
    CbxOutputMode.ItemIndex := 0;

  CbxFormat.ItemIndex := Ord(ASettings.SaveFormat);
  UdJpegQuality.Position := ASettings.JpegQuality;
  UdPngCompression.Position := ASettings.PngCompression;
  ChkShowFileSizes.Checked := ASettings.ShowFileSizes;

  UdColumns.Position := ASettings.CombinedColumns;
  UdCellGap.Position := ASettings.CellGap;
  PnlBackground.Color := ASettings.Background;
  ChkTimestamp.Checked := ASettings.ShowTimestamp;

  UpdateMaxWorkersControls;
  UpdateCombinedState;
  UpdateFFmpegInfo;
end;

procedure TWcxSettingsForm.ControlsToSettings(ASettings: TWcxSettings);
begin
  ASettings.FramesCount := UdFrameCount.Position;
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;

  if ChkMaxWorkersAuto.Checked then
    ASettings.MaxWorkers := 0
  else
    ASettings.MaxWorkers := UdMaxWorkers.Position;
  ASettings.MaxThreads := UdMaxThreads.Position;
  ASettings.UseBmpPipe := ChkUseBmpPipe.Checked;
  ASettings.ExtensionList := EdtExtensions.Text;
  ASettings.FFmpegExePath := EdtFFmpegPath.Text;

  if CbxOutputMode.ItemIndex = 1 then
    ASettings.OutputMode := womCombined
  else
    ASettings.OutputMode := womSeparate;

  ASettings.SaveFormat := TSaveFormat(CbxFormat.ItemIndex);
  ASettings.JpegQuality := UdJpegQuality.Position;
  ASettings.PngCompression := UdPngCompression.Position;
  ASettings.ShowFileSizes := ChkShowFileSizes.Checked;

  ASettings.CombinedColumns := UdColumns.Position;
  ASettings.CellGap := UdCellGap.Position;
  ASettings.Background := PnlBackground.Color;
  ASettings.ShowTimestamp := ChkTimestamp.Checked;
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
  PnlBackground.Enabled := IsCombined;
  BtnBackground.Enabled := IsCombined;
  ChkTimestamp.Enabled := IsCombined;
end;

procedure TWcxSettingsForm.UpdateMaxWorkersControls;
var
  Manual, OnePerFrame: Boolean;
begin
  OnePerFrame := ChkMaxWorkersAuto.Checked;
  Manual := not OnePerFrame;
  LblMaxWorkers.Enabled := Manual;
  EdtMaxWorkers.Enabled := Manual;
  UdMaxWorkers.Enabled := Manual;
  LblMaxThreads.Enabled := OnePerFrame;
  EdtMaxThreads.Enabled := OnePerFrame;
  UdMaxThreads.Enabled := OnePerFrame;
  if not OnePerFrame then
    LblMaxThreadsAuto.Caption := ''
  else if UdMaxThreads.Position < 0 then
    LblMaxThreadsAuto.Caption := '(no limit)'
  else if UdMaxThreads.Position = 0 then
    LblMaxThreadsAuto.Caption := Format('(auto: %d cores)', [CPUCount])
  else
    LblMaxThreadsAuto.Caption := '';
end;

procedure TWcxSettingsForm.UpdateFFmpegInfo;
var
  Path, Ver: string;
begin
  Path := EdtFFmpegPath.Text;
  if Path <> '' then
    Path := ExpandEnvVars(Path)
  else
    Path := FindFFmpegExe(ExtractFilePath(Application.ExeName), '');

  if Path = '' then
  begin
    LblFFmpegInfo.Caption := 'Not found';
    Exit;
  end;

  if not FileExists(Path) then
  begin
    LblFFmpegInfo.Caption := Format('Not found: %s', [Path]);
    Exit;
  end;

  Ver := ValidateFFmpeg(Path);
  if Ver <> '' then
  begin
    if EdtFFmpegPath.Text = '' then
      LblFFmpegInfo.Caption := Format('Detected: %s (%s)', [Path, Ver])
    else
      LblFFmpegInfo.Caption := Format('Version: %s', [Ver]);
  end
  else
    LblFFmpegInfo.Caption := Format('Invalid executable: %s', [Path]);
end;

procedure TWcxSettingsForm.CbxOutputModeChange(Sender: TObject);
begin
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.ChkMaxWorkersAutoClick(Sender: TObject);
begin
  UpdateMaxWorkersControls;
end;

procedure TWcxSettingsForm.EdtMaxThreadsChange(Sender: TObject);
begin
  UpdateMaxWorkersControls;
end;

procedure TWcxSettingsForm.EdtFFmpegPathChange(Sender: TObject);
begin
  UpdateFFmpegInfo;
end;

procedure TWcxSettingsForm.PnlBackgroundClick(Sender: TObject);
begin
  ColorDlg.Color := PnlBackground.Color;
  if ColorDlg.Execute then
    PnlBackground.Color := ColorDlg.Color;
end;

procedure TWcxSettingsForm.BtnFFmpegPathClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if EdtFFmpegPath.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(EdtFFmpegPath.Text));
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      if ValidateFFmpeg(Dlg.FileName) = '' then
      begin
        MessageBox(Handle,
          PChar('The selected file is not a valid ffmpeg executable.'),
          'Glimpse', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      EdtFFmpegPath.Text := Dlg.FileName;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TWcxSettingsForm.BtnDefaultsClick(Sender: TObject);
var
  Defaults: TWcxSettings;
begin
  Defaults := TWcxSettings.Create('');
  try
    SettingsToControls(Defaults);
  finally
    Defaults.Free;
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
