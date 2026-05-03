program GlimpseTests;

{$STRONGLINKTYPES ON}
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  uTypes in '..\src\uTypes.pas',
  uDefaults in '..\src\uDefaults.pas',
  uSettingsGroups in '..\src\uSettingsGroups.pas',
  uSettings in '..\src\uSettings.pas',
  uFrameOffsets in '..\src\uFrameOffsets.pas',
  uFFmpegLocator in '..\src\uFFmpegLocator.pas',
  uFFmpegExe in '..\src\uFFmpegExe.pas',
  TestFFmpegLocator in 'TestFFmpegLocator.pas',
  TestSettings in 'TestSettings.pas',
  uHotkeys in '..\src\uHotkeys.pas',
  TestHotkeys in 'TestHotkeys.pas',
  uCaptureShortcutDlg in '..\wlx\uCaptureShortcutDlg.pas',
  TestFrameOffsets in 'TestFrameOffsets.pas',
  TestFFmpegExe in 'TestFFmpegExe.pas',
  uFrameView in '..\wlx\uFrameView.pas',
  uExtractionWorker in '..\src\uExtractionWorker.pas',
  uPluginForm in '..\wlx\uPluginForm.pas',
  TestFrameView in 'TestFrameView.pas',
  uDebugLog in '..\src\uDebugLog.pas',
  uCache in '..\src\uCache.pas',
  uCacheKey in '..\src\uCacheKey.pas',
  TestCacheKey in 'TestCacheKey.pas',
  TestCache in 'TestCache.pas',
  uFrameFileNames in '..\src\uFrameFileNames.pas',
  TestFrameFileNames in 'TestFrameFileNames.pas',
  uBitmapSaver in '..\src\uBitmapSaver.pas',
  TestBitmapSaver in 'TestBitmapSaver.pas',
  uClipboardImage in '..\src\uClipboardImage.pas',
  TestClipboardImage in 'TestClipboardImage.pas',
  uZoomController in '..\wlx\uZoomController.pas',
  TestZoomController in 'TestZoomController.pas',
  uViewModeLogic in '..\wlx\uViewModeLogic.pas',
  TestViewModeLogic in 'TestViewModeLogic.pas',
  uExtractionPlanner in '..\src\uExtractionPlanner.pas',
  TestExtractionPlanner in 'TestExtractionPlanner.pas',
  uToolbarLayout in '..\wlx\uToolbarLayout.pas',
  TestToolbarLayout in 'TestToolbarLayout.pas',
  uFileNavigator in '..\src\uFileNavigator.pas',
  TestFileNavigator in 'TestFileNavigator.pas',
  TestDebugLog in 'TestDebugLog.pas',
  uPathExpand in '..\src\uPathExpand.pas',
  TestPathExpand in 'TestPathExpand.pas',
  TestTypes in 'TestTypes.pas',
  uColorConv in '..\src\uColorConv.pas',
  TestColorConv in 'TestColorConv.pas',
  uRunProcess in '..\src\uRunProcess.pas',
  TestRunProcess in 'TestRunProcess.pas',
  uFrameExtractor in '..\src\uFrameExtractor.pas',
  TestFrameExtractor in 'TestFrameExtractor.pas',
  TestExtractionWorker in 'TestExtractionWorker.pas',
  uViewModeLayout in '..\wlx\uViewModeLayout.pas',
  TestViewModeLayout in 'TestViewModeLayout.pas',
  uFrameExport in '..\wlx\uFrameExport.pas',
  TestFrameExport in 'TestFrameExport.pas',
  uExtractionController in '..\wlx\uExtractionController.pas',
  TestExtractionController in 'TestExtractionController.pas',
  uSaveResolutionExtractor in '..\wlx\uSaveResolutionExtractor.pas',
  TestSaveResolutionExtractor in 'TestSaveResolutionExtractor.pas',
  uWcxAPI in '..\wcx\uWcxAPI.pas',
  uWcxSettings in '..\wcx\uWcxSettings.pas',
  TestWcxSettings in 'TestWcxSettings.pas',
  TestWcxAPI in 'TestWcxAPI.pas',
  uCombinedImage in '..\src\uCombinedImage.pas',
  TestCombinedImage in 'TestCombinedImage.pas',
  uProbeCache in '..\src\uProbeCache.pas',
  TestProbeCache in 'TestProbeCache.pas',
  uBitmapResize in '..\src\uBitmapResize.pas',
  TestBitmapResize in 'TestBitmapResize.pas',
  uThumbnailRender in '..\src\uThumbnailRender.pas',
  TestThumbnailRender in 'TestThumbnailRender.pas',
  uSettingsDlgLogic in '..\src\uSettingsDlgLogic.pas',
  uSettingsDlgUI in '..\src\uSettingsDlgUI.pas',
  TestSettingsDlgUI in 'TestSettingsDlgUI.pas',
  TestSettingsDlgLogic in 'TestSettingsDlgLogic.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    if TDUnitX.Options.XMLOutputFile <> '' then
    begin
      NUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
      Runner.AddLogger(NUnitLogger);
    end;
    Runner.FailsOnNoAsserts := False;
    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
end.
