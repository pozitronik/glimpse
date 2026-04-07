{ Settings dialog for configuring plugin behavior.
  Works on TPluginSettings directly; changes take effect only when OK is pressed. }
unit uSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  Winapi.Windows,
  uTypes, uSettings;

type
  TSettingsForm = class(TForm)
    GbxGeneral: TGroupBox;
    LblSkipEdges: TLabel;
    EdtSkipEdges: TEdit;
    UdSkipEdges: TUpDown;
    LblSkipEdgesUnit: TLabel;
    LblMaxWorkers: TLabel;
    EdtMaxWorkers: TEdit;
    UdMaxWorkers: TUpDown;
    ChkMaxWorkersAuto: TCheckBox;
    ChkUseBmpPipe: TCheckBox;
    ChkHwAccel: TCheckBox;
    ChkUseKeyframes: TCheckBox;
    ChkScaledExtraction: TCheckBox;
    LblMinFrameSide: TLabel;
    EdtMinFrameSide: TEdit;
    UdMinFrameSide: TUpDown;
    LblMaxFrameSide: TLabel;
    EdtMaxFrameSide: TEdit;
    UdMaxFrameSide: TUpDown;
    LblMaxThreads: TLabel;
    LblMaxThreadsAuto: TLabel;
    EdtMaxThreads: TEdit;
    UdMaxThreads: TUpDown;
    LblExtensions: TLabel;
    EdtExtensions: TEdit;
    LblFFmpegPath: TLabel;
    EdtFFmpegPath: TEdit;
    BtnFFmpegPath: TButton;
    LblFFmpegInfo: TLabel;
    GbxAppearance: TGroupBox;
    LblBackground: TLabel;
    PnlBackground: TPanel;
    BtnBackground: TButton;
    LblTCBack: TLabel;
    PnlTCBack: TPanel;
    BtnTCBack: TButton;
    LblTCAlpha: TLabel;
    EdtTCAlpha: TEdit;
    UdTCAlpha: TUpDown;
    LblTCAlphaHint: TLabel;
    LblTimestampFont: TLabel;
    EdtTimestampFont: TEdit;
    LblTimestampFontSize: TLabel;
    EdtTimestampFontSize: TEdit;
    UdTimestampFontSize: TUpDown;
    ChkShowToolbar: TCheckBox;
    ChkShowStatusBar: TCheckBox;
    GbxSave: TGroupBox;
    LblSaveFormat: TLabel;
    CbxSaveFormat: TComboBox;
    LblJpegQuality: TLabel;
    EdtJpegQuality: TEdit;
    UdJpegQuality: TUpDown;
    LblPngCompression: TLabel;
    EdtPngCompression: TEdit;
    UdPngCompression: TUpDown;
    LblSaveFolder: TLabel;
    EdtSaveFolder: TEdit;
    BtnSaveFolder: TButton;
    ChkShowBanner: TCheckBox;
    GbxCache: TGroupBox;
    ChkCacheEnabled: TCheckBox;
    LblCacheFolder: TLabel;
    EdtCacheFolder: TEdit;
    BtnCacheFolder: TButton;
    LblCacheFolderInfo: TLabel;
    LblCacheMaxSize: TLabel;
    EdtCacheMaxSize: TEdit;
    UdCacheMaxSize: TUpDown;
    LblCacheMaxSizeUnit: TLabel;
    LblCacheSizeInfo: TLabel;
    BtnClearCache: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    BtnDefaults: TButton;
    ColorDlg: TColorDialog;
    procedure PnlBackgroundClick(Sender: TObject);
    procedure PnlTCBackClick(Sender: TObject);
    procedure CbxSaveFormatChange(Sender: TObject);
    procedure BtnSaveFolderClick(Sender: TObject);
    procedure ChkMaxWorkersAutoClick(Sender: TObject);
    procedure ChkCacheEnabledClick(Sender: TObject);
    procedure BtnCacheFolderClick(Sender: TObject);
    procedure BtnFFmpegPathClick(Sender: TObject);
    procedure EdtFFmpegPathChange(Sender: TObject);
    procedure EdtMaxThreadsChange(Sender: TObject);
    procedure ChkScaledExtractionClick(Sender: TObject);
    procedure EdtCacheFolderChange(Sender: TObject);
    procedure BtnClearCacheClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
  private
    FResolvedFFmpegPath: string;
    procedure SettingsToControls(ASettings: TPluginSettings);
    procedure ControlsToSettings(ASettings: TPluginSettings);
    procedure UpdateMaxWorkersControls;
    procedure UpdateSaveFormatControls;
    procedure UpdateCacheControls;
    procedure UpdateScaledExtractionControls;
    procedure UpdateFFmpegInfo;
    procedure UpdateCacheFolderInfo;
    procedure UpdateCacheSizeInfo;
    procedure PickColor(APanel: TPanel);
    procedure BrowseFolder(AEdit: TEdit);
  end;

{ Shows the settings dialog.
  AResolvedFFmpegPath is the currently active ffmpeg path (may differ from settings
  when auto-detected). Shown as informational text when the explicit path is empty.
  Returns True if the user pressed OK (ASettings is updated).
  Returns False if dismissed (ASettings unchanged). }
function ShowSettingsDialog(ASettings: TPluginSettings; const AResolvedFFmpegPath: string): Boolean;

implementation

{$R *.dfm}

uses
  System.IOUtils,
  uFFmpegExe, uCache, uBitmapSaver, uPathExpand;

procedure TSettingsForm.SettingsToControls(ASettings: TPluginSettings);
begin
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;
  ChkMaxWorkersAuto.Checked := ASettings.MaxWorkers = 0;
  if ASettings.MaxWorkers > 0 then
    UdMaxWorkers.Position := ASettings.MaxWorkers
  else
    UdMaxWorkers.Position := 1;
  ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  ChkHwAccel.Checked := ASettings.HwAccel;
  ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  if ASettings.MaxThreads > 0 then
    UdMaxThreads.Position := ASettings.MaxThreads
  else
    UdMaxThreads.Position := 0;
  ChkScaledExtraction.Checked := ASettings.ScaledExtraction;
  UdMinFrameSide.Position := ASettings.MinFrameSide;
  UdMaxFrameSide.Position := ASettings.MaxFrameSide;
  UpdateMaxWorkersControls;
  UpdateScaledExtractionControls;
  EdtExtensions.Text := ASettings.ExtensionList;
  EdtFFmpegPath.Text := ASettings.FFmpegExePath;

  PnlBackground.Color := ASettings.Background;
  PnlTCBack.Color := ASettings.TimecodeBackColor;
  UdTCAlpha.Position := ASettings.TimecodeBackAlpha;
  EdtTimestampFont.Text := ASettings.TimestampFontName;
  UdTimestampFontSize.Position := ASettings.TimestampFontSize;
  ChkShowToolbar.Checked := ASettings.ShowToolbar;
  ChkShowStatusBar.Checked := ASettings.ShowStatusBar;

  CbxSaveFormat.ItemIndex := Ord(ASettings.SaveFormat);
  UdJpegQuality.Position := ASettings.JpegQuality;
  UdPngCompression.Position := ASettings.PngCompression;
  EdtSaveFolder.Text := ASettings.SaveFolder;
  ChkShowBanner.Checked := ASettings.ShowBanner;

  ChkCacheEnabled.Checked := ASettings.CacheEnabled;
  EdtCacheFolder.Text := ASettings.CacheFolder;
  UdCacheMaxSize.Position := ASettings.CacheMaxSizeMB;

  UpdateSaveFormatControls;
  UpdateCacheControls;
  UpdateFFmpegInfo;
  UpdateCacheFolderInfo;
  UpdateCacheSizeInfo;
end;

procedure TSettingsForm.ControlsToSettings(ASettings: TPluginSettings);
begin
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;
  if ChkMaxWorkersAuto.Checked then
    ASettings.MaxWorkers := 0
  else
    ASettings.MaxWorkers := UdMaxWorkers.Position;
  ASettings.UseBmpPipe := ChkUseBmpPipe.Checked;
  ASettings.HwAccel := ChkHwAccel.Checked;
  ASettings.UseKeyframes := ChkUseKeyframes.Checked;
  ASettings.ScaledExtraction := ChkScaledExtraction.Checked;
  ASettings.MinFrameSide := UdMinFrameSide.Position;
  ASettings.MaxFrameSide := UdMaxFrameSide.Position;
  ASettings.MaxThreads := UdMaxThreads.Position;
  ASettings.ExtensionList := EdtExtensions.Text;

  { Switch to explicit mode when user provides a path }
  if EdtFFmpegPath.Text <> '' then
  begin
    ASettings.FFmpegExePath := EdtFFmpegPath.Text;
    ASettings.FFmpegMode := fmExe;
  end
  else
  begin
    ASettings.FFmpegExePath := '';
    ASettings.FFmpegMode := fmAuto;
  end;

  ASettings.Background := PnlBackground.Color;
  ASettings.TimecodeBackColor := PnlTCBack.Color;
  ASettings.TimecodeBackAlpha := UdTCAlpha.Position;
  ASettings.TimestampFontName := EdtTimestampFont.Text;
  ASettings.TimestampFontSize := UdTimestampFontSize.Position;
  ASettings.ShowToolbar := ChkShowToolbar.Checked;
  ASettings.ShowStatusBar := ChkShowStatusBar.Checked;

  ASettings.SaveFormat := TSaveFormat(CbxSaveFormat.ItemIndex);
  ASettings.JpegQuality := UdJpegQuality.Position;
  ASettings.PngCompression := UdPngCompression.Position;
  ASettings.SaveFolder := EdtSaveFolder.Text;
  ASettings.ShowBanner := ChkShowBanner.Checked;

  ASettings.CacheEnabled := ChkCacheEnabled.Checked;
  ASettings.CacheFolder := EdtCacheFolder.Text;
  ASettings.CacheMaxSizeMB := UdCacheMaxSize.Position;
end;

procedure TSettingsForm.PickColor(APanel: TPanel);
begin
  ColorDlg.Color := APanel.Color;
  if ColorDlg.Execute then
    APanel.Color := ColorDlg.Color;
end;

procedure TSettingsForm.PnlBackgroundClick(Sender: TObject);
begin
  PickColor(PnlBackground);
end;

procedure TSettingsForm.PnlTCBackClick(Sender: TObject);
begin
  PickColor(PnlTCBack);
end;

procedure TSettingsForm.BrowseFolder(AEdit: TEdit);
var
  Dlg: TFileOpenDialog;
begin
  Dlg := TFileOpenDialog.Create(Self);
  try
    Dlg.Options := [fdoPickFolders, fdoPathMustExist];
    if AEdit.Text <> '' then
      Dlg.DefaultFolder := ExpandEnvVars(AEdit.Text);
    if Dlg.Execute then
      AEdit.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TSettingsForm.BtnSaveFolderClick(Sender: TObject);
begin
  BrowseFolder(EdtSaveFolder);
end;

procedure TSettingsForm.BtnCacheFolderClick(Sender: TObject);
begin
  BrowseFolder(EdtCacheFolder);
end;

procedure TSettingsForm.BtnFFmpegPathClick(Sender: TObject);
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
        MessageBox(Handle, PChar('The selected file is not a valid ffmpeg executable.'), 'Glimpse', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      EdtFFmpegPath.Text := Dlg.FileName;
      { OnChange fires automatically and updates the info label }
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TSettingsForm.EdtFFmpegPathChange(Sender: TObject);
begin
  UpdateFFmpegInfo;
end;

procedure TSettingsForm.EdtMaxThreadsChange(Sender: TObject);
begin
  UpdateMaxWorkersControls;
end;

procedure TSettingsForm.EdtCacheFolderChange(Sender: TObject);
begin
  UpdateCacheFolderInfo;
end;

procedure TSettingsForm.BtnClearCacheClick(Sender: TObject);
var
  Dir: string;
  Mgr: ICacheManager;
begin
  Dir := EffectiveCacheFolder(EdtCacheFolder.Text);

  if not TDirectory.Exists(Dir) then
  begin
    UpdateCacheSizeInfo;
    Exit;
  end;

  if MessageBox(Handle, PChar(Format('Delete all cached frames in %s?', [Dir])),
    'Glimpse', MB_OKCANCEL or MB_ICONQUESTION) <> IDOK then
    Exit;

  Mgr := CreateCacheManager(Dir, 0);
  Mgr.Clear;
  UpdateCacheSizeInfo;
end;

procedure TSettingsForm.BtnDefaultsClick(Sender: TObject);
var
  Defaults: TPluginSettings;
begin
  Defaults := TPluginSettings.Create('');
  try
    SettingsToControls(Defaults);
  finally
    Defaults.Free;
  end;
end;

procedure TSettingsForm.CbxSaveFormatChange(Sender: TObject);
begin
  UpdateSaveFormatControls;
end;

procedure TSettingsForm.ChkMaxWorkersAutoClick(Sender: TObject);
begin
  UpdateMaxWorkersControls;
end;

procedure TSettingsForm.ChkScaledExtractionClick(Sender: TObject);
begin
  UpdateScaledExtractionControls;
end;

procedure TSettingsForm.ChkCacheEnabledClick(Sender: TObject);
begin
  UpdateCacheControls;
end;

procedure TSettingsForm.UpdateMaxWorkersControls;
var
  Manual, OnePerFrame: Boolean;
begin
  OnePerFrame := ChkMaxWorkersAuto.Checked;
  Manual := not OnePerFrame;
  LblMaxWorkers.Enabled := Manual;
  EdtMaxWorkers.Enabled := Manual;
  UdMaxWorkers.Enabled := Manual;
  { Limit workers count is only relevant in one-per-frame mode }
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

procedure TSettingsForm.UpdateSaveFormatControls;
var
  IsPNG: Boolean;
begin
  IsPNG := CbxSaveFormat.ItemIndex = Ord(sfPNG);
  LblJpegQuality.Enabled := not IsPNG;
  EdtJpegQuality.Enabled := not IsPNG;
  UdJpegQuality.Enabled := not IsPNG;
  LblPngCompression.Enabled := IsPNG;
  EdtPngCompression.Enabled := IsPNG;
  UdPngCompression.Enabled := IsPNG;
end;

procedure TSettingsForm.UpdateCacheControls;
var
  CacheOn: Boolean;
begin
  CacheOn := ChkCacheEnabled.Checked;
  LblCacheFolder.Enabled := CacheOn;
  EdtCacheFolder.Enabled := CacheOn;
  BtnCacheFolder.Enabled := CacheOn;
  LblCacheMaxSize.Enabled := CacheOn;
  EdtCacheMaxSize.Enabled := CacheOn;
  UdCacheMaxSize.Enabled := CacheOn;
  LblCacheMaxSizeUnit.Enabled := CacheOn;
end;

procedure TSettingsForm.UpdateScaledExtractionControls;
var
  Enabled: Boolean;
begin
  Enabled := ChkScaledExtraction.Checked;
  LblMinFrameSide.Enabled := Enabled;
  EdtMinFrameSide.Enabled := Enabled;
  UdMinFrameSide.Enabled := Enabled;
  LblMaxFrameSide.Enabled := Enabled;
  EdtMaxFrameSide.Enabled := Enabled;
  UdMaxFrameSide.Enabled := Enabled;
end;

procedure TSettingsForm.UpdateFFmpegInfo;
var
  Path, Ver: string;
begin
  if EdtFFmpegPath.Text <> '' then
    Path := ExpandEnvVars(EdtFFmpegPath.Text)
  else
    Path := FResolvedFFmpegPath;

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

procedure TSettingsForm.UpdateCacheFolderInfo;
begin
  if EdtCacheFolder.Text = '' then
    LblCacheFolderInfo.Caption := Format('Default: %s', [DefaultCacheFolder])
  else
    LblCacheFolderInfo.Caption := '';
end;

procedure TSettingsForm.UpdateCacheSizeInfo;
var
  Dir: string;
  Mgr: ICacheManager;
  Total: Int64;
begin
  Dir := EffectiveCacheFolder(EdtCacheFolder.Text);

  if not TDirectory.Exists(Dir) then
  begin
    LblCacheSizeInfo.Caption := '(current: empty)';
    Exit;
  end;

  Mgr := CreateCacheManager(Dir, 0);
  Total := Mgr.GetTotalSize;

  if Total > 0 then
    LblCacheSizeInfo.Caption := Format('(current: %.1f MB)', [Total / (1024 * 1024)])
  else
    LblCacheSizeInfo.Caption := '(current: empty)';
end;

function ShowSettingsDialog(ASettings: TPluginSettings; const AResolvedFFmpegPath: string): Boolean;
var
  Form: TSettingsForm;
begin
  Result := False;
  Form := TSettingsForm.Create(nil);
  try
    Form.FResolvedFFmpegPath := AResolvedFFmpegPath;
    Form.SettingsToControls(ASettings);
    if Form.ShowModal = mrOK then
    begin
      Form.ControlsToSettings(ASettings);
      Result := True;
    end;
  finally
    Form.Free;
  end;
end;

end.
