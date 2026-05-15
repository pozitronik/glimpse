{Single source of truth for the status-bar token catalogue. Lists every
 token kind the user may reference from the configurable template and
 carries the per-kind metadata the parser and renderer need:

   - canonical lowercase name (matched against template identifiers)
   - default tooltip text shown when hovering the panel
   - representative text used to size the panel when width=auto and the
     "recalculate auto-sized cells on every update" toggle is OFF

 Live values (e.g. the resolution string for the current file) are
 produced by the renderer from plugin state. This unit is value-free
 and VCL-free so it can be exercised by DUnitX in a console process
 without pulling Forms / Graphics into the test harness.}
unit uStatusBarTokens;

interface

type
  {Recognised status-bar token kinds. Order is incidental; the canonical
   name from StatusBarTokenName is what the user types and what the
   parser matches against.

   tkUnknown is reserved for tokens the user typed but the parser did
   not recognise. The renderer paints them literally so typos surface
   instead of vanishing.}
  TStatusBarTokenKind = (
    tkUnknown,
    tkFilePosition,
    tkFilename,
    tkFrames,
    tkResolution,
    tkFps,
    tkDuration,
    tkSaveDimension,
    tkCopyDimension,
    tkViewMode,
    tkZoom);

const
  {Reserved attribute name shared by every token. Value is either an
   integer (panel pixel width) or 'auto' (width derived from text).}
  ATTR_WIDTH = 'width';
  ATTR_WIDTH_AUTO = 'auto';

  {Token-specific attribute consumed by tkSaveDimension / tkCopyDimension.
   'true' shows the post-cap dimensions after the transform glyph;
   'false' shows just the predicted pre-cap dimensions.}
  ATTR_CAP = 'cap';

{Canonical lowercase name for AKind. tkUnknown returns ''.}
function StatusBarTokenName(AKind: TStatusBarTokenKind): string;

{Tooltip shown when the user hovers the panel that holds the token.
 Empty for tkUnknown — the literally-painted raw text already conveys
 the typo.}
function StatusBarTokenHint(AKind: TStatusBarTokenKind): string;

{Representative text used to size the panel when width=auto and the
 "recalculate auto-sized cells on every update" toggle is OFF. The
 width is measured once with this string at template / font apply time;
 a real value never exceeds it for typical inputs (e.g. resolutions up
 to 9999x9999).}
function StatusBarTokenSampleText(AKind: TStatusBarTokenKind): string;

{Looks up AName (case-insensitive) against the canonical name table.
 Returns False on no match; AKind is set to tkUnknown in that case.}
function StatusBarTokenKindByName(const AName: string;
  out AKind: TStatusBarTokenKind): Boolean;

{All recognised kinds in declaration order (excluding tkUnknown). Used
 by the settings dialog to render the legend list under the template
 field.}
function AllStatusBarTokenKinds: TArray<TStatusBarTokenKind>;

implementation

uses
  System.SysUtils;

function StatusBarTokenName(AKind: TStatusBarTokenKind): string;
begin
  case AKind of
    tkFilePosition:  Result := 'file_position';
    tkFilename:      Result := 'filename';
    tkFrames:        Result := 'frames';
    tkResolution:    Result := 'resolution';
    tkFps:           Result := 'fps';
    tkDuration:      Result := 'duration';
    tkSaveDimension: Result := 'save_dimension';
    tkCopyDimension: Result := 'copy_dimension';
    tkViewMode:      Result := 'view_mode';
    tkZoom:          Result := 'zoom';
  else
    Result := '';
  end;
end;

function StatusBarTokenHint(AKind: TStatusBarTokenKind): string;
begin
  case AKind of
    tkFilePosition:  Result := 'Position of the current file in the folder';
    tkFilename:      Result := 'Current file name';
    tkFrames:        Result := 'Number of extracted frames';
    tkResolution:    Result := 'Source video resolution';
    tkFps:           Result := 'Source frame rate';
    tkDuration:      Result := 'Source duration';
    tkSaveDimension: Result := 'Predicted Save view output dimensions';
    tkCopyDimension: Result := 'Predicted Copy view output dimensions';
    tkViewMode:      Result := 'Active view mode';
    tkZoom:          Result := 'Active zoom mode';
  else
    Result := '';
  end;
end;

function StatusBarTokenSampleText(AKind: TStatusBarTokenKind): string;
begin
  case AKind of
    tkFilePosition:  Result := '999 / 999';
    tkFilename:      Result := 'a-very-long-video-filename.mkv';
    tkFrames:        Result := '999 frames';
    tkResolution:    Result := '9999x9999';
    tkFps:           Result := '999.00 fps';
    tkDuration:      Result := '99:99:99';
    tkSaveDimension: Result := 'Save: 9999x9999 -> 9999x9999';
    tkCopyDimension: Result := 'Copy: 9999x9999 -> 9999x9999';
    tkViewMode:      Result := 'Filmstrip';
    tkZoom:          Result := 'Fit window';
  else
    Result := '';
  end;
end;

function StatusBarTokenKindByName(const AName: string;
  out AKind: TStatusBarTokenKind): Boolean;
var
  K: TStatusBarTokenKind;
begin
  AKind := tkUnknown;
  if AName = '' then
    Exit(False);
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
    if SameText(StatusBarTokenName(K), AName) then
    begin
      AKind := K;
      Exit(True);
    end;
  Result := False;
end;

function AllStatusBarTokenKinds: TArray<TStatusBarTokenKind>;
var
  K: TStatusBarTokenKind;
  N: Integer;
begin
  SetLength(Result, Ord(High(TStatusBarTokenKind)) - Ord(tkUnknown));
  N := 0;
  for K := Succ(tkUnknown) to High(TStatusBarTokenKind) do
  begin
    Result[N] := K;
    Inc(N);
  end;
end;

end.
