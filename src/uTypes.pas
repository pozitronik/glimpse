{Shared type declarations used across multiple units.
 Extracted from uSettings to break unnecessary coupling.}
unit uTypes;

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
  end;

{Enum <-> INI-string conversions for TTimestampCorner and TBannerPosition.
 StrToX returns ADefault when the string does not match any known literal,
 matching the StrToIntDef convention. XToStr always returns a recognised
 literal so its output round-trips through StrToX.}
function StrToTimestampCorner(const AValue: string; ADefault: TTimestampCorner): TTimestampCorner;
function TimestampCornerToStr(ACorner: TTimestampCorner): string;
function StrToBannerPosition(const AValue: string; ADefault: TBannerPosition): TBannerPosition;
function BannerPositionToStr(APosition: TBannerPosition): string;

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
  case ACorner of
    tcNone:
      Result := 'none';
    tcTopLeft:
      Result := 'topleft';
    tcTopRight:
      Result := 'topright';
    tcBottomRight:
      Result := 'bottomright';
    else
      Result := 'bottomleft';
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
    bpBottom:
      Result := 'bottom';
    else
      Result := 'top';
  end;
end;

end.
