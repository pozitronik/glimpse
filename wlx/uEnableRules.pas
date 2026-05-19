{Declarative enable-rule table for VCL form control groups. A TEnableRule
 pairs a Boolean predicate (closure that reads live control state) with the
 controls whose .Enabled property tracks it.}
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
