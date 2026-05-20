{Configurable-hotkey machinery. Each action can hold many chords (key +
 modifiers). Numpad keys (VK_NUMPAD0..9, VK_ADD/SUBTRACT/DECIMAL) are
 collapsed onto their letter-row equivalents at Lookup time so a single
 binding handles both.}
unit Hotkeys;

interface

uses
  System.Classes, System.SysUtils,
  IniStore;

type
  {Tab is intentionally not listed; it is reserved for VCL focus cycling.}
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
    Key: Word;               {VK_* code; 0 = unbound}
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

  {Positional aggregate `array[TPluginAction] of TActionDescriptor`
   forces a compile error on a missing entry; the prior case ladder
   silently returned '' and caused INI data loss.}
  TActionDescriptor = record
    IniKey: string;
    Caption: string;
  end;

  THotkeyBindings = class
  private
    FBindings: array [TPluginAction] of THotkeyChordArray;
  public
    constructor Create;
    {Returns a copy; callers mutate through the Put/Add/Remove API.}
    function Get(AAction: TPluginAction): THotkeyChordArray;
    procedure Put(AAction: TPluginAction; const AChords: THotkeyChordArray);
    {Returns False when AChord is already present.}
    function AddChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
    function RemoveChord(AAction: TPluginAction; const AChord: THotkeyChord): Boolean;
    {Normalises numpad aliases before matching. paNone on no match.}
    function Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
    {Section [hotkeys], chord separator '|'.}
    procedure Load(const AIni: IIniFile);
    procedure Save(const AIni: IIniFile);
    procedure ResetToDefaults;
    procedure Assign(const AOther: THotkeyBindings);
    function FindActionByChord(const AChord: THotkeyChord;
      AExcept: TPluginAction = paNone): TPluginAction;
    {Takes ownership of any chord currently held by another action.
     Returns the list of evicted actions (excluding AAction itself) so
     the settings dialog can refresh their rows.}
    function ReassignExclusive(AAction: TPluginAction;
      const AChords: THotkeyChordArray): TArray<TPluginAction>;
  end;

const
  HOTKEYS_SECTION = 'hotkeys';
  CHORD_SEPARATOR = '|';

function DefaultBinding(AAction: TPluginAction): THotkeyChordArray;

function ActionIniKey(AAction: TPluginAction): string;

function ActionCaption(AAction: TPluginAction): string;

implementation

uses
  Winapi.Windows,
  HotkeysCodec, HotkeysDisplay;

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
      {Locale caveat: collapsed onto VK_OEM_PERIOD. European numpads
       producing ',' would prefer VK_OEM_COMMA but Windows does not
       expose layout-aware VK mapping at this layer.}
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
  Result := HotkeysDisplay.ChordToDisplayStr(Self);
end;

function THotkeyChord.ToIniStr: string;
begin
  Result := HotkeysCodec.ChordToIniStr(Self);
end;

class function THotkeyChord.Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord;
begin
  {Normalise at construction so numpad/OEM aliases captured from the
   shortcut editor survive INI round-trip (VKToName would otherwise
   serialise them as empty).}
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
  Result := HotkeysCodec.ChordFromIniStr(AValue);
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

procedure THotkeyBindings.Load(const AIni: IIniFile);
var
  A: TPluginAction;
  Raw: string;
begin
  {Defaults first so missing keys keep their default. An explicit empty
   value ("Settings=") disables the default.}
  ResetToDefaults;
  for A := Succ(paNone) to High(TPluginAction) do
  begin
    if not AIni.ValueExists(HOTKEYS_SECTION, ActionIniKey(A)) then
      Continue;
    Raw := AIni.ReadString(HOTKEYS_SECTION, ActionIniKey(A), '');
    if Raw.Trim = '' then
      FBindings[A] := nil
    else
      FBindings[A] := HotkeysCodec.ChordsFromIniStr(Raw);
  end;
end;

procedure THotkeyBindings.Save(const AIni: IIniFile);
var
  A: TPluginAction;
begin
  for A := Succ(paNone) to High(TPluginAction) do
    AIni.WriteString(HOTKEYS_SECTION, ActionIniKey(A), HotkeysCodec.ChordsToIniStr(FBindings[A]));
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
    {Loop handles pathological INI-edited duplicates across actions.}
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

const
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
  {Case ladder is required: Delphi const aggregates cannot nest record
   literals inside dynamic-array fields. A missing branch yields nil
   (action has no shortcut) which is harmless and visible in the dialog.}
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
    {Save: Shift modifier. L=Live (view resolution), N=Native (source).}
    paSaveViewLive:       Result := [THotkeyChord.Make(Ord('L'), [ssCtrl, ssShift])];
    paSaveViewNative:     Result := [THotkeyChord.Make(Ord('N'), [ssCtrl, ssShift])];
    paSaveFrames:         Result := [THotkeyChord.Make(Ord('S'), [ssCtrl, ssAlt, ssShift])];
    paSelectAllFrames:    Result := [THotkeyChord.Make(Ord('A'), [ssCtrl])];
    paCopyFrame:          Result := [THotkeyChord.Make(Ord('C'), [ssCtrl])];
    paCopyView:           Result := [THotkeyChord.Make(Ord('C'), [ssCtrl, ssShift])];
    {Copy: Alt modifier (Shift is taken by Save).}
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
