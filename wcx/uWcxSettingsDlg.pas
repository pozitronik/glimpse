{Configuration dialog for the WCX plugin.
 Shown via ConfigurePacker when the user clicks Configure in TC.}
unit uWcxSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls, Vcl.ComCtrls,
  Vcl.Dialogs,
  Winapi.Windows,
  uWcxSettings, uWcxPresetEditorModel;

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
    {Sampling tab — frame-positioning controls: frame count, skip edges,
     and the random-extraction slider. No "Cache random frames" toggle
     here: WCX runs on demand from TC and has no frame cache, so the
     option would be a no-op.}
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
    {Presets tab — master-detail editor over TPresetEditorModel}
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
  private
    FOwnerWnd: HWND;
    FSettings: TWcxSettings;
    FOnApply: TProc;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBannerFontName: string;
    FBannerFontSize: Integer;
    FPresetModel: TPresetEditorModel;
    FPresetsPath: string;
    {Tracks which row the edit fields currently mirror so a list-selection
     change can flush the in-progress edits back to the model before
     loading the newly-selected row.}
    FCurrentPresetIndex: Integer;
    procedure SettingsToControls(ASettings: TWcxSettings);
    procedure ControlsToSettings(ASettings: TWcxSettings);
    {Pulls every preset from disk into FPresetModel and refreshes the
     listbox. Called once at dialog open and after Apply (so the next
     edit cycle starts from the persisted state).}
    procedure LoadPresetsFromDisk;
    {Refreshes the listbox to mirror FPresetModel and selects ASelectIndex
     (clamping to a valid row when out of range).}
    procedure RefreshPresetList(ASelectIndex: Integer);
    {Loads the preset at AIndex into the edit fields. Pass -1 to clear
     the panel and disable editing (no rows in the model).}
    procedure ShowPreset(AIndex: Integer);
    {Saves the edit fields back into FPresetModel at FCurrentPresetIndex.
     No-op when no row is currently displayed.}
    procedure CommitCurrentPreset;
    procedure SetEditFieldsEnabled(AEnabled: Boolean);
    {Validates the model and writes both Glimpse.ini and presets.ini.
     Returns False on validation failure (with a message box already
     shown and the offending preset selected/focused). Used by both
     Apply and OK so the persistence rules stay in one place.}
    function TrySaveAll: Boolean;
    procedure UpdateCombinedState;
    {Greys out the randomness slider and its labels when the random
     extraction checkbox is unchecked, so the user is not given a control
     that would have no effect until the checkbox is ticked.}
    procedure UpdateRandomState;
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
    destructor Destroy; override;
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
  uSettingsDlgUI, uDefaults, uTypes,
  uWcxPresets;

procedure TWcxSettingsForm.SettingsToControls(ASettings: TWcxSettings);
var
  AutoChecked, ShowChecked: Boolean;
  UdPos, ComboIdx: Integer;
begin
  UdFrameCount.Position := ASettings.FramesCount;
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;

  ChkRandomExtraction.Checked := ASettings.RandomExtraction;
  TrkRandomPercent.Position := ASettings.RandomPercent;
  LblRandomPercentValue.Caption := IntToStr(ASettings.RandomPercent) + '%';

  DecodeMaxWorkersControls(ASettings.MaxWorkers, AutoChecked, UdPos);
  ChkMaxWorkersAuto.Checked := AutoChecked;
  UdMaxWorkers.Position := UdPos;
  UdMaxThreads.Position := DecodeMaxThreadsControl(ASettings.MaxThreads);
  ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  ChkHwAccel.Checked := ASettings.HwAccel;
  ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  ChkRespectAnamorphic.Checked := ASettings.RespectAnamorphic;
  EdtFFmpegPath.Text := ASettings.FFmpegExePath;

  ChkModeFrames.Checked := ASettings.ShowFrames;
  ChkModeCombined.Checked := ASettings.ShowCombined;
  ChkModePresets.Checked := ASettings.ShowPresets;

  CbxFormat.ItemIndex := Ord(ASettings.SaveFormat);
  UdJpegQuality.Position := ASettings.JpegQuality;
  UdPngCompression.Position := ASettings.PngCompression;
  UdBackgroundAlpha.Position := ASettings.BackgroundAlpha;
  ChkShowFileSizes.Checked := ASettings.ShowFileSizes;

  UdColumns.Position := ASettings.CombinedColumns;
  UdCellGap.Position := ASettings.CellGap;
  UdBorder.Position := ASettings.CombinedBorder;
  PnlBackground.Color := ASettings.Background;
  DecodeTimestampCornerControls(ASettings.ShowTimestamp, ASettings.TimestampCorner, ShowChecked, ComboIdx);
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
  UpdateRandomState;
  UpdateFFmpegInfo;
end;

procedure TWcxSettingsForm.ControlsToSettings(ASettings: TWcxSettings);
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  ASettings.FramesCount := UdFrameCount.Position;
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;
  ASettings.RandomExtraction := ChkRandomExtraction.Checked;
  ASettings.RandomPercent := TrkRandomPercent.Position;

  ASettings.MaxWorkers := EncodeMaxWorkersControls(ChkMaxWorkersAuto.Checked, UdMaxWorkers.Position);
  ASettings.MaxThreads := UdMaxThreads.Position;
  ASettings.UseBmpPipe := ChkUseBmpPipe.Checked;
  ASettings.HwAccel := ChkHwAccel.Checked;
  ASettings.UseKeyframes := ChkUseKeyframes.Checked;
  ASettings.RespectAnamorphic := ChkRespectAnamorphic.Checked;
  ASettings.FFmpegExePath := EdtFFmpegPath.Text;

  ASettings.ShowFrames := ChkModeFrames.Checked;
  ASettings.ShowCombined := ChkModeCombined.Checked;
  ASettings.ShowPresets := ChkModePresets.Checked;

  ASettings.SaveFormat := TSaveFormat(CbxFormat.ItemIndex);
  ASettings.JpegQuality := UdJpegQuality.Position;
  ASettings.PngCompression := UdPngCompression.Position;
  {Explicit Byte cast: TUpDown.Position is Integer, target is Byte; the
   control's Min/Max are clamped to [0, 255] so the narrowing is safe.}
  ASettings.BackgroundAlpha := Byte(UdBackgroundAlpha.Position);
  ASettings.ShowFileSizes := ChkShowFileSizes.Checked;

  ASettings.CombinedColumns := UdColumns.Position;
  ASettings.CellGap := UdCellGap.Position;
  ASettings.CombinedBorder := UdBorder.Position;
  ASettings.Background := PnlBackground.Color;
  EncodeTimestampCornerControls(ChkTimestamp.Checked, CbxTimestampCorner.ItemIndex, Show, Corner);
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

procedure TWcxSettingsForm.UpdateFFmpegInfo;
var
  Input, Path, Ver, Prefix, Value: string;
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

  FFmpegInfoLabelParts(State, Path, Ver, Input = '', Prefix, Value);
  ApplyInfoParts(LblFFmpegInfo, EdtFFmpegInfo, Prefix, Value);
end;

procedure TWcxSettingsForm.ChkModeFramesClick(Sender: TObject);
begin
  {Frames have no dependent fields on this tab; the click is a no-op
   for the dependent-state pass but matches the Combined / Presets
   handlers for symmetry.}
end;

procedure TWcxSettingsForm.ChkModeCombinedClick(Sender: TObject);
begin
  {The Combined tab's controls grey out when this is off — keep the
   dependent state in sync as the user toggles.}
  UpdateCombinedState;
end;

procedure TWcxSettingsForm.ChkModePresetsClick(Sender: TObject);
begin
  {No dependent state on this tab today; the Presets tab manages its
   own enable state.}
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
  PickColorForPanel(APanel, ColorDlg);
end;

procedure TWcxSettingsForm.UpdateTimestampFontDisplay;
begin
  RefreshTimestampFontEdit(EdtTimestampFont, FTimestampFontName, FTimestampFontSize);
end;

procedure TWcxSettingsForm.UpdateBannerFontDisplay;
begin
  RefreshBannerFontEdit(EdtBannerFont, ChkBannerAutoSize.Checked, FBannerFontName, FBannerFontSize);
end;

procedure TWcxSettingsForm.PickTimestampFont;
begin
  PickTimestampFontInto(FontDlg, EdtTimestampFont, FTimestampFontName, FTimestampFontSize, MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
end;

procedure TWcxSettingsForm.PickBannerFont;
begin
  PickBannerFontInto(FontDlg, EdtBannerFont, ChkBannerAutoSize, FBannerFontName, FBannerFontSize, MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE, DEF_BANNER_FONT_SIZE);
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
  BadIdx: Integer;
  Reason: string;
begin
  Result := False;
  if FSettings = nil then
    Exit;
  {Flush any in-progress edits in the right-hand panel back to the model
   so validation and save see the user's latest input, not the snapshot
   from the last list-selection change.}
  CommitCurrentPreset;
  if not FPresetModel.Validate(BadIdx, Reason) then
  begin
    PageControl.ActivePage := TshPresets;
    if (BadIdx >= 0) and (BadIdx < LbxPresets.Items.Count) then
    begin
      LbxPresets.ItemIndex := BadIdx;
      ShowPreset(BadIdx);
    end;
    MessageBox(Handle, PChar(Reason), 'Invalid preset', MB_OK or MB_ICONWARNING);
    Exit;
  end;

  ControlsToSettings(FSettings);
  FSettings.Save;
  if FPresetsPath <> '' then
    SavePresets(FPresetsPath, FPresetModel.ToArray);
  {Re-validate the FFmpeg path in case the user changed it; without this
   the info label keeps showing the validation result from dialog open.}
  UpdateFFmpegInfo;
  if Assigned(FOnApply) then
    FOnApply();
  Result := True;
end;

procedure TWcxSettingsForm.BtnApplyClick(Sender: TObject);
begin
  TrySaveAll;
end;

procedure TWcxSettingsForm.BtnOKClick(Sender: TObject);
begin
  {OK is "save and close". Validation failure keeps the dialog open so
   the user can fix the offending preset; success sets ModalResult so
   ShowModal returns mrOk and the caller knows the dialog committed.}
  if TrySaveAll then
    ModalResult := mrOk;
end;

procedure TWcxSettingsForm.LoadPresetsFromDisk;
begin
  FPresetModel.LoadFrom(LoadAllPresets(FPresetsPath));
  RefreshPresetList(0);
end;

procedure TWcxSettingsForm.RefreshPresetList(ASelectIndex: Integer);
var
  I, NewSel: Integer;
  Caption: string;
begin
  LbxPresets.Items.BeginUpdate;
  try
    LbxPresets.Items.Clear;
    for I := 0 to FPresetModel.Count - 1 do
    begin
      Caption := FPresetModel.Get(I).Name;
      if not FPresetModel.Get(I).Enabled then
        Caption := Caption + ' (off)';
      LbxPresets.Items.Add(Caption);
    end;
  finally
    LbxPresets.Items.EndUpdate;
  end;

  if FPresetModel.Count = 0 then
  begin
    LbxPresets.ItemIndex := -1;
    ShowPreset(-1);
    Exit;
  end;

  NewSel := ASelectIndex;
  if NewSel < 0 then
    NewSel := 0;
  if NewSel >= FPresetModel.Count then
    NewSel := FPresetModel.Count - 1;
  LbxPresets.ItemIndex := NewSel;
  ShowPreset(NewSel);
end;

procedure TWcxSettingsForm.SetEditFieldsEnabled(AEnabled: Boolean);
begin
  EdtPresetName.Enabled := AEnabled;
  ChkPresetEnabled.Enabled := AEnabled;
  EdtPresetDescription.Enabled := AEnabled;
  EdtPresetOutputExt.Enabled := AEnabled;
  EdtPresetOutputName.Enabled := AEnabled;
  MemoPresetArgs.Enabled := AEnabled;
end;

procedure TWcxSettingsForm.ShowPreset(AIndex: Integer);
var
  P: TWcxPreset;
begin
  FCurrentPresetIndex := AIndex;
  if (AIndex < 0) or (AIndex >= FPresetModel.Count) then
  begin
    EdtPresetName.Text := '';
    ChkPresetEnabled.Checked := False;
    EdtPresetDescription.Text := '';
    EdtPresetOutputExt.Text := '';
    EdtPresetOutputName.Text := '';
    MemoPresetArgs.Text := '';
    SetEditFieldsEnabled(False);
    Exit;
  end;

  P := FPresetModel.Get(AIndex);
  EdtPresetName.Text := P.Name;
  ChkPresetEnabled.Checked := P.Enabled;
  EdtPresetDescription.Text := P.Description;
  EdtPresetOutputExt.Text := P.OutputExt;
  EdtPresetOutputName.Text := P.OutputName;
  MemoPresetArgs.Text := P.Args;
  SetEditFieldsEnabled(True);
end;

procedure TWcxSettingsForm.CommitCurrentPreset;
var
  P: TWcxPreset;
  ListCaption: string;
begin
  if (FCurrentPresetIndex < 0) or (FCurrentPresetIndex >= FPresetModel.Count) then
    Exit;
  P := FPresetModel.Get(FCurrentPresetIndex);
  P.Name := Trim(EdtPresetName.Text);
  P.Enabled := ChkPresetEnabled.Checked;
  P.Description := Trim(EdtPresetDescription.Text);
  P.OutputExt := Trim(EdtPresetOutputExt.Text);
  P.OutputName := Trim(EdtPresetOutputName.Text);
  P.Args := MemoPresetArgs.Text;
  FPresetModel.Update(FCurrentPresetIndex, P);

  {Reflect rename or enabled-toggle in the listbox label without rebuilding
   the whole list, which would lose the user's selection.}
  ListCaption := P.Name;
  if not P.Enabled then
    ListCaption := ListCaption + ' (off)';
  if FCurrentPresetIndex < LbxPresets.Items.Count then
    LbxPresets.Items[FCurrentPresetIndex] := ListCaption;
end;

procedure TWcxSettingsForm.LbxPresetsClick(Sender: TObject);
begin
  if LbxPresets.ItemIndex = FCurrentPresetIndex then
    Exit;
  CommitCurrentPreset;
  ShowPreset(LbxPresets.ItemIndex);
end;

procedure TWcxSettingsForm.BtnPresetAddClick(Sender: TObject);
var
  NewIdx: Integer;
begin
  CommitCurrentPreset;
  NewIdx := FPresetModel.Add;
  RefreshPresetList(NewIdx);
  EdtPresetName.SetFocus;
  EdtPresetName.SelectAll;
end;

procedure TWcxSettingsForm.BtnPresetRemoveClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := LbxPresets.ItemIndex;
  if Idx < 0 then
    Exit;
  {Skip the commit on remove — the in-flight edits are about to be
   discarded. Drop the model row directly.}
  FCurrentPresetIndex := -1;
  FPresetModel.Remove(Idx);
  RefreshPresetList(Idx);
end;

procedure TWcxSettingsForm.BtnPresetDuplicateClick(Sender: TObject);
var
  Idx, NewIdx: Integer;
begin
  Idx := LbxPresets.ItemIndex;
  if Idx < 0 then
    Exit;
  CommitCurrentPreset;
  NewIdx := FPresetModel.Duplicate(Idx);
  if NewIdx >= 0 then
  begin
    RefreshPresetList(NewIdx);
    EdtPresetName.SetFocus;
    EdtPresetName.SelectAll;
  end;
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

procedure TWcxSettingsForm.TrkRandomPercentChange(Sender: TObject);
begin
  {Live readout — the percent value is also captured into TWcxSettings
   on Apply/OK via ControlsToSettings.}
  LblRandomPercentValue.Caption := IntToStr(TrkRandomPercent.Position) + '%';
end;

constructor TWcxSettingsForm.CreateWithOwner(AOwnerWnd: HWND);
begin
  FOwnerWnd := AOwnerWnd;
  inherited Create(nil);
  FPresetModel := TPresetEditorModel.Create;
  FCurrentPresetIndex := -1;
end;

destructor TWcxSettingsForm.Destroy;
begin
  FPresetModel.Free;
  inherited;
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
    Dlg.FPresetsPath := PresetsIniPath(ASettings.IniPath);
    Dlg.SettingsToControls(ASettings);
    Dlg.LoadPresetsFromDisk;
    if Dlg.ShowModal = mrOk then
    begin
      {Settings + presets are already persisted by BtnOKClick → TrySaveAll;
       just refresh the caller's settings reference so any post-dialog
       inspection sees what the dialog committed.}
      Dlg.ControlsToSettings(ASettings);
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
