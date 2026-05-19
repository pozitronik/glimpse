{Per-group control bundles + bind helpers for the WCX settings dialog.
 Mirrors wlx/uSettingsControlsBundles; lives in wcx/ to keep the shared
 uSettingsGroups unit VCL-free. Names are TWcxXxxControls to prevent
 clashes with the WLX bundle unit.}
unit uWcxSettingsControlsBundles;

interface

uses
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  uWcxSettings;

type
  {MaxWorkers and MaxThreads encode across the auto-checkbox / spin-
   control pair via uSettingsDlgLogic.}
  TWcxExtractionControls = record
    UdFrameCount: TUpDown;
    UdSkipEdges: TUpDown;
    ChkMaxWorkersAuto: TCheckBox;
    UdMaxWorkers: TUpDown;
    UdMaxThreads: TUpDown;
    ChkUseBmpPipe: TCheckBox;
    ChkHwAccel: TCheckBox;
    ChkUseKeyframes: TCheckBox;
    ChkRespectAnamorphic: TCheckBox;
  end;

  TWcxRandomControls = record
    ChkRandomExtraction: TCheckBox;
    TrkRandomPercent: TTrackBar;
  end;

  TWcxFFmpegControls = record
    EdtFFmpegPath: TEdit;
  end;

  TWcxModeControls = record
    ChkModeFrames: TCheckBox;
    ChkModeCombined: TCheckBox;
    ChkModePresets: TCheckBox;
  end;

  TWcxOutputControls = record
    CbxFormat: TComboBox;
    UdJpegQuality: TUpDown;
    UdPngCompression: TUpDown;
    UdBackgroundAlpha: TUpDown;
    ChkShowFileSizes: TCheckBox;
  end;

  TWcxCombinedControls = record
    UdColumns: TUpDown;
    UdCellGap: TUpDown;
    UdBorder: TUpDown;
    PnlBackground: TPanel;
  end;

  TWcxTimestampControls = record
    ChkTimestamp: TCheckBox;
    CbxTimestampCorner: TComboBox;
    PnlTCBack: TPanel;
    UdTCAlpha: TUpDown;
    PnlTCTextColor: TPanel;
    UdTCTextAlpha: TUpDown;
  end;

  TWcxBannerControls = record
    ChkShowBanner: TCheckBox;
    PnlBannerBackground: TPanel;
    PnlBannerTextColor: TPanel;
    ChkBannerAutoSize: TCheckBox;
    CbxBannerPosition: TComboBox;
  end;

  {Both 0 = no limit (uncapped); spin controls clamp at 0.}
  TWcxLimitsControls = record
    UdFrameMax: TUpDown;
    UdCombinedMax: TUpDown;
  end;

procedure BindWcxExtractionToControls(ASettings: TWcxSettings; const AControls: TWcxExtractionControls);
procedure BindWcxRandomToControls(ASettings: TWcxSettings; const AControls: TWcxRandomControls);
procedure BindWcxFFmpegToControls(ASettings: TWcxSettings; const AControls: TWcxFFmpegControls);
procedure BindWcxModeToControls(ASettings: TWcxSettings; const AControls: TWcxModeControls);
procedure BindWcxOutputToControls(ASettings: TWcxSettings; const AControls: TWcxOutputControls);
procedure BindWcxCombinedToControls(ASettings: TWcxSettings; const AControls: TWcxCombinedControls);
procedure BindWcxTimestampToControls(ASettings: TWcxSettings; const AControls: TWcxTimestampControls);
procedure BindWcxBannerToControls(ASettings: TWcxSettings; const AControls: TWcxBannerControls);
procedure BindWcxLimitsToControls(ASettings: TWcxSettings; const AControls: TWcxLimitsControls);

procedure BindWcxExtractionFromControls(ASettings: TWcxSettings; const AControls: TWcxExtractionControls);
procedure BindWcxRandomFromControls(ASettings: TWcxSettings; const AControls: TWcxRandomControls);
procedure BindWcxFFmpegFromControls(ASettings: TWcxSettings; const AControls: TWcxFFmpegControls);
procedure BindWcxModeFromControls(ASettings: TWcxSettings; const AControls: TWcxModeControls);
procedure BindWcxOutputFromControls(ASettings: TWcxSettings; const AControls: TWcxOutputControls);
procedure BindWcxCombinedFromControls(ASettings: TWcxSettings; const AControls: TWcxCombinedControls);
procedure BindWcxTimestampFromControls(ASettings: TWcxSettings; const AControls: TWcxTimestampControls);
procedure BindWcxBannerFromControls(ASettings: TWcxSettings; const AControls: TWcxBannerControls);
procedure BindWcxLimitsFromControls(ASettings: TWcxSettings; const AControls: TWcxLimitsControls);

implementation

uses
  uTypes, uBitmapSaver,
  uSettingsDlgLogic;

{Extraction}

procedure BindWcxExtractionToControls(ASettings: TWcxSettings; const AControls: TWcxExtractionControls);
var
  AutoChecked: Boolean;
  UdPos: Integer;
begin
  AControls.UdFrameCount.Position := ASettings.FramesCount;
  AControls.UdSkipEdges.Position := ASettings.SkipEdgesPercent;
  DecodeMaxWorkersControls(ASettings.MaxWorkers, AutoChecked, UdPos);
  AControls.ChkMaxWorkersAuto.Checked := AutoChecked;
  AControls.UdMaxWorkers.Position := UdPos;
  AControls.UdMaxThreads.Position := DecodeMaxThreadsControl(ASettings.MaxThreads);
  AControls.ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  AControls.ChkHwAccel.Checked := ASettings.HwAccel;
  AControls.ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  AControls.ChkRespectAnamorphic.Checked := ASettings.RespectAnamorphic;
end;

procedure BindWcxExtractionFromControls(ASettings: TWcxSettings; const AControls: TWcxExtractionControls);
begin
  ASettings.FramesCount := AControls.UdFrameCount.Position;
  ASettings.SkipEdgesPercent := AControls.UdSkipEdges.Position;
  ASettings.MaxWorkers := EncodeMaxWorkersControls(AControls.ChkMaxWorkersAuto.Checked, AControls.UdMaxWorkers.Position);
  ASettings.MaxThreads := AControls.UdMaxThreads.Position;
  ASettings.UseBmpPipe := AControls.ChkUseBmpPipe.Checked;
  ASettings.HwAccel := AControls.ChkHwAccel.Checked;
  ASettings.UseKeyframes := AControls.ChkUseKeyframes.Checked;
  ASettings.RespectAnamorphic := AControls.ChkRespectAnamorphic.Checked;
end;

{Random}

procedure BindWcxRandomToControls(ASettings: TWcxSettings; const AControls: TWcxRandomControls);
begin
  AControls.ChkRandomExtraction.Checked := ASettings.RandomExtraction;
  AControls.TrkRandomPercent.Position := ASettings.RandomPercent;
end;

procedure BindWcxRandomFromControls(ASettings: TWcxSettings; const AControls: TWcxRandomControls);
begin
  ASettings.RandomExtraction := AControls.ChkRandomExtraction.Checked;
  ASettings.RandomPercent := AControls.TrkRandomPercent.Position;
end;

{FFmpeg}

procedure BindWcxFFmpegToControls(ASettings: TWcxSettings; const AControls: TWcxFFmpegControls);
begin
  AControls.EdtFFmpegPath.Text := ASettings.FFmpegExePath;
end;

procedure BindWcxFFmpegFromControls(ASettings: TWcxSettings; const AControls: TWcxFFmpegControls);
begin
  ASettings.FFmpegExePath := AControls.EdtFFmpegPath.Text;
end;

{Mode}

procedure BindWcxModeToControls(ASettings: TWcxSettings; const AControls: TWcxModeControls);
begin
  AControls.ChkModeFrames.Checked := ASettings.ShowFrames;
  AControls.ChkModeCombined.Checked := ASettings.ShowCombined;
  AControls.ChkModePresets.Checked := ASettings.ShowPresets;
end;

procedure BindWcxModeFromControls(ASettings: TWcxSettings; const AControls: TWcxModeControls);
begin
  ASettings.ShowFrames := AControls.ChkModeFrames.Checked;
  ASettings.ShowCombined := AControls.ChkModeCombined.Checked;
  ASettings.ShowPresets := AControls.ChkModePresets.Checked;
end;

{Output}

procedure BindWcxOutputToControls(ASettings: TWcxSettings; const AControls: TWcxOutputControls);
begin
  AControls.CbxFormat.ItemIndex := Ord(ASettings.SaveFormat);
  AControls.UdJpegQuality.Position := ASettings.JpegQuality;
  AControls.UdPngCompression.Position := ASettings.PngCompression;
  AControls.UdBackgroundAlpha.Position := ASettings.BackgroundAlpha;
  AControls.ChkShowFileSizes.Checked := ASettings.ShowFileSizes;
end;

procedure BindWcxOutputFromControls(ASettings: TWcxSettings; const AControls: TWcxOutputControls);
begin
  ASettings.SaveFormat := TSaveFormat(AControls.CbxFormat.ItemIndex);
  ASettings.JpegQuality := AControls.UdJpegQuality.Position;
  ASettings.PngCompression := AControls.UdPngCompression.Position;
  {Narrowing from Integer; safe because the control clamps Position to
   [0, 255].}
  ASettings.BackgroundAlpha := Byte(AControls.UdBackgroundAlpha.Position);
  ASettings.ShowFileSizes := AControls.ChkShowFileSizes.Checked;
end;

{Combined}

procedure BindWcxCombinedToControls(ASettings: TWcxSettings; const AControls: TWcxCombinedControls);
begin
  AControls.UdColumns.Position := ASettings.CombinedColumns;
  AControls.UdCellGap.Position := ASettings.CellGap;
  AControls.UdBorder.Position := ASettings.CombinedBorder;
  AControls.PnlBackground.Color := ASettings.Background;
end;

procedure BindWcxCombinedFromControls(ASettings: TWcxSettings; const AControls: TWcxCombinedControls);
begin
  ASettings.CombinedColumns := AControls.UdColumns.Position;
  ASettings.CellGap := AControls.UdCellGap.Position;
  ASettings.CombinedBorder := AControls.UdBorder.Position;
  ASettings.Background := AControls.PnlBackground.Color;
end;

{Timestamp}

procedure BindWcxTimestampToControls(ASettings: TWcxSettings; const AControls: TWcxTimestampControls);
var
  ShowChecked: Boolean;
  ComboIdx: Integer;
begin
  DecodeTimestampCornerControls(ASettings.ShowTimestamp, ASettings.TimestampCorner, ShowChecked, ComboIdx);
  AControls.ChkTimestamp.Checked := ShowChecked;
  AControls.CbxTimestampCorner.ItemIndex := ComboIdx;
  AControls.PnlTCBack.Color := ASettings.TimecodeBackColor;
  AControls.UdTCAlpha.Position := ASettings.TimecodeBackAlpha;
  AControls.PnlTCTextColor.Color := ASettings.TimestampTextColor;
  AControls.UdTCTextAlpha.Position := ASettings.TimestampTextAlpha;
end;

procedure BindWcxTimestampFromControls(ASettings: TWcxSettings; const AControls: TWcxTimestampControls);
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  EncodeTimestampCornerControls(AControls.ChkTimestamp.Checked, AControls.CbxTimestampCorner.ItemIndex, Show, Corner);
  ASettings.ShowTimestamp := Show;
  ASettings.TimestampCorner := Corner;
  ASettings.TimecodeBackColor := AControls.PnlTCBack.Color;
  ASettings.TimecodeBackAlpha := AControls.UdTCAlpha.Position;
  ASettings.TimestampTextColor := AControls.PnlTCTextColor.Color;
  ASettings.TimestampTextAlpha := AControls.UdTCTextAlpha.Position;
end;

{Banner}

procedure BindWcxBannerToControls(ASettings: TWcxSettings; const AControls: TWcxBannerControls);
begin
  AControls.ChkShowBanner.Checked := ASettings.ShowBanner;
  AControls.PnlBannerBackground.Color := ASettings.BannerBackground;
  AControls.PnlBannerTextColor.Color := ASettings.BannerTextColor;
  AControls.ChkBannerAutoSize.Checked := ASettings.BannerFontAutoSize;
  AControls.CbxBannerPosition.ItemIndex := Ord(ASettings.BannerPosition);
end;

procedure BindWcxBannerFromControls(ASettings: TWcxSettings; const AControls: TWcxBannerControls);
begin
  ASettings.ShowBanner := AControls.ChkShowBanner.Checked;
  ASettings.BannerBackground := AControls.PnlBannerBackground.Color;
  ASettings.BannerTextColor := AControls.PnlBannerTextColor.Color;
  ASettings.BannerFontAutoSize := AControls.ChkBannerAutoSize.Checked;
  ASettings.BannerPosition := TBannerPosition(AControls.CbxBannerPosition.ItemIndex);
end;

{Limits}

procedure BindWcxLimitsToControls(ASettings: TWcxSettings; const AControls: TWcxLimitsControls);
begin
  AControls.UdFrameMax.Position := ASettings.FrameMaxSide;
  AControls.UdCombinedMax.Position := ASettings.CombinedMaxSide;
end;

procedure BindWcxLimitsFromControls(ASettings: TWcxSettings; const AControls: TWcxLimitsControls);
begin
  ASettings.FrameMaxSide := AControls.UdFrameMax.Position;
  ASettings.CombinedMaxSide := AControls.UdCombinedMax.Position;
end;

end.
