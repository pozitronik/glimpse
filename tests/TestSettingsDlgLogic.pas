{ Tests for the pure formatting helpers shared by both settings dialogs.
  These exercise every branch of the policy without touching VCL or
  spawning ffmpeg. }
unit TestSettingsDlgLogic;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsDlgLogic = class
  public
    { MaxThreadsAutoLabel }
    [Test] procedure MaxThreads_OnePerFrameOff_ReturnsEmpty;
    [Test] procedure MaxThreads_OnePerFrameOff_IgnoresThreadsAndCpu;
    [Test] procedure MaxThreads_AutoNegativePos_ReturnsNoLimit;
    [Test] procedure MaxThreads_AutoZeroPos_ReturnsCoresLabel;
    [Test] procedure MaxThreads_AutoZeroPos_FormatsCpuCount;
    [Test] procedure MaxThreads_AutoExplicitPos_ReturnsEmpty;

    { FFmpegInfoLabelText }
    [Test] procedure FFmpegInfo_NoPath_ReturnsNotFound;
    [Test] procedure FFmpegInfo_FileMissing_IncludesPath;
    [Test] procedure FFmpegInfo_Invalid_IncludesPath;
    [Test] procedure FFmpegInfo_ValidEmptyInput_ShowsDetected;
    [Test] procedure FFmpegInfo_ValidNonEmptyInput_ShowsVersionOnly;
    [Test] procedure FFmpegInfo_ValidEmptyInput_IncludesPathAndVersion;
  end;

implementation

uses
  System.SysUtils,
  uSettingsDlgLogic;

{ -------- MaxThreadsAutoLabel -------- }

procedure TTestSettingsDlgLogic.MaxThreads_OnePerFrameOff_ReturnsEmpty;
begin
  { When the field is disabled the hint must be empty regardless of the
    other inputs. }
  Assert.AreEqual('', MaxThreadsAutoLabel(False, 0, 8));
end;

procedure TTestSettingsDlgLogic.MaxThreads_OnePerFrameOff_IgnoresThreadsAndCpu;
begin
  { Belt-and-braces: a stale spin-edit value or a different CPU count
    must not leak into the label when the mode is off. }
  Assert.AreEqual('', MaxThreadsAutoLabel(False, 999, 1));
  Assert.AreEqual('', MaxThreadsAutoLabel(False, -1, 32));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoNegativePos_ReturnsNoLimit;
begin
  { Spin position < 0 is the sentinel for "unlimited threads". }
  Assert.AreEqual('(no limit)', MaxThreadsAutoLabel(True, -1, 8));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoZeroPos_ReturnsCoresLabel;
begin
  Assert.AreEqual('(auto: 4 cores)', MaxThreadsAutoLabel(True, 0, 4));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoZeroPos_FormatsCpuCount;
begin
  { Verify the live CPU count is interpolated rather than a hardcoded
    constant — different machines must show different numbers. }
  Assert.AreEqual('(auto: 16 cores)', MaxThreadsAutoLabel(True, 0, 16));
  Assert.AreEqual('(auto: 1 cores)', MaxThreadsAutoLabel(True, 0, 1));
end;

procedure TTestSettingsDlgLogic.MaxThreads_AutoExplicitPos_ReturnsEmpty;
begin
  { When the user picked a positive value the hint is suppressed —
    the visible spin shows the chosen value, no extra text needed. }
  Assert.AreEqual('', MaxThreadsAutoLabel(True, 1, 8));
  Assert.AreEqual('', MaxThreadsAutoLabel(True, 12, 8));
end;

{ -------- FFmpegInfoLabelText -------- }

procedure TTestSettingsDlgLogic.FFmpegInfo_NoPath_ReturnsNotFound;
begin
  Assert.AreEqual('Not found',
    FFmpegInfoLabelText(fpsNoPath, '', '', True));
end;

procedure TTestSettingsDlgLogic.FFmpegInfo_FileMissing_IncludesPath;
begin
  Assert.AreEqual('Not found: C:\nope\ffmpeg.exe',
    FFmpegInfoLabelText(fpsFileMissing, 'C:\nope\ffmpeg.exe', '', False));
end;

procedure TTestSettingsDlgLogic.FFmpegInfo_Invalid_IncludesPath;
begin
  Assert.AreEqual('Invalid executable: C:\bin\notffmpeg.exe',
    FFmpegInfoLabelText(fpsInvalid, 'C:\bin\notffmpeg.exe', '', False));
end;

procedure TTestSettingsDlgLogic.FFmpegInfo_ValidEmptyInput_ShowsDetected;
begin
  { Autodetected path: label leads with 'Detected:' so the user knows
    the dialog filled it in for them. }
  Assert.IsTrue(FFmpegInfoLabelText(fpsValid, 'C:\ff\ffmpeg.exe', '6.1', True)
    .StartsWith('Detected:'),
    'Empty input + valid must produce a Detected label');
end;

procedure TTestSettingsDlgLogic.FFmpegInfo_ValidNonEmptyInput_ShowsVersionOnly;
begin
  { User-typed path: don't echo the path back, just show the version. }
  Assert.AreEqual('Version: 6.1',
    FFmpegInfoLabelText(fpsValid, 'C:\ff\ffmpeg.exe', '6.1', False));
end;

procedure TTestSettingsDlgLogic.FFmpegInfo_ValidEmptyInput_IncludesPathAndVersion;
begin
  Assert.AreEqual('Detected: C:\ff\ffmpeg.exe (6.1.1)',
    FFmpegInfoLabelText(fpsValid, 'C:\ff\ffmpeg.exe', '6.1.1', True));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsDlgLogic);

end.
