{Owns the status-bar rendering pipeline: the cached values snapshot,
 the TStatusBarRenderer instance, the token/hint/kind resolver
 callbacks, the per-refresh build flow, and the bar's dbl-click /
 ctrl-click handlers.

 Stable collaborators (Settings, FrameView, Exporter, LoadTimer,
 FileNavigator, the StatusBar widget, the ProgressIndicator) come in
 via the constructor. Mutable host state (file name, frame offsets,
 video info, quick-view flag) is read on every Refresh through
 IStatusBarDataSource so the presenter sees the host's current values
 without coupling to its concrete type.}
unit StatusBarPresenter;

interface

uses
  System.Classes, System.UITypes,
  Vcl.Controls, Vcl.ComCtrls,
  Settings, FrameView, FrameExport, LoadTimeRecorder, FileNavigator,
  ProgressIndicator,
  StatusBarHostBar, StatusBarRenderer, StatusBarTokens, StatusBarTemplate, StatusBarFormatters,
  FrameOffsets, VideoInfo;

type
  {The slice of host state the presenter reads on each refresh. The
   host (typically TPluginForm) implements it. Refresh-time-read getters
   matter for collaborators that may still be nil while the host's
   init order is mid-flight; on a complex form (CreateStatusBar runs
   before CreateFrameView / InitializeExtractionStack / InitializeServices)
   the presenter would otherwise capture nil at construction and crash
   later. Reading through the interface keeps the presenter robust to
   any host init order.}
  IStatusBarDataSource = interface
    ['{4D8C2F31-7B5E-4A92-91D0-3E6F8B0C2D4A}']
    function GetCurrentFileName: string;
    function GetCurrentOffsets: TFrameOffsetArray;
    function GetCurrentVideoInfo: TVideoInfo;
    function IsQuickViewMode: Boolean;
    function GetFrameView: TFrameView;
    function GetExporter: TFrameExporter;
    function GetLoadTimer: TLoadTimeRecorder;
  end;

  TStatusBarPresenter = class
  strict private
    FStatusBar: TGlimpseStatusBar;
    FProgressIndicator: TProgressIndicator;
    FSettings: TPluginSettings;
    FFileNavigator: IFileNavigator;
    FDataSource: IStatusBarDataSource;
    FRenderer: TStatusBarRenderer;
    FCachedValues: TStatusBarValues;
    function ResolveToken(const AToken: TStatusBarToken): string;
    function GetPanelHint(APanelIndex: Integer): string;
    function GetPanelKind(APanelIndex: Integer): TStatusBarTokenKind;
    procedure BuildValues(out AValues: TStatusBarValues);
    procedure BuildFileSourceFields(var AValues: TStatusBarValues);
    procedure BuildFrameViewFields(var AValues: TStatusBarValues);
    procedure BuildVideoInfoFields(var AValues: TStatusBarValues);
    procedure BuildExporterPredictionFields(var AValues: TStatusBarValues);
    function ResolveHeight(ATextHeight: Integer): Integer;
  public
    {ARendererOwner is the TComponent that owns the renderer for VCL
     cleanup; passing the host form here keeps the existing
     "inherited Destroy frees the renderer" lifecycle. AStatusBar,
     AProgressIndicator, ASettings, AFileNavigator and ADataSource are
     all borrowed. FrameView, Exporter and LoadTimer are read on
     demand through ADataSource so the presenter is robust to host
     init order — they may still be nil when the presenter is
     constructed and the data source's getters will return them once
     the host has wired them up.}
    constructor Create(ARendererOwner: TComponent;
      AStatusBar: TGlimpseStatusBar;
      AProgressIndicator: TProgressIndicator;
      ASettings: TPluginSettings;
      const AFileNavigator: IFileNavigator;
      const ADataSource: IStatusBarDataSource);
    {Rebuilds the cached snapshot and tells the renderer to repaint.
     Idempotent. No-op when the renderer is nil — defensive for
     pre-CreateStatusBar lifecycle paths.}
    procedure Refresh;
    {Pushes the four status-bar settings (template, font name + size,
     auto-width-live flag, stretch-panels) into the renderer, then
     resizes the bar from the configured font height.}
    procedure ApplySettings;
    {Wired to FStatusBar.OnDblClick — flips SaveAtLiveResolution /
     CopyAtLiveResolution when the cursor is over the corresponding
     panel, persists, and refreshes so the visible text changes
     immediately.}
    procedure HandleStatusBarDblClick(Sender: TObject);
    {Wired to FStatusBar.OnMouseUp — copies the panel text under the
     cursor when Ctrl+left-click; falls through silently otherwise.}
    procedure HandleStatusBarMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Graphics, Vcl.Clipbrd,
  Types, ViewModeLogic,
  StatusBarLayout, PlatformDetect;

constructor TStatusBarPresenter.Create(ARendererOwner: TComponent;
  AStatusBar: TGlimpseStatusBar;
  AProgressIndicator: TProgressIndicator;
  ASettings: TPluginSettings;
  const AFileNavigator: IFileNavigator;
  const ADataSource: IStatusBarDataSource);
begin
  inherited Create;
  FStatusBar := AStatusBar;
  FProgressIndicator := AProgressIndicator;
  FSettings := ASettings;
  FFileNavigator := AFileNavigator;
  FDataSource := ADataSource;
  {Renderer takes the host as its TComponent owner so the host's
   inherited Destroy releases it; no explicit Free in this class.}
  FRenderer := TStatusBarRenderer.Create(ARendererOwner, FStatusBar, ResolveToken);
  FStatusBar.OnGetPanelHint := GetPanelHint;
  FStatusBar.OnQueryPanelKind := GetPanelKind;
end;

function TStatusBarPresenter.ResolveToken(const AToken: TStatusBarToken): string;
begin
  {Resolve the platform-specific glyph once per token; the formatter
   used to call PlatformDetect itself, but lifting the dependency to
   the call site keeps StatusBarFormatters truly pure.}
  Result := FormatStatusBarToken(AToken, FCachedValues, ResolutionTransformGlyph);
end;

function TStatusBarPresenter.GetPanelHint(APanelIndex: Integer): string;
begin
  Result := FRenderer.HintForPanel(APanelIndex);
end;

function TStatusBarPresenter.GetPanelKind(APanelIndex: Integer): TStatusBarTokenKind;
begin
  Result := FRenderer.KindForPanel(APanelIndex);
end;

procedure TStatusBarPresenter.ApplySettings;
var
  Bmp: Vcl.Graphics.TBitmap;
  TextH: Integer;
begin
  if FRenderer = nil then
    Exit;
  FRenderer.SetFont(FSettings.StatusBarFontName, FSettings.StatusBarFontSize);
  FRenderer.SetAutoWidthLive(FSettings.StatusBarAutoWidthLive);
  FRenderer.SetStretchPanels(FSettings.StatusBarStretchPanels);
  FRenderer.ApplyTemplate(FSettings.StatusBarTemplate);

  {Resize the bar. Auto path uses font-derived height (TextHeight + a
   small padding), explicit path scales the user's logical pixel value
   to the bar's CurrentPPI and silently bumps up to the font minimum
   so text never clips. Apply-mode gate honours the lister/quickview
   selection.}
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(FStatusBar.Font);
    {'Hg' is the standard ascender + descender pair used to measure a
     font's true vertical reach (matches GDI's GetTextMetrics output).}
    TextH := Bmp.Canvas.TextHeight('Hg');
  finally
    Bmp.Free;
  end;
  FStatusBar.Height := ResolveHeight(TextH);
  FProgressIndicator.Reposition;
end;

function TStatusBarPresenter.ResolveHeight(ATextHeight: Integer): Integer;
begin
  {FStatusBar.CurrentPPI returns 0 in some pre-paint states; the pure
   helper normalises that to 96.}
  Result := ResolveStatusBarHeightPixels(ATextHeight,
    FSettings.StatusBarHeight,
    FSettings.StatusBarHeightApplyMode,
    FDataSource.IsQuickViewMode,
    FStatusBar.CurrentPPI);
end;

procedure TStatusBarPresenter.BuildFileSourceFields(var AValues: TStatusBarValues);
begin
  AValues.Filename := FDataSource.GetCurrentFileName;
  AValues.FilePositionAvailable := FFileNavigator.GetFilePosition(AValues.Filename,
    FSettings.ExtensionList, AValues.FilePositionIndex, AValues.FilePositionTotal);
end;

procedure TStatusBarPresenter.BuildFrameViewFields(var AValues: TStatusBarValues);
var
  Offsets: TFrameOffsetArray;
  FrameView: TFrameView;
begin
  Offsets := FDataSource.GetCurrentOffsets;
  AValues.FramesAvailable := Length(Offsets) > 0;
  AValues.FramesTotal := Length(Offsets);
  FrameView := FDataSource.GetFrameView;
  if FrameView = nil then
    Exit;
  AValues.CurrentFrameIndex := FrameView.CurrentFrameIndex;
  AValues.IsSingleViewMode := FrameView.ViewMode = vmSingle;
  AValues.ViewModeName := ViewModeDisplayName(FrameView.ViewMode);
  AValues.ZoomModeName := ZoomModeDisplayName(FrameView.ZoomMode);
end;

procedure TStatusBarPresenter.BuildVideoInfoFields(var AValues: TStatusBarValues);
var
  Info: TVideoInfo;
begin
  Info := FDataSource.GetCurrentVideoInfo;
  AValues.SourceWidth := Info.Width;
  AValues.SourceHeight := Info.Height;
  AValues.SourceFps := Info.Fps;
  AValues.SourceDurationSec := Info.Duration;
  AValues.SourceBitrateKbps := Info.Bitrate;
  AValues.SourceVideoCodec := Info.VideoCodec;

  AValues.SourceAudioCodec := Info.AudioCodec;
  AValues.SourceAudioSampleRate := Info.AudioSampleRate;
  AValues.SourceAudioChannels := Info.AudioChannels;
  AValues.SourceAudioBitrateKbps := Info.AudioBitrateKbps;
end;

procedure TStatusBarPresenter.BuildExporterPredictionFields(var AValues: TStatusBarValues);
var
  PredW, PredH, PredCappedW, PredCappedH: Integer;
  Exporter: TFrameExporter;
begin
  Exporter := FDataSource.GetExporter;
  if Exporter = nil then
    Exit;
  AValues.SaveDimAvailable := Exporter.PredictDisplayedSize(
    FSettings.SaveAtLiveResolution, PredW, PredH, PredCappedW, PredCappedH);
  if AValues.SaveDimAvailable then
  begin
    AValues.SaveDimW := PredW;
    AValues.SaveDimH := PredH;
    AValues.SaveDimCappedW := PredCappedW;
    AValues.SaveDimCappedH := PredCappedH;
  end;
  AValues.CopyDimAvailable := Exporter.PredictDisplayedSize(
    FSettings.CopyAtLiveResolution, PredW, PredH, PredCappedW, PredCappedH);
  if AValues.CopyDimAvailable then
  begin
    AValues.CopyDimW := PredW;
    AValues.CopyDimH := PredH;
    AValues.CopyDimCappedW := PredCappedW;
    AValues.CopyDimCappedH := PredCappedH;
  end;
end;

procedure TStatusBarPresenter.BuildValues(out AValues: TStatusBarValues);
var
  LoadTimer: TLoadTimeRecorder;
begin
  AValues := Default(TStatusBarValues);
  {Pre-template behaviour: the bar showed nothing until video info was
   probed. Preserved here so panels stay hidden until extraction starts
   filling them in.}
  if not FDataSource.GetCurrentVideoInfo.IsValid then
    Exit;
  AValues.VideoInfoValid := True;

  BuildFileSourceFields(AValues);
  BuildFrameViewFields(AValues);
  BuildVideoInfoFields(AValues);
  BuildExporterPredictionFields(AValues);
  LoadTimer := FDataSource.GetLoadTimer;
  if LoadTimer <> nil then
    AValues.LoadTimeText := LoadTimer.Formatted;
end;

procedure TStatusBarPresenter.Refresh;
var
  Last: Integer;
  Dummy: TStatusPanel;
begin
  if FRenderer = nil then
    Exit;
  BuildValues(FCachedValues);
  FRenderer.Refresh;
  {Append a 0-width dummy panel only when the last visible panel has
   non-default alignment. Without it the common control lets the last
   panel stretch to fill remaining width, defeating the right- or
   center-justify the user asked for.}
  Last := FStatusBar.Panels.Count - 1;
  if (Last >= 0) and (FStatusBar.Panels[Last].Alignment <> taLeftJustify) then
  begin
    Dummy := FStatusBar.Panels.Add;
    Dummy.Width := 0;
    Dummy.Text := '';
  end;
end;

procedure TStatusBarPresenter.HandleStatusBarDblClick(Sender: TObject);
var
  Pt: TPoint;
  HitIdx, PanelLeft: Integer;
  Kind: TStatusBarTokenKind;
begin
  if (FStatusBar.Panels.Count = 0) or (FRenderer = nil) then
    Exit;
  Pt := FStatusBar.ScreenToClient(Mouse.CursorPos);
  HitIdx := StatusBarPanelHitTest(FStatusBar, Pt.X, PanelLeft);
  if HitIdx < 0 then
    Exit;
  Kind := FRenderer.KindForPanel(HitIdx);
  case Kind of
    tkSaveDimension:
      FSettings.SaveAtLiveResolution := not FSettings.SaveAtLiveResolution;
    tkCopyDimension:
      FSettings.CopyAtLiveResolution := not FSettings.CopyAtLiveResolution;
  else
    Exit;
  end;
  {Persist so a TC restart preserves the flip — same contract the
   settings dialog has. Refresh recomputes the predicted-size panels
   against the new toggle so the visible text changes on the next
   paint, giving the user immediate feedback.}
  FSettings.Save;
  Refresh;
end;

procedure TStatusBarPresenter.HandleStatusBarMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  HitIdx, PanelLeft: Integer;
begin
  {Only Ctrl+left-click copies. Other modifier combinations and right /
   middle clicks fall through to default (no-op for status bar).}
  if (Button <> mbLeft) or (Shift * [ssCtrl, ssShift, ssAlt] <> [ssCtrl]) then
    Exit;
  if FStatusBar.Panels.Count = 0 then
    Exit;
  HitIdx := StatusBarPanelHitTest(FStatusBar, X, PanelLeft);
  {Click past last panel: copy last panel.}
  if HitIdx < 0 then
    HitIdx := FStatusBar.Panels.Count - 1;
  Clipboard.AsText := FStatusBar.Panels[HitIdx].Text;
end;

end.
