{Per-archive-open state for the WCX plugin. Implements
 IWcxExtractionContext so entry extractors see a read-only facet.
 TNoRefCountObject-based because TC's WCX API owns the handle lifecycle
 (created in OpenArchive, freed in CloseArchive).}
unit WcxArchiveHandle;

interface

uses
  Winapi.Windows,
  System.Classes,
  WcxAPI,
  WcxSettings,
  WcxPresets,
  FrameExtractor,
  FrameOffsets,
  VideoInfo,
  WcxEntryExtractors,
  PresetExtractReporter;

type
  TArchiveHandle = class(TNoRefCountObject, IWcxExtractionContext)
  public
    {Per-archive immutable state. Set once at OpenArchive.}
    FileName: string;
    Settings: TWcxSettings;
    FFmpegPath: string;
    VideoInfo: TVideoInfo;
    Offsets: TFrameOffsetArray;
    OpenMode: Integer;
    FileTime: Integer;
    {Populated from module-level cache when ShowFileSizes is enabled.}
    TempPaths: TArray<string>;
    EntrySizes: TArray<Int64>;
    {Loaded once at OpenArchive when ShowPresets is on; empty otherwise.
     Indexed by TPresetEntry.PresetIndex.}
    Presets: TWcxPresetArray;
    Listing: TWcxEntryExtractorArray;
    {Either or both may be nil; ProcessFile then runs without surfacing
     progress. Wide variant preferred when set; ANSI is the legacy
     fallback for older TC builds.}
    ProcessDataProc: TProcessDataProc;
    ProcessDataProcW: TProcessDataProcW;
    {Reported as the synthetic UnpSize for preset entries — output size
     is not predictable, but the source size keeps TC's listing column
     believable and gives the progress bridge a meaningful denominator.}
    SourceFileSize: Int64;
    {Allocated once at OpenArchive so dependents share one instance per
     archive. Interface-typed so lifetime is automatic.}
    FrameExtractor: IFrameExtractor;
    BitmapSaver: IBitmapSaverRouter;
    FailureReporter: IPresetExtractFailureReporter;

  strict private
    {Strict-private to force all access through AdvanceCursor /
     IsExhausted / CurrentEntry / ResetCursor — the "one cursor, one
     valid range" invariant lives in those methods, not at the
     call sites.}
    FCurrentIndex: Integer;

  public
    constructor Create;

    function EntryCount: Integer;

    function IsExhausted: Boolean;

    {Caller must check IsExhausted first; does not guard.}
    function CurrentEntry: IWcxEntryExtractor;

    function CurrentEntryIndex: Integer;

    {Idempotent at the exhaustion boundary: cursor may advance one past
     the last valid index, after which IsExhausted reports True.}
    procedure AdvanceCursor;

    procedure ResetCursor;

    function GetFileName: string;
    function GetFFmpegPath: string;
    function GetSourceFileSize: Int64;
    function GetSettings: TWcxSettings;
    function GetOffsets: TFrameOffsetArray;
    function GetPresets: TWcxPresetArray;
    function GetVideoInfo: TVideoInfo;
    function GetTempPaths: TArray<string>;
    function GetEntrySizes: TArray<Int64>;
    function GetProcessDataProc: TProcessDataProc;
    function GetProcessDataProcW: TProcessDataProcW;
    function GetFrameExtractor: IFrameExtractor;
    function GetBitmapSaver: IBitmapSaverRouter;
    function GetFailureReporter: IPresetExtractFailureReporter;
  end;

implementation

{ TArchiveHandle }

constructor TArchiveHandle.Create;
begin
  inherited;
  FCurrentIndex := 0;
end;

function TArchiveHandle.EntryCount: Integer;
begin
  Result := Length(Listing);
end;

function TArchiveHandle.IsExhausted: Boolean;
begin
  Result := FCurrentIndex >= EntryCount;
end;

function TArchiveHandle.CurrentEntry: IWcxEntryExtractor;
begin
  Result := Listing[FCurrentIndex];
end;

function TArchiveHandle.CurrentEntryIndex: Integer;
begin
  Result := FCurrentIndex;
end;

procedure TArchiveHandle.AdvanceCursor;
begin
  Inc(FCurrentIndex);
end;

procedure TArchiveHandle.ResetCursor;
begin
  FCurrentIndex := 0;
end;

{ IWcxExtractionContext getters: trivial field forwarders. Delphi
  interface property accessors must be functions, not direct fields. }

function TArchiveHandle.GetFileName: string;
begin
  Result := FileName;
end;

function TArchiveHandle.GetFFmpegPath: string;
begin
  Result := FFmpegPath;
end;

function TArchiveHandle.GetSourceFileSize: Int64;
begin
  Result := SourceFileSize;
end;

function TArchiveHandle.GetSettings: TWcxSettings;
begin
  Result := Settings;
end;

function TArchiveHandle.GetOffsets: TFrameOffsetArray;
begin
  Result := Offsets;
end;

function TArchiveHandle.GetPresets: TWcxPresetArray;
begin
  Result := Presets;
end;

function TArchiveHandle.GetVideoInfo: TVideoInfo;
begin
  Result := VideoInfo;
end;

function TArchiveHandle.GetTempPaths: TArray<string>;
begin
  Result := TempPaths;
end;

function TArchiveHandle.GetEntrySizes: TArray<Int64>;
begin
  Result := EntrySizes;
end;

function TArchiveHandle.GetProcessDataProc: TProcessDataProc;
begin
  Result := ProcessDataProc;
end;

function TArchiveHandle.GetProcessDataProcW: TProcessDataProcW;
begin
  Result := ProcessDataProcW;
end;

function TArchiveHandle.GetFrameExtractor: IFrameExtractor;
begin
  Result := FrameExtractor;
end;

function TArchiveHandle.GetBitmapSaver: IBitmapSaverRouter;
begin
  Result := BitmapSaver;
end;

function TArchiveHandle.GetFailureReporter: IPresetExtractFailureReporter;
begin
  Result := FailureReporter;
end;

end.
