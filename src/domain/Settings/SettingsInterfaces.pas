{Per-concern narrow interface seams on TPluginSettings so collaborators
 can hold typed refs to just the slice they need rather than the whole
 settings god-object.}
unit SettingsInterfaces;

interface

uses
  System.UITypes,
  Types, BitmapSaver, SettingsGroups;

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
    {Commits in-memory settings to the backing INI; called by
     TSaveDialogPresenter to persist the dialog's folder + live-resolution
     choice across sessions.}
    procedure Save;
  end;

  {Render-size cap for the combined grid image. Carved off ISaveFormatPolicy
   so render-side consumers depend only on the cap they read.}
  IRenderSizePolicy = interface
    ['{E6F0B5D8-4A8C-4D9F-B7E0-5C0F8E2D3A6B}']
    function GetCombinedMaxSide: Integer;
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
    {Clipboard tab knobs — drive the direct-publish strategies (registered
     PNG / JFIF formats) AND the file-reference temp encoder. Distinct from
     IFrameSaveSettings.GetJpegQuality / GetPngCompression which read the
     Save tab. TPluginSettings uses a method-resolution clause to satisfy
     both interfaces from the appropriate field.}
    function GetPngCompression: Integer;
    function GetJpegQuality: Integer;
    {File-reference temp-file format only; the JPEG quality / PNG
     compression it uses come from the Get*Quality / Get*Compression
     methods above.}
    function GetClipboardFileReferenceFormat: TSaveFormat;
    {Raw configured folder for file-reference temp files; empty = system
     %TEMP%. The publisher expands env vars and falls back via
     ClipboardTempResolver, so consumers get the unresolved value here.}
    function GetClipboardTempFolder: string;
  end;

  {Settings slice for the frame-save flow: encoder format, the live-resolution
   toggle for saves, and the format-specific quality knobs.}
  IFrameSaveSettings = interface
    ['{F1B6C9E7-5B9D-4E0F-A8B1-6D1E9F3E4B7C}']
    function GetSaveFormat: TSaveFormat;
    function GetSaveAtLiveResolution: Boolean;
    function GetJpegQuality: Integer;
    function GetPngCompression: Integer;
  end;

  {Settings slice for the frame-copy flow: clipboard target routing, the
   background color the flattened path needs, and copy-at-live-resolution.}
  IFrameCopySettings = interface
    ['{A2C7DAF8-6CAE-4F10-B9C2-7E2FA042F5CD}']
    function GetClipboardAsFileReference: Boolean;
    function GetBackground: TColor;
    function GetCopyAtLiveResolution: Boolean;
    {Combined-view background opacity for the file-reference PNG path; the
     copier re-renders with this alpha (independent of the Save tab's
     GetBackgroundAlpha) before writing the temp file.}
    function GetClipboardFileReferenceBackgroundAlpha: Integer;
  end;

implementation

end.
