{Configurable-hotkey machinery for the WLX plugin.

 Each plugin action can be bound to any number of chords (a "chord" is a
 VK_* key plus a modifier set). Multiple chords let a single action — say
 "previous file" — be invoked by several shorthand keys at once: Left,
 PageUp, Backspace, Z all navigate backward out of the box.

 Numpad digits and symbol aliases (VK_NUMPAD0..9, VK_ADD, VK_SUBTRACT,
 VK_DECIMAL) are collapsed to their letter-row equivalents at Lookup
 time so a single binding "Zoom reset = 0" matches both top-row 0 and
 numpad 0 without the UI having to show two entries.

 Pure: no VCL, no form references. TestHotkeys covers the record, the
 binding table, and the INI round-trip end-to-end.}
unit uHotkeys;

interface

uses
  System.Classes, System.SysUtils,
  uUnicodeIniFile;

type
  {Command-style actions the user can assign hotkeys to. Tab (VCL focus
   cycling) is intentionally not listed — it's a system-level shortcut
   that isn't user-configurable.}
  TPluginAction = (paNone,
    {Window / view}
    paSettings, paToggleToolbar, paToggleStatusBar, paToggleTimecode,
    paToggleMaximize, paToggleFullScreen, paHamburgerMenu, paCloseLister,
    {File}
    paPrevFile, paNextFile,
    paOpenInPlayer, paRefreshExtraction, paShuffleExtraction,
    {Frame}
    paPrevFrame, paNextFrame,
    paFrameCountInc, paFrameCountDec,
    {Frame output}
    paSaveFrame, paSaveFrames, paSaveView,
    paSaveViewLive, paSaveViewNative,
    paSelectAllFrames, paCopyFrame, paCopyView,
    paCopyViewLive, paCopyViewNative,
    {Zoom}
    paZoomIn, paZoomOut, paZoomReset,
    {View mode}
    paViewModeSmartGrid, paViewModeGrid, paViewModeScroll,
    paViewModeFilmstrip, paViewModeSingle);

  THotkeyChord = record
    Key: Word;               {VK_* code; 0 means unbound}
    Modifiers: TShiftState;  {subset of [ssCtrl, ssShift, ssAlt]}
    function IsAssigned: Boolean;
    function Matches(AKey: Word; AShift: TShiftState): Boolean;
    function Equals(const AOther: THotkeyChord): Boolean;
    function ToDisplayStr: string;
    function ToIniStr: string;
    class function Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord; static;
    class function None: THotkeyChord; static;
    class function FromIniStr(const AValue: string): THotkeyChord; static;
  end;

  THotkeyChordArray = TArray<THotkeyChord>;

  {Descriptor row in the ACTIONS table. Each row pins the [hotkeys] INI
   key and the display caption shown in the settings dialog.
   Initialising the table as a positional aggregate
   `array[TPluginAction] of TActionDescriptor` forces the Delphi
   compiler to flag a missing entry — replacing the prior parallel case
   ladders that silently returned '' (which THotkeyBindings.Load /
   Save would then use as an INI key, causing silent data loss).

   Default chord lists are NOT in this table: Delphi's const aggregate
   syntax does not accept nested record-literals inside dynamic-array
   fields (the inner `[...]` parses as a set, not an array). Defaults
   live in DefaultBinding's case ladder; the silent-data-loss class is
   not present there because a missing default just produces nil — the
   action has no shortcut, which is benign and obvious in the dialog.}
  TActionDescriptor = record
    IniKey: string;
    Caption: string;
  end;

  THotkeyBindings = class
  private
    FBindings: array [TPluginAction] of THotkeyChordArray;
  public
    constructor Create;
    {Returns a copy of the chord list for AAction; callers mutate through
     the Put / Add / Remove API rather than editing the returned array.}
    function Get(AAction: TPluginAction): THotkeyChordArray;
    {Replaces the chord list for AAction wholesale. Empty list means unbound.}
    procedure Put(AAction: TPluginAction; const AChords: THotkeyChordArray);
    {Appends AChord to AAction's list if it's not already present (silent
     no-op on duplicate). Returns True when a new chord was actually added.}
    function AddChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
    {Removes the first chord equal to AChord from AAction's list. Returns
     True when a chord was removed.}
    function RemoveChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
    {Scans every action's chord list and returns the first action whose
     chord matches the incoming key + modifiers. Numpad aliases are
     normalised before matching. Returns paNone on no match.}
    function Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
    {Load / Save read and write the [hotkeys] section with '|' as the
     between-chords separator, e.g. PrevFile=Left|PageUp|Backspace|Z.}
    procedure Load(AIni: TUnicodeIniFile);
    procedure Save(AIni: TUnicodeIniFile);
    procedure ResetToDefaults;
    {Overwrites every action's chord list with AOther's (deep copy of the
     arrays). Used by the settings dialog to snapshot/restore.}
    procedure Assign(const AOther: THotkeyBindings);
    {First action (other than AExcept) that contains a chord equal to
     AChord. Returns paNone when no conflict.}
    function FindActionByChord(const AChord: THotkeyChord;
      AExcept: TPluginAction = paNone): TPluginAction;
    {Reassigns AAction's chord list to AChords, taking ownership of any
     chord currently held by another action. Replaces the assign-then-
     reconcile dance the dialog used to do inline: for each chord in
     AChords, every other action that contains it has it removed
     (handles pathological INI-edited duplicates by stripping until
     gone); AAction is then Put to the full new list.

     Returns the deduplicated list of actions whose chord lists were
     mutated by eviction — the dialog uses it to refresh those rows in
     the visible table. AAction itself is excluded from the result even
     though AAction's row will of course also need refreshing.

     Idempotent in the no-conflict case: if no other action owns any
     chord in AChords, the result is empty and only AAction is touched.}
    function ReassignExclusive(AAction: TPluginAction;
      const AChords: THotkeyChordArray): TArray<TPluginAction>;
  end;

const
  HOTKEYS_SECTION = 'hotkeys';
  CHORD_SEPARATOR = '|';

{Default chord list (possibly empty) for an action.}
function DefaultBinding(AAction: TPluginAction): THotkeyChordArray;

{Short INI key used to serialise the action (without the 'pa' enum prefix).}
function ActionIniKey(AAction: TPluginAction): string;

{Human-readable caption for the action, used by the settings dialog UI.}
function ActionCaption(AAction: TPluginAction): string;

implementation

uses
  Winapi.Windows,
  uHotkeysCodec, uHotkeysDisplay;

function NormalizeKey(AKey: Word): Word;
begin
  case AKey of
    VK_NUMPAD0 .. VK_NUMPAD9:
      Result := AKey - VK_NUMPAD0 + Ord('0');
    VK_ADD:
      Result := VK_OEM_PLUS;
    VK_SUBTRACT:
      Result := VK_OEM_MINUS;
    VK_DECIMAL:
      {Locale caveat: VK_DECIMAL is collapsed onto VK_OEM_PERIOD so
       numpad-decimal and the top-row '.' share a single binding.
       European numpads where the decimal key produces ',' would
       prefer VK_OEM_COMMA, but Windows does not expose layout-aware
       VK mapping at this layer. Acceptable - worst case the user
       binds the top-row key separately and gets the layout they
       expect; current behaviour matches WLX's existing one-binding
       contract.}
      Result := VK_OEM_PERIOD;
  else
    Result := AKey;
  end;
end;

function NormalizeShift(const AShift: TShiftState): TShiftState;
begin
  Result := AShift * [ssShift, ssAlt, ssCtrl];
end;

{THotkeyChord}

function THotkeyChord.IsAssigned: Boolean;
begin
  Result := Key <> 0;
end;

function THotkeyChord.Matches(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := IsAssigned and (Key = AKey) and (Modifiers = AShift);
end;

function THotkeyChord.Equals(const AOther: THotkeyChord): Boolean;
begin
  Result := (Key = AOther.Key) and (Modifiers = AOther.Modifiers);
end;

function THotkeyChord.ToDisplayStr: string;
begin
  Result := uHotkeysDisplay.ChordToDisplayStr(Self);
end;

function THotkeyChord.ToIniStr: string;
begin
  Result := uHotkeysCodec.ChordToIniStr(Self);
end;

class function THotkeyChord.Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord;
begin
  {Normalise at construction so numpad/OEM aliases captured from the shortcut
   editor round-trip through INI. Without this, VK_NUMPAD0..9 and VK_ADD /
   VK_SUBTRACT / VK_DECIMAL would hit VKToName as unknown and serialise empty.}
  Result.Key := NormalizeKey(AKey);
  Result.Modifiers := NormalizeShift(AModifiers);
end;

class function THotkeyChord.None: THotkeyChord;
begin
  Result.Key := 0;
  Result.Modifiers := [];
end;

class function THotkeyChord.FromIniStr(const AValue: string): THotkeyChord;
begin
  Result := uHotkeysCodec.ChordFromIniStr(AValue);
end;

{THotkeyBindings}

constructor THotkeyBindings.Create;
begin
  inherited;
  ResetToDefaults;
end;

function THotkeyBindings.Get(AAction: TPluginAction): THotkeyChordArray;
var
  I: Integer;
begin
  SetLength(Result, Length(FBindings[AAction]));
  for I := 0 to High(FBindings[AAction]) do
    Result[I] := FBindings[AAction][I];
end;

procedure THotkeyBindings.Put(AAction: TPluginAction; const AChords: THotkeyChordArray);
var
  I: Integer;
begin
  SetLength(FBindings[AAction], Length(AChords));
  for I := 0 to High(AChords) do
    FBindings[AAction][I] := AChords[I];
end;

function THotkeyBindings.AddChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
var
  I, N: Integer;
begin
  if not AChord.IsAssigned then
    Exit(False);
  for I := 0 to High(FBindings[AAction]) do
    if FBindings[AAction][I].Equals(AChord) then
      Exit(False);
  N := Length(FBindings[AAction]);
  SetLength(FBindings[AAction], N + 1);
  FBindings[AAction][N] := AChord;
  Result := True;
end;

function THotkeyBindings.RemoveChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  for I := 0 to High(FBindings[AAction]) do
    if FBindings[AAction][I].Equals(AChord) then
    begin
      for J := I to High(FBindings[AAction]) - 1 do
        FBindings[AAction][J] := FBindings[AAction][J + 1];
      SetLength(FBindings[AAction], Length(FBindings[AAction]) - 1);
      Exit(True);
    end;
end;

function THotkeyBindings.Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
var
  NormKey: Word;
  NormShift: TShiftState;
  A: TPluginAction;
  I: Integer;
begin
  NormKey := NormalizeKey(AKey);
  NormShift := NormalizeShift(AShift);
  for A := Succ(paNone) to High(TPluginAction) do
    for I := 0 to High(FBindings[A]) do
      if FBindings[A][I].Matches(NormKey, NormShift) then
        Exit(A);
  Result := paNone;
end;

procedure THotkeyBindings.Load(AIni: TUnicodeIniFile);
var
  A: TPluginAction;
  Raw: string;
begin
  {Start from defaults so any key missing from the INI retains its default
   binding rather than becoming unbound. Users can explicitly disable a
   default by writing an empty value (e.g. "Settings=").}
  ResetToDefaults;
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    if not AIni.ValueExists(HOTKEYS_SECTION, ActionIniKey(A)) then
      Continue;
    Raw := AIni.ReadString(HOTKEYS_SECTION, ActionIniKey(A), '');
    if Raw.Trim = '' then
      FBindings[A] := nil
    else
      FBindings[A] := uHotkeysCodec.ChordsFromIniStr(Raw);
  end;
end;

procedure THotkeyBindings.Save(AIni: TUnicodeIniFile);
var
  A: TPluginAction;
begin
  for A := Succ(paNone) to High(TPluginAction) do
    AIni.WriteString(HOTKEYS_SECTION, ActionIniKey(A), uHotkeysCodec.ChordsToIniStr(FBindings[A]));
end;

procedure THotkeyBindings.ResetToDefaults;
var
  A: TPluginAction;
begin
  for A := Low(TPluginAction) to High(TPluginAction) do
    FBindings[A] := DefaultBinding(A);
end;

procedure THotkeyBindings.Assign(const AOther: THotkeyBindings);
var
  A: TPluginAction;
begin
  if AOther = nil then
    Exit;
  for A := Low(TPluginAction) to High(TPluginAction) do
    Put(A, AOther.Get(A));
end;

function THotkeyBindings.FindActionByChord(const AChord: THotkeyChord;
  AExcept: TPluginAction): TPluginAction;
var
  A: TPluginAction;
  I: Integer;
begin
  if not AChord.IsAssigned then
    Exit(paNone);
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    if A = AExcept then
      Continue;
    for I := 0 to High(FBindings[A]) do
      if FBindings[A][I].Equals(AChord) then
        Exit(A);
  end;
  Result := paNone;
end;

function THotkeyBindings.ReassignExclusive(AAction: TPluginAction;
  const AChords: THotkeyChordArray): TArray<TPluginAction>;
var
  I: Integer;
  Conflict: TPluginAction;
  Touched: array[TPluginAction] of Boolean;
  A: TPluginAction;
begin
  for A := Low(TPluginAction) to High(TPluginAction) do
    Touched[A] := False;
  for I := 0 to High(AChords) do
  begin
    Conflict := FindActionByChord(AChords[I], AAction);
    {Loop because a single chord could (in pathological INI-edited data)
     appear in more than one action's list; keep stripping until gone.}
    while Conflict <> paNone do
    begin
      RemoveChord(Conflict, AChords[I]);
      Touched[Conflict] := True;
      Conflict := FindActionByChord(AChords[I], AAction);
    end;
  end;
  Put(AAction, AChords);
  SetLength(Result, 0);
  for A := Succ(paNone) to High(TPluginAction) do
    if Touched[A] then
      Result := Result + [A];
end;

{Unit-level helpers}

const
  {Single source of truth for every TPluginAction's INI key + caption.
   Indexed by enum value: Delphi enforces one entry per TPluginAction
   at compile time, so adding a new action without an entry here
   produces an incomplete-initialization error rather than a silent ''
   INI key at runtime (which the original ladder did via its else
   branch, causing data loss in THotkeyBindings.Load/Save).}
  ACTIONS: array[TPluginAction] of TActionDescriptor = (
    (IniKey: '';                  Caption: ''),                                                          {paNone}
    (IniKey: 'Settings';          Caption: 'Settings'),                                                  {paSettings}
    (IniKey: 'ToggleToolbar';     Caption: 'Toggle toolbar'),                                            {paToggleToolbar}
    (IniKey: 'ToggleStatusBar';   Caption: 'Toggle statusbar'),                                          {paToggleStatusBar}
    (IniKey: 'ToggleTimecode';    Caption: 'Toggle timecode overlay'),                                   {paToggleTimecode}
    (IniKey: 'ToggleMaximize';    Caption: 'Toggle maximize'),                                           {paToggleMaximize}
    (IniKey: 'ToggleFullScreen';  Caption: 'Toggle full-screen'),                                        {paToggleFullScreen}
    (IniKey: 'HamburgerMenu';     Caption: 'Open hamburger menu'),                                       {paHamburgerMenu}
    (IniKey: 'CloseLister';       Caption: 'Close viewer'),                                              {paCloseLister}
    (IniKey: 'PrevFile';          Caption: 'Previous file'),                                             {paPrevFile}
    (IniKey: 'NextFile';          Caption: 'Next file'),                                                 {paNextFile}
    (IniKey: 'OpenInPlayer';      Caption: 'Open in default player'),                                    {paOpenInPlayer}
    (IniKey: 'RefreshExtraction'; Caption: 'Refresh frames'),                                            {paRefreshExtraction}
    (IniKey: 'ShuffleExtraction'; Caption: 'Shuffle frames (random positions)'),                         {paShuffleExtraction}
    (IniKey: 'PrevFrame';         Caption: 'Previous frame (single view)'),                              {paPrevFrame}
    (IniKey: 'NextFrame';         Caption: 'Next frame (single view)'),                                  {paNextFrame}
    (IniKey: 'FrameCountInc';     Caption: 'Increase frame count'),                                      {paFrameCountInc}
    (IniKey: 'FrameCountDec';     Caption: 'Decrease frame count'),                                      {paFrameCountDec}
    (IniKey: 'SaveFrame';         Caption: 'Save frame'),                                                {paSaveFrame}
    (IniKey: 'SaveFrames';        Caption: 'Save frames'),                                               {paSaveFrames}
    (IniKey: 'SaveView';          Caption: 'Save view (honour persisted resolution toggle)'),            {paSaveView}
    (IniKey: 'SaveViewLive';      Caption: 'Save view at view resolution (one-shot)'),                   {paSaveViewLive}
    (IniKey: 'SaveViewNative';    Caption: 'Save view at native size (one-shot)'),                       {paSaveViewNative}
    (IniKey: 'SelectAllFrames';   Caption: 'Select all frames'),                                         {paSelectAllFrames}
    (IniKey: 'CopyFrame';         Caption: 'Copy frame to clipboard'),                                   {paCopyFrame}
    (IniKey: 'CopyView';          Caption: 'Copy view to clipboard (honour persisted resolution toggle)'), {paCopyView}
    (IniKey: 'CopyViewLive';      Caption: 'Copy view at view resolution (one-shot)'),                   {paCopyViewLive}
    (IniKey: 'CopyViewNative';    Caption: 'Copy view at native size (one-shot)'),                       {paCopyViewNative}
    (IniKey: 'ZoomIn';            Caption: 'Zoom in'),                                                   {paZoomIn}
    (IniKey: 'ZoomOut';           Caption: 'Zoom out'),                                                  {paZoomOut}
    (IniKey: 'ZoomReset';         Caption: 'Reset zoom'),                                                {paZoomReset}
    (IniKey: 'ViewModeSmartGrid'; Caption: 'View mode: Smart grid'),                                     {paViewModeSmartGrid}
    (IniKey: 'ViewModeGrid';      Caption: 'View mode: Grid'),                                           {paViewModeGrid}
    (IniKey: 'ViewModeScroll';    Caption: 'View mode: Scroll'),                                         {paViewModeScroll}
    (IniKey: 'ViewModeFilmstrip'; Caption: 'View mode: Filmstrip'),                                      {paViewModeFilmstrip}
    (IniKey: 'ViewModeSingle';    Caption: 'View mode: Single frame')                                    {paViewModeSingle}
  );

function ActionIniKey(AAction: TPluginAction): string;
begin
  Result := ACTIONS[AAction].IniKey;
end;

function ActionCaption(AAction: TPluginAction): string;
begin
  Result := ACTIONS[AAction].Caption;
end;

function DefaultBinding(AAction: TPluginAction): THotkeyChordArray;
begin
  {Default-chord assignments still ride a case ladder because Delphi
   const aggregates cannot nest record literals inside dynamic-array
   fields. The bug class the violation flagged (silent '' INI key) is
   gone via the ACTIONS table; a missing branch here returns nil which
   is observable in the dialog (action has no shortcut) rather than
   silently corrupting INI data.

   Bare Left/Right bind to frame navigation so the single-view
   "slideshow" feel is the default. paPrevFrame/paNextFrame have a
   vmSingle guard in the dispatcher — in other modes the action's
   ExecuteHotkey returns False and the keystroke quietly does nothing.
   Ctrl+Left/Ctrl+Right are kept as a modifier-qualified alias.}
  case AAction of
    paSettings:           Result := [THotkeyChord.Make(VK_F2, [])];
    paToggleToolbar:      Result := [THotkeyChord.Make(VK_F4, [])];
    paToggleStatusBar:    Result := [THotkeyChord.Make(VK_F3, [])];
    paToggleTimecode:     Result := [THotkeyChord.Make(Ord('T'), [])];
    paToggleMaximize:     Result := [THotkeyChord.Make(VK_F11, [])];
    paToggleFullScreen:   Result := [THotkeyChord.Make(VK_RETURN, [ssAlt])];
    paHamburgerMenu:      Result := [THotkeyChord.Make(VK_OEM_3, [])];
    paCloseLister:        Result := [THotkeyChord.Make(VK_ESCAPE, [])];
    paPrevFile:           Result := [THotkeyChord.Make(VK_PRIOR, []),
                                     THotkeyChord.Make(VK_BACK, []),
                                     THotkeyChord.Make(Ord('Z'), [])];
    paNextFile:           Result := [THotkeyChord.Make(VK_NEXT, []),
                                     THotkeyChord.Make(VK_SPACE, [])];
    paOpenInPlayer:       Result := [THotkeyChord.Make(VK_RETURN, [])];
    paRefreshExtraction:  Result := [THotkeyChord.Make(Ord('R'), [])];
    paShuffleExtraction:  Result := [THotkeyChord.Make(Ord('R'), [ssCtrl])];
    paPrevFrame:          Result := [THotkeyChord.Make(VK_LEFT, []),
                                     THotkeyChord.Make(VK_LEFT, [ssCtrl])];
    paNextFrame:          Result := [THotkeyChord.Make(VK_RIGHT, []),
                                     THotkeyChord.Make(VK_RIGHT, [ssCtrl])];
    paFrameCountInc:      Result := [THotkeyChord.Make(VK_UP, [ssCtrl])];
    paFrameCountDec:      Result := [THotkeyChord.Make(VK_DOWN, [ssCtrl])];
    paSaveFrame:          Result := [THotkeyChord.Make(Ord('S'), [ssCtrl])];
    paSaveView:           Result := [THotkeyChord.Make(Ord('S'), [ssCtrl, ssShift])];
    {Save side: Shift modifier. Mnemonics L=Live (view-resolution),
     N=Native (source pixel dimensions).}
    paSaveViewLive:       Result := [THotkeyChord.Make(Ord('L'), [ssCtrl, ssShift])];
    paSaveViewNative:     Result := [THotkeyChord.Make(Ord('N'), [ssCtrl, ssShift])];
    paSaveFrames:         Result := [THotkeyChord.Make(Ord('S'), [ssCtrl, ssAlt, ssShift])];
    paSelectAllFrames:    Result := [THotkeyChord.Make(Ord('A'), [ssCtrl])];
    paCopyFrame:          Result := [THotkeyChord.Make(Ord('C'), [ssCtrl])];
    paCopyView:           Result := [THotkeyChord.Make(Ord('C'), [ssCtrl, ssShift])];
    {Copy side: Alt modifier (Shift was already taken by Save side).}
    paCopyViewLive:       Result := [THotkeyChord.Make(Ord('L'), [ssCtrl, ssAlt])];
    paCopyViewNative:     Result := [THotkeyChord.Make(Ord('N'), [ssCtrl, ssAlt])];
    paZoomIn:             Result := [THotkeyChord.Make(VK_OEM_PLUS, [])];
    paZoomOut:            Result := [THotkeyChord.Make(VK_OEM_MINUS, [])];
    paZoomReset:          Result := [THotkeyChord.Make(Ord('0'), [])];
    paViewModeSmartGrid:  Result := [THotkeyChord.Make(Ord('1'), [ssCtrl])];
    paViewModeGrid:       Result := [THotkeyChord.Make(Ord('2'), [ssCtrl])];
    paViewModeScroll:     Result := [THotkeyChord.Make(Ord('3'), [ssCtrl])];
    paViewModeFilmstrip:  Result := [THotkeyChord.Make(Ord('4'), [ssCtrl])];
    paViewModeSingle:     Result := [THotkeyChord.Make(Ord('5'), [ssCtrl])];
  else
    Result := nil;
  end;
end;

end.
