{Toggle-persistence service for visibility toggles in TPluginSettings.

 The form's hotkey/click handlers (DoToggleToolbar, DoToggleStatusBar,
 OnTimecodeButtonClick) used to do "FSettings.ShowX := Y; FSettings.Save"
 inline — mixing the VCL visibility flip with persistence. The service
 collapses the set+save pair into one atomic call so the form handlers
 stay focused on UI state and side effects live behind a named service
 boundary.

 Quick-view mode (paToggleToolbar / paToggleStatusBar): the handler
 still checks FQuickViewMode and skips persistence; the service has
 no quick-view awareness because the policy is "should we persist?"
 not "what to persist".}
unit uSettingsToggleService;

interface

uses
  uSettings;

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
