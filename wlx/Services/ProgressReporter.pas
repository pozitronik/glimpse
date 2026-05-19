{Narrow progress-reporting interface. Hosts implement to wire their own
 progress UI; failure is signalled by exception, not via this interface.}
unit ProgressReporter;

interface

type
  IProgressReporter = interface
    ['{8B5C4F3A-2D7E-4E8B-A1F2-9C3D5A7B2F11}']
    procedure Start(const AStatusText: string; ATotalSteps: Integer);
    {AStepIndex is 0-based.}
    procedure Advance(AStepIndex: Integer);
    {Drains the message queue between work items so the UI stays responsive.}
    procedure Pump;
    procedure Complete;
  end;

implementation

end.
