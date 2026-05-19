{Viewport-refresh debounce helper for TPluginForm.

 Step 105 (C1, part 2 of 4): one of two small focused extractions from
 the form's extraction cluster. The cluster as a whole resists clean
 controller-style decomposition because its methods are heavily
 intertwined with FFrameView / FSettings / FProgressBar / FExporter /
 FExtractCtrl / FOffsets / FVideoInfo / FFileName / FFFmpegPath /
 FServices state; lifting the whole thing would either drag a form
 back-reference into the controller or invent ~10 callback interfaces.
 This helper extracts only the part that does have clean boundaries:
 the viewport-refresh debounce + the last-extraction-size memo that
 lets the debounce decide whether the viewport actually changed.

 The form passes 3 callbacks at construction:
   - AShouldRefresh: re-checks preconditions when the debounce fires
     (settings nil, auto-refresh off, scaled-extraction off, no video
     info, no filename, no offsets - any of these short-circuits).
   - AComputeMaxSide: returns the current viewport's max-side, which
     the helper compares against the last recorded extraction size.
   - AOnRefresh: invoked when the comparison shows a size change.
     The form wires this to SoftRefreshExtraction.

 Lifetime: the helper owns a TTimer; both are TComponent-owned by
 AOwner (the form passes Self). Cleaned up via inherited destructor.}
unit uViewportRefreshDebouncer;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.ExtCtrls;

type
  {Returns True to proceed with the refresh check, False to short-circuit
   silently. The form reads its FSettings / FVideoInfo / FFileName state
   to decide.}
  TPreconditionCheck = reference to function: Boolean;

  {Computes the viewport's current max-side. The form combines its
   scrollbox dimensions, view mode, offsets count, frame view aspect,
   video pixel dimensions, and settings min/max into a single number.}
  TMaxSideComputer = reference to function: Integer;

  {Fired when the debounce timer settles AND preconditions hold AND
   the computed max-side differs from the last recorded extraction
   max-side. The form wires this to SoftRefreshExtraction.}
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
    {Kick (or re-kick) the debounce countdown. Every viewport-changing
     event calls this; when the events stop arriving for ADebounceMs
     the timer fires and runs the (preconditions + size compare +
     refresh-or-not) sequence.}
    procedure Schedule;
    {Called by the form's StartExtraction after the new extraction size
     is determined, so the next debounce-fire comparison has a baseline.}
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

procedure TViewportRefreshDebouncer.Schedule;
begin
  if not Assigned(FShouldRefresh) or not FShouldRefresh then
    Exit;
  {Restart the countdown by toggling Enabled — setting False then True
   resets the internal timer.}
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
  {All preconditions can become false between the event that kicked the
   timer and the timer firing (form closed, auto-refresh disabled, etc.),
   so re-check before doing any work.}
  if not Assigned(FShouldRefresh) or not FShouldRefresh then
    Exit;
  if not Assigned(FComputeMaxSide) then
    Exit;
  NewMaxSide := FComputeMaxSide;
  {Same size bucket as the live extraction (viewport only jittered within
   one SCALE_BUCKET, or the view mode didn't actually change the
   divisor). Nothing to do — any cached frames are already at the right
   resolution.}
  if NewMaxSide = FLastExtractionMaxSide then
    Exit;
  if Assigned(FOnRefresh) then
    FOnRefresh;
end;

end.
