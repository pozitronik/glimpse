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
  uSettings, uFFmpegLocator, uPluginForm, uCache;

var
  GSettings: TPluginSettings;
  GPluginDir: string;
  GFFmpegPath: string;
procedure Log(const AMsg: string);
begin
  {$IFDEF DEBUG}
  DebugLog('Plugin', AMsg);
  {$ENDIF}
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
      MessageBox(ParentWin, PChar(Format('VideoThumb: %s', [E.Message])),
        'VideoThumb', MB_OK or MB_ICONERROR);
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
  Ctrl: TWinControl;
begin
  Log(Format('DoListLoadNext: ListWin=$%s File=%s', [IntToHex(ListWin), AFileName]));
  Ctrl := FindControl(ListWin);
  if Ctrl is TPluginForm then
  begin
    TPluginForm(Ctrl).LoadFile(AFileName);
    TPluginForm(Ctrl).ApplyListerParams(ShowFlags);
    Result := LISTPLUGIN_OK;
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
  Ctrl: TWinControl;
begin
  Log(Format('ListCloseWindow: $%s', [IntToHex(ListWin)]));
  Ctrl := FindControl(ListWin);
  if Ctrl is TPluginForm then
    Ctrl.Free;
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
  Ctrl: TWinControl;
begin
  case Command of
    lc_Copy:
      begin
        Ctrl := FindControl(ListWin);
        if Ctrl is TPluginForm then
          TPluginForm(Ctrl).CopyFrameToClipboard;
        Result := LISTPLUGIN_OK;
      end;
    lc_NewParams:
      begin
        Ctrl := FindControl(ListWin);
        if Ctrl is TPluginForm then
          TPluginForm(Ctrl).ApplyListerParams(Parameter);
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
  uCache.GDebugLogPath := GPluginDir + 'videothumb_debug.log';
  { Start fresh log each session }
  if FileExists(uCache.GDebugLogPath) then
    DeleteFile(uCache.GDebugLogPath);
  {$ENDIF}

  Log('ListSetDefaultParams');
  Log(Format('  PluginDir=%s', [GPluginDir]));
  Log(Format('  DLL HInstance=$%s', [IntToHex(HInstance)]));

  { Swap: GSettings is never nil (created at initialization with defaults) }
  NewSettings := TPluginSettings.Create(GPluginDir + 'VideoThumb.ini');
  NewSettings.Load;
  GSettings.Free;
  GSettings := NewSettings;

  GFFmpegPath := FindFFmpegExe(GPluginDir, GSettings.FFmpegExePath);
  Log(Format('  FFmpegPath=%s', [GFFmpegPath]));

  { Run cache eviction once per session, only when over budget }
  if GSettings.CacheEnabled then
  begin
    var CacheDir := EffectiveCacheFolder(GSettings.CacheFolder);
    with TFrameCache.Create(CacheDir, GSettings.CacheMaxSizeMB) do
    try
      if GetTotalSize > Int64(GSettings.CacheMaxSizeMB) * 1024 * 1024 then
        Evict;
    finally
      Free;
    end;
    Log(Format('  CacheDir=%s', [CacheDir]));
  end;
end;

{ Returns a preview bitmap for TC thumbnail view. }
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
