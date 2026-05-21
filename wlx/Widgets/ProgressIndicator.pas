{Progress-bar widget controller for TPluginForm.}
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
  strict protected
    function GetVisible: Boolean; virtual;
    function GetProgressBar: TProgressBar; virtual;
  public
    procedure Show; virtual;
    procedure Hide; virtual;
    procedure Reposition; virtual;
    {Configure the bar for a determinate run of ATotalSteps, then track
     progress with SetStep. The Null base no-ops both, so callers need no
     subclass check.}
    procedure BeginSteps(ATotalSteps: Integer); virtual;
    procedure SetStep(AStepIndex: Integer); virtual;
    property ProgressBar: TProgressBar read GetProgressBar;
    property Visible: Boolean read GetVisible;
  end;

  TStatusBarProgressIndicator = class(TProgressIndicator)
  strict private
    FStatusBar: TStatusBar;
    FProgressBar: TProgressBar;
    FVisible: Boolean;
    FOnPostHideVisibility: TStatusBarVisibilityCallback;
    FOnQueryLayout: TStatusBarLayoutCallback;
  strict protected
    function GetVisible: Boolean; override;
    function GetProgressBar: TProgressBar; override;
  public
    constructor Create(AStatusBar: TStatusBar;
      const AOnPostHideVisibility: TStatusBarVisibilityCallback;
      const AOnQueryLayout: TStatusBarLayoutCallback);
    {Idempotent — re-Show on a visible indicator just re-runs Reposition.}
    procedure Show; override;
    procedure Hide; override;
    {No-op when the indicator is not visible.}
    procedure Reposition; override;
    procedure BeginSteps(ATotalSteps: Integer); override;
    procedure SetStep(AStepIndex: Integer); override;
  end;

implementation

const
  PROGRESSBAR_MIN_W = 40;
  PROGRESSBAR_MARGIN = 1;

{TProgressIndicator}

function TProgressIndicator.GetVisible: Boolean;
begin
  Result := False;
end;

function TProgressIndicator.GetProgressBar: TProgressBar;
begin
  Result := nil;
end;

procedure TProgressIndicator.Show;
begin
end;

procedure TProgressIndicator.Hide;
begin
end;

procedure TProgressIndicator.Reposition;
begin
end;

procedure TProgressIndicator.BeginSteps(ATotalSteps: Integer);
begin
end;

procedure TProgressIndicator.SetStep(AStepIndex: Integer);
begin
end;

{TStatusBarProgressIndicator}

constructor TStatusBarProgressIndicator.Create(AStatusBar: TStatusBar;
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

function TStatusBarProgressIndicator.GetVisible: Boolean;
begin
  Result := FVisible;
end;

function TStatusBarProgressIndicator.GetProgressBar: TProgressBar;
begin
  Result := FProgressBar;
end;

procedure TStatusBarProgressIndicator.Show;
begin
  FStatusBar.Visible := True;
  FVisible := True;
  Reposition;
  FProgressBar.Visible := True;
end;

procedure TStatusBarProgressIndicator.Hide;
begin
  FProgressBar.Visible := False;
  FVisible := False;
  if Assigned(FOnPostHideVisibility) then
    FStatusBar.Visible := FOnPostHideVisibility;
end;

procedure TStatusBarProgressIndicator.Reposition;
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
  PanelsRight := 0;
  for I := 0 to FStatusBar.Panels.Count - 1 do
    Inc(PanelsRight, FStatusBar.Panels[I].Width);
  Bounds := ResolveProgressBarBounds(FStatusBar.ClientWidth, FStatusBar.ClientHeight,
    PanelsRight, Stretch, Layout, PROGRESSBAR_MIN_W, PROGRESSBAR_MARGIN);
  FProgressBar.SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
end;

procedure TStatusBarProgressIndicator.BeginSteps(ATotalSteps: Integer);
begin
  FProgressBar.Style := pbstNormal;
  FProgressBar.Min := 0;
  FProgressBar.Max := ATotalSteps;
  FProgressBar.Position := 0;
end;

procedure TStatusBarProgressIndicator.SetStep(AStepIndex: Integer);
begin
  FProgressBar.Position := AStepIndex;
end;

end.
