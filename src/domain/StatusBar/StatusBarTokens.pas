{Status-bar token catalogue: every token kind the user can reference
 from the configurable template, plus per-kind name / tooltip / sample
 text. Value-free and VCL-free so tests can run without Forms / Graphics.}
unit StatusBarTokens;

interface

type
  {tkUnknown is reserved for tokens the user typed but the parser did
   not recognise. The renderer paints them literally so typos surface
   instead of vanishing.}
  TStatusBarTokenKind = (
    tkUnknown,
    tkFilePosition,
    tkFilename,
    tkFrames,
    tkFramePosition,
    tkResolution,
    tkFps,
    tkDuration,
    tkBitrate,
    tkVideoCodec,
    tkAudio,
    tkLoadTime,
    tkSaveDimension,
    tkCopyDimension,
    tkViewMode,
    tkZoom);

const
  {Panel width: integer pixels or 'auto'.}
  ATTR_WIDTH = 'width';
  ATTR_WIDTH_AUTO = 'auto';

  {tkSaveDimension / tkCopyDimension: 'true' shows post-cap dimensions
   after the transform glyph; 'false' shows just the predicted pre-cap.}
  ATTR_CAP = 'cap';

  {Panel text alignment: 'left' (default), 'right', 'center'.}
  ATTR_ALIGN = 'align';
  ATTR_ALIGN_LEFT = 'left';
  ATTR_ALIGN_RIGHT = 'right';
  ATTR_ALIGN_CENTER = 'center';

function StatusBarTokenName(AKind: TStatusBarTokenKind): string;

function StatusBarTokenHint(AKind: TStatusBarTokenKind): string;

{Used to size the panel when width=auto and the recalculate-on-every-update
 toggle is OFF. The width is measured once at template / font apply time;
 a real value never exceeds this for typical inputs.}
function StatusBarTokenSampleText(AKind: TStatusBarTokenKind): string;

{Returns False on no match; AKind is set to tkUnknown in that case.}
function StatusBarTokenKindByName(const AName: string;
  out AKind: TStatusBarTokenKind): Boolean;

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
    tkFramePosition: Result := 'frame_position';
    tkResolution:    Result := 'resolution';
    tkFps:           Result := 'fps';
    tkDuration:      Result := 'duration';
    tkBitrate:       Result := 'bitrate';
    tkVideoCodec:    Result := 'video_codec';
    tkAudio:         Result := 'audio';
    tkLoadTime:      Result := 'load_time';
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
    tkFrames:        Result := 'Total number of extracted frames';
    tkFramePosition: Result := 'Current frame in single-view, total otherwise';
    tkResolution:    Result := 'Source video resolution';
    tkFps:           Result := 'Source frame rate';
    tkDuration:      Result := 'Source duration';
    tkBitrate:       Result := 'Source container bitrate';
    tkVideoCodec:    Result := 'Source video codec';
    tkAudio:         Result := 'First audio stream summary';
    tkLoadTime:      Result := 'Time spent extracting the displayed frames';
    tkSaveDimension: Result := 'Predicted Save view output dimensions. ' +
      'Click to toggle Save at view resolution (single or double click per ' +
      'settings); Ctrl+click copies.';
    tkCopyDimension: Result := 'Predicted Copy view output dimensions. ' +
      'Click to toggle Copy at view resolution (single or double click per ' +
      'settings); Ctrl+click copies.';
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
    tkFrames:        Result := '9999';
    tkFramePosition: Result := '999 / 999';
    tkResolution:    Result := '9999x9999';
    tkFps:           Result := '999.99 fps';
    tkDuration:      Result := '99:99:99';
    tkBitrate:       Result := '9999.9 Mbps';
    tkVideoCodec:    Result := 'h265_hevc';
    tkAudio:         Result := 'aac 48000 Hz stereo 320 kbps';
    tkLoadTime:      Result := 'cache 99/99 99.99s';
    tkSaveDimension: Result := 'Save: 9999x9999 -> 9999x9999';
    tkCopyDimension: Result := 'Copy: 9999x9999 -> 9999x9999';
    tkViewMode:      Result := 'Smart Grid';
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
