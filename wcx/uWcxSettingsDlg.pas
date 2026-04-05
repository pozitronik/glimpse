{ Configuration dialog for the WCX plugin.
  Shown via ConfigurePacker when the user clicks Configure in TC. }
unit uWcxSettingsDlg;

interface

uses
  Winapi.Windows, uWcxSettings;

{ Shows the WCX settings dialog. Returns True if the user clicked OK. }
function ShowWcxSettingsDialog(AParentWnd: HWND;
  ASettings: TWcxSettings): Boolean;

implementation

uses
  System.SysUtils, System.Math, System.UITypes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls, Vcl.ComCtrls,
  Vcl.Graphics, Vcl.Dialogs,
  uBitmapSaver, uPathExpand;

const
  DLG_W = 420;
  DLG_H = 460;
  MARGIN = 12;
  ROW_H = 26;
  LBL_W = 130;

type
  TWcxSettingsForm = class(TForm)
  private
    FSettings: TWcxSettings;
    { Extraction }
    FEdtFrames: TEdit;
    FUdFrames: TUpDown;
    FEdtSkipEdges: TEdit;
    FUdSkipEdges: TUpDown;
    { Output }
    FCmbOutputMode: TComboBox;
    FCmbFormat: TComboBox;
    FEdtJpegQuality: TEdit;
    FUdJpegQuality: TUpDown;
    { Combined }
    FGrpCombined: TGroupBox;
    FEdtColumns: TEdit;
    FUdColumns: TUpDown;
    FChkTimestamp: TCheckBox;
    FEdtCellGap: TEdit;
    FUdCellGap: TUpDown;
    { FFmpeg }
    FEdtFFmpegPath: TEdit;
    FBtnBrowse: TButton;
    { Buttons }
    FBtnOK: TButton;
    FBtnCancel: TButton;

    procedure BuildUI;
    procedure LoadFromSettings;
    procedure SaveToSettings;
    procedure UpdateCombinedState;
    procedure OnOutputModeChange(Sender: TObject);
    procedure OnBrowseClick(Sender: TObject);
    procedure OnOKClick(Sender: TObject);
  public
    constructor CreateForSettings(AOwnerWnd: HWND; ASettings: TWcxSettings);
  end;

{ TWcxSettingsForm }

constructor TWcxSettingsForm.CreateForSettings(AOwnerWnd: HWND;
  ASettings: TWcxSettings);
begin
  CreateNew(nil);
  FSettings := ASettings;

  BorderStyle := bsDialog;
  Caption := 'Glimpse WCX Settings';
  ClientWidth := DLG_W;
  ClientHeight := DLG_H;
  Position := poScreenCenter;

  BuildUI;
  LoadFromSettings;
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.BuildUI;
var
  Y: Integer;

  function AddLabel(AParent: TWinControl; ATop: Integer;
    const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Left := MARGIN;
    Result.Top := ATop + 3;
    Result.Caption := ACaption;
  end;

  function AddSpinEdit(AParent: TWinControl; ATop, AMin, AMax,
    ALeft, AWidth: Integer): TUpDown;
  var
    Edt: TEdit;
  begin
    Edt := TEdit.Create(Self);
    Edt.Parent := AParent;
    Edt.SetBounds(ALeft, ATop, AWidth, 23);
    Edt.NumbersOnly := True;
    Result := TUpDown.Create(Self);
    Result.Parent := AParent;
    Result.Associate := Edt;
    Result.Min := AMin;
    Result.Max := AMax;
  end;

begin
  Y := MARGIN;

  { Extraction group }
  AddLabel(Self, Y, 'Frame count:');
  FEdtFrames := TEdit.Create(Self);
  FEdtFrames.Parent := Self;
  FEdtFrames.SetBounds(LBL_W, Y, 50, 23);
  FEdtFrames.NumbersOnly := True;
  FUdFrames := TUpDown.Create(Self);
  FUdFrames.Parent := Self;
  FUdFrames.Associate := FEdtFrames;
  FUdFrames.Min := 1;
  FUdFrames.Max := 99;
  Inc(Y, ROW_H + 4);

  AddLabel(Self, Y, 'Skip edges (%):');
  FEdtSkipEdges := TEdit.Create(Self);
  FEdtSkipEdges.Parent := Self;
  FEdtSkipEdges.SetBounds(LBL_W, Y, 50, 23);
  FEdtSkipEdges.NumbersOnly := True;
  FUdSkipEdges := TUpDown.Create(Self);
  FUdSkipEdges.Parent := Self;
  FUdSkipEdges.Associate := FEdtSkipEdges;
  FUdSkipEdges.Min := 0;
  FUdSkipEdges.Max := 49;
  Inc(Y, ROW_H + 8);

  { Output group }
  AddLabel(Self, Y, 'Output mode:');
  FCmbOutputMode := TComboBox.Create(Self);
  FCmbOutputMode.Parent := Self;
  FCmbOutputMode.Style := csDropDownList;
  FCmbOutputMode.SetBounds(LBL_W, Y, 150, 23);
  FCmbOutputMode.Items.Add('Separate frames');
  FCmbOutputMode.Items.Add('Combined image');
  FCmbOutputMode.OnChange := OnOutputModeChange;
  Inc(Y, ROW_H + 4);

  AddLabel(Self, Y, 'Image format:');
  FCmbFormat := TComboBox.Create(Self);
  FCmbFormat.Parent := Self;
  FCmbFormat.Style := csDropDownList;
  FCmbFormat.SetBounds(LBL_W, Y, 150, 23);
  FCmbFormat.Items.Add('PNG');
  FCmbFormat.Items.Add('JPEG');
  Inc(Y, ROW_H + 4);

  AddLabel(Self, Y, 'JPEG quality:');
  FEdtJpegQuality := TEdit.Create(Self);
  FEdtJpegQuality.Parent := Self;
  FEdtJpegQuality.SetBounds(LBL_W, Y, 50, 23);
  FEdtJpegQuality.NumbersOnly := True;
  FUdJpegQuality := TUpDown.Create(Self);
  FUdJpegQuality.Parent := Self;
  FUdJpegQuality.Associate := FEdtJpegQuality;
  FUdJpegQuality.Min := 1;
  FUdJpegQuality.Max := 100;
  Inc(Y, ROW_H + 8);

  { Combined image options }
  FGrpCombined := TGroupBox.Create(Self);
  FGrpCombined.Parent := Self;
  FGrpCombined.Caption := ' Combined image ';
  FGrpCombined.SetBounds(MARGIN, Y, DLG_W - 2 * MARGIN, 120);

  AddLabel(FGrpCombined, 20, 'Columns (0=auto):');
  FEdtColumns := TEdit.Create(Self);
  FEdtColumns.Parent := FGrpCombined;
  FEdtColumns.SetBounds(LBL_W, 18, 50, 23);
  FEdtColumns.NumbersOnly := True;
  FUdColumns := TUpDown.Create(Self);
  FUdColumns.Parent := FGrpCombined;
  FUdColumns.Associate := FEdtColumns;
  FUdColumns.Min := 0;
  FUdColumns.Max := 20;

  AddLabel(FGrpCombined, 50, 'Cell gap (px):');
  FEdtCellGap := TEdit.Create(Self);
  FEdtCellGap.Parent := FGrpCombined;
  FEdtCellGap.SetBounds(LBL_W, 48, 50, 23);
  FEdtCellGap.NumbersOnly := True;
  FUdCellGap := TUpDown.Create(Self);
  FUdCellGap.Parent := FGrpCombined;
  FUdCellGap.Associate := FEdtCellGap;
  FUdCellGap.Min := 0;
  FUdCellGap.Max := 20;

  FChkTimestamp := TCheckBox.Create(Self);
  FChkTimestamp.Parent := FGrpCombined;
  FChkTimestamp.SetBounds(MARGIN, 80, 200, 20);
  FChkTimestamp.Caption := 'Show timestamps on frames';

  Inc(Y, 128);

  { FFmpeg path }
  AddLabel(Self, Y, 'FFmpeg path:');
  FEdtFFmpegPath := TEdit.Create(Self);
  FEdtFFmpegPath.Parent := Self;
  FEdtFFmpegPath.SetBounds(LBL_W, Y, DLG_W - LBL_W - MARGIN - 34, 23);
  FBtnBrowse := TButton.Create(Self);
  FBtnBrowse.Parent := Self;
  FBtnBrowse.SetBounds(DLG_W - MARGIN - 30, Y, 30, 23);
  FBtnBrowse.Caption := '...';
  FBtnBrowse.OnClick := OnBrowseClick;
  Inc(Y, ROW_H + 16);

  { OK / Cancel }
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := Self;
  FBtnCancel.Caption := 'Cancel';
  FBtnCancel.SetBounds(DLG_W - MARGIN - 80, Y, 80, 28);
  FBtnCancel.Cancel := True;
  FBtnCancel.ModalResult := mrCancel;

  FBtnOK := TButton.Create(Self);
  FBtnOK.Parent := Self;
  FBtnOK.Caption := 'OK';
  FBtnOK.SetBounds(DLG_W - MARGIN - 80 - 8 - 80, Y, 80, 28);
  FBtnOK.Default := True;
  FBtnOK.OnClick := OnOKClick;

  ClientHeight := Y + 28 + MARGIN;
end;

procedure TWcxSettingsForm.LoadFromSettings;
begin
  FUdFrames.Position := FSettings.FramesCount;
  FUdSkipEdges.Position := FSettings.SkipEdgesPercent;

  if FSettings.OutputMode = womCombined then
    FCmbOutputMode.ItemIndex := 1
  else
    FCmbOutputMode.ItemIndex := 0;

  if FSettings.SaveFormat = sfJPEG then
    FCmbFormat.ItemIndex := 1
  else
    FCmbFormat.ItemIndex := 0;
  FUdJpegQuality.Position := FSettings.JpegQuality;

  FUdColumns.Position := FSettings.CombinedColumns;
  FUdCellGap.Position := FSettings.CellGap;
  FChkTimestamp.Checked := FSettings.ShowTimestamp;

  FEdtFFmpegPath.Text := FSettings.FFmpegExePath;
end;

procedure TWcxSettingsForm.SaveToSettings;
begin
  FSettings.FramesCount := FUdFrames.Position;
  FSettings.SkipEdgesPercent := FUdSkipEdges.Position;

  if FCmbOutputMode.ItemIndex = 1 then
    FSettings.OutputMode := womCombined
  else
    FSettings.OutputMode := womSeparate;

  if FCmbFormat.ItemIndex = 1 then
    FSettings.SaveFormat := sfJPEG
  else
    FSettings.SaveFormat := sfPNG;
  FSettings.JpegQuality := FUdJpegQuality.Position;

  FSettings.CombinedColumns := FUdColumns.Position;
  FSettings.CellGap := FUdCellGap.Position;
  FSettings.ShowTimestamp := FChkTimestamp.Checked;

  FSettings.FFmpegExePath := FEdtFFmpegPath.Text;
end;

procedure TWcxSettingsForm.UpdateCombinedState;
var
  IsCombined: Boolean;
begin
  IsCombined := FCmbOutputMode.ItemIndex = 1;
  FGrpCombined.Enabled := IsCombined;
  FEdtColumns.Enabled := IsCombined;
  FUdColumns.Enabled := IsCombined;
  FEdtCellGap.Enabled := IsCombined;
  FUdCellGap.Enabled := IsCombined;
  FChkTimestamp.Enabled := IsCombined;
end;

procedure TWcxSettingsForm.OnOutputModeChange(Sender: TObject);
begin
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.OnBrowseClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files|*.*';
    Dlg.Title := 'Select ffmpeg.exe';
    if FEdtFFmpegPath.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(FEdtFFmpegPath.Text));
    if Dlg.Execute then
      FEdtFFmpegPath.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TWcxSettingsForm.OnOKClick(Sender: TObject);
begin
  SaveToSettings;
  ModalResult := mrOk;
end;

{ Public API }

function ShowWcxSettingsDialog(AParentWnd: HWND;
  ASettings: TWcxSettings): Boolean;
var
  Dlg: TWcxSettingsForm;
begin
  Dlg := TWcxSettingsForm.CreateForSettings(AParentWnd, ASettings);
  try
    Result := Dlg.ShowModal = mrOk;
  finally
    Dlg.Free;
  end;
end;

end.
