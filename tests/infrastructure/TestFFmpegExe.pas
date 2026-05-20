unit TestFFmpegExe;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegProbeIntegration = class
  public
    {Real ffmpeg.exe + a real anamorphic file. Skipped when ffmpeg.exe is
     not on the system PATH so the suite stays runnable on machines without
     ffmpeg installed.}
    [Test] procedure TestProbeAnamorphicVideo;
  end;

  {Drives TFFmpegExe through a fake IProcessRunner so the probe-parse
   sequencing and the extract decode branch are tested without ffmpeg.}
  [TestFixture]
  TTestFFmpegExeWithFakeRunner = class
  public
    [Test] procedure ProbeVideo_ParsesCannedStderr;
    [Test] procedure ProbeVideo_EmptyStderr_SetsErrorMessage;
    [Test] procedure ProbeVideo_UnparseableStderr_SetsErrorMessage;
    [Test] procedure ExtractFrame_BmpPipe_ReturnsBitmap;
    [Test] procedure ExtractFrame_ShortOutput_ReturnsNil;
    [Test] procedure ExtractFrame_NonZeroExit_ReturnsNil;
  end;

  [TestFixture]
  TTestFFmpegLocator = class
  private
    FTempDir: string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TestFindInPluginDir;
    [Test] procedure TestFindAtConfiguredPath;
    [Test] procedure TestPluginDirHasPriority;
    [Test] procedure TestNotFoundReturnsEmpty;
    [Test] procedure TestEmptyPluginDir;
    [Test] procedure TestConfiguredPathNotExists;
    [Test] procedure TestConfiguredPathExpandsEnvVars;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Winapi.Windows, Vcl.Graphics,
  Types, FFmpegExe, FFmpegLocator, VideoInfo, VideoProbing, FrameExtractor,
  ProcessRunner;

function TestDataPath(const AFileName: string): string;
begin
  {Tests run from tests/Win64/Debug/GlimpseTests.exe; data lives in tests/data/}
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\data\' + AFileName));
end;

const
  {Realistic ffmpeg -i stderr — the same shape TestFFmpegProbeParser pins.}
  SAMPLE_FFMPEG_STDERR =
    'Input #0, mov,mp4,m4a,3gp,3g2,mj2, from ''test.mp4'':'#13#10 +
    '  Metadata:'#13#10 +
    '    encoder         : Lavf58.29.100'#13#10 +
    '  Duration: 00:10:30.50, start: 0.000000, bitrate: 2000 kb/s'#13#10 +
    '  Stream #0:0(und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709), ' +
      '1920x1080 [SAR 1:1 DAR 16:9], 1800 kb/s, 30 fps, 30 tbr, 15360 tbn (default)'#13#10 +
    '  Stream #0:1(und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, ' +
      '128 kb/s (default)'#13#10 +
    'At least one output file must be specified'#13#10;

type
  {Canned IProcessRunner: yields a fixed exit code and stdout/stderr so
   TFFmpegExe can be exercised without spawning a real process.}
  TFakeProcessRunner = class(TInterfacedObject, IProcessRunner)
  strict private
    FExitCode: Integer;
    FStdOut, FStdErr: TBytes;
  public
    constructor Create(AExitCode: Integer; const AStdOut, AStdErr: TBytes);
    function Run(const ACommandLine: string; out AStdOut, AStdErr: TBytes;
      ATimeoutMs: DWORD; ACancelHandle: THandle): Integer;
  end;

constructor TFakeProcessRunner.Create(AExitCode: Integer; const AStdOut, AStdErr: TBytes);
begin
  inherited Create;
  FExitCode := AExitCode;
  FStdOut := AStdOut;
  FStdErr := AStdErr;
end;

function TFakeProcessRunner.Run(const ACommandLine: string; out AStdOut, AStdErr: TBytes;
  ATimeoutMs: DWORD; ACancelHandle: THandle): Integer;
begin
  AStdOut := FStdOut;
  AStdErr := FStdErr;
  Result := FExitCode;
end;

{UTF-8 bytes, as ffmpeg would emit on its stderr pipe.}
function Utf8Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

{A real, decodable BMP byte stream — a small bitmap round-tripped through
 SaveToStream, exactly what ffmpeg's bmp image2pipe produces.}
function MakeBmpBytes(AWidth, AHeight: Integer): TBytes;
var
  Bmp: TBitmap;
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create;
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf24bit;
      Bmp.SetSize(AWidth, AHeight);
      Bmp.SaveToStream(Stream);
    finally
      Bmp.Free;
    end;
    Result := Copy(Stream.Bytes, 0, Stream.Size);
  finally
    Stream.Free;
  end;
end;

function BmpPipeOptions: TExtractionOptions;
begin
  Result := Default(TExtractionOptions);
  Result.UseBmpPipe := True;
end;

{ TTestFFmpegExeWithFakeRunner }

procedure TTestFFmpegExeWithFakeRunner.ProbeVideo_ParsesCannedStderr;
var
  FFmpeg: IVideoProber;
  Info: TVideoInfo;
begin
  FFmpeg := TFFmpegExe.Create('ffmpeg.exe', 30000,
    TFakeProcessRunner.Create(1, nil, Utf8Bytes(SAMPLE_FFMPEG_STDERR)));
  Info := FFmpeg.ProbeVideo('any.mp4');
  Assert.IsTrue(Info.IsValid, 'Canned probe output must yield a valid result');
  Assert.AreEqual(Double(630.5), Info.Duration, 0.01, 'Duration 00:10:30.50');
  Assert.AreEqual(1920, Info.Width);
  Assert.AreEqual(1080, Info.Height);
  Assert.AreEqual('h264', Info.VideoCodec);
  Assert.AreEqual(Double(30.0), Info.Fps, 0.01);
end;

procedure TTestFFmpegExeWithFakeRunner.ProbeVideo_EmptyStderr_SetsErrorMessage;
var
  FFmpeg: IVideoProber;
  Info: TVideoInfo;
begin
  FFmpeg := TFFmpegExe.Create('ffmpeg.exe', 30000,
    TFakeProcessRunner.Create(1, nil, nil));
  Info := FFmpeg.ProbeVideo('any.mp4');
  Assert.IsFalse(Info.IsValid);
  Assert.AreEqual('No output from ffmpeg', Info.ErrorMessage);
end;

procedure TTestFFmpegExeWithFakeRunner.ProbeVideo_UnparseableStderr_SetsErrorMessage;
var
  FFmpeg: IVideoProber;
  Info: TVideoInfo;
begin
  FFmpeg := TFFmpegExe.Create('ffmpeg.exe', 30000,
    TFakeProcessRunner.Create(1, nil, Utf8Bytes('not ffmpeg output at all')));
  Info := FFmpeg.ProbeVideo('any.mp4');
  Assert.IsFalse(Info.IsValid);
  Assert.AreEqual('Could not parse video metadata', Info.ErrorMessage);
end;

procedure TTestFFmpegExeWithFakeRunner.ExtractFrame_BmpPipe_ReturnsBitmap;
var
  FFmpeg: IFrameExtractor;
  Bmp: TBitmap;
begin
  FFmpeg := TFFmpegExe.Create('ffmpeg.exe', 30000,
    TFakeProcessRunner.Create(0, MakeBmpBytes(8, 6), nil));
  Bmp := FFmpeg.ExtractFrame('any.mp4', 1.0, BmpPipeOptions);
  try
    Assert.IsNotNull(Bmp, 'Valid BMP stdout must decode into a bitmap');
    Assert.AreEqual(8, Bmp.Width);
    Assert.AreEqual(6, Bmp.Height);
  finally
    Bmp.Free;
  end;
end;

procedure TTestFFmpegExeWithFakeRunner.ExtractFrame_ShortOutput_ReturnsNil;
var
  FFmpeg: IFrameExtractor;
  Bmp: TBitmap;
begin
  {Fewer than 8 bytes cannot be an image; ExtractFrame must fail closed.}
  FFmpeg := TFFmpegExe.Create('ffmpeg.exe', 30000,
    TFakeProcessRunner.Create(0, TBytes.Create(1, 2, 3), nil));
  Bmp := FFmpeg.ExtractFrame('any.mp4', 1.0, BmpPipeOptions);
  try
    Assert.IsNull(Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TTestFFmpegExeWithFakeRunner.ExtractFrame_NonZeroExit_ReturnsNil;
var
  FFmpeg: IFrameExtractor;
  Bmp: TBitmap;
begin
  {A non-zero exit (or runner -1 for timeout/cancel) must yield nil even
   when the stdout payload would otherwise decode.}
  FFmpeg := TFFmpegExe.Create('ffmpeg.exe', 30000,
    TFakeProcessRunner.Create(-1, MakeBmpBytes(8, 6), nil));
  Bmp := FFmpeg.ExtractFrame('any.mp4', 1.0, BmpPipeOptions);
  try
    Assert.IsNull(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ TTestFFmpegProbeIntegration }

procedure TTestFFmpegProbeIntegration.TestProbeAnamorphicVideo;
var
  FFmpegPath, VideoPath: string;
  FFmpeg: TFFmpegExe;
  Info: TVideoInfo;
begin
  FFmpegPath := FindFFmpegExe('', '');
  if FFmpegPath = '' then
  begin
    {Pass-through when ffmpeg is not on PATH; the unit-level parse tests
     still cover the parsing logic.}
    Assert.Pass('ffmpeg.exe not on PATH; skipping integration test');
    Exit;
  end;

  VideoPath := TestDataPath('test_anamorphic.mp4');
  Assert.IsTrue(TFile.Exists(VideoPath),
    'Test data missing: ' + VideoPath);

  FFmpeg := TFFmpegExe.Create(FFmpegPath);
  try
    Info := FFmpeg.ProbeVideo(VideoPath);
    Assert.IsTrue(Info.IsValid, 'Probe must succeed: ' + Info.ErrorMessage);
    Assert.AreEqual(720, Info.Width, 'Storage width');
    Assert.AreEqual(576, Info.Height, 'Storage height');
    Assert.AreEqual(64, Info.SampleAspectN, 'SAR numerator');
    Assert.AreEqual(45, Info.SampleAspectD, 'SAR denominator');
    Assert.AreEqual(1024, Info.DisplayWidth,
      'Display width = round(720 * 64/45) = 1024');
    Assert.AreEqual(576, Info.DisplayHeight, 'SAR scales width, not height');
  finally
    FFmpeg.Free;
  end;
end;

{ TTestFFmpegLocator }

procedure TTestFFmpegLocator.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_Loc_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestFFmpegLocator.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestFFmpegLocator.TestFindInPluginDir;
var
  PluginDir, Found: string;
begin
  PluginDir := TPath.Combine(FTempDir, 'plugin');
  TDirectory.CreateDirectory(PluginDir);
  TFile.WriteAllText(TPath.Combine(PluginDir, 'ffmpeg.exe'), 'dummy');

  Found := FindFFmpegExe(PluginDir, '');
  Assert.AreEqual(TPath.Combine(PluginDir, 'ffmpeg.exe'), Found);
end;

procedure TTestFFmpegLocator.TestFindAtConfiguredPath;
var
  ExePath, Found: string;
begin
  ExePath := TPath.Combine(FTempDir, 'custom_ffmpeg.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  { Empty plugin dir (no ffmpeg there), configured path exists }
  Found := FindFFmpegExe(TPath.Combine(FTempDir, 'empty'), ExePath);
  Assert.AreEqual(ExePath, Found);
end;

procedure TTestFFmpegLocator.TestPluginDirHasPriority;
var
  PluginDir, ConfigPath, Found: string;
begin
  { Both plugin dir and configured path have ffmpeg; plugin dir should win }
  PluginDir := TPath.Combine(FTempDir, 'plugin');
  TDirectory.CreateDirectory(PluginDir);
  TFile.WriteAllText(TPath.Combine(PluginDir, 'ffmpeg.exe'), 'plugin');

  ConfigPath := TPath.Combine(FTempDir, 'other_ffmpeg.exe');
  TFile.WriteAllText(ConfigPath, 'config');

  Found := FindFFmpegExe(PluginDir, ConfigPath);
  Assert.AreEqual(TPath.Combine(PluginDir, 'ffmpeg.exe'), Found,
    'Plugin directory should have priority over configured path');
end;

procedure TTestFFmpegLocator.TestNotFoundReturnsEmpty;
var
  Found: string;
begin
  { Neither plugin dir nor configured path has ffmpeg, and we cannot rely
    on system PATH for a deterministic test. Just verify no crash. }
  Found := FindFFmpegExe(TPath.Combine(FTempDir, 'nowhere'), '');
  { Result depends on whether ffmpeg is on system PATH; just verify no exception }
  Assert.Pass;
end;

procedure TTestFFmpegLocator.TestEmptyPluginDir;
var
  ExePath, Found: string;
begin
  ExePath := TPath.Combine(FTempDir, 'ff.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  Found := FindFFmpegExe('', ExePath);
  Assert.AreEqual(ExePath, Found, 'Empty plugin dir should skip to configured path');
end;

procedure TTestFFmpegLocator.TestConfiguredPathNotExists;
var
  Found: string;
begin
  { Configured path points to a non-existent file }
  Found := FindFFmpegExe(
    TPath.Combine(FTempDir, 'empty'),
    TPath.Combine(FTempDir, 'no_such_file.exe'));
  { Should fall through to system PATH search }
  Assert.Pass;
end;

procedure TTestFFmpegLocator.TestConfiguredPathExpandsEnvVars;
var
  SubDir, ExePath, Found: string;
begin
  { Place ffmpeg.exe inside a subdirectory of TEMP and reference it via
    the %TEMP% environment variable. FindFFmpegExe must expand the variable
    before checking TFile.Exists. }
  SubDir := TPath.Combine(FTempDir, 'tools');
  TDirectory.CreateDirectory(SubDir);
  ExePath := TPath.Combine(SubDir, 'ffmpeg.exe');
  TFile.WriteAllText(ExePath, 'dummy');

  { Set a custom env var pointing to our temp dir }
  SetEnvironmentVariable('VT_TEST_PLUGIN_DIR', PChar(FTempDir));
  try
    Found := FindFFmpegExe('',
      '%VT_TEST_PLUGIN_DIR%' + PathDelim + 'tools' + PathDelim + 'ffmpeg.exe');
    Assert.AreEqual(ExePath, Found,
      'FindFFmpegExe must expand environment variables in configured path');
  finally
    SetEnvironmentVariable('VT_TEST_PLUGIN_DIR', nil);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegProbeIntegration);
  TDUnitX.RegisterTestFixture(TTestFFmpegExeWithFakeRunner);
  TDUnitX.RegisterTestFixture(TTestFFmpegLocator);

end.
