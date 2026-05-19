{Replaces THintWindow with a variant without CS_DROPSHADOW.

 In a hosted-DLL scenario (TC owns the windows under our hints) the
 system's shadow-region invalidation on hide is brittle and "ghost"
 rectangles can linger across window switches. Removing CS_DROPSHADOW
 gives flat tooltips and eliminates the artefact.

 Pure side-effects: including the unit installs the replacement.}
unit uNoShadowHints;

interface

implementation

uses
  Winapi.Windows,
  Vcl.Controls, Vcl.Forms;

type
  TNoShadowHintWindow = class(THintWindow)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  end;

procedure TNoShadowHintWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.style := Params.WindowClass.style and not CS_DROPSHADOW;
end;

initialization
  HintWindowClass := TNoShadowHintWindow;

end.
