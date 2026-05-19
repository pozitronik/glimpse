{Singleton container for the WLX plugin's process-wide state. Settings is
 created eagerly in the constructor so any path running before
 ListSetDefaultParams still sees a usable defaults snapshot.}
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
    {Lazy accessor — creates Instance with an empty defaults Settings on first call.}
    class function Instance: TPluginContext;
    {Idempotent. Called from host finalization in production; tests call it in TearDown.}
    class procedure ReleaseInstance;
    {Setter frees the previous instance so callers can assign wholesale.}
    property Settings: TPluginSettings read FSettings write SetSettings;
    property PluginDir: string read FPluginDir write FPluginDir;
    property FFmpegPath: string read FFFmpegPath write FFFmpegPath;
    property ThumbnailCache: IFrameCache read FThumbnailCache write FThumbnailCache;
    {Setter frees the previous instance like Settings.}
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
