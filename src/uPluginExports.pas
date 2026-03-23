/// WLX plugin API exported functions.
/// These are called by Total Commander to interact with the plugin.
unit uPluginExports;

interface

uses
  Winapi.Windows, uWlxAPI;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadNext(ParentWin: HWND; ListWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): Integer; stdcall;
function ListLoadNextW(ParentWin: HWND; ListWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): Integer; stdcall;
procedure ListCloseWindow(ListWin: HWND); stdcall;
procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
function ListGetPreviewBitmap(FileToLoad: PAnsiChar; Width, Height: Integer;
  ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;
function ListGetPreviewBitmapW(FileToLoad: PWideChar; Width, Height: Integer;
  ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;

implementation

uses
  System.SysUtils, System.AnsiStrings, uSettings;

var
  GSettings: TPluginSettings;
  GPluginDir: string;

/// Internal handler shared by ListLoad and ListLoadW.
function DoListLoad(ParentWin: HWND; const AFileName: string; ShowFlags: Integer): HWND;
begin
  { Phase 3: will create the plugin window here }
  Result := 0;
end;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
begin
  Result := DoListLoad(ParentWin, string(AnsiString(FileToLoad)), ShowFlags);
end;

function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
begin
  Result := DoListLoad(ParentWin, string(FileToLoad), ShowFlags);
end;

/// Reuses an existing plugin window for a new file (smoother navigation).
function DoListLoadNext(ParentWin: HWND; ListWin: HWND; const AFileName: string; ShowFlags: Integer): Integer;
begin
  { Phase 3: will reload the plugin window with a new file }
  Result := LISTPLUGIN_ERROR;
end;

function ListLoadNext(ParentWin: HWND; ListWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): Integer; stdcall;
begin
  Result := DoListLoadNext(ParentWin, ListWin, string(AnsiString(FileToLoad)), ShowFlags);
end;

function ListLoadNextW(ParentWin: HWND; ListWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): Integer; stdcall;
begin
  Result := DoListLoadNext(ParentWin, ListWin, string(FileToLoad), ShowFlags);
end;

procedure ListCloseWindow(ListWin: HWND); stdcall;
begin
  { Phase 3: will destroy the plugin window here }
end;

procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
var
  Extensions: TArray<string>;
  Builder: string;
  I: Integer;
  DS: AnsiString;
begin
  { Build detect string from configured or default extension list.
    TC may call this before ListSetDefaultParams, so GSettings can be nil. }
  if Assigned(GSettings) then
    Extensions := GSettings.ExtensionList.Split([',', ' '])
  else
    Extensions := DEF_EXTENSION_LIST.Split([',', ' ']);

  Builder := '';
  for I := 0 to High(Extensions) do
  begin
    Extensions[I] := Extensions[I].Trim.ToUpper;
    if Extensions[I] = '' then
      Continue;
    if Builder <> '' then
      Builder := Builder + ' | ';
    Builder := Builder + 'EXT="' + Extensions[I] + '"';
  end;

  DS := AnsiString(Builder);
  if MaxLen > 0 then
    System.AnsiStrings.StrLCopy(DetectString, PAnsiChar(DS), MaxLen - 1);
end;

function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
begin
  Result := LISTPLUGIN_ERROR;
end;

function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
begin
  case Command of
    lc_Copy:
      begin
        { Phase 11: copy frame to clipboard }
        Result := LISTPLUGIN_OK;
      end;
    lc_NewParams:
      begin
        { Phase 5: re-layout on resize }
        Result := LISTPLUGIN_OK;
      end;
  else
    Result := LISTPLUGIN_ERROR;
  end;
end;

procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
var
  ModulePath: array[0..MAX_PATH] of Char;
begin
  GetModuleFileName(HInstance, ModulePath, MAX_PATH);
  GPluginDir := ExtractFilePath(string(ModulePath));

  FreeAndNil(GSettings);
  GSettings := TPluginSettings.Create(GPluginDir + 'VideoThumb.ini');
  GSettings.Load;
end;

/// Returns a preview bitmap for TC thumbnail view.
function DoGetPreviewBitmap(const AFileName: string; Width, Height: Integer): HBITMAP;
begin
  { Phase 2+: will extract a single midpoint frame and return as HBITMAP }
  Result := 0;
end;

function ListGetPreviewBitmap(FileToLoad: PAnsiChar; Width, Height: Integer;
  ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;
begin
  Result := DoGetPreviewBitmap(string(AnsiString(FileToLoad)), Width, Height);
end;

function ListGetPreviewBitmapW(FileToLoad: PWideChar; Width, Height: Integer;
  ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;
begin
  Result := DoGetPreviewBitmap(string(FileToLoad), Width, Height);
end;

initialization

finalization
  FreeAndNil(GSettings);

end.
