{VCL-dependent helpers shared by the WLX and WCX settings dialogs.

 Each dialog historically carried byte-identical copies of these
 procedures: a colour-picker bound to a TPanel.Color, two font-edit
 readout formatters, and two TFontDialog drivers. Hoisting them here
 removes ~50 lines of duplication per dialog and gives both plugins
 one place to tweak the look-and-feel.

 Sibling unit uSettingsDlgLogic stays VCL-free and houses the pure
 formatting / encode-decode helpers; this unit gathers the necessarily
 VCL-touching pieces. The split keeps the pure-logic side unit-testable
 without a UI runtime.}
unit uSettingsDlgUI;

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Dialogs;

{Opens AColorDialog seeded with the panel's current colour; commits the
 chosen colour back to the panel if the user accepts.}
procedure PickColorForPanel(APanel: TPanel; AColorDialog: TColorDialog);

{Formats AEdit's text as "Name, N pt" — the timestamp-font readout the
 dialogs use to surface the picked font without putting a real font
 control on the form.}
procedure RefreshTimestampFontEdit(AEdit: TEdit; const AFontName: string; AFontSize: Integer);

{Formats AEdit's text as "Name, auto" when the auto-size checkbox is
 checked, otherwise "Name, N pt". Mirrors RefreshTimestampFontEdit but
 honours the auto-size special case the banner uses.}
procedure RefreshBannerFontEdit(AEdit: TEdit; AAutoSize: Boolean; const AFontName: string; AFontSize: Integer);

{Drives AFontDialog seeded with the current font name and size; writes
 the picked values back through the var parameters and refreshes AEdit.
 Picked size is clamped to [AMinSize, AMaxSize] before storage.}
procedure PickTimestampFontInto(AFontDialog: TFontDialog; AEdit: TEdit;
  var AFontName: string; var AFontSize: Integer; AMinSize, AMaxSize: Integer);

{Same as PickTimestampFontInto but for the banner font, with two extra
 wrinkles:
  - When AChkAutoSize is checked at entry, the dialog seeds the size
    field with ADefaultSize so the user sees a sensible starting value
    instead of whatever stale FBannerFontSize happens to hold.
  - Picking any size signals intent to drop auto-sizing, so the auto
    checkbox is unchecked on accept.}
procedure PickBannerFontInto(AFontDialog: TFontDialog; AEdit: TEdit;
  AChkAutoSize: TCheckBox; var AFontName: string; var AFontSize: Integer;
  AMinSize, AMaxSize, ADefaultSize: Integer);

implementation

procedure PickColorForPanel(APanel: TPanel; AColorDialog: TColorDialog);
begin
  AColorDialog.Color := APanel.Color;
  if AColorDialog.Execute then
    APanel.Color := AColorDialog.Color;
end;

procedure RefreshTimestampFontEdit(AEdit: TEdit; const AFontName: string; AFontSize: Integer);
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

procedure PickTimestampFontInto(AFontDialog: TFontDialog; AEdit: TEdit;
  var AFontName: string; var AFontSize: Integer; AMinSize, AMaxSize: Integer);
begin
  AFontDialog.Font.Name := AFontName;
  AFontDialog.Font.Size := AFontSize;
  if AFontDialog.Execute then
  begin
    AFontName := AFontDialog.Font.Name;
    AFontSize := ClampInt(AFontDialog.Font.Size, AMinSize, AMaxSize);
    RefreshTimestampFontEdit(AEdit, AFontName, AFontSize);
  end;
end;

procedure PickBannerFontInto(AFontDialog: TFontDialog; AEdit: TEdit;
  AChkAutoSize: TCheckBox; var AFontName: string; var AFontSize: Integer;
  AMinSize, AMaxSize, ADefaultSize: Integer);
begin
  AFontDialog.Font.Name := AFontName;
  if AChkAutoSize.Checked then
    AFontDialog.Font.Size := ADefaultSize
  else
    AFontDialog.Font.Size := AFontSize;
  if AFontDialog.Execute then
  begin
    AFontName := AFontDialog.Font.Name;
    AFontSize := ClampInt(AFontDialog.Font.Size, AMinSize, AMaxSize);
    AChkAutoSize.Checked := False;
    RefreshBannerFontEdit(AEdit, AChkAutoSize.Checked, AFontName, AFontSize);
  end;
end;

end.
