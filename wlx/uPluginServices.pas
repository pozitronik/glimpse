{Dependency-injection container for TPluginForm's collaborators. Production
 wires factories via CreateProductionServices; tests build the record by
 hand with fakes.}
unit uPluginServices;

interface

uses
  uCache, uFrameExtractor, uProbeCache, uSettings;

type
  IFrameCacheFactory = interface
    ['{A1B2C3D4-1111-2222-3333-444455556666}']
    function CreateCache(const ASettings: TPluginSettings): IFrameCache;
  end;

  {Form takes ownership of ProbeCache and frees it in its destructor.
   Factories are refcount-managed; record copy semantics handle the refcounts.}
  TPluginServices = record
    FrameCacheFactory: IFrameCacheFactory;
    FrameExtractorFactory: IFrameExtractorFactory;
    ProbeCache: TProbeCache;
  end;

  TProductionFrameCacheFactory = class(TInterfacedObject, IFrameCacheFactory)
  public
    function CreateCache(const ASettings: TPluginSettings): IFrameCache;
  end;

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

function CreateProductionServices: TPluginServices;
begin
  Result.FrameCacheFactory := TProductionFrameCacheFactory.Create;
  Result.FrameExtractorFactory := TProductionFrameExtractorFactory.Create;
  Result.ProbeCache := TProbeCache.Create(DefaultProbeCacheDir);
end;

end.
