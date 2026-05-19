{TStatusBar specialisation that surfaces per-panel hints and a hand cursor
 over interactive tokens. The hint mechanism drives CMHintShow's CursorRect
 so the VCL re-issues CMHintShow on cross-panel moves, avoiding the
 unreliable "set Hint + CancelHint" dance.}
unit uStatusBarHostBar;

interface

uses
  System.Classes, System.Types,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.ComCtrls,
  uStatusBarTokens;

type
  {APanelIndex is 0-based; -1 when past the last panel.}
  TStatusBarHintProvider = reference to function(APanelIndex: Integer): string;

  {Returns tkUnknown for unmapped indices (cursor logic treats as non-interactive).}
  TStatusBarPanelKindProvider = reference to function(APanelIndex: Integer): TStatusBarTokenKind;

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

{Returns the panel index under AX, or -1 when past the last panel.
 APanelLeft = left edge of the matched panel, or the right edge of the
 last panel for past-end (so callers can compose a "trailing dead zone").}
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
    {Suppress popup but keep a tight CursorRect so cross-panel moves re-query.}
    Msg.Result := 1;
  end else begin
    Msg.HintInfo.HintStr := HintText;
    Msg.Result := 0;
  end;

  if HitIdx >= 0 then
    Msg.HintInfo.CursorRect := Rect(PanelLeft, 0, PanelLeft + Panels[HitIdx].Width, Height)
  else
    {Past-last: cursor rect is the trailing dead zone.}
    Msg.HintInfo.CursorRect := Rect(PanelLeft, 0, ClientWidth, Height);
end;

procedure TGlimpseStatusBar.WMSetCursor(var Msg: TWMSetCursor);
var
  Pt: TPoint;
  PanelLeft, HitIdx: Integer;
  Kind: TStatusBarTokenKind;
begin
  {Hand cursor only over interactive-token panels. Cursor := crHandPoint
   at the control level would apply uniformly across every panel, so we
   intercept per-panel here. Skip child controls (embedded TProgressBar).}
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
