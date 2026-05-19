{TStatusBar specialisation used by the plugin form. Hoisted from
 uPluginForm so the per-panel hint plumbing and the hit-test arithmetic
 stay independently inspectable from the host form and its many other
 concerns. Self-contained: no back reference to the form is needed.}
unit uStatusBarHostBar;

interface

uses
  System.Classes, System.Types,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.ComCtrls,
  uStatusBarTokens;

type
  {Per-panel hint provider used by TGlimpseStatusBar. APanelIndex is the
   0-based index of the panel under the cursor, or -1 when the cursor is
   past the last panel.}
  TStatusBarHintProvider = reference to function(APanelIndex: Integer): string;

  {Callback the host form supplies so the status bar can ask "what kind
   of token does the panel at APanelIndex render?" without coupling the
   subclass to the renderer. Returns tkUnknown for unmapped indices,
   which the cursor logic treats as "not interactive".}
  TStatusBarPanelKindProvider = reference to function(APanelIndex: Integer): TStatusBarTokenKind;

  {TStatusBar specialisation that surfaces a per-panel hint instead of a
   single per-control Hint. Drives the hint mechanism via CMHintShow's
   CursorRect: setting CursorRect to the panel under the cursor makes the
   VCL re-issue CMHintShow when the cursor crosses into a different panel,
   which in turn lets us swap HintStr without the brittle
   "set Hint + CancelHint" dance that does not always re-pop on the same
   control. Also intercepts WM_SETCURSOR to paint the hand cursor over
   panels whose backing token kind is interactive (Save / Copy dim).}
  TGlimpseStatusBar = class(TStatusBar)
  private
    FOnGetPanelHint: TStatusBarHintProvider;
    FOnQueryPanelKind: TStatusBarPanelKindProvider;
    procedure CMHintShow(var Msg: TCMHintShow); message CM_HINTSHOW;
    procedure WMSetCursor(var Msg: TWMSetCursor); message WM_SETCURSOR;
  public
    property OnGetPanelHint: TStatusBarHintProvider read FOnGetPanelHint write FOnGetPanelHint;
    property OnQueryPanelKind: TStatusBarPanelKindProvider read FOnQueryPanelKind write FOnQueryPanelKind;
  end;

{Walks AStatusBar's panels left-to-right; returns the index of the panel
 under the X coord, or -1 when AX is past the last panel. APanelLeft is
 set to the left edge of the matched panel; when -1 (past-end) it is set
 to the right edge of the last panel so callers can compose a "trailing
 dead zone" rect. Returns -1 for an empty status bar (APanelLeft=0).
 Centralises the arithmetic shared by OnStatusBarDblClick and the per-
 panel hint dispatch in TGlimpseStatusBar.CMHintShow.}
function StatusBarPanelHitTest(AStatusBar: TStatusBar; AX: Integer; out APanelLeft: Integer): Integer;

implementation

function StatusBarPanelHitTest(AStatusBar: TStatusBar; AX: Integer; out APanelLeft: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  APanelLeft := 0;
  for I := 0 to AStatusBar.Panels.Count - 1 do
  begin
    if AX < APanelLeft + AStatusBar.Panels[I].Width then
      Exit(I);
    Inc(APanelLeft, AStatusBar.Panels[I].Width);
  end;
end;

procedure TGlimpseStatusBar.CMHintShow(var Msg: TCMHintShow);
var
  PanelLeft, HitIdx: Integer;
  HintText: string;
begin
  if not Assigned(FOnGetPanelHint) then
  begin
    inherited;
    Exit;
  end;

  HitIdx := StatusBarPanelHitTest(Self, Msg.HintInfo.CursorPos.X, PanelLeft);

  HintText := FOnGetPanelHint(HitIdx);
  if HintText = '' then
  begin
    {No hint for this region. Suppress the popup but still set a tight
     CursorRect so the next cross-panel move re-queries us.}
    Msg.Result := 1;
  end else begin
    Msg.HintInfo.HintStr := HintText;
    Msg.Result := 0;
  end;

  if HitIdx >= 0 then
    Msg.HintInfo.CursorRect := Rect(PanelLeft, 0, PanelLeft + Panels[HitIdx].Width, Height)
  else
    {Past the last panel: cursor rect is the trailing dead zone, so we
     stay quiet until the cursor enters a real panel.}
    Msg.HintInfo.CursorRect := Rect(PanelLeft, 0, ClientWidth, Height);
end;

procedure TGlimpseStatusBar.WMSetCursor(var Msg: TWMSetCursor);
var
  Pt: TPoint;
  PanelLeft, HitIdx: Integer;
  Kind: TStatusBarTokenKind;
begin
  {Paint the hand cursor over panels whose backing token is interactive.
   Only intercept hits on the bar's client area — child controls (the
   embedded TProgressBar) keep their default cursor. We can't rely on
   Cursor := crHandPoint at the control level because that would apply
   the cursor uniformly across every panel.}
  if (Msg.HitTest = HTCLIENT) and Assigned(FOnQueryPanelKind) then
  begin
    GetCursorPos(Pt);
    Pt := ScreenToClient(Pt);
    HitIdx := StatusBarPanelHitTest(Self, Pt.X, PanelLeft);
    if HitIdx >= 0 then
    begin
      Kind := FOnQueryPanelKind(HitIdx);
      if Kind in [tkSaveDimension, tkCopyDimension] then
      begin
        Winapi.Windows.SetCursor(LoadCursor(0, IDC_HAND));
        Msg.Result := 1;
        Exit;
      end;
    end;
  end;
  inherited;
end;

end.
