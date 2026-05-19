{TArchiveHandle: per-archive-open state for the WCX plugin.

 Promoted from a 17-field public-record struct in uWcxExports's
 implementation into a real class with behaviour. Cursor management
 (CurrentIndex + advance + exhaustion check) used to be scattered as
 inline `Inc(H.CurrentIndex)` / `H.CurrentIndex >= GetEntryCount(H)`
 reads across every uWcxExports routine; lifting the cursor into named
 methods (AdvanceCursor / IsExhausted / CurrentEntry / ResetCursor)
 enforces the "one cursor, one valid range" invariant inside the
 class instead of trusting every caller.

 Implements IWcxExtractionContext (from uWcxEntryExtractors) so entry
 extractors get a clean read-only facet of the per-open-session state.
 Stays TNoRefCountObject-based: TC's WCX API owns the handle lifecycle
 (created in OpenArchive, freed in CloseArchive); the interface
 implementation is just a passthrough seam for tests.

 Field privacy is intentionally deferred for this step. The collaborator
 fields (FileName, Settings, etc.) stay public so uWcxExports's existing
 setup code in DoOpenArchive can keep writing them as plain assignments;
 a follow-up step can promote them to strict-private once a constructor
 / setter surface is designed. The behavioural cursor methods below are
 the only intended access path for the iteration state — FCurrentIndex
 is already strict-private to enforce that boundary today.}
unit uWcxArchiveHandle;

interface

uses
  Winapi.Windows,
  System.Classes,
  uWcxAPI,
  uWcxSettings,
  uWcxPresets,
  uFrameExtractor,
  uFrameOffsets,
  uVideoInfo,
  uWcxEntryExtractors;

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
    {Populated from module-level cache when ShowFileSizes is enabled}
    TempPaths: TArray<string>;
    EntrySizes: TArray<Int64>;
    {Loaded once at OpenArchive when ShowPresets is on; empty otherwise.
     Indexed by TPresetEntry.PresetIndex.}
    Presets: TWcxPresetArray;
    {Pre-built polymorphic listing. ReadHeaderExW iterates this;
     ProcessFile dispatches via Entry.Extract — no Kind switch.}
    Listing: TWcxEntryExtractorArray;
    {TC's progress callbacks. The Wide variant is preferred when set;
     legacy TC builds fall back to the ANSI variant. Either or both may
     be nil — ProcessFile then runs without surfacing progress.}
    ProcessDataProc: TProcessDataProc;
    ProcessDataProcW: TProcessDataProcW;
    {Source video size in bytes. Reported as the synthetic UnpSize for
     preset entries (output size is not predictable in advance, but
     using the source size keeps the listing column believable AND gives
     the progress bridge a meaningful denominator).}
    SourceFileSize: Int64;
    {Per-open-session collaborators. Allocated at OpenArchive (so
     dependents share one instance per archive rather than reconstruct
     per call), freed implicitly when the handle is freed. Frame
     extractor wraps ffmpeg; bitmap saver wraps SaveBitmapToFile. Both
     are interface-typed so the field lifetime is automatic.}
    FrameExtractor: IFrameExtractor;
    BitmapSaver: IBitmapSaverRouter;

  strict private
    {Iteration cursor for the TC-driven extract loop. Strict-private
     because the behavioural methods (AdvanceCursor / IsExhausted /
     CurrentEntry / ResetCursor) are the only intended access path —
     every uWcxExports routine used to read/write H.CurrentIndex
     directly, and that scatter is exactly what the lift to methods
     prevents going forward.}
    FCurrentIndex: Integer;

  public
    constructor Create;

    {Behavioural methods that replace the prior `H.CurrentIndex` /
     `GetEntryCount(H)` / `H.Listing[H.CurrentIndex]` patterns
     scattered across uWcxExports's routines.}

    {Number of entries TC sees in this archive. Returns Length(Listing)
     when Listing is populated, else 0. Wraps the old free function
     GetEntryCount(H) — that free function is removed.}
    function EntryCount: Integer;

    {True when the cursor has walked past the last entry. ReadHeader,
     ReadHeaderExW and ProcessFile all bail out when this is True.}
    function IsExhausted: Boolean;

    {Returns the entry under the cursor. Caller must check IsExhausted
     first (or accept an out-of-bounds access — this method does not
     guard, following the existing call-site contract where the
     exhaustion check happens before the read).}
    function CurrentEntry: IWcxEntryExtractor;

    {Position of the cursor — the same value ReadHeader/ReadHeaderExW
     pass as the AListingIndex argument to Entry.ReportedSize.}
    function CurrentEntryIndex: Integer;

    {Advances the cursor by one. Called from the PK_SKIP /
     fall-through / dispatch-failure branches in ProcessFile and the
     end-of-extract path. Idempotent at the exhaustion boundary
     (cursor can advance one past the last valid index — IsExhausted
     reports True at that point).}
    procedure AdvanceCursor;

    {Resets the cursor to the start. Called from DoOpenArchive after
     the listing is built so the first ReadHeader sees entry 0.}
    procedure ResetCursor;

    {IWcxExtractionContext implementation. Trivial field forwarders;
     methods (not direct field reads) because Delphi interface property
     accessors must be getter functions.}
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

{ IWcxExtractionContext getters: trivial field forwarders. Methods (not
  raw field access) because Delphi interface property accessors must be
  getter functions, not direct fields. }

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

end.
