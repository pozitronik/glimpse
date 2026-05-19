{Shared helpers for the WLX + WCX settings dialogs.

 Step 104 (M25): after Phases 5/6, most of the original duplication
 between WLX TSettingsForm and WCX TWcxSettingsForm has been removed
 via earlier steps (PickColorForPanel and the font-display helpers in
 uSettingsDlgUI, FFmpegInfoLabelParts in uSettingsDlgLogic, per-plugin
 bundle + presenter units). Two genuine duplications remain after the
 dust settled:

   1. The ffmpeg-info probe-and-display flow (Input -> resolved Path
      -> probe state -> FFmpegInfoLabelParts -> ApplyInfoParts) lived
      identically inside TExtractionPresenter.UpdateFFmpegInfo and
      TWcxExtractionPresenter.UpdateFFmpegInfo. Only the fallback path
      computation differed: WLX uses a pre-resolved FResolvedFFmpegPath
      threaded in at dialog open; WCX re-probes via FindFFmpegExe on
      every call. Lifted here as DisplayFFmpegInfo with the fallback
      as an in-parameter — each presenter computes its own fallback
      before calling.

   2. The BtnFFmpegPathClick browse dialog (TOpenDialog setup +
      ValidateFFmpeg check + ShowPluginMessage on bad pick + write to
      EdtFFmpegPath) lived identically in both presenters. Lifted here
      as BrowseForFFmpegExe.

 Both helpers are free procedures (no class). The presenters keep their
 own UpdateFFmpegInfo / OnFFmpegPathClick methods as one-line
 delegations so DFM-wired event signatures and the presenter contract
 stay unchanged.}
unit uSettingsDialogHelpers;

interface

uses
  Winapi.Windows,
  Vcl.StdCtrls, Vcl.ExtCtrls;

{Resolves AInputPath via ExpandEnvVars (or falls back to AFallbackPath
 if AInputPath is empty), classifies the resulting Path into a
 TFFmpegProbeState (no-path / file-missing / invalid / valid), and
 writes the result into ALblInfo + AEdtInfo via FFmpegInfoLabelParts +
 ApplyInfoParts. The "input was empty" branch of FFmpegInfoLabelParts
 controls whether the label says "Resolved:" vs "Configured:" so
 passing the right value matters.}
procedure DisplayFFmpegInfo(const AInputPath, AFallbackPath: string;
  ALblInfo: TLabel; AEdtInfo: TEdit);

{Shows a TOpenDialog (filtered to ffmpeg.exe) starting from the
 directory of AEdt.Text if non-empty. On a successful pick: validates
 the file via ValidateFFmpeg; on validation failure surfaces a
 ShowPluginMessage warning under AParentWnd and leaves AEdt untouched;
 on validation success writes the picked path into AEdt.Text (the
 OnChange handler then re-runs DisplayFFmpegInfo via the form's
 forwarder).}
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
