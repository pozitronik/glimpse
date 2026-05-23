{Tests for wlx/SettingsControlsBundles. Each bundle is exercised
 end-to-end with real VCL controls (TCheckBox, TEdit, TUpDown,
 TPanel, TComboBox, TTrackBar). Per bundle two contracts are pinned:
 BindXxxToControls writes settings values into the control cluster,
 and BindXxxFromControls reads them back and round-trips cleanly.
 Encode/decode edge cases (MaxWorkers auto vs manual, enum ord-cast,
 etc.) have dedicated tests to guard against silent contract drift.}
unit TestSettingsControlsBundles;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsControlsBundles = class
  public
    [Test] procedure Extraction_Roundtrip_PinsAllFields;
    [Test] procedure Extraction_MaxWorkers_AutoCheckbox_EncodesToZero;
    [Test] procedure Extraction_MaxWorkers_NonAutoCheckbox_EncodesPositive;
    [Test] procedure Extraction_MaxThreads_Zero_DecodesToZero;
    [Test] procedure Save_Roundtrip_PinsAllFields;
    [Test] procedure Save_SaveFormat_EnumRoundTripsViaItemIndex;
    [Test] procedure Cache_Roundtrip_PinsAllFields;
    [Test] procedure FFmpeg_Roundtrip_UsesSetterOnWrite;
    [Test] procedure View_Roundtrip_PinsAllFields;
    [Test] procedure View_ProgressBarLayout_EnumRoundTripsViaItemIndex;
    [Test] procedure Timestamp_Roundtrip_PinsAllFields;
    [Test] procedure Timestamp_DecodeEncode_ShowOff_PreservesCornerOnReencode;
    [Test] procedure Banner_Roundtrip_PinsAllFields;
    [Test] procedure Banner_Position_EnumRoundTripsViaItemIndex;
    [Test] procedure ClipboardFormats_Roundtrip_PinsAllFields;
    [Test] procedure StatusBar_Roundtrip_PinsAllFields;
    [Test] procedure StatusBar_HeightApplyMode_EnumRoundTripsViaItemIndex;
    [Test] procedure QuickView_Roundtrip_PinsAllFields;
    [Test] procedure Thumbnails_Roundtrip_PinsAllFields;
    [Test] procedure Thumbnails_Mode_EnumRoundTripsViaItemIndex;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Controls,
  Types, StatusBarLayout, BitmapSaver, Defaults,
  Settings,
  SettingsControlsBundles;

{Helper factories: each VCL control needs an Owner that frees it AND
 a Parent that backs it with a window handle (TComboBox.ItemIndex,
 TUpDown.Position et al. need an allocated handle to apply). The
 fixture uses a hidden TForm as both owner and parent — its handle
 backs every child. Form.Free in the finally cascades to all
 children.}

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

{Extraction}

procedure TTestSettingsControlsBundles.Extraction_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TExtractionControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.UdSkipEdges := MakeUpDown(Owner, 0, 100);
    Bundle.ChkMaxWorkersAuto := MakeCheckBox(Owner);
    Bundle.UdMaxWorkers := MakeUpDown(Owner, 1, 32);
    Bundle.UdMaxThreads := MakeUpDown(Owner, 0, 64);
    Bundle.ChkUseBmpPipe := MakeCheckBox(Owner);
    Bundle.ChkHwAccel := MakeCheckBox(Owner);
    Bundle.ChkUseKeyframes := MakeCheckBox(Owner);
    Bundle.ChkRespectAnamorphic := MakeCheckBox(Owner);

    Settings.SkipEdgesPercent := 17;
    Settings.MaxWorkers := 7;
    Settings.MaxThreads := 3;
    Settings.UseBmpPipe := True;
    Settings.HwAccel := False;
    Settings.UseKeyframes := True;
    Settings.RespectAnamorphic := False;

    BindExtractionToControls(Settings, Bundle);
    Assert.AreEqual(17, Bundle.UdSkipEdges.Position);
    Assert.IsFalse(Bundle.ChkMaxWorkersAuto.Checked, 'MaxWorkers=7 must decode to non-auto');
    Assert.AreEqual(7, Bundle.UdMaxWorkers.Position);
    Assert.AreEqual(3, Bundle.UdMaxThreads.Position);
    Assert.IsTrue(Bundle.ChkUseBmpPipe.Checked);
    Assert.IsFalse(Bundle.ChkHwAccel.Checked);
    Assert.IsTrue(Bundle.ChkUseKeyframes.Checked);
    Assert.IsFalse(Bundle.ChkRespectAnamorphic.Checked);

    BindExtractionFromControls(Reloaded, Bundle);
    Assert.AreEqual(17, Reloaded.SkipEdgesPercent);
    Assert.AreEqual(7, Reloaded.MaxWorkers);
    Assert.AreEqual(3, Reloaded.MaxThreads);
    Assert.IsTrue(Reloaded.UseBmpPipe);
    Assert.IsFalse(Reloaded.HwAccel);
    Assert.IsTrue(Reloaded.UseKeyframes);
    Assert.IsFalse(Reloaded.RespectAnamorphic);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Extraction_MaxWorkers_AutoCheckbox_EncodesToZero;
var
  Owner: TForm;
  Bundle: TExtractionControls;
  Settings: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.UdSkipEdges := MakeUpDown(Owner, 0, 100);
    Bundle.ChkMaxWorkersAuto := MakeCheckBox(Owner);
    Bundle.UdMaxWorkers := MakeUpDown(Owner, 1, 32);
    Bundle.UdMaxThreads := MakeUpDown(Owner, 0, 64);
    Bundle.ChkUseBmpPipe := MakeCheckBox(Owner);
    Bundle.ChkHwAccel := MakeCheckBox(Owner);
    Bundle.ChkUseKeyframes := MakeCheckBox(Owner);
    Bundle.ChkRespectAnamorphic := MakeCheckBox(Owner);

    Bundle.ChkMaxWorkersAuto.Checked := True;
    Bundle.UdMaxWorkers.Position := 5; {Ignored when auto is checked}
    BindExtractionFromControls(Settings, Bundle);
    Assert.AreEqual(0, Settings.MaxWorkers,
      'Auto checkbox checked must encode to MaxWorkers=0 regardless of spinner value');
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Extraction_MaxWorkers_NonAutoCheckbox_EncodesPositive;
var
  Owner: TForm;
  Bundle: TExtractionControls;
  Settings: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.UdSkipEdges := MakeUpDown(Owner, 0, 100);
    Bundle.ChkMaxWorkersAuto := MakeCheckBox(Owner);
    Bundle.UdMaxWorkers := MakeUpDown(Owner, 1, 32);
    Bundle.UdMaxThreads := MakeUpDown(Owner, 0, 64);
    Bundle.ChkUseBmpPipe := MakeCheckBox(Owner);
    Bundle.ChkHwAccel := MakeCheckBox(Owner);
    Bundle.ChkUseKeyframes := MakeCheckBox(Owner);
    Bundle.ChkRespectAnamorphic := MakeCheckBox(Owner);

    Bundle.ChkMaxWorkersAuto.Checked := False;
    Bundle.UdMaxWorkers.Position := 4;
    BindExtractionFromControls(Settings, Bundle);
    Assert.AreEqual(4, Settings.MaxWorkers,
      'Non-auto must propagate the spinner value verbatim');
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Extraction_MaxThreads_Zero_DecodesToZero;
var
  Owner: TForm;
  Bundle: TExtractionControls;
  Settings: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.UdSkipEdges := MakeUpDown(Owner, 0, 100);
    Bundle.ChkMaxWorkersAuto := MakeCheckBox(Owner);
    Bundle.UdMaxWorkers := MakeUpDown(Owner, 1, 32);
    Bundle.UdMaxThreads := MakeUpDown(Owner, 0, 64);
    Bundle.ChkUseBmpPipe := MakeCheckBox(Owner);
    Bundle.ChkHwAccel := MakeCheckBox(Owner);
    Bundle.ChkUseKeyframes := MakeCheckBox(Owner);
    Bundle.ChkRespectAnamorphic := MakeCheckBox(Owner);

    Settings.MaxThreads := 0;
    BindExtractionToControls(Settings, Bundle);
    Assert.AreEqual(0, Bundle.UdMaxThreads.Position,
      'MaxThreads=0 means "ffmpeg default"; spinner shows 0');
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

{Save}

procedure TTestSettingsControlsBundles.Save_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TSaveControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.CbxSaveFormat := MakeComboBox(Owner, 2);
    Bundle.UdJpegQuality := MakeUpDown(Owner, 1, 100);
    Bundle.UdPngCompression := MakeUpDown(Owner, 0, 9);
    Bundle.UdBackgroundAlpha := MakeUpDown(Owner, 0, 255);
    Bundle.EdtSaveFolder := MakeEdit(Owner);
    Bundle.ChkSaveAtLiveResolution := MakeCheckBox(Owner);
    Bundle.ChkCopyAtLiveResolution := MakeCheckBox(Owner);
    Bundle.ChkClipboardAsFileReference := MakeCheckBox(Owner);
    Bundle.UdCombinedMaxSide := MakeUpDown(Owner, 0, 16384);
    Bundle.ChkScaledExtraction := MakeCheckBox(Owner);
    Bundle.UdMinFrameSide := MakeUpDown(Owner, 0, 4096);
    Bundle.UdMaxFrameSide := MakeUpDown(Owner, 0, 4096);
    Bundle.ChkAutoRefreshViewport := MakeCheckBox(Owner);
    Bundle.EdtExtensions := MakeEdit(Owner);

    Settings.SaveFormat := sfJPEG;
    Settings.JpegQuality := 87;
    Settings.PngCompression := 5;
    Settings.BackgroundAlpha := 128;
    Settings.SaveFolder := 'C:\frames';
    Settings.SaveAtLiveResolution := True;
    Settings.CopyAtLiveResolution := False;
    Settings.ClipboardAsFileReference := True;
    Settings.CombinedMaxSide := 4000;
    Settings.ScaledExtraction := True;
    Settings.MinFrameSide := 240;
    Settings.MaxFrameSide := 1080;
    Settings.AutoRefreshOnViewportChange := True;
    Settings.ExtensionList := 'mp4,mkv,webm';

    BindSaveToControls(Settings, Bundle);
    Assert.AreEqual(Ord(sfJPEG), Bundle.CbxSaveFormat.ItemIndex);
    Assert.AreEqual(87, Bundle.UdJpegQuality.Position);
    Assert.AreEqual(5, Bundle.UdPngCompression.Position);
    Assert.AreEqual(128, Bundle.UdBackgroundAlpha.Position);
    Assert.AreEqual('C:\frames', Bundle.EdtSaveFolder.Text);
    Assert.IsTrue(Bundle.ChkSaveAtLiveResolution.Checked);
    Assert.IsFalse(Bundle.ChkCopyAtLiveResolution.Checked);
    Assert.IsTrue(Bundle.ChkClipboardAsFileReference.Checked);
    Assert.AreEqual(4000, Bundle.UdCombinedMaxSide.Position);
    Assert.IsTrue(Bundle.ChkScaledExtraction.Checked);
    Assert.AreEqual(240, Bundle.UdMinFrameSide.Position);
    Assert.AreEqual(1080, Bundle.UdMaxFrameSide.Position);
    Assert.IsTrue(Bundle.ChkAutoRefreshViewport.Checked);
    Assert.AreEqual('mp4,mkv,webm', Bundle.EdtExtensions.Text);

    BindSaveFromControls(Reloaded, Bundle);
    Assert.AreEqual(Ord(sfJPEG), Ord(Reloaded.SaveFormat));
    Assert.AreEqual(87, Reloaded.JpegQuality);
    Assert.AreEqual(128, Integer(Reloaded.BackgroundAlpha));
    Assert.AreEqual('C:\frames', Reloaded.SaveFolder);
    Assert.IsTrue(Reloaded.SaveAtLiveResolution);
    Assert.IsTrue(Reloaded.ClipboardAsFileReference);
    Assert.AreEqual(4000, Reloaded.CombinedMaxSide);
    Assert.IsTrue(Reloaded.ScaledExtraction);
    Assert.AreEqual(240, Reloaded.MinFrameSide);
    Assert.AreEqual(1080, Reloaded.MaxFrameSide);
    Assert.IsTrue(Reloaded.AutoRefreshOnViewportChange);
    Assert.AreEqual('mp4,mkv,webm', Reloaded.ExtensionList);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Save_SaveFormat_EnumRoundTripsViaItemIndex;
var
  Owner: TForm;
  Bundle: TSaveControls;
  Settings: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.CbxSaveFormat := MakeComboBox(Owner, 2);
    Bundle.UdJpegQuality := MakeUpDown(Owner, 1, 100);
    Bundle.UdPngCompression := MakeUpDown(Owner, 0, 9);
    Bundle.UdBackgroundAlpha := MakeUpDown(Owner, 0, 255);
    Bundle.EdtSaveFolder := MakeEdit(Owner);
    Bundle.ChkSaveAtLiveResolution := MakeCheckBox(Owner);
    Bundle.ChkCopyAtLiveResolution := MakeCheckBox(Owner);
    Bundle.ChkClipboardAsFileReference := MakeCheckBox(Owner);
    Bundle.UdCombinedMaxSide := MakeUpDown(Owner, 0, 16384);
    Bundle.ChkScaledExtraction := MakeCheckBox(Owner);
    Bundle.UdMinFrameSide := MakeUpDown(Owner, 0, 4096);
    Bundle.UdMaxFrameSide := MakeUpDown(Owner, 0, 4096);
    Bundle.ChkAutoRefreshViewport := MakeCheckBox(Owner);
    Bundle.EdtExtensions := MakeEdit(Owner);

    Bundle.CbxSaveFormat.ItemIndex := Ord(sfPNG);
    BindSaveFromControls(Settings, Bundle);
    Assert.IsTrue(Settings.SaveFormat = sfPNG, 'ItemIndex must cast to TSaveFormat verbatim');
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

{Cache}

procedure TTestSettingsControlsBundles.Cache_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TCacheControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkCacheEnabled := MakeCheckBox(Owner);
    Bundle.EdtCacheFolder := MakeEdit(Owner);
    Bundle.UdCacheMaxSize := MakeUpDown(Owner, 0, 100000);
    Bundle.ChkRandomExtraction := MakeCheckBox(Owner);
    Bundle.TrkRandomPercent := MakeTrackBar(Owner, 0, 100);
    Bundle.ChkCacheRandomFrames := MakeCheckBox(Owner);

    Settings.CacheEnabled := True;
    Settings.CacheFolder := 'D:\cache';
    Settings.CacheMaxSizeMB := 4096;
    Settings.RandomExtraction := True;
    Settings.RandomPercent := 35;
    Settings.CacheRandomFrames := True;

    BindCacheToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.ChkCacheEnabled.Checked);
    Assert.AreEqual('D:\cache', Bundle.EdtCacheFolder.Text);
    Assert.AreEqual(4096, Bundle.UdCacheMaxSize.Position);
    Assert.IsTrue(Bundle.ChkRandomExtraction.Checked);
    Assert.AreEqual(35, Bundle.TrkRandomPercent.Position);
    Assert.IsTrue(Bundle.ChkCacheRandomFrames.Checked);

    BindCacheFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.CacheEnabled);
    Assert.AreEqual('D:\cache', Reloaded.CacheFolder);
    Assert.AreEqual(4096, Reloaded.CacheMaxSizeMB);
    Assert.IsTrue(Reloaded.RandomExtraction);
    Assert.AreEqual(35, Reloaded.RandomPercent);
    Assert.IsTrue(Reloaded.CacheRandomFrames);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

{FFmpeg}

procedure TTestSettingsControlsBundles.FFmpeg_Roundtrip_UsesSetterOnWrite;
var
  Owner: TForm;
  Bundle: TFFmpegControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.EdtFFmpegPath := MakeEdit(Owner);

    Settings.SetFFmpegPath('C:\bin\ffmpeg.exe');
    BindFFmpegToControls(Settings, Bundle);
    Assert.AreEqual('C:\bin\ffmpeg.exe', Bundle.EdtFFmpegPath.Text);

    Bundle.EdtFFmpegPath.Text := 'D:\new\ffmpeg.exe';
    BindFFmpegFromControls(Reloaded, Bundle);
    {The bundle uses SetFFmpegPath; FFmpegExePath read-back must reflect
     whatever the setter persisted (normally the trimmed text verbatim).}
    Assert.AreEqual('D:\new\ffmpeg.exe', Reloaded.FFmpegExePath);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

{View}

procedure TTestSettingsControlsBundles.View_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TViewControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.PnlBackground := MakePanel(Owner);
    Bundle.ChkShowToolbar := MakeCheckBox(Owner);
    Bundle.ChkShowStatusBar := MakeCheckBox(Owner);
    Bundle.UdCellGap := MakeUpDown(Owner, 0, 100);
    Bundle.UdBorder := MakeUpDown(Owner, 0, 100);
    Bundle.CbxProgressBarLayout := MakeComboBox(Owner, 3);
    Bundle.ChkShowListerMenu := MakeCheckBox(Owner);
    Bundle.ChkListerMenuFlat := MakeCheckBox(Owner);

    Settings.Background := clNavy;
    Settings.ShowToolbar := False;
    Settings.ShowStatusBar := True;
    Settings.CellGap := 9;
    Settings.CombinedBorder := 11;
    Settings.ProgressBarLayout := pblOverPanels;

    BindViewToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.PnlBackground.Color = clNavy);
    Assert.IsFalse(Bundle.ChkShowToolbar.Checked);
    Assert.IsTrue(Bundle.ChkShowStatusBar.Checked);
    Assert.AreEqual(9, Bundle.UdCellGap.Position);
    Assert.AreEqual(11, Bundle.UdBorder.Position);
    Assert.AreEqual(Ord(pblOverPanels), Bundle.CbxProgressBarLayout.ItemIndex);

    BindViewFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.Background = clNavy);
    Assert.IsFalse(Reloaded.ShowToolbar);
    Assert.IsTrue(Reloaded.ShowStatusBar);
    Assert.AreEqual(9, Reloaded.CellGap);
    Assert.AreEqual(11, Reloaded.CombinedBorder);
    Assert.IsTrue(Reloaded.ProgressBarLayout = pblOverPanels);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.View_ProgressBarLayout_EnumRoundTripsViaItemIndex;
var
  Owner: TForm;
  Bundle: TViewControls;
  Settings: TPluginSettings;
  V: TProgressBarLayout;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.PnlBackground := MakePanel(Owner);
    Bundle.ChkShowToolbar := MakeCheckBox(Owner);
    Bundle.ChkShowStatusBar := MakeCheckBox(Owner);
    Bundle.UdCellGap := MakeUpDown(Owner, 0, 100);
    Bundle.UdBorder := MakeUpDown(Owner, 0, 100);
    Bundle.CbxProgressBarLayout := MakeComboBox(Owner, 3);
    Bundle.ChkShowListerMenu := MakeCheckBox(Owner);
    Bundle.ChkListerMenuFlat := MakeCheckBox(Owner);

    for V := Low(TProgressBarLayout) to High(TProgressBarLayout) do
    begin
      Bundle.CbxProgressBarLayout.ItemIndex := Ord(V);
      BindViewFromControls(Settings, Bundle);
      Assert.IsTrue(Settings.ProgressBarLayout = V,
        'Each ProgressBarLayout enum value must round-trip via ItemIndex');
    end;
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

{Timestamp}

procedure TTestSettingsControlsBundles.Timestamp_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TTimestampControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkShowTimecode := MakeCheckBox(Owner);
    Bundle.CbxTimestampCorner := MakeComboBox(Owner, 4);
    Bundle.PnlTCBack := MakePanel(Owner);
    Bundle.UdTCAlpha := MakeUpDown(Owner, 0, 255);
    Bundle.PnlTCTextColor := MakePanel(Owner);
    Bundle.UdTCTextAlpha := MakeUpDown(Owner, 0, 255);

    Settings.ShowTimecode := True;
    Settings.TimestampCorner := tcTopLeft;
    Settings.TimecodeBackColor := clRed;
    Settings.TimecodeBackAlpha := 200;
    Settings.TimestampTextColor := clYellow;
    Settings.TimestampTextAlpha := 180;

    BindTimestampToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.ChkShowTimecode.Checked);
    Assert.IsTrue(Bundle.PnlTCBack.Color = clRed);
    Assert.AreEqual(200, Bundle.UdTCAlpha.Position);
    Assert.IsTrue(Bundle.PnlTCTextColor.Color = clYellow);
    Assert.AreEqual(180, Bundle.UdTCTextAlpha.Position);

    BindTimestampFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.ShowTimecode);
    Assert.IsTrue(Reloaded.TimestampCorner = tcTopLeft, 'Corner round-trip via encode helper');
    Assert.IsTrue(Reloaded.TimecodeBackColor = clRed);
    Assert.AreEqual(200, Integer(Reloaded.TimecodeBackAlpha));
    Assert.IsTrue(Reloaded.TimestampTextColor = clYellow);
    Assert.AreEqual(180, Integer(Reloaded.TimestampTextAlpha));
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Timestamp_DecodeEncode_ShowOff_PreservesCornerOnReencode;
var
  Owner: TForm;
  Bundle: TTimestampControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkShowTimecode := MakeCheckBox(Owner);
    Bundle.CbxTimestampCorner := MakeComboBox(Owner, 4);
    Bundle.PnlTCBack := MakePanel(Owner);
    Bundle.UdTCAlpha := MakeUpDown(Owner, 0, 255);
    Bundle.PnlTCTextColor := MakePanel(Owner);
    Bundle.UdTCTextAlpha := MakeUpDown(Owner, 0, 255);

    {Show=False + Corner=BottomRight. Decode sets Show checkbox off;
     re-encode through the bundle must preserve the Corner.}
    Settings.ShowTimecode := False;
    Settings.TimestampCorner := tcBottomRight;
    BindTimestampToControls(Settings, Bundle);
    Assert.IsFalse(Bundle.ChkShowTimecode.Checked);

    BindTimestampFromControls(Reloaded, Bundle);
    Assert.IsFalse(Reloaded.ShowTimecode);
    Assert.IsTrue(Reloaded.TimestampCorner = tcBottomRight,
      'Show=False must preserve the existing Corner via the decode/encode pair');
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

{Banner}

procedure TTestSettingsControlsBundles.Banner_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TBannerControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkShowBanner := MakeCheckBox(Owner);
    Bundle.PnlBannerBackground := MakePanel(Owner);
    Bundle.PnlBannerTextColor := MakePanel(Owner);
    Bundle.ChkBannerAutoSize := MakeCheckBox(Owner);
    Bundle.CbxBannerPosition := MakeComboBox(Owner, 2);

    Settings.ShowBanner := True;
    Settings.BannerBackground := clBlack;
    Settings.BannerTextColor := clWhite;
    Settings.BannerFontAutoSize := True;
    Settings.BannerPosition := bpBottom;

    BindBannerToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.ChkShowBanner.Checked);
    Assert.IsTrue(Bundle.PnlBannerBackground.Color = clBlack);
    Assert.IsTrue(Bundle.PnlBannerTextColor.Color = clWhite);
    Assert.IsTrue(Bundle.ChkBannerAutoSize.Checked);
    Assert.AreEqual(Ord(bpBottom), Bundle.CbxBannerPosition.ItemIndex);

    BindBannerFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.ShowBanner);
    Assert.IsTrue(Reloaded.BannerBackground = clBlack);
    Assert.IsTrue(Reloaded.BannerTextColor = clWhite);
    Assert.IsTrue(Reloaded.BannerFontAutoSize);
    Assert.IsTrue(Reloaded.BannerPosition = bpBottom);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Banner_Position_EnumRoundTripsViaItemIndex;
var
  Owner: TForm;
  Bundle: TBannerControls;
  Settings: TPluginSettings;
  V: TBannerPosition;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.ChkShowBanner := MakeCheckBox(Owner);
    Bundle.PnlBannerBackground := MakePanel(Owner);
    Bundle.PnlBannerTextColor := MakePanel(Owner);
    Bundle.ChkBannerAutoSize := MakeCheckBox(Owner);
    Bundle.CbxBannerPosition := MakeComboBox(Owner, 2);

    for V := Low(TBannerPosition) to High(TBannerPosition) do
    begin
      Bundle.CbxBannerPosition.ItemIndex := Ord(V);
      BindBannerFromControls(Settings, Bundle);
      Assert.IsTrue(Settings.BannerPosition = V);
    end;
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

{Clipboard formats}

procedure TTestSettingsControlsBundles.ClipboardFormats_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TClipboardFormatsControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkPublishAlphaAwareBitmap := MakeCheckBox(Owner);
    Bundle.ChkPublishCompressedPng := MakeCheckBox(Owner);
    Bundle.ChkPublishFlattenedBitmap := MakeCheckBox(Owner);
    Bundle.ChkPublishBitmapHandle := MakeCheckBox(Owner);

    Settings.PublishAlphaAwareBitmap := True;
    Settings.PublishCompressedPng := False;
    Settings.PublishFlattenedBitmap := True;
    Settings.PublishBitmapHandle := False;

    BindClipboardFormatsToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.ChkPublishAlphaAwareBitmap.Checked);
    Assert.IsFalse(Bundle.ChkPublishCompressedPng.Checked);
    Assert.IsTrue(Bundle.ChkPublishFlattenedBitmap.Checked);
    Assert.IsFalse(Bundle.ChkPublishBitmapHandle.Checked);

    BindClipboardFormatsFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.PublishAlphaAwareBitmap);
    Assert.IsFalse(Reloaded.PublishCompressedPng);
    Assert.IsTrue(Reloaded.PublishFlattenedBitmap);
    Assert.IsFalse(Reloaded.PublishBitmapHandle);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

{Status bar}

procedure TTestSettingsControlsBundles.StatusBar_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TStatusBarControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.EdtStatusBarTemplate := MakeEdit(Owner);
    Bundle.ChkStatusBarAutoWidthLive := MakeCheckBox(Owner);
    Bundle.ChkStatusBarStretchPanels := MakeCheckBox(Owner);
    Bundle.UdStatusBarHeight := MakeUpDown(Owner, 0, 200);
    Bundle.CbxStatusBarHeightApply := MakeComboBox(Owner, 3);

    Settings.StatusBarTemplate := '{file} - {duration}';
    Settings.StatusBarAutoWidthLive := True;
    Settings.StatusBarStretchPanels := False;
    Settings.StatusBarHeight := 28;
    Settings.StatusBarHeightApplyMode := sbhamLister;

    BindStatusBarToControls(Settings, Bundle);
    Assert.AreEqual('{file} - {duration}', Bundle.EdtStatusBarTemplate.Text);
    Assert.IsTrue(Bundle.ChkStatusBarAutoWidthLive.Checked);
    Assert.IsFalse(Bundle.ChkStatusBarStretchPanels.Checked);
    Assert.AreEqual(28, Bundle.UdStatusBarHeight.Position);
    Assert.AreEqual(Ord(sbhamLister), Bundle.CbxStatusBarHeightApply.ItemIndex);

    BindStatusBarFromControls(Reloaded, Bundle);
    Assert.AreEqual('{file} - {duration}', Reloaded.StatusBarTemplate);
    Assert.IsTrue(Reloaded.StatusBarAutoWidthLive);
    Assert.IsFalse(Reloaded.StatusBarStretchPanels);
    Assert.AreEqual(28, Reloaded.StatusBarHeight);
    Assert.IsTrue(Reloaded.StatusBarHeightApplyMode = sbhamLister);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.StatusBar_HeightApplyMode_EnumRoundTripsViaItemIndex;
var
  Owner: TForm;
  Bundle: TStatusBarControls;
  Settings: TPluginSettings;
  V: TStatusBarHeightApplyMode;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.EdtStatusBarTemplate := MakeEdit(Owner);
    Bundle.ChkStatusBarAutoWidthLive := MakeCheckBox(Owner);
    Bundle.ChkStatusBarStretchPanels := MakeCheckBox(Owner);
    Bundle.UdStatusBarHeight := MakeUpDown(Owner, 0, 200);
    Bundle.CbxStatusBarHeightApply := MakeComboBox(Owner, 3);

    for V := Low(TStatusBarHeightApplyMode) to High(TStatusBarHeightApplyMode) do
    begin
      Bundle.CbxStatusBarHeightApply.ItemIndex := Ord(V);
      BindStatusBarFromControls(Settings, Bundle);
      Assert.IsTrue(Settings.StatusBarHeightApplyMode = V);
    end;
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

{Quick view}

procedure TTestSettingsControlsBundles.QuickView_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TQuickViewControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkQVDisableNavigation := MakeCheckBox(Owner);
    Bundle.ChkQVHideToolbar := MakeCheckBox(Owner);
    Bundle.ChkQVHideStatusBar := MakeCheckBox(Owner);

    Settings.QVDisableNavigation := True;
    Settings.QVHideToolbar := False;
    Settings.QVHideStatusBar := True;

    BindQuickViewToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.ChkQVDisableNavigation.Checked);
    Assert.IsFalse(Bundle.ChkQVHideToolbar.Checked);
    Assert.IsTrue(Bundle.ChkQVHideStatusBar.Checked);

    BindQuickViewFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.QVDisableNavigation);
    Assert.IsFalse(Reloaded.QVHideToolbar);
    Assert.IsTrue(Reloaded.QVHideStatusBar);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

{Thumbnails}

procedure TTestSettingsControlsBundles.Thumbnails_Roundtrip_PinsAllFields;
var
  Owner: TForm;
  Bundle: TThumbnailsControls;
  Settings, Reloaded: TPluginSettings;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  Reloaded := TPluginSettings.Create('');
  try
    Bundle.ChkThumbnailsEnabled := MakeCheckBox(Owner);
    Bundle.CbxThumbnailMode := MakeComboBox(Owner, 2);
    Bundle.UdThumbnailPosition := MakeUpDown(Owner, 0, 100);
    Bundle.UdThumbnailGridFrames := MakeUpDown(Owner, 1, 64);

    Settings.ThumbnailsEnabled := True;
    Settings.ThumbnailMode := tnmGrid;
    Settings.ThumbnailPosition := 50;
    Settings.ThumbnailGridFrames := 9;

    BindThumbnailsToControls(Settings, Bundle);
    Assert.IsTrue(Bundle.ChkThumbnailsEnabled.Checked);
    Assert.AreEqual(Ord(tnmGrid), Bundle.CbxThumbnailMode.ItemIndex);
    Assert.AreEqual(50, Bundle.UdThumbnailPosition.Position);
    Assert.AreEqual(9, Bundle.UdThumbnailGridFrames.Position);

    BindThumbnailsFromControls(Reloaded, Bundle);
    Assert.IsTrue(Reloaded.ThumbnailsEnabled);
    Assert.IsTrue(Reloaded.ThumbnailMode = tnmGrid);
    Assert.AreEqual(50, Reloaded.ThumbnailPosition);
    Assert.AreEqual(9, Reloaded.ThumbnailGridFrames);
  finally
    Reloaded.Free;
    Settings.Free;
    Owner.Free;
  end;
end;

procedure TTestSettingsControlsBundles.Thumbnails_Mode_EnumRoundTripsViaItemIndex;
var
  Owner: TForm;
  Bundle: TThumbnailsControls;
  Settings: TPluginSettings;
  V: TThumbnailMode;
begin
  Owner := TForm.CreateNew(nil);
  Settings := TPluginSettings.Create('');
  try
    Bundle.ChkThumbnailsEnabled := MakeCheckBox(Owner);
    Bundle.CbxThumbnailMode := MakeComboBox(Owner, 2);
    Bundle.UdThumbnailPosition := MakeUpDown(Owner, 0, 100);
    Bundle.UdThumbnailGridFrames := MakeUpDown(Owner, 1, 64);

    for V := Low(TThumbnailMode) to High(TThumbnailMode) do
    begin
      Bundle.CbxThumbnailMode.ItemIndex := Ord(V);
      BindThumbnailsFromControls(Settings, Bundle);
      Assert.IsTrue(Settings.ThumbnailMode = V);
    end;
  finally
    Settings.Free;
    Owner.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsControlsBundles);

end.
