{File "Save as" dialog with an inline "Save at view resolution" check
 button on Vista+ (the Delphi VCL wrapper does not expose
 IFileDialogCustomize, so a hook bridges the gap), falling back to the
 plain legacy TSaveDialog on pre-Vista or when the modern dialog refuses
 to instantiate.

 Extracted from TFrameExporter so the Win32 file-dialog concerns live
 apart from the render and clipboard pipelines. The presenter owns the
 dialog lifecycle and the inline-checkbox round-trip; the caller passes
 in the persisted settings record so save-folder, save-format and
 save-at-view-resolution state can round-trip through a single object.}
unit uSaveDialogPresenter;

interface

uses
  uSettingsInterfaces, uBitmapSaver;

type
  {Presents the system "Save as" dialog and reports the user's choices
   back via out parameters. Lifetime is one-call: create on the stack,
   invoke Show, destroy. The presenter mutates the policy on accept
   (SaveFolder + SaveAtLiveResolution) and calls Save so the persisted
   state matches what the dialog returned; the caller does not need to
   redo the save.

   Step 109 (N3, ISP): depends on ISaveFormatPolicy only (read +
   write + Save). The full TPluginSettings is no longer threaded
   through.}
  TSaveDialogPresenter = class
  strict private
    FSavePolicy: ISaveFormatPolicy;
  public
    constructor Create(const ASavePolicy: ISaveFormatPolicy);
    {Opens the file dialog and returns the chosen path/format. The
     AInitialLiveRes value seeds the dialog: on modern Windows it is the
     starting state of the inline 'Save at view resolution' check button
     (the user can flip it before accept, and the final state is what
     gets persisted via FSettings.SaveAtLiveResolution); on legacy
     Windows the dialog has no checkbox, so the seed becomes the
     authoritative value and is persisted directly.}
    function Show(const ATitle, ADefaultName: string;
      AOverwritePrompt: Boolean; AInitialLiveRes: Boolean;
      out APath: string; out AFormat: TSaveFormat): Boolean;
  end;

implementation

uses
  Winapi.Windows, Winapi.ShlObj,
  System.SysUtils,
  Vcl.Dialogs,
  uPathExpand;

const
  {Arbitrary control id for the inline 'save at live resolution' check button
   on the modern (Vista+) file save dialog. Must be unique within the dialog;
   1001 is well clear of any control ids the system uses.}
  ID_CHK_LIVE_RES = 1001;
  LIVE_RES_LABEL = 'Save at view resolution';

type
  {Bridges TFileSaveDialog with the Win32 IFileDialogCustomize interface,
   which the Delphi VCL wrapper does not expose. The check button must be
   added before the dialog window is created (DoOnExecute fires just
   before Show), and its final state must be read while the dialog is
   still alive (OnFileOkClick fires inside the modal loop). After the
   dialog closes, TCustomFileDialog clears its internal IFileDialog
   reference, so a query attempt after Execute returns is too late.}
  TLiveResDialogHook = class
  strict private
    FDialog: TCustomFileDialog;
    FInitialState: Boolean;
    FFinalState: Boolean;
    procedure HandleExecute(Sender: TObject);
    procedure HandleFileOkClick(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(ADialog: TCustomFileDialog; AInitialState: Boolean);
    procedure Attach;
    property FinalState: Boolean read FFinalState;
  end;

constructor TLiveResDialogHook.Create(ADialog: TCustomFileDialog; AInitialState: Boolean);
begin
  inherited Create;
  FDialog := ADialog;
  FInitialState := AInitialState;
  FFinalState := AInitialState; {Preserve current value if the user cancels mid-flight.}
end;

procedure TLiveResDialogHook.Attach;
begin
  FDialog.OnExecute := HandleExecute;
  FDialog.OnFileOkClick := HandleFileOkClick;
end;

procedure TLiveResDialogHook.HandleExecute(Sender: TObject);
var
  Customize: IFileDialogCustomize;
begin
  if Supports(FDialog.Dialog, IFileDialogCustomize, Customize) then
    Customize.AddCheckButton(ID_CHK_LIVE_RES, LIVE_RES_LABEL, FInitialState);
end;

procedure TLiveResDialogHook.HandleFileOkClick(Sender: TObject; var CanClose: Boolean);
var
  Customize: IFileDialogCustomize;
  Checked: BOOL;
begin
  CanClose := True;
  if Supports(FDialog.Dialog, IFileDialogCustomize, Customize) then
  begin
    Checked := False;
    if Succeeded(Customize.GetCheckButtonState(ID_CHK_LIVE_RES, Checked)) then
      FFinalState := Checked;
  end;
end;

{ TSaveDialogPresenter }

constructor TSaveDialogPresenter.Create(const ASavePolicy: ISaveFormatPolicy);
begin
  inherited Create;
  FSavePolicy := ASavePolicy;
end;

function TSaveDialogPresenter.Show(const ATitle, ADefaultName: string;
  AOverwritePrompt: Boolean; AInitialLiveRes: Boolean;
  out APath: string; out AFormat: TSaveFormat): Boolean;
var
  ModernDlg: TFileSaveDialog;
  Hook: TLiveResDialogHook;
  PngType, JpegType: TFileTypeItem;
  LegacyDlg: TSaveDialog;
  ModernHandled: Boolean;
begin
  Result := False;
  ModernHandled := False;

  {Modern Vista+ dialog with an inline 'live resolution' check button.
   Falls through to the legacy TSaveDialog if the platform refuses the
   modern dialog (pre-Vista or unusual COM environments). The legacy
   path has no checkbox; the same toggle is reachable via the settings
   dialog there or via the toolbar's Save view dropdown.}
  if Win32MajorVersion >= 6 then
  begin
    try
      ModernDlg := TFileSaveDialog.Create(nil);
      try
        Hook := TLiveResDialogHook.Create(ModernDlg, AInitialLiveRes);
        try
          ModernDlg.Title := ATitle;

          PngType := ModernDlg.FileTypes.Add;
          PngType.DisplayName := 'PNG image';
          PngType.FileMask := '*.png';
          JpegType := ModernDlg.FileTypes.Add;
          JpegType.DisplayName := 'JPEG image';
          JpegType.FileMask := '*.jpg';

          case FSavePolicy.GetSaveFormat of
            sfJPEG:
              ModernDlg.FileTypeIndex := 2;
            else
              ModernDlg.FileTypeIndex := 1;
          end;
          ModernDlg.DefaultExtension := 'png';
          ModernDlg.FileName := ADefaultName;
          if FSavePolicy.GetSaveFolder <> '' then
            ModernDlg.DefaultFolder := ExpandEnvVars(FSavePolicy.GetSaveFolder);
          if AOverwritePrompt then
            ModernDlg.Options := ModernDlg.Options + [fdoOverWritePrompt]
          else
            ModernDlg.Options := ModernDlg.Options - [fdoOverWritePrompt];

          Hook.Attach;

          if ModernDlg.Execute then
          begin
            case ModernDlg.FileTypeIndex of
              2:
                AFormat := sfJPEG;
              else
                AFormat := sfPNG;
            end;
            APath := ModernDlg.FileName;
            FSavePolicy.SetSaveFolder(ExtractFilePath(ModernDlg.FileName));
            FSavePolicy.SetSaveAtLiveResolution(Hook.FinalState);
            FSavePolicy.Save;
            Result := True;
          end;
          ModernHandled := True;
        finally
          Hook.Free;
        end;
      finally
        ModernDlg.Free;
      end;
    except
      on EPlatformVersionException do
        ModernHandled := False; {Defer to legacy dialog below.}
    end;
  end;

  if ModernHandled then
    Exit;

  LegacyDlg := TSaveDialog.Create(nil);
  try
    LegacyDlg.Title := ATitle;
    LegacyDlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSavePolicy.GetSaveFormat of
      sfJPEG:
        LegacyDlg.FilterIndex := 2;
      else
        LegacyDlg.FilterIndex := 1;
    end;
    LegacyDlg.DefaultExt := 'png';
    LegacyDlg.FileName := ADefaultName;
    if FSavePolicy.GetSaveFolder <> '' then
      LegacyDlg.InitialDir := ExpandEnvVars(FSavePolicy.GetSaveFolder);
    if AOverwritePrompt then
      LegacyDlg.Options := LegacyDlg.Options + [ofOverwritePrompt];

    if LegacyDlg.Execute then
    begin
      case LegacyDlg.FilterIndex of
        2:
          AFormat := sfJPEG;
        else
          AFormat := sfPNG;
      end;
      APath := LegacyDlg.FileName;
      FSavePolicy.SetSaveFolder(ExtractFilePath(LegacyDlg.FileName));
      {No dialog override available on legacy Windows, so the caller's
       seed becomes the persisted choice.}
      FSavePolicy.SetSaveAtLiveResolution(AInitialLiveRes);
      FSavePolicy.Save;
      Result := True;
    end;
  finally
    LegacyDlg.Free;
  end;
end;

end.
