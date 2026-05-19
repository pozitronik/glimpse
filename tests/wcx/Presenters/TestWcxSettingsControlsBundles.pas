{Tests for wcx/WcxSettingsControlsBundles. Per-bundle round-trip
 coverage, mirroring TestSettingsControlsBundles (WLX). Hidden
 TForm.CreateNew acts as both owner + parent so TComboBox.ItemIndex /
 TUpDown.Position have a backing window. Focused on the WCX-specific
 bundles (Mode + Output + Combined + Limits) and the WCX shape of the
 shared concepts (Extraction with FrameCount; Timestamp using
 ShowTimestamp).}
unit TestWcxSettingsControlsBundles;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxSettingsControlsBundles = class
  public
    [Test] procedure Extraction_Roundtrip_PinsAllFieldsIncludingFrameCount;
    [Test] procedure Random_Roundtrip_PinsToggleAndPercent;
    [Test] procedure FFmpeg_Roundtrip_DirectAssignment;
    [Test] procedure Mode_Roundtrip_TogglesUnderlyingBitmask;
    [Test] procedure Output_Roundtrip_PinsFormatAndShowFileSizes;
    [Test] procedure Combined_Roundtrip_PinsColumnsAndBackground;
    [Test] procedure Timestamp_Roundtrip_PinsShowTimestamp;
    [Test] procedure Banner_Roundtrip_PinsAllFields;
    [Test] procedure Limits_Roundtrip_PinsFrameAndCombinedMax;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Controls,
  Types, BitmapSaver,
  WcxSettings,
  WcxSettingsControlsBundles;

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

procedure TTestWcxSettingsControlsBundles.Extraction_Roundtrip_PinsAllFieldsIncludingFrameCount;
var
  Form: TForm;
  B: TWcxExtractionControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.UdFrameCount := MakeUpDown(Form, 1, 256);
    B.UdSkipEdges := MakeUpDown(Form, 0, 100);
    B.ChkMaxWorkersAuto := MakeCheckBox(Form);
    B.UdMaxWorkers := MakeUpDown(Form, 1, 32);
    B.UdMaxThreads := MakeUpDown(Form, 0, 64);
    B.ChkUseBmpPipe := MakeCheckBox(Form);
    B.ChkHwAccel := MakeCheckBox(Form);
    B.ChkUseKeyframes := MakeCheckBox(Form);
    B.ChkRespectAnamorphic := MakeCheckBox(Form);

    S.FramesCount := 24;
    S.SkipEdgesPercent := 13;
    S.MaxWorkers := 6;
    S.MaxThreads := 4;
    S.UseBmpPipe := True;
    S.HwAccel := True;
    S.UseKeyframes := False;
    S.RespectAnamorphic := True;

    BindWcxExtractionToControls(S, B);
    Assert.AreEqual(24, B.UdFrameCount.Position,
      'FrameCount is WCX-specific (WLX manages this via toolbar); bundle must bind it');
    Assert.IsFalse(B.ChkMaxWorkersAuto.Checked);
    Assert.AreEqual(6, B.UdMaxWorkers.Position);
    Assert.IsTrue(B.ChkUseBmpPipe.Checked);

    BindWcxExtractionFromControls(R, B);
    Assert.AreEqual(24, R.FramesCount);
    Assert.AreEqual(13, R.SkipEdgesPercent);
    Assert.AreEqual(6, R.MaxWorkers);
    Assert.AreEqual(4, R.MaxThreads);
    Assert.IsTrue(R.UseBmpPipe);
    Assert.IsTrue(R.HwAccel);
    Assert.IsFalse(R.UseKeyframes);
    Assert.IsTrue(R.RespectAnamorphic);
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Random_Roundtrip_PinsToggleAndPercent;
var
  Form: TForm;
  B: TWcxRandomControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.ChkRandomExtraction := MakeCheckBox(Form);
    B.TrkRandomPercent := MakeTrackBar(Form, 0, 100);

    S.RandomExtraction := True;
    S.RandomPercent := 65;
    BindWcxRandomToControls(S, B);
    Assert.IsTrue(B.ChkRandomExtraction.Checked);
    Assert.AreEqual(65, B.TrkRandomPercent.Position);

    BindWcxRandomFromControls(R, B);
    Assert.IsTrue(R.RandomExtraction);
    Assert.AreEqual(65, R.RandomPercent);
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.FFmpeg_Roundtrip_DirectAssignment;
var
  Form: TForm;
  B: TWcxFFmpegControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.EdtFFmpegPath := MakeEdit(Form);
    S.FFmpegExePath := 'D:\tools\ffmpeg.exe';
    BindWcxFFmpegToControls(S, B);
    Assert.AreEqual('D:\tools\ffmpeg.exe', B.EdtFFmpegPath.Text);

    B.EdtFFmpegPath.Text := 'E:\new\ffmpeg.exe';
    BindWcxFFmpegFromControls(R, B);
    Assert.AreEqual('E:\new\ffmpeg.exe', R.FFmpegExePath,
      'WCX uses direct property assignment (no SetFFmpegPath setter exists)');
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Mode_Roundtrip_TogglesUnderlyingBitmask;
var
  Form: TForm;
  B: TWcxModeControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.ChkModeFrames := MakeCheckBox(Form);
    B.ChkModeCombined := MakeCheckBox(Form);
    B.ChkModePresets := MakeCheckBox(Form);

    S.ShowFrames := True;
    S.ShowCombined := False;
    S.ShowPresets := True;

    BindWcxModeToControls(S, B);
    Assert.IsTrue(B.ChkModeFrames.Checked);
    Assert.IsFalse(B.ChkModeCombined.Checked);
    Assert.IsTrue(B.ChkModePresets.Checked);

    BindWcxModeFromControls(R, B);
    Assert.IsTrue(R.ShowFrames);
    Assert.IsFalse(R.ShowCombined);
    Assert.IsTrue(R.ShowPresets,
      'Each setter manipulates one bit of the underlying Mode bitmask; round-trip preserves all three');
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Output_Roundtrip_PinsFormatAndShowFileSizes;
var
  Form: TForm;
  B: TWcxOutputControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.CbxFormat := MakeComboBox(Form, 2);
    B.UdJpegQuality := MakeUpDown(Form, 1, 100);
    B.UdPngCompression := MakeUpDown(Form, 0, 9);
    B.UdBackgroundAlpha := MakeUpDown(Form, 0, 255);
    B.ChkShowFileSizes := MakeCheckBox(Form);

    S.SaveFormat := sfJPEG;
    S.JpegQuality := 80;
    S.PngCompression := 6;
    S.BackgroundAlpha := 200;
    S.ShowFileSizes := True;

    BindWcxOutputToControls(S, B);
    Assert.AreEqual(Ord(sfJPEG), B.CbxFormat.ItemIndex);
    Assert.AreEqual(200, B.UdBackgroundAlpha.Position);
    Assert.IsTrue(B.ChkShowFileSizes.Checked);

    BindWcxOutputFromControls(R, B);
    Assert.IsTrue(R.SaveFormat = sfJPEG);
    Assert.AreEqual(80, R.JpegQuality);
    Assert.AreEqual(200, Integer(R.BackgroundAlpha));
    Assert.IsTrue(R.ShowFileSizes);
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Combined_Roundtrip_PinsColumnsAndBackground;
var
  Form: TForm;
  B: TWcxCombinedControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.UdColumns := MakeUpDown(Form, 0, 16);
    B.UdCellGap := MakeUpDown(Form, 0, 100);
    B.UdBorder := MakeUpDown(Form, 0, 100);
    B.PnlBackground := MakePanel(Form);

    S.CombinedColumns := 4;
    S.CellGap := 5;
    S.CombinedBorder := 8;
    S.Background := clGreen;

    BindWcxCombinedToControls(S, B);
    Assert.AreEqual(4, B.UdColumns.Position);
    Assert.IsTrue(B.PnlBackground.Color = clGreen);

    BindWcxCombinedFromControls(R, B);
    Assert.AreEqual(4, R.CombinedColumns);
    Assert.AreEqual(5, R.CellGap);
    Assert.AreEqual(8, R.CombinedBorder);
    Assert.IsTrue(R.Background = clGreen);
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Timestamp_Roundtrip_PinsShowTimestamp;
var
  Form: TForm;
  B: TWcxTimestampControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.ChkTimestamp := MakeCheckBox(Form);
    B.CbxTimestampCorner := MakeComboBox(Form, 4);
    B.PnlTCBack := MakePanel(Form);
    B.UdTCAlpha := MakeUpDown(Form, 0, 255);
    B.PnlTCTextColor := MakePanel(Form);
    B.UdTCTextAlpha := MakeUpDown(Form, 0, 255);

    S.ShowTimestamp := True;
    S.TimestampCorner := tcTopLeft;
    S.TimecodeBackColor := clMaroon;
    S.TimecodeBackAlpha := 160;
    S.TimestampTextColor := clAqua;
    S.TimestampTextAlpha := 220;

    BindWcxTimestampToControls(S, B);
    Assert.IsTrue(B.ChkTimestamp.Checked,
      'WCX exposes ShowTimestamp via ChkTimestamp (WLX naming differs)');
    Assert.AreEqual(220, B.UdTCTextAlpha.Position);

    BindWcxTimestampFromControls(R, B);
    Assert.IsTrue(R.ShowTimestamp);
    Assert.IsTrue(R.TimestampCorner = tcTopLeft);
    Assert.IsTrue(R.TimecodeBackColor = clMaroon);
    Assert.AreEqual(220, Integer(R.TimestampTextAlpha));
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Banner_Roundtrip_PinsAllFields;
var
  Form: TForm;
  B: TWcxBannerControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.ChkShowBanner := MakeCheckBox(Form);
    B.PnlBannerBackground := MakePanel(Form);
    B.PnlBannerTextColor := MakePanel(Form);
    B.ChkBannerAutoSize := MakeCheckBox(Form);
    B.CbxBannerPosition := MakeComboBox(Form, 2);

    S.ShowBanner := True;
    S.BannerBackground := clBlack;
    S.BannerTextColor := clWhite;
    S.BannerFontAutoSize := False;
    S.BannerPosition := bpTop;

    BindWcxBannerToControls(S, B);
    Assert.IsTrue(B.ChkShowBanner.Checked);
    Assert.IsFalse(B.ChkBannerAutoSize.Checked);
    Assert.AreEqual(Ord(bpTop), B.CbxBannerPosition.ItemIndex);

    BindWcxBannerFromControls(R, B);
    Assert.IsTrue(R.ShowBanner);
    Assert.IsTrue(R.BannerBackground = clBlack);
    Assert.IsFalse(R.BannerFontAutoSize);
    Assert.IsTrue(R.BannerPosition = bpTop);
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

procedure TTestWcxSettingsControlsBundles.Limits_Roundtrip_PinsFrameAndCombinedMax;
var
  Form: TForm;
  B: TWcxLimitsControls;
  S, R: TWcxSettings;
begin
  Form := TForm.CreateNew(nil);
  S := TWcxSettings.Create('');
  R := TWcxSettings.Create('');
  try
    B.UdFrameMax := MakeUpDown(Form, 0, 8000);
    B.UdCombinedMax := MakeUpDown(Form, 0, 16000);

    S.FrameMaxSide := 1080;
    S.CombinedMaxSide := 4096;

    BindWcxLimitsToControls(S, B);
    Assert.AreEqual(1080, B.UdFrameMax.Position);
    Assert.AreEqual(4096, B.UdCombinedMax.Position);

    BindWcxLimitsFromControls(R, B);
    Assert.AreEqual(1080, R.FrameMaxSide);
    Assert.AreEqual(4096, R.CombinedMaxSide);
  finally
    R.Free;
    S.Free;
    Form.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxSettingsControlsBundles);

end.
