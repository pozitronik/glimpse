unit TestFFmpegCmdLine;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegCmdLine = class
  public
    { Version parsing }
    [Test] procedure TestParseVersionStandard;
    [Test] procedure TestParseVersionWithSuffix;
    [Test] procedure TestParseVersionGitBuild;
    [Test] procedure TestParseVersionMultiLine;
    [Test] procedure TestParseVersionEmpty;
    [Test] procedure TestParseVersionNotFFmpeg;
    [Test] procedure TestParseVersionCaseInsensitive;
    { Extract command-line construction }
    [Test] procedure TestBuildExtractCmdLineDefault;
    [Test] procedure TestBuildExtractCmdLineMaxSideOnly;
    [Test] procedure TestBuildExtractCmdLineRespectAnamorphicOnly;
    [Test] procedure TestBuildExtractCmdLineRespectAnamorphicWithMaxSide;
    [Test] procedure TestBuildExtractCmdLineMaxSideUsesMinExpressionToPreventUpscale;
    [Test] procedure TestBuildExtractCmdLineHwAccel;
    [Test] procedure TestBuildExtractCmdLineUseKeyframes;
    [Test] procedure TestBuildExtractCmdLinePngCodec;
    [Test] procedure TestBuildExtractCmdLineTimeOffsetInvariantLocale;
  end;

implementation

uses
  System.SysUtils,
  uTypes, uFFmpegProbeParser, uFFmpegCmdLine;

{ TTestFFmpegCmdLine: Version }

procedure TTestFFmpegCmdLine.TestParseVersionStandard;
begin
  Assert.AreEqual('6.1.1',
    ParseFFmpegVersion('ffmpeg version 6.1.1 Copyright (c) 2000-2023'));
end;

procedure TTestFFmpegCmdLine.TestParseVersionWithSuffix;
begin
  Assert.AreEqual('7.0',
    ParseFFmpegVersion('ffmpeg version 7.0-full_build Copyright (c) 2000-2024'));
end;

procedure TTestFFmpegCmdLine.TestParseVersionGitBuild;
begin
  Assert.AreEqual('N',
    ParseFFmpegVersion('ffmpeg version N-112858-g3545b4a51b Copyright (c) 2000-2024'));
end;

procedure TTestFFmpegCmdLine.TestParseVersionMultiLine;
begin
  Assert.AreEqual('5.1.4',
    ParseFFmpegVersion('ffmpeg version 5.1.4 Copyright'#13#10 +
      'built with gcc 12.2.0'#13#10 +
      'configuration: --enable-gpl'));
end;

procedure TTestFFmpegCmdLine.TestParseVersionEmpty;
begin
  Assert.AreEqual('', ParseFFmpegVersion(''));
end;

procedure TTestFFmpegCmdLine.TestParseVersionNotFFmpeg;
begin
  Assert.AreEqual('', ParseFFmpegVersion('Microsoft Windows [Version 10.0.19045]'));
  Assert.AreEqual('', ParseFFmpegVersion('Usage: someapp [options]'));
end;

procedure TTestFFmpegCmdLine.TestParseVersionCaseInsensitive;
begin
  Assert.AreEqual('6.0',
    ParseFFmpegVersion('FFmpeg version 6.0 Copyright'));
end;

{ Extract command-line construction }

function MakeBaseOptions: TExtractionOptions;
begin
  Result := Default(TExtractionOptions);
  Result.UseBmpPipe := True;
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineDefault;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  {Defaults: BMP pipe, no scale filter, no HW accel, no keyframes, square pixels.
   The bare command must point at the exe, the input file, and a single frame.}
  Opts := MakeBaseOptions;
  CmdLine := BuildExtractCmdLine('C:\bin\ffmpeg.exe', 'C:\v.mp4', 12.5, Opts);

  Assert.Contains(CmdLine, '"C:\bin\ffmpeg.exe"');
  Assert.Contains(CmdLine, '-i "C:\v.mp4"');
  Assert.Contains(CmdLine, '-frames:v 1');
  Assert.Contains(CmdLine, '-vcodec bmp');
  Assert.IsFalse(CmdLine.Contains('-vf '),
    'No filters expected when both MaxSide and RespectAnamorphic are off');
  Assert.IsFalse(CmdLine.Contains('-hwaccel'),
    'HwAccel flag must not appear when disabled');
  Assert.IsFalse(CmdLine.Contains('-noaccurate_seek'),
    'Keyframe flag must not appear when disabled');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineMaxSideOnly;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  Opts := MakeBaseOptions;
  Opts.MaxSide := 256;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine,
    '-vf scale=min(iw\,256):min(ih\,256):force_original_aspect_ratio=decrease:force_divisible_by=2 ');
  Assert.IsFalse(CmdLine.Contains('iw*sar'),
    'SAR scale must not appear when RespectAnamorphic is off');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineRespectAnamorphicOnly;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  {SAR scale alone, no MaxSide cap.}
  Opts := MakeBaseOptions;
  Opts.RespectAnamorphic := True;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine, '-vf scale=iw*sar:ih,setsar=1 ');
  Assert.IsFalse(CmdLine.Contains('force_original_aspect_ratio'),
    'MaxSide cap must not appear when MaxSide is 0');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineRespectAnamorphicWithMaxSide;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  {Both filters, comma-chained, SAR correction first so the cap operates
   on display dimensions.}
  Opts := MakeBaseOptions;
  Opts.RespectAnamorphic := True;
  Opts.MaxSide := 512;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine,
    '-vf scale=iw*sar:ih,setsar=1,scale=min(iw\,512):min(ih\,512):force_original_aspect_ratio=decrease:force_divisible_by=2 ');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineMaxSideUsesMinExpressionToPreventUpscale;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  {Regression test for a real bug: a 720x578 anamorphic source extracted with
   MaxSide=1920 was being upscaled to 1920x1080 because the bare
   'scale=W:W:force_original_aspect_ratio=decrease' form treats W as the
   target box, not a ceiling. The fix is to wrap each target dimension in
   min(iw,W) / min(ih,W) so undersized inputs become a no-op for the scale
   filter. This test pins both halves of the contract so the bug cannot
   silently regress.}
  Opts := MakeBaseOptions;
  Opts.MaxSide := 1920;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine, 'min(iw\,1920)',
    'Width target must be capped via min(iw,MAX) so smaller sources are not upscaled');
  Assert.Contains(CmdLine, 'min(ih\,1920)',
    'Height target must be capped via min(ih,MAX) so smaller sources are not upscaled');
  Assert.IsFalse(CmdLine.Contains('scale=1920:1920'),
    'The bare "scale=MAX:MAX" form must not appear — it would upscale undersized sources');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineHwAccel;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  Opts := MakeBaseOptions;
  Opts.HwAccel := True;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine, '-hwaccel auto ');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineUseKeyframes;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  Opts := MakeBaseOptions;
  Opts.UseKeyframes := True;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine, '-noaccurate_seek ');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLinePngCodec;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  Opts := Default(TExtractionOptions);
  Opts.UseBmpPipe := False;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 0, Opts);

  Assert.Contains(CmdLine, '-q:v 2');
  Assert.Contains(CmdLine, '-vcodec png');
end;

procedure TTestFFmpegCmdLine.TestBuildExtractCmdLineTimeOffsetInvariantLocale;
var
  Opts: TExtractionOptions;
  CmdLine: string;
begin
  {Time offset must always use '.' as decimal separator, regardless of the
   thread locale, otherwise ffmpeg rejects it.}
  Opts := MakeBaseOptions;
  CmdLine := BuildExtractCmdLine('ffmpeg', 'v.mp4', 1.25, Opts);

  Assert.Contains(CmdLine, '-ss 1.250 ');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegCmdLine);

end.
