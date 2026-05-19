{Dependency-injection container for TPluginForm's collaborators.

 The form's InitializeExtractionStack / StartExtraction / WithReExtract
 used to instantiate concrete TFrameCache / TFFmpegFrameExtractor /
 TProbeCache classes directly - a DIP / Low Coupling violation that
 made the form hard to test in isolation. The factory interfaces here
 let DoListLoad wire production factories at startup while tests
 inject fakes that record calls without actually launching ffmpeg or
 touching the disk cache.

 ProbeCache stays a concrete TProbeCache (not factoried) because there
 is exactly one per plugin instance and its construction is trivial
 (one constructor arg). The form takes ownership of the passed instance
 and frees it in its destructor - DoListLoad constructs it just before
 passing the services and never holds a separate reference.}
unit uPluginServices;

interface

uses
  uCache, uFrameExtractor, uProbeCache, uSettings;

type
  {Builds an IFrameCache wired to the user's settings (CacheEnabled
   selects between TFrameCache on disk and TNullFrameCache). One factory
   instance can produce many caches; the production impl is stateless.}
  IFrameCacheFactory = interface
    ['{A1B2C3D4-1111-2222-3333-444455556666}']
    function CreateCache(const ASettings: TPluginSettings): IFrameCache;
  end;

  {Builds an IFrameExtractor wrapping ffmpeg at AFFmpegPath. Stateless
   factory; can be called many times from worker threads (StartExtraction
   + WithReExtract both produce fresh extractors per call).}
  IFrameExtractorFactory = interface
    ['{A1B2C3D4-7777-8888-9999-AAAABBBBCCCC}']
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

  {DI container the form receives. ProbeCache is a concrete instance
   passed-in (form takes ownership; frees in destructor). Factories are
   refcount-managed interface fields - the record's implicit copy
   semantics correctly bump/drop the refcount, so passing TPluginServices
   by value is safe.}
  TPluginServices = record
    FrameCacheFactory: IFrameCacheFactory;
    FrameExtractorFactory: IFrameExtractorFactory;
    ProbeCache: TProbeCache;
  end;

  {Production factory: returns a TFrameCache when CacheEnabled, else a
   TNullFrameCache. The CacheEnabled branch was previously inline in
   TPluginForm.InitializeExtractionStack.}
  TProductionFrameCacheFactory = class(TInterfacedObject, IFrameCacheFactory)
  public
    function CreateCache(const ASettings: TPluginSettings): IFrameCache;
  end;

  {Production factory: returns a fresh TFFmpegFrameExtractor per call.}
  TProductionFrameExtractorFactory = class(TInterfacedObject, IFrameExtractorFactory)
  public
    function CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
  end;

{Convenience constructor: builds a TPluginServices with production
 factories + a freshly-allocated TProbeCache. Used by DoListLoad; tests
 build the record field-by-field with fake factories.}
function CreateProductionServices: TPluginServices;

implementation

{TProductionFrameCacheFactory}

function TProductionFrameCacheFactory.CreateCache(const ASettings: TPluginSettings): IFrameCache;
begin
  if ASettings.CacheEnabled then
    Result := TFrameCache.Create(EffectiveCacheFolder(ASettings.CacheFolder), ASettings.CacheMaxSizeMB)
  else
    Result := TNullFrameCache.Create;
end;

{TProductionFrameExtractorFactory}

function TProductionFrameExtractorFactory.CreateExtractor(const AFFmpegPath: string): IFrameExtractor;
begin
  Result := TFFmpegFrameExtractor.Create(AFFmpegPath);
end;

function CreateProductionServices: TPluginServices;
begin
  Result.FrameCacheFactory := TProductionFrameCacheFactory.Create;
  Result.FrameExtractorFactory := TProductionFrameExtractorFactory.Create;
  Result.ProbeCache := TProbeCache.Create(DefaultProbeCacheDir);
end;

end.
