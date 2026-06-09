{Facade for frame save and clipboard-copy operations.}
unit FrameExport;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics,
  FrameView, FrameCellStore, ExportTargetResolver, Settings, BitmapSaver, BannerInfo,
  BitmapWorkThread, SaveDialogPresenter, ClipboardPublisher,
  FrameRenderPipeline, FrameDimensionPredictor, FrameSaver, FrameCopier, FrameExportTypes;

type
  {Re-exported from FrameExportTypes so existing FrameExport imports keep
   resolving the type.}
  TReExtractAction = FrameExportTypes.TReExtractAction;

  TAsyncTaskRunner = ClipboardPublisher.TAsyncTaskRunner;
  TClipboardPublishResult = ClipboardPublisher.TClipboardPublishResult;

const
  cprSuccess = ClipboardPublisher.cprSuccess;
  cprFailed = ClipboardPublisher.cprFailed;
  cprCancelled = ClipboardPublisher.cprCancelled;

{Re-exported from ClipboardPublisher so existing imports keep resolving.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;
function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;

type
  {Facade over render pipeline, save dialog presenter, clipboard publisher,
   dimension predictor, and selection policy.}
  TFrameExporter = class
  strict private
    FResolver: TExportTargetResolver;
    FSaveDialog: TSaveDialogPresenter;
    FClipboardPublisher: TClipboardPublisher;
    FRenderPipeline: TFrameRenderPipeline;
    FDimensionPredictor: TFrameDimensionPredictor;
    FSaver: TFrameSaver;
    FCopier: TFrameCopier;
    function GetOnAsyncTaskRun: TAsyncTaskRunner;
    procedure SetOnAsyncTaskRun(const AValue: TAsyncTaskRunner);
  public
    {Collaborators are injected and owned; build one via CreateFrameExporter.}
    constructor Create(AResolver: TExportTargetResolver; ASaveDialog: TSaveDialogPresenter;
      AClipboardPublisher: TClipboardPublisher; ARenderPipeline: TFrameRenderPipeline;
      ADimensionPredictor: TFrameDimensionPredictor; ASaver: TFrameSaver; ACopier: TFrameCopier);
    destructor Destroy; override;
    {Nil = synchronous no-UI execution (tests/standalone).}
    property OnAsyncTaskRun: TAsyncTaskRunner read GetOnAsyncTaskRun write SetOnAsyncTaskRun;
    {Prefers AContextCellIndex, falls back to CurrentFrameIndex, then 0.
     Returns False when no loaded frame is found.}
    function ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
    {Selection-aware singular-action resolver. Priority:
       1. AContextCellIndex when in range and loaded.
       2. First selected loaded cell (multi-selection collapses by design).
       3. CurrentFrameIndex when loaded.
       4. Cell 0 when loaded.
       5. -1 when nothing usable.
     Differs from ResolveFrameIndex (which never consults selection).}
    function PickActionCell(AContextCellIndex: Integer): Integer;
    {Single = one element when ResolveFrameIndex succeeds; AllLoaded = every
     fcsLoaded cell; SelectedOrAll = selection when non-empty, else all loaded.}
    function BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
    function BuildSaveIndicesAllLoaded: TArray<Integer>;
    function BuildSaveIndicesSelectedOrAll: TArray<Integer>;
    {Honours SaveAtLiveResolution. AReExtract runs only after the dialog
     accepts AND the user chose native resolution — keeps the dialog snappy.}
    procedure SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {Selection-aware: writes only selected loaded frames when any are
     selected, otherwise every loaded frame.}
    procedure SaveFrames(const AFileName: string; AReExtract: TReExtractAction = nil);
    {AInitialLiveRes seeds the dialog checkbox on modern Windows; on legacy
     Windows it IS the persisted choice (no inline checkbox there).}
    procedure SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Honours CopyAtLiveResolution. AReExtract fires when native is requested
     AND live cells are not already at native size.}
    procedure CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {AForceLiveRes overrides SaveAtLiveResolution for this call only (no persist).}
    procedure CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Banner height is omitted (variable; hard to predict without a canvas).}
    procedure PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
    {ACappedW/H equal AW/H when CombinedMaxSide does not clamp.}
    function PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
    function FormatPredictedSize(AForceLiveRes: Boolean): string;
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
    {Caller-supplied save-resolution bitmaps; set before save/copy, clear
     immediately after. Bitmaps are not owned by the exporter.}
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
  end;

{Composition root: builds TFrameExporter's sub-services from AFrameView and
 ASettings, then injects them. The exporter owns and frees the sub-services.}
function CreateFrameExporter(AFrameView: TFrameView; ASettings: TPluginSettings): TFrameExporter;

implementation

uses
  ClipboardFileDrop, VclClipboard;

{Thin pass-throughs so existing call sites that resolved these via
 FrameExport continue to compile after the publisher extraction.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;
begin
  Result := ClipboardPublisher.RunBitmapWorkInModal(ABitmap, AStatusText,
    AWork, APostWork, ARunner, AOutcome);
end;

function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;
begin
  Result := ClipboardPublisher.BuildClipboardCopyFailureMessage(AFailedFormat,
    AIsCombinedView);
end;

{TFrameExporter}

constructor TFrameExporter.Create(AResolver: TExportTargetResolver; ASaveDialog: TSaveDialogPresenter;
  AClipboardPublisher: TClipboardPublisher; ARenderPipeline: TFrameRenderPipeline;
  ADimensionPredictor: TFrameDimensionPredictor; ASaver: TFrameSaver; ACopier: TFrameCopier);
begin
  inherited Create;
  FResolver := AResolver;
  FSaveDialog := ASaveDialog;
  FClipboardPublisher := AClipboardPublisher;
  FRenderPipeline := ARenderPipeline;
  FDimensionPredictor := ADimensionPredictor;
  FSaver := ASaver;
  FCopier := ACopier;
end;

{The single TPluginSettings argument coerces to each sub-service's narrow
 policy interface via the implements clause on TPluginSettings.}
function CreateFrameExporter(AFrameView: TFrameView; ASettings: TPluginSettings): TFrameExporter;
var
  Resolver: TExportTargetResolver;
  SaveDialog: TSaveDialogPresenter;
  Publisher: TClipboardPublisher;
  RenderPipeline: TFrameRenderPipeline;
  DimensionPredictor: TFrameDimensionPredictor;
  Saver: TFrameSaver;
  Copier: TFrameCopier;
begin
  Resolver := TExportTargetResolver.Create(AFrameView);
  SaveDialog := TSaveDialogPresenter.Create(ASettings);
  Publisher := TClipboardPublisher.Create(ASettings, CreateFileDropClipboard, CreateImageClipboard);
  RenderPipeline := TFrameRenderPipeline.Create(AFrameView, ASettings, ASettings, ASettings, ASettings);
  DimensionPredictor := TFrameDimensionPredictor.Create(AFrameView, ASettings, ASettings, RenderPipeline);
  Saver := TFrameSaver.Create(AFrameView, ASettings, Resolver, SaveDialog, RenderPipeline);
  Copier := TFrameCopier.Create(AFrameView, ASettings, Resolver, Publisher, RenderPipeline);
  Result := TFrameExporter.Create(Resolver, SaveDialog, Publisher,
    RenderPipeline, DimensionPredictor, Saver, Copier);
end;

destructor TFrameExporter.Destroy;
begin
  FCopier.Free;
  FSaver.Free;
  FDimensionPredictor.Free;
  FRenderPipeline.Free;
  FClipboardPublisher.Free;
  FSaveDialog.Free;
  FResolver.Free;
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
begin
  Result := FResolver.ResolveFrameIndex(AContextCellIndex, AIndex);
end;

function TFrameExporter.PickActionCell(AContextCellIndex: Integer): Integer;
begin
  Result := FResolver.PickActionCell(AContextCellIndex);
end;

function TFrameExporter.BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
begin
  Result := FResolver.BuildSaveIndicesSingle(AContextCellIndex);
end;

function TFrameExporter.BuildSaveIndicesAllLoaded: TArray<Integer>;
begin
  Result := FResolver.BuildSaveIndicesAllLoaded;
end;

function TFrameExporter.BuildSaveIndicesSelectedOrAll: TArray<Integer>;
begin
  Result := FResolver.BuildSaveIndicesSelectedOrAll;
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

procedure TFrameExporter.SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction);
begin
  FSaver.SaveFrame(AFileName, AContextCellIndex, AReExtract);
end;

procedure TFrameExporter.SaveFrames(const AFileName: string; AReExtract: TReExtractAction);
begin
  FSaver.SaveFrames(AFileName, AReExtract);
end;

procedure TFrameExporter.SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction);
begin
  FSaver.SaveView(AFileName, AInitialLiveRes, AReExtract);
end;

procedure TFrameExporter.CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction);
begin
  FCopier.CopyFrame(AContextCellIndex, AReExtract);
end;

procedure TFrameExporter.CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction);
begin
  FCopier.CopyView(AForceLiveRes, AReExtract);
end;

end.
