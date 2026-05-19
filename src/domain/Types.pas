{Shared type declarations used across multiple units.
 Extracted from Settings to break unnecessary coupling.}
unit Types;

interface

type
  TFFmpegMode = (fmAuto, fmExe);
  TViewMode = (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);
  TZoomMode = (zmFitWindow, zmFitIfLarger, zmActual);
  {Thumbnail rendering mode for TC panel previews. Single = one frame at
   a configurable position; Grid = mini multi-frame composite.}
  TThumbnailMode = (tnmSingle, tnmGrid);
  {Timestamp overlay corner on each frame cell (WLX live view and combined image).
   tcNone disables the overlay entirely (useful as a single-control off switch).}
  TTimestampCorner = (tcNone, tcTopLeft, tcTopRight, tcBottomLeft, tcBottomRight);
  {Info banner placement relative to the combined image.}
  TBannerPosition = (bpTop, bpBottom);

  {Bundles extraction parameters that travel together through the
   extraction pipeline (controller -> worker -> extractor).}
  TExtractionOptions = record
    UseBmpPipe: Boolean;
    MaxSide: Integer;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
    {When True, a leading scale=iw*sar:ih,setsar=1 is added to the ffmpeg
     filter chain so anamorphic sources are output at display dimensions
     instead of the raw storage pixel grid. No-op for SAR=1:1 sources.
     Default False so callers must opt in; settings layers do.}
    RespectAnamorphic: Boolean;
  end;

  {Enum <-> INI-string conversions. StrToX returns ADefault when the
   string does not match any known literal, matching the StrToIntDef
   convention. XToStr always returns a recognised literal so its output
   round-trips through StrToX.

   FFmpegMode / ViewMode / ZoomMode / ThumbnailMode use historical
   one-arg StrToX overloads that fall back to a hard-coded default
   (DEF_FFMPEG_MODE = fmAuto etc.) — preserved verbatim from the
   pre-extraction TPluginSettings class methods so the INI wire format
   stays unchanged. TimestampCorner / BannerPosition take a caller-supplied
   default because their group records use the record's current value as
   the fallback.}
function StrToTimestampCorner(const AValue: string; ADefault: TTimestampCorner): TTimestampCorner;
function TimestampCornerToStr(ACorner: TTimestampCorner): string;
function StrToBannerPosition(const AValue: string; ADefault: TBannerPosition): TBannerPosition;
function BannerPositionToStr(APosition: TBannerPosition): string;
function StrToFFmpegMode(const AValue: string): TFFmpegMode;
function FFmpegModeToStr(AMode: TFFmpegMode): string;
function StrToViewMode(const AValue: string): TViewMode;
function ViewModeToStr(AMode: TViewMode): string;
function StrToZoomMode(const AValue: string): TZoomMode;
function ZoomModeToStr(AMode: TZoomMode): string;
function StrToThumbnailMode(const AValue: string): TThumbnailMode;
function ThumbnailModeToStr(AMode: TThumbnailMode): string;

implementation

uses
  System.SysUtils;

function StrToTimestampCorner(const AValue: string; ADefault: TTimestampCorner): TTimestampCorner;
begin
  if SameText(AValue, 'none') then
    Result := tcNone
  else if SameText(AValue, 'topleft') then
    Result := tcTopLeft
  else if SameText(AValue, 'topright') then
    Result := tcTopRight
  else if SameText(AValue, 'bottomright') then
    Result := tcBottomRight
  else if SameText(AValue, 'bottomleft') then
    Result := tcBottomLeft
  else
    Result := ADefault;
end;

function TimestampCornerToStr(ACorner: TTimestampCorner): string;
begin
  {Exhaustive enumeration so a future TTimestampCorner value triggers a
   compiler hint instead of silently falling through to 'bottomleft'.}
  case ACorner of
    tcNone:
      Result := 'none';
    tcTopLeft:
      Result := 'topleft';
    tcTopRight:
      Result := 'topright';
    tcBottomLeft:
      Result := 'bottomleft';
    tcBottomRight:
      Result := 'bottomright';
  end;
end;

function StrToBannerPosition(const AValue: string; ADefault: TBannerPosition): TBannerPosition;
begin
  if SameText(AValue, 'bottom') then
    Result := bpBottom
  else if SameText(AValue, 'top') then
    Result := bpTop
  else
    Result := ADefault;
end;

function BannerPositionToStr(APosition: TBannerPosition): string;
begin
  case APosition of
    bpTop:
      Result := 'top';
    bpBottom:
      Result := 'bottom';
  end;
end;

function StrToFFmpegMode(const AValue: string): TFFmpegMode;
begin
  if SameText(AValue, 'exe') then
    Result := fmExe
  else
    Result := fmAuto;
end;

function FFmpegModeToStr(AMode: TFFmpegMode): string;
begin
  case AMode of
    fmExe:
      Result := 'exe';
    else
      Result := 'auto';
  end;
end;

function StrToViewMode(const AValue: string): TViewMode;
begin
  if SameText(AValue, 'scroll') then
    Result := vmScroll
  else if SameText(AValue, 'smartgrid') then
    Result := vmSmartGrid
  else if SameText(AValue, 'filmstrip') then
    Result := vmFilmstrip
  else if SameText(AValue, 'single') then
    Result := vmSingle
  else
    Result := vmGrid;
end;

function ViewModeToStr(AMode: TViewMode): string;
begin
  case AMode of
    vmScroll:
      Result := 'scroll';
    vmSmartGrid:
      Result := 'smartgrid';
    vmFilmstrip:
      Result := 'filmstrip';
    vmSingle:
      Result := 'single';
    else
      Result := 'grid';
  end;
end;

function StrToZoomMode(const AValue: string): TZoomMode;
begin
  if SameText(AValue, 'fitlarger') then
    Result := zmFitIfLarger
  else if SameText(AValue, 'actual') then
    Result := zmActual
  else
    Result := zmFitWindow;
end;

function ZoomModeToStr(AMode: TZoomMode): string;
begin
  case AMode of
    zmFitIfLarger:
      Result := 'fitlarger';
    zmActual:
      Result := 'actual';
    else
      Result := 'fit';
  end;
end;

function StrToThumbnailMode(const AValue: string): TThumbnailMode;
begin
  if SameText(AValue, 'grid') then
    Result := tnmGrid
  else
    Result := tnmSingle;
end;

function ThumbnailModeToStr(AMode: TThumbnailMode): string;
begin
  case AMode of
    tnmGrid:
      Result := 'grid';
    else
      Result := 'single';
  end;
end;

end.
