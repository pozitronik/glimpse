{Per-concern narrow interface seams on TPluginSettings.

 Step 109 (N3, ISP): the various render / clipboard / save-dialog
 collaborators historically held a `TPluginSettings` reference and
 reached into ~10 unrelated properties on it. The collaborator's
 dependency was on the whole settings god-object, even when the
 collaborator only needed three fields. Tests had to construct a full
 TPluginSettings (cheap in practice — Create('') skips Load — but the
 dependency shape mis-signalled "this code depends on every setting").

 Five narrow interfaces here decompose TPluginSettings's surface by
 concern domain. TPluginSettings implements all five via TNoRefCountObject
 (no automatic refcounting — the WLX form owns the instance's lifetime
 manually). Collaborators take typed interface references at construction;
 tests can stand up tiny per-interface fakes when needed.

 Concern boundaries:

   ITimecodeStyleProvider  Timestamp overlay style (Timestamp group).
                           Used by TFrameRenderPipeline (renders the
                           overlay), TFrameDimensionPredictor (no — only
                           layout fields, but the predictor today reads
                           via the render pipeline).

   IBannerStyleProvider    Info-banner style + show toggle. Used by
                           TFrameRenderPipeline (renders the banner).

   ISaveFormatPolicy       Bitmap-output knobs + live-resolution policy +
                           Save() commit. Used by TSaveDialogPresenter
                           (reads+writes), TFrameDimensionPredictor and
                           TFrameRenderPipeline (read CombinedMaxSide +
                           SaveAtLiveResolution).

   IRenderColorPolicy      Grid + background appearance knobs (color,
                           alpha, cell gap, border). Used by
                           TFrameRenderPipeline (renders) and
                           TFrameDimensionPredictor (layout math).

   IClipboardPolicy        Clipboard publish behavior (format strategies,
                           file-reference override, PNG compression for
                           the in-memory PNG path). Used by
                           TClipboardPublisher.

 PngCompression appears on both ISaveFormatPolicy and IClipboardPolicy
 — the same underlying field, two consumer concerns. Not duplication;
 separate interfaces deliberately expose what each consumer needs from
 what is, on the model side, one shared setting.

 ISaveFormatPolicy.Save is included even though "Save the INI file"
 is a different concern from "save knobs" because TSaveDialogPresenter
 needs to commit its dialog edits at OK time. Keeping it on the same
 interface avoids a second tiny ISaveCommit just for one call site.}
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
    {Commits the in-memory settings to the backing INI. Called by
     TSaveDialogPresenter after it captures a folder + live-resolution
     choice the user wants persisted across sessions.}
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
    {Returned by both ISaveFormatPolicy and IClipboardPolicy because the
     PNG-compression setting drives both file-save and in-memory CF_PNG
     allocation. The model has one field; the consumers see it through
     their own interface boundary.}
    function GetPngCompression: Integer;
  end;

implementation

end.
