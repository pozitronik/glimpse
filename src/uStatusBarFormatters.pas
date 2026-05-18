{Maps a parsed status-bar token plus a snapshot of plugin state to the
 string that should appear in the panel. The unit is the source of
 truth for "what does %name% look like" — every visible difference
 between the old hand-rolled UpdateStatusBar and the new template-driven
 bar lives here.

 Pure: no VCL, no plugin classes, no global state. Caller (the renderer
 in wlx/) populates a TStatusBarValues record from its collaborators
 and passes it in. This makes the per-kind formatting exhaustively
 testable without spinning up a TStatusBar.

 Missing-data contract: when a token's source datum is unavailable, the
 formatter returns ''. The renderer decides what to do with the empty
 string (skip the panel for width=auto, show '?' for fixed width). The
 audio token is special-cased: when video info is valid but no audio
 stream exists, it returns 'No audio' rather than '' (matches the
 pre-template behaviour).

 Casing: when AToken.Casing = tcUpper the final result is uppercased.
 Applied after formatting so numeric formats and the transform glyph
 are unaffected.}
unit uStatusBarFormatters;

interface

uses
  uStatusBarTokens, uStatusBarTemplate;

type
  {Snapshot of every datum the token catalogue can render. Boolean *Available
   flags exist where a zero / empty value is itself a valid state and the
   formatter would otherwise have no way to distinguish "not yet known"
   from "known to be zero" (e.g. file position, frames, predicted dims).
   Numeric fields whose 0 already means "unavailable" (resolution, fps,
   duration, bitrate) skip the flag.}
  TStatusBarValues = record
    {True iff the source video has been probed successfully. Tokens that
     read source-info fields short-circuit on this — including %audio%,
     which only emits 'No audio' when video info is known to be valid.}
    VideoInfoValid: Boolean;

    FilePositionAvailable: Boolean;
    FilePositionIndex: Integer;     {1-based, as displayed}
    FilePositionTotal: Integer;

    Filename: string;

    FramesAvailable: Boolean;
    FramesTotal: Integer;
    CurrentFrameIndex: Integer;     {0-based}
    IsSingleViewMode: Boolean;

    SourceWidth, SourceHeight: Integer;
    SourceFps: Double;
    SourceDurationSec: Double;
    SourceBitrateKbps: Integer;
    SourceVideoCodec: string;

    SourceAudioCodec: string;       {empty + VideoInfoValid -> 'No audio'}
    SourceAudioSampleRate: Integer;
    SourceAudioChannels: string;
    SourceAudioBitrateKbps: Integer;

    SaveDimAvailable: Boolean;
    SaveDimW, SaveDimH: Integer;
    SaveDimCappedW, SaveDimCappedH: Integer;

    CopyDimAvailable: Boolean;
    CopyDimW, CopyDimH: Integer;
    CopyDimCappedW, CopyDimCappedH: Integer;

    LoadTimeText: string;

    ViewModeName: string;
    ZoomModeName: string;
  end;

{Returns the panel text for AToken given AValues. Empty string means
 "data unavailable" and the renderer is expected to either skip the
 panel (width=auto) or paint a placeholder (fixed width). tkUnknown
 always returns AToken.RawText so the user sees their typo back.

 AResolutionTransformGlyph is the arrow/separator shown between the
 native and capped dimensions in %save_dimension% / %copy_dimension%
 when capping fires. The caller (typically the WLX form) resolves it
 via uPlatformDetect.ResolutionTransformGlyph once and passes it here,
 keeping this unit free of the OS-detect dependency. Empty string is a
 valid default for tests that do not exercise the dim-with-cap path.}
function FormatStatusBarToken(const AToken: TStatusBarToken;
  const AValues: TStatusBarValues;
  const AResolutionTransformGlyph: string = ''): string;

implementation

uses
  System.SysUtils,
  uFrameOffsets;

function FormatBitrateKbps(AKbps: Integer): string;
begin
  if AKbps >= 1000 then
    Result := Format('%.1f Mbps', [AKbps / 1000])
  else
    Result := Format('%d kbps', [AKbps]);
end;

function FormatAudio(const AValues: TStatusBarValues): string;
begin
  if not AValues.VideoInfoValid then
    Exit('');
  if AValues.SourceAudioCodec = '' then
    Exit('No audio');
  Result := AValues.SourceAudioCodec;
  if AValues.SourceAudioSampleRate > 0 then
    Result := Result + Format(' %d Hz', [AValues.SourceAudioSampleRate]);
  if AValues.SourceAudioChannels <> '' then
    Result := Result + ' ' + AValues.SourceAudioChannels;
  if AValues.SourceAudioBitrateKbps > 0 then
    Result := Result + Format(' %d kbps', [AValues.SourceAudioBitrateKbps]);
end;

{Common renderer for %save_dimension% / %copy_dimension%. ALabel is the
 'Save' or 'Copy' prefix that mirrors today's text. AShowCap is the
 already-resolved attribute value: when False, the post-cap segment is
 suppressed regardless of whether capping would actually change the
 dimensions. When True (the default), the post-cap segment appears only
 when CombinedMaxSide actually shrinks the image.}
function FormatPredictedDim(const ALabel: string;
  AAvailable: Boolean; AW, AH, ACappedW, ACappedH: Integer;
  AShowCap: Boolean; const AGlyph: string): string;
begin
  if not AAvailable then
    Exit('');
  if AShowCap and ((ACappedW <> AW) or (ACappedH <> AH)) then
    Result := Format('%s: %dx%d%s%dx%d',
      [ALabel, AW, AH, AGlyph, ACappedW, ACappedH])
  else
    Result := Format('%s: %dx%d', [ALabel, AW, AH]);
end;

function ResolveCapAttr(const AToken: TStatusBarToken): Boolean;
begin
  {Default is True — the pre-template UpdateStatusBar always showed the
   transform when capping fired. cap=false is the user's opt-out.}
  Result := not SameText(AToken.AttrValue(ATTR_CAP, 'true'), 'false');
end;

function FormatStatusBarToken(const AToken: TStatusBarToken;
  const AValues: TStatusBarValues;
  const AResolutionTransformGlyph: string): string;
begin
  case AToken.Kind of
    tkUnknown:
      Exit(AToken.RawText);

    tkFilePosition:
      if AValues.FilePositionAvailable then
        Result := Format('%d / %d',
          [AValues.FilePositionIndex, AValues.FilePositionTotal])
      else
        Result := '';

    tkFilename:
      Result := AValues.Filename;

    tkFrames:
      if AValues.FramesAvailable then
        Result := IntToStr(AValues.FramesTotal)
      else
        Result := '';

    tkFramePosition:
      if not AValues.FramesAvailable then
        Result := ''
      else if AValues.IsSingleViewMode then
        Result := Format('%d / %d',
          [AValues.CurrentFrameIndex + 1, AValues.FramesTotal])
      else
        Result := IntToStr(AValues.FramesTotal);

    tkResolution:
      if (AValues.SourceWidth > 0) and (AValues.SourceHeight > 0) then
        Result := Format('%dx%d', [AValues.SourceWidth, AValues.SourceHeight])
      else
        Result := '';

    tkFps:
      if AValues.SourceFps > 0 then
        Result := Format('%.4g fps', [AValues.SourceFps])
      else
        Result := '';

    tkDuration:
      if AValues.SourceDurationSec > 0 then
        Result := FormatDurationHMS(AValues.SourceDurationSec)
      else
        Result := '';

    tkBitrate:
      if AValues.SourceBitrateKbps > 0 then
        Result := FormatBitrateKbps(AValues.SourceBitrateKbps)
      else
        Result := '';

    tkVideoCodec:
      Result := AValues.SourceVideoCodec;

    tkAudio:
      Result := FormatAudio(AValues);

    tkLoadTime:
      Result := AValues.LoadTimeText;

    tkSaveDimension:
      Result := FormatPredictedDim('Save',
        AValues.SaveDimAvailable,
        AValues.SaveDimW, AValues.SaveDimH,
        AValues.SaveDimCappedW, AValues.SaveDimCappedH,
        ResolveCapAttr(AToken), AResolutionTransformGlyph);

    tkCopyDimension:
      Result := FormatPredictedDim('Copy',
        AValues.CopyDimAvailable,
        AValues.CopyDimW, AValues.CopyDimH,
        AValues.CopyDimCappedW, AValues.CopyDimCappedH,
        ResolveCapAttr(AToken), AResolutionTransformGlyph);

    tkViewMode:
      Result := AValues.ViewModeName;

    tkZoom:
      Result := AValues.ZoomModeName;

  else
    Result := '';
  end;

  if (AToken.Casing = tcUpper) and (Result <> '') then
    Result := UpperCase(Result);
end;

end.
