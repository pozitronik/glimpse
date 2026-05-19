{Progress-bar widget controller for TPluginForm. Owns a TProgressBar
 parented on the status bar and recomputes its bounds via
 StatusBarLayout.ResolveProgressBarBounds.}
unit ProgressIndicator;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.ComCtrls,
  StatusBarLayout;

type
  {Returns whether the status bar should stay visible AFTER a Hide call.}
  TStatusBarVisibilityCallback = reference to function: Boolean;

  {Read on every Reposition so settings changes between Show and the next
   Reposition take effect immediately.}
  TStatusBarLayoutCallback = reference to function(out AStretch: Boolean;
    out ALayout: TProgressBarLayout): Boolean;

  TProgressIndicator = class
  strict private
    FStatusBar: TStatusBar;
    FProgressBar: TProgressBar;
    FVisible: Boolean;
    FOnPostHideVisibility: TStatusBarVisibilityCallback;
    FOnQueryLayout: TStatusBarLayoutCallback;
  public
    constructor Create(AStatusBar: TStatusBar;
      const AOnPostHideVisibility: TStatusBarVisibilityCallback;
      const AOnQueryLayout: TStatusBarLayoutCallback);
    {Idempotent — re-Show on a visible indicator just re-runs Reposition.}
    procedure Show;
    procedure Hide;
    {No-op when the indicator is not visible.}
    procedure Reposition;
    property ProgressBar: TProgressBar read FProgressBar;
    property Visible: Boolean read FVisible;
  end;

implementation

const
  PROGRESSBAR_MIN_W = 40; {Minimum width before clamping the embedded progress bar.}
  PROGRESSBAR_MARGIN = 1; {Tiny inset so the bar doesn't touch the status bar's borders.}

constructor TProgressIndicator.Create(AStatusBar: TStatusBar;
  const AOnPostHideVisibility: TStatusBarVisibilityCallback;
  const AOnQueryLayout: TStatusBarLayoutCallback);
begin
  inherited Create;
  FStatusBar := AStatusBar;
  FOnPostHideVisibility := AOnPostHideVisibility;
  FOnQueryLayout := AOnQueryLayout;
  FProgressBar := TProgressBar.Create(AStatusBar);
  FProgressBar.Parent := AStatusBar;
  FProgressBar.Visible := False;
end;

procedure TProgressIndicator.Show;
begin
  FStatusBar.Visible := True;
  FVisible := True;
  Reposition;
  FProgressBar.Visible := True;
end;

procedure TProgressIndicator.Hide;
begin
  FProgressBar.Visible := False;
  FVisible := False;
  if Assigned(FOnPostHideVisibility) then
    FStatusBar.Visible := FOnPostHideVisibility;
end;

procedure TProgressIndicator.Reposition;
var
  PanelsRight, I: Integer;
  Stretch: Boolean;
  Layout: TProgressBarLayout;
  Bounds: TProgressBarBounds;
begin
  if not FVisible then
    Exit;
  if not Assigned(FOnQueryLayout) or not FOnQueryLayout(Stretch, Layout) then
    Exit;
  {Right edge of the last panel — computed live so adding or removing
   a panel in UpdateStatusBar needs no separate bookkeeping here.}
  PanelsRight := 0;
  for I := 0 to FStatusBar.Panels.Count - 1 do
    Inc(PanelsRight, FStatusBar.Panels[I].Width);
  Bounds := ResolveProgressBarBounds(FStatusBar.ClientWidth, FStatusBar.ClientHeight,
    PanelsRight, Stretch, Layout, PROGRESSBAR_MIN_W, PROGRESSBAR_MARGIN);
  FProgressBar.SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
end;

end.
