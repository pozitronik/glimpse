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
    {Non-flat: handle of the "Glimpse" popup we appended.
     Flat: 0 (items live directly on the parent's menu bar).}
    FSubmenu: HMENU;
    {Flat: command IDs of the top-level items we appended; needed for
     removal in Destroy. Non-flat: command IDs of items inside the
     submenu; their removal happens implicitly when we DeleteMenu the
     parent of the submenu.}
    FOwnedIds: TList<Word>;
    {Map from command ID to the entry payload, used by TryHandleCommand
     to look up which operation a clicked item maps to.}
    FEntries: TDictionary<Word, TListerMenuEntry>;
    FNextId: Word;
    function AllocIdFor(const AEntry: TListerMenuEntry): Word;
    procedure AddModeItems(ADest: HMENU);
    procedure AddSeparator(ADest: HMENU);
    procedure AddTimecodeItem(ADest: HMENU);
    procedure AddActionGroup(ADest: HMENU; AActionTag: Integer; const ACaption: string);
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
  ToolbarLayout, KeyInterceptionSubclass;

const
  {Captions used in the menu. Static (English-only — experimental
   feature, see unit header).}
  TIMECODE_MENU_CAPTION = 'Show timecodes';
  REFRESH_MENU_CAPTION = '&Refresh';
  SHUFFLE_MENU_CAPTION = 'Shuf&fle';
  SETTINGS_MENU_CAPTION = '&Settings...';
  SAVE_VIEW_MENU_CAPTION = '&Save view...';
  COPY_VIEW_MENU_CAPTION = '&Copy view';

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
  FOwnedIds := TList<Word>.Create;
  FEntries := TDictionary<Word, TListerMenuEntry>.Create;
  FParentMenu := GetMenu(AParentWnd);
  {No menu on the parent (Quick View panel, or a host that opted out)
   — leave FParentMenu = 0; Destroy will short-circuit cleanly.}
  if FParentMenu = 0 then
    Exit;

  if FFlatMode then
    BuildFlat
  else
    BuildSubmenu;

  DrawMenuBar(FParentWnd);
  InstallSubclass;
end;

destructor TListerMenuExtension.Destroy;
var
  Id: Word;
begin
  if FParentMenu <> 0 then
  begin
    UninstallSubclass;
    if FFlatMode then
    begin
      {Flat: each item is its own top-level entry, removed by command ID.}
      for Id in FOwnedIds do
        RemoveMenu(FParentMenu, Id, MF_BYCOMMAND);
    end
    else if FSubmenu <> 0 then
    begin
      {Submenu mode: removing the popup from the parent also destroys
       all items inside it. Use MF_BYCOMMAND with the submenu HANDLE,
       which is what AppendMenu(MF_POPUP) used as the "uIDNewItem".}
      RemoveMenu(FParentMenu, FSubmenu, MF_BYCOMMAND);
      DestroyMenu(FSubmenu);
    end;
    DrawMenuBar(FParentWnd);
  end;
  FEntries.Free;
  FOwnedIds.Free;
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

procedure TListerMenuExtension.AddModeItems(ADest: HMENU);
var
  VM: TViewMode;
  Entry: TListerMenuEntry;
  Id: Word;
begin
  for VM := Low(TViewMode) to High(TViewMode) do
  begin
    Entry.Kind := lmekMode;
    Entry.Mode := VM;
    Entry.Zoom := zmFitWindow;
    Entry.ActionTag := 0;
    Id := AllocIdFor(Entry);
    if FFlatMode then
      FOwnedIds.Add(Id);
    AppendMenu(ADest, MF_STRING, Id, PChar(MODE_CAPTIONS[VM]));
  end;
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
  if FFlatMode then
    FOwnedIds.Add(Id);
  AppendMenu(ADest, MF_STRING, Id, TIMECODE_MENU_CAPTION);
end;

procedure TListerMenuExtension.AddActionGroup(ADest: HMENU; AActionTag: Integer;
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
  if FFlatMode then
    FOwnedIds.Add(Id);
  AppendMenu(ADest, MF_STRING, Id, PChar(ACaption));
end;

procedure TListerMenuExtension.BuildSubmenu;
begin
  FSubmenu := CreatePopupMenu;

  AddModeItems(FSubmenu);
  AddSeparator(FSubmenu);
  AddTimecodeItem(FSubmenu);
  AddSeparator(FSubmenu);
  AddActionGroup(FSubmenu, CM_REFRESH, REFRESH_MENU_CAPTION);
  AddActionGroup(FSubmenu, CM_SHUFFLE, SHUFFLE_MENU_CAPTION);
  AddSeparator(FSubmenu);
  AddActionGroup(FSubmenu, CM_SAVE_VIEW, SAVE_VIEW_MENU_CAPTION);
  AddActionGroup(FSubmenu, CM_SAVE_VIEW_LIVE, 'Save view (live resolution)');
  AddActionGroup(FSubmenu, CM_SAVE_VIEW_NATIVE, 'Save view (native size)');
  AddSeparator(FSubmenu);
  AddActionGroup(FSubmenu, CM_COPY_VIEW, COPY_VIEW_MENU_CAPTION);
  AddActionGroup(FSubmenu, CM_COPY_VIEW_LIVE, 'Copy view (live resolution)');
  AddActionGroup(FSubmenu, CM_COPY_VIEW_NATIVE, 'Copy view (native size)');
  AddSeparator(FSubmenu);
  AddActionGroup(FSubmenu, CM_SETTINGS, SETTINGS_MENU_CAPTION);

  AppendMenu(FParentMenu, MF_POPUP, FSubmenu, GLIMPSE_MENU_CAPTION);
end;

procedure TListerMenuExtension.BuildFlat;
begin
  {Each call appends directly to FParentMenu; AddSeparator is a no-op
   here because separators on a top-level menu bar look weird and most
   menu bars ignore them anyway.}
  AddModeItems(FParentMenu);
  AddTimecodeItem(FParentMenu);
  AddActionGroup(FParentMenu, CM_REFRESH, 'Refresh');
  AddActionGroup(FParentMenu, CM_SHUFFLE, 'Shuffle');
  AddActionGroup(FParentMenu, CM_SAVE_VIEW, 'Save view');
  AddActionGroup(FParentMenu, CM_SAVE_VIEW_LIVE, 'Save (live)');
  AddActionGroup(FParentMenu, CM_SAVE_VIEW_NATIVE, 'Save (native)');
  AddActionGroup(FParentMenu, CM_COPY_VIEW, 'Copy view');
  AddActionGroup(FParentMenu, CM_COPY_VIEW_LIVE, 'Copy (live)');
  AddActionGroup(FParentMenu, CM_COPY_VIEW_NATIVE, 'Copy (native)');
  AddActionGroup(FParentMenu, CM_SETTINGS, 'Settings');
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
