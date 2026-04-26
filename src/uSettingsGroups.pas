{Shared settings-group value objects for TPluginSettings (WLX) and
 TWcxSettings (WCX).

 Each record owns a related cluster of fields plus their INI Load/Save
 plumbing so the two settings classes don't have to re-implement the same
 key-by-key reads and writes. Defaults come from uDefaults; field names
 match the external properties exposed by the owning settings classes so
 the refactor is behaviour-preserving.

 LoadFrom uses the *current* record state as the fallback when an INI key
 is missing — callers reset the record to defaults before Load so the
 record's values act as the defaults. String fields additionally fall
 back to the pre-load value if the INI stored an explicit empty string,
 matching the historical "empty string becomes default font" behaviour.

 The timestamp group takes the show-toggle INI key as a parameter because
 WLX historically wrote it as "ShowTimecode" under [view] while WCX used
 "ShowTimestamp" under [combined]. Keeping the key name configurable
 avoids breaking either plugin's existing INI files.}
unit uSettingsGroups;

interface

uses
  System.UITypes, System.IniFiles,
  uTypes;

type
  {[extraction] group — eight fields shared verbatim between WLX and WCX.
   Both plugins write these under the INI section 'extraction'.}
  TExtractionSettingsGroup = record
    FramesCount: Integer;
    SkipEdgesPercent: Integer;
    MaxWorkers: Integer;
    MaxThreads: Integer;
    UseBmpPipe: Boolean;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
    RespectAnamorphic: Boolean;

    {Populates every field with the shared uDefaults constants.}
    class function Defaults: TExtractionSettingsGroup; static;
    {Reads the group from AIni. Missing keys fall back to the record's
     current values (callers reset to defaults first). Numeric fields are
     clamped to their documented ranges.}
    procedure LoadFrom(AIni: TIniFile; const ASection: string);
    {Writes the group to AIni. Round-trips exactly through LoadFrom.}
    procedure SaveTo(AIni: TIniFile; const ASection: string);
  end;

  {Info-banner group — seven fields shared verbatim between WLX and WCX.
   Show is exposed externally as ShowBanner on both classes. Both plugins
   use the same set of INI key names; only the section differs (WLX 'save',
   WCX 'combined').}
  TBannerSettingsGroup = record
    Show: Boolean;
    Background: TColor;
    TextColor: TColor;
    FontName: string;
    FontSize: Integer;
    AutoSize: Boolean;
    Position: TBannerPosition;

    class function Defaults: TBannerSettingsGroup; static;
    procedure LoadFrom(AIni: TIniFile; const ASection: string);
    procedure SaveTo(AIni: TIniFile; const ASection: string);
  end;

  {Timestamp overlay group — eight fields shared between WLX and WCX,
   modulo the show-toggle key name. WLX uses 'ShowTimecode' under [view],
   WCX uses 'ShowTimestamp' under [combined]. The caller passes the
   appropriate key name so neither plugin's existing INIs break.

   Show is exposed externally as ShowTimecode (WLX) / ShowTimestamp (WCX)
   via property delegation.}
  TTimestampSettingsGroup = record
    Show: Boolean;
    Corner: TTimestampCorner;
    FontName: string;
    FontSize: Integer;
    BackColor: TColor;
    BackAlpha: Byte;
    TextColor: TColor;
    TextAlpha: Byte;

    class function Defaults: TTimestampSettingsGroup; static;
    procedure LoadFrom(AIni: TIniFile; const ASection, AShowKey: string);
    procedure SaveTo(AIni: TIniFile; const ASection, AShowKey: string);
  end;

implementation

uses
  System.Math, System.SysUtils,
  uDefaults, uColorConv;

{TExtractionSettingsGroup}

class function TExtractionSettingsGroup.Defaults: TExtractionSettingsGroup;
begin
  Result.FramesCount := DEF_FRAMES_COUNT;
  Result.SkipEdgesPercent := DEF_SKIP_EDGES;
  Result.MaxWorkers := DEF_MAX_WORKERS;
  Result.MaxThreads := DEF_MAX_THREADS;
  Result.UseBmpPipe := DEF_USE_BMP_PIPE;
  Result.HwAccel := DEF_HW_ACCEL;
  Result.UseKeyframes := DEF_USE_KEYFRAMES;
  Result.RespectAnamorphic := DEF_RESPECT_ANAMORPHIC;
end;

procedure TExtractionSettingsGroup.LoadFrom(AIni: TIniFile; const ASection: string);
begin
  FramesCount := EnsureRange(AIni.ReadInteger(ASection, 'FramesCount', FramesCount),
    MIN_FRAMES_COUNT, MAX_FRAMES_COUNT);
  SkipEdgesPercent := EnsureRange(AIni.ReadInteger(ASection, 'SkipEdges', SkipEdgesPercent),
    MIN_SKIP_EDGES, MAX_SKIP_EDGES);
  MaxWorkers := EnsureRange(AIni.ReadInteger(ASection, 'MaxWorkers', MaxWorkers),
    MIN_MAX_WORKERS, MAX_MAX_WORKERS);
  MaxThreads := EnsureRange(AIni.ReadInteger(ASection, 'MaxThreads', MaxThreads),
    MIN_MAX_THREADS, MAX_MAX_THREADS);
  UseBmpPipe := AIni.ReadBool(ASection, 'UseBmpPipe', UseBmpPipe);
  HwAccel := AIni.ReadBool(ASection, 'HwAccel', HwAccel);
  UseKeyframes := AIni.ReadBool(ASection, 'UseKeyframes', UseKeyframes);
  RespectAnamorphic := AIni.ReadBool(ASection, 'RespectAnamorphic', RespectAnamorphic);
end;

procedure TExtractionSettingsGroup.SaveTo(AIni: TIniFile; const ASection: string);
begin
  AIni.WriteInteger(ASection, 'FramesCount', FramesCount);
  AIni.WriteInteger(ASection, 'SkipEdges', SkipEdgesPercent);
  AIni.WriteInteger(ASection, 'MaxWorkers', MaxWorkers);
  AIni.WriteInteger(ASection, 'MaxThreads', MaxThreads);
  AIni.WriteBool(ASection, 'UseBmpPipe', UseBmpPipe);
  AIni.WriteBool(ASection, 'HwAccel', HwAccel);
  AIni.WriteBool(ASection, 'UseKeyframes', UseKeyframes);
  AIni.WriteBool(ASection, 'RespectAnamorphic', RespectAnamorphic);
end;

{TBannerSettingsGroup}

class function TBannerSettingsGroup.Defaults: TBannerSettingsGroup;
begin
  {WLX previously used DEF_SHOW_BANNER = False; WCX used
   WCX_DEF_SHOW_BANNER = False. Both resolve to False, so a single
   default is correct. Callers that want a different initial Show
   state overwrite Show after calling Defaults.}
  Result.Show := False;
  Result.Background := DEF_BANNER_BACKGROUND;
  Result.TextColor := DEF_BANNER_TEXT_COLOR;
  Result.FontName := DEF_BANNER_FONT_NAME;
  Result.FontSize := DEF_BANNER_FONT_SIZE;
  Result.AutoSize := DEF_BANNER_FONT_AUTO_SIZE;
  Result.Position := DEF_BANNER_POSITION;
end;

procedure TBannerSettingsGroup.LoadFrom(AIni: TIniFile; const ASection: string);
var
  FallbackFont: string;
begin
  Show := AIni.ReadBool(ASection, 'ShowBanner', Show);
  Background := HexToColor(AIni.ReadString(ASection, 'BannerBackground', ''), Background);
  TextColor := HexToColor(AIni.ReadString(ASection, 'BannerTextColor', ''), TextColor);
  FallbackFont := FontName;
  FontName := AIni.ReadString(ASection, 'BannerFont', FontName);
  if FontName.Trim = '' then
    FontName := FallbackFont;
  FontSize := EnsureRange(AIni.ReadInteger(ASection, 'BannerFontSize', FontSize),
    MIN_BANNER_FONT_SIZE, MAX_BANNER_FONT_SIZE);
  AutoSize := AIni.ReadBool(ASection, 'BannerFontAutoSize', AutoSize);
  Position := StrToBannerPosition(AIni.ReadString(ASection, 'BannerPosition', ''), Position);
end;

procedure TBannerSettingsGroup.SaveTo(AIni: TIniFile; const ASection: string);
begin
  AIni.WriteBool(ASection, 'ShowBanner', Show);
  AIni.WriteString(ASection, 'BannerBackground', ColorToHex(Background));
  AIni.WriteString(ASection, 'BannerTextColor', ColorToHex(TextColor));
  AIni.WriteString(ASection, 'BannerFont', FontName);
  AIni.WriteInteger(ASection, 'BannerFontSize', FontSize);
  AIni.WriteBool(ASection, 'BannerFontAutoSize', AutoSize);
  AIni.WriteString(ASection, 'BannerPosition', BannerPositionToStr(Position));
end;

{TTimestampSettingsGroup}

class function TTimestampSettingsGroup.Defaults: TTimestampSettingsGroup;
begin
  {Show defaults to True — matches the WLX DEF_SHOW_TIMECODE. WCX's
   WCX_DEF_SHOW_TIMESTAMP is also True, so both plugins agree. Callers
   only override when they need a non-historical start state.
   FontName/FontSize match WLX's DEF_TIMESTAMP_FONT / _SIZE; WCX
   overrides these to Consolas/9 after calling Defaults because its
   historical default differs.}
  Result.Show := True;
  Result.Corner := DEF_TIMESTAMP_CORNER;
  Result.FontName := DEF_TIMESTAMP_FONT;
  Result.FontSize := DEF_TIMESTAMP_FONT_SIZE;
  Result.BackColor := DEF_TC_BACK_COLOR;
  Result.BackAlpha := DEF_TC_BACK_ALPHA;
  Result.TextColor := DEF_TIMESTAMP_TEXT_COLOR;
  Result.TextAlpha := DEF_TIMESTAMP_TEXT_ALPHA;
end;

procedure TTimestampSettingsGroup.LoadFrom(AIni: TIniFile; const ASection, AShowKey: string);
var
  FallbackFont: string;
  FallbackColor: TColor;
  FallbackAlpha: Byte;
begin
  Show := AIni.ReadBool(ASection, AShowKey, Show);
  Corner := StrToTimestampCorner(AIni.ReadString(ASection, 'TimestampCorner', ''), Corner);
  FallbackFont := FontName;
  FontName := AIni.ReadString(ASection, 'TimestampFont', FontName);
  if FontName.Trim = '' then
    FontName := FallbackFont;
  FontSize := EnsureRange(AIni.ReadInteger(ASection, 'TimestampFontSize', FontSize),
    MIN_TIMESTAMP_FONT_SIZE, MAX_TIMESTAMP_FONT_SIZE);
  {HexToColorAlpha's out-params are simple types, so aliasing with the
   const defaults is safe under Delphi's out semantics. Local fallback
   vars guard defensively anyway.}
  FallbackColor := BackColor;
  FallbackAlpha := BackAlpha;
  HexToColorAlpha(AIni.ReadString(ASection, 'TimecodeBackground', ''),
    FallbackColor, FallbackAlpha, BackColor, BackAlpha);
  TextColor := HexToColor(AIni.ReadString(ASection, 'TimestampTextColor', ''), TextColor);
  TextAlpha := EnsureRange(AIni.ReadInteger(ASection, 'TimestampTextAlpha', TextAlpha),
    MIN_TIMESTAMP_TEXT_ALPHA, MAX_TIMESTAMP_TEXT_ALPHA);
end;

procedure TTimestampSettingsGroup.SaveTo(AIni: TIniFile; const ASection, AShowKey: string);
begin
  AIni.WriteBool(ASection, AShowKey, Show);
  AIni.WriteString(ASection, 'TimestampCorner', TimestampCornerToStr(Corner));
  AIni.WriteString(ASection, 'TimestampFont', FontName);
  AIni.WriteInteger(ASection, 'TimestampFontSize', FontSize);
  AIni.WriteString(ASection, 'TimecodeBackground', ColorAlphaToHex(BackColor, BackAlpha));
  AIni.WriteString(ASection, 'TimestampTextColor', ColorToHex(TextColor));
  AIni.WriteInteger(ASection, 'TimestampTextAlpha', TextAlpha);
end;

end.
