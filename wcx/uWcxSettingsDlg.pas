{Configuration dialog for the WCX plugin.
 Shown via ConfigurePacker when the user clicks Configure in TC.}
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
    PageControl: TPageControl;
    TshGeneral: TTabSheet;
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
    ChkHwAccel: TCheckBox;
    ChkUseKeyframes: TCheckBox;
    ChkRespectAnamorphic: TCheckBox;
    LblFFmpegPath: TLabel;
    EdtFFmpegPath: TEdit;
    BtnFFmpegPath: TButton;
    LblFFmpegInfo: TLabel;
    TshOutput: TTabSheet;
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
    TshCombined: TTabSheet;
    LblColumns: TLabel;
    EdtColumns: TEdit;
    UdColumns: TUpDown;
    LblBackground: TLabel;
    PnlBackground: TPanel;
    BtnBackground: TButton;
    LblCellGap: TLabel;
    EdtCellGap: TEdit;
    UdCellGap: TUpDown;
    LblBorder: TLabel;
    EdtBorder: TEdit;
    UdBorder: TUpDown;
    ChkTimestamp: TCheckBox;
    CbxTimestampCorner: TComboBox;
    LblTCBack: TLabel;
    PnlTCBack: TPanel;
    BtnTCBack: TButton;
    LblTCAlpha: TLabel;
    EdtTCAlpha: TEdit;
    UdTCAlpha: TUpDown;
    LblTCTextColor: TLabel;
    PnlTCTextColor: TPanel;
    BtnTCTextColor: TButton;
    LblTCTextAlpha: TLabel;
    EdtTCTextAlpha: TEdit;
    UdTCTextAlpha: TUpDown;
    LblTimestampFont: TLabel;
    EdtTimestampFont: TEdit;
    BtnTimestampFont: TButton;
    ChkShowBanner: TCheckBox;
    LblBannerBackground: TLabel;
    PnlBannerBackground: TPanel;
    BtnBannerBackground: TButton;
    LblBannerTextColor: TLabel;
    PnlBannerTextColor: TPanel;
    BtnBannerTextColor: TButton;
    LblBannerFont: TLabel;
    EdtBannerFont: TEdit;
    BtnBannerFont: TButton;
    ChkBannerAutoSize: TCheckBox;
    LblBannerPosition: TLabel;
    CbxBannerPosition: TComboBox;
    FontDlg: TFontDialog;
    TshLimits: TTabSheet;
    LblLimitsHint: TLabel;
    LblFrameMax: TLabel;
    LblCombinedMax: TLabel;
    EdtFrameMax: TEdit;
    UdFrameMax: TUpDown;
    EdtCombinedMax: TEdit;
    UdCombinedMax: TUpDown;
    PnlButtons: TPanel;
    BtnDefaults: TButton;
    BtnApply: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    ColorDlg: TColorDialog;
    procedure CbxOutputModeChange(Sender: TObject);
    procedure BtnFFmpegPathClick(Sender: TObject);
    procedure EdtFFmpegPathChange(Sender: TObject);
    procedure ChkMaxWorkersAutoClick(Sender: TObject);
    procedure EdtMaxThreadsChange(Sender: TObject);
    procedure PnlBackgroundClick(Sender: TObject);
    procedure PnlTCBackClick(Sender: TObject);
    procedure PnlTCTextColorClick(Sender: TObject);
    procedure PnlBannerBackgroundClick(Sender: TObject);
    procedure PnlBannerTextColorClick(Sender: TObject);
    procedure ChkShowBannerClick(Sender: TObject);
    procedure ChkBannerAutoSizeClick(Sender: TObject);
    procedure BtnTimestampFontClick(Sender: TObject);
    procedure BtnBannerFontClick(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
  private
    FOwnerWnd: HWND;
    FSettings: TWcxSettings;
    FOnApply: TProc;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBannerFontName: string;
    FBannerFontSize: Integer;
    procedure SettingsToControls(ASettings: TWcxSettings);
    procedure ControlsToSettings(ASettings: TWcxSettings);
    procedure UpdateCombinedState;
    procedure UpdateMaxWorkersControls;
    procedure UpdateFFmpegInfo;
    procedure UpdateTimestampFontDisplay;
    procedure UpdateBannerFontDisplay;
    procedure PickColor(APanel: TPanel);
    procedure PickTimestampFont;
    procedure PickBannerFont;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor CreateWithOwner(AOwnerWnd: HWND);
  end;

  {Shows the WCX settings dialog. Returns True if the user clicked OK.
   AOnApply fires after every Apply press; the settings object has already
   been updated and persisted to the INI by the time the callback runs.}
function ShowWcxSettingsDialog(AParentWnd: HWND; ASettings: TWcxSettings; AOnApply: TProc = nil): Boolean;

implementation

{$R *.dfm}

uses
  System.Math,
  uBitmapSaver, uPathExpand, uFFmpegExe, uFFmpegLocator, uSettingsDlgLogic,
  uDefaults, uTypes;

procedure TWcxSettingsForm.SettingsToControls(ASettings: TWcxSettings);
var
  AutoChecked, ShowChecked: Boolean;
  UdPos, ComboIdx: Integer;
begin
  UdFrameCount.Position := ASettings.FramesCount;
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;

  DecodeMaxWorkersControls(ASettings.MaxWorkers, AutoChecked, UdPos);
  ChkMaxWorkersAuto.Checked := AutoChecked;
  UdMaxWorkers.Position := UdPos;
  UdMaxThreads.Position := DecodeMaxThreadsControl(ASettings.MaxThreads);
  ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  ChkHwAccel.Checked := ASettings.HwAccel;
  ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  ChkRespectAnamorphic.Checked := ASettings.RespectAnamorphic;
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
  UdBorder.Position := ASettings.CombinedBorder;
  PnlBackground.Color := ASettings.Background;
  DecodeTimestampCornerControls(ASettings.ShowTimestamp, ASettings.TimestampCorner,
    ShowChecked, ComboIdx);
  ChkTimestamp.Checked := ShowChecked;
  CbxTimestampCorner.ItemIndex := ComboIdx;
  PnlTCBack.Color := ASettings.TimecodeBackColor;
  UdTCAlpha.Position := ASettings.TimecodeBackAlpha;
  PnlTCTextColor.Color := ASettings.TimestampTextColor;
  UdTCTextAlpha.Position := ASettings.TimestampTextAlpha;
  FTimestampFontName := ASettings.TimestampFontName;
  FTimestampFontSize := ASettings.TimestampFontSize;
  UpdateTimestampFontDisplay;
  ChkShowBanner.Checked := ASettings.ShowBanner;
  PnlBannerBackground.Color := ASettings.BannerBackground;
  PnlBannerTextColor.Color := ASettings.BannerTextColor;
  FBannerFontName := ASettings.BannerFontName;
  FBannerFontSize := ASettings.BannerFontSize;
  ChkBannerAutoSize.Checked := ASettings.BannerFontAutoSize;
  UpdateBannerFontDisplay;
  CbxBannerPosition.ItemIndex := Ord(ASettings.BannerPosition);

  UdFrameMax.Position := ASettings.FrameMaxSide;
  UdCombinedMax.Position := ASettings.CombinedMaxSide;

  UpdateMaxWorkersControls;
  UpdateCombinedState;
  UpdateFFmpegInfo;
end;

procedure TWcxSettingsForm.ControlsToSettings(ASettings: TWcxSettings);
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  ASettings.FramesCount := UdFrameCount.Position;
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;

  ASettings.MaxWorkers := EncodeMaxWorkersControls(ChkMaxWorkersAuto.Checked,
    UdMaxWorkers.Position);
  ASettings.MaxThreads := UdMaxThreads.Position;
  ASettings.UseBmpPipe := ChkUseBmpPipe.Checked;
  ASettings.HwAccel := ChkHwAccel.Checked;
  ASettings.UseKeyframes := ChkUseKeyframes.Checked;
  ASettings.RespectAnamorphic := ChkRespectAnamorphic.Checked;
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
  ASettings.CombinedBorder := UdBorder.Position;
  ASettings.Background := PnlBackground.Color;
  EncodeTimestampCornerControls(ChkTimestamp.Checked, CbxTimestampCorner.ItemIndex,
    Show, Corner);
  ASettings.ShowTimestamp := Show;
  ASettings.TimestampCorner := Corner;
  ASettings.TimecodeBackColor := PnlTCBack.Color;
  ASettings.TimecodeBackAlpha := UdTCAlpha.Position;
  ASettings.TimestampTextColor := PnlTCTextColor.Color;
  ASettings.TimestampTextAlpha := UdTCTextAlpha.Position;
  ASettings.TimestampFontName := FTimestampFontName;
  ASettings.TimestampFontSize := FTimestampFontSize;
  ASettings.ShowBanner := ChkShowBanner.Checked;
  ASettings.BannerBackground := PnlBannerBackground.Color;
  ASettings.BannerTextColor := PnlBannerTextColor.Color;
  ASettings.BannerFontName := FBannerFontName;
  ASettings.BannerFontSize := FBannerFontSize;
  ASettings.BannerFontAutoSize := ChkBannerAutoSize.Checked;
  ASettings.BannerPosition := TBannerPosition(CbxBannerPosition.ItemIndex);

  ASettings.FrameMaxSide := UdFrameMax.Position;
  ASettings.CombinedMaxSide := UdCombinedMax.Position;
end;

procedure TWcxSettingsForm.UpdateCombinedState;
var
  IsCombined, BannerOn: Boolean;
begin
  IsCombined := CbxOutputMode.ItemIndex = 1;
  LblColumns.Enabled := IsCombined;
  EdtColumns.Enabled := IsCombined;
  UdColumns.Enabled := IsCombined;
  LblCellGap.Enabled := IsCombined;
  EdtCellGap.Enabled := IsCombined;
  UdCellGap.Enabled := IsCombined;
  LblBorder.Enabled := IsCombined;
  EdtBorder.Enabled := IsCombined;
  UdBorder.Enabled := IsCombined;
  LblBackground.Enabled := IsCombined;
  PnlBackground.Enabled := IsCombined;
  BtnBackground.Enabled := IsCombined;
  ChkTimestamp.Enabled := IsCombined;
  CbxTimestampCorner.Enabled := IsCombined;
  LblTCBack.Enabled := IsCombined;
  PnlTCBack.Enabled := IsCombined;
  BtnTCBack.Enabled := IsCombined;
  LblTCAlpha.Enabled := IsCombined;
  EdtTCAlpha.Enabled := IsCombined;
  UdTCAlpha.Enabled := IsCombined;
  LblTCTextColor.Enabled := IsCombined;
  PnlTCTextColor.Enabled := IsCombined;
  BtnTCTextColor.Enabled := IsCombined;
  LblTCTextAlpha.Enabled := IsCombined;
  EdtTCTextAlpha.Enabled := IsCombined;
  UdTCTextAlpha.Enabled := IsCombined;
  LblTimestampFont.Enabled := IsCombined;
  EdtTimestampFont.Enabled := IsCombined;
  BtnTimestampFont.Enabled := IsCombined;
  ChkShowBanner.Enabled := IsCombined;

  BannerOn := IsCombined and ChkShowBanner.Checked;
  LblBannerBackground.Enabled := BannerOn;
  PnlBannerBackground.Enabled := BannerOn;
  BtnBannerBackground.Enabled := BannerOn;
  LblBannerTextColor.Enabled := BannerOn;
  PnlBannerTextColor.Enabled := BannerOn;
  BtnBannerTextColor.Enabled := BannerOn;
  LblBannerFont.Enabled := BannerOn;
  EdtBannerFont.Enabled := BannerOn;
  BtnBannerFont.Enabled := BannerOn;
  ChkBannerAutoSize.Enabled := BannerOn;
  LblBannerPosition.Enabled := BannerOn;
  CbxBannerPosition.Enabled := BannerOn;
end;

procedure TWcxSettingsForm.UpdateMaxWorkersControls;
var
  OnePerFrame: Boolean;
begin
  OnePerFrame := ChkMaxWorkersAuto.Checked;
  LblMaxWorkers.Enabled := not OnePerFrame;
  EdtMaxWorkers.Enabled := not OnePerFrame;
  UdMaxWorkers.Enabled := not OnePerFrame;
  LblMaxThreads.Enabled := OnePerFrame;
  EdtMaxThreads.Enabled := OnePerFrame;
  UdMaxThreads.Enabled := OnePerFrame;
  LblMaxThreadsAuto.Caption := MaxThreadsAutoLabel(OnePerFrame, UdMaxThreads.Position, CPUCount);
end;

procedure TWcxSettingsForm.UpdateFFmpegInfo;
var
  Input, Path, Ver: string;
  State: TFFmpegProbeState;
begin
  Input := EdtFFmpegPath.Text;
  if Input <> '' then
    Path := ExpandEnvVars(Input)
  else
    Path := FindFFmpegExe(ExtractFilePath(Application.ExeName), '');

  Ver := '';
  if Path = '' then
    State := fpsNoPath
  else if not FileExists(Path) then
    State := fpsFileMissing
  else
  begin
    Ver := ValidateFFmpeg(Path);
    if Ver = '' then
      State := fpsInvalid
    else
      State := fpsValid;
  end;

  LblFFmpegInfo.Caption := FFmpegInfoLabelText(State, Path, Ver, Input = '');
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

procedure TWcxSettingsForm.PickColor(APanel: TPanel);
begin
  ColorDlg.Color := APanel.Color;
  if ColorDlg.Execute then
    APanel.Color := ColorDlg.Color;
end;

procedure TWcxSettingsForm.UpdateTimestampFontDisplay;
begin
  EdtTimestampFont.Text := Format('%s, %d pt', [FTimestampFontName, FTimestampFontSize]);
end;

procedure TWcxSettingsForm.UpdateBannerFontDisplay;
begin
  if ChkBannerAutoSize.Checked then
    EdtBannerFont.Text := Format('%s, auto', [FBannerFontName])
  else
    EdtBannerFont.Text := Format('%s, %d pt', [FBannerFontName, FBannerFontSize]);
end;

procedure TWcxSettingsForm.PickTimestampFont;
begin
  FontDlg.Font.Name := FTimestampFontName;
  FontDlg.Font.Size := FTimestampFontSize;
  if FontDlg.Execute then
  begin
    FTimestampFontName := FontDlg.Font.Name;
    FTimestampFontSize := EnsureRange(FontDlg.Font.Size, MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
    UpdateTimestampFontDisplay;
  end;
end;

procedure TWcxSettingsForm.PickBannerFont;
begin
  FontDlg.Font.Name := FBannerFontName;
  {Auto mode has no stored size, so seed the dialog with the default.}
  if ChkBannerAutoSize.Checked then
    FontDlg.Font.Size := DEF_BANNER_FONT_SIZE
  else
    FontDlg.Font.Size := FBannerFontSize;
  if FontDlg.Execute then
  begin
    FBannerFontName := FontDlg.Font.Name;
    FBannerFontSize := EnsureRange(FontDlg.Font.Size, MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE);
    {User picked a specific size; that signals intent to drop auto-sizing.}
    ChkBannerAutoSize.Checked := False;
    UpdateBannerFontDisplay;
  end;
end;

procedure TWcxSettingsForm.BtnTimestampFontClick(Sender: TObject);
begin
  PickTimestampFont;
end;

procedure TWcxSettingsForm.BtnBannerFontClick(Sender: TObject);
begin
  PickBannerFont;
end;

procedure TWcxSettingsForm.ChkBannerAutoSizeClick(Sender: TObject);
begin
  UpdateBannerFontDisplay;
end;

procedure TWcxSettingsForm.PnlBackgroundClick(Sender: TObject);
begin
  PickColor(PnlBackground);
end;

procedure TWcxSettingsForm.PnlTCBackClick(Sender: TObject);
begin
  PickColor(PnlTCBack);
end;

procedure TWcxSettingsForm.PnlTCTextColorClick(Sender: TObject);
begin
  PickColor(PnlTCTextColor);
end;

procedure TWcxSettingsForm.PnlBannerBackgroundClick(Sender: TObject);
begin
  PickColor(PnlBannerBackground);
end;

procedure TWcxSettingsForm.PnlBannerTextColorClick(Sender: TObject);
begin
  PickColor(PnlBannerTextColor);
end;

procedure TWcxSettingsForm.ChkShowBannerClick(Sender: TObject);
begin
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.BtnApplyClick(Sender: TObject);
begin
  {Persist immediately so the archive-browsing path, which re-reads the INI,
   picks up the changes without the user having to close the dialog first.}
  if FSettings = nil then
    Exit;
  ControlsToSettings(FSettings);
  FSettings.Save;
  if Assigned(FOnApply) then
    FOnApply();
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
        MessageBox(Handle, PChar('The selected file is not a valid ffmpeg executable.'), 'Glimpse', MB_OK or MB_ICONWARNING);
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

constructor TWcxSettingsForm.CreateWithOwner(AOwnerWnd: HWND);
begin
  FOwnerWnd := AOwnerWnd;
  inherited Create(nil);
end;

procedure TWcxSettingsForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if FOwnerWnd <> 0 then
    Params.WndParent := FOwnerWnd;
end;

{Public API}

function ShowWcxSettingsDialog(AParentWnd: HWND; ASettings: TWcxSettings; AOnApply: TProc): Boolean;
var
  Dlg: TWcxSettingsForm;
begin
  Result := False;
  Dlg := TWcxSettingsForm.CreateWithOwner(AParentWnd);
  try
    Dlg.FSettings := ASettings;
    Dlg.FOnApply := AOnApply;
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
