{Persists visibility toggles to TPluginSettings. Collapses set+save into
 one atomic call so form handlers stay focused on UI state.}
unit SettingsToggleService;

interface

uses
  Settings;

type
  TSettingsToggleService = class
  strict private
    FSettings: TPluginSettings;
  public
    constructor Create(ASettings: TPluginSettings);
    procedure PersistToolbarVisible(AValue: Boolean);
    procedure PersistStatusBarVisible(AValue: Boolean);
    procedure PersistTimecodeVisible(AValue: Boolean);
  end;

implementation

constructor TSettingsToggleService.Create(ASettings: TPluginSettings);
begin
  inherited Create;
  FSettings := ASettings;
end;

procedure TSettingsToggleService.PersistToolbarVisible(AValue: Boolean);
begin
  FSettings.ShowToolbar := AValue;
  FSettings.Save;
end;

procedure TSettingsToggleService.PersistStatusBarVisible(AValue: Boolean);
begin
  FSettings.ShowStatusBar := AValue;
  FSettings.Save;
end;

procedure TSettingsToggleService.PersistTimecodeVisible(AValue: Boolean);
begin
  FSettings.ShowTimecode := AValue;
  FSettings.Save;
end;

end.
