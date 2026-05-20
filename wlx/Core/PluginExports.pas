{WLX plugin API exported functions.
 These are called by Total Commander to interact with the plugin.}
unit PluginExports;

interface

uses
  Winapi.Windows, WlxAPI;

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
  Vcl.Graphics,
  Settings, FFmpegLocator, FFmpegExe, PluginForm, PluginServices, Cache, ProbeCache,
  Logging, ThumbnailRender, ToolbarLayout, PluginContext, Defaults,
  VideoProbing, FrameExtractor, FrameCacheFactory;

var
  Log: TProc<string>;

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

function DoListLoad(ParentWin: HWND; const AFileName: string; ShowFlags: Integer): HWND;
var
  Form: TPluginForm;
  Services: TPluginServices;
begin
  Result := 0;
  Log(Format('DoListLoad: ParentWin=$%s File=%s Flags=%d', [IntToHex(ParentWin), AFileName, ShowFlags]));
  try
    Log(Format('DoListLoad: ffmpegPath=%s', [TPluginContext.Instance.FFmpegPath]));
    {Services is a managed local: its ProbeCache and factory interfaces
     are refcount-released on every exit path, including exceptions.}
    Services := CreateProductionServices;
    Form := TPluginForm.CreateForPlugin(ParentWin, AFileName,
      TPluginContext.Instance.Settings, TPluginContext.Instance.FFmpegPath, Services);
    Form.ApplyListerParams(ShowFlags);
    Result := Form.Handle;
    Log(Format('DoListLoad: Form created, Handle=$%s IsWindow=%s Visible=%s Parent=$%s', [IntToHex(Result), BoolToStr(IsWindow(Result), True), BoolToStr(IsWindowVisible(Result), True), IntToHex(GetParent(Result))]));
  except
    on E: Exception do
    begin
      Log(Format('DoListLoad: EXCEPTION %s: %s', [E.ClassName, E.Message]));
      MessageBox(ParentWin, PChar(Format('Glimpse: %s', [E.Message])), 'Glimpse', MB_OK or MB_ICONERROR);
    end;
  end;
end;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
begin
  {ANSI shim for ABI completeness only — path chars outside CP_ACP are
   corrupted at the AnsiString conversion. Modern TC always calls W variants.}
  Log('ListLoad (ANSI)');
  Result := DoListLoad(ParentWin, string(AnsiString(FileToLoad)), ShowFlags);
end;

function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
begin
  Log('ListLoadW (Unicode)');
  Result := DoListLoad(ParentWin, string(FileToLoad), ShowFlags);
end;

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
  Extensions := TPluginContext.Instance.Settings.ExtensionList.Split([',', ' ']);

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

  {MULTIMEDIA keyword tells TC to override its built-in media viewer}
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
        {Forward to the shared command dispatcher so all Copy-frame entry points share one path.}
        if Form <> nil then
          Form.DispatchCommand(CM_COPY_FRAME);
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
  ModulePath: array [0 .. MAX_PATH] of Char;
  NewSettings: TPluginSettings;
  Ctx: TPluginContext;
begin
  Ctx := TPluginContext.Instance;
  GetModuleFileName(HInstance, ModulePath, MAX_PATH);
  Ctx.PluginDir := ExtractFilePath(string(ModulePath));

  {Load settings BEFORE the first Log call so [debug] LogEnabled controls
   whether the log file is created at all.}
  NewSettings := TPluginSettings.Create(Ctx.PluginDir + 'Glimpse.ini');
  NewSettings.Load;
  Ctx.Settings := NewSettings;

  if Ctx.Settings.DebugLogEnabled then
  begin
    {Fresh log each TC session — delete BEFORE Configure or the singleton
     would seek to the end of the stale file.}
    if FileExists(Ctx.PluginDir + 'glimpse_debug.log') then
      DeleteFile(Ctx.PluginDir + 'glimpse_debug.log');
    TDebugLog.Instance.Configure(Ctx.PluginDir + 'glimpse_debug.log');
  end
  else
    TDebugLog.Instance.Configure('');

  Log('ListSetDefaultParams');
  Log(Format('  PluginDir=%s', [Ctx.PluginDir]));
  Log(Format('  DLL HInstance=$%s', [IntToHex(HInstance)]));

  Ctx.FFmpegPath := FindFFmpegExe(Ctx.PluginDir, Ctx.Settings.FFmpegExePath);
  Log(Format('  FFmpegPath=%s', [Ctx.FFmpegPath]));

  if Ctx.ProbeCache = nil then
    Ctx.ProbeCache := CreateProbeCache;

  {Run cache eviction once per session. Wrapped in try/except: an invalid
   cache folder must not crash TC.}
  if Ctx.Settings.CacheEnabled then
  begin
    var
    CacheDir := EffectiveCacheFolder(Ctx.Settings.CacheFolder);
    try
      CreateCacheManager(CacheDir, Ctx.Settings.CacheMaxSizeMB).Evict;
      Log(Format('  CacheDir=%s', [CacheDir]));
      {Same directory + budget as the main cache so eviction is shared.}
      Ctx.ThumbnailCache := CreateFrameCache(CacheDir, Ctx.Settings.CacheMaxSizeMB);
    except
      on E: Exception do
      begin
        Log(Format('  Cache init failed: %s', [E.Message]));
        Ctx.ThumbnailCache := TNullFrameCache.Create;
      end;
    end;
  end
  else
    Ctx.ThumbnailCache := TNullFrameCache.Create;
end;

{Runs on TC's worker thread. Failures return 0 so TC falls back to its default icon.}
function DoGetPreviewBitmap(const AFileName: string; Width, Height: Integer): HBITMAP;
var
  Ctx: TPluginContext;
  FFmpeg: IVideoProber;
  Bmp: TBitmap;
begin
  Result := 0;
  Ctx := TPluginContext.Instance;
  if (Ctx.Settings = nil) or not Ctx.Settings.ThumbnailsEnabled then
    Exit;
  if (Ctx.FFmpegPath = '') or not FileExists(Ctx.FFmpegPath) then
    Exit;
  if Ctx.ThumbnailCache = nil then
    Exit;
  if Ctx.ProbeCache = nil then
    Exit;

  try
    {One TFFmpegExe instance, held via its two interfaces — refcount frees
     it on scope exit. The shorter thumbnail extract budget is baked in.}
    FFmpeg := TFFmpegExe.Create(Ctx.FFmpegPath, DEF_THUMBNAIL_TIMEOUT_MS);
    Bmp := RenderThumbnail(FFmpeg as IFrameExtractor, FFmpeg, AFileName, Width, Height,
      TThumbnailParams.FromSettings(Ctx.Settings), Ctx.ThumbnailCache, Ctx.ProbeCache);
    if Bmp <> nil then
      try
        {TC takes ownership of the returned HBITMAP — detach so Bmp.Free does not free it.}
        Result := Bmp.ReleaseHandle;
      finally
        Bmp.Free;
      end;
  except
    on E: Exception do
    begin
      Log(Format('DoGetPreviewBitmap exception: %s: %s', [E.ClassName, E.Message]));
      Result := 0;
    end;
  end;
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

Log := DebugLogger('Plugin');

finalization

Log('finalization');
TPluginContext.ReleaseInstance;

end.
