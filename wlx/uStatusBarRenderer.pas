{Bridges the parsed token list (uStatusBarTemplate) and the live VCL
 status bar. Holds no domain knowledge of its own — the per-token text
 is supplied through a resolver callback so the renderer can be unit-
 tested with a fake resolver and so plugin state never leaks into this
 unit.

 Responsibilities:
   - parses the template at ApplyTemplate time and caches the tokens
   - measures sample-text widths once per font/template change so
     "auto" panels do not flicker on each Refresh (live mode opt-in)
   - on Refresh: queries the resolver per token, decides skip vs
     placeholder for empty results, mirrors the result onto
     FStatusBar.Panels in declaration order
   - exposes HintForPanel for the host form's CMHintShow plumbing

 Missing-data contract (decided with the user):
   - resolver returned ''  AND token width is auto: panel is skipped
     entirely (the bar collapses), so dynamic layouts stay tidy
   - resolver returned ''  AND token has a fixed pixel width: panel
     stays at that width and shows '?', so anchored layouts retain
     their slot count and the user notices the missing datum

 The progress bar continues to live outside the template — the host
 form keeps its existing overlay/append logic and reads
 FStatusBar.Panels exactly as before.}
unit uStatusBarRenderer;

interface

uses
  System.Classes, Vcl.ComCtrls,
  uStatusBarTokens, uStatusBarTemplate;

type
  {Lambda the host form supplies to map a token to its current text.
   Empty result is the explicit signal "data unavailable"; the renderer
   takes care of skip-vs-placeholder per the missing-data contract.}
  TStatusBarTokenTextResolver = reference to function(
    const AToken: TStatusBarToken): string;

  TStatusBarRenderer = class
  private
    FStatusBar: TStatusBar;
    FResolver: TStatusBarTokenTextResolver;
    FTokens: TStatusBarTokenArray;
    {Parallel to FTokens. Cached width measured from the token's sample
     text, used when AutoWidthLive=False and the token has no explicit
     width. Indexed by token index, not panel index, because tokens may
     resolve to no panel (skip-on-auto-empty).}
    FAutoWidths: TArray<Integer>;
    {Parallel to the LIVE FStatusBar.Panels. Populated by Refresh in
     lockstep with panel additions, so HintForPanel(I) always lines up
     with Panels[I] no matter how many tokens were skipped.}
    FPanelHints: TArray<string>;
    {Parallel to the LIVE FStatusBar.Panels. Lets the host form ask
     "what token does this panel render?" without re-parsing the
     template — needed by the click-to-toggle handler on the dimension
     panels and the WM_SETCURSOR hand-cursor handler.}
    FPanelKinds: TArray<TStatusBarTokenKind>;
    {Parallel to the LIVE FStatusBar.Panels. Marks each panel as
     auto-width (no explicit width=N in the template) or fixed. Drives
     the stretch post-pass: only auto-width panels receive a share of
     the slack so users keep precise control over fixed-width slots.}
    FPanelIsAuto: TArray<Boolean>;
    {Parallel to the LIVE FStatusBar.Panels. The panel's pre-stretch
     natural width (sample-text-measured for auto, explicit-scaled for
     fixed). Stored separately from Panel.Width because Panel.Width
     gets mutated by the stretch pass.}
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
    {AStatusBar must outlive the renderer; AResolver may not be nil.}
    constructor Create(AStatusBar: TStatusBar;
      AResolver: TStatusBarTokenTextResolver);
    {Replaces the template. Re-parses, re-measures auto widths against
     the current font, and rebuilds FStatusBar.Panels via Refresh.}
    procedure ApplyTemplate(const ATemplate: string);
    {Re-queries the resolver for every token and rewrites
     FStatusBar.Panels. Token list and font are unchanged.}
    procedure Refresh;
    {Returns the default tooltip for the panel currently at AIndex,
     or '' for out-of-range / unknown / unset entries.}
    function HintForPanel(AIndex: Integer): string;
    {Returns the token kind backing the panel currently at AIndex.
     tkUnknown for out-of-range (or for an unknown token whose RawText
     was painted literally). Lets callers route interactive behaviour
     by panel kind without touching the renderer's internals.}
    function KindForPanel(AIndex: Integer): TStatusBarTokenKind;
    {Updates FStatusBar.Font to the given face + size, re-measures any
     cached auto widths, and rebuilds the panels so the new metrics
     take effect immediately.}
    procedure SetFont(const AFontName: string; AFontSize: Integer);
    {When True the renderer measures the live resolved text on every
     Refresh (panel widths track content, with the inevitable layout
     shift). Default False: auto widths are measured once with the
     token's representative sample text and then locked.}
    procedure SetAutoWidthLive(AValue: Boolean);
    {When True, Refresh runs a post-pass that distributes any slack
     between sum-of-panel-widths and FStatusBar.ClientWidth across the
     auto-width panels proportionally to their natural widths. The
     stretch baseline is always the sample-text width (not the live
     text) so the layout stays stable when AutoWidthLive is also on —
     stretch is a layout decision, not a content one. No-op when there
     is no slack or no auto-width panels.}
    procedure SetStretchPanels(AValue: Boolean);
    property AutoWidthLive: Boolean read FAutoWidthLive;
    property StretchPanels: Boolean read FStretchPanels;
  end;

const
  {Painted into a fixed-width panel when its resolver returned ''.
   Single character keeps the panel from looking blank-on-purpose.}
  STATUSBAR_MISSING_PLACEHOLDER = '?';

  {Pixel slack added to TextWidth measurements so Tahoma's last
   character isn't clipped against the panel border. Empirical value
   matching the inset the common control draws on either side.}
  STATUSBAR_AUTO_WIDTH_PADDING = 8;

implementation

uses
  System.SysUtils, Winapi.Windows, Vcl.Graphics;

constructor TStatusBarRenderer.Create(AStatusBar: TStatusBar;
  AResolver: TStatusBarTokenTextResolver);
begin
  inherited Create;
  {Hard runtime check, not Assert. Assert compiles to nothing in $C-
   release builds; the constructor would then accept nil and the first
   FStatusBar / FResolver access would crash with an opaque AV.}
  if AStatusBar = nil then
    raise EArgumentNilException.Create('TStatusBarRenderer requires a TStatusBar instance');
  if not Assigned(AResolver) then
    raise EArgumentNilException.Create('TStatusBarRenderer requires a non-nil resolver');
  FStatusBar := AStatusBar;
  FResolver := AResolver;
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
      {Unknown tokens always paint their RawText, so size to that
       directly rather than to a sample (which is empty for tkUnknown).}
      Sample := FTokens[I].RawText
    else
      Sample := StatusBarTokenSampleText(FTokens[I].Kind);
    FAutoWidths[I] := MeasureText(Sample);
  end;
end;

function TStatusBarRenderer.MeasureText(const AText: string): Integer;
var
  Bmp: TBitmap;
  Ppi: Integer;
begin
  if AText = '' then
    Exit(0);
  {Status bar widths live in the bar's device pixels — on a 150% DPI
   monitor "100 px" really means 150 device pixels. A fresh TBitmap
   defaults its canvas to 96 DPI, so TextWidth on it would return
   unscaled values and panel widths would clip under high-DPI / per-
   monitor-aware mode. Borrow the bar's CurrentPPI so font height is
   converted using the same context the panels will paint into.}
  Ppi := FStatusBar.CurrentPPI;
  if Ppi <= 0 then
    Ppi := 96;
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.PixelsPerInch := Ppi;
    Bmp.Canvas.Font.Name := FFontName;
    Bmp.Canvas.Font.Size := FFontSize;
    Result := Bmp.Canvas.TextWidth(AText) + MulDiv(STATUSBAR_AUTO_WIDTH_PADDING, Ppi, 96);
  finally
    Bmp.Free;
  end;
end;

function TStatusBarRenderer.ScaledExplicitWidth(ALogicalWidth: Integer): Integer;
var
  Ppi: Integer;
begin
  {User-typed "width=N" in a template is a logical pixel count (i.e.
   what the user would have measured on a 100%-scaled monitor). Convert
   to the bar's device pixels here so explicit panels stay the right
   visual size on high-DPI displays.}
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
          {Skip-on-auto-empty: a missing datum in an auto-width slot
           collapses out so the bar stays tidy.}
          Continue;
        Text := STATUSBAR_MISSING_PLACEHOLDER;
      end;

      if HasExplicitWidth then
        EffectiveWidth := ScaledExplicitWidth(ExplicitWidth)
      else if FStretchPanels then
        {Stretch baseline must be stable: pick the sample-text width
         (FAutoWidths) regardless of AutoWidthLive so the proportional
         distribution stays consistent and doesn't jitter as live text
         changes. The stretch post-pass below expands each auto panel
         from this baseline.}
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
    {Stretch is a post-pass so the per-panel build above stays simple;
     the math only needs the natural totals computed against the live
     ClientWidth.}
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
  {No-op when natural widths already overflow the bar (Slack < 0), when
   the bar is at exact-fit (Slack = 0), or when the template has no
   auto-width panels to receive the distribution.}
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

  {Rounding leftover (MulDiv truncates): dump the remainder into the
   last auto panel so the panels exactly cover ClientWidth and the
   common control has no trailing slack to inflate.}
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
