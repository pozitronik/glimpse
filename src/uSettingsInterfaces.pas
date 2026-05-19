{Per-concern narrow interface seams on TPluginSettings so collaborators
 can hold typed refs to just the slice they need rather than the whole
 settings god-object.}
unit uSettingsInterfaces;

interface

uses
  System.UITypes,
  uTypes, uBitmapSaver, uSettingsGroups;

type
  ITimecodeStyleProvider = interface
    ['{A4D1F2C3-3E5B-4A8A-9F1B-2E7C5B9D7A12}']
    function GetTimestamp: TTimestampSettingsGroup;
  end;

  IBannerStyleProvider = interface
    ['{B2C3D4E5-5F7C-4B9B-A2D5-3F8C6BAE8B23}']
    function GetBanner: TBannerSettingsGroup;
    function GetShowBanner: Boolean;
  end;

  ISaveFormatPolicy = interface
    ['{C3D4E5F6-6A8D-4CAC-B3E6-4A9D7CBF9C34}']
    function GetSaveFormat: TSaveFormat;
    function GetSaveFolder: string;
    procedure SetSaveFolder(const AValue: string);
    function GetSaveAtLiveResolution: Boolean;
    procedure SetSaveAtLiveResolution(AValue: Boolean);
    function GetCopyAtLiveResolution: Boolean;
    function GetCombinedMaxSide: Integer;
    {Commits in-memory settings to the backing INI; called by
     TSaveDialogPresenter to persist the dialog's folder + live-resolution
     choice across sessions.}
    procedure Save;
  end;

  IRenderColorPolicy = interface
    ['{D4E5F6A7-7B9E-4DBD-C4F7-5BAE8DCFAD45}']
    function GetBackground: TColor;
    function GetBackgroundAlpha: Byte;
    function GetCellGap: Integer;
    function GetCombinedBorder: Integer;
  end;

  IClipboardPolicy = interface
    ['{E5F6A7B8-8CAF-4ECE-D508-6CBF9EDABE56}']
    function GetClipboardFormats: TClipboardFormatsGroup;
    function GetClipboardAsFileReference: Boolean;
    {Also exposed via ISaveFormatPolicy. One underlying field driving
     two consumer concerns (file-save + in-memory CF_PNG) is not
     duplication; each interface exposes what its consumer needs.}
    function GetPngCompression: Integer;
  end;

implementation

end.
