{Cluster presenters for the WCX settings dialog.

 Step 99 (C8, part 2): mirrors the WLX-side wlx/uSettingsPresenters
 (step 84). Three presenters by domain:

   - TWcxExtractionPresenter     General + Sampling tabs (extraction,
                                  ffmpeg path, random sampling)
   - TWcxOutputPresenter         Output + Combined + Limits tabs
                                  (mode toggles, format/quality,
                                  combined-grid layout + timestamp +
                                  banner sub-clusters, max-side caps)
   - TWcxPresetEditorPresenter   Presets tab (preset list/edit
                                  fields, LoadPresetsFromDisk, the
                                  Add/Remove/Duplicate/Show flow,
                                  validation-failure navigation)

 Each non-preset presenter owns: its bundle(s) (referenced, not owned),
 the update helpers that DON'T toggle enable-state of non-bundle
 controls (UpdateFFmpegInfo, UpdateRandomPercentLabel,
 UpdateTimestampFontDisplay, UpdateBannerFontDisplay), its event
 handlers, and (for Output) its share of the dialog-local font shadow
 fields.

 The form keeps:

   - Update*State enable methods (UpdateCombinedState, UpdateRandomState,
     UpdateMaxWorkersControls): these toggle ~30 labels/buttons that
     aren't in any bundle; lifting them into presenters would require
     extra plumbing for unclear win. The WCX dialog has no declarative
     TEnableRules table (unlike WLX after step 82); converting WCX's
     imperative Update*State into a table is a separate finding (the
     "WCX step 82" follow-up) outside this step's scope.
   - TrySaveAll (already delegates to TSettingsSaveOrchestrator per
     step 102). The validation-failure navigation block calls into
     TWcxPresetEditorPresenter.NavigateToValidationFailure.
   - BtnDefaults / BtnApply / BtnOK / BtnCancel (form-level orchestration).
   - One-line handlers that only call Update*State (rule adjacency).

 DFM event wiring: form's published handlers stay (DFM points at them
 by name); each becomes a one-line forwarder to the matching presenter
 method, optionally followed by an Update*State call.}
unit uWcxSettingsPresenters;

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Forms, Vcl.Controls, Vcl.Dialogs,
  uWcxSettings, uWcxPresets, uWcxPresetEditorModel,
  uWcxPresetsRepository,
  uWcxSettingsControlsBundles;

type
  {General + Sampling tab logic. Owns the extraction + ffmpeg + random
   bundles, the ffmpeg-info + random-percent live readout helpers, and
   the BtnFFmpegPathClick browse dialog. The MaxWorkers/MaxThreads
   enable toggles stay on the form (UpdateMaxWorkersControls).}
  TWcxExtractionPresenter = class
  strict private
    FExtractionControls: TWcxExtractionControls;
    FRandomControls: TWcxRandomControls;
    FFFmpegControls: TWcxFFmpegControls;
    FLblFFmpegInfo: TLabel;
    FEdtFFmpegInfo: TEdit;
    FLblRandomPercentValue: TLabel;
    FApplicationDir: string;
    FParentWnd: HWND;
  public
    constructor Create(const AExtractionControls: TWcxExtractionControls;
      const ARandomControls: TWcxRandomControls;
      const AFFmpegControls: TWcxFFmpegControls;
      ALblFFmpegInfo: TLabel; AEdtFFmpegInfo: TEdit;
      ALblRandomPercentValue: TLabel;
      const AApplicationDir: string; AParentWnd: HWND);
    procedure LoadFrom(ASettings: TWcxSettings);
    procedure SaveTo(ASettings: TWcxSettings);
    procedure UpdateFFmpegInfo;
    procedure UpdateRandomPercentLabel;
    procedure OnFFmpegPathClick;
    procedure OnFFmpegPathChange;
    procedure OnRandomPercentChange;
  end;

  {Output + Combined + Limits tab logic. Owns 6 bundles (mode + output
   + combined + timestamp + banner + limits), the font shadow fields,
   the font-display + font-picker helpers. The combined-tab enable
   toggles (UpdateCombinedState) stay on the form.}
  TWcxOutputPresenter = class
  strict private
    FModeControls: TWcxModeControls;
    FOutputControls: TWcxOutputControls;
    FCombinedControls: TWcxCombinedControls;
    FTimestampControls: TWcxTimestampControls;
    FBannerControls: TWcxBannerControls;
    FLimitsControls: TWcxLimitsControls;
    FEdtTimestampFont: TEdit;
    FEdtBannerFont: TEdit;
    FFontDlg: TFontDialog;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBannerFontName: string;
    FBannerFontSize: Integer;
  public
    constructor Create(const AModeControls: TWcxModeControls;
      const AOutputControls: TWcxOutputControls;
      const ACombinedControls: TWcxCombinedControls;
      const ATimestampControls: TWcxTimestampControls;
      const ABannerControls: TWcxBannerControls;
      const ALimitsControls: TWcxLimitsControls;
      AEdtTimestampFont: TEdit; AEdtBannerFont: TEdit;
      AFontDlg: TFontDialog);
    procedure LoadFrom(ASettings: TWcxSettings);
    procedure SaveTo(ASettings: TWcxSettings);
    procedure UpdateTimestampFontDisplay;
    procedure UpdateBannerFontDisplay;
    procedure OnTimestampFontClick;
    procedure OnBannerFontClick;
  end;

  {Presets tab logic. Owns the in-memory editor model, the current-row
   tracker, the listbox + edit controls, the preset persistence
   repository (for LoadAll), and every preset-tab event handler. The
   form's TrySaveAll calls NavigateToValidationFailure when the
   orchestrator reports a bad row.}
  TWcxPresetEditorPresenter = class
  strict private
    FPresetModel: TPresetEditorModel;
    FPresetsRepo: IWcxPresetsRepository;
    FLbxPresets: TListBox;
    FEdtPresetName: TEdit;
    FChkPresetEnabled: TCheckBox;
    FEdtPresetDescription: TEdit;
    FEdtPresetOutputExt: TEdit;
    FEdtPresetOutputName: TEdit;
    FMemoPresetArgs: TMemo;
    FCurrentPresetIndex: Integer;
  public
    constructor Create(APresetModel: TPresetEditorModel;
      const APresetsRepo: IWcxPresetsRepository;
      ALbxPresets: TListBox;
      AEdtPresetName: TEdit; AChkPresetEnabled: TCheckBox;
      AEdtPresetDescription: TEdit; AEdtPresetOutputExt: TEdit;
      AEdtPresetOutputName: TEdit; AMemoPresetArgs: TMemo);
    {Pulls every preset from the repository into the model and refreshes
     the listbox. Called once at dialog open and after every successful
     Apply (so the next edit cycle starts from the persisted state).}
    procedure LoadPresetsFromDisk;
    {Refreshes the listbox to mirror the model and selects ASelectIndex
     (clamping to a valid row when out of range).}
    procedure RefreshPresetList(ASelectIndex: Integer);
    {Loads the preset at AIndex into the edit fields. Pass -1 to clear
     the panel and disable editing (no rows in the model).}
    procedure ShowPreset(AIndex: Integer);
    {Saves the edit fields back into the model at FCurrentPresetIndex.
     No-op when no row is currently displayed.}
    procedure CommitCurrentPreset;
    procedure SetEditFieldsEnabled(AEnabled: Boolean);
    {Form's TrySaveAll calls this on validation failure: selects the
     offending row in the listbox and re-shows it.}
    procedure NavigateToValidationFailure(AIndex: Integer);
    procedure OnLbxPresetsClick;
    procedure OnBtnPresetAddClick;
    procedure OnBtnPresetRemoveClick;
    procedure OnBtnPresetDuplicateClick;
    property CurrentPresetIndex: Integer read FCurrentPresetIndex;
  end;

implementation

uses
  uTypes, uBitmapSaver, uDefaults,
  uFFmpegExe, uFFmpegCmdLine, uFFmpegLocator, uPathExpand, uPluginMessages,
  uSettingsDlgLogic, uSettingsDlgUI;

{TWcxExtractionPresenter}

constructor TWcxExtractionPresenter.Create(const AExtractionControls: TWcxExtractionControls;
  const ARandomControls: TWcxRandomControls;
  const AFFmpegControls: TWcxFFmpegControls;
  ALblFFmpegInfo: TLabel; AEdtFFmpegInfo: TEdit;
  ALblRandomPercentValue: TLabel;
  const AApplicationDir: string; AParentWnd: HWND);
begin
  inherited Create;
  FExtractionControls := AExtractionControls;
  FRandomControls := ARandomControls;
  FFFmpegControls := AFFmpegControls;
  FLblFFmpegInfo := ALblFFmpegInfo;
  FEdtFFmpegInfo := AEdtFFmpegInfo;
  FLblRandomPercentValue := ALblRandomPercentValue;
  FApplicationDir := AApplicationDir;
  FParentWnd := AParentWnd;
end;

procedure TWcxExtractionPresenter.LoadFrom(ASettings: TWcxSettings);
begin
  BindWcxExtractionToControls(ASettings, FExtractionControls);
  BindWcxRandomToControls(ASettings, FRandomControls);
  BindWcxFFmpegToControls(ASettings, FFFmpegControls);
  UpdateRandomPercentLabel;
  UpdateFFmpegInfo;
end;

procedure TWcxExtractionPresenter.SaveTo(ASettings: TWcxSettings);
begin
  BindWcxExtractionFromControls(ASettings, FExtractionControls);
  BindWcxRandomFromControls(ASettings, FRandomControls);
  BindWcxFFmpegFromControls(ASettings, FFFmpegControls);
end;

procedure TWcxExtractionPresenter.UpdateFFmpegInfo;
var
  Input, Path, Ver, Prefix, Value: string;
  State: TFFmpegProbeState;
begin
  Input := FFFmpegControls.EdtFFmpegPath.Text;
  if Input <> '' then
    Path := ExpandEnvVars(Input)
  else
    Path := FindFFmpegExe(FApplicationDir, '');

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
  ApplyInfoParts(FLblFFmpegInfo, FEdtFFmpegInfo, Prefix, Value);
end;

procedure TWcxExtractionPresenter.UpdateRandomPercentLabel;
begin
  FLblRandomPercentValue.Caption := IntToStr(FRandomControls.TrkRandomPercent.Position) + '%';
end;

procedure TWcxExtractionPresenter.OnFFmpegPathClick;
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if FFFmpegControls.EdtFFmpegPath.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(FFFmpegControls.EdtFFmpegPath.Text));
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      if ValidateFFmpeg(Dlg.FileName) = '' then
      begin
        ShowPluginMessage(FParentWnd, 'The selected file is not a valid ffmpeg executable.', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      FFFmpegControls.EdtFFmpegPath.Text := Dlg.FileName;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TWcxExtractionPresenter.OnFFmpegPathChange;
begin
  UpdateFFmpegInfo;
end;

procedure TWcxExtractionPresenter.OnRandomPercentChange;
begin
  UpdateRandomPercentLabel;
end;

{TWcxOutputPresenter}

constructor TWcxOutputPresenter.Create(const AModeControls: TWcxModeControls;
  const AOutputControls: TWcxOutputControls;
  const ACombinedControls: TWcxCombinedControls;
  const ATimestampControls: TWcxTimestampControls;
  const ABannerControls: TWcxBannerControls;
  const ALimitsControls: TWcxLimitsControls;
  AEdtTimestampFont: TEdit; AEdtBannerFont: TEdit;
  AFontDlg: TFontDialog);
begin
  inherited Create;
  FModeControls := AModeControls;
  FOutputControls := AOutputControls;
  FCombinedControls := ACombinedControls;
  FTimestampControls := ATimestampControls;
  FBannerControls := ABannerControls;
  FLimitsControls := ALimitsControls;
  FEdtTimestampFont := AEdtTimestampFont;
  FEdtBannerFont := AEdtBannerFont;
  FFontDlg := AFontDlg;
end;

procedure TWcxOutputPresenter.LoadFrom(ASettings: TWcxSettings);
begin
  BindWcxModeToControls(ASettings, FModeControls);
  BindWcxOutputToControls(ASettings, FOutputControls);
  BindWcxCombinedToControls(ASettings, FCombinedControls);
  BindWcxTimestampToControls(ASettings, FTimestampControls);
  FTimestampFontName := ASettings.TimestampFontName;
  FTimestampFontSize := ASettings.TimestampFontSize;
  UpdateTimestampFontDisplay;
  BindWcxBannerToControls(ASettings, FBannerControls);
  FBannerFontName := ASettings.BannerFontName;
  FBannerFontSize := ASettings.BannerFontSize;
  UpdateBannerFontDisplay;
  BindWcxLimitsToControls(ASettings, FLimitsControls);
end;

procedure TWcxOutputPresenter.SaveTo(ASettings: TWcxSettings);
begin
  BindWcxModeFromControls(ASettings, FModeControls);
  BindWcxOutputFromControls(ASettings, FOutputControls);
  BindWcxCombinedFromControls(ASettings, FCombinedControls);
  BindWcxTimestampFromControls(ASettings, FTimestampControls);
  ASettings.TimestampFontName := FTimestampFontName;
  ASettings.TimestampFontSize := FTimestampFontSize;
  BindWcxBannerFromControls(ASettings, FBannerControls);
  ASettings.BannerFontName := FBannerFontName;
  ASettings.BannerFontSize := FBannerFontSize;
  BindWcxLimitsFromControls(ASettings, FLimitsControls);
end;

procedure TWcxOutputPresenter.UpdateTimestampFontDisplay;
begin
  RefreshFontEdit(FEdtTimestampFont, FTimestampFontName, FTimestampFontSize);
end;

procedure TWcxOutputPresenter.UpdateBannerFontDisplay;
begin
  RefreshBannerFontEdit(FEdtBannerFont, FBannerControls.ChkBannerAutoSize.Checked, FBannerFontName, FBannerFontSize);
end;

procedure TWcxOutputPresenter.OnTimestampFontClick;
begin
  PickFontInto(FFontDlg, FEdtTimestampFont, FTimestampFontName, FTimestampFontSize,
    MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
end;

procedure TWcxOutputPresenter.OnBannerFontClick;
var
  AutoSize: Boolean;
begin
  AutoSize := FBannerControls.ChkBannerAutoSize.Checked;
  PickBannerFontInto(FFontDlg, FEdtBannerFont, AutoSize, FBannerFontName, FBannerFontSize,
    MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE, DEF_BANNER_FONT_SIZE);
  FBannerControls.ChkBannerAutoSize.Checked := AutoSize;
end;

{TWcxPresetEditorPresenter}

constructor TWcxPresetEditorPresenter.Create(APresetModel: TPresetEditorModel;
  const APresetsRepo: IWcxPresetsRepository;
  ALbxPresets: TListBox;
  AEdtPresetName: TEdit; AChkPresetEnabled: TCheckBox;
  AEdtPresetDescription: TEdit; AEdtPresetOutputExt: TEdit;
  AEdtPresetOutputName: TEdit; AMemoPresetArgs: TMemo);
begin
  inherited Create;
  FPresetModel := APresetModel;
  FPresetsRepo := APresetsRepo;
  FLbxPresets := ALbxPresets;
  FEdtPresetName := AEdtPresetName;
  FChkPresetEnabled := AChkPresetEnabled;
  FEdtPresetDescription := AEdtPresetDescription;
  FEdtPresetOutputExt := AEdtPresetOutputExt;
  FEdtPresetOutputName := AEdtPresetOutputName;
  FMemoPresetArgs := AMemoPresetArgs;
  FCurrentPresetIndex := -1;
end;

procedure TWcxPresetEditorPresenter.LoadPresetsFromDisk;
var
  Loaded: TWcxPresetArray;
begin
  if FPresetsRepo <> nil then
    Loaded := FPresetsRepo.LoadAll
  else
    Loaded := nil;
  FPresetModel.LoadFrom(Loaded);
  RefreshPresetList(0);
end;

procedure TWcxPresetEditorPresenter.RefreshPresetList(ASelectIndex: Integer);
var
  I, NewSel: Integer;
  Caption: string;
begin
  FLbxPresets.Items.BeginUpdate;
  try
    FLbxPresets.Items.Clear;
    for I := 0 to FPresetModel.Count - 1 do
    begin
      Caption := FPresetModel.Get(I).Name;
      if not FPresetModel.Get(I).Enabled then
        Caption := Caption + ' (off)';
      FLbxPresets.Items.Add(Caption);
    end;
  finally
    FLbxPresets.Items.EndUpdate;
  end;

  if FPresetModel.Count = 0 then
  begin
    FLbxPresets.ItemIndex := -1;
    ShowPreset(-1);
    Exit;
  end;

  NewSel := ASelectIndex;
  if NewSel < 0 then
    NewSel := 0;
  if NewSel >= FPresetModel.Count then
    NewSel := FPresetModel.Count - 1;
  FLbxPresets.ItemIndex := NewSel;
  ShowPreset(NewSel);
end;

procedure TWcxPresetEditorPresenter.SetEditFieldsEnabled(AEnabled: Boolean);
begin
  FEdtPresetName.Enabled := AEnabled;
  FChkPresetEnabled.Enabled := AEnabled;
  FEdtPresetDescription.Enabled := AEnabled;
  FEdtPresetOutputExt.Enabled := AEnabled;
  FEdtPresetOutputName.Enabled := AEnabled;
  FMemoPresetArgs.Enabled := AEnabled;
end;

procedure TWcxPresetEditorPresenter.ShowPreset(AIndex: Integer);
var
  P: TWcxPreset;
begin
  FCurrentPresetIndex := AIndex;
  if (AIndex < 0) or (AIndex >= FPresetModel.Count) then
  begin
    FEdtPresetName.Text := '';
    FChkPresetEnabled.Checked := False;
    FEdtPresetDescription.Text := '';
    FEdtPresetOutputExt.Text := '';
    FEdtPresetOutputName.Text := '';
    FMemoPresetArgs.Text := '';
    SetEditFieldsEnabled(False);
    Exit;
  end;

  P := FPresetModel.Get(AIndex);
  FEdtPresetName.Text := P.Name;
  FChkPresetEnabled.Checked := P.Enabled;
  FEdtPresetDescription.Text := P.Description;
  FEdtPresetOutputExt.Text := P.OutputExt;
  FEdtPresetOutputName.Text := P.OutputName;
  FMemoPresetArgs.Text := P.Args;
  SetEditFieldsEnabled(True);
end;

procedure TWcxPresetEditorPresenter.CommitCurrentPreset;
var
  P: TWcxPreset;
  ListCaption: string;
begin
  if (FCurrentPresetIndex < 0) or (FCurrentPresetIndex >= FPresetModel.Count) then
    Exit;
  P := FPresetModel.Get(FCurrentPresetIndex);
  P.Name := Trim(FEdtPresetName.Text);
  P.Enabled := FChkPresetEnabled.Checked;
  P.Description := Trim(FEdtPresetDescription.Text);
  P.OutputExt := Trim(FEdtPresetOutputExt.Text);
  P.OutputName := Trim(FEdtPresetOutputName.Text);
  P.Args := FMemoPresetArgs.Text;
  FPresetModel.Update(FCurrentPresetIndex, P);

  {Reflect rename or enabled-toggle in the listbox label without rebuilding
   the whole list, which would lose the user's selection.}
  ListCaption := P.Name;
  if not P.Enabled then
    ListCaption := ListCaption + ' (off)';
  if FCurrentPresetIndex < FLbxPresets.Items.Count then
    FLbxPresets.Items[FCurrentPresetIndex] := ListCaption;
end;

procedure TWcxPresetEditorPresenter.NavigateToValidationFailure(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FLbxPresets.Items.Count) then
  begin
    FLbxPresets.ItemIndex := AIndex;
    ShowPreset(AIndex);
  end;
end;

procedure TWcxPresetEditorPresenter.OnLbxPresetsClick;
begin
  if FLbxPresets.ItemIndex = FCurrentPresetIndex then
    Exit;
  CommitCurrentPreset;
  ShowPreset(FLbxPresets.ItemIndex);
end;

procedure TWcxPresetEditorPresenter.OnBtnPresetAddClick;
var
  NewIdx: Integer;
begin
  CommitCurrentPreset;
  NewIdx := FPresetModel.Add;
  RefreshPresetList(NewIdx);
  try
    FEdtPresetName.SetFocus;
    FEdtPresetName.SelectAll;
  except
    {Focus is a UX nicety, not a correctness requirement; some test
     contexts construct the form without showing it, in which case
     SetFocus throws.}
  end;
end;

procedure TWcxPresetEditorPresenter.OnBtnPresetRemoveClick;
var
  Idx: Integer;
begin
  Idx := FLbxPresets.ItemIndex;
  if Idx < 0 then
    Exit;
  {Skip the commit on remove — the in-flight edits are about to be
   discarded. Drop the model row directly.}
  FCurrentPresetIndex := -1;
  FPresetModel.Remove(Idx);
  RefreshPresetList(Idx);
end;

procedure TWcxPresetEditorPresenter.OnBtnPresetDuplicateClick;
var
  Idx, NewIdx: Integer;
begin
  Idx := FLbxPresets.ItemIndex;
  if Idx < 0 then
    Exit;
  CommitCurrentPreset;
  NewIdx := FPresetModel.Duplicate(Idx);
  if NewIdx >= 0 then
  begin
    RefreshPresetList(NewIdx);
    try
      FEdtPresetName.SetFocus;
      FEdtPresetName.SelectAll;
    except
      {Focus is a UX nicety, not a correctness requirement; some test
       contexts construct the form without showing it, in which case
       SetFocus throws.}
    end;
  end;
end;

end.
