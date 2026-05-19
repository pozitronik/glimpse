{ Tests for the pure formatting helpers shared by both settings dialogs.
  These exercise every branch of the policy without touching VCL or
  spawning ffmpeg. }
unit TestSettingsDlgLogic;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsDlgLogic = class
  public
    { MaxThreadsAutoLabel }
    [Test] procedure MaxThreads_OnePerFrameOff_ReturnsEmpty;
    [Test] procedure MaxThreads_OnePerFrameOff_IgnoresThreadsAndCpu;
    [Test] procedure MaxThreads_AutoNegativePos_ReturnsNoLimit;
    [Test] procedure MaxThreads_AutoZeroPos_ReturnsCoresLabel;
    [Test] procedure MaxThreads_AutoZeroPos_FormatsCpuCount;
    [Test] procedure MaxThreads_AutoExplicitPos_ReturnsEmpty;

    { DecodeTimestampCornerControls / EncodeTimestampCornerControls }
    [Test] procedure DecodeTimestamp_LegacyNone_UnchecksAndSetsDefaultCorner;
    [Test] procedure DecodeTimestamp_NonNone_PreservesShowAndCornerIndex;
    [Test] procedure DecodeTimestamp_AllCorners_RoundTrip;
    [Test] procedure EncodeTimestamp_PassThrough;
    [Test] procedure Timestamp_RoundTrip_ForAllCorners;

    { DecodeMaxWorkersControls / EncodeMaxWorkersControls }
    [Test] procedure DecodeMaxWorkers_Zero_ChecksAutoAndFallsBackToOne;
    [Test] procedure DecodeMaxWorkers_Positive_UnchecksAuto;
    [Test] procedure EncodeMaxWorkers_AutoWins_OverUdPosition;
    [Test] procedure EncodeMaxWorkers_Explicit_ReturnsUdPosition;
    [Test] procedure MaxWorkers_RoundTrip_Zero;
    [Test] procedure MaxWorkers_RoundTrip_Positive;

    { DecodeMaxThreadsControl }
    [Test] procedure DecodeMaxThreads_Positive_ReturnsAsIs;
    [Test] procedure DecodeMaxThreads_NoLimit_CollapsesToZero;
    [Test] procedure DecodeMaxThreads_Auto_StaysZero;

    { DeriveColorPanelNameForButton }
    [Test] procedure DerivePanelName_BtnPrefix_ReplacesWithPnl;
    [Test] procedure DerivePanelName_AllProductionButtons_RoundTrip;
    [Test] procedure DerivePanelName_NoBtnPrefix_ReturnsEmpty;
    [Test] procedure DerivePanelName_EmptyName_ReturnsEmpty;
    [Test] procedure DerivePanelName_JustBtn_ReturnsBarePnl;
    [Test] procedure DerivePanelName_MixedCase_StillMatches;
  end;

implementation

uses
  System.SysUtils,
  Types, Defaults, SettingsDlgLogic;

{ MaxThreadsAutoLabel }

procedure TTestSettingsDlgLogic.MaxThreads_OnePerFrameOff_ReturnsEmpty;
begin
  { When the field is disabled the hint must be empty regardless of the
    other inputs. }
  Assert.AreEqual('', MaxThreadsAutoLabel(False, 0, 8));
end;

procedure TTestSettingsDlgLogic.MaxThreads_OnePerFrameOff_IgnoresThreadsAndCpu;
begin
  { Belt-and-braces: a stale spin-edit value or a different CPU count
    must not leak into the label when the mode is off. }
  Assert.AreEqual('', MaxThreadsAutoLabel(False, 999, 1));
  Assert.AreEqual('', MaxThreadsAutoLabel(False, -1, 32));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoNegativePos_ReturnsNoLimit;
begin
  { Spin position < 0 is the sentinel for "unlimited threads". }
  Assert.AreEqual('(no limit)', MaxThreadsAutoLabel(True, -1, 8));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoZeroPos_ReturnsCoresLabel;
begin
  Assert.AreEqual('(auto: 4 cores)', MaxThreadsAutoLabel(True, 0, 4));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoZeroPos_FormatsCpuCount;
begin
  { Verify the live CPU count is interpolated rather than a hardcoded
    constant — different machines must show different numbers. }
  Assert.AreEqual('(auto: 16 cores)', MaxThreadsAutoLabel(True, 0, 16));
  Assert.AreEqual('(auto: 1 cores)', MaxThreadsAutoLabel(True, 0, 1));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoExplicitPos_ReturnsEmpty;
begin
  { When the user picked a positive value the hint is suppressed —
    the visible spin shows the chosen value, no extra text needed. }
  Assert.AreEqual('', MaxThreadsAutoLabel(True, 1, 8));
  Assert.AreEqual('', MaxThreadsAutoLabel(True, 12, 8));
end;

{ DecodeTimestampCornerControls / EncodeTimestampCornerControls }

procedure TTestSettingsDlgLogic.DecodeTimestamp_LegacyNone_UnchecksAndSetsDefaultCorner;
var
  ShowChecked: Boolean;
  ComboIdx: Integer;
begin
  {Legacy tcNone migrates to Show=False + default-corner combo index, no
   matter what the persisted Show flag was.}
  DecodeTimestampCornerControls(True, tcNone, ShowChecked, ComboIdx);
  Assert.IsFalse(ShowChecked, 'tcNone must force Show=False');
  Assert.AreEqual(Ord(DEF_TIMESTAMP_CORNER) - 1, ComboIdx,
    'tcNone must fall back to the default corner combo index');
end;

procedure TTestSettingsDlgLogic.DecodeTimestamp_NonNone_PreservesShowAndCornerIndex;
var
  ShowChecked: Boolean;
  ComboIdx: Integer;
begin
  DecodeTimestampCornerControls(False, tcTopRight, ShowChecked, ComboIdx);
  Assert.IsFalse(ShowChecked);
  Assert.AreEqual(1, ComboIdx, 'tcTopRight is combo index 1');

  DecodeTimestampCornerControls(True, tcBottomLeft, ShowChecked, ComboIdx);
  Assert.IsTrue(ShowChecked);
  Assert.AreEqual(2, ComboIdx, 'tcBottomLeft is combo index 2');
end;

procedure TTestSettingsDlgLogic.DecodeTimestamp_AllCorners_RoundTrip;
var
  C: TTimestampCorner;
  ShowChecked: Boolean;
  ComboIdx: Integer;
begin
  {Every non-None corner must survive a Decode: Show flag preserved, combo
   index = Ord(Corner) - 1.}
  for C := tcTopLeft to tcBottomRight do
  begin
    DecodeTimestampCornerControls(True, C, ShowChecked, ComboIdx);
    Assert.IsTrue(ShowChecked);
    Assert.AreEqual(Ord(C) - 1, ComboIdx,
      Format('Combo index for corner %d must be Ord-1', [Ord(C)]));
  end;
end;

procedure TTestSettingsDlgLogic.EncodeTimestamp_PassThrough;
var
  Show: Boolean;
  Corner: TTimestampCorner;
begin
  EncodeTimestampCornerControls(True, 0, Show, Corner);
  Assert.IsTrue(Show);
  Assert.AreEqual(Ord(tcTopLeft), Ord(Corner));

  EncodeTimestampCornerControls(False, 3, Show, Corner);
  Assert.IsFalse(Show);
  Assert.AreEqual(Ord(tcBottomRight), Ord(Corner));
end;

procedure TTestSettingsDlgLogic.Timestamp_RoundTrip_ForAllCorners;
var
  Orig: TTimestampCorner;
  ShowIn, ShowOut: Boolean;
  ComboIdx: Integer;
  CornerOut: TTimestampCorner;
begin
  {Full cycle Decode → Encode for every non-None corner. Exercises the
   invariant that the dialog controls are a lossless representation of
   the stored state (excluding the one-way tcNone migration).}
  for Orig := tcTopLeft to tcBottomRight do
  begin
    ShowIn := (Ord(Orig) mod 2) = 0;
    DecodeTimestampCornerControls(ShowIn, Orig, ShowOut, ComboIdx);
    EncodeTimestampCornerControls(ShowOut, ComboIdx, ShowOut, CornerOut);
    Assert.AreEqual(ShowIn, ShowOut,
      Format('Show flag must survive round-trip for corner %d', [Ord(Orig)]));
    Assert.AreEqual(Ord(Orig), Ord(CornerOut),
      Format('Corner must survive round-trip for %d', [Ord(Orig)]));
  end;
end;

{ DecodeMaxWorkersControls / EncodeMaxWorkersControls }

procedure TTestSettingsDlgLogic.DecodeMaxWorkers_Zero_ChecksAutoAndFallsBackToOne;
var
  AutoChecked: Boolean;
  UdPos: Integer;
begin
  {Zero = auto. The UpDown is kept at a visible "1" fallback so the user
   doesn't see an ambiguous "0" if they toggle auto off.}
  DecodeMaxWorkersControls(0, AutoChecked, UdPos);
  Assert.IsTrue(AutoChecked);
  Assert.AreEqual(1, UdPos);
end;

procedure TTestSettingsDlgLogic.DecodeMaxWorkers_Positive_UnchecksAuto;
var
  AutoChecked: Boolean;
  UdPos: Integer;
begin
  DecodeMaxWorkersControls(4, AutoChecked, UdPos);
  Assert.IsFalse(AutoChecked);
  Assert.AreEqual(4, UdPos);

  DecodeMaxWorkersControls(16, AutoChecked, UdPos);
  Assert.IsFalse(AutoChecked);
  Assert.AreEqual(16, UdPos);
end;

procedure TTestSettingsDlgLogic.EncodeMaxWorkers_AutoWins_OverUdPosition;
begin
  {When auto is checked, the UpDown position is stale and must be ignored.}
  Assert.AreEqual(0, EncodeMaxWorkersControls(True, 8));
  Assert.AreEqual(0, EncodeMaxWorkersControls(True, 1));
end;

procedure TTestSettingsDlgLogic.EncodeMaxWorkers_Explicit_ReturnsUdPosition;
begin
  Assert.AreEqual(1, EncodeMaxWorkersControls(False, 1));
  Assert.AreEqual(16, EncodeMaxWorkersControls(False, 16));
end;

procedure TTestSettingsDlgLogic.MaxWorkers_RoundTrip_Zero;
var
  AutoChecked: Boolean;
  UdPos: Integer;
begin
  DecodeMaxWorkersControls(0, AutoChecked, UdPos);
  Assert.AreEqual(0, EncodeMaxWorkersControls(AutoChecked, UdPos),
    'Zero must round-trip: Decode auto + fallback UpDown, Encode back to 0');
end;

procedure TTestSettingsDlgLogic.MaxWorkers_RoundTrip_Positive;
var
  AutoChecked: Boolean;
  UdPos: Integer;
begin
  DecodeMaxWorkersControls(7, AutoChecked, UdPos);
  Assert.AreEqual(7, EncodeMaxWorkersControls(AutoChecked, UdPos),
    'Positive MaxWorkers must survive Decode→Encode unchanged');
end;

{ DecodeMaxThreadsControl }

procedure TTestSettingsDlgLogic.DecodeMaxThreads_Positive_ReturnsAsIs;
begin
  Assert.AreEqual(8, DecodeMaxThreadsControl(8));
  Assert.AreEqual(64, DecodeMaxThreadsControl(64));
end;

procedure TTestSettingsDlgLogic.DecodeMaxThreads_NoLimit_CollapsesToZero;
begin
  {The UpDown's minimum is 0, so -1 (no limit) collapses to 0 on display.
   This is a documented lossy one-way map — the encode direction is a
   straight UpDown.Position passthrough.}
  Assert.AreEqual(0, DecodeMaxThreadsControl(-1));
end;

procedure TTestSettingsDlgLogic.DecodeMaxThreads_Auto_StaysZero;
begin
  Assert.AreEqual(0, DecodeMaxThreadsControl(0));
end;

{ DeriveColorPanelNameForButton }

procedure TTestSettingsDlgLogic.DerivePanelName_BtnPrefix_ReplacesWithPnl;
begin
  Assert.AreEqual('PnlBackground', DeriveColorPanelNameForButton('BtnBackground'));
  Assert.AreEqual('PnlTCBack', DeriveColorPanelNameForButton('BtnTCBack'));
end;

procedure TTestSettingsDlgLogic.DerivePanelName_AllProductionButtons_RoundTrip;
begin
  {Pins every BtnXxx -> PnlXxx mapping the production DFM relies on.
   If a future settings-dialog edit renames a panel/button pair away
   from this convention, this test fails before the user notices a
   dead colour-picker click.}
  Assert.AreEqual('PnlBackground', DeriveColorPanelNameForButton('BtnBackground'));
  Assert.AreEqual('PnlTCBack', DeriveColorPanelNameForButton('BtnTCBack'));
  Assert.AreEqual('PnlTCTextColor', DeriveColorPanelNameForButton('BtnTCTextColor'));
  Assert.AreEqual('PnlBannerBackground', DeriveColorPanelNameForButton('BtnBannerBackground'));
  Assert.AreEqual('PnlBannerTextColor', DeriveColorPanelNameForButton('BtnBannerTextColor'));
end;

procedure TTestSettingsDlgLogic.DerivePanelName_NoBtnPrefix_ReturnsEmpty;
begin
  {Sender lacking the convention prefix must yield an empty string so
   the caller silently no-ops rather than producing a garbage panel
   name and hitting FindComponent with it.}
  Assert.AreEqual('', DeriveColorPanelNameForButton('LblBackground'));
  Assert.AreEqual('', DeriveColorPanelNameForButton('EdtSomething'));
  Assert.AreEqual('', DeriveColorPanelNameForButton('SomethingElse'));
end;

procedure TTestSettingsDlgLogic.DerivePanelName_EmptyName_ReturnsEmpty;
begin
  Assert.AreEqual('', DeriveColorPanelNameForButton(''));
end;

procedure TTestSettingsDlgLogic.DerivePanelName_JustBtn_ReturnsBarePnl;
begin
  {Degenerate case: a button named exactly 'Btn' produces 'Pnl' as the
   sibling panel name. The runtime FindComponent lookup will fail to
   resolve that to anything in production (no panel is named 'Pnl' on
   its own), so the handler safely no-ops. Test pins the string
   transform, not the runtime behaviour.}
  Assert.AreEqual('Pnl', DeriveColorPanelNameForButton('Btn'));
end;

procedure TTestSettingsDlgLogic.DerivePanelName_MixedCase_StillMatches;
begin
  {StartsText is case-insensitive — defensive: a future rename to
   'btnBackground' or 'BTNBackground' still resolves correctly.}
  Assert.AreEqual('Pnlbackground', DeriveColorPanelNameForButton('btnbackground'));
  Assert.AreEqual('PnlBackground', DeriveColorPanelNameForButton('BTNBackground'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsDlgLogic);

end.
