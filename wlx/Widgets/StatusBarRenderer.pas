{Bridges the parsed token list (StatusBarTemplate) and the live VCL
 status bar. The per-token text comes through a resolver callback so
 the renderer holds no plugin state.

 Missing-data contract:
   - resolver = '' AND auto width: panel is skipped (bar collapses).
   - resolver = '' AND explicit width: panel keeps width and shows '?'.}
unit StatusBarRenderer;

interface

uses
  System.Classes, Vcl.ComCtrls,
  StatusBarTokens, StatusBarTemplate, TextMeasurement;

type
  {Empty result is the "data unavailable" signal; the renderer handles
   skip-vs-placeholder per the missing-data contract.}
  TStatusBarTokenTextResolver = reference to function(
    const AToken: TStatusBarToken): string;

  {TComponent-based so the host form can pass Self as owner — destruction
   then runs during the form's inherited Destroy, while the form's fields
   are still memory-valid (the resolver closure captures Self).}
  TStatusBarRenderer = class(TComponent)
  private
    FStatusBar: TStatusBar;
    FResolver: TStatusBarTokenTextResolver;
    FMeasurer: ITextMeasurer;
    FTokens: TStatusBarTokenArray;
    {Parallel to FTokens (not panels) — tokens may resolve to no panel.}
    FAutoWidths: TArray<Integer>;
    {Parallel to the LIVE FStatusBar.Panels (post-skip).}
    FPanelHints: TArray<string>;
    FPanelKinds: TArray<TStatusBarTokenKind>;
    {Only auto-width panels receive stretch slack — fixed widths are user-precise.}
    FPanelIsAuto: TArray<Boolean>;
    {Pre-stretch natural width (Panel.Width is mutated by RedistributeSlack).}
    FPanelBaseWidth: TArray<Integer>;
    FAutoWidthLive: Boolean;
    FStretchPanels: Boolean;
    FFontName: string;
    FFontSize: Integer;
    procedure RemeasureAutoWidths;
    procedure RedistributeSlack;
    function MeasureText(const AText: string): Integer;
    function ScaledExplicitWidth(ALogicalWidth: Integer): Integer;
    function MapAlignment(A: TStatusBarTokenAlign): TAlignment;
  public
    {AOwner nil = caller-owned (tests). 3-arg overload wires
     TBitmapTextMeasurer; tests use the 4-arg overload to inject a stub.}
    constructor Create(AOwner: TComponent; AStatusBar: TStatusBar;
      AResolver: TStatusBarTokenTextResolver); reintroduce; overload;
    constructor Create(AOwner: TComponent; AStatusBar: TStatusBar;
      AResolver: TStatusBarTokenTextResolver;
      AMeasurer: ITextMeasurer); reintroduce; overload;
    procedure ApplyTemplate(const ATemplate: string);
    procedure Refresh;
    function HintForPanel(AIndex: Integer): string;
    function KindForPanel(AIndex: Integer): TStatusBarTokenKind;
    procedure SetFont(const AFontName: string; AFontSize: Integer);
    {True = measure live text on every Refresh (panel widths track content).
     False (default) = measure once from the token's sample text, then lock.}
    procedure SetAutoWidthLive(AValue: Boolean);
    {Stretch baseline is the sample-text width (NOT the live text) so the
     layout stays stable when AutoWidthLive is also on.}
    procedure SetStretchPanels(AValue: Boolean);
    property AutoWidthLive: Boolean read FAutoWidthLive;
    property StretchPanels: Boolean read FStretchPanels;
  end;

const
  STATUSBAR_MISSING_PLACEHOLDER = '?';
  {Empirical inset matching the common-control draw — without it Tahoma's
   last character clips against the panel border.}
  STATUSBAR_AUTO_WIDTH_PADDING = 8;

implementation

uses
  System.SysUtils, Winapi.Windows, Vcl.Graphics;

constructor TStatusBarRenderer.Create(AOwner: TComponent; AStatusBar: TStatusBar;
  AResolver: TStatusBarTokenTextResolver);
begin
  Create(AOwner, AStatusBar, AResolver, TBitmapTextMeasurer.Create);
end;

constructor TStatusBarRenderer.Create(AOwner: TComponent; AStatusBar: TStatusBar;
  AResolver: TStatusBarTokenTextResolver; AMeasurer: ITextMeasurer);
begin
  inherited Create(AOwner);
  {Hard runtime check, not Assert — Assert compiles to nothing in release builds.}
  if AStatusBar = nil then
    raise EArgumentNilException.Create('TStatusBarRenderer requires a TStatusBar instance');
  if not Assigned(AResolver) then
    raise EArgumentNilException.Create('TStatusBarRenderer requires a non-nil resolver');
  if AMeasurer = nil then
    raise EArgumentNilException.Create('TStatusBarRenderer requires a non-nil text measurer');
  FStatusBar := AStatusBar;
  FResolver := AResolver;
  FMeasurer := AMeasurer;
  FAutoWidthLive := False;
  FFontName := AStatusBar.Font.Name;
  FFontSize := AStatusBar.Font.Size;
end;

procedure TStatusBarRenderer.SetFont(const AFontName: string; AFontSize: Integer);
begin
  FFontName := AFontName;
  FFontSize := AFontSize;
  FStatusBar.Font.Name := AFontName;
  FStatusBar.Font.Size := AFontSize;
  RemeasureAutoWidths;
  Refresh;
end;

procedure TStatusBarRenderer.SetAutoWidthLive(AValue: Boolean);
begin
  if FAutoWidthLive = AValue then
    Exit;
  FAutoWidthLive := AValue;
  Refresh;
end;

procedure TStatusBarRenderer.SetStretchPanels(AValue: Boolean);
begin
  if FStretchPanels = AValue then
    Exit;
  FStretchPanels := AValue;
  Refresh;
end;

procedure TStatusBarRenderer.ApplyTemplate(const ATemplate: string);
begin
  FTokens := ParseStatusBarTemplate(ATemplate);
  RemeasureAutoWidths;
  Refresh;
end;

procedure TStatusBarRenderer.RemeasureAutoWidths;
var
  I: Integer;
  Sample: string;
begin
  SetLength(FAutoWidths, Length(FTokens));
  for I := 0 to High(FTokens) do
  begin
    if FTokens[I].Kind = tkUnknown then
      {Unknown tokens paint their RawText directly (sample is empty).}
      Sample := FTokens[I].RawText
    else
      Sample := StatusBarTokenSampleText(FTokens[I].Kind);
    FAutoWidths[I] := MeasureText(Sample);
  end;
end;

function TStatusBarRenderer.MeasureText(const AText: string): Integer;
var
  Ppi: Integer;
begin
  if AText = '' then
    Exit(0);
  {Padding is a status-bar policy, not a text-width primitive — applied here.}
  Ppi := FStatusBar.CurrentPPI;
  if Ppi <= 0 then
    Ppi := 96;
  Result := FMeasurer.MeasureWidth(AText, FFontName, FFontSize, Ppi)
    + MulDiv(STATUSBAR_AUTO_WIDTH_PADDING, Ppi, 96);
end;

function TStatusBarRenderer.ScaledExplicitWidth(ALogicalWidth: Integer): Integer;
var
  Ppi: Integer;
begin
  {User-typed "width=N" is a 96-DPI logical pixel count; convert here.}
  Ppi := FStatusBar.CurrentPPI;
  if Ppi <= 0 then
    Ppi := 96;
  Result := MulDiv(ALogicalWidth, Ppi, 96);
end;

function TStatusBarRenderer.MapAlignment(A: TStatusBarTokenAlign): TAlignment;
begin
  case A of
    sbaRight:  Result := taRightJustify;
    sbaCenter: Result := taCenter;
  else
    Result := taLeftJustify;
  end;
end;

procedure TStatusBarRenderer.Refresh;
var
  I, ExplicitWidth, EffectiveWidth: Integer;
  HasExplicitWidth: Boolean;
  Tok: TStatusBarToken;
  Text: string;
  Panel: TStatusPanel;
begin
  FStatusBar.Panels.BeginUpdate;
  try
    FStatusBar.Panels.Clear;
    SetLength(FPanelHints, 0);
    SetLength(FPanelKinds, 0);
    SetLength(FPanelIsAuto, 0);
    SetLength(FPanelBaseWidth, 0);
    for I := 0 to High(FTokens) do
    begin
      Tok := FTokens[I];
      Text := FResolver(Tok);
      HasExplicitWidth := Tok.TryGetWidth(ExplicitWidth);

      if Text = '' then
      begin
        if not HasExplicitWidth then
          {Skip-on-auto-empty: missing datum collapses out.}
          Continue;
        Text := STATUSBAR_MISSING_PLACEHOLDER;
      end;

      if HasExplicitWidth then
        EffectiveWidth := ScaledExplicitWidth(ExplicitWidth)
      else if FStretchPanels then
        {Stable baseline so the proportional distribution does not jitter
         on live-text changes.}
        EffectiveWidth := FAutoWidths[I]
      else if FAutoWidthLive then
        EffectiveWidth := MeasureText(Text)
      else
        EffectiveWidth := FAutoWidths[I];

      Panel := FStatusBar.Panels.Add;
      Panel.Text := Text;
      Panel.Width := EffectiveWidth;
      Panel.Alignment := MapAlignment(Tok.GetAlignment);

      SetLength(FPanelHints, Length(FPanelHints) + 1);
      FPanelHints[High(FPanelHints)] := StatusBarTokenHint(Tok.Kind);
      SetLength(FPanelKinds, Length(FPanelKinds) + 1);
      FPanelKinds[High(FPanelKinds)] := Tok.Kind;
      SetLength(FPanelIsAuto, Length(FPanelIsAuto) + 1);
      FPanelIsAuto[High(FPanelIsAuto)] := not HasExplicitWidth;
      SetLength(FPanelBaseWidth, Length(FPanelBaseWidth) + 1);
      FPanelBaseWidth[High(FPanelBaseWidth)] := EffectiveWidth;
    end;
    if FStretchPanels then
      RedistributeSlack;
  finally
    FStatusBar.Panels.EndUpdate;
  end;
end;

procedure TStatusBarRenderer.RedistributeSlack;
var
  I, TotalCur, AutoBaseSum, Slack, Bonus, Distributed, LastAuto: Integer;
begin
  if FStatusBar.Panels.Count = 0 then
    Exit;

  TotalCur := 0;
  AutoBaseSum := 0;
  for I := 0 to FStatusBar.Panels.Count - 1 do
  begin
    Inc(TotalCur, FStatusBar.Panels[I].Width);
    if FPanelIsAuto[I] then
      Inc(AutoBaseSum, FPanelBaseWidth[I]);
  end;

  Slack := FStatusBar.ClientWidth - TotalCur;
  if (Slack <= 0) or (AutoBaseSum <= 0) then
    Exit;

  Distributed := 0;
  LastAuto := -1;
  for I := 0 to FStatusBar.Panels.Count - 1 do
  begin
    if not FPanelIsAuto[I] then
      Continue;
    Bonus := MulDiv(Slack, FPanelBaseWidth[I], AutoBaseSum);
    FStatusBar.Panels[I].Width := FStatusBar.Panels[I].Width + Bonus;
    Inc(Distributed, Bonus);
    LastAuto := I;
  end;

  {Dump MulDiv truncation remainder into the last auto panel.}
  if (LastAuto >= 0) and (Distributed < Slack) then
    FStatusBar.Panels[LastAuto].Width :=
      FStatusBar.Panels[LastAuto].Width + (Slack - Distributed);
end;

function TStatusBarRenderer.HintForPanel(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= Length(FPanelHints)) then
    Exit('');
  Result := FPanelHints[AIndex];
end;

function TStatusBarRenderer.KindForPanel(AIndex: Integer): TStatusBarTokenKind;
begin
  if (AIndex < 0) or (AIndex >= Length(FPanelKinds)) then
    Exit(tkUnknown);
  Result := FPanelKinds[AIndex];
end;

end.
