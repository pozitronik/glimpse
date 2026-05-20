{VCL-dependent helpers shared by the WLX and WCX settings dialogs.

 Each dialog historically carried byte-identical copies of these
 procedures: a colour-picker bound to a TPanel.Color, two font-edit
 readout formatters, and two TFontDialog drivers. Hoisting them here
 removes ~50 lines of duplication per dialog and gives both plugins
 one place to tweak the look-and-feel.

 Sibling unit SettingsDlgLogic stays VCL-free and houses the pure
 formatting / encode-decode helpers; this unit gathers the necessarily
 VCL-touching pieces. The split keeps the pure-logic side unit-testable
 without a UI runtime.}
unit SettingsDlgUI;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Dialogs;

{Opens AColorDialog seeded with the panel's current colour; commits the
 chosen colour back to the panel if the user accepts.}
procedure PickColorForPanel(APanel: TPanel; AColorDialog: TColorDialog);

{Formats AEdit's text as "Name, N pt" — the simple-font readout the
 dialogs use to surface the picked font without putting a real font
 control on the form. Used for timestamp, status-bar, and any other
 font field that does not need the banner's auto-size branch.}
procedure RefreshFontEdit(AEdit: TEdit; const AFontName: string; AFontSize: Integer);

{Formats AEdit's text as "Name, auto" when the auto-size checkbox is
 checked, otherwise "Name, N pt". Mirrors RefreshFontEdit but
 honours the auto-size special case the banner uses.}
procedure RefreshBannerFontEdit(AEdit: TEdit; AAutoSize: Boolean; const AFontName: string; AFontSize: Integer);

{Drives AFontDialog seeded with the current font name and size; writes
 the picked values back through the var parameters and refreshes AEdit.
 Picked size is clamped to [AMinSize, AMaxSize] before storage.}
procedure PickFontInto(AFontDialog: TFontDialog; AEdit: TEdit; var AFontName: string; var AFontSize: Integer; AMinSize, AMaxSize: Integer);

{Wires the two-control "info" pattern: a fixed-status TLabel (e.g.
 "Detected:") next to a borderless read-only TEdit that holds the
 copy-friendly value. Layout (Left/Top/Width) is owned by the DFM;
 this helper only updates Caption / Text / Visible. Pass empty AValue
 to hide the edit; the prefix still renders (or also clears if APrefix
 is '').}
procedure ApplyInfoParts(APrefixLabel: TLabel; AValueEdit: TEdit; const APrefix, AValue: string);

{Same as PickFontInto but for the banner font, with two extra
 wrinkles:
 - When AAutoSize is True at entry, the dialog seeds the size field
 with ADefaultSize so the user sees a sensible starting value instead
 of whatever stale FBannerFontSize happens to hold.
 - Picking any size signals intent to drop auto-sizing: on accept the
 helper writes AAutoSize := False through the var-param; the caller
 reflects this onto whichever UI control owns the toggle. On cancel
 AAutoSize is left unchanged.}
procedure PickBannerFontInto(AFontDialog: TFontDialog; AEdit: TEdit; var AAutoSize: Boolean; var AFontName: string; var AFontSize: Integer; AMinSize, AMaxSize, ADefaultSize: Integer);

{Opens a folder-picker dialog seeded with AEdit's current text (env-var
 expanded) and writes the chosen folder back to AEdit on accept. AOwner
 is the VCL owner for the transient TFileOpenDialog instance — typically
 the hosting form. Both WLX and WCX settings dialogs use this for their
 Save folder / Cache folder picker buttons.}
procedure BrowseFolderInto(AEdit: TEdit; AOwner: TComponent);

implementation

uses
  PathExpand;

procedure PickColorForPanel(APanel: TPanel; AColorDialog: TColorDialog);
begin
  AColorDialog.Color := APanel.Color;
  if AColorDialog.Execute then
    APanel.Color := AColorDialog.Color;
end;

procedure RefreshFontEdit(AEdit: TEdit; const AFontName: string; AFontSize: Integer);
begin
  AEdit.Text := Format('%s, %d pt', [AFontName, AFontSize]);
end;

procedure RefreshBannerFontEdit(AEdit: TEdit; AAutoSize: Boolean; const AFontName: string; AFontSize: Integer);
begin
  if AAutoSize then
    AEdit.Text := Format('%s, auto', [AFontName])
  else
    AEdit.Text := Format('%s, %d pt', [AFontName, AFontSize]);
end;

procedure ApplyInfoParts(APrefixLabel: TLabel; AValueEdit: TEdit; const APrefix, AValue: string);
begin
  APrefixLabel.Caption := APrefix;
  AValueEdit.Text := AValue;
  AValueEdit.Visible := AValue <> '';
end;

{Local helper: clamps an integer into [AMin, AMax] without pulling in
 System.Math just for one EnsureRange call.}
function ClampInt(AValue, AMin, AMax: Integer): Integer;
begin
  if AValue < AMin then
    Exit(AMin);
  if AValue > AMax then
    Exit(AMax);
  Result := AValue;
end;

procedure PickFontInto(AFontDialog: TFontDialog; AEdit: TEdit; var AFontName: string; var AFontSize: Integer; AMinSize, AMaxSize: Integer);
begin
  AFontDialog.Font.Name := AFontName;
  AFontDialog.Font.Size := AFontSize;
  if AFontDialog.Execute then
  begin
    AFontName := AFontDialog.Font.Name;
    AFontSize := ClampInt(AFontDialog.Font.Size, AMinSize, AMaxSize);
    RefreshFontEdit(AEdit, AFontName, AFontSize);
  end;
end;

procedure PickBannerFontInto(AFontDialog: TFontDialog; AEdit: TEdit; var AAutoSize: Boolean; var AFontName: string; var AFontSize: Integer; AMinSize, AMaxSize, ADefaultSize: Integer);
begin
  AFontDialog.Font.Name := AFontName;
  if AAutoSize then
    AFontDialog.Font.Size := ADefaultSize
  else
    AFontDialog.Font.Size := AFontSize;
  if AFontDialog.Execute then
  begin
    AFontName := AFontDialog.Font.Name;
    AFontSize := ClampInt(AFontDialog.Font.Size, AMinSize, AMaxSize);
    AAutoSize := False;
    RefreshBannerFontEdit(AEdit, AAutoSize, AFontName, AFontSize);
  end;
end;

procedure BrowseFolderInto(AEdit: TEdit; AOwner: TComponent);
var
  Dlg: TFileOpenDialog;
begin
  Dlg := TFileOpenDialog.Create(AOwner);
  try
    Dlg.Options := [fdoPickFolders, fdoPathMustExist];
    if AEdit.Text <> '' then
      Dlg.DefaultFolder := ExpandEnvVars(AEdit.Text);
    if Dlg.Execute then
      AEdit.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

end.
