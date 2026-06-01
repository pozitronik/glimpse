{Experimental: appends Glimpse's toolbar actions into TLister's own
 menu bar so the user can drive the plugin from TC's menu in addition
 to the in-form toolbar and configurable hotkeys.

 The actions live under a single new top-level "Glimpse" entry on the
 menu bar, keeping visual noise low and staying out of TC's way.

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
  Types, Hotkeys;

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

  {One-shot deferred-install message. Posted from the constructor so
   the retry dispatches AFTER TC's ListLoad returns and any subsequent
   SetMenu the host runs during its post-load setup. Picked from the
   WM_APP range to stay out of the system-message space; the constant
   is module-private since nobody else posts it.}
  WM_GLIMPSE_LISTER_MENU_DEFERRED_INSTALL = WM_APP + 1;

type
  {Each menu item dispatches to one of four host operations.}
  TListerMenuEntryKind = (lmekMode, lmekZoom, lmekTimecode, lmekFrameCount, lmekAction);

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

  {Supplies the current frame count for the live "Frames count: X" header.}
  TListerMenuFrameCountProvider = reference to function: Integer;

  TListerMenuExtension = class
  strict private
    FParentWnd: HWND;
    FParentMenu: HMENU;
    FDispatch: TListerMenuDispatch;
    {Supplies the live frame count for the "Frames count: X" header; the
     value is re-stamped on every WM_INITMENU.}
    FFrameCountProvider: TListerMenuFrameCountProvider;
    {Slot of the frame-count submenu's parent item, captured at build so
     RefreshFrameCountCaption can re-stamp the live value in place.}
    FFrameCountParentMenu: HMENU;
    FFrameCountPos: Integer;
    FFrameCountPopup: HMENU;
    {Borrowed; lookup-only. Used to format the hotkey shown next to
     each leaf menu item's caption. May be nil — captions then render
     without accelerator text.}
    FHotkeys: THotkeyBindings;
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
    {Maps an entry to its TPluginAction so we can look up the binding.
     Returns paNone for entries with no direct action (zoom variants,
     submenu parents that only open their popup).}
    function PluginActionFor(const AEntry: TListerMenuEntry): TPluginAction;
    {Returns the display string for the first assigned chord bound to
     AEntry's TPluginAction, or '' when nothing is bound or no action
     maps. Reads through FHotkeys (nil-safe).}
    function AcceleratorFor(const AEntry: TListerMenuEntry): string;
    {ABase + #9 + accelerator (when present). #9 is the Win32 menu
     convention for right-aligning the accelerator hint. Returns ABase
     unchanged when ADest is the parent menu bar — top-level menu bar
     entries render the #9 padding broken, so they get just the caption.}
    function CaptionWithAccelerator(const ABase: string;
      const AEntry: TListerMenuEntry; ADest: HMENU): string;
    procedure AddSeparator(ADest: HMENU);
    procedure AddPlainModeItem(ADest: HMENU; AMode: TViewMode);
    procedure AddModeWithZoomSubmenu(ADest: HMENU; AMode: TViewMode);
    procedure AddModeItems(ADest: HMENU);
    procedure AddTimecodeItem(ADest: HMENU);
    procedure AddActionItem(ADest: HMENU; AActionTag: Integer; const ACaption: string);
    procedure AddFrameCountItem(APopup: HMENU; ADelta: Integer; const ACaption: string);
    procedure AddFrameCountSubmenu(ADest: HMENU);
    procedure AddSaveViewSubmenu(ADest: HMENU);
    procedure AddCopyViewSubmenu(ADest: HMENU);
    procedure AddRefreshSubmenu(ADest: HMENU);
    procedure PopulateContents(ADest: HMENU);
    procedure BuildSubmenu;
    procedure ForceStringFTypeRecursive(AMenu: HMENU);
    procedure Install;
    procedure Teardown;
    procedure InstallSubclass;
    procedure UninstallSubclass;
  public
    {Re-attaches our items when the host's menu has been replaced or
     trimmed underneath us. Cheap fast-path check; rebuilds only when
     a mismatch is detected. Called by our subclass on WM_INITMENU.}
    procedure EnsureItemsInstalled;
    {Re-stamps the "Frames count: X" header with the current value so the
     menu bar shows it fresh each time it is activated. Public so the
     unit-level subclass proc can call it on WM_INITMENU.}
    procedure RefreshFrameCountCaption;
    {Unconditional teardown + install. Called on WM_DPICHANGED /
     WM_DISPLAYCHANGE / WM_THEMECHANGED where the menu is known to
     have been redrawn and a verify-then-rebuild path can be tricked
     by surviving-but-corrupted items.}
    procedure ForceRebuild;
    {AParentWnd is the TLister window. AHotkeys is borrowed (nil is
     allowed; captions then omit the accelerator hint). The dispatch
     callback is invoked on every click; the host translates the entry
     to its action.}
    constructor Create(AParentWnd: HWND;
      AHotkeys: THotkeyBindings;
      const ADispatch: TListerMenuDispatch;
      const AFrameCountProvider: TListerMenuFrameCountProvider);
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
  {Step sizes offered by the frame-count submenu, applied as +/- deltas.}
  FRAME_COUNT_STEPS: array [0 .. 2] of Integer = (1, 5, 10);

{The toolbar shares the 'Scroll' caption between vmScroll and vmFilmstrip
 and distinguishes with arrow icons (vertical / horizontal); the menu
 has no icons so the captions spell out the direction.}
function MenuCaptionForMode(AMode: TViewMode): string;
begin
  case AMode of
    vmSmartGrid: Result := 'Smart grid';
    vmGrid:      Result := 'Grid';
    vmScroll:    Result := 'Vertical scroll';
    vmFilmstrip: Result := 'Horizontal scroll (filmstrip)';
    vmSingle:    Result := 'Single frame';
  else
    Result := ViewModeDisplayName(AMode);
  end;
end;

{Subclass proc that intercepts WM_COMMAND for our menu IDs. Installed
 by InstallSubclass with dwRefData = TListerMenuExtension Self pointer.}
function ListerMenuSubclassProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM;
  ALParam: LPARAM; AIdSubclass: UINT_PTR; ARefData: DWORD_PTR): LRESULT; stdcall;
var
  Ext: TListerMenuExtension;
  CmdId: Word;
begin
  Ext := TListerMenuExtension(Pointer(ARefData));
  case AMsg of
    WM_COMMAND:
      begin
        {Menu commands have HIWORD(wParam) = 0; accelerator commands set
         HIWORD = 1. Treat both the same — only the ID matters for our
         range check. Intercept BEFORE TC's wndproc so it never sees
         our IDs.}
        CmdId := Word(AWParam and $FFFF);
        if (CmdId >= LISTER_MENU_CMD_BASE) and (CmdId <= LISTER_MENU_CMD_LAST) then
          if (Ext <> nil) and Ext.TryHandleCommand(CmdId) then
            Exit(0);
        Result := DefSubclassProc(AWnd, AMsg, AWParam, ALParam);
      end;
    {Menu-affecting messages: let TC process them FIRST (it may rebuild
     its menu, resize the bar, adjust DPI-scaled font metrics, etc.),
     THEN run our hook so our items land on top of TC's processed
     state. Our subclass was installed after TC's wndproc so we fire
     first in the chain — without this explicit ordering, any work TC
     does after DefSubclassProc returns would wipe our additions.}
    WM_INITMENU:
      begin
        Result := DefSubclassProc(AWnd, AMsg, AWParam, ALParam);
        if Ext <> nil then
        begin
          Ext.EnsureItemsInstalled;
          Ext.RefreshFrameCountCaption;
        end;
      end;
    WM_DPICHANGED, WM_DISPLAYCHANGE, WM_THEMECHANGED:
      begin
        Result := DefSubclassProc(AWnd, AMsg, AWParam, ALParam);
        if Ext <> nil then
          Ext.ForceRebuild;
      end;
    WM_GLIMPSE_LISTER_MENU_DEFERRED_INSTALL:
      begin
        {Deferred retry posted from the constructor — runs after TC's
         ListLoad has returned, when any host-side SetMenu has settled.
         On Win11 the items are already installed and EnsureItemsInstalled
         early-exits; on XP this is where they finally land.}
        if Ext <> nil then
          Ext.EnsureItemsInstalled;
        Result := 0;
      end;
  else
    Result := DefSubclassProc(AWnd, AMsg, AWParam, ALParam);
  end;
end;

constructor TListerMenuExtension.Create(AParentWnd: HWND;
  AHotkeys: THotkeyBindings;
  const ADispatch: TListerMenuDispatch;
  const AFrameCountProvider: TListerMenuFrameCountProvider);
begin
  inherited Create;
  FParentWnd := AParentWnd;
  FHotkeys := AHotkeys;
  FDispatch := ADispatch;
  FFrameCountProvider := AFrameCountProvider;
  FNextId := LISTER_MENU_CMD_BASE;
  FEntries := TDictionary<Word, TListerMenuEntry>.Create;
  Install;
  {Always install the subclass — even if Install short-circuited
   (no parent menu yet), a future WM_INITMENU will let
   EnsureItemsInstalled try again. Subclass also forwards WM_COMMAND
   no matter what.}
  InstallSubclass;
  {Deferred retry: when the host's lister-menu construction races our
   constructor (observed on XP — TC sometimes calls SetMenu only after
   ListLoad has returned), the synchronous Install above silently bails
   on GetMenu = 0. Post a one-shot message that fires after the current
   ListLoad call unwinds; by then the menu is set and EnsureItemsInstalled
   can take. No-op on hosts where the synchronous Install already
   succeeded.}
  if FParentWnd <> 0 then
    PostMessage(FParentWnd, WM_GLIMPSE_LISTER_MENU_DEFERRED_INSTALL, 0, 0);
end;

destructor TListerMenuExtension.Destroy;
begin
  UninstallSubclass;
  Teardown;
  FEntries.Free;
  inherited;
end;

procedure TListerMenuExtension.Install;
begin
  FParentMenu := GetMenu(FParentWnd);
  {No menu on the parent (Quick View panel, or the host is currently
   between menu HANDLES — common during DPI change). Leave state
   cleared; EnsureItemsInstalled will retry on the next WM_INITMENU.}
  if FParentMenu = 0 then
  begin
    FFirstPos := 0;
    FItemCount := 0;
    Exit;
  end;

  FFirstPos := GetMenuItemCount(FParentMenu);
  BuildSubmenu;
  FItemCount := GetMenuItemCount(FParentMenu) - FFirstPos;
  {Force MFT_STRING on every item we just appended (and on any popup
   submenus we own). Defends against the parent menu having MNS_NOTIFYBYPOS
   or other style flags that make AppendMenu's default rendering be
   treated as owner-draw by the host — the classic cause of "items
   invisible until you hover them" after a UI-state change like Alt
   activating the menu bar.}
  ForceStringFTypeRecursive(FParentMenu);
  DrawMenuBar(FParentWnd);
end;

procedure TListerMenuExtension.Teardown;
var
  I: Integer;
begin
  {Only remove if the cached parent menu is still the host's current
   menu. If GetMenu has changed underneath us, the old HMENU was
   destroyed by the host (taking our items with it) and a removal call
   would target the wrong menu.}
  if (FParentMenu <> 0) and (FParentMenu = GetMenu(FParentWnd)) then
  begin
    for I := FItemCount - 1 downto 0 do
      RemoveMenu(FParentMenu, FFirstPos + I, MF_BYPOSITION);
    DrawMenuBar(FParentWnd);
  end;
  FParentMenu := 0;
  FFirstPos := 0;
  FItemCount := 0;
  FNextId := LISTER_MENU_CMD_BASE;
  FFrameCountParentMenu := 0;
  FFrameCountPos := 0;
  FFrameCountPopup := 0;
  FEntries.Clear;
end;

procedure TListerMenuExtension.EnsureItemsInstalled;
var
  CurrentMenu: HMENU;
begin
  CurrentMenu := GetMenu(FParentWnd);
  {Same menu and item count looks sane — nothing to do. Cheap fast
   path for the common WM_INITMENU storm.}
  if (CurrentMenu <> 0) and (CurrentMenu = FParentMenu)
    and (GetMenuItemCount(FParentMenu) >= FFirstPos + FItemCount) then
    Exit;
  ForceRebuild;
end;

procedure TListerMenuExtension.ForceRebuild;
begin
  Teardown;
  Install;
  {Force a non-client area recalc on the host. DrawMenuBar alone is
   sometimes insufficient after DPI / display changes — items end up
   in the menu data but the menu bar's non-client cache stays stale
   until something else triggers a repaint. SWP_FRAMECHANGED forces
   WM_NCCALCSIZE which redraws the menu bar from scratch.}
  if FParentWnd <> 0 then
    SetWindowPos(FParentWnd, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
end;

procedure TListerMenuExtension.ForceStringFTypeRecursive(AMenu: HMENU);
const
  STR_BUF_LEN = 256;
var
  I, Count, StartPos, EndPos: Integer;
  StrBuf: array [0 .. STR_BUF_LEN - 1] of Char;
  Info: TMenuItemInfo;
begin
  if AMenu = 0 then
    Exit;
  Count := GetMenuItemCount(AMenu);
  if Count <= 0 then
    Exit;

  {Top-level call against the parent menu: only touch our items. Any
   nested call (popup we built) processes all items inside that popup.}
  if AMenu = FParentMenu then
  begin
    StartPos := FFirstPos;
    EndPos := FFirstPos + FItemCount - 1;
    if EndPos >= Count then
      EndPos := Count - 1;
  end else begin
    StartPos := 0;
    EndPos := Count - 1;
  end;

  for I := StartPos to EndPos do
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    Info.fMask := MIIM_FTYPE or MIIM_SUBMENU or MIIM_STRING or MIIM_ID;
    Info.dwTypeData := @StrBuf[0];
    Info.cch := STR_BUF_LEN;
    if not GetMenuItemInfo(AMenu, I, True, Info) then
      Continue;
    {Recurse into popup submenus we own before mutating. The recursion
     is bounded by our build depth (two levels at most: parent → Glimpse
     popup → mode-zoom or save-view popup).}
    if Info.hSubMenu <> 0 then
      ForceStringFTypeRecursive(Info.hSubMenu);
    {Skip separators (they carry MFT_SEPARATOR; reassigning would turn
     them into empty text items).}
    if (Info.fType and MFT_SEPARATOR) <> 0 then
      Continue;
    {ModifyMenu replaces the item wholesale rather than mutating
     individual fields like SetMenuItemInfo does. Used here as a
     stronger override than the previous SetMenuItemInfo(MIIM_FTYPE)
     attempt — if TC's WM_INITMENU handler post-stamps owner-draw bits
     on items it doesn't recognise, the per-field SET call competes
     with that stamping, while ModifyMenu replaces the item from
     scratch on the menu's data structure.}
    if Info.hSubMenu <> 0 then
      ModifyMenu(AMenu, I, MF_BYPOSITION or MF_STRING or MF_POPUP,
        UINT_PTR(Info.hSubMenu), PChar(@StrBuf[0]))
    else
      ModifyMenu(AMenu, I, MF_BYPOSITION or MF_STRING,
        Info.wID, PChar(@StrBuf[0]));
  end;
end;

function TListerMenuExtension.AllocIdFor(const AEntry: TListerMenuEntry): Word;
begin
  if FNextId > LISTER_MENU_CMD_LAST then
    raise Exception.Create('TListerMenuExtension: reserved menu ID range exhausted');
  Result := FNextId;
  Inc(FNextId);
  FEntries.Add(Result, AEntry);
end;

function TListerMenuExtension.PluginActionFor(const AEntry: TListerMenuEntry): TPluginAction;
begin
  case AEntry.Kind of
    lmekMode:
      case AEntry.Mode of
        vmSmartGrid: Result := paViewModeSmartGrid;
        vmGrid:      Result := paViewModeGrid;
        vmScroll:    Result := paViewModeScroll;
        vmFilmstrip: Result := paViewModeFilmstrip;
        vmSingle:    Result := paViewModeSingle;
      else
        Result := paNone;
      end;
    lmekTimecode:
      Result := paToggleTimecode;
    lmekAction:
      case AEntry.ActionTag of
        CM_SAVE_FRAME:       Result := paSaveFrame;
        CM_SAVE_FRAMES:      Result := paSaveFrames;
        CM_SAVE_VIEW:        Result := paSaveView;
        CM_SAVE_VIEW_LIVE:   Result := paSaveViewLive;
        CM_SAVE_VIEW_NATIVE: Result := paSaveViewNative;
        CM_COPY_FRAME:       Result := paCopyFrame;
        CM_COPY_VIEW:        Result := paCopyView;
        CM_COPY_VIEW_LIVE:   Result := paCopyViewLive;
        CM_COPY_VIEW_NATIVE: Result := paCopyViewNative;
        CM_REFRESH:          Result := paRefreshExtraction;
        CM_SHUFFLE:          Result := paShuffleExtraction;
        CM_SETTINGS:         Result := paSettings;
      else
        Result := paNone;
      end;
  else
    {lmekZoom items inside mode submenus have no dedicated action —
     they activate a mode + apply a zoom, which has no single hotkey
     in the binding table.}
    Result := paNone;
  end;
end;

function TListerMenuExtension.AcceleratorFor(const AEntry: TListerMenuEntry): string;
var
  Action: TPluginAction;
  Chords: THotkeyChordArray;
  I: Integer;
begin
  Result := '';
  if FHotkeys = nil then
    Exit;
  Action := PluginActionFor(AEntry);
  if Action = paNone then
    Exit;
  Chords := FHotkeys.Get(Action);
  for I := 0 to High(Chords) do
    if Chords[I].IsAssigned then
      Exit(Chords[I].ToDisplayStr);
end;

function TListerMenuExtension.CaptionWithAccelerator(const ABase: string;
  const AEntry: TListerMenuEntry; ADest: HMENU): string;
var
  Acc: string;
begin
  if ADest = FParentMenu then
    Exit(ABase);
  Acc := AcceleratorFor(AEntry);
  if Acc = '' then
    Exit(ABase);
  Result := ABase + #9 + Acc;
end;

procedure TListerMenuExtension.AddSeparator(ADest: HMENU);
begin
  {Separators only belong inside popup menus. Adding one to the
   top-level menu bar (Mode B) renders as a stray "-" on some
   Windows configurations and survives TC menu rebuilds out of step
   with the text items, leaving an orphan after our items vanish.}
  if ADest = FParentMenu then
    Exit;
  AppendMenu(ADest, MF_SEPARATOR, 0, nil);
end;

procedure TListerMenuExtension.AddPlainModeItem(ADest: HMENU; AMode: TViewMode);
var
  Entry: TListerMenuEntry;
  Id: Word;
  Caption: string;
begin
  Entry.Kind := lmekMode;
  Entry.Mode := AMode;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := 0;
  Id := AllocIdFor(Entry);
  Caption := CaptionWithAccelerator(MenuCaptionForMode(AMode), Entry, ADest);
  AppendMenu(ADest, MF_STRING, Id, PChar(Caption));
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
  AppendMenu(ADest, MF_POPUP, ModePopup, PChar(MenuCaptionForMode(AMode)));
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
  Caption: string;
begin
  Entry.Kind := lmekTimecode;
  Entry.Mode := vmGrid;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := 0;
  Id := AllocIdFor(Entry);
  Caption := CaptionWithAccelerator(TIMECODE_MENU_CAPTION, Entry, ADest);
  AppendMenu(ADest, MF_STRING, Id, PChar(Caption));
end;

procedure TListerMenuExtension.AddActionItem(ADest: HMENU; AActionTag: Integer;
  const ACaption: string);
var
  Entry: TListerMenuEntry;
  Id: Word;
  Caption: string;
begin
  Entry.Kind := lmekAction;
  Entry.Mode := vmGrid;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := AActionTag;
  Id := AllocIdFor(Entry);
  Caption := CaptionWithAccelerator(ACaption, Entry, ADest);
  AppendMenu(ADest, MF_STRING, Id, PChar(Caption));
end;

procedure TListerMenuExtension.AddFrameCountItem(APopup: HMENU; ADelta: Integer;
  const ACaption: string);
var
  Entry: TListerMenuEntry;
  Id: Word;
begin
  Entry.Kind := lmekFrameCount;
  Entry.Mode := vmGrid;
  Entry.Zoom := zmFitWindow;
  Entry.ActionTag := ADelta;
  Id := AllocIdFor(Entry);
  AppendMenu(APopup, MF_STRING, Id, PChar(ACaption));
end;

{Live "Frames count: X" header whose value refreshes on each menu
 activation, with a submenu of +/- step adjustments.}
procedure TListerMenuExtension.AddFrameCountSubmenu(ADest: HMENU);
var
  Popup: HMENU;
  Step: Integer;
  Caption: string;
begin
  Popup := CreatePopupMenu;
  for Step in FRAME_COUNT_STEPS do
    AddFrameCountItem(Popup, Step, Format('Increase by %d', [Step]));
  AddSeparator(Popup);
  for Step in FRAME_COUNT_STEPS do
    AddFrameCountItem(Popup, -Step, Format('Decrease by %d', [Step]));
  if Assigned(FFrameCountProvider) then
    Caption := Format('Frames count: %d', [FFrameCountProvider()])
  else
    Caption := 'Frames count';
  {Capture the slot before appending so RefreshFrameCountCaption can
   re-stamp the value in place via MF_BYPOSITION.}
  FFrameCountParentMenu := ADest;
  FFrameCountPos := GetMenuItemCount(ADest);
  FFrameCountPopup := Popup;
  AppendMenu(ADest, MF_POPUP, Popup, PChar(Caption));
end;

procedure TListerMenuExtension.RefreshFrameCountCaption;
var
  Caption: string;
begin
  if (FFrameCountParentMenu = 0) or (FFrameCountPopup = 0) or
     not Assigned(FFrameCountProvider) then
    Exit;
  Caption := Format('Frames count: %d', [FFrameCountProvider()]);
  ModifyMenu(FFrameCountParentMenu, FFrameCountPos,
    MF_BYPOSITION or MF_STRING or MF_POPUP, UINT_PTR(FFrameCountPopup),
    PChar(Caption));
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
  AddFrameCountSubmenu(ADest);
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
