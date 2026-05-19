{Shared ffmpeg-info probe and browse helpers for the WLX/WCX settings
 dialogs. Presenters delegate one-liners so DFM event signatures and the
 presenter contract stay unchanged.}
unit uSettingsDialogHelpers;

interface

uses
  Winapi.Windows,
  Vcl.StdCtrls, Vcl.ExtCtrls;

{Empty AInputPath causes the label to read "Resolved:"; non-empty
 reads "Configured:".}
procedure DisplayFFmpegInfo(const AInputPath, AFallbackPath: string;
  ALblInfo: TLabel; AEdtInfo: TEdit);

{Validation failure surfaces a warning and leaves AEdt untouched.}
procedure BrowseForFFmpegExe(AEdt: TEdit; AParentWnd: HWND);

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  uFFmpegExe, uFFmpegCmdLine, uPathExpand, uPluginMessages,
  uSettingsDlgLogic, uSettingsDlgUI;

procedure DisplayFFmpegInfo(const AInputPath, AFallbackPath: string;
  ALblInfo: TLabel; AEdtInfo: TEdit);
var
  Path, Ver, Prefix, Value: string;
  State: TFFmpegProbeState;
begin
  if AInputPath <> '' then
    Path := ExpandEnvVars(AInputPath)
  else
    Path := AFallbackPath;

  Ver := '';
  if Path = '' then
    State := fpsNoPath
  else if not FileExists(Path) then
    State := fpsFileMissing
  else
  begin
    Ver := ValidateFFmpeg(Path);
    if Ver = '' then
      State := fpsInvalid
    else
      State := fpsValid;
  end;

  FFmpegInfoLabelParts(State, Path, Ver, AInputPath = '', Prefix, Value);
  ApplyInfoParts(ALblInfo, AEdtInfo, Prefix, Value);
end;

procedure BrowseForFFmpegExe(AEdt: TEdit; AParentWnd: HWND);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'ffmpeg.exe|ffmpeg.exe|All files (*.*)|*.*';
    Dlg.Title := 'Locate ffmpeg.exe';
    if AEdt.Text <> '' then
      Dlg.InitialDir := ExtractFilePath(ExpandEnvVars(AEdt.Text));
    if Dlg.Execute and FileExists(Dlg.FileName) then
    begin
      if ValidateFFmpeg(Dlg.FileName) = '' then
      begin
        ShowPluginMessage(AParentWnd, 'The selected file is not a valid ffmpeg executable.', MB_OK or MB_ICONWARNING);
        Exit;
      end;
      AEdt.Text := Dlg.FileName;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
