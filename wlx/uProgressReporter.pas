{Narrow progress-reporting interface.

 Step 107 (N1): replaces the 4 separate anonymous-method event types
 TSaveResolutionExtractor previously exposed (OnLabel + OnProgress +
 OnPump + OnDone) with a single cohesive interface. Hosts implement
 the interface to wire their own progress UI; the extractor calls
 Start once at the beginning, Advance once per item, Pump after each
 advance so a hosted modal can stay responsive, and Complete at the
 end.

 The plan also mentioned a Fail hook. Skipped on purpose — the
 existing extractor surfaces failures by raising an exception (caller
 catches in the WithReExtract finally block); adding a speculative
 Fail method nobody calls today would be over-spec'd.}
unit uProgressReporter;

interface

type
  IProgressReporter = interface
    ['{8B5C4F3A-2D7E-4E8B-A1F2-9C3D5A7B2F11}']
    {Begins reporting for ATotalSteps items. AStatusText is shown to
     the user (typically a "Re-extracting N frames..." message).}
    procedure Start(const AStatusText: string; ATotalSteps: Integer);
    {Reports that AStepIndex (0-based) is complete. Hosts typically
     update a progress bar's Position.}
    procedure Advance(AStepIndex: Integer);
    {Drains the host's message queue so the UI stays responsive between
     work items. Hosts typically call Application.ProcessMessages.}
    procedure Pump;
    {Signals end of work. Hosts typically hide their progress widget.}
    procedure Complete;
  end;

implementation

end.
