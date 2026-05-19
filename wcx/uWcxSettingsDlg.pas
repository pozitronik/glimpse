{Configuration dialog for the WCX plugin, shown via ConfigurePacker.}
unit uWcxSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls, Vcl.ComCtrls,
  Vcl.Dialogs,
  Winapi.Windows,
  uWcxSettings, uWcxPresetEditorModel,
  uWcxSettingsRepository, uWcxPresetsRepository,
  uWcxSettingsControlsBundles, uWcxSettingsPresenters;

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
    EdtFFmpegInfo: TEdit;
    TshSampling: TTabSheet;
    LblRandomPercent: TLabel;
    LblRandomPercentValue: TLabel;
    ChkRandomExtraction: TCheckBox;
    TrkRandomPercent: TTrackBar;
    TshOutput: TTabSheet;
    LblOutputMode: TLabel;
    ChkModeFrames: TCheckBox;
    ChkModeCombined: TCheckBox;
    ChkModePresets: TCheckBox;
    LblFormat: TLabel;
    CbxFormat: TComboBox;
    LblJpegQuality: TLabel;
    EdtJpegQuality: TEdit;
    UdJpegQuality: TUpDown;
    LblPngCompression: TLabel;
    EdtPngCompression: TEdit;
    UdPngCompression: TUpDown;
    LblBackgroundAlpha: TLabel;
    EdtBackgroundAlpha: TEdit;
    UdBackgroundAlpha: TUpDown;
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
    TshPresets: TTabSheet;
    LbxPresets: TListBox;
    BtnPresetAdd: TButton;
    BtnPresetRemove: TButton;
    BtnPresetDuplicate: TButton;
    LblPresetName: TLabel;
    EdtPresetName: TEdit;
    ChkPresetEnabled: TCheckBox;
    LblPresetDescription: TLabel;
    EdtPresetDescription: TEdit;
    LblPresetOutputExt: TLabel;
    EdtPresetOutputExt: TEdit;
    LblPresetOutputName: TLabel;
    EdtPresetOutputName: TEdit;
    LblPresetArgs: TLabel;
    MemoPresetArgs: TMemo;
    procedure ChkModeFramesClick(Sender: TObject);
    procedure ChkModeCombinedClick(Sender: TObject);
    procedure ChkModePresetsClick(Sender: TObject);
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
    procedure ChkRandomExtractionClick(Sender: TObject);
    procedure BtnTimestampFontClick(Sender: TObject);
    procedure BtnBannerFontClick(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
    procedure TrkRandomPercentChange(Sender: TObject);
    procedure BtnOKClick(Sender: TObject);
    procedure LbxPresetsClick(Sender: TObject);
    procedure BtnPresetAddClick(Sender: TObject);
    procedure BtnPresetRemoveClick(Sender: TObject);
    procedure BtnPresetDuplicateClick(Sender: TObject);
  strict private
    {Construct via CreateForSettings; strict-private blocks the previous
     external-reach pattern. Repositories own persistence — the dialog
     never calls TWcxSettings.Save or SavePresets directly.}
    FSettings: TWcxSettings;
    FOnApply: TProc;
    FSettingsRepo: IWcxSettingsRepository;
    FPresetsRepo: IWcxPresetsRepository;
  private
    FOwnerWnd: HWND;
    FPresetModel: TPresetEditorModel;
    FExtractionControls: TWcxExtractionControls;
    FRandomControls: TWcxRandomControls;
    FFFmpegControls: TWcxFFmpegControls;
    FModeControls: TWcxModeControls;
    FOutputControls: TWcxOutputControls;
    FCombinedControls: TWcxCombinedControls;
    FTimestampControls: TWcxTimestampControls;
    FBannerControls: TWcxBannerControls;
    FLimitsControls: TWcxLimitsControls;
    FExtractionPresenter: TWcxExtractionPresenter;
    FOutputPresenter: TWcxOutputPresenter;
    FPresetEditorPresenter: TWcxPresetEditorPresenter;
    procedure InitControlsBundles;
    procedure SettingsToControls(ASettings: TWcxSettings);
    procedure ControlsToSettings(ASettings: TWcxSettings);
    {False on validation failure (offending preset already selected and
     a message box shown).}
    function TrySaveAll: Boolean;
    procedure UpdateCombinedState;
    procedure UpdateRandomState;
    procedure UpdateMaxWorkersControls;
    procedure PickColor(APanel: TPanel);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    {Caller still owns ASettings; the form mutates it in place on Apply
     and OK. Pass nil for APresetsRepo to disable preset persistence.}
    constructor CreateForSettings(AOwnerWnd: HWND; ASettings: TWcxSettings;
      AOnApply: TProc;
      const ASettingsRepo: IWcxSettingsRepository;
      const APresetsRepo: IWcxPresetsRepository);
    destructor Destroy; override;
  end;

  {AOnApply fires after every Apply press; ASettings is already persisted
   by the time the callback runs.}
function ShowWcxSettingsDialog(AParentWnd: HWND; ASettings: TWcxSettings;
  const ASettingsRepo: IWcxSettingsRepository;
  const APresetsRepo: IWcxPresetsRepository;
  AOnApply: TProc = nil): Boolean;

implementation

{$R *.dfm}

uses
  System.Math,
  uBitmapSaver, uPathExpand, uFFmpegExe, uFFmpegCmdLine, uFFmpegLocator, uSettingsDlgLogic,
  uSettingsDlgUI, uPluginMessages, uDefaults, uTypes,
  uWcxPresets, uSettingsSaveOrchestrator;

procedure TWcxSettingsForm.InitControlsBundles;
begin
  FExtractionControls.UdFrameCount := UdFrameCount;
  FExtractionControls.UdSkipEdges := UdSkipEdges;
  FExtractionControls.ChkMaxWorkersAuto := ChkMaxWorkersAuto;
  FExtractionControls.UdMaxWorkers := UdMaxWorkers;
  FExtractionControls.UdMaxThreads := UdMaxThreads;
  FExtractionControls.ChkUseBmpPipe := ChkUseBmpPipe;
  FExtractionControls.ChkHwAccel := ChkHwAccel;
  FExtractionControls.ChkUseKeyframes := ChkUseKeyframes;
  FExtractionControls.ChkRespectAnamorphic := ChkRespectAnamorphic;

  FRandomControls.ChkRandomExtraction := ChkRandomExtraction;
  FRandomControls.TrkRandomPercent := TrkRandomPercent;

  FFFmpegControls.EdtFFmpegPath := EdtFFmpegPath;

  FModeControls.ChkModeFrames := ChkModeFrames;
  FModeControls.ChkModeCombined := ChkModeCombined;
  FModeControls.ChkModePresets := ChkModePresets;

  FOutputControls.CbxFormat := CbxFormat;
  FOutputControls.UdJpegQuality := UdJpegQuality;
  FOutputControls.UdPngCompression := UdPngCompression;
  FOutputControls.UdBackgroundAlpha := UdBackgroundAlpha;
  FOutputControls.ChkShowFileSizes := ChkShowFileSizes;

  FCombinedControls.UdColumns := UdColumns;
  FCombinedControls.UdCellGap := UdCellGap;
  FCombinedControls.UdBorder := UdBorder;
  FCombinedControls.PnlBackground := PnlBackground;

  FTimestampControls.ChkTimestamp := ChkTimestamp;
  FTimestampControls.CbxTimestampCorner := CbxTimestampCorner;
  FTimestampControls.PnlTCBack := PnlTCBack;
  FTimestampControls.UdTCAlpha := UdTCAlpha;
  FTimestampControls.PnlTCTextColor := PnlTCTextColor;
  FTimestampControls.UdTCTextAlpha := UdTCTextAlpha;

  FBannerControls.ChkShowBanner := ChkShowBanner;
  FBannerControls.PnlBannerBackground := PnlBannerBackground;
  FBannerControls.PnlBannerTextColor := PnlBannerTextColor;
  FBannerControls.ChkBannerAutoSize := ChkBannerAutoSize;
  FBannerControls.CbxBannerPosition := CbxBannerPosition;

  FLimitsControls.UdFrameMax := UdFrameMax;
  FLimitsControls.UdCombinedMax := UdCombinedMax;
end;

procedure TWcxSettingsForm.SettingsToControls(ASettings: TWcxSettings);
begin
  FExtractionPresenter.LoadFrom(ASettings);
  FOutputPresenter.LoadFrom(ASettings);

  UpdateMaxWorkersControls;
  UpdateCombinedState;
  UpdateRandomState;
end;

procedure TWcxSettingsForm.ControlsToSettings(ASettings: TWcxSettings);
begin
  FExtractionPresenter.SaveTo(ASettings);
  FOutputPresenter.SaveTo(ASettings);
end;

procedure TWcxSettingsForm.UpdateCombinedState;
var
  IsCombined, BannerOn: Boolean;
begin
  IsCombined := ChkModeCombined.Checked;
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

procedure TWcxSettingsForm.ChkModeFramesClick(Sender: TObject);
begin
  {No-op; kept for symmetry with the Combined / Presets handlers.}
end;

procedure TWcxSettingsForm.ChkModeCombinedClick(Sender: TObject);
begin
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.ChkModePresetsClick(Sender: TObject);
begin
  {No-op; the Presets tab manages its own enable state.}
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
  FExtractionPresenter.OnFFmpegPathChange;
end;

procedure TWcxSettingsForm.PickColor(APanel: TPanel);
begin
  PickColorForPanel(APanel, ColorDlg);
end;

procedure TWcxSettingsForm.BtnTimestampFontClick(Sender: TObject);
begin
  FOutputPresenter.OnTimestampFontClick;
end;

procedure TWcxSettingsForm.BtnBannerFontClick(Sender: TObject);
begin
  FOutputPresenter.OnBannerFontClick;
end;

procedure TWcxSettingsForm.ChkBannerAutoSizeClick(Sender: TObject);
begin
  FOutputPresenter.UpdateBannerFontDisplay;
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

procedure TWcxSettingsForm.ChkRandomExtractionClick(Sender: TObject);
begin
  UpdateRandomState;
end;

procedure TWcxSettingsForm.UpdateRandomState;
var
  Enabled: Boolean;
begin
  Enabled := ChkRandomExtraction.Checked;
  LblRandomPercent.Enabled := Enabled;
  LblRandomPercentValue.Enabled := Enabled;
  TrkRandomPercent.Enabled := Enabled;
end;

function TWcxSettingsForm.TrySaveAll: Boolean;
var
  Orchestrator: TSettingsSaveOrchestrator;
  Outcome: TSettingsSaveResult;
begin
  {Flush in-progress right-pane edits to the model so validation and
   save see the user's latest input.}
  FPresetEditorPresenter.CommitCurrentPreset;

  Orchestrator := TSettingsSaveOrchestrator.Create;
  try
    Outcome := Orchestrator.Run(FSettings, FPresetModel,
      FSettingsRepo, FPresetsRepo,
      procedure begin ControlsToSettings(FSettings) end,
      FOnApply);
  finally
    Orchestrator.Free;
  end;

  case Outcome.Kind of
    ssrValidationFailed:
      begin
        PageControl.ActivePage := TshPresets;
        FPresetEditorPresenter.NavigateToValidationFailure(Outcome.ValidationIndex);
        MessageBox(Handle, PChar(Outcome.ValidationReason), 'Invalid preset', MB_OK or MB_ICONWARNING);
        Exit(False);
      end;
    ssrSuccess:
      begin
        {Re-validate the FFmpeg path so the info label reflects any
         change the user just made.}
        FExtractionPresenter.UpdateFFmpegInfo;
        Exit(True);
      end;
  else
    {ssrSkipped: FSettings was nil; nothing to do.}
    Exit(False);
  end;
end;

procedure TWcxSettingsForm.BtnApplyClick(Sender: TObject);
begin
  TrySaveAll;
end;

procedure TWcxSettingsForm.BtnOKClick(Sender: TObject);
begin
  {Validation failure keeps the dialog open so the user can fix the
   offending preset.}
  if TrySaveAll then
    ModalResult := mrOk;
end;

procedure TWcxSettingsForm.LbxPresetsClick(Sender: TObject);
begin
  FPresetEditorPresenter.OnLbxPresetsClick;
end;

procedure TWcxSettingsForm.BtnPresetAddClick(Sender: TObject);
begin
  FPresetEditorPresenter.OnBtnPresetAddClick;
end;

procedure TWcxSettingsForm.BtnPresetRemoveClick(Sender: TObject);
begin
  FPresetEditorPresenter.OnBtnPresetRemoveClick;
end;

procedure TWcxSettingsForm.BtnPresetDuplicateClick(Sender: TObject);
begin
  FPresetEditorPresenter.OnBtnPresetDuplicateClick;
end;

procedure TWcxSettingsForm.BtnFFmpegPathClick(Sender: TObject);
begin
  FExtractionPresenter.OnFFmpegPathClick;
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

procedure TWcxSettingsForm.TrkRandomPercentChange(Sender: TObject);
begin
  FExtractionPresenter.OnRandomPercentChange;
end;

constructor TWcxSettingsForm.CreateForSettings(AOwnerWnd: HWND;
  ASettings: TWcxSettings; AOnApply: TProc;
  const ASettingsRepo: IWcxSettingsRepository;
  const APresetsRepo: IWcxPresetsRepository);
begin
  FOwnerWnd := AOwnerWnd;
  inherited Create(nil);
  FPresetModel := TPresetEditorModel.Create;
  FSettings := ASettings;
  FOnApply := AOnApply;
  FSettingsRepo := ASettingsRepo;
  FPresetsRepo := APresetsRepo;
  {Order: bundles populated first so presenters can copy refs out;
   both run after the DFM has instantiated every control referenced.}
  InitControlsBundles;
  FExtractionPresenter := TWcxExtractionPresenter.Create(
    FExtractionControls, FRandomControls, FFFmpegControls,
    LblFFmpegInfo, EdtFFmpegInfo, LblRandomPercentValue,
    ExtractFilePath(Application.ExeName), FOwnerWnd);
  FOutputPresenter := TWcxOutputPresenter.Create(
    FModeControls, FOutputControls, FCombinedControls,
    FTimestampControls, FBannerControls, FLimitsControls,
    EdtTimestampFont, EdtBannerFont, FontDlg);
  FPresetEditorPresenter := TWcxPresetEditorPresenter.Create(
    FPresetModel, FPresetsRepo, LbxPresets,
    EdtPresetName, ChkPresetEnabled, EdtPresetDescription,
    EdtPresetOutputExt, EdtPresetOutputName, MemoPresetArgs);
  {Keep tooltips visible as long as the cursor stays. Application is
   per-DLL, so this only affects our forms; TC uses its own non-VCL
   tooltip mechanism.}
  Application.HintHidePause := MaxInt;
  if FSettings <> nil then
  begin
    SettingsToControls(FSettings);
    FPresetEditorPresenter.LoadPresetsFromDisk;
  end;
end;

destructor TWcxSettingsForm.Destroy;
begin
  FPresetEditorPresenter.Free;
  FOutputPresenter.Free;
  FExtractionPresenter.Free;
  FPresetModel.Free;
  inherited;
end;

procedure TWcxSettingsForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if FOwnerWnd <> 0 then
    Params.WndParent := FOwnerWnd;
end;

function ShowWcxSettingsDialog(AParentWnd: HWND; ASettings: TWcxSettings;
  const ASettingsRepo: IWcxSettingsRepository;
  const APresetsRepo: IWcxPresetsRepository;
  AOnApply: TProc): Boolean;
var
  Dlg: TWcxSettingsForm;
begin
  Result := False;
  Dlg := TWcxSettingsForm.CreateForSettings(AParentWnd, ASettings, AOnApply,
    ASettingsRepo, APresetsRepo);
  try
    if Dlg.ShowModal = mrOk then
    begin
      {Persisted already by BtnOKClick; refresh ASettings so post-dialog
       inspection sees what was committed.}
      Dlg.ControlsToSettings(ASettings);
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
