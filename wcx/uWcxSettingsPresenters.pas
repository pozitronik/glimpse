{Cluster presenters for the WCX settings dialog: one per tab domain
 (Extraction, Output, PresetEditor). Each owns its bundles, helpers,
 and event handlers; the form keeps Update*State enable methods,
 TrySaveAll, and OK/Apply/Defaults orchestration.}
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
    procedure LoadPresetsFromDisk;
    procedure RefreshPresetList(ASelectIndex: Integer);
    {Pass -1 to clear and disable the panel.}
    procedure ShowPreset(AIndex: Integer);
    procedure CommitCurrentPreset;
    procedure SetEditFieldsEnabled(AEnabled: Boolean);
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
  uFFmpegLocator,
  uSettingsDlgUI, uSettingsDialogHelpers;

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
begin
  {Re-probe on every call; WLX uses a pre-resolved path threaded in at
   dialog open, but the WCX flow does not.}
  DisplayFFmpegInfo(FFFmpegControls.EdtFFmpegPath.Text,
    FindFFmpegExe(FApplicationDir, ''),
    FLblFFmpegInfo, FEdtFFmpegInfo);
end;

procedure TWcxExtractionPresenter.UpdateRandomPercentLabel;
begin
  FLblRandomPercentValue.Caption := IntToStr(FRandomControls.TrkRandomPercent.Position) + '%';
end;

procedure TWcxExtractionPresenter.OnFFmpegPathClick;
begin
  BrowseForFFmpegExe(FFFmpegControls.EdtFFmpegPath, FParentWnd);
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

  {Patch the label in place rather than rebuild — a full refresh would
   lose the user's selection.}
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
    {SetFocus throws when the form is not shown (test contexts).}
  end;
end;

procedure TWcxPresetEditorPresenter.OnBtnPresetRemoveClick;
var
  Idx: Integer;
begin
  Idx := FLbxPresets.ItemIndex;
  if Idx < 0 then
    Exit;
  {Skip the commit; in-flight edits are about to be discarded.}
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
      {SetFocus throws when the form is not shown (test contexts).}
    end;
  end;
end;

end.
