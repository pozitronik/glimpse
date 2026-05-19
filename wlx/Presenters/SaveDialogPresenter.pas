{File "Save as" dialog with an inline "Save at view resolution" check
 button on Vista+ (bridged via IFileDialogCustomize because the VCL
 wrapper does not expose it). Falls back to TSaveDialog on pre-Vista
 or when the modern dialog refuses to instantiate.}
unit SaveDialogPresenter;

interface

uses
  SettingsInterfaces, BitmapSaver;

type
  {On accept the presenter mutates the policy (SaveFolder + SaveAtLiveResolution)
   and calls Save, so caller need not redo the save.}
  TSaveDialogPresenter = class
  strict private
    FSavePolicy: ISaveFormatPolicy;
  public
    constructor Create(const ASavePolicy: ISaveFormatPolicy);
    {AInitialLiveRes seeds the inline check button on modern Windows
     (final state wins); on legacy Windows the seed is authoritative.}
    function Show(const ATitle, ADefaultName: string;
      AOverwritePrompt: Boolean; AInitialLiveRes: Boolean;
      out APath: string; out AFormat: TSaveFormat): Boolean;
  end;

implementation

uses
  Winapi.Windows, Winapi.ShlObj,
  System.SysUtils,
  Vcl.Dialogs,
  PathExpand;

const
  {Unique within the dialog; clear of any system-used ids.}
  ID_CHK_LIVE_RES = 1001;
  LIVE_RES_LABEL = 'Save at view resolution';

type
  {Bridges TFileSaveDialog with IFileDialogCustomize. The check button MUST
   be added in DoOnExecute (before Show) and its state read in OnFileOkClick
   (still inside the modal loop) — TCustomFileDialog clears its internal
   IFileDialog after Execute, so a later query is too late.}
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
  FFinalState := AInitialState; {Preserve current value on cancel.}
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

  {Falls through to legacy TSaveDialog when the modern one refuses (pre-Vista
   or unusual COM environments). Legacy path has no inline checkbox.}
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
      {Legacy dialog has no inline override; caller's seed becomes persisted choice.}
      FSavePolicy.SetSaveAtLiveResolution(AInitialLiveRes);
      FSavePolicy.Save;
      Result := True;
    end;
  finally
    LegacyDlg.Free;
  end;
end;

end.
