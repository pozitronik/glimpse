{Progress-bar widget controller for TPluginForm.

 Step 105 (C1, part 3 of 4): focused mini-extraction of the
 progress-bar widget that floats over the status bar during extraction
 + clipboard-write operations. Same honest scope as part 2 — the
 status-bar controller envisioned by the plan resists clean extraction
 because BuildStatusBarValues / ApplyStatusBarSettings / UpdateStatusBar
 reach into ~25 form fields. This helper extracts only the progress-
 bar concern, which has clean boundaries: own a TProgressBar parented
 on the status bar, manage its visibility flag, recompute its bounds
 via the pure uStatusBarLayout.ResolveProgressBarBounds helper, and
 surface a tiny API the form drives explicitly.

 The form retains UpdateProgress (its body mixes progress-bar updates
 with toolbar-button updates and the FrameView animation timer — too
 cross-cluster to lift cleanly). UpdateProgress calls into this helper
 for the progress-bar bits only.

 Lifetime: helper is owned by the form (TComponent ownership). The
 TProgressBar inside the helper is in turn owned by the status bar
 (TComponent parent ownership) so VCL handles its release. Show/Hide
 are reentrancy-safe.}
unit uProgressIndicator;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.ComCtrls,
  uStatusBarLayout;

type
  {Returns whether the status bar should be visible AFTER a Hide call.
   The form computes ShowStatusBar AND NOT (QuickView AND QVHide) at
   call time so the helper doesn't need to know about the form's
   quick-view mode or the QVHideStatusBar setting.}
  TStatusBarVisibilityCallback = reference to function: Boolean;

  {Returns the current (stretch, layout) pair the form's settings
   expose. Read at every Reposition so a settings change between
   Show and the next Reposition takes effect immediately.}
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
    {Forces the status bar visible, marks the indicator visible,
     repositions the progress bar inside the status bar, then makes
     the progress bar itself visible. Idempotent: a second Show on
     an already-visible indicator just re-runs the reposition.}
    procedure Show;
    {Hides the progress bar, clears the visible flag, then lets the
     post-hide callback decide whether the status bar itself should
     stay visible (depends on the user's ShowStatusBar setting and
     whether the form is in Quick View mode).}
    procedure Hide;
    {Recomputes the progress-bar bounds against the status bar's
     current dimensions + the form's stretch/layout settings. No-op
     when the indicator is not visible.}
    procedure Reposition;
    {Direct accessor for callers that need to set Style/Min/Max/Position
     on the bar directly (WithReExtract, UpdateProgress). Returning the
     widget rather than wrapping every TProgressBar property keeps the
     wrapper thin.}
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
  {Right edge of the last panel — the boundary the AfterPanels layout
   needs to clear. Computed from the live panel widths so adding or
   removing a panel in UpdateStatusBar requires no separate
   bookkeeping here.}
  PanelsRight := 0;
  for I := 0 to FStatusBar.Panels.Count - 1 do
    Inc(PanelsRight, FStatusBar.Panels[I].Width);
  Bounds := ResolveProgressBarBounds(FStatusBar.ClientWidth, FStatusBar.ClientHeight,
    PanelsRight, Stretch, Layout, PROGRESSBAR_MIN_W, PROGRESSBAR_MARGIN);
  FProgressBar.SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
end;

end.
