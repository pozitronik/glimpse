{Declarative enable-rule table for VCL form control groups.

 Seven hand-written UpdateXxxControls methods in TSettingsForm all
 encoded the same pattern: "enable a group of related controls based on
 a master toggle". This unit collapses that pattern: a TEnableRule pairs
 a Boolean predicate with the controls whose .Enabled property tracks
 it; ApplyEnableRules walks the array.

 Predicates are TFunc<Boolean> closures so they can read live control
 state (e.g. `function: Boolean begin Result := ChkX.Checked end`) at
 evaluation time. The table is built once at form construction (after
 the DFM-defined controls exist) and recomputed on every relevant
 user change.}
unit uEnableRules;

interface

uses
  System.SysUtils, Vcl.Controls;

type
  TEnableRule = record
    Predicate: TFunc<Boolean>;
    Controls: TArray<TControl>;
  end;

  TEnableRules = TArray<TEnableRule>;

{Walks the rule array; each rule's predicate is evaluated once and the
 result is written to .Enabled of every listed control. Cost is one
 closure call plus one VCL property write per affected control —
 negligible next to the original per-method overhead.}
procedure ApplyEnableRules(const ARules: TEnableRules);

implementation

procedure ApplyEnableRules(const ARules: TEnableRules);
var
  I, J: Integer;
  IsEnabled: Boolean;
begin
  for I := 0 to High(ARules) do
  begin
    IsEnabled := ARules[I].Predicate();
    for J := 0 to High(ARules[I].Controls) do
      ARules[I].Controls[J].Enabled := IsEnabled;
  end;
end;

end.
