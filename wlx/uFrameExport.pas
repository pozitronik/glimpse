{Frame export operations: save to file and copy to clipboard.
 Extracted from TPluginForm to isolate I/O from UI orchestration.}
unit uFrameExport;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics,
  uFrameView, uSettings, uBitmapSaver, uBannerInfo,
  uBitmapWorkThread, uSaveDialogPresenter, uClipboardPublisher,
  uFrameRenderPipeline, uFrameDimensionPredictor;

type
  {Callback the host injects so the save methods can request a re-extract
   at native resolution AFTER their dialog has been confirmed (instead of
   the dispatch wrapping the entire flow in a re-extract upfront, which
   blocked TC for seconds before the dialog even appeared). The host's
   implementation is expected to set/clear FOverrideFrames around AAction
   so PickSaveBitmap picks up the re-extracted bitmaps. Pass nil to skip
   the re-extract path entirely (the save then uses live cells only).}
  TReExtractAction = reference to procedure(const AIndices: TArray<Integer>; AAction: TProc);

  {Re-exports so existing call-sites and tests that imported these from
   uFrameExport keep compiling after the publisher extraction.}
  TAsyncTaskRunner = uClipboardPublisher.TAsyncTaskRunner;
  TClipboardPublishResult = uClipboardPublisher.TClipboardPublishResult;

const
  cprSuccess = uClipboardPublisher.cprSuccess;
  cprFailed = uClipboardPublisher.cprFailed;
  cprCancelled = uClipboardPublisher.cprCancelled;

{Re-exported from uClipboardPublisher; see that unit for the full
 contract. Kept here so existing tests / call-sites that resolved these
 through uFrameExport continue to compile after the extraction.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;
function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;

type
  {Facade over the four extracted concerns (render pipeline, save dialog
   presenter, clipboard publisher, dimension predictor in a later step)
   plus the selection policy. Public surface stays stable so TPluginForm
   keeps a single FExporter field for SaveFrame/SaveFrames/SaveView/
   CopyFrame/CopyView dispatch.}
  TFrameExporter = class
  strict private
    FFrameView: TFrameView;
    FSettings: TPluginSettings;
    {Owns the "Save as" file dialog presentation. Constructed in Create,
     freed in Destroy. Re-bound to FSettings so SaveFolder / SaveFormat /
     SaveAtLiveResolution round-trip through the persisted record.}
    FSaveDialog: TSaveDialogPresenter;
    {Handles the two clipboard-publish paths (file reference + in-memory
     image strategies) plus the temp-file bookkeeping the CF_HDROP path
     needs. Owns the OnAsyncTaskRun callback; the facade's same-named
     property is a thin pass-through.}
    FClipboardPublisher: TClipboardPublisher;
    {Owns the entire render tree (scale helpers, layout math, grid
     renderers, banner attachment, size cap) plus the FOverrideFrames
     array and the FBannerInfo snapshot. The facade orchestrates around
     this object but does no drawing itself.}
    FRenderPipeline: TFrameRenderPipeline;
    {Predicts the rendered combined-image dimensions ahead of time.
     Reuses the render pipeline's layout helpers so prediction and
     render cannot drift apart.}
    FDimensionPredictor: TFrameDimensionPredictor;
    function GetOnAsyncTaskRun: TAsyncTaskRunner;
    procedure SetOnAsyncTaskRun(const AValue: TAsyncTaskRunner);
  protected
    {Render helpers exposed at protected scope so a test subclass can
     exercise them directly. Implementation now delegates to
     FRenderPipeline; the wrappers exist purely to preserve the test
     surface (TTestableExporter calls them via inherited protected
     access). They remain pipeline internals; production code reaches
     them only through SaveFrame / SaveView / CopyFrame.}
    function ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    function ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
    function RenderCellAtLiveSize(AIndex: Integer): TBitmap;
    function RenderGridCombinedAtLiveResolution: TBitmap;
    function RenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
    function RenderCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
    function RenderWithBanner(ABmp: TBitmap): TBitmap;
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
  public
    constructor Create(AFrameView: TFrameView; ASettings: TPluginSettings);
    destructor Destroy; override;
    {Optional host-form hook that runs a worker thread inside a modal
     progress dialog. Wire to uProgressModalForm.RunWithProgress. Leave
     nil to fall back to synchronous, no-UI execution (tests / standalone).
     Stored on FClipboardPublisher (the only consumer); the property is a
     pass-through so call sites do not have to know that.}
    property OnAsyncTaskRun: TAsyncTaskRunner read GetOnAsyncTaskRun write SetOnAsyncTaskRun;
    {Resolves which frame to act on: prefers AContextCellIndex, falls back
     to current frame index, then 0. Returns False if no loaded frame found.}
    function ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
    {Selection-aware singular-action resolver. Picks the cell that a
     toolbar / hotkey "Save frame" or "Copy frame" should act on.
     Priority:
       1. AContextCellIndex when in range and loaded — used by the
          right-click context menu so the menu acts on the right-clicked
          cell regardless of the current selection.
       2. First selected loaded cell — covers Ctrl+click selecting a
          frame and then triggering Save/Copy via toolbar or hotkey.
          Multi-selection collapses to the first selected: the action is
          singular by design (clipboard holds one image, save dialog is
          one filename), so picking deterministically beats refusing.
       3. CurrentFrameIndex (single-view focus) when loaded.
       4. Cell 0 when loaded.
       5. -1 when nothing usable is loaded — caller must skip the action.
     Distinct from ResolveFrameIndex: that helper preserves legacy
     semantics where -1 simply normalises to CurrentFrameIndex / 0 and
     never consults the selection set. Both coexist; this one drives the
     dispatch policy for Save/Copy frame.}
    function PickActionCell(AContextCellIndex: Integer): Integer;
    {Returns the cell-index list a save / copy action will consume. Used
     by the form's WithReExtract wrapper to scope re-extraction to the
     frames the action actually reads.
     Single — one element if ResolveFrameIndex(AContextCellIndex) succeeds, empty otherwise.
     AllLoaded — every cell whose state is fcsLoaded.
     SelectedOrAll — selected loaded cells if any selection exists, else
     every loaded cell (mirrors the selection-aware semantics of SaveFrames).}
    function BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
    function BuildSaveIndicesAllLoaded: TArray<Integer>;
    function BuildSaveIndicesSelectedOrAll: TArray<Integer>;
    {Saves a single frame to a user-chosen file. Honours
     SaveAtLiveResolution: native frame size when off, on-screen cell
     size when on (letterbox in vmGrid/Filmstrip/Scroll/Single,
     crop-to-fill in vmSmartGrid).
     AReExtract is invoked after the dialog accepts iff the user chose
     native resolution; the host wraps re-extract via WithReExtract so
     the dialog appears immediately and the re-extract work runs only
     when the user has committed to the save.}
    procedure SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {Saves multiple frames as separate files. Selection-aware: when at
     least one frame is selected only those are written, otherwise every
     loaded frame is written. Per-frame resolution policy mirrors
     SaveFrame. AReExtract gates the post-dialog re-extract the same way
     SaveFrame does.}
    procedure SaveFrames(const AFileName: string; AReExtract: TReExtractAction = nil);
    {Saves a combined image of every loaded cell. AInitialLiveRes seeds
     the file dialog's "Save at view resolution" checkbox on modern
     Windows (the user can flip it before accepting); on legacy Windows,
     where the dialog has no checkbox, the seed is the authoritative
     value and is persisted as the new SaveAtLiveResolution.
     Layout per the live view mode (vmGrid: live columns, vmSmartGrid:
     smart panel-aspect rows, vmFilmstrip: one row, vmScroll: one
     column, vmSingle: degenerates to SaveFrame).
     AReExtract gates the post-dialog re-extract the same way SaveFrame
     does.}
    procedure SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Copies a single frame to the clipboard. Honours the persisted
     CopyAtLiveResolution: live = render at on-screen cell size and
     publish; native = publish the cell's native bitmap. AReExtract is
     invoked when native resolution is requested AND the live cells
     are not already at native size — so the clipboard receives true
     native pixels rather than the viewport-scaled live cell. Mirrors
     the CopyView pattern.}
    procedure CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {Copies a combined image of every loaded cell to the clipboard.
     AForceLiveRes overrides FSettings.SaveAtLiveResolution for this call
     only (no persist); set True to copy at panel pixel size, False to
     copy at native frame size. AReExtract gates the pre-copy re-extract:
     when AForceLiveRes is False and AReExtract is supplied, the host
     re-extracts at native resolution before the copy so the clipboard
     receives true native-resolution pixels rather than the
     viewport-scaled live cells.}
    procedure CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Predicts the pixel dimensions the rendered combined image would have
     for a one-shot resolution choice, before banner attachment and before
     the CombinedMaxSide cap. Mirrors the layout math in
     RenderCombinedFromCells / RenderSmartCombinedFromCells /
     RenderGridCombinedAtLiveResolution; banner height is intentionally
     omitted (it adds a small variable height that is hard to predict
     without setting up a canvas). Returns 0,0 when there are no cells.
     Used by the toolbar dropdown to label the Save view / Copy view
     variants with their predicted output size.}
    procedure PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
    {Predicts the rendered combined-image dimensions and the post-cap
     dimensions for a one-shot resolution choice. ACappedW/H equal AW/H
     when the FSettings.CombinedMaxSide cap does not apply (cap=0 or
     image already fits). Returns False when no frames are loaded yet.}
    function PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
    {Returns the bracketed dimension suffix used on the Save/Copy view
     dropdown menu items, e.g. " [1920x1080]" or
     " [19200x10800 -> 8192x4608]" when CombinedMaxSide caps the output.
     Empty string when no frames are loaded yet.}
    function FormatPredictedSize(AForceLiveRes: Boolean): string;
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
    {Caller-supplied save-resolution bitmaps. Set before invoking a save
     or copy method when SaveAtLiveResolution is off and the caller has
     re-extracted at native (or capped) resolution; clear immediately
     after. Pass an empty array (or nil) to release. Bitmaps are not
     owned by the exporter.}
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  uFrameFileNames, uTypes,
  uFrameSelectionPolicy;

type
  {Production IFrameViewQuery adapter over a TFrameView. The selection
   policy operates on this thin read-only view so its rules live in a
   VCL-free unit. Lifetime tied to the owning TFrameExporter via the
   adapter being constructed and freed per ResolveFrameIndex /
   PickActionCell call (the adapter is stateless beyond holding a
   FFrameView reference, so per-call construction is cheap).}
  TFrameViewQueryAdapter = class(TInterfacedObject, IFrameViewQuery)
  strict private
    FFrameView: TFrameView;
  public
    constructor Create(AFrameView: TFrameView);
    function CellCount: Integer;
    function CurrentFrameIndex: Integer;
    function CellIsLoaded(AIndex: Integer): Boolean;
    function CellSelected(AIndex: Integer): Boolean;
    function IsSingleView: Boolean;
  end;

{Thin pass-throughs so existing call sites that resolved these via
 uFrameExport continue to compile after the publisher extraction.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;
begin
  Result := uClipboardPublisher.RunBitmapWorkInModal(ABitmap, AStatusText,
    AWork, APostWork, ARunner, AOutcome);
end;

function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;
begin
  Result := uClipboardPublisher.BuildClipboardCopyFailureMessage(AFailedFormat,
    AIsCombinedView);
end;

{TFrameExporter}

constructor TFrameExporter.Create(AFrameView: TFrameView; ASettings: TPluginSettings);
begin
  inherited Create;
  FFrameView := AFrameView;
  FSettings := ASettings;
  FSaveDialog := TSaveDialogPresenter.Create(ASettings);
  FClipboardPublisher := TClipboardPublisher.Create(ASettings);
  FRenderPipeline := TFrameRenderPipeline.Create(AFrameView, ASettings);
  FDimensionPredictor := TFrameDimensionPredictor.Create(AFrameView, ASettings, FRenderPipeline);
end;

destructor TFrameExporter.Destroy;
begin
  FDimensionPredictor.Free;
  FRenderPipeline.Free;
  FClipboardPublisher.Free;
  FSaveDialog.Free;
  inherited Destroy;
end;

function TFrameExporter.GetOnAsyncTaskRun: TAsyncTaskRunner;
begin
  Result := FClipboardPublisher.OnAsyncTaskRun;
end;

procedure TFrameExporter.SetOnAsyncTaskRun(const AValue: TAsyncTaskRunner);
begin
  FClipboardPublisher.OnAsyncTaskRun := AValue;
end;

function TFrameExporter.ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
var
  View: IFrameViewQuery;
begin
  {Explicit local: passing TFrameViewQueryAdapter.Create(...) directly
   to a const interface parameter is a known Delphi leak gotcha — the
   compiler skips the interface-temp's AddRef/Release pair under that
   optimisation, so the adapter instance never gets freed. The local
   holds the reference for the call's duration and releases it when
   View goes out of scope.}
  View := TFrameViewQueryAdapter.Create(FFrameView);
  Result := TFrameSelectionPolicy.ResolveFrameIndex(View, AContextCellIndex, AIndex);
end;

function TFrameExporter.PickActionCell(AContextCellIndex: Integer): Integer;
var
  View: IFrameViewQuery;
begin
  View := TFrameViewQueryAdapter.Create(FFrameView);
  Result := TFrameSelectionPolicy.PickActionCell(View, AContextCellIndex);
end;

{ TFrameViewQueryAdapter }

constructor TFrameViewQueryAdapter.Create(AFrameView: TFrameView);
begin
  inherited Create;
  FFrameView := AFrameView;
end;

function TFrameViewQueryAdapter.CellCount: Integer;
begin
  Result := FFrameView.CellCount;
end;

function TFrameViewQueryAdapter.CurrentFrameIndex: Integer;
begin
  Result := FFrameView.CurrentFrameIndex;
end;

function TFrameViewQueryAdapter.CellIsLoaded(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < FFrameView.CellCount)
    and (FFrameView.CellState(AIndex) = fcsLoaded);
end;

function TFrameViewQueryAdapter.CellSelected(AIndex: Integer): Boolean;
begin
  Result := FFrameView.CellSelected(AIndex);
end;

function TFrameViewQueryAdapter.IsSingleView: Boolean;
begin
  Result := FFrameView.ViewMode = vmSingle;
end;

function TFrameExporter.BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
var
  Idx: Integer;
begin
  if ResolveFrameIndex(AContextCellIndex, Idx) then
    Result := TArray<Integer>.Create(Idx)
  else
    SetLength(Result, 0);
end;

function TFrameExporter.BuildSaveIndicesAllLoaded: TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellState(I) = fcsLoaded then
      Result := Result + [I];
end;

function TFrameExporter.BuildSaveIndicesSelectedOrAll: TArray<Integer>;
var
  I: Integer;
  SelectedOnly: Boolean;
begin
  SetLength(Result, 0);
  SelectedOnly := FFrameView.SelectedCount > 0;
  for I := 0 to FFrameView.CellCount - 1 do
    if (FFrameView.CellState(I) = fcsLoaded) and ((not SelectedOnly) or FFrameView.CellSelected(I)) then
      Result := Result + [I];
end;

{Render-tree wrappers: each forwards to FRenderPipeline. They survive
 on TFrameExporter at protected scope only because the existing
 TTestableExporter test subclass invokes them via inherited access; new
 tests should target uFrameRenderPipeline directly.}
function TFrameExporter.ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
begin
  Result := FRenderPipeline.ScaleBitmapLetterbox(ASrc, AW, AH, ABg);
end;

function TFrameExporter.ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
begin
  Result := FRenderPipeline.ScaleBitmapCropToFill(ASrc, AW, AH);
end;

function TFrameExporter.RenderCellAtLiveSize(AIndex: Integer): TBitmap;
begin
  Result := FRenderPipeline.RenderCellAtLiveSize(AIndex);
end;

function TFrameExporter.RenderGridCombinedAtLiveResolution: TBitmap;
begin
  Result := FRenderPipeline.RenderGridCombinedAtLiveResolution;
end;

function TFrameExporter.RenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
begin
  Result := FRenderPipeline.RenderSmartCombinedFromCells(ALiveResolutionIntent);
end;

function TFrameExporter.RenderCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
begin
  Result := FRenderPipeline.RenderCombinedFromCells(ALiveResolutionIntent);
end;

function TFrameExporter.RenderWithBanner(ABmp: TBitmap): TBitmap;
begin
  Result := FRenderPipeline.RenderWithBanner(ABmp);
end;

procedure TFrameExporter.SetOverrideFrames(const AFrames: TArray<TBitmap>);
begin
  FRenderPipeline.SetOverrideFrames(AFrames);
end;

procedure TFrameExporter.ClearOverrideFrames;
begin
  FRenderPipeline.ClearOverrideFrames;
end;

procedure TFrameExporter.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FRenderPipeline.UpdateBannerInfo(AInfo);
end;

{Prediction methods delegate to FDimensionPredictor.}
procedure TFrameExporter.PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
begin
  FDimensionPredictor.PredictCombinedSize(AForceLiveRes, AW, AH);
end;

function TFrameExporter.PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
begin
  Result := FDimensionPredictor.PredictDisplayedSize(AForceLiveRes, AW, AH, ACappedW, ACappedH);
end;

function TFrameExporter.FormatPredictedSize(AForceLiveRes: Boolean): string;
begin
  Result := FDimensionPredictor.FormatPredictedSize(AForceLiveRes);
end;

procedure TFrameExporter.SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
var
  I: Integer;
  Tmp: TBitmap;
  TargetPath: string;
begin
  for I := 0 to FFrameView.CellCount - 1 do
  begin
    if ASelectedOnly and not FFrameView.CellSelected(I) then
      Continue;
    if FFrameView.CellState(I) <> fcsLoaded then
      Continue;
    TargetPath := ADir + GenerateFrameFileName(AFileName, I, FFrameView.CellTimeOffset(I), AFormat);
    if FSettings.SaveAtLiveResolution then
    begin
      Tmp := RenderCellAtLiveSize(I);
      try
        uBitmapSaver.SaveBitmapToFile(Tmp, TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
      finally
        Tmp.Free;
      end;
    end
    else
      uBitmapSaver.SaveBitmapToFile(FRenderPipeline.PickSaveBitmap(I, False), TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TFrameExporter.SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction);
var
  Idx: Integer;
  Fmt: TSaveFormat;
  Path: string;
  WriteAction: TProc;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  {Dialog FIRST so the user gets immediate feedback. The seconds-long
   re-extract that may follow runs only after the user has committed to
   the save (and only when they picked native resolution); previously it
   ran upfront, freezing TC for seconds before the dialog even appeared.}
  if not FSaveDialog.Show('Save frame', GenerateFrameFileName(AFileName, Idx, FFrameView.CellTimeOffset(Idx), FSettings.SaveFormat), True, FSettings.SaveAtLiveResolution, Path, Fmt) then
    Exit;

  WriteAction := procedure
    var
      Tmp: TBitmap;
    begin
      if FSettings.SaveAtLiveResolution then
      begin
        Tmp := RenderCellAtLiveSize(Idx);
        try
          uBitmapSaver.SaveBitmapToFile(Tmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
        finally
          Tmp.Free;
        end;
      end
      else
        uBitmapSaver.SaveBitmapToFile(FRenderPipeline.PickSaveBitmap(Idx, False), Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
    end;

  {Native-resolution path may need re-extract; defer to host. Live-
   resolution path uses on-screen cells directly, no re-extract needed.}
  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
    AReExtract([Idx], WriteAction)
  else
    WriteAction;
end;

procedure TFrameExporter.SaveFrames(const AFileName: string; AReExtract: TReExtractAction);
var
  I, FirstIdx: Integer;
  Path: string;
  Fmt: TSaveFormat;
  SelectedOnly: Boolean;
  WriteAction: TProc;
  Indices: TArray<Integer>;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {Selection-aware: any selection at all means "save just those";
   otherwise every loaded frame goes out. Replaces the historical
   pair (SaveAllFrames + SaveSelectedFrames) with one action.}
  SelectedOnly := FFrameView.SelectedCount > 0;

  {Sample filename uses the first frame that will actually be written
   so the user sees a meaningful default in the dialog.}
  FirstIdx := 0;
  if SelectedOnly then
    for I := 0 to FFrameView.CellCount - 1 do
      if FFrameView.CellSelected(I) then
      begin
        FirstIdx := I;
        Break;
      end;

  {Dialog first; re-extract (if needed) only after the user accepts.
   See SaveFrame for the rationale.}
  if not FSaveDialog.Show('Save frames', GenerateFrameFileName(AFileName, FirstIdx, FFrameView.CellTimeOffset(FirstIdx), FSettings.SaveFormat), False, FSettings.SaveAtLiveResolution, Path, Fmt) then
    Exit;

  WriteAction := procedure
    begin
      SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, SelectedOnly, AFileName);
    end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
  begin
    Indices := BuildSaveIndicesSelectedOrAll;
    AReExtract(Indices, WriteAction);
  end
  else
    WriteAction;
end;

procedure TFrameExporter.SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction);
var
  Fmt: TSaveFormat;
  Path, BaseName: string;
  WriteAction: TProc;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {vmSingle's "view" is a single frame; route to SaveFrame so the user
   gets a single-frame artefact rather than a wasteful 1-cell combined.
   SaveFrame uses the persisted setting for its dialog seed; the
   distinction between "view" and "frame" loses meaning here so the
   per-call AInitialLiveRes override is intentionally not threaded
   through.}
  if FFrameView.ViewMode = vmSingle then
  begin
    SaveFrame(AFileName, FFrameView.CurrentFrameIndex, AReExtract);
    Exit;
  end;

  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  {Dialog first; the rendering + re-extract that may follow run only
   after the user accepts. See SaveFrame for the rationale.}
  if not FSaveDialog.Show('Save view', BaseName + '_view.png', True, AInitialLiveRes, Path, Fmt) then
    Exit;

  WriteAction := procedure
    var
      Bmp: TBitmap;
    begin
      {Rendering the combined image at native size for many cells can blow
       past 32-bit address space (or simply exhaust the heap). Catch the
       memory exceptions here and surface a domain-specific error so the
       user gets a hint about the cause and possible workarounds, rather
       than the host's generic OS-level message.}
      try
        Bmp := RenderWithBanner(RenderCombinedFromCells(FSettings.SaveAtLiveResolution));
        try
          FRenderPipeline.ApplyCombinedSizeCap(Bmp);
          uBitmapSaver.SaveBitmapToFile(Bmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
        finally
          Bmp.Free;
        end;
      except
        on E: EOutOfMemory do
          MessageDlg(Format('Out of memory while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large for this build. Lower the Scale target in Settings, reduce the frame count, or use the 64-bit plugin variant.', [E.Message]), mtError, [mbOK], 0);
        on E: EOutOfResources do
          MessageDlg(Format('Out of system resources while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large. Lower the Scale target in Settings or reduce the frame count.', [E.Message]), mtError, [mbOK], 0);
      end;
    end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
    AReExtract(BuildSaveIndicesAllLoaded, WriteAction)
  else
    WriteAction;
end;

procedure TFrameExporter.CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction);
var
  Idx: Integer;
  CopyLiveRes: Boolean;
  WriteAction: TProc;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  {Single-frame copies publish CF_BITMAP only (via Clipboard.Assign),
   not the CF_DIBV5 + CF_DIB pair CopyView uses. The decoder pipeline
   produces pf24bit frames (TFrameView.SetFrame asserts the contract)
   so there is no alpha channel to preserve — every paste target gets
   the same opaque pixels regardless of which DIB variant it asks for,
   and CF_BITMAP is the broadest-compatibility format. CopyView differs
   because the combined image carries cell-gap transparency that only
   CF_DIBV5 can round-trip; do not collapse the two paths.

   Copy-side resolution intent is captured as a local; the render path
   used to read FSettings.SaveAtLiveResolution and required a temp-flip
   to CopyAtLiveResolution around the call. That temp-flip was a
   cross-cutting hazard for any concurrent reader of SaveAtLiveResolution
   (toolbar button state, settings dialog mid-paint, status-bar resolver).
   The intent now travels as a value through PickSaveBitmap's parameter.}
  CopyLiveRes := FSettings.CopyAtLiveResolution;

  WriteAction := procedure
    var
      Tmp, Source: TBitmap;
      OwnsSource: Boolean;
      ErrMsg: string;
    begin
      {Pick the bitmap that becomes the clipboard payload. The
       file-reference path needs the bitmap object to encode to PNG;
       the legacy path hands it to VCL's Clipboard.Assign which
       publishes CF_BITMAP. CopyLiveRes is the copy-side intent
       captured above the closure.}
      if CopyLiveRes then
      begin
        Source := RenderCellAtLiveSize(Idx);
        OwnsSource := True;
      end
      else
      begin
        Source := FRenderPipeline.PickSaveBitmap(Idx, False);
        OwnsSource := False;
      end;
      try
        if FSettings.ClipboardAsFileReference then
        begin
          {File-reference path takes ownership. When OwnsSource is True
           we hand Source directly; when False (PickSaveBitmap returned
           a bitmap that lives in FFrameView), we must clone it first —
           cell bitmaps belong to the view and can't be transferred to
           the worker thread which would free them on completion.}
          if OwnsSource then
          begin
            if FClipboardPublisher.PublishAsFileReference(Source) = cprFailed then
              MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
            {PublishBitmapAsFileReference set Source to nil; don't double-free.}
            OwnsSource := False;
          end
          else
          begin
            Tmp := TBitmap.Create;
            try
              Tmp.Assign(Source);
              if FClipboardPublisher.PublishAsFileReference(Tmp) = cprFailed then
                MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
            finally
              {PublishBitmapAsFileReference set Tmp to nil on success or
               kept ownership on the cancel path; either way Free on nil
               is safe and Free on a real bitmap covers the early-exit
               case before the call.}
              Tmp.Free;
            end;
          end;
        end
        else
        begin
          {In-memory clipboard path. Same owned-vs-clone rule as the
           file-reference branch above — PublishBitmapToClipboardAsImage
           takes ownership of the bitmap, so an unowned PickSaveBitmap
           result must be cloned first to keep the FFrameView cell
           intact.}
          if OwnsSource then
          begin
            if FClipboardPublisher.PublishAsImage(Source, FSettings.Background, ErrMsg) = cprFailed then
              MessageDlg(BuildClipboardCopyFailureMessage(ErrMsg, False), mtError, [mbOK], 0);
            OwnsSource := False;
          end
          else
          begin
            Tmp := TBitmap.Create;
            try
              Tmp.Assign(Source);
              if FClipboardPublisher.PublishAsImage(Tmp, FSettings.Background, ErrMsg) = cprFailed then
                MessageDlg(BuildClipboardCopyFailureMessage(ErrMsg, False), mtError, [mbOK], 0);
            finally
              Tmp.Free;
            end;
          end;
        end;
      finally
        if OwnsSource then
        begin
          Tmp := Source;
          Tmp.Free;
        end;
      end;
    end;

  if (not CopyLiveRes) and Assigned(AReExtract) then
    AReExtract([Idx], WriteAction)
  else
    WriteAction;
end;

procedure TFrameExporter.CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction);
var
  WriteAction: TProc;
begin
  if FFrameView.CellCount = 0 then
    Exit;
  if FFrameView.ViewMode = vmSingle then
  begin
    CopyFrame(FFrameView.CurrentFrameIndex);
    Exit;
  end;

  {Copy-side resolution intent (AForceLiveRes) used to be installed by
   temp-flipping FSettings.SaveAtLiveResolution for the duration of
   this call. That was a cross-cutting hazard for concurrent readers
   of SaveAtLiveResolution; the render path now takes the intent as a
   parameter so we pass AForceLiveRes through directly.}

  WriteAction := procedure
    var
      Bmp: TBitmap;
      ErrMsg: string;
    begin
      {Same OOM-safety wrapper as SaveView, plus a check for the silent
       failure path inside CopyBitmapToClipboard: when GlobalAlloc returns
       0 mid-publish the helper bails with Result := False without raising,
       which historically meant the user saw the clipboard simply not
       change. Surface that as an explicit error too.}
      try
        Bmp := RenderWithBanner(RenderCombinedFromCells(AForceLiveRes));
        try
          FRenderPipeline.ApplyCombinedSizeCap(Bmp);
          {Publishes the strategy array assembled from FSettings.ClipboardFormats
           (DIBV5 + PNG + DIB + BITMAP by default), so modern paste targets
           keep the transparent gaps and legacy targets see a working opaque
           image instead of the broken paste they get from the OS's default
           CF_DIB synthesis. FSettings.Background is the colour transparent
           pixels are flattened against for legacy-bitmap variants; the
           alpha-aware variants ignore it.}
          if FSettings.ClipboardAsFileReference then
          begin
            if FClipboardPublisher.PublishAsFileReference(Bmp) = cprFailed then
              MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
          end
          else if FClipboardPublisher.PublishAsImage(Bmp, FSettings.Background, ErrMsg) = cprFailed then
            MessageDlg(BuildClipboardCopyFailureMessage(ErrMsg, True), mtError, [mbOK], 0);
        finally
          Bmp.Free;
        end;
      except
        on E: EOutOfMemory do
          MessageDlg(Format('Out of memory while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large for this build. Lower the Scale target in Settings, reduce the frame count, or use the 64-bit plugin variant.', [E.Message]), mtError, [mbOK], 0);
        on E: EOutOfResources do
          MessageDlg(Format('Out of system resources while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large. Lower the Scale target in Settings or reduce the frame count.', [E.Message]), mtError, [mbOK], 0);
      end;
    end;

  if (not AForceLiveRes) and Assigned(AReExtract) then
    AReExtract(BuildSaveIndicesAllLoaded, WriteAction)
  else
    WriteAction;
end;

end.
