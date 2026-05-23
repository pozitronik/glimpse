{Tests for wcx/WcxSettingsPresenters. Two layers of coverage:
 per-presenter smoke tests (LoadFrom/SaveTo + update helpers), and
 deeper coverage of TWcxPresetEditorPresenter (preset CRUD,
 navigation, current-row tracking, validation-failure navigation),
 which is the only presenter with non-trivial state transitions.

 Fixture uses a hidden TForm as both owner + parent so VCL handles
 allocate.}
unit TestWcxSettingsPresenters;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxSettingsPresenters = class
  public
    [Test] procedure Extraction_LoadFrom_BindsAndUpdatesPercentLabel;
    [Test] procedure Extraction_SaveTo_RoundTripsBundles;
    [Test] procedure Output_LoadFrom_BindsBundlesAndFontShadows;
    [Test] procedure Output_SaveTo_PushesFontShadowsBackToSettings;
    [Test] procedure PresetEditor_LoadFromDisk_PopulatesListBox;
    [Test] procedure PresetEditor_ShowPreset_PopulatesEditFields;
    [Test] procedure PresetEditor_ShowMinusOne_ClearsAndDisables;
    [Test] procedure PresetEditor_CommitCurrentPreset_WritesBackToModel;
    [Test] procedure PresetEditor_AddPreset_AppendsAndSelects;
    [Test] procedure PresetEditor_RemovePreset_DropsRow;
    [Test] procedure PresetEditor_DuplicatePreset_AddsCopyAndSelects;
    [Test] procedure PresetEditor_NavigateToValidationFailure_SelectsAndShows;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Controls, Vcl.Dialogs,
  Types, BitmapSaver, Defaults,
  WcxSettings, WcxPresets, WcxPresetEditorModel,
  WcxPresetsRepository,
  WcxSettingsControlsBundles,
  WcxSettingsPresenters;

function MakeCheckBox(AParent: TWinControl): TCheckBox;
begin
  Result := TCheckBox.Create(AParent);
  Result.Parent := AParent;
end;

function MakeEdit(AParent: TWinControl): TEdit;
begin
  Result := TEdit.Create(AParent);
  Result.Parent := AParent;
end;

function MakeLabel(AParent: TWinControl): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
end;

function MakeUpDown(AParent: TWinControl; AMin, AMax: Integer): TUpDown;
begin
  Result := TUpDown.Create(AParent);
  Result.Parent := AParent;
  Result.Min := AMin;
  Result.Max := AMax;
end;

function MakePanel(AParent: TWinControl): TPanel;
begin
  Result := TPanel.Create(AParent);
  Result.Parent := AParent;
end;

function MakeComboBox(AParent: TWinControl; ANumItems: Integer): TComboBox;
var
  I: Integer;
begin
  Result := TComboBox.Create(AParent);
  Result.Parent := AParent;
  for I := 0 to ANumItems - 1 do
    Result.Items.Add(IntToStr(I));
end;

function MakeTrackBar(AParent: TWinControl; AMin, AMax: Integer): TTrackBar;
begin
  Result := TTrackBar.Create(AParent);
  Result.Parent := AParent;
  Result.Min := AMin;
  Result.Max := AMax;
end;

function MakeListBox(AParent: TWinControl): TListBox;
begin
  Result := TListBox.Create(AParent);
  Result.Parent := AParent;
end;

function MakeMemo(AParent: TWinControl): TMemo;
begin
  Result := TMemo.Create(AParent);
  Result.Parent := AParent;
end;

procedure BuildExtractionBundle(AParent: TWinControl; out AControls: TWcxExtractionControls);
begin
  AControls.UdFrameCount := MakeUpDown(AParent, 1, 256);
  AControls.UdSkipEdges := MakeUpDown(AParent, 0, 100);
  AControls.ChkMaxWorkersAuto := MakeCheckBox(AParent);
  AControls.UdMaxWorkers := MakeUpDown(AParent, 1, 32);
  AControls.UdMaxThreads := MakeUpDown(AParent, 0, 64);
  AControls.ChkUseBmpPipe := MakeCheckBox(AParent);
  AControls.ChkHwAccel := MakeCheckBox(AParent);
  AControls.ChkUseKeyframes := MakeCheckBox(AParent);
  AControls.ChkRespectAnamorphic := MakeCheckBox(AParent);
end;

procedure BuildRandomBundle(AParent: TWinControl; out AControls: TWcxRandomControls);
begin
  AControls.ChkRandomExtraction := MakeCheckBox(AParent);
  AControls.TrkRandomPercent := MakeTrackBar(AParent, 0, 100);
end;

procedure BuildFFmpegBundle(AParent: TWinControl; out AControls: TWcxFFmpegControls);
begin
  AControls.EdtFFmpegPath := MakeEdit(AParent);
end;

procedure BuildModeBundle(AParent: TWinControl; out AControls: TWcxModeControls);
begin
  AControls.ChkModeFrames := MakeCheckBox(AParent);
  AControls.ChkModeCombined := MakeCheckBox(AParent);
  AControls.ChkModePresets := MakeCheckBox(AParent);
end;

procedure BuildOutputBundle(AParent: TWinControl; out AControls: TWcxOutputControls);
begin
  AControls.CbxFormat := MakeComboBox(AParent, 2);
  AControls.UdJpegQuality := MakeUpDown(AParent, 1, 100);
  AControls.UdPngCompression := MakeUpDown(AParent, 0, 9);
  AControls.UdBackgroundAlpha := MakeUpDown(AParent, 0, 255);
  AControls.ChkShowFileSizes := MakeCheckBox(AParent);
end;

procedure BuildCombinedBundle(AParent: TWinControl; out AControls: TWcxCombinedControls);
begin
  AControls.UdColumns := MakeUpDown(AParent, 0, 16);
  AControls.UdCellGap := MakeUpDown(AParent, 0, 100);
  AControls.UdBorder := MakeUpDown(AParent, 0, 100);
  AControls.PnlBackground := MakePanel(AParent);
end;

procedure BuildTimestampBundle(AParent: TWinControl; out AControls: TWcxTimestampControls);
begin
  AControls.ChkTimestamp := MakeCheckBox(AParent);
  AControls.CbxTimestampCorner := MakeComboBox(AParent, 4);
  AControls.PnlTCBack := MakePanel(AParent);
  AControls.UdTCAlpha := MakeUpDown(AParent, 0, 255);
  AControls.PnlTCTextColor := MakePanel(AParent);
  AControls.UdTCTextAlpha := MakeUpDown(AParent, 0, 255);
end;

procedure BuildBannerBundle(AParent: TWinControl; out AControls: TWcxBannerControls);
begin
  AControls.ChkShowBanner := MakeCheckBox(AParent);
  AControls.PnlBannerBackground := MakePanel(AParent);
  AControls.PnlBannerTextColor := MakePanel(AParent);
  AControls.ChkBannerAutoSize := MakeCheckBox(AParent);
  AControls.CbxBannerPosition := MakeComboBox(AParent, 2);
end;

procedure BuildLimitsBundle(AParent: TWinControl; out AControls: TWcxLimitsControls);
begin
  AControls.UdFrameMax := MakeUpDown(AParent, 0, 8000);
  AControls.UdCombinedMax := MakeUpDown(AParent, 0, 16000);
end;

{In-memory presets reader for preset-editor tests. LoadAll returns the
 seeded array; the presenter only reads, so no writer facet is exposed.}
type
  TFakeWcxPresetsRepo = class(TInterfacedObject, IWcxPresetsReader)
  strict private
    FStored: TWcxPresetArray;
  public
    constructor Create(const ASeed: TWcxPresetArray);
    function LoadAll: TWcxPresetArray;
  end;

constructor TFakeWcxPresetsRepo.Create(const ASeed: TWcxPresetArray);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FStored, Length(ASeed));
  for I := 0 to High(ASeed) do
    FStored[I] := ASeed[I];
end;

function TFakeWcxPresetsRepo.LoadAll: TWcxPresetArray;
begin
  Result := FStored;
end;

{TWcxExtractionPresenter}

procedure TTestWcxSettingsPresenters.Extraction_LoadFrom_BindsAndUpdatesPercentLabel;
var
  Form: TForm;
  Extraction: TWcxExtractionControls;
  Random: TWcxRandomControls;
  FFmpeg: TWcxFFmpegControls;
  LblInfo, LblPercent: TLabel;
  EdtInfo: TEdit;
  P: TWcxExtractionPresenter;
  S: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  try
    BuildExtractionBundle(Form, Extraction);
    BuildRandomBundle(Form, Random);
    BuildFFmpegBundle(Form, FFmpeg);
    LblInfo := MakeLabel(Form);
    LblPercent := MakeLabel(Form);
    EdtInfo := MakeEdit(Form);

    P := TWcxExtractionPresenter.Create(Extraction, Random, FFmpeg,
      LblInfo, EdtInfo, LblPercent, '', 0);
    try
      S.FramesCount := 18;
      S.UseBmpPipe := True;
      S.RandomPercent := 55;
      P.LoadFrom(S);
      Assert.AreEqual(18, Extraction.UdFrameCount.Position);
      Assert.IsTrue(Extraction.ChkUseBmpPipe.Checked);
      Assert.AreEqual(55, Random.TrkRandomPercent.Position);
      Assert.AreEqual('55%', LblPercent.Caption,
        'LoadFrom updates the live random-percent label');
    finally
      P.Free;
    end;
  finally
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.Extraction_SaveTo_RoundTripsBundles;
var
  Form: TForm;
  Extraction: TWcxExtractionControls;
  Random: TWcxRandomControls;
  FFmpeg: TWcxFFmpegControls;
  LblInfo, LblPercent: TLabel;
  EdtInfo: TEdit;
  P: TWcxExtractionPresenter;
  Src, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  Src := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    BuildExtractionBundle(Form, Extraction);
    BuildRandomBundle(Form, Random);
    BuildFFmpegBundle(Form, FFmpeg);
    LblInfo := MakeLabel(Form);
    LblPercent := MakeLabel(Form);
    EdtInfo := MakeEdit(Form);

    P := TWcxExtractionPresenter.Create(Extraction, Random, FFmpeg,
      LblInfo, EdtInfo, LblPercent, '', 0);
    try
      Src.FramesCount := 7;
      Src.HwAccel := True;
      Src.RandomExtraction := True;
      Src.RandomPercent := 42;
      Src.FFmpegExePath := 'C:\ffmpeg.exe';
      P.LoadFrom(Src);

      P.SaveTo(R);
      Assert.AreEqual(7, R.FramesCount);
      Assert.IsTrue(R.HwAccel);
      Assert.IsTrue(R.RandomExtraction);
      Assert.AreEqual(42, R.RandomPercent);
      Assert.AreEqual('C:\ffmpeg.exe', R.FFmpegExePath);
    finally
      P.Free;
    end;
  finally
    R.Free;
    Src.Free;
    Form.Free;
  end;
end;

{TWcxOutputPresenter}

procedure TTestWcxSettingsPresenters.Output_LoadFrom_BindsBundlesAndFontShadows;
var
  Form: TForm;
  Mode: TWcxModeControls;
  Output: TWcxOutputControls;
  Combined: TWcxCombinedControls;
  Timestamp: TWcxTimestampControls;
  Banner: TWcxBannerControls;
  Limits: TWcxLimitsControls;
  EdtTSFont, EdtBnFont: TEdit;
  FontDlg: TFontDialog;
  P: TWcxOutputPresenter;
  S: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  FontDlg := TFontDialog.Create(Form);
  try
    BuildModeBundle(Form, Mode);
    BuildOutputBundle(Form, Output);
    BuildCombinedBundle(Form, Combined);
    BuildTimestampBundle(Form, Timestamp);
    BuildBannerBundle(Form, Banner);
    BuildLimitsBundle(Form, Limits);
    EdtTSFont := MakeEdit(Form);
    EdtBnFont := MakeEdit(Form);

    P := TWcxOutputPresenter.Create(Mode, Output, Combined,
      Timestamp, Banner, Limits, EdtTSFont, EdtBnFont, FontDlg);
    try
      S.SaveFormat := sfPNG;
      S.CombinedColumns := 6;
      S.Background := clNavy;
      S.ShowTimestamp := True;
      S.TimestampFontName := 'Verdana';
      S.TimestampFontSize := 11;
      S.BannerFontName := 'Tahoma';
      S.BannerFontSize := 12;
      S.FrameMaxSide := 720;
      S.CombinedMaxSide := 3000;

      P.LoadFrom(S);
      Assert.AreEqual(Ord(sfPNG), Output.CbxFormat.ItemIndex, 'Output bundle bound');
      Assert.AreEqual(6, Combined.UdColumns.Position, 'Combined bundle bound');
      Assert.IsTrue(Combined.PnlBackground.Color = clNavy);
      Assert.IsTrue(Timestamp.ChkTimestamp.Checked);
      Assert.IsTrue(Pos('Verdana', EdtTSFont.Text) > 0,
        'Timestamp font shadow rendered into the font display edit');
      Assert.IsTrue(Pos('Tahoma', EdtBnFont.Text) > 0,
        'Banner font shadow rendered into the font display edit');
      Assert.AreEqual(720, Limits.UdFrameMax.Position);
    finally
      P.Free;
    end;
  finally
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.Output_SaveTo_PushesFontShadowsBackToSettings;
var
  Form: TForm;
  Mode: TWcxModeControls;
  Output: TWcxOutputControls;
  Combined: TWcxCombinedControls;
  Timestamp: TWcxTimestampControls;
  Banner: TWcxBannerControls;
  Limits: TWcxLimitsControls;
  EdtTSFont, EdtBnFont: TEdit;
  FontDlg: TFontDialog;
  P: TWcxOutputPresenter;
  Src, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  Src := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  FontDlg := TFontDialog.Create(Form);
  try
    BuildModeBundle(Form, Mode);
    BuildOutputBundle(Form, Output);
    BuildCombinedBundle(Form, Combined);
    BuildTimestampBundle(Form, Timestamp);
    BuildBannerBundle(Form, Banner);
    BuildLimitsBundle(Form, Limits);
    EdtTSFont := MakeEdit(Form);
    EdtBnFont := MakeEdit(Form);

    P := TWcxOutputPresenter.Create(Mode, Output, Combined,
      Timestamp, Banner, Limits, EdtTSFont, EdtBnFont, FontDlg);
    try
      Src.TimestampFontName := 'Consolas';
      Src.TimestampFontSize := 13;
      Src.BannerFontName := 'Segoe UI';
      Src.BannerFontSize := 16;
      P.LoadFrom(Src);

      P.SaveTo(R);
      Assert.AreEqual('Consolas', R.TimestampFontName);
      Assert.AreEqual(13, R.TimestampFontSize);
      Assert.AreEqual('Segoe UI', R.BannerFontName);
      Assert.AreEqual(16, R.BannerFontSize);
    finally
      P.Free;
    end;
  finally
    R.Free;
    Src.Free;
    Form.Free;
  end;
end;

{TWcxPresetEditorPresenter — deeper coverage}

{Builds a presenter wired to the supplied model + repo, with fresh
 VCL controls under AForm. Caller frees the presenter.}
function BuildPresetEditor(AForm: TForm; AModel: TPresetEditorModel;
  const ARepo: IWcxPresetsReader): TWcxPresetEditorPresenter;
var
  Lbx: TListBox;
  EdtName, EdtDesc, EdtExt, EdtOutName: TEdit;
  Chk: TCheckBox;
  Memo: TMemo;
begin
  Lbx := MakeListBox(AForm);
  EdtName := MakeEdit(AForm);
  Chk := MakeCheckBox(AForm);
  EdtDesc := MakeEdit(AForm);
  EdtExt := MakeEdit(AForm);
  EdtOutName := MakeEdit(AForm);
  Memo := MakeMemo(AForm);
  Result := TWcxPresetEditorPresenter.Create(AModel, ARepo, Lbx,
    EdtName, Chk, EdtDesc, EdtExt, EdtOutName, Memo);
end;

procedure TTestWcxSettingsPresenters.PresetEditor_LoadFromDisk_PopulatesListBox;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  Lbx: TListBox;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 3);
  Seed[0].Name := 'h264'; Seed[0].Enabled := True;
  Seed[1].Name := 'h265'; Seed[1].Enabled := False;
  Seed[2].Name := 'av1'; Seed[2].Enabled := True;
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      Lbx := TListBox(Form.Controls[0]); {first child of the form}
      Assert.AreEqual(3, Lbx.Items.Count);
      Assert.AreEqual('h264', Lbx.Items[0]);
      Assert.AreEqual('h265 (off)', Lbx.Items[1],
        'Disabled presets are suffixed " (off)" in the listbox caption');
      Assert.AreEqual('av1', Lbx.Items[2]);
      Assert.AreEqual(0, Lbx.ItemIndex, 'First row selected by default');
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_ShowPreset_PopulatesEditFields;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  EdtName: TEdit;
  Memo: TMemo;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 1);
  Seed[0].Name := 'fastdraft';
  Seed[0].Enabled := True;
  Seed[0].Description := 'Quick preview';
  Seed[0].OutputExt := 'mp4';
  Seed[0].Args := '-preset ultrafast';
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      EdtName := TEdit(Form.Controls[1]);
      Memo := TMemo(Form.Controls[6]);
      Assert.AreEqual('fastdraft', EdtName.Text);
      Assert.AreEqual('-preset ultrafast', Memo.Text);
      Assert.AreEqual(0, P.CurrentPresetIndex);
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_ShowMinusOne_ClearsAndDisables;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  EdtName: TEdit;
  Memo: TMemo;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 1);
  Seed[0].Name := 'preset1';
  Seed[0].Enabled := True;
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      EdtName := TEdit(Form.Controls[1]);
      Memo := TMemo(Form.Controls[6]);

      P.ShowPreset(-1);
      Assert.AreEqual('', EdtName.Text, 'ShowPreset(-1) clears edit fields');
      Assert.AreEqual('', Memo.Text);
      Assert.IsFalse(EdtName.Enabled, 'ShowPreset(-1) disables edit fields');
      Assert.IsFalse(Memo.Enabled);
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_CommitCurrentPreset_WritesBackToModel;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  EdtName, EdtExt: TEdit;
  Updated: TWcxPreset;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 1);
  Seed[0].Name := 'original';
  Seed[0].OutputExt := 'mkv';
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      EdtName := TEdit(Form.Controls[1]);
      EdtExt := TEdit(Form.Controls[4]);
      EdtName.Text := 'renamed';
      EdtExt.Text := 'webm';
      P.CommitCurrentPreset;

      Updated := Model.Get(0);
      Assert.AreEqual('renamed', Updated.Name,
        'CommitCurrentPreset writes the user-edited Name back to the model');
      Assert.AreEqual('webm', Updated.OutputExt);
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_AddPreset_AppendsAndSelects;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  Lbx: TListBox;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 1);
  Seed[0].Name := 'existing';
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      Lbx := TListBox(Form.Controls[0]);

      P.OnBtnPresetAddClick;
      Assert.AreEqual(2, Model.Count, 'Add appends a new row to the model');
      Assert.AreEqual(2, Lbx.Items.Count);
      Assert.AreEqual(1, Lbx.ItemIndex, 'New row is selected');
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_RemovePreset_DropsRow;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  Lbx: TListBox;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 2);
  Seed[0].Name := 'a';
  Seed[1].Name := 'b';
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      Lbx := TListBox(Form.Controls[0]);
      Lbx.ItemIndex := 0;

      P.OnBtnPresetRemoveClick;
      Assert.AreEqual(1, Model.Count, 'Remove drops the selected row from the model');
      Assert.AreEqual('b', Model.Get(0).Name);
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_DuplicatePreset_AddsCopyAndSelects;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  Lbx: TListBox;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 1);
  Seed[0].Name := 'src';
  Seed[0].OutputExt := 'mp4';
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      Lbx := TListBox(Form.Controls[0]);
      Lbx.ItemIndex := 0;

      P.OnBtnPresetDuplicateClick;
      Assert.AreEqual(2, Model.Count, 'Duplicate adds a copy to the model');
      Assert.AreEqual(1, Lbx.ItemIndex, 'Duplicate selects the new row');
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsPresenters.PresetEditor_NavigateToValidationFailure_SelectsAndShows;
var
  Form: TForm;
  Model: TPresetEditorModel;
  Repo: IWcxPresetsReader;
  Seed: TWcxPresetArray;
  P: TWcxPresetEditorPresenter;
  Lbx: TListBox;
  EdtName: TEdit;
begin
  Form := TForm.CreateNew(nil);
  Model := TPresetEditorModel.Create;
  SetLength(Seed, 3);
  Seed[0].Name := 'first';
  Seed[1].Name := 'second';
  Seed[2].Name := 'third';
  Repo := TFakeWcxPresetsRepo.Create(Seed);
  try
    P := BuildPresetEditor(Form, Model, Repo);
    try
      P.LoadPresetsFromDisk;
      Lbx := TListBox(Form.Controls[0]);
      EdtName := TEdit(Form.Controls[1]);

      P.NavigateToValidationFailure(2);
      Assert.AreEqual(2, Lbx.ItemIndex, 'NavigateToValidationFailure selects the offending row');
      Assert.AreEqual('third', EdtName.Text,
        'NavigateToValidationFailure also calls ShowPreset to populate edit fields');
      Assert.AreEqual(2, P.CurrentPresetIndex);
    finally
      P.Free;
    end;
  finally
    Model.Free;
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxSettingsPresenters);

end.
