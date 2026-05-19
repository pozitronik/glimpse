library Glimpse;

{$IFDEF WIN64}
{$E wcx64}
{$ELSE}
{$E wcx}
{$ENDIF}

uses
  Winapi.Windows,
  Types in '..\src\domain\Types.pas',
  StatusBarLayout in '..\src\domain\StatusBar\StatusBarLayout.pas',
  WcxAPI in 'Core\WcxAPI.pas',
  WcxExports in 'Core\WcxExports.pas',
  WcxSettings in 'Settings\WcxSettings.pas',
  WcxSettingsDlg in 'Forms\WcxSettingsDlg.pas',
  FrameOffsets in '..\src\domain\Frame\FrameOffsets.pas',
  FFmpegLocator in '..\src\domain\Frame\FFmpegLocator.pas',
  FFmpegExe in '..\src\infrastructure\FFmpegExe.pas',
  Logging in '..\src\shared\Logging.pas',
  CacheStorage in '..\src\infrastructure\CacheStorage.pas',
  LruEvictionPolicy in '..\src\infrastructure\LruEvictionPolicy.pas',
  Cache in '..\src\domain\Cache\Cache.pas',
  CacheKey in '..\src\domain\Cache\CacheKey.pas',
  ProbeCache in '..\src\domain\Cache\ProbeCache.pas',
  FrameFileNames in '..\src\domain\Frame\FrameFileNames.pas',
  BitmapSaver in '..\src\domain\Render\BitmapSaver.pas',
  ExtractionPlanner in '..\src\domain\Frame\ExtractionPlanner.pas',
  BitmapResize in '..\src\domain\Render\BitmapResize.pas',
  PathExpand in '..\src\shared\PathExpand.pas',
  ColorConv in '..\src\domain\Render\ColorConv.pas',
  ProcessRunner in '..\src\infrastructure\ProcessRunner.pas',
  Defaults in '..\src\domain\Settings\Defaults.pas',
  FrameExtractor in '..\src\domain\Frame\FrameExtractor.pas',
  BannerInfo in '..\src\domain\Render\BannerInfo.pas',
  BannerPainter in '..\src\domain\Render\BannerPainter.pas',
  CombinedGrid in '..\src\domain\Render\CombinedGrid.pas',
  TimecodeOverlay in '..\src\domain\Render\TimecodeOverlay.pas',
  RenderDefaults in '..\src\domain\Render\RenderDefaults.pas',
  PluginMessages in '..\src\shared\PluginMessages.pas',
  VideoProbing in '..\src\domain\Video\VideoProbing.pas',
  WcxFrameCache in 'Services\WcxFrameCache.pas',
  PresetExtractReporter in 'Services\PresetExtractReporter.pas',
  WcxProgressCallback in 'Services\WcxProgressCallback.pas',
  VideoInfo in '..\src\domain\Video\VideoInfo.pas',
  LineSplitter in '..\src\infrastructure\LineSplitter.pas',
  FFmpegProbeParser in '..\src\infrastructure\FFmpegProbeParser.pas',
  FFmpegCmdLine in '..\src\infrastructure\FFmpegCmdLine.pas',
  IniEncoding in '..\src\infrastructure\IniEncoding.pas',
  IniDocument in '..\src\infrastructure\IniDocument.pas',
  SettingsInterfaces in '..\src\domain\Settings\SettingsInterfaces.pas',
  Settings in '..\src\domain\Settings\Settings.pas',
  SettingsDlgLogic in '..\src\application\SettingsDlgLogic.pas',
  SettingsDlgUI in '..\src\application\SettingsDlgUI.pas',
  CmdLineTokens in 'Util\CmdLineTokens.pas',
  WcxPresetValidation in 'Entries\WcxPresetValidation.pas',
  WcxPresetTemplate in 'Entries\WcxPresetTemplate.pas',
  FileNameDedupe in 'Util\FileNameDedupe.pas',
  WcxPresets in 'Entries\WcxPresets.pas',
  WcxEntryExtractors in 'Entries\WcxEntryExtractors.pas',
  WcxArchiveHandle in 'Core\WcxArchiveHandle.pas',
  WcxListing in 'Services\WcxListing.pas',
  WcxProgressBridge in 'Services\WcxProgressBridge.pas',
  WcxPresetExtractor in 'Entries\WcxPresetExtractor.pas',
  WcxErrorMapping in 'Util\WcxErrorMapping.pas',
  WcxExtractionController in 'Services\WcxExtractionController.pas',
  WcxArchiveCoordinator in 'Core\WcxArchiveCoordinator.pas',
  SettingsSaveOrchestrator in 'Services\SettingsSaveOrchestrator.pas',
  WcxSettingsRepository in 'Settings\WcxSettingsRepository.pas',
  WcxPresetsRepository in 'Entries\WcxPresetsRepository.pas',
  WcxSettingsControlsBundles in 'Presenters\WcxSettingsControlsBundles.pas',
  SettingsDialogHelpers in '..\src\application\SettingsDialogHelpers.pas',
  WcxSettingsPresenters in 'Presenters\WcxSettingsPresenters.pas',
  NoShadowHints in '..\src\shared\NoShadowHints.pas';

exports
  OpenArchive,
  OpenArchiveW,
  ReadHeader,
  ReadHeaderExW,
  ProcessFile,
  ProcessFileW,
  CloseArchive,
  SetChangeVolProc,
  SetChangeVolProcW,
  SetProcessDataProc,
  SetProcessDataProcW,
  GetPackerCaps,
  SetDefaultParams,
  PackFiles,
  ConfigurePacker;

begin
  {Surface forgotten Free calls as a Delphi-builtin leak dialog when TC unloads
   the DLL. Debug-only: the report runs at finalization and would be noise for
   end users in release builds.}
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
end.
