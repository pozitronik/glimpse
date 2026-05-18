{Tests for the declarative enable-rule table that replaced the cluster
 of UpdateXxxControls methods in TSettingsForm. Exercises ApplyEnableRules
 with synthetic TControl-derived doubles so the assertions are independent
 of any real settings dialog instance.}
unit TestEnableRules;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEnableRules = class
  public
    [Test] procedure ApplyEnableRules_AllControlsTrackPredicateResult;
    [Test] procedure ApplyEnableRules_MultipleRulesEvaluateIndependently;
    [Test] procedure ApplyEnableRules_EmptyRuleArray_NoOp;
    [Test] procedure ApplyEnableRules_RuleWithNoControls_StillEvaluatesPredicate;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.ExtCtrls,
  uEnableRules;

{TPanel is a convenient concrete TControl-derived class for tests:
 it can be created with a nil owner and freed individually, without
 dragging a parent form into the test harness.}

procedure TTestEnableRules.ApplyEnableRules_AllControlsTrackPredicateResult;
var
  CtrlA, CtrlB: TPanel;
  Toggle: Boolean;
  Rules: TEnableRules;
begin
  CtrlA := TPanel.Create(nil);
  CtrlB := TPanel.Create(nil);
  try
    {Initial state: both controls enabled (Vcl default).}
    Toggle := False;

    SetLength(Rules, 1);
    Rules[0].Predicate := function: Boolean begin Result := Toggle end;
    Rules[0].Controls := [TControl(CtrlA), TControl(CtrlB)];

    ApplyEnableRules(Rules);
    Assert.IsFalse(CtrlA.Enabled, 'CtrlA must follow predicate=False');
    Assert.IsFalse(CtrlB.Enabled, 'CtrlB must follow predicate=False');

    {Flip the captured variable; the closure re-reads it on next apply.}
    Toggle := True;
    ApplyEnableRules(Rules);
    Assert.IsTrue(CtrlA.Enabled, 'CtrlA must follow predicate=True');
    Assert.IsTrue(CtrlB.Enabled, 'CtrlB must follow predicate=True');
  finally
    CtrlA.Free;
    CtrlB.Free;
  end;
end;

procedure TTestEnableRules.ApplyEnableRules_MultipleRulesEvaluateIndependently;
var
  CtrlA, CtrlB: TPanel;
  ToggleA, ToggleB: Boolean;
  Rules: TEnableRules;
begin
  CtrlA := TPanel.Create(nil);
  CtrlB := TPanel.Create(nil);
  try
    {Each control is governed by its own predicate; flipping one must
     leave the other untouched. This pins the rule-independence
     guarantee that the production table relies on (e.g. the banner
     predicate must not bleed into the cache predicate).}
    ToggleA := True;
    ToggleB := False;

    SetLength(Rules, 2);
    Rules[0].Predicate := function: Boolean begin Result := ToggleA end;
    Rules[0].Controls := [TControl(CtrlA)];
    Rules[1].Predicate := function: Boolean begin Result := ToggleB end;
    Rules[1].Controls := [TControl(CtrlB)];

    ApplyEnableRules(Rules);
    Assert.IsTrue(CtrlA.Enabled, 'CtrlA tracks its own predicate');
    Assert.IsFalse(CtrlB.Enabled, 'CtrlB tracks its own predicate');

    {Swap the two predicates' values, confirm each control responds
     independently.}
    ToggleA := False;
    ToggleB := True;
    ApplyEnableRules(Rules);
    Assert.IsFalse(CtrlA.Enabled, 'CtrlA must flip with its predicate');
    Assert.IsTrue(CtrlB.Enabled, 'CtrlB must flip with its predicate');
  finally
    CtrlA.Free;
    CtrlB.Free;
  end;
end;

procedure TTestEnableRules.ApplyEnableRules_EmptyRuleArray_NoOp;
var
  Rules: TEnableRules;
begin
  {Defensive: an empty rule table must not raise (range-check, AV)
   and the caller can pass a brand-new field with no SetLength.}
  SetLength(Rules, 0);
  Assert.WillNotRaiseAny(
    procedure
    begin
      ApplyEnableRules(Rules);
    end);
end;

procedure TTestEnableRules.ApplyEnableRules_RuleWithNoControls_StillEvaluatesPredicate;
var
  Rules: TEnableRules;
  PredicateCalled: Boolean;
begin
  {A rule with an empty Controls array is legal and the implementation
   must still call the predicate. This pins behaviour against an
   accidental "skip predicate when nothing to apply" optimisation that
   would break diagnostics built on top of predicates with side effects.}
  PredicateCalled := False;

  SetLength(Rules, 1);
  Rules[0].Predicate := function: Boolean
    begin
      PredicateCalled := True;
      Result := True;
    end;
  Rules[0].Controls := [];

  ApplyEnableRules(Rules);
  Assert.IsTrue(PredicateCalled, 'Predicate must run even with no controls');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEnableRules);

end.
