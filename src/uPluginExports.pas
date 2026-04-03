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
  System.SysUtils, System.AnsiStrings, System.IOUtils, Vcl.Controls,
  uSettings, uFFmpegLocator, uFFmpegSetupDlg, uPluginForm, uCache;

var
  GSettings: TPluginSettings;
  GPluginDir: string;
  GFFmpegPath: string;
  GLogPath: string;
  GPromptShown: Boolean;

procedure Log(const AMsg: string);
{$IFDEF DEBUG}
var
  F: TextFile;
{$ENDIF}
begin
  {$IFDEF DEBUG}
  if GLogPath = '' then Exit;
  try
    AssignFile(F, GLogPath);
    if FileExists(GLogPath) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AMsg);
    finally
      CloseFile(F);
    end;
  except
    { Logging must never crash the plugin }
  end;
  {$ENDIF}
end;

/// Ensures ffmpeg is available; shows setup dialog if needed.
procedure EnsureFFmpeg;
var
  Path: string;
begin
  if GFFmpegPath <> '' then
    Exit;
  if GPromptShown then
    Exit;

  Log('EnsureFFmpeg: showing setup dialog');
  GPromptShown := True;
  case ShowFFmpegSetupDialog(Path) of
    fsrBrowsed:
      begin
        GFFmpegPath := Path;
        Log('EnsureFFmpeg: user browsed, path=' + Path);
        GSettings.FFmpegExePath := Path;
        GSettings.Save;
      end;
    fsrCancel:
      Log('EnsureFFmpeg: user cancelled');
  end;
end;

/// Internal handler shared by ListLoad and ListLoadW.
function DoListLoad(ParentWin: HWND; const AFileName: string; ShowFlags: Integer): HWND;
var
  Form: TPluginForm;
begin
  Result := 0;
  Log('DoListLoad: ParentWin=$' + IntToHex(ParentWin) +
      ' File=' + AFileName + ' Flags=' + IntToStr(ShowFlags));
  try
    EnsureFFmpeg;
    Log('DoListLoad: ffmpegPath=' + GFFmpegPath);
    Form := TPluginForm.CreateForPlugin(ParentWin, AFileName, GSettings, GFFmpegPath);
    Result := Form.Handle;
    Log('DoListLoad: Form created, Handle=$' + IntToHex(Result) +
        ' IsWindow=' + BoolToStr(IsWindow(Result), True) +
        ' Visible=' + BoolToStr(IsWindowVisible(Result), True) +
        ' Parent=$' + IntToHex(GetParent(Result)));
  except
    on E: Exception do
    begin
      Log('DoListLoad: EXCEPTION ' + E.ClassName + ': ' + E.Message);
      MessageBox(ParentWin, PChar('VideoThumb: ' + E.Message),
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

/// Reuses an existing plugin window for a new file (smoother navigation).
function DoListLoadNext(ParentWin: HWND; ListWin: HWND; const AFileName: string; ShowFlags: Integer): Integer;
var
  Ctrl: TWinControl;
begin
  Log('DoListLoadNext: ListWin=$' + IntToHex(ListWin) + ' File=' + AFileName);
  Ctrl := FindControl(ListWin);
  if Ctrl is TPluginForm then
  begin
    TPluginForm(Ctrl).LoadFile(AFileName);
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
  Log('ListCloseWindow: $' + IntToHex(ListWin));
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

  Log('ListGetDetectString: MaxLen=' + IntToStr(MaxLen) +
      ' len=' + IntToStr(Length(DS)) +
      ' str=' + string(DS));
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
      Result := LISTPLUGIN_OK;
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
  GLogPath := GPluginDir + 'videothumb_debug.log';

  { Start fresh log each session }
  if FileExists(GLogPath) then
    DeleteFile(GLogPath);

  Log('ListSetDefaultParams');
  Log('  PluginDir=' + GPluginDir);
  Log('  DLL HInstance=$' + IntToHex(HInstance));

  { Swap: GSettings is never nil (created at initialization with defaults) }
  NewSettings := TPluginSettings.Create(GPluginDir + 'VideoThumb.ini');
  NewSettings.Load;
  GSettings.Free;
  GSettings := NewSettings;

  GFFmpegPath := FindFFmpegExe(GPluginDir, GSettings.FFmpegExePath);
  Log('  FFmpegPath=' + GFFmpegPath);

  { Run cache eviction once per session }
  if GSettings.CacheEnabled then
  begin
    var CacheDir := GSettings.CacheFolder;
    if CacheDir = '' then
      CacheDir := TPath.Combine(TPath.GetTempPath, 'VideoThumb' + PathDelim + 'cache');
    with TFrameCache.Create(CacheDir, GSettings.CacheMaxSizeMB) do
    try
      Evict;
    finally
      Free;
    end;
    Log('  CacheDir=' + CacheDir);
  end;
end;

/// Returns a preview bitmap for TC thumbnail view.
function DoGetPreviewBitmap(const AFileName: string; Width, Height: Integer): HBITMAP;
begin
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
  GSettings := TPluginSettings.Create('');

finalization
  Log('finalization');
  FreeAndNil(GSettings);

end.
