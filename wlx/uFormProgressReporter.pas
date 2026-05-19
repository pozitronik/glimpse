{Form-side IProgressReporter implementation.

 Step 107 (N1): wires TSaveResolutionExtractor's lifecycle into the
 form's TProgressIndicator. Used by TPluginForm.WithReExtract; could
 also serve any future caller that needs to drive the form's progress
 widget from a worker context.

 Lifetime: held as an IInterface inside WithReExtract; auto-released
 at scope end. TInterfacedObject-based ref counting is fine here
 because the reporter holds NO state of its own — the TProgressIndicator
 reference is borrowed (form owns the indicator), so a late release
 is harmless.}
unit uFormProgressReporter;

interface

uses
  uProgressReporter, uProgressIndicator;

type
  TFormProgressReporter = class(TInterfacedObject, IProgressReporter)
  strict private
    FIndicator: TProgressIndicator;
  public
    constructor Create(AIndicator: TProgressIndicator);
    procedure Start(const AStatusText: string; ATotalSteps: Integer);
    procedure Advance(AStepIndex: Integer);
    procedure Pump;
    procedure Complete;
  end;

implementation

uses
  Vcl.ComCtrls, Vcl.Forms;

constructor TFormProgressReporter.Create(AIndicator: TProgressIndicator);
begin
  inherited Create;
  FIndicator := AIndicator;
end;

procedure TFormProgressReporter.Start(const AStatusText: string; ATotalSteps: Integer);
begin
  {AStatusText is currently ignored — the form's progress widget has
   no visible label panel (status text shows in the modal host dialog
   that the form runs around the reporter, not in the bar itself).
   Wiring AStatusText into a future status-bar label panel would be
   a one-line change here. Kept in the interface signature for that
   future extension.}
  FIndicator.ProgressBar.Style := pbstNormal;
  FIndicator.ProgressBar.Min := 0;
  FIndicator.ProgressBar.Max := ATotalSteps;
  FIndicator.ProgressBar.Position := 0;
  FIndicator.Show;
end;

procedure TFormProgressReporter.Advance(AStepIndex: Integer);
begin
  FIndicator.ProgressBar.Position := AStepIndex;
end;

procedure TFormProgressReporter.Pump;
begin
  Application.ProcessMessages;
end;

procedure TFormProgressReporter.Complete;
begin
  FIndicator.Hide;
end;

end.
