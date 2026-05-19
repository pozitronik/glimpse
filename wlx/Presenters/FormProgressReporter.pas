{Form-side IProgressReporter — drives the form's TProgressIndicator.
 The indicator reference is borrowed (form owns it), so the reporter's
 ref-counted lifetime can outlive its useful scope without harm.}
unit FormProgressReporter;

interface

uses
  ProgressReporter, ProgressIndicator;

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
  {AStatusText is ignored: the form's progress widget has no label panel.}
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
