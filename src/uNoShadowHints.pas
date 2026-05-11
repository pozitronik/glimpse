{Replaces VCL's default THintWindow with a variant that does not register
 the CS_DROPSHADOW window class style.

 Why: CS_DROPSHADOW asks Windows to render a drop shadow under the hint
 window onto whatever sits below it. The shadow pixels live on the
 underlying surface (DWM-composited or GDI), not inside the hint's own
 client area. When the hint hides, Windows is supposed to invalidate the
 shadow region so the host repaints it. In a hosted-DLL scenario (TC owns
 the windows under our hints, our Application.Handle is an invisible
 sibling) that invalidate is brittle and a "ghost" rectangle can survive
 on screen until something else repaints the area. The visible artefact
 is intermittent shadow remnants that linger across window switches and
 sometimes for the host process's whole lifetime.

 Removing CS_DROPSHADOW gives flat tooltips and removes the source of the
 bug entirely. No ongoing maintenance, no per-hide invalidation hack.

 The unit is pure side-effects: just being included in the DLL's uses
 chain installs the replacement via HintWindowClass during initialization.}
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
