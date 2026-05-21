{Viewport-refresh debounce helper for TPluginForm. The helper holds the
 last extraction max-side; the debounce fires AShouldRefresh + AComputeMaxSide
 and only invokes AOnRefresh when the size actually changed.}
unit ViewportRefreshDebouncer;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.ExtCtrls;

type
  {Re-checked when the debounce fires; False short-circuits silently.}
  TPreconditionCheck = reference to function: Boolean;

  TMaxSideComputer = reference to function: Integer;

  TViewportRefreshAction = reference to procedure;

  TViewportRefreshDebouncer = class
  strict private
    FTimer: TTimer;
    FLastExtractionMaxSide: Integer;
    FShouldRefresh: TPreconditionCheck;
    FComputeMaxSide: TMaxSideComputer;
    FOnRefresh: TViewportRefreshAction;
    procedure TimerFired(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; ADebounceMs: Integer;
      const AShouldRefresh: TPreconditionCheck;
      const AComputeMaxSide: TMaxSideComputer;
      const AOnRefresh: TViewportRefreshAction);
    destructor Destroy; override;
    {Kick (or re-kick) the debounce countdown.}
    procedure Schedule;
    {Sets the baseline for the next debounce-fire size comparison.}
    procedure RecordExtractionMaxSide(AValue: Integer);
    property LastExtractionMaxSide: Integer read FLastExtractionMaxSide;
  end;

implementation

constructor TViewportRefreshDebouncer.Create(AOwner: TComponent; ADebounceMs: Integer;
  const AShouldRefresh: TPreconditionCheck;
  const AComputeMaxSide: TMaxSideComputer;
  const AOnRefresh: TViewportRefreshAction);
begin
  inherited Create;
  FShouldRefresh := AShouldRefresh;
  FComputeMaxSide := AComputeMaxSide;
  FOnRefresh := AOnRefresh;
  FTimer := TTimer.Create(AOwner);
  FTimer.Interval := ADebounceMs;
  FTimer.OnTimer := TimerFired;
  FTimer.Enabled := False;
end;

destructor TViewportRefreshDebouncer.Destroy;
begin
  {FTimer is owned by AOwner; drop the callback so a WM_TIMER still
   queued when this debouncer is freed cannot fire TimerFired into
   freed memory.}
  if Assigned(FTimer) then
  begin
    FTimer.Enabled := False;
    FTimer.OnTimer := nil;
  end;
  inherited;
end;

procedure TViewportRefreshDebouncer.Schedule;
begin
  if not Assigned(FShouldRefresh) or not FShouldRefresh then
    Exit;
  {Toggle Enabled to reset the internal countdown.}
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TViewportRefreshDebouncer.RecordExtractionMaxSide(AValue: Integer);
begin
  FLastExtractionMaxSide := AValue;
end;

procedure TViewportRefreshDebouncer.TimerFired(Sender: TObject);
var
  NewMaxSide: Integer;
begin
  FTimer.Enabled := False;
  {Preconditions may have flipped between the trigger and firing; re-check.}
  if not Assigned(FShouldRefresh) or not FShouldRefresh then
    Exit;
  if not Assigned(FComputeMaxSide) then
    Exit;
  NewMaxSide := FComputeMaxSide;
  {Same size bucket: cached frames already match — no work needed.}
  if NewMaxSide = FLastExtractionMaxSide then
    Exit;
  if Assigned(FOnRefresh) then
    FOnRefresh;
end;

end.
