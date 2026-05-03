{Settings dialog for configuring plugin behavior.
 Works on TPluginSettings directly; changes take effect only when OK is pressed.}
unit uSettingsDlg;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Dialogs,
  Winapi.Windows,
  uTypes, uSettings, uHotkeys;

type
  TSettingsForm = class(TForm)
    PageControl: TPageControl;
    TshGeneral: TTabSheet;
    LblMaxWorkers: TLabel;
    EdtMaxWorkers: TEdit;
    UdMaxWorkers: TUpDown;
    ChkMaxWorkersAuto: TCheckBox;
    LblMaxThreads: TLabel;
    EdtMaxThreads: TEdit;
    UdMaxThreads: TUpDown;
    LblMaxThreadsAuto: TLabel;
    ChkUseBmpPipe: TCheckBox;
    ChkHwAccel: TCheckBox;
    ChkUseKeyframes: TCheckBox;
    ChkRespectAnamorphic: TCheckBox;
    ChkScaledExtraction: TCheckBox;
    LblScaleTarget: TLabel;
    EdtMinFrameSide: TEdit;
    UdMinFrameSide: TUpDown;
    LblScaleSep: TLabel;
    EdtMaxFrameSide: TEdit;
    UdMaxFrameSide: TUpDown;
    LblScaleUnit: TLabel;
    ChkAutoRefreshViewport: TCheckBox;
    LblExtensions: TLabel;
    EdtExtensions: TEdit;
    LblFFmpegPath: TLabel;
    EdtFFmpegPath: TEdit;
    BtnFFmpegPath: TButton;
    LblFFmpegInfo: TLabel;
    TshAppearance: TTabSheet;
    LblBackground: TLabel;
    PnlBackground: TPanel;
    BtnBackground: TButton;
    LblTCBack: TLabel;
    PnlTCBack: TPanel;
    BtnTCBack: TButton;
    LblTCAlpha: TLabel;
    EdtTCAlpha: TEdit;
    UdTCAlpha: TUpDown;
    LblTCTextAlpha: TLabel;
    EdtTCTextAlpha: TEdit;
    UdTCTextAlpha: TUpDown;
    LblTCTextColor: TLabel;
    PnlTCTextColor: TPanel;
    BtnTCTextColor: TButton;
    LblTimestampFont: TLabel;
    EdtTimestampFont: TEdit;
    BtnTimestampFont: TButton;
    LblCellGap: TLabel;
    EdtCellGap: TEdit;
    UdCellGap: TUpDown;
    LblBorder: TLabel;
    EdtBorder: TEdit;
    UdBorder: TUpDown;
    ChkShowTimecode: TCheckBox;
    CbxTimestampCorner: TComboBox;
    ChkShowToolbar: TCheckBox;
    ChkShowStatusBar: TCheckBox;
    TshSave: TTabSheet;
    LblSaveFormat: TLabel;
    CbxSaveFormat: TComboBox;
    LblJpegQuality: TLabel;
    EdtJpegQuality: TEdit;
    UdJpegQuality: TUpDown;
    LblPngCompression: TLabel;
    EdtPngCompression: TEdit;
    UdPngCompression: TUpDown;
    LblBackgroundAlpha: TLabel;
    EdtBackgroundAlpha: TEdit;
    UdBackgroundAlpha: TUpDown;
    LblSaveFolder: TLabel;
    EdtSaveFolder: TEdit;
    BtnSaveFolder: TButton;
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
    ChkSaveAtLiveResolution: TCheckBox;
    TshCache: TTabSheet;
    ChkCacheEnabled: TCheckBox;
    BtnClearCache: TButton;
    LblCacheFolder: TLabel;
    EdtCacheFolder: TEdit;
    BtnCacheFolder: TButton;
    LblCacheFolderInfo: TLabel;
    LblCacheMaxSize: TLabel;
    EdtCacheMaxSize: TEdit;
    UdCacheMaxSize: TUpDown;
    LblCacheMaxSizeUnit: TLabel;
    LblCacheSizeInfo: TLabel;
    TshThumbnails: TTabSheet;
    ChkThumbnailsEnabled: TCheckBox;
    LblThumbnailMode: TLabel;
    CbxThumbnailMode: TComboBox;
    LblThumbnailPosition: TLabel;
    EdtThumbnailPosition: TEdit;
    UdThumbnailPosition: TUpDown;
    LblThumbnailPositionUnit: TLabel;
    LblThumbnailGridFrames: TLabel;
    EdtThumbnailGridFrames: TEdit;
    UdThumbnailGridFrames: TUpDown;
    TshQuickView: TTabSheet;
    ChkQVDisableNavigation: TCheckBox;
    ChkQVHideToolbar: TCheckBox;
    ChkQVHideStatusBar: TCheckBox;
    TshHotkeys: TTabSheet;
    LvwHotkeys: TListView;
    BtnHotkeyClear: TButton;
    BtnHotkeyAssign: TButton;
    BtnHotkeyResetAll: TButton;
    PnlButtons: TPanel;
    BtnDefaults: TButton;
    BtnApply: TButton;
    BtnOK: TButton;
    BtnCancel: TButton;
    ColorDlg: TColorDialog;
    FontDlg: TFontDialog;
    TshSampling: TTabSheet;
    EdtSkipEdges: TEdit;
    LblSkipEdges: TLabel;
    UdSkipEdges: TUpDown;
    LblSkipEdgesUnit: TLabel;
    ChkRandomExtraction: TCheckBox;
    LblRandomPercent: TLabel;
    TrkRandomPercent: TTrackBar;
    ChkCacheRandomFrames: TCheckBox;
    LblRandomPercentValue: TLabel;
    procedure PnlBackgroundClick(Sender: TObject);
    procedure PnlTCBackClick(Sender: TObject);
    procedure PnlTCTextColorClick(Sender: TObject);
    procedure PnlBannerBackgroundClick(Sender: TObject);
    procedure PnlBannerTextColorClick(Sender: TObject);
    procedure ChkShowBannerClick(Sender: TObject);
    procedure ChkBannerAutoSizeClick(Sender: TObject);
    procedure BtnTimestampFontClick(Sender: TObject);
    procedure BtnBannerFontClick(Sender: TObject);
    procedure CbxSaveFormatChange(Sender: TObject);
    procedure BtnSaveFolderClick(Sender: TObject);
    procedure ChkMaxWorkersAutoClick(Sender: TObject);
    procedure ChkCacheEnabledClick(Sender: TObject);
    procedure BtnCacheFolderClick(Sender: TObject);
    procedure BtnFFmpegPathClick(Sender: TObject);
    procedure EdtFFmpegPathChange(Sender: TObject);
    procedure EdtMaxThreadsChange(Sender: TObject);
    procedure ChkScaledExtractionClick(Sender: TObject);
    procedure TrkRandomPercentChange(Sender: TObject);
    procedure EdtCacheFolderChange(Sender: TObject);
    procedure BtnClearCacheClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
    procedure ChkThumbnailsEnabledClick(Sender: TObject);
    procedure CbxThumbnailModeChange(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure LvwHotkeysDblClick(Sender: TObject);
    procedure BtnHotkeyClearClick(Sender: TObject);
    procedure BtnHotkeyAssignClick(Sender: TObject);
    procedure BtnHotkeyResetAllClick(Sender: TObject);
  private
    FOwnerWnd: HWND;
    FResolvedFFmpegPath: string;
    FSettings: TPluginSettings;
    FOnApply: TNotifyEvent;
    FTimestampFontName: string;
    FTimestampFontSize: Integer;
    FBannerFontName: string;
    FBannerFontSize: Integer;
    {Local snapshot of the bindings so the live table isn't mutated unless
     the user confirms with OK/Apply. Mirrors the per-row listview rows.}
    FHotkeys: uHotkeys.THotkeyBindings;
    procedure SettingsToControls(ASettings: TPluginSettings);
    procedure ControlsToSettings(ASettings: TPluginSettings);
    procedure UpdateMaxWorkersControls;
    procedure UpdateSaveFormatControls;
    procedure UpdateBannerControls;
    procedure UpdateCacheControls;
    procedure UpdateScaledExtractionControls;
    procedure UpdateThumbnailControls;
    procedure UpdateFFmpegInfo;
    procedure UpdateCacheFolderInfo;
    procedure UpdateCacheSizeInfo;
    procedure PickColor(APanel: TPanel);
    procedure PickTimestampFont;
    procedure PickBannerFont;
    procedure UpdateTimestampFontDisplay;
    procedure UpdateBannerFontDisplay;
    procedure BrowseFolder(AEdit: TEdit);
    procedure PopulateHotkeyList;
    procedure RefreshHotkeyRow(AAction: uHotkeys.TPluginAction);
    function SelectedHotkeyAction: uHotkeys.TPluginAction;
    procedure CaptureAndAssignHotkey(AAction: uHotkeys.TPluginAction);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor CreateWithOwner(AOwnerWnd: HWND);
    destructor Destroy; override;
  end;

  {Shows the settings dialog.
   AResolvedFFmpegPath is the currently active ffmpeg path (may differ from settings
   when auto-detected). Shown as informational text when the explicit path is empty.
   AOnApply is invoked whenever the user presses the Apply button, after the dialog
   has pushed current control values into ASettings. Pass nil to disable live-apply.
   Returns True if the user pressed OK (ASettings is updated on top of any prior Apply).
   Returns False if dismissed. NOTE: an earlier Apply is not rolled back on Cancel.}
function ShowSettingsDialog(AParentWnd: HWND; ASettings: TPluginSettings; const AResolvedFFmpegPath: string; AOnApply: TNotifyEvent = nil): Boolean;

implementation

{$R *.dfm}

uses
  System.IOUtils, System.Math,
  uDefaults, uFFmpegExe, uCache, uProbeCache, uBitmapSaver, uPathExpand,
  uSettingsDlgLogic, uCaptureShortcutDlg;

procedure TSettingsForm.SettingsToControls(ASettings: TPluginSettings);
var
  AutoChecked, ShowChecked: Boolean;
  UdPos, ComboIdx: Integer;
begin
  UdSkipEdges.Position := ASettings.SkipEdgesPercent;
  DecodeMaxWorkersControls(ASettings.MaxWorkers, AutoChecked, UdPos);
  ChkMaxWorkersAuto.Checked := AutoChecked;
  UdMaxWorkers.Position := UdPos;
  ChkUseBmpPipe.Checked := ASettings.UseBmpPipe;
  ChkHwAccel.Checked := ASettings.HwAccel;
  ChkUseKeyframes.Checked := ASettings.UseKeyframes;
  ChkRespectAnamorphic.Checked := ASettings.RespectAnamorphic;
  UdMaxThreads.Position := DecodeMaxThreadsControl(ASettings.MaxThreads);
  ChkScaledExtraction.Checked := ASettings.ScaledExtraction;
  UdMinFrameSide.Position := ASettings.MinFrameSide;
  UdMaxFrameSide.Position := ASettings.MaxFrameSide;
  ChkAutoRefreshViewport.Checked := ASettings.AutoRefreshOnViewportChange;
  ChkRandomExtraction.Checked := ASettings.RandomExtraction;
  TrkRandomPercent.Position := ASettings.RandomPercent;
  LblRandomPercentValue.Caption := IntToStr(ASettings.RandomPercent) + '%';
  ChkCacheRandomFrames.Checked := ASettings.CacheRandomFrames;
  UpdateMaxWorkersControls;
  UpdateScaledExtractionControls;
  EdtExtensions.Text := ASettings.ExtensionList;
  EdtFFmpegPath.Text := ASettings.FFmpegExePath;

  PnlBackground.Color := ASettings.Background;
  PnlTCBack.Color := ASettings.TimecodeBackColor;
  UdTCAlpha.Position := ASettings.TimecodeBackAlpha;
  UdTCTextAlpha.Position := ASettings.TimestampTextAlpha;
  PnlTCTextColor.Color := ASettings.TimestampTextColor;
  FTimestampFontName := ASettings.TimestampFontName;
  FTimestampFontSize := ASettings.TimestampFontSize;
  UpdateTimestampFontDisplay;
  UdCellGap.Position := ASettings.CellGap;
  UdBorder.Position := ASettings.CombinedBorder;
  DecodeTimestampCornerControls(ASettings.ShowTimecode, ASettings.TimestampCorner,
    ShowChecked, ComboIdx);
  ChkShowTimecode.Checked := ShowChecked;
  CbxTimestampCorner.ItemIndex := ComboIdx;
  ChkShowToolbar.Checked := ASettings.ShowToolbar;
  ChkShowStatusBar.Checked := ASettings.ShowStatusBar;

  CbxSaveFormat.ItemIndex := Ord(ASettings.SaveFormat);
  UdJpegQuality.Position := ASettings.JpegQuality;
  UdPngCompression.Position := ASettings.PngCompression;
  UdBackgroundAlpha.Position := ASettings.BackgroundAlpha;
  EdtSaveFolder.Text := ASettings.SaveFolder;
  ChkShowBanner.Checked := ASettings.ShowBanner;
  PnlBannerBackground.Color := ASettings.BannerBackground;
  PnlBannerTextColor.Color := ASettings.BannerTextColor;
  FBannerFontName := ASettings.BannerFontName;
  FBannerFontSize := ASettings.BannerFontSize;
  ChkBannerAutoSize.Checked := ASettings.BannerFontAutoSize;
  UpdateBannerFontDisplay;
  CbxBannerPosition.ItemIndex := Ord(ASettings.BannerPosition);
  ChkSaveAtLiveResolution.Checked := ASettings.SaveAtLiveResolution;

  ChkCacheEnabled.Checked := ASettings.CacheEnabled;
  EdtCacheFolder.Text := ASettings.CacheFolder;
  UdCacheMaxSize.Position := ASettings.CacheMaxSizeMB;

  ChkQVDisableNavigation.Checked := ASettings.QVDisableNavigation;
  ChkQVHideToolbar.Checked := ASettings.QVHideToolbar;
  ChkQVHideStatusBar.Checked := ASettings.QVHideStatusBar;

  ChkThumbnailsEnabled.Checked := ASettings.ThumbnailsEnabled;
  CbxThumbnailMode.ItemIndex := Ord(ASettings.ThumbnailMode);
  UdThumbnailPosition.Position := ASettings.ThumbnailPosition;
  UdThumbnailGridFrames.Position := ASettings.ThumbnailGridFrames;

  {Snapshot the bindings into our local copy so edits here only commit on
   OK/Apply via ControlsToSettings.}
  FHotkeys.Assign(ASettings.Hotkeys);
  PopulateHotkeyList;

  UpdateSaveFormatControls;
  UpdateBannerControls;
  UpdateCacheControls;
  UpdateThumbnailControls;
  UpdateFFmpegInfo;
  UpdateCacheFolderInfo;
  UpdateCacheSizeInfo;
end;

procedure TSettingsForm.ControlsToSettings(ASettings: TPluginSettings);
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  ASettings.SkipEdgesPercent := UdSkipEdges.Position;
  ASettings.MaxWorkers := EncodeMaxWorkersControls(ChkMaxWorkersAuto.Checked,
    UdMaxWorkers.Position);
  ASettings.UseBmpPipe := ChkUseBmpPipe.Checked;
  ASettings.HwAccel := ChkHwAccel.Checked;
  ASettings.UseKeyframes := ChkUseKeyframes.Checked;
  ASettings.RespectAnamorphic := ChkRespectAnamorphic.Checked;
  ASettings.ScaledExtraction := ChkScaledExtraction.Checked;
  ASettings.MinFrameSide := UdMinFrameSide.Position;
  ASettings.MaxFrameSide := UdMaxFrameSide.Position;
  ASettings.AutoRefreshOnViewportChange := ChkAutoRefreshViewport.Checked;
  ASettings.RandomExtraction := ChkRandomExtraction.Checked;
  ASettings.RandomPercent := TrkRandomPercent.Position;
  ASettings.CacheRandomFrames := ChkCacheRandomFrames.Checked;
  ASettings.MaxThreads := UdMaxThreads.Position;
  ASettings.ExtensionList := EdtExtensions.Text;

  {Switch to explicit mode when user provides a path}
  if EdtFFmpegPath.Text <> '' then
  begin
    ASettings.FFmpegExePath := EdtFFmpegPath.Text;
    ASettings.FFmpegMode := fmExe;
  end else begin
    ASettings.FFmpegExePath := '';
    ASettings.FFmpegMode := fmAuto;
  end;

  ASettings.Background := PnlBackground.Color;
  ASettings.TimecodeBackColor := PnlTCBack.Color;
  ASettings.TimecodeBackAlpha := UdTCAlpha.Position;
  ASettings.TimestampTextAlpha := UdTCTextAlpha.Position;
  ASettings.TimestampTextColor := PnlTCTextColor.Color;
  ASettings.TimestampFontName := FTimestampFontName;
  ASettings.TimestampFontSize := FTimestampFontSize;
  ASettings.CellGap := UdCellGap.Position;
  ASettings.CombinedBorder := UdBorder.Position;
  EncodeTimestampCornerControls(ChkShowTimecode.Checked, CbxTimestampCorner.ItemIndex,
    Show, Corner);
  ASettings.ShowTimecode := Show;
  ASettings.TimestampCorner := Corner;
  ASettings.ShowToolbar := ChkShowToolbar.Checked;
  ASettings.ShowStatusBar := ChkShowStatusBar.Checked;

  ASettings.SaveFormat := TSaveFormat(CbxSaveFormat.ItemIndex);
  ASettings.JpegQuality := UdJpegQuality.Position;
  ASettings.PngCompression := UdPngCompression.Position;
  ASettings.BackgroundAlpha := UdBackgroundAlpha.Position;
  ASettings.SaveFolder := EdtSaveFolder.Text;
  ASettings.ShowBanner := ChkShowBanner.Checked;
  ASettings.BannerBackground := PnlBannerBackground.Color;
  ASettings.BannerTextColor := PnlBannerTextColor.Color;
  ASettings.BannerFontName := FBannerFontName;
  ASettings.BannerFontSize := FBannerFontSize;
  ASettings.BannerFontAutoSize := ChkBannerAutoSize.Checked;
  ASettings.BannerPosition := TBannerPosition(CbxBannerPosition.ItemIndex);
  ASettings.SaveAtLiveResolution := ChkSaveAtLiveResolution.Checked;

  ASettings.CacheEnabled := ChkCacheEnabled.Checked;
  ASettings.CacheFolder := EdtCacheFolder.Text;
  ASettings.CacheMaxSizeMB := UdCacheMaxSize.Position;

  ASettings.QVDisableNavigation := ChkQVDisableNavigation.Checked;
  ASettings.QVHideToolbar := ChkQVHideToolbar.Checked;
  ASettings.QVHideStatusBar := ChkQVHideStatusBar.Checked;

  ASettings.ThumbnailsEnabled := ChkThumbnailsEnabled.Checked;
  ASettings.ThumbnailMode := TThumbnailMode(CbxThumbnailMode.ItemIndex);
  ASettings.ThumbnailPosition := UdThumbnailPosition.Position;
  ASettings.ThumbnailGridFrames := UdThumbnailGridFrames.Position;

  {Hotkeys were edited into our local snapshot; push the whole table back.}
  ASettings.Hotkeys.Assign(FHotkeys);
end;

procedure TSettingsForm.PickColor(APanel: TPanel);
begin
  ColorDlg.Color := APanel.Color;
  if ColorDlg.Execute then
    APanel.Color := ColorDlg.Color;
end;

procedure TSettingsForm.UpdateTimestampFontDisplay;
begin
  EdtTimestampFont.Text := Format('%s, %d pt', [FTimestampFontName, FTimestampFontSize]);
end;

procedure TSettingsForm.UpdateBannerFontDisplay;
begin
  if ChkBannerAutoSize.Checked then
    EdtBannerFont.Text := Format('%s, auto', [FBannerFontName])
  else
    EdtBannerFont.Text := Format('%s, %d pt', [FBannerFontName, FBannerFontSize]);
end;

procedure TSettingsForm.PickTimestampFont;
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

procedure TSettingsForm.PickBannerFont;
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

procedure TSettingsForm.BtnTimestampFontClick(Sender: TObject);
begin
  PickTimestampFont;
end;

procedure TSettingsForm.BtnBannerFontClick(Sender: TObject);
begin
  PickBannerFont;
end;

procedure TSettingsForm.ChkBannerAutoSizeClick(Sender: TObject);
begin
  UpdateBannerFontDisplay;
end;

procedure TSettingsForm.PnlBackgroundClick(Sender: TObject);
begin
  PickColor(PnlBackground);
end;

procedure TSettingsForm.PnlTCBackClick(Sender: TObject);
begin
  PickColor(PnlTCBack);
end;

procedure TSettingsForm.PnlTCTextColorClick(Sender: TObject);
begin
  PickColor(PnlTCTextColor);
end;

procedure TSettingsForm.PnlBannerBackgroundClick(Sender: TObject);
begin
  PickColor(PnlBannerBackground);
end;

procedure TSettingsForm.PnlBannerTextColorClick(Sender: TObject);
begin
  PickColor(PnlBannerTextColor);
end;

procedure TSettingsForm.ChkShowBannerClick(Sender: TObject);
begin
  UpdateBannerControls;
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
      {OnChange fires automatically and updates the info label}
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
  ProbeC: TProbeCache;
begin
  Dir := EffectiveCacheFolder(EdtCacheFolder.Text);

  if MessageBox(Handle, 'Delete all cached frames and probe metadata?',
    'Glimpse', MB_OKCANCEL or MB_ICONQUESTION) <> IDOK then
    Exit;

  if TDirectory.Exists(Dir) then
  begin
    Mgr := CreateCacheManager(Dir, 0);
    Mgr.Clear;
  end;

  {Probe cache lives outside the user-configurable cache folder, in
   %TEMP%\Glimpse\probes. Wiping it alongside the frame cache matches
   user intent (one Cache button = all of Glimpse's on-disk caches).}
  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    ProbeC.Clear;
  finally
    ProbeC.Free;
  end;

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

procedure TSettingsForm.TrkRandomPercentChange(Sender: TObject);
begin
  LblRandomPercentValue.Caption := IntToStr(TrkRandomPercent.Position) + '%';
end;

procedure TSettingsForm.ChkCacheEnabledClick(Sender: TObject);
begin
  UpdateCacheControls;
end;

procedure TSettingsForm.ChkThumbnailsEnabledClick(Sender: TObject);
begin
  UpdateThumbnailControls;
end;

procedure TSettingsForm.CbxThumbnailModeChange(Sender: TObject);
begin
  UpdateThumbnailControls;
end;

procedure TSettingsForm.BtnApplyClick(Sender: TObject);
begin
  {Apply commits current control values to the live settings immediately,
   allowing the host view to act as a preview. The dialog stays open so
   the user can continue adjusting. Cancel afterwards cannot roll back.}
  if FSettings = nil then
    Exit;
  ControlsToSettings(FSettings);
  if Assigned(FOnApply) then
    FOnApply(Self);
end;

{Hotkeys tab}

procedure TSettingsForm.PopulateHotkeyList;
var
  A: uHotkeys.TPluginAction;
  Item: TListItem;
begin
  LvwHotkeys.Items.BeginUpdate;
  try
    LvwHotkeys.Items.Clear;
    for A := Succ(uHotkeys.paNone) to High(uHotkeys.TPluginAction) do
    begin
      Item := LvwHotkeys.Items.Add;
      Item.Caption := uHotkeys.ActionCaption(A);
      {Tag-via-Data the action ordinal so the row survives a sort or
       filter without relying on Items.IndexOf positional mapping.}
      Item.Data := Pointer(NativeInt(Ord(A)));
      Item.SubItems.Add(uHotkeys.ChordsToDisplayStr(FHotkeys.Get(A)));
    end;
  finally
    LvwHotkeys.Items.EndUpdate;
  end;
end;

procedure TSettingsForm.RefreshHotkeyRow(AAction: uHotkeys.TPluginAction);
var
  I: Integer;
  Item: TListItem;
  Display: string;
begin
  Display := uHotkeys.ChordsToDisplayStr(FHotkeys.Get(AAction));
  for I := 0 to LvwHotkeys.Items.Count - 1 do
  begin
    Item := LvwHotkeys.Items[I];
    if uHotkeys.TPluginAction(NativeInt(Item.Data)) = AAction then
    begin
      if Item.SubItems.Count = 0 then
        Item.SubItems.Add(Display)
      else
        Item.SubItems[0] := Display;
      Exit;
    end;
  end;
end;

function TSettingsForm.SelectedHotkeyAction: uHotkeys.TPluginAction;
var
  Item: TListItem;
begin
  Item := LvwHotkeys.Selected;
  if Item = nil then
    Exit(uHotkeys.paNone);
  Result := uHotkeys.TPluginAction(NativeInt(Item.Data));
end;

procedure TSettingsForm.CaptureAndAssignHotkey(AAction: uHotkeys.TPluginAction);
var
  NewChords: uHotkeys.THotkeyChordArray;
  I: Integer;
  Conflict: uHotkeys.TPluginAction;
begin
  if AAction = uHotkeys.paNone then
    Exit;
  if not EditShortcuts(Self, AAction, FHotkeys, NewChords) then
    Exit;

  {The editor prompted for conflicts at the moment each chord was added,
   and the user said "Yes, reassign" for every chord that reached here.
   Reconcile the table now by removing those chords from any other action
   that still owns them. Without this step the old owner would keep the
   binding in memory until the user also opens its row.}
  for I := 0 to High(NewChords) do
  begin
    Conflict := FHotkeys.FindActionByChord(NewChords[I], AAction);
    while Conflict <> uHotkeys.paNone do
    begin
      FHotkeys.RemoveChord(Conflict, NewChords[I]);
      RefreshHotkeyRow(Conflict);
      {A chord could (in pathological INI-edited data) appear more than
       once across different actions; keep stripping until gone.}
      Conflict := FHotkeys.FindActionByChord(NewChords[I], AAction);
    end;
  end;

  FHotkeys.Put(AAction, NewChords);
  RefreshHotkeyRow(AAction);
end;

procedure TSettingsForm.LvwHotkeysDblClick(Sender: TObject);
begin
  CaptureAndAssignHotkey(SelectedHotkeyAction);
end;

procedure TSettingsForm.BtnHotkeyAssignClick(Sender: TObject);
begin
  CaptureAndAssignHotkey(SelectedHotkeyAction);
end;

procedure TSettingsForm.BtnHotkeyClearClick(Sender: TObject);
var
  A: uHotkeys.TPluginAction;
begin
  A := SelectedHotkeyAction;
  if A = uHotkeys.paNone then
    Exit;
  FHotkeys.Put(A, nil);
  RefreshHotkeyRow(A);
end;

procedure TSettingsForm.BtnHotkeyResetAllClick(Sender: TObject);
begin
  if MessageBox(Handle,
    'Reset every hotkey to its default? Unsaved changes in this tab will be lost.',
    'Glimpse', MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  FHotkeys.ResetToDefaults;
  PopulateHotkeyList;
end;

procedure TSettingsForm.UpdateMaxWorkersControls;
var
  OnePerFrame: Boolean;
begin
  OnePerFrame := ChkMaxWorkersAuto.Checked;
  LblMaxWorkers.Enabled := not OnePerFrame;
  EdtMaxWorkers.Enabled := not OnePerFrame;
  UdMaxWorkers.Enabled := not OnePerFrame;
  {Limit workers count is only relevant in one-per-frame mode}
  LblMaxThreads.Enabled := OnePerFrame;
  EdtMaxThreads.Enabled := OnePerFrame;
  UdMaxThreads.Enabled := OnePerFrame;
  LblMaxThreadsAuto.Caption := MaxThreadsAutoLabel(OnePerFrame, UdMaxThreads.Position, CPUCount);
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
  LblBackgroundAlpha.Enabled := IsPNG;
  EdtBackgroundAlpha.Enabled := IsPNG;
  UdBackgroundAlpha.Enabled := IsPNG;
end;

procedure TSettingsForm.UpdateBannerControls;
var
  Enabled: Boolean;
begin
  {Banner style is only meaningful when the banner is actually drawn}
  Enabled := ChkShowBanner.Checked;
  LblBannerBackground.Enabled := Enabled;
  PnlBannerBackground.Enabled := Enabled;
  BtnBannerBackground.Enabled := Enabled;
  LblBannerTextColor.Enabled := Enabled;
  PnlBannerTextColor.Enabled := Enabled;
  BtnBannerTextColor.Enabled := Enabled;
  LblBannerFont.Enabled := Enabled;
  EdtBannerFont.Enabled := Enabled;
  BtnBannerFont.Enabled := Enabled;
  ChkBannerAutoSize.Enabled := Enabled;
  LblBannerPosition.Enabled := Enabled;
  CbxBannerPosition.Enabled := Enabled;
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
  LblScaleTarget.Enabled := Enabled;
  EdtMinFrameSide.Enabled := Enabled;
  UdMinFrameSide.Enabled := Enabled;
  LblScaleSep.Enabled := Enabled;
  EdtMaxFrameSide.Enabled := Enabled;
  UdMaxFrameSide.Enabled := Enabled;
  LblScaleUnit.Enabled := Enabled;
  {Auto-refresh has no effect when scaling is off (no MaxSide to compare).}
  ChkAutoRefreshViewport.Enabled := Enabled;
end;

procedure TSettingsForm.UpdateThumbnailControls;
var
  GroupOn, IsSingle, IsGrid: Boolean;
begin
  GroupOn := ChkThumbnailsEnabled.Checked;
  LblThumbnailMode.Enabled := GroupOn;
  CbxThumbnailMode.Enabled := GroupOn;

  {Position controls only meaningful in Single mode; grid frames only in
   Grid mode. Disabling avoids the user editing fields that won't be used.}
  IsSingle := GroupOn and (CbxThumbnailMode.ItemIndex = Ord(tnmSingle));
  IsGrid := GroupOn and (CbxThumbnailMode.ItemIndex = Ord(tnmGrid));

  LblThumbnailPosition.Enabled := IsSingle;
  EdtThumbnailPosition.Enabled := IsSingle;
  UdThumbnailPosition.Enabled := IsSingle;
  LblThumbnailPositionUnit.Enabled := IsSingle;

  LblThumbnailGridFrames.Enabled := IsGrid;
  EdtThumbnailGridFrames.Enabled := IsGrid;
  UdThumbnailGridFrames.Enabled := IsGrid;
end;

procedure TSettingsForm.UpdateFFmpegInfo;
var
  Input, Path, Ver: string;
  State: TFFmpegProbeState;
begin
  Input := EdtFFmpegPath.Text;
  if Input <> '' then
    Path := ExpandEnvVars(Input)
  else
    Path := FResolvedFFmpegPath;

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
  ProbeC: TProbeCache;
  Total: Int64;
begin
  Total := 0;

  Dir := EffectiveCacheFolder(EdtCacheFolder.Text);
  if TDirectory.Exists(Dir) then
  begin
    Mgr := CreateCacheManager(Dir, 0);
    Total := Total + Mgr.GetTotalSize;
  end;

  {Probe cache lives in a separate fixed directory; fold it into the total
   so the readout reflects every byte the plugin keeps on disk.}
  ProbeC := TProbeCache.Create(DefaultProbeCacheDir);
  try
    Total := Total + ProbeC.GetTotalSize;
  finally
    ProbeC.Free;
  end;

  if Total > 0 then
    LblCacheSizeInfo.Caption := Format('(current: %.1f MB)', [Total / (1024 * 1024)])
  else
    LblCacheSizeInfo.Caption := '(current: empty)';
end;

constructor TSettingsForm.CreateWithOwner(AOwnerWnd: HWND);
begin
  {Must be set before inherited: DFM loading may force handle creation,
   and CreateParams needs the value at that point}
  FOwnerWnd := AOwnerWnd;
  inherited Create(nil);
  FHotkeys := uHotkeys.THotkeyBindings.Create;
end;

destructor TSettingsForm.Destroy;
begin
  FHotkeys.Free;
  inherited;
end;

procedure TSettingsForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  if FOwnerWnd <> 0 then
    Params.WndParent := FOwnerWnd;
end;

function ShowSettingsDialog(AParentWnd: HWND; ASettings: TPluginSettings; const AResolvedFFmpegPath: string; AOnApply: TNotifyEvent): Boolean;
var
  Form: TSettingsForm;
begin
  Result := False;
  Form := TSettingsForm.CreateWithOwner(AParentWnd);
  try
    Form.FResolvedFFmpegPath := AResolvedFFmpegPath;
    Form.FSettings := ASettings;
    Form.FOnApply := AOnApply;
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
