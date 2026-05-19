{Maps a parsed status-bar token plus a snapshot of plugin state to the
 string that should appear in the panel. Pure: no VCL, no plugin classes,
 no global state — testable without a TStatusBar.

 Missing-data contract: empty string means data unavailable; renderer
 decides whether to skip the panel (width=auto) or paint a placeholder
 (fixed width). The audio token is special-cased: when video info is
 valid but no audio stream exists, returns 'No audio' rather than ''.

 Casing: tcUpper uppercases the final result after formatting so numeric
 formats and the transform glyph are unaffected.}
unit StatusBarFormatters;

interface

uses
  StatusBarTokens, StatusBarTemplate;

type
  {Snapshot of every datum the token catalogue can render. Boolean
   *Available flags exist where 0 / '' is a valid state and the formatter
   would otherwise be unable to distinguish "not known" from "known zero".
   Fields whose 0 already means "unavailable" (resolution, fps, duration,
   bitrate) skip the flag.}
  TStatusBarValues = record
    {True iff video has been probed; tokens that read source-info fields
     short-circuit on this, including %audio% which only emits 'No audio'
     when video info is valid.}
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
 data unavailable. tkUnknown returns AToken.RawText so the user sees
 their typo back.

 AResolutionTransformGlyph: arrow/separator between native and capped
 dimensions in %save_dimension% / %copy_dimension%. Caller (typically
 the WLX form) resolves via PlatformDetect.ResolutionTransformGlyph
 once and passes it in, keeping this unit free of the OS-detect
 dependency.}
function FormatStatusBarToken(const AToken: TStatusBarToken;
  const AValues: TStatusBarValues;
  const AResolutionTransformGlyph: string = ''): string;

implementation

uses
  System.SysUtils,
  FrameOffsets;

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

{ALabel is 'Save' or 'Copy'. When AShowCap is False the post-cap segment
 is suppressed regardless of whether capping would change dimensions.}
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
  {Default True; cap=false is the user's opt-out.}
  Result := not SameText(AToken.AttrValue(ATTR_CAP, 'true'), 'false');
end;

type
  TStatusBarProjectorFunc = reference to function(
    const AValues: TStatusBarValues;
    const AToken: TStatusBarToken;
    const AResolutionTransformGlyph: string): string;

var
  GProjectors: array [TStatusBarTokenKind] of TStatusBarProjectorFunc;

function FormatStatusBarToken(const AToken: TStatusBarToken;
  const AValues: TStatusBarValues;
  const AResolutionTransformGlyph: string): string;
var
  Projector: TStatusBarProjectorFunc;
begin
  Projector := GProjectors[AToken.Kind];
  if Assigned(Projector) then
    Result := Projector(AValues, AToken, AResolutionTransformGlyph)
  else
    Result := '';

  if (AToken.Casing = tcUpper) and (Result <> '') then
    Result := UpperCase(Result);
end;

initialization

  GProjectors[tkUnknown] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := AToken.RawText;
  end;

  GProjectors[tkFilePosition] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if AValues.FilePositionAvailable then
      Result := Format('%d / %d',
        [AValues.FilePositionIndex, AValues.FilePositionTotal])
    else
      Result := '';
  end;

  GProjectors[tkFilename] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := AValues.Filename;
  end;

  GProjectors[tkFrames] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if AValues.FramesAvailable then
      Result := IntToStr(AValues.FramesTotal)
    else
      Result := '';
  end;

  GProjectors[tkFramePosition] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if not AValues.FramesAvailable then
      Result := ''
    else if AValues.IsSingleViewMode then
      Result := Format('%d / %d',
        [AValues.CurrentFrameIndex + 1, AValues.FramesTotal])
    else
      Result := IntToStr(AValues.FramesTotal);
  end;

  GProjectors[tkResolution] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if (AValues.SourceWidth > 0) and (AValues.SourceHeight > 0) then
      Result := Format('%dx%d', [AValues.SourceWidth, AValues.SourceHeight])
    else
      Result := '';
  end;

  GProjectors[tkFps] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if AValues.SourceFps > 0 then
      Result := Format('%.4g fps', [AValues.SourceFps])
    else
      Result := '';
  end;

  GProjectors[tkDuration] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if AValues.SourceDurationSec > 0 then
      Result := FormatDurationHMS(AValues.SourceDurationSec)
    else
      Result := '';
  end;

  GProjectors[tkBitrate] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    if AValues.SourceBitrateKbps > 0 then
      Result := FormatBitrateKbps(AValues.SourceBitrateKbps)
    else
      Result := '';
  end;

  GProjectors[tkVideoCodec] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := AValues.SourceVideoCodec;
  end;

  GProjectors[tkAudio] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := FormatAudio(AValues);
  end;

  GProjectors[tkLoadTime] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := AValues.LoadTimeText;
  end;

  GProjectors[tkSaveDimension] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := FormatPredictedDim('Save',
      AValues.SaveDimAvailable,
      AValues.SaveDimW, AValues.SaveDimH,
      AValues.SaveDimCappedW, AValues.SaveDimCappedH,
      ResolveCapAttr(AToken), AResolutionTransformGlyph);
  end;

  GProjectors[tkCopyDimension] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := FormatPredictedDim('Copy',
      AValues.CopyDimAvailable,
      AValues.CopyDimW, AValues.CopyDimH,
      AValues.CopyDimCappedW, AValues.CopyDimCappedH,
      ResolveCapAttr(AToken), AResolutionTransformGlyph);
  end;

  GProjectors[tkViewMode] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := AValues.ViewModeName;
  end;

  GProjectors[tkZoom] := function(const AValues: TStatusBarValues;
    const AToken: TStatusBarToken; const AResolutionTransformGlyph: string): string
  begin
    Result := AValues.ZoomModeName;
  end;

end.
