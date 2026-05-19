{Pure data and text formatting for the info banner. Bitmap construction
 lives in uBannerPainter; this unit stays VCL-free for testability.}
unit uBannerInfo;

interface

uses
  uVideoInfo;

type
  TBannerInfo = record
    FileName: string;
    FileSizeBytes: Int64;
    DurationSec: Double;
    {Storage pixel grid; for non-square-pixel sources DisplayWidth/Height
     differ and FormatBannerLines renders "stored -> displayed".}
    Width, Height: Integer;
    DisplayWidth, DisplayHeight: Integer;
    VideoCodec: string;
    VideoBitrateKbps: Integer;
    Fps: Double;
    AudioCodec: string;
    AudioSampleRate: Integer;
    AudioChannels: string;
    AudioBitrateKbps: Integer;
  end;

function BuildBannerInfo(const AFileName: string; const AVideoInfo: TVideoInfo): TBannerInfo;

function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;

implementation

uses
  System.SysUtils, System.IOUtils,
  uFrameOffsets;

function FormatFileSize(ABytes: Int64): string;
var
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create('en-US');
  if ABytes >= 1024 * 1024 * 1024 then
    Result := Format('%.2f GB', [ABytes / (1024.0 * 1024 * 1024)], Fmt)
  else if ABytes >= 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024.0 * 1024)], Fmt)
  else if ABytes >= 1024 then
    Result := Format('%.0f KB', [ABytes / 1024.0], Fmt)
  else
    Result := Format('%d B', [ABytes]);
end;

function BuildBannerInfo(const AFileName: string; const AVideoInfo: TVideoInfo): TBannerInfo;
begin
  Result := Default (TBannerInfo);
  Result.FileName := AFileName;
  if TFile.Exists(AFileName) then
    Result.FileSizeBytes := TFile.GetSize(AFileName);
  Result.DurationSec := AVideoInfo.Duration;
  Result.Width := AVideoInfo.Width;
  Result.Height := AVideoInfo.Height;
  Result.DisplayWidth := AVideoInfo.DisplayWidth;
  Result.DisplayHeight := AVideoInfo.DisplayHeight;
  Result.VideoCodec := AVideoInfo.VideoCodec;
  Result.VideoBitrateKbps := AVideoInfo.VideoBitrateKbps;
  Result.Fps := AVideoInfo.Fps;
  Result.AudioCodec := AVideoInfo.AudioCodec;
  Result.AudioSampleRate := AVideoInfo.AudioSampleRate;
  Result.AudioChannels := AVideoInfo.AudioChannels;
  Result.AudioBitrateKbps := AVideoInfo.AudioBitrateKbps;
end;

function FormatBannerLines(const AInfo: TBannerInfo): TArray<string>;
var
  Line1, Line2, Line3, Audio: string;
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create('en-US');
  Line1 := Format('File: %s', [ExtractFileName(AInfo.FileName)]);
  if AInfo.FileSizeBytes > 0 then
    Line1 := Line1 + Format('  |  Size: %s', [FormatFileSize(AInfo.FileSizeBytes)]);

  Line2 := '';
  if AInfo.DurationSec > 0 then
    Line2 := Format('Duration: %s', [FormatDurationHMS(AInfo.DurationSec)]);
  if (AInfo.Width > 0) and (AInfo.Height > 0) then
  begin
    if Line2 <> '' then
      Line2 := Line2 + '  |  ';
    {Show "storage -> display" for anamorphic so users see why the saved
     combined image is wider than the raw WxH reported by other tools.}
    if (AInfo.DisplayWidth > 0) and (AInfo.DisplayHeight > 0) and ((AInfo.DisplayWidth <> AInfo.Width) or (AInfo.DisplayHeight <> AInfo.Height)) then
      Line2 := Line2 + Format('%dx%d -> %dx%d', [AInfo.Width, AInfo.Height, AInfo.DisplayWidth, AInfo.DisplayHeight])
    else
      Line2 := Line2 + Format('%dx%d', [AInfo.Width, AInfo.Height]);
  end;
  if AInfo.Fps > 0 then
  begin
    if Line2 <> '' then
      Line2 := Line2 + '  |  ';
    Line2 := Line2 + Format('%.3f fps', [AInfo.Fps], Fmt);
  end;

  Line3 := '';
  if AInfo.VideoCodec <> '' then
  begin
    Line3 := Format('Video: %s', [AInfo.VideoCodec]);
    if AInfo.VideoBitrateKbps > 0 then
      Line3 := Line3 + Format('  %d kbps', [AInfo.VideoBitrateKbps]);
  end;
  if AInfo.AudioCodec <> '' then
  begin
    Audio := Format('Audio: %s', [AInfo.AudioCodec]);
    if AInfo.AudioSampleRate > 0 then
      Audio := Audio + Format('  %d Hz', [AInfo.AudioSampleRate]);
    if AInfo.AudioChannels <> '' then
      Audio := Audio + Format('  %s', [AInfo.AudioChannels]);
    if AInfo.AudioBitrateKbps > 0 then
      Audio := Audio + Format('  %d kbps', [AInfo.AudioBitrateKbps]);
    if Line3 <> '' then
      Line3 := Line3 + '  |  ';
    Line3 := Line3 + Audio;
  end;

  Result := [Line1, Line2, Line3];
end;

end.
