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
    FAutoWidthLive: Boolean;
    FFontName: string;
    FFontSize: Integer;
    procedure RemeasureAutoWidths;
    function MeasureText(const AText: string): Integer;
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
    {Updates FStatusBar.Font to the given face + size, re-measures any
     cached auto widths, and rebuilds the panels so the new metrics
     take effect immediately.}
    procedure SetFont(const AFontName: string; AFontSize: Integer);
    {When True the renderer measures the live resolved text on every
     Refresh (panel widths track content, with the inevitable layout
     shift). Default False: auto widths are measured once with the
     token's representative sample text and then locked.}
    procedure SetAutoWidthLive(AValue: Boolean);
    property AutoWidthLive: Boolean read FAutoWidthLive;
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
  System.SysUtils, Vcl.Graphics;

constructor TStatusBarRenderer.Create(AStatusBar: TStatusBar;
  AResolver: TStatusBarTokenTextResolver);
begin
  inherited Create;
  Assert(AStatusBar <> nil, 'TStatusBarRenderer requires a TStatusBar instance');
  Assert(Assigned(AResolver), 'TStatusBarRenderer requires a non-nil resolver');
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
begin
  if AText = '' then
    Exit(0);
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Name := FFontName;
    Bmp.Canvas.Font.Size := FFontSize;
    Result := Bmp.Canvas.TextWidth(AText) + STATUSBAR_AUTO_WIDTH_PADDING;
  finally
    Bmp.Free;
  end;
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
        EffectiveWidth := ExplicitWidth
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
    end;
  finally
    FStatusBar.Panels.EndUpdate;
  end;
end;

function TStatusBarRenderer.HintForPanel(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= Length(FPanelHints)) then
    Exit('');
  Result := FPanelHints[AIndex];
end;

end.
