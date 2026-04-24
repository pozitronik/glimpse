{Configurable-hotkey machinery for the WLX plugin.

 Defines the enum of command-style plugin actions, a chord record that
 pairs a VK_* key with a modifier set, and a binding table that persists
 to INI and exposes a Lookup used by the form's OnKeyDown dispatcher.

 Numpad digits and symbol aliases (VK_NUMPAD0..9, VK_ADD, VK_SUBTRACT,
 VK_DECIMAL) are collapsed to their letter-row equivalents at Lookup
 time so the single binding "Zoom reset = 0" matches both top-row 0 and
 numpad 0 without the UI having to show two entries.

 Pure: no VCL, no form references. TestHotkeys covers the record and
 the binding table end-to-end.}
unit uHotkeys;

interface

uses
  System.Classes, System.SysUtils, System.IniFiles;

type
  {Command-style actions the user can assign hotkeys to. Directional /
   navigation behaviour (bare arrows, Ctrl+arrows, Space/Backspace for
   file nav) stays hardcoded in the form and is not represented here.}
  TPluginAction = (paNone,
    {Window / view}
    paSettings, paToggleToolbar, paToggleStatusBar, paToggleTimecode,
    paToggleMaximize, paToggleFullScreen, paHamburgerMenu, paCloseLister,
    {File}
    paOpenInPlayer, paRefreshExtraction,
    {Frame output}
    paSaveSingleFrame, paSaveAllFrames, paSaveCombined, paSaveSelected,
    paSelectAllFrames, paCopyToClipboard, paCopyAllToClipboard,
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
    function ToDisplayStr: string;
    function ToIniStr: string;
    class function Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord; static;
    class function None: THotkeyChord; static;
    class function FromIniStr(const AValue: string): THotkeyChord; static;
  end;

  THotkeyBindings = class
  private
    FBindings: array [TPluginAction] of THotkeyChord;
  public
    constructor Create;
    function Get(AAction: TPluginAction): THotkeyChord;
    procedure Put(AAction: TPluginAction; const AChord: THotkeyChord);
    function Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
    procedure Load(AIni: TIniFile);
    procedure Save(AIni: TIniFile);
    procedure ResetToDefaults;
  end;

const
  HOTKEYS_SECTION = 'hotkeys';

{Default chord (or THotkeyChord.None for intentionally-unbound) for an action.}
function DefaultBinding(AAction: TPluginAction): THotkeyChord;

{Short INI key used to serialise the action (without the 'pa' enum prefix).}
function ActionIniKey(AAction: TPluginAction): string;

{Human-readable caption for the action, used by the settings dialog UI.}
function ActionCaption(AAction: TPluginAction): string;

implementation

uses
  Winapi.Windows;

{Key-to-name canonical table for INI serialisation and display. Maps in
 both directions; parsing is case-insensitive via SameText below.}
type
  TKeyName = record
    Key: Word;
    Name: string;
  end;

const
  {Fixed named keys. Letter/digit keys are handled separately (single char).
   VK_OEM_* codes are the subset the plugin actually uses as hotkeys today;
   adding more is a matter of extending this array.}
  KEY_NAMES: array [0 .. 20] of TKeyName = (
    (Key: VK_RETURN; Name: 'Enter'),
    (Key: VK_ESCAPE; Name: 'Escape'),
    (Key: VK_SPACE; Name: 'Space'),
    (Key: VK_TAB; Name: 'Tab'),
    (Key: VK_BACK; Name: 'Backspace'),
    (Key: VK_DELETE; Name: 'Delete'),
    (Key: VK_INSERT; Name: 'Insert'),
    (Key: VK_HOME; Name: 'Home'),
    (Key: VK_END; Name: 'End'),
    (Key: VK_PRIOR; Name: 'PageUp'),
    (Key: VK_NEXT; Name: 'PageDown'),
    (Key: VK_LEFT; Name: 'Left'),
    (Key: VK_RIGHT; Name: 'Right'),
    (Key: VK_UP; Name: 'Up'),
    (Key: VK_DOWN; Name: 'Down'),
    (Key: VK_OEM_PLUS; Name: '+'),
    (Key: VK_OEM_MINUS; Name: '-'),
    (Key: VK_OEM_COMMA; Name: ','),
    (Key: VK_OEM_PERIOD; Name: '.'),
    (Key: VK_OEM_3; Name: '`'),
    (Key: VK_OEM_2; Name: '/'));

function VKToName(AKey: Word): string;
var
  I: Integer;
begin
  if (AKey >= VK_F1) and (AKey <= VK_F12) then
    Exit(Format('F%d', [AKey - VK_F1 + 1]));
  if (AKey >= Ord('0')) and (AKey <= Ord('9')) then
    Exit(Chr(AKey));
  if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
    Exit(Chr(AKey));
  for I := Low(KEY_NAMES) to High(KEY_NAMES) do
    if KEY_NAMES[I].Key = AKey then
      Exit(KEY_NAMES[I].Name);
  Result := '';
end;

function NameToVK(const AName: string): Word;
var
  S: string;
  I, N: Integer;
begin
  S := AName.Trim;
  if S = '' then
    Exit(0);
  {F-keys: "F1".."F12"}
  if (Length(S) >= 2) and ((S[1] = 'F') or (S[1] = 'f')) then
  begin
    if TryStrToInt(Copy(S, 2, Length(S) - 1), N) and (N >= 1) and (N <= 12) then
      Exit(VK_F1 + N - 1);
  end;
  {Single char: letter or digit}
  if Length(S) = 1 then
  begin
    if CharInSet(S[1], ['0' .. '9']) then
      Exit(Ord(S[1]));
    if CharInSet(S[1], ['A' .. 'Z', 'a' .. 'z']) then
      Exit(Ord(UpCase(S[1])));
  end;
  for I := Low(KEY_NAMES) to High(KEY_NAMES) do
    if SameText(KEY_NAMES[I].Name, S) then
      Exit(KEY_NAMES[I].Key);
  Result := 0;
end;

{Collapse keyboard aliases so a single binding covers both top-row and
 numpad equivalents; called on incoming events in Lookup, never applied
 to stored values.}
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

function THotkeyChord.ToDisplayStr: string;
var
  KeyName: string;
begin
  if not IsAssigned then
    Exit('');
  KeyName := VKToName(Key);
  if KeyName = '' then
    Exit('');
  Result := '';
  if ssCtrl in Modifiers then
    Result := Result + 'Ctrl+';
  if ssShift in Modifiers then
    Result := Result + 'Shift+';
  if ssAlt in Modifiers then
    Result := Result + 'Alt+';
  Result := Result + KeyName;
end;

function THotkeyChord.ToIniStr: string;
begin
  Result := ToDisplayStr;
end;

class function THotkeyChord.Make(AKey: Word; const AModifiers: TShiftState): THotkeyChord;
begin
  Result.Key := AKey;
  Result.Modifiers := NormalizeShift(AModifiers);
end;

class function THotkeyChord.None: THotkeyChord;
begin
  Result.Key := 0;
  Result.Modifiers := [];
end;

class function THotkeyChord.FromIniStr(const AValue: string): THotkeyChord;
var
  Parts: TArray<string>;
  I: Integer;
  Token: string;
  Mods: TShiftState;
  KeyCode: Word;
begin
  Result := None;
  if AValue.Trim = '' then
    Exit;
  Parts := AValue.Split(['+']);
  if Length(Parts) = 0 then
    Exit;
  Mods := [];
  KeyCode := 0;
  for I := 0 to High(Parts) do
  begin
    Token := Parts[I].Trim;
    if SameText(Token, 'Ctrl') then
      Include(Mods, ssCtrl)
    else if SameText(Token, 'Shift') then
      Include(Mods, ssShift)
    else if SameText(Token, 'Alt') then
      Include(Mods, ssAlt)
    else
      {Last non-modifier token is the key itself. Empty tokens appear when
       the key part is '+' (VK_OEM_PLUS) split on '+' — the final split
       element is '' immediately after an empty-before-'+'. Only assign
       when we find a recognised key; unparseable values leave Result as
       None so callers fall back to defaults.}
      if (Token <> '') and (KeyCode = 0) then
        KeyCode := NameToVK(Token);
  end;
  {Special case: the key '+' when used bare is Split into ['', ''] (split on
   '+' with two empty neighbours). Recover it by checking the raw input.}
  if (KeyCode = 0) and (AValue.Trim = '+') then
    KeyCode := VK_OEM_PLUS;
  if KeyCode = 0 then
    Exit;
  Result.Key := KeyCode;
  Result.Modifiers := Mods;
end;

{THotkeyBindings}

constructor THotkeyBindings.Create;
begin
  inherited;
  ResetToDefaults;
end;

function THotkeyBindings.Get(AAction: TPluginAction): THotkeyChord;
begin
  Result := FBindings[AAction];
end;

procedure THotkeyBindings.Put(AAction: TPluginAction; const AChord: THotkeyChord);
begin
  FBindings[AAction] := AChord;
end;

function THotkeyBindings.Lookup(AKey: Word; const AShift: TShiftState): TPluginAction;
var
  NormKey: Word;
  NormShift: TShiftState;
  A: TPluginAction;
begin
  NormKey := NormalizeKey(AKey);
  NormShift := NormalizeShift(AShift);
  for A := Succ(paNone) to High(TPluginAction) do
    if FBindings[A].Matches(NormKey, NormShift) then
      Exit(A);
  Result := paNone;
end;

procedure THotkeyBindings.Load(AIni: TIniFile);
var
  A: TPluginAction;
  Raw: string;
  Parsed: THotkeyChord;
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
    begin
      FBindings[A] := THotkeyChord.None;
      Continue;
    end;
    Parsed := THotkeyChord.FromIniStr(Raw);
    if Parsed.IsAssigned then
      FBindings[A] := Parsed;
    {Unparseable values keep the default — no silent unbind for typos.}
  end;
end;

procedure THotkeyBindings.Save(AIni: TIniFile);
var
  A: TPluginAction;
begin
  for A := Succ(paNone) to High(TPluginAction) do
    AIni.WriteString(HOTKEYS_SECTION, ActionIniKey(A), FBindings[A].ToIniStr);
end;

procedure THotkeyBindings.ResetToDefaults;
var
  A: TPluginAction;
begin
  for A := Low(TPluginAction) to High(TPluginAction) do
    FBindings[A] := DefaultBinding(A);
end;

{Unit-level helpers}

function DefaultBinding(AAction: TPluginAction): THotkeyChord;
begin
  case AAction of
    paSettings:
      Result := THotkeyChord.Make(VK_F2, []);
    paToggleToolbar:
      Result := THotkeyChord.Make(VK_F4, []);
    paToggleStatusBar:
      Result := THotkeyChord.Make(VK_F3, []);
    paToggleTimecode:
      Result := THotkeyChord.Make(Ord('T'), []);
    paToggleMaximize:
      Result := THotkeyChord.Make(VK_F11, []);
    paToggleFullScreen:
      Result := THotkeyChord.Make(VK_RETURN, [ssAlt]);
    paHamburgerMenu:
      Result := THotkeyChord.Make(VK_OEM_3, []);
    paCloseLister:
      Result := THotkeyChord.Make(VK_ESCAPE, []);
    paOpenInPlayer:
      Result := THotkeyChord.Make(VK_RETURN, []);
    paRefreshExtraction:
      Result := THotkeyChord.Make(Ord('R'), []);
    paSaveSingleFrame:
      Result := THotkeyChord.Make(Ord('S'), [ssCtrl]);
    paSaveAllFrames:
      Result := THotkeyChord.Make(Ord('S'), [ssCtrl, ssAlt]);
    paSaveCombined:
      Result := THotkeyChord.Make(Ord('S'), [ssCtrl, ssShift]);
    paSaveSelected:
      Result := THotkeyChord.None;
    paSelectAllFrames:
      Result := THotkeyChord.Make(Ord('A'), [ssCtrl]);
    paCopyToClipboard:
      Result := THotkeyChord.Make(Ord('C'), [ssCtrl]);
    paCopyAllToClipboard:
      Result := THotkeyChord.Make(Ord('C'), [ssCtrl, ssShift]);
    paZoomIn:
      Result := THotkeyChord.Make(VK_OEM_PLUS, []);
    paZoomOut:
      Result := THotkeyChord.Make(VK_OEM_MINUS, []);
    paZoomReset:
      Result := THotkeyChord.Make(Ord('0'), []);
    paViewModeSmartGrid:
      Result := THotkeyChord.Make(Ord('1'), [ssCtrl]);
    paViewModeGrid:
      Result := THotkeyChord.Make(Ord('2'), [ssCtrl]);
    paViewModeScroll:
      Result := THotkeyChord.Make(Ord('3'), [ssCtrl]);
    paViewModeFilmstrip:
      Result := THotkeyChord.Make(Ord('4'), [ssCtrl]);
    paViewModeSingle:
      Result := THotkeyChord.Make(Ord('5'), [ssCtrl]);
  else
    Result := THotkeyChord.None;
  end;
end;

function ActionIniKey(AAction: TPluginAction): string;
begin
  case AAction of
    paSettings: Result := 'Settings';
    paToggleToolbar: Result := 'ToggleToolbar';
    paToggleStatusBar: Result := 'ToggleStatusBar';
    paToggleTimecode: Result := 'ToggleTimecode';
    paToggleMaximize: Result := 'ToggleMaximize';
    paToggleFullScreen: Result := 'ToggleFullScreen';
    paHamburgerMenu: Result := 'HamburgerMenu';
    paCloseLister: Result := 'CloseLister';
    paOpenInPlayer: Result := 'OpenInPlayer';
    paRefreshExtraction: Result := 'RefreshExtraction';
    paSaveSingleFrame: Result := 'SaveSingleFrame';
    paSaveAllFrames: Result := 'SaveAllFrames';
    paSaveCombined: Result := 'SaveCombined';
    paSaveSelected: Result := 'SaveSelected';
    paSelectAllFrames: Result := 'SelectAllFrames';
    paCopyToClipboard: Result := 'CopyToClipboard';
    paCopyAllToClipboard: Result := 'CopyAllToClipboard';
    paZoomIn: Result := 'ZoomIn';
    paZoomOut: Result := 'ZoomOut';
    paZoomReset: Result := 'ZoomReset';
    paViewModeSmartGrid: Result := 'ViewModeSmartGrid';
    paViewModeGrid: Result := 'ViewModeGrid';
    paViewModeScroll: Result := 'ViewModeScroll';
    paViewModeFilmstrip: Result := 'ViewModeFilmstrip';
    paViewModeSingle: Result := 'ViewModeSingle';
  else
    Result := '';
  end;
end;

function ActionCaption(AAction: TPluginAction): string;
begin
  case AAction of
    paSettings: Result := 'Settings';
    paToggleToolbar: Result := 'Toggle toolbar';
    paToggleStatusBar: Result := 'Toggle statusbar';
    paToggleTimecode: Result := 'Toggle timecode overlay';
    paToggleMaximize: Result := 'Toggle maximize';
    paToggleFullScreen: Result := 'Toggle full-screen';
    paHamburgerMenu: Result := 'Open hamburger menu';
    paCloseLister: Result := 'Close viewer';
    paOpenInPlayer: Result := 'Open in default player';
    paRefreshExtraction: Result := 'Refresh frames';
    paSaveSingleFrame: Result := 'Save frame';
    paSaveAllFrames: Result := 'Save all frames';
    paSaveCombined: Result := 'Save combined image';
    paSaveSelected: Result := 'Save selected frames';
    paSelectAllFrames: Result := 'Select all frames';
    paCopyToClipboard: Result := 'Copy frame to clipboard';
    paCopyAllToClipboard: Result := 'Copy all frames to clipboard';
    paZoomIn: Result := 'Zoom in';
    paZoomOut: Result := 'Zoom out';
    paZoomReset: Result := 'Reset zoom';
    paViewModeSmartGrid: Result := 'View mode: Smart grid';
    paViewModeGrid: Result := 'View mode: Grid';
    paViewModeScroll: Result := 'View mode: Scroll';
    paViewModeFilmstrip: Result := 'View mode: Filmstrip';
    paViewModeSingle: Result := 'View mode: Single frame';
  else
    Result := '';
  end;
end;

end.
