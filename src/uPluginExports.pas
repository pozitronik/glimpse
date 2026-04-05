{ WLX plugin API exported functions.
  These are called by Total Commander to interact with the plugin. }
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
function ListGetPreviewBitmap(FileToLoad: PAnsiChar; Width, Height: Integer; ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;
function ListGetPreviewBitmapW(FileToLoad: PWideChar; Width, Height: Integer; ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;

implementation

uses
  System.SysUtils, System.AnsiStrings, System.IOUtils, Vcl.Controls,
  uSettings, uFFmpegLocator, uPluginForm, uCache, uDebugLog;

var
  GSettings: TPluginSettings;
  GPluginDir: string;
  GFFmpegPath: string;

procedure Log(const AMsg: string);
begin
  DebugLog('Plugin', AMsg);
end;

{ Resolves a TC-provided window handle to our plugin form, or nil. }
function FindPluginForm(ListWin: HWND): TPluginForm;
var
  Ctrl: TWinControl;
begin
  Ctrl := FindControl(ListWin);
  if Ctrl is TPluginForm then
    Result := TPluginForm(Ctrl)
  else
    Result := nil;
end;

{ Internal handler shared by ListLoad and ListLoadW. }
function DoListLoad(ParentWin: HWND; const AFileName: string; ShowFlags: Integer): HWND;
var
  Form: TPluginForm;
begin
  Result := 0;
  Log(Format('DoListLoad: ParentWin=$%s File=%s Flags=%d', [IntToHex(ParentWin), AFileName, ShowFlags]));
  try
    Log(Format('DoListLoad: ffmpegPath=%s', [GFFmpegPath]));
    Form := TPluginForm.CreateForPlugin(ParentWin, AFileName, GSettings, GFFmpegPath);
    Form.ApplyListerParams(ShowFlags);
    Result := Form.Handle;
    Log(Format('DoListLoad: Form created, Handle=$%s IsWindow=%s Visible=%s Parent=$%s',
      [IntToHex(Result), BoolToStr(IsWindow(Result), True),
       BoolToStr(IsWindowVisible(Result), True), IntToHex(GetParent(Result))]));
  except
    on E: Exception do
    begin
      Log(Format('DoListLoad: EXCEPTION %s: %s', [E.ClassName, E.Message]));
      MessageBox(ParentWin, PChar(Format('Glimpse: %s', [E.Message])),
        'Glimpse', MB_OK or MB_ICONERROR);
    end;
  end;
end;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
begin
  Log('ListLoad (ANSI)');
  Result := DoListLoad(ParentWin, string(AnsiString(FileToLoad)), ShowFlags);
end;

function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
begin
  Log('ListLoadW (Unicode)');
  Result := DoListLoad(ParentWin, string(FileToLoad), ShowFlags);
end;

{ Reuses an existing plugin window for a new file (smoother navigation). }
function DoListLoadNext(ParentWin: HWND; ListWin: HWND; const AFileName: string; ShowFlags: Integer): Integer;
var
  Form: TPluginForm;
begin
  Log(Format('DoListLoadNext: ListWin=$%s File=%s', [IntToHex(ListWin), AFileName]));
  Form := FindPluginForm(ListWin);
  if Form <> nil then
  begin
    try
      Form.LoadFile(AFileName);
      Form.ApplyListerParams(ShowFlags);
      Result := LISTPLUGIN_OK;
    except
      on E: Exception do
      begin
        Log(Format('DoListLoadNext: EXCEPTION %s: %s', [E.ClassName, E.Message]));
        Result := LISTPLUGIN_ERROR;
      end;
    end;
  end
  else
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
var
  Form: TPluginForm;
begin
  Log(Format('ListCloseWindow: $%s', [IntToHex(ListWin)]));
  Form := FindPluginForm(ListWin);
  if Form <> nil then
    Form.Free;
end;

procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
var
  Extensions: TArray<string>;
  Builder: string;
  I: Integer;
  DS: AnsiString;
begin
  Extensions := GSettings.ExtensionList.Split([',', ' ']);

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

  { MULTIMEDIA keyword tells TC to override its built-in media viewer }
  Builder := 'MULTIMEDIA & (' + Builder + ')';
  DS := AnsiString(Builder);
  if MaxLen > 0 then
    System.AnsiStrings.StrLCopy(DetectString, PAnsiChar(DS), MaxLen - 1);

  Log(Format('ListGetDetectString: MaxLen=%d len=%d str=%s', [MaxLen, Length(DS), string(DS)]));
end;

function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
begin
  Result := LISTPLUGIN_ERROR;
end;

function ListSendCommand(ListWin: HWND; Command, Parameter: Integer): Integer; stdcall;
var
  Form: TPluginForm;
begin
  Form := FindPluginForm(ListWin);
  case Command of
    lc_Copy:
      begin
        if Form <> nil then
          Form.CopyFrameToClipboard;
        Result := LISTPLUGIN_OK;
      end;
    lc_NewParams:
      begin
        if Form <> nil then
          Form.ApplyListerParams(Parameter);
        Result := LISTPLUGIN_OK;
      end;
  else
    Result := LISTPLUGIN_ERROR;
  end;
end;

procedure ListSetDefaultParams(dps: PListDefaultParamStruct); stdcall;
var
  ModulePath: array[0..MAX_PATH] of Char;
  NewSettings: TPluginSettings;
begin
  GetModuleFileName(HInstance, ModulePath, MAX_PATH);
  GPluginDir := ExtractFilePath(string(ModulePath));
  {$IFDEF DEBUG}
  uDebugLog.GDebugLogPath := GPluginDir + 'glimpse_debug.log';
  { Start fresh log each session }
  if FileExists(uDebugLog.GDebugLogPath) then
    DeleteFile(uDebugLog.GDebugLogPath);
  {$ENDIF}

  Log('ListSetDefaultParams');
  Log(Format('  PluginDir=%s', [GPluginDir]));
  Log(Format('  DLL HInstance=$%s', [IntToHex(HInstance)]));

  { Swap: GSettings is never nil (created at initialization with defaults) }
  NewSettings := TPluginSettings.Create(GPluginDir + 'Glimpse.ini');
  NewSettings.Load;
  GSettings.Free;
  GSettings := NewSettings;

  GFFmpegPath := FindFFmpegExe(GPluginDir, GSettings.FFmpegExePath);
  Log(Format('  FFmpegPath=%s', [GFFmpegPath]));

  { Run cache eviction once per session.
    Evict enumerates files and exits early if within budget, so no pre-check needed.
    Wrapped in try/except: invalid or inaccessible cache folder must not crash TC. }
  if GSettings.CacheEnabled then
  begin
    var CacheDir := EffectiveCacheFolder(GSettings.CacheFolder);
    try
      with TFrameCache.Create(CacheDir, GSettings.CacheMaxSizeMB) do
      try
        Evict;
      finally
        Free;
      end;
      Log(Format('  CacheDir=%s', [CacheDir]));
    except
      on E: Exception do
        Log(Format('  Cache init failed: %s', [E.Message]));
    end;
  end;
end;

{ Returns a preview bitmap for TC thumbnail view.
  Not implemented: TC calls this for thumbnails panel, which requires
  synchronous single-frame extraction; the current architecture is
  async-only. Returns 0 so TC falls back to its default thumbnail. }
function DoGetPreviewBitmap(const AFileName: string; Width, Height: Integer): HBITMAP;
begin
  Result := 0;
end;

function ListGetPreviewBitmap(FileToLoad: PAnsiChar; Width, Height: Integer; ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;
begin
  Result := DoGetPreviewBitmap(string(AnsiString(FileToLoad)), Width, Height);
end;

function ListGetPreviewBitmapW(FileToLoad: PWideChar; Width, Height: Integer; ContentBuf: PAnsiChar; ContentBufLen: Integer): HBITMAP; stdcall;
begin
  Result := DoGetPreviewBitmap(string(FileToLoad), Width, Height);
end;

initialization
  GSettings := TPluginSettings.Create('');

finalization
  Log('finalization');
  FreeAndNil(GSettings);

end.
