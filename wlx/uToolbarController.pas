{Toolbar controller for TPluginForm.

 Step 105 (C1, partial): the first of the planned 4-controller split
 of TPluginForm. After step 87's earlier extraction (TToolbarBuilder +
 TToolbarGlyphLibrary + TToolbarLayout pure helper), what remained on
 the form was glue: construct via the builder, lay out via the helper,
 handle the hamburger click, and update per-button enable state from
 the command table. This controller owns that glue plus the
 TToolbarGlyphLibrary lifetime.

 What lives here:
   - FGlyphLibrary (owned: created in Build, freed in destructor).
   - Toolbar layout state (FElementRights, FFrameCountRight,
     FVisibleElementCount) — values produced by TToolbarBuilder, read
     by Layout to compute per-button visibility.
   - FHamburgerMenuOpen re-entry guard.
   - The four orchestration methods: Build, Layout, HamburgerClick,
     UpdateButtonEnables.

 What stays on TPluginForm:
   - Cached widget references (FToolbar, FToolbarButtons, FBtnHamburger,
     FBtnTimecode, FModeButtons, etc.) populated from the controller's
     Build result and consumed at ~90 call sites across the form.
     These are non-owning pointer aliases; the widget components are
     owned by the form via TComponent.Owner. Keeping the cached fields
     avoids rewriting every call site through controller accessors.
   - The hamburger sub-handlers (OnHamburgerModeClick, OnHamburgerZoomClick,
     OnHamburgerActionClick, OnHamburgerMenuPopup) — they reach form
     state to dispatch commands and compose menu items.
   - The DFM-wired event handlers passed to Build as callbacks.}
unit uToolbarController;

interface

uses
  System.SysUtils, System.Classes,
  Winapi.Windows,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Buttons, Vcl.ComCtrls,
  uTypes,
  uToolbarBuilder, uToolbarGlyphLibrary;

type
  {Form-side callback that asks "should the button with this command
   tag be enabled right now?". Decouples the controller from the form's
   command-descriptor table + policy evaluator (which reach into form
   state the controller has no business knowing about).}
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

    {Constructs the toolbar via TToolbarBuilder. AHandlers carries the
     form's event handlers (mode click, sizing menu, timecode click,
     toolbar button click, context menu click, view-dropdown popup,
     hamburger click, hamburger menu popup) — the controller does NOT
     own those handlers, only wires them to the appropriate widgets at
     build time. Returns the build result so the form can cache its
     widget pointers (see unit docstring).}
    function Build(const AOnModeClick, AOnSizingMenu, AOnTimecodeClick,
      AOnToolbarButton, AOnContextMenu, AOnViewDropdown,
      AOnHamburgerClick, AOnHamburgerMenuPopup: TNotifyEvent): TToolbarHandles;

    {Recomputes per-button visibility + the hamburger overflow's
     placement after a width change. AClientWidth is the toolbar
     panel's current ClientWidth (passed in rather than read from a
     cached toolbar pointer to keep the controller decoupled from the
     form's caching). ACtrlGap is the horizontal spacing constant the
     form uses (8 px today). Updates FVisibleElementCount as a
     side effect; readable via VisibleElementCount.}
    procedure Layout(AClientWidth, ACtrlGap: Integer);

    {Pops the hamburger overflow menu under the hamburger button.
     Guards against re-entry via FHamburgerMenuOpen. The keyboard hook
     install/uninstall is intentionally inside the guarded region.}
    procedure HamburgerClick;

    {Walks each toolbar button and sets its Enabled state by asking
     AIsAllowedByTag. Buttons whose tag is not recognised default to
     Enabled := True (same fallback as the previous form-side method).
     Decouples the controller from the form's command-descriptor table.}
    procedure UpdateButtonEnables(const AIsAllowedByTag: TButtonEnableCallback);

    property GlyphLibrary: TToolbarGlyphLibrary read FGlyphLibrary;
    property VisibleElementCount: Integer read FVisibleElementCount;
  end;

implementation

uses
  System.Types,
  uToolbarLayout, uKeyInterceptionSubclass;

constructor TToolbarController.Create(AFormOwner: TForm);
begin
  inherited Create;
  FFormOwner := AFormOwner;
end;

destructor TToolbarController.Destroy;
begin
  {FGlyphLibrary is owned by FFormOwner (passed as the TComponent owner
   in Build) so it is freed by the form's inherited destructor. Explicit
   .Free here would double-free.}
  inherited;
end;

function TToolbarController.Build(const AOnModeClick, AOnSizingMenu,
  AOnTimecodeClick, AOnToolbarButton, AOnContextMenu, AOnViewDropdown,
  AOnHamburgerClick, AOnHamburgerMenuPopup: TNotifyEvent): TToolbarHandles;
var
  Builder: TToolbarBuilder;
begin
  {Glyph library owns the shared TImageList that paints the hamburger
   button, the arrow-bearing mode buttons, and the matching menu items
   on the hamburger overflow. Owned by FFormOwner so the form's
   inherited destructor releases it.}
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

  {Per-button visibility based on element index. Indices match the order
   produced by TToolbarBuilder; ELEM_TIMECODE_INDEX + ELEM_ACTION_FIRST
   live in uToolbarLayout for the same reason.}
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
