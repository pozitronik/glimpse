unit TestStatusBarRenderer;

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms, Vcl.ComCtrls,
  uStatusBarTokens, uStatusBarTemplate, uStatusBarRenderer;

type
  [TestFixture]
  TTestStatusBarRenderer = class
  private
    FForm: TForm;
    FStatusBar: TStatusBar;
    FCanned: string;
    {Resolver factories: every test installs a fresh resolver so the
     renderer's behaviour can be observed against known inputs without
     pulling in TPluginForm or TStatusBarValues.}
    function ResolverConstant(const AText: string): TStatusBarTokenTextResolver;
    function ResolverEcho: TStatusBarTokenTextResolver;
    function MakeRenderer(AResolver: TStatusBarTokenTextResolver): TStatusBarRenderer;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;

    {Construction / lifecycle}
    [Test]
    procedure TestEmptyTemplateProducesNoPanels;
    [Test]
    procedure TestSingleTokenProducesOnePanel;
    [Test]
    procedure TestMultipleTokensProduceOrderedPanels;
    [Test]
    procedure TestRefreshReplacesPanelText;
    [Test]
    procedure TestApplyTemplateReplacesTokens;

    {Missing-data contract}
    [Test]
    procedure TestEmptyResolverWithAutoWidthSkipsPanel;
    [Test]
    procedure TestEmptyResolverWithFixedWidthShowsPlaceholder;
    [Test]
    procedure TestMixedSkipAndKeepLeavesContiguousPanels;

    {Width handling}
    [Test]
    procedure TestExplicitWidthHonoured;
    [Test]
    procedure TestAutoWidthIsPositive;

    {Alignment}
    [Test]
    procedure TestAlignmentRightMapsToTaRightJustify;
    [Test]
    procedure TestAlignmentCenterMapsToTaCenter;
    [Test]
    procedure TestAlignmentDefaultIsTaLeftJustify;

    {Unknown token painting}
    [Test]
    procedure TestUnknownTokenPaintsRawText;

    {Hints}
    [Test]
    procedure TestHintForKnownTokenReturnsRegisteredHint;
    [Test]
    procedure TestHintForOutOfRangeReturnsEmpty;
    [Test]
    procedure TestHintIndicesTrackSkippedPanels;

    {Kind lookup (drives the click-to-toggle dispatch)}
    [Test]
    procedure TestKindForPanelReturnsTokenKind;
    [Test]
    procedure TestKindForOutOfRangeReturnsUnknown;
    [Test]
    procedure TestKindIndicesTrackSkippedPanels;

    {Font}
    [Test]
    procedure TestSetFontUpdatesStatusBarFont;

    {Stretch (panels fill ClientWidth)}
    [Test]
    procedure TestStretchOffLeavesNaturalWidths;
    [Test]
    procedure TestStretchDistributesSlackAcrossAutoPanels;
    [Test]
    procedure TestStretchExactlyFillsClientWidth;
    [Test]
    procedure TestStretchSkipsFixedWidthPanels;
    [Test]
    procedure TestStretchNoOpWhenNoAutoPanels;
    [Test]
    procedure TestStretchNoOpWhenNoSlack;
    [Test]
    procedure TestStretchSingleAutoPanelTakesAllSlack;
  end;

implementation

uses
  System.Classes, System.SysUtils, Vcl.Controls;

{Setup}

procedure TTestStatusBarRenderer.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 800;
  FForm.Height := 100;
  FStatusBar := TStatusBar.Create(FForm);
  FStatusBar.Parent := FForm;
end;

procedure TTestStatusBarRenderer.TearDown;
begin
  FForm.Free;
  FStatusBar := nil;
  FForm := nil;
end;

function TTestStatusBarRenderer.ResolverConstant(
  const AText: string): TStatusBarTokenTextResolver;
begin
  FCanned := AText;
  Result := function(const AToken: TStatusBarToken): string
    begin
      Result := FCanned;
    end;
end;

function TTestStatusBarRenderer.ResolverEcho: TStatusBarTokenTextResolver;
begin
  Result := function(const AToken: TStatusBarToken): string
    begin
      Result := StatusBarTokenName(AToken.Kind);
    end;
end;

function TTestStatusBarRenderer.MakeRenderer(
  AResolver: TStatusBarTokenTextResolver): TStatusBarRenderer;
begin
  Result := TStatusBarRenderer.Create(FStatusBar, AResolver);
end;

{Tests}

procedure TTestStatusBarRenderer.TestEmptyTemplateProducesNoPanels;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('');
    Assert.AreEqual<Integer>(0, FStatusBar.Panels.Count);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestSingleTokenProducesOnePanel;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('hello'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual<Integer>(1, FStatusBar.Panels.Count);
    Assert.AreEqual('hello', FStatusBar.Panels[0].Text);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestMultipleTokensProduceOrderedPanels;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    R.ApplyTemplate('%resolution%%fps%%duration%');
    Assert.AreEqual<Integer>(3, FStatusBar.Panels.Count);
    Assert.AreEqual('resolution', FStatusBar.Panels[0].Text);
    Assert.AreEqual('fps', FStatusBar.Panels[1].Text);
    Assert.AreEqual('duration', FStatusBar.Panels[2].Text);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestRefreshReplacesPanelText;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('first'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual('first', FStatusBar.Panels[0].Text);
    FCanned := 'second';
    R.Refresh;
    Assert.AreEqual('second', FStatusBar.Panels[0].Text);
    Assert.AreEqual<Integer>(1, FStatusBar.Panels.Count,
      'Refresh must not duplicate panels');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestApplyTemplateReplacesTokens;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    R.ApplyTemplate('%resolution%%fps%');
    Assert.AreEqual<Integer>(2, FStatusBar.Panels.Count);
    R.ApplyTemplate('%duration%');
    Assert.AreEqual<Integer>(1, FStatusBar.Panels.Count);
    Assert.AreEqual('duration', FStatusBar.Panels[0].Text);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestEmptyResolverWithAutoWidthSkipsPanel;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant(''));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual<Integer>(0, FStatusBar.Panels.Count,
      'Auto-width token with empty data must collapse out of the bar');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestEmptyResolverWithFixedWidthShowsPlaceholder;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant(''));
  try
    R.ApplyTemplate('%resolution width=120%');
    Assert.AreEqual<Integer>(1, FStatusBar.Panels.Count,
      'Fixed-width token must keep its slot when data is missing');
    Assert.AreEqual(STATUSBAR_MISSING_PLACEHOLDER, FStatusBar.Panels[0].Text);
    Assert.AreEqual<Integer>(120, FStatusBar.Panels[0].Width);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestMixedSkipAndKeepLeavesContiguousPanels;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(
    function(const AToken: TStatusBarToken): string
    begin
      {Empty for fps, present for the others — fps is auto-width so it
       must be elided, leaving resolution and duration adjacent.}
      if AToken.Kind = tkFps then
        Result := ''
      else
        Result := StatusBarTokenName(AToken.Kind);
    end);
  try
    R.ApplyTemplate('%resolution%%fps%%duration%');
    Assert.AreEqual<Integer>(2, FStatusBar.Panels.Count);
    Assert.AreEqual('resolution', FStatusBar.Panels[0].Text);
    Assert.AreEqual('duration', FStatusBar.Panels[1].Text,
      'Skipped panel must not leave a gap; the next visible token slides in');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestExplicitWidthHonoured;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution width=200%');
    Assert.AreEqual<Integer>(200, FStatusBar.Panels[0].Width);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestAutoWidthIsPositive;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('1234567890'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.IsTrue(FStatusBar.Panels[0].Width > 0,
      'Auto width must be measured to a positive value, not 0 / negative');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestAlignmentRightMapsToTaRightJustify;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('1.23s'));
  try
    R.ApplyTemplate('%load_time width=100 align=right%');
    Assert.AreEqual(Ord(taRightJustify), Ord(FStatusBar.Panels[0].Alignment));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestAlignmentCenterMapsToTaCenter;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution width=100 align=center%');
    Assert.AreEqual(Ord(taCenter), Ord(FStatusBar.Panels[0].Alignment));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestAlignmentDefaultIsTaLeftJustify;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual(Ord(taLeftJustify), Ord(FStatusBar.Panels[0].Alignment));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestUnknownTokenPaintsRawText;
var
  R: TStatusBarRenderer;
begin
  {The resolver will receive tkUnknown and is expected to return the
   token's RawText (that is what the production formatter does). The
   renderer must add a panel for it because the text is non-empty.}
  R := MakeRenderer(
    function(const AToken: TStatusBarToken): string
    begin
      Result := AToken.RawText;
    end);
  try
    R.ApplyTemplate('%mistype%');
    Assert.AreEqual<Integer>(1, FStatusBar.Panels.Count);
    Assert.AreEqual('%mistype%', FStatusBar.Panels[0].Text);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestHintForKnownTokenReturnsRegisteredHint;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual(StatusBarTokenHint(tkResolution), R.HintForPanel(0));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestHintForOutOfRangeReturnsEmpty;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual('', R.HintForPanel(-1));
    Assert.AreEqual('', R.HintForPanel(99));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestHintIndicesTrackSkippedPanels;
var
  R: TStatusBarRenderer;
begin
  {When fps is skipped (empty + auto), HintForPanel(1) must address
   duration's hint, NOT fps's. Hints are parallel to the live Panels
   collection, not the source token list.}
  R := MakeRenderer(
    function(const AToken: TStatusBarToken): string
    begin
      if AToken.Kind = tkFps then
        Result := ''
      else
        Result := 'present';
    end);
  try
    R.ApplyTemplate('%resolution%%fps%%duration%');
    Assert.AreEqual(StatusBarTokenHint(tkResolution), R.HintForPanel(0));
    Assert.AreEqual(StatusBarTokenHint(tkDuration), R.HintForPanel(1));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestKindForPanelReturnsTokenKind;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%save_dimension%%copy_dimension%');
    Assert.AreEqual(Ord(tkSaveDimension), Ord(R.KindForPanel(0)));
    Assert.AreEqual(Ord(tkCopyDimension), Ord(R.KindForPanel(1)));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestKindForOutOfRangeReturnsUnknown;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution%');
    Assert.AreEqual(Ord(tkUnknown), Ord(R.KindForPanel(-1)));
    Assert.AreEqual(Ord(tkUnknown), Ord(R.KindForPanel(99)));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestKindIndicesTrackSkippedPanels;
var
  R: TStatusBarRenderer;
begin
  {Same parallel-to-live-Panels rule as HintForPanel: when fps is
   skipped (empty + auto), KindForPanel(1) addresses duration. Pins
   the contract that drives the click-to-toggle dispatch — if kinds
   tracked SOURCE tokens instead of live panels, clicking on duration
   would flip the wrong setting.}
  R := MakeRenderer(
    function(const AToken: TStatusBarToken): string
    begin
      if AToken.Kind = tkFps then
        Result := ''
      else
        Result := 'present';
    end);
  try
    R.ApplyTemplate('%save_dimension%%fps%%copy_dimension%');
    Assert.AreEqual(Ord(tkSaveDimension), Ord(R.KindForPanel(0)));
    Assert.AreEqual(Ord(tkCopyDimension), Ord(R.KindForPanel(1)));
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestSetFontUpdatesStatusBarFont;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverConstant('x'));
  try
    R.ApplyTemplate('%resolution%');
    R.SetFont('Courier New', 12);
    Assert.AreEqual('Courier New', FStatusBar.Font.Name);
    Assert.AreEqual<Integer>(12, FStatusBar.Font.Size);
  finally
    R.Free;
  end;
end;

function SumPanelWidths(AStatusBar: TStatusBar): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to AStatusBar.Panels.Count - 1 do
    Inc(Result, AStatusBar.Panels[I].Width);
end;

procedure TTestStatusBarRenderer.TestStretchOffLeavesNaturalWidths;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    FStatusBar.Width := 800;
    R.ApplyTemplate('%resolution%%fps%');
    Assert.IsTrue(SumPanelWidths(FStatusBar) < FStatusBar.ClientWidth,
      'Without stretch, the sum of natural widths must leave slack on the right');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestStretchDistributesSlackAcrossAutoPanels;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    FStatusBar.Width := 800;
    R.SetStretchPanels(True);
    R.ApplyTemplate('%resolution%%fps%');
    Assert.AreEqual<Integer>(FStatusBar.ClientWidth, SumPanelWidths(FStatusBar),
      'With stretch on, panels must exactly cover ClientWidth');
    Assert.IsTrue(FStatusBar.Panels[0].Width > 0);
    Assert.IsTrue(FStatusBar.Panels[1].Width > 0);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestStretchExactlyFillsClientWidth;
var
  R: TStatusBarRenderer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    FStatusBar.Width := 800;
    R.SetStretchPanels(True);
    R.ApplyTemplate('%resolution%%fps%%duration%');
    Assert.AreEqual<Integer>(FStatusBar.ClientWidth, SumPanelWidths(FStatusBar),
      'MulDiv rounding leftover must be absorbed by the last auto panel');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestStretchSkipsFixedWidthPanels;
var
  R: TStatusBarRenderer;
  FixedBefore, FixedAfter: Integer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    {Capture the fixed panel's width without stretch first, then enable
     stretch — the fixed panel's width must be identical in both cases.}
    FStatusBar.Width := 800;
    R.ApplyTemplate('%resolution width=100%%fps%');
    FixedBefore := FStatusBar.Panels[0].Width;

    R.SetStretchPanels(True);
    FixedAfter := FStatusBar.Panels[0].Width;
    Assert.AreEqual<Integer>(FixedBefore, FixedAfter,
      'Fixed-width panel must not receive any stretch share');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestStretchNoOpWhenNoAutoPanels;
var
  R: TStatusBarRenderer;
  W0, W1: Integer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    FStatusBar.Width := 800;
    R.ApplyTemplate('%resolution width=100%%fps width=120%');
    W0 := FStatusBar.Panels[0].Width;
    W1 := FStatusBar.Panels[1].Width;

    R.SetStretchPanels(True);
    Assert.AreEqual<Integer>(W0, FStatusBar.Panels[0].Width);
    Assert.AreEqual<Integer>(W1, FStatusBar.Panels[1].Width);
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestStretchNoOpWhenNoSlack;
var
  R: TStatusBarRenderer;
  BeforeWidth: Integer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    {Tiny bar with one wide fixed panel: natural width exceeds
     ClientWidth so stretch has nothing to redistribute. Panel must
     keep its natural (overflowing) width — no negative stretch.}
    FStatusBar.Width := 50;
    R.ApplyTemplate('%resolution width=200%');
    BeforeWidth := FStatusBar.Panels[0].Width;

    R.SetStretchPanels(True);
    Assert.AreEqual<Integer>(BeforeWidth, FStatusBar.Panels[0].Width,
      'Overflow case must be a no-op rather than producing negative or zero widths');
  finally
    R.Free;
  end;
end;

procedure TTestStatusBarRenderer.TestStretchSingleAutoPanelTakesAllSlack;
var
  R: TStatusBarRenderer;
  FixedWidth: Integer;
begin
  R := MakeRenderer(ResolverEcho());
  try
    FStatusBar.Width := 800;
    R.SetStretchPanels(True);
    R.ApplyTemplate('%resolution width=100%%fps%');
    FixedWidth := FStatusBar.Panels[0].Width;
    Assert.AreEqual<Integer>(FStatusBar.ClientWidth - FixedWidth,
      FStatusBar.Panels[1].Width,
      'The lone auto panel must absorb all the remaining slack');
  finally
    R.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestStatusBarRenderer);

end.
