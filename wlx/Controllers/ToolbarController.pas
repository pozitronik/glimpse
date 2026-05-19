{Toolbar controller for TPluginForm. Owns the TToolbarGlyphLibrary
 and the orchestration glue (Build / Layout / HamburgerClick /
 UpdateButtonEnables). Widget references stay cached on the form.}
unit ToolbarController;

interface

uses
  System.SysUtils, System.Classes,
  Winapi.Windows,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Buttons, Vcl.ComCtrls,
  Types,
  ToolbarBuilder, ToolbarGlyphLibrary;

type
  {Returns whether the button with ATag should be enabled — keeps the
   controller decoupled from the form's command-descriptor + policy table.}
  TButtonEnableCallback = reference to function(ATag: Integer): Boolean;

  TToolbarController = class
  strict private
    FFormOwner: TForm;
    FGlyphLibrary: TToolbarGlyphLibrary;
    FBuildResult: TToolbarHandles;
    FElementRights: TArray<Integer>;
    FFrameCountRight: Integer;
    FVisibleElementCount: Integer;
    FHamburgerMenuOpen: Boolean;
  public
    constructor Create(AFormOwner: TForm);
    destructor Destroy; override;

    {Returns the build result so the form can cache its widget pointers.}
    function Build(const AOnModeClick, AOnSizingMenu, AOnTimecodeClick,
      AOnToolbarButton, AOnContextMenu, AOnViewDropdown,
      AOnHamburgerClick, AOnHamburgerMenuPopup: TNotifyEvent): TToolbarHandles;

    procedure Layout(AClientWidth, ACtrlGap: Integer);

    {Re-entry guarded; the keyboard hook install/uninstall is inside the guard.}
    procedure HamburgerClick;

    procedure UpdateButtonEnables(const AIsAllowedByTag: TButtonEnableCallback);

    property GlyphLibrary: TToolbarGlyphLibrary read FGlyphLibrary;
    property VisibleElementCount: Integer read FVisibleElementCount;
  end;

implementation

uses
  System.Types,
  ToolbarLayout, KeyInterceptionSubclass;

constructor TToolbarController.Create(AFormOwner: TForm);
begin
  inherited Create;
  FFormOwner := AFormOwner;
end;

destructor TToolbarController.Destroy;
begin
  {FGlyphLibrary is owned by FFormOwner via TComponent ownership —
   explicit Free here would double-free.}
  inherited;
end;

function TToolbarController.Build(const AOnModeClick, AOnSizingMenu,
  AOnTimecodeClick, AOnToolbarButton, AOnContextMenu, AOnViewDropdown,
  AOnHamburgerClick, AOnHamburgerMenuPopup: TNotifyEvent): TToolbarHandles;
var
  Builder: TToolbarBuilder;
begin
  FGlyphLibrary := TToolbarGlyphLibrary.Create(FFormOwner);
  Builder := TToolbarBuilder.Create(FFormOwner, FGlyphLibrary,
    AOnModeClick, AOnSizingMenu, AOnTimecodeClick,
    AOnToolbarButton, AOnContextMenu, AOnViewDropdown,
    AOnHamburgerClick, AOnHamburgerMenuPopup);
  try
    FBuildResult := Builder.Build;
  finally
    Builder.Free;
  end;
  FElementRights := FBuildResult.ElementRights;
  FFrameCountRight := FBuildResult.FrameCountRight;
  Result := FBuildResult;
end;

procedure TToolbarController.Layout(AClientWidth, ACtrlGap: Integer);
var
  LayoutResult: TToolbarLayoutResult;
  VM: TViewMode;
  I: Integer;
begin
  if FBuildResult.BtnHamburger = nil then
    Exit;

  LayoutResult := ComputeToolbarLayout(AClientWidth, FElementRights,
    FFrameCountRight, FBuildResult.BtnHamburger.Width, ACtrlGap);
  FVisibleElementCount := LayoutResult.VisibleCount;

  for VM := Low(TViewMode) to High(TViewMode) do
    FBuildResult.ModeButtons[VM].Visible := Ord(VM) < LayoutResult.VisibleCount;

  FBuildResult.BtnTimecode.Visible := ELEM_TIMECODE_INDEX < LayoutResult.VisibleCount;

  for I := 0 to High(FBuildResult.ToolbarButtons) do
    FBuildResult.ToolbarButtons[I].Visible := (ELEM_ACTION_FIRST + I) < LayoutResult.VisibleCount;

  FBuildResult.BtnHamburger.Visible := LayoutResult.HamburgerVisible;
  FBuildResult.BtnHamburger.Left := LayoutResult.HamburgerLeft;
end;

procedure TToolbarController.HamburgerClick;
var
  P: TPoint;
  Hook: HHOOK;
begin
  if FHamburgerMenuOpen then
    Exit;
  FHamburgerMenuOpen := True;
  Hook := InstallMenuKeyboardHook;
  try
    P := FBuildResult.BtnHamburger.ClientToScreen(
      Point(0, FBuildResult.BtnHamburger.Height));
    FBuildResult.HamburgerMenu.Popup(P.X, P.Y);
  finally
    UninstallMenuKeyboardHook(Hook);
    FHamburgerMenuOpen := False;
  end;
end;

procedure TToolbarController.UpdateButtonEnables(const AIsAllowedByTag: TButtonEnableCallback);
var
  I: Integer;
begin
  if not Assigned(AIsAllowedByTag) then
    Exit;
  for I := 0 to High(FBuildResult.ToolbarButtons) do
    FBuildResult.ToolbarButtons[I].Enabled := AIsAllowedByTag(FBuildResult.ToolbarButtons[I].Tag);
end;

end.
