{Experimental: appends Glimpse's toolbar actions into TLister's own
 menu bar so the user can drive the plugin from TC's menu in addition
 to the in-form toolbar and configurable hotkeys.

 Two layouts (selected via TPluginSettings.ListerMenuFlat):
 - Submenu (default, ListerMenuFlat = False): a single new top-level
   "Glimpse" entry on the menu bar; all items live as children of that
   popup. Lower visual noise.
 - Flat (ListerMenuFlat = True): every action gets its own top-level
   entry on the menu bar. Pushes TC's existing menus rightward; mainly
   here so the user can A/B-test the two layouts.

 The extension installs its own window subclass on the parent (TLister)
 to intercept WM_COMMAND in the reserved range $C000..$C1FF. Standard
 Win32 menus require the command handler to live on the menu's owner
 window, which is the lister — not the plugin form.

 Quick View has no menu bar (the parent is the QV panel, not TLister),
 so the host MUST gate construction with not-FQuickViewMode and pass a
 valid parent HWND that owns a menu. The constructor checks
 GetMenu(AParentWnd) and is a near-no-op when the parent has none.}
unit ListerMenuExtension;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Generics.Collections,
  Types;

const
  {Reserved WM_COMMAND ID range. Well above standard Windows menu ID
   territory (typically <$8000) so we cannot collide with TC's own
   command IDs even on heavily-customised TC builds.}
  LISTER_MENU_CMD_BASE: Word = $C000;
  LISTER_MENU_CMD_LAST: Word = $C1FF;
  {SetWindowSubclass uIdSubclass for this extension. Distinct from
   ParentSubclassProc's id=1 so the two subclasses coexist on the
   same parent.}
  LISTER_MENU_SUBCLASS_ID = 10;

  GLIMPSE_MENU_CAPTION = '&Glimpse';

type
  {Each menu item dispatches to one of four host operations.}
  TListerMenuEntryKind = (lmekMode, lmekZoom, lmekTimecode, lmekAction);

  TListerMenuEntry = record
    Kind: TListerMenuEntryKind;
    Mode: TViewMode;
    Zoom: TZoomMode;
    ActionTag: Integer;
  end;

  {Invoked with the entry the user picked. The host translates each
   kind to its existing handler (ActivateMode / SetModeZoom /
   DoToggleTimecode / DispatchCommand).}
  TListerMenuDispatch = reference to procedure(const AEntry: TListerMenuEntry);

  TListerMenuExtension = class
  strict private
    FParentWnd: HWND;
    FParentMenu: HMENU;
    FFlatMode: Boolean;
    FDispatch: TListerMenuDispatch;
    {Position of the first top-level item we appended to FParentMenu,
     and how many top-level items we appended. Used for removal via
     MF_BYPOSITION (deleting in reverse order shifts the menu down
     each step, leaving the next-to-remove at the same start position).
     Assumes the parent menu is stable between Build and Destroy — TC
     does not mutate its lister menu, so this holds in practice.}
    FFirstPos: Integer;
    FItemCount: Integer;
    {Map from command ID to the entry payload, used by TryHandleCommand
     to look up which operation a clicked item maps to.}
    FEntries: TDictionary<Word, TListerMenuEntry>;
    FNextId: Word;
    function AllocIdFor(const AEntry: TListerMenuEntry): Word;
    procedure AddSeparator(ADest: HMENU);
    procedure AddPlainModeItem(ADest: HMENU; AMode: TViewMode);
    procedure AddModeWithZoomSubmenu(ADest: HMENU; AMode: TViewMode);
    procedure AddModeItems(ADest: HMENU);
    procedure AddTimecodeItem(ADest: HMENU);
    procedure AddActionItem(ADest: HMENU; AActionTag: Integer; const ACaption: string);
    procedure AddSaveViewSubmenu(ADest: HMENU);
    procedure AddCopyViewSubmenu(ADest: HMENU);
    procedure AddRefreshSubmenu(ADest: HMENU);
    procedure PopulateContents(ADest: HMENU);
    procedure BuildSubmenu;
    procedure BuildFlat;
    procedure InstallSubclass;
    procedure UninstallSubclass;
  public
    {AParentWnd is the TLister window. AFlatMode selects layout
     (False = submenu under one "Glimpse" entry, True = each item
     at top level). The dispatch callback is invoked on every click;
     the host translates the entry to its action.}
    constructor Create(AParentWnd: HWND; AFlatMode: Boolean;
      const ADispatch: TListerMenuDispatch);
    destructor Destroy; override;
    {Returns True if ACommandId was one of ours (dispatched). The
     installing subclass proc calls this; if False, the WM_COMMAND
     falls through to the parent's normal handling.}
    function TryHandleCommand(ACommandId: Word): Boolean;
  end;

implementation

uses
  ToolbarLayout, ViewModeLogic, KeyInterceptionSubclass;

const
  {Captions used in the menu. Submenu items deliberately drop the '&'
   mnemonic markers so the menu matches the hamburger popup's style
   and avoids surprise accelerator collisions inside a long submenu.}
  TIMECODE_MENU_CAPTION = 'Show timecodes';
  SETTINGS_MENU_CAPTION = 'Settings...';

{Subclass proc that intercepts WM_COMMAND for our menu IDs. Installed
 by InstallSubclass with dwRefData = TListerMenuExtension Self pointer.}
function ListerMenuSubclassProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM;
  ALParam: LPARAM; AIdSubclass: UINT_PTR; ARefData: DWORD_PTR): LRESULT; stdcall;
var
  Ext: TListerMenuExtension;
  CmdId: Word;
begin
  if AMsg = WM_COMMAND then
  begin
    {Menu commands have HIWORD(wParam) = 0; accelerator commands set
     HIWORD = 1. Treat both the same — only the ID matters for our
     range check.}
    CmdId := Word(AWParam and $FFFF);
    if (CmdId >= LISTER_MENU_CMD_BASE) and (CmdId <= LISTER_MENU_CMD_LAST) then
    begin
      Ext := TListerMenuExtension(Pointer(ARefData));
      if (Ext <> nil) and Ext.TryHandleCommand(CmdId) then
        Exit(0);
    end;
  end;
  Result := DefSubclassProc(AWnd, AMsg, AWParam, ALParam);
end;

constructor TListerMenuExtension.Create(AParentWnd: HWND; AFlatMode: Boolean;
  const ADispatch: TListerMenuDispatch);
begin
  inherited Create;
  FParentWnd := AParentWnd;
  FFlatMode := AFlatMode;
  FDispatch := ADispatch;
  FNextId := LISTER_MENU_CMD_BASE;
  FEntries := TDictionary<Word, TListerMenuEntry>.Create;
  FParentMenu := GetMenu(AParentWnd);
  {No menu on the parent (Quick View panel, or a host that opted out)
   — leave FParentMenu = 0; Destroy will short-circuit cleanly.}
  if FParentMenu = 0 then
    Exit;

  FFirstPos := GetMenuItemCount(FParentMenu);
  if FFlatMode then
    BuildFlat
  else
    BuildSubmenu;
  FItemCount := GetMenuItemCount(FParentMenu) - FFirstPos;

  DrawMenuBar(FParentWnd);
  InstallSubclass;
end;

destructor TListerMenuExtension.Destroy;
var
  I: Integer;
begin
  if FParentMenu <> 0 then
  begin
    UninstallSubclass;
    {Remove items in reverse order. Each RemoveMenu shifts subsequent
     items down, so deleting from the tail keeps FFirstPos pointing at
     the correct position for the next removal. Popup submenus attached
     via MF_POPUP are destroyed automatically when their host item is
     removed.}
    for I := FItemCount - 1 downto 0 do
      RemoveMenu(FParentMenu, FFirstPos + I, MF_BYPOSITION);
    DrawMenuBar(FParentWnd);
  end;
  FEntries.Free;
  inherited;
end;

function TListerMenuExtension.AllocIdFor(const AEntry: TListerMenuEntry): Word;
begin
  if FNextId > LISTER_MENU_CMD_LAST then
    raise Exception.Create('TListerMenuExtension: reserved menu ID range exhausted');
  Result := FNextId;
  Inc(FNextId);
  FEntries.Add(Result, AEntry);
end;

procedure TListerMenuExtension.AddSeparator(ADest: HMENU);
begin
  AppendMenu(ADest, MF_SEPARATOR, 0, nil);
end;

procedure TListerMenuExtension.AddPlainModeItem(ADest: HMENU; AMode: TViewMode);
var
  Entry: TListerMenuEntry;
  Id: Word;
begin
  Entry.Kind := lmekMode;
  Entry.Mode := AMode;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := 0;
  Id := AllocIdFor(Entry);
  AppendMenu(ADest, MF_STRING, Id, PChar(ViewModeDisplayName(AMode)));
end;

procedure TListerMenuExtension.AddModeWithZoomSubmenu(ADest: HMENU; AMode: TViewMode);
var
  ZM: TZoomMode;
  Entry: TListerMenuEntry;
  Id: Word;
  ModePopup: HMENU;
begin
  ModePopup := CreatePopupMenu;
  for ZM := Low(TZoomMode) to High(TZoomMode) do
  begin
    Entry.Kind := lmekZoom;
    Entry.Mode := AMode;
    Entry.Zoom := ZM;
    Entry.ActionTag := 0;
    Id := AllocIdFor(Entry);
    AppendMenu(ModePopup, MF_STRING, Id, PChar(SIZING_LABELS[AMode, ZM]));
  end;
  AppendMenu(ADest, MF_POPUP, ModePopup, PChar(ViewModeDisplayName(AMode)));
end;

procedure TListerMenuExtension.AddModeItems(ADest: HMENU);
var
  VM: TViewMode;
begin
  for VM := Low(TViewMode) to High(TViewMode) do
    if ModeHasZoomSubmodes(VM) then
      AddModeWithZoomSubmenu(ADest, VM)
    else
      AddPlainModeItem(ADest, VM);
end;

procedure TListerMenuExtension.AddTimecodeItem(ADest: HMENU);
var
  Entry: TListerMenuEntry;
  Id: Word;
begin
  Entry.Kind := lmekTimecode;
  Entry.Mode := vmGrid;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := 0;
  Id := AllocIdFor(Entry);
  AppendMenu(ADest, MF_STRING, Id, TIMECODE_MENU_CAPTION);
end;

procedure TListerMenuExtension.AddActionItem(ADest: HMENU; AActionTag: Integer;
  const ACaption: string);
var
  Entry: TListerMenuEntry;
  Id: Word;
begin
  Entry.Kind := lmekAction;
  Entry.Mode := vmGrid;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := AActionTag;
  Id := AllocIdFor(Entry);
  AppendMenu(ADest, MF_STRING, Id, PChar(ACaption));
end;

{Save view / Copy view / Refresh map to split-buttons on the toolbar
 with dropdown variants. In the menu, each becomes a popup that lists
 the default action plus the variants, mirroring the toolbar dropdown.}
procedure TListerMenuExtension.AddSaveViewSubmenu(ADest: HMENU);
var
  Popup: HMENU;
  I: Integer;
begin
  Popup := CreatePopupMenu;
  AddActionItem(Popup, CM_SAVE_VIEW, 'Save view (default)...');
  for I := 0 to High(SAVE_VIEW_VARIANTS) do
    AddActionItem(Popup, SAVE_VIEW_VARIANTS[I].Tag, SAVE_VIEW_VARIANTS[I].Caption);
  AppendMenu(ADest, MF_POPUP, Popup, 'Save view');
end;

procedure TListerMenuExtension.AddCopyViewSubmenu(ADest: HMENU);
var
  Popup: HMENU;
  I: Integer;
begin
  Popup := CreatePopupMenu;
  AddActionItem(Popup, CM_COPY_VIEW, 'Copy view (default)');
  for I := 0 to High(COPY_VIEW_VARIANTS) do
    AddActionItem(Popup, COPY_VIEW_VARIANTS[I].Tag, COPY_VIEW_VARIANTS[I].Caption);
  AppendMenu(ADest, MF_POPUP, Popup, 'Copy view');
end;

procedure TListerMenuExtension.AddRefreshSubmenu(ADest: HMENU);
var
  Popup: HMENU;
begin
  Popup := CreatePopupMenu;
  AddActionItem(Popup, CM_REFRESH, 'Refresh');
  AddActionItem(Popup, CM_SHUFFLE, 'Shuffle');
  AppendMenu(ADest, MF_POPUP, Popup, 'Refresh');
end;

procedure TListerMenuExtension.PopulateContents(ADest: HMENU);
begin
  AddModeItems(ADest);
  AddSeparator(ADest);
  AddTimecodeItem(ADest);
  AddSeparator(ADest);
  AddActionItem(ADest, CM_SAVE_FRAME, 'Save frame...');
  AddActionItem(ADest, CM_SAVE_FRAMES, 'Save frames...');
  AddSaveViewSubmenu(ADest);
  AddSeparator(ADest);
  AddActionItem(ADest, CM_COPY_FRAME, 'Copy frame');
  AddCopyViewSubmenu(ADest);
  AddSeparator(ADest);
  AddRefreshSubmenu(ADest);
  AddSeparator(ADest);
  AddActionItem(ADest, CM_SETTINGS, SETTINGS_MENU_CAPTION);
end;

procedure TListerMenuExtension.BuildSubmenu;
var
  Glimpse: HMENU;
begin
  Glimpse := CreatePopupMenu;
  PopulateContents(Glimpse);
  AppendMenu(FParentMenu, MF_POPUP, Glimpse, GLIMPSE_MENU_CAPTION);
end;

procedure TListerMenuExtension.BuildFlat;
begin
  {Flat mode appends the same content directly to the menu bar; mode
   items with zoom submenus and the save / copy / refresh groups
   become top-level entries opening their respective popup. Visually
   noisy but matches the "every button as a top-level menu entry"
   instruction.}
  PopulateContents(FParentMenu);
end;

procedure TListerMenuExtension.InstallSubclass;
begin
  SetWindowSubclass(FParentWnd, @ListerMenuSubclassProc,
    LISTER_MENU_SUBCLASS_ID, DWORD_PTR(Self));
end;

procedure TListerMenuExtension.UninstallSubclass;
begin
  RemoveWindowSubclass(FParentWnd, @ListerMenuSubclassProc,
    LISTER_MENU_SUBCLASS_ID);
end;

function TListerMenuExtension.TryHandleCommand(ACommandId: Word): Boolean;
var
  Entry: TListerMenuEntry;
begin
  Result := FEntries.TryGetValue(ACommandId, Entry);
  if not Result then
    Exit;
  if Assigned(FDispatch) then
    FDispatch(Entry);
end;

end.
