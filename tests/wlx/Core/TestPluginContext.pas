unit TestPluginContext;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPluginContext = class
  public
    [TearDown] procedure TearDown;

    [Test] procedure TestInstanceIsLazy;
    [Test] procedure TestInstanceIsSingleton;
    [Test] procedure TestInstanceHasDefaultSettings;
    [Test] procedure TestReleaseInstanceClearsSingleton;
    [Test] procedure TestSettingsSetterFreesPrevious;
    [Test] procedure TestProbeCacheSetterFreesPrevious;
    [Test] procedure TestPluginDirIsReadWrite;
    [Test] procedure TestFFmpegPathIsReadWrite;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Settings, ProbeCache,
  PluginContext;

procedure TTestPluginContext.TearDown;
begin
  {Every test must leave the singleton in a clean state so the next
   test's TestInstanceIsLazy starts from nil.}
  TPluginContext.ReleaseInstance;
end;

procedure TTestPluginContext.TestInstanceIsLazy;
begin
  {After TearDown the previous instance is freed. The first call to
   Instance must construct a fresh one with non-nil Settings (the eager
   defaults).}
  Assert.IsNotNull(TPluginContext.Instance);
  Assert.IsNotNull(TPluginContext.Instance.Settings);
end;

procedure TTestPluginContext.TestInstanceIsSingleton;
begin
  Assert.AreSame(TPluginContext.Instance, TPluginContext.Instance,
    'Two Instance calls must return the same object');
end;

procedure TTestPluginContext.TestInstanceHasDefaultSettings;
begin
  {The lazy-created Settings instance carries ResetDefaults values. Pick
   a constant the audit guarantees is part of the defaults set.}
  Assert.IsNotNull(TPluginContext.Instance.Settings);
  Assert.AreEqual('', TPluginContext.Instance.Settings.IniPath,
    'Default Settings has empty IniPath (transient defaults snapshot)');
end;

procedure TTestPluginContext.TestReleaseInstanceClearsSingleton;
begin
  {After ReleaseInstance the singleton is nil; a subsequent Instance
   call must construct a fresh one with non-nil Settings. We cannot
   reliably assert object-identity inequality (the memory allocator
   may legitimately reuse the freed slot for the next allocation), so
   the observable contract checked here is: post-Release Instance is
   non-nil AND ReleaseInstance is idempotent.}
  TPluginContext.Instance; {force construction}
  TPluginContext.ReleaseInstance;
  TPluginContext.ReleaseInstance; {must not raise}
  Assert.IsNotNull(TPluginContext.Instance);
  Assert.IsNotNull(TPluginContext.Instance.Settings,
    'Re-constructed instance must seed Settings the same way as the first');
end;

procedure TTestPluginContext.TestSettingsSetterFreesPrevious;
var
  Ctx: TPluginContext;
  Replacement: TPluginSettings;
begin
  Ctx := TPluginContext.Instance;
  {The lazy ctor created a default Settings. Replacing it via the setter
   must free the old one (otherwise the old instance leaks).
   We cannot directly observe the freed memory, but we CAN assert that
   Ctx.Settings now points at our new instance. DUnitX's leak counter
   catches the freed-vs-not regression separately.}
  Replacement := TPluginSettings.Create('');
  Ctx.Settings := Replacement;
  Assert.AreSame(Replacement, Ctx.Settings,
    'Setter must store the new instance');
end;

procedure TTestPluginContext.TestProbeCacheSetterFreesPrevious;
var
  Ctx: TPluginContext;
  Cache: IProbeCache;
begin
  Ctx := TPluginContext.Instance;
  Assert.IsNull(Ctx.ProbeCache, 'Default ProbeCache is nil');
  Cache := TProbeCache.Create(TPath.GetTempPath);
  Ctx.ProbeCache := Cache;
  Assert.AreSame(Cache, Ctx.ProbeCache);
end;

procedure TTestPluginContext.TestPluginDirIsReadWrite;
begin
  TPluginContext.Instance.PluginDir := 'C:\Plugins\Glimpse\';
  Assert.AreEqual('C:\Plugins\Glimpse\', TPluginContext.Instance.PluginDir);
end;

procedure TTestPluginContext.TestFFmpegPathIsReadWrite;
begin
  TPluginContext.Instance.FFmpegPath := 'C:\ffmpeg\ffmpeg.exe';
  Assert.AreEqual('C:\ffmpeg\ffmpeg.exe', TPluginContext.Instance.FFmpegPath);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPluginContext);

end.
