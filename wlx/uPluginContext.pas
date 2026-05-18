{Singleton container for the WLX plugin's process-wide state.

 The five fields (Settings, PluginDir, FFmpegPath, ThumbnailCache,
 ProbeCache) used to live as module-level globals in uPluginExports.
 That made the exports unit both an ABI surface and a service
 container — tests / alternative hosts could not construct one without
 the other. With the singleton:
 - Production: TC calls ListSetDefaultParams once per session, which
 populates Instance via the setters.
 - Tests: instantiate TPluginContext directly, drive DoListLoad-like
 paths against the instance, then call ReleaseInstance to clean up.

 Settings is created eagerly in the constructor so any path that runs
 before ListSetDefaultParams (e.g. DoListLoad coming in early on some
 TC startups) still sees a usable defaults snapshot rather than nil.

 The two setters (Settings, ProbeCache) free the previous instance
 atomically — matches the historical "GSettings.Free; GSettings := New"
 pattern from the module globals.}
unit uPluginContext;

interface

uses
  uSettings, uCache, uProbeCache;

type
  TPluginContext = class
  strict private
    class var FInstance: TPluginContext;
  strict private
    FSettings: TPluginSettings;
    FPluginDir: string;
    FFFmpegPath: string;
    FThumbnailCache: IFrameCache;
    FProbeCache: TProbeCache;
    procedure SetSettings(AValue: TPluginSettings);
    procedure SetProbeCache(AValue: TProbeCache);
  public
    constructor Create;
    destructor Destroy; override;
    {Lazy singleton accessor — creates Instance on first call with an
     empty defaults Settings snapshot. The matching teardown is the
     class procedure ReleaseInstance.}
    class function Instance: TPluginContext;
    {Frees the singleton (idempotent). Called from the host's finalization
     section in production; tests call it in TearDown.}
    class procedure ReleaseInstance;
    {Settings setter frees the previous instance before storing the new
     one so the historical "replace wholesale" pattern from ListSetDefaultParams
     stays a single assignment at the call site.}
    property Settings: TPluginSettings read FSettings write SetSettings;
    property PluginDir: string read FPluginDir write FPluginDir;
    property FFmpegPath: string read FFFmpegPath write FFFmpegPath;
    {ThumbnailCache is an interface — assignment refcounts and the old
     instance is released automatically.}
    property ThumbnailCache: IFrameCache read FThumbnailCache write FThumbnailCache;
    {ProbeCache setter frees the previous instance like Settings.}
    property ProbeCache: TProbeCache read FProbeCache write SetProbeCache;
  end;

implementation

uses
  System.SysUtils;

constructor TPluginContext.Create;
begin
  inherited;
  FSettings := TPluginSettings.Create('');
end;

destructor TPluginContext.Destroy;
begin
  FThumbnailCache := nil;
  FreeAndNil(FProbeCache);
  FreeAndNil(FSettings);
  inherited;
end;

class function TPluginContext.Instance: TPluginContext;
begin
  if FInstance = nil then
    FInstance := TPluginContext.Create;
  Result := FInstance;
end;

class procedure TPluginContext.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

procedure TPluginContext.SetSettings(AValue: TPluginSettings);
begin
  if FSettings = AValue then
    Exit;
  FSettings.Free;
  FSettings := AValue;
end;

procedure TPluginContext.SetProbeCache(AValue: TProbeCache);
begin
  if FProbeCache = AValue then
    Exit;
  FProbeCache.Free;
  FProbeCache := AValue;
end;

end.
