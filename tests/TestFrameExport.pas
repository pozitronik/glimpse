unit TestFrameExport;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResolveFrameIndex = class
  public
    [Test] procedure TestContextCellPreferred;
    [Test] procedure TestFallsBackToCurrentFrame;
    [Test] procedure TestFallsBackToZero;
    [Test] procedure TestReturnsFalseWhenEmpty;
    [Test] procedure TestReturnsFalseWhenNotLoaded;
    [Test] procedure TestNegativeContextIgnored;
    [Test] procedure TestOutOfRangeContextIgnored;
  end;

  [TestFixture]
  TTestPickActionCell = class
  public
    [Test] procedure SelectionWinsOverContextCell;
    [Test] procedure ContextCellUsedWhenNoSelection;
    [Test] procedure ContextCellOutOfRangeFallsThrough;
    [Test] procedure ContextCellNotLoadedFallsThrough;
    [Test] procedure SelectionUsedWhenNoContext;
    [Test] procedure FirstSelectedLoadedCellWins;
    [Test] procedure UnloadedSelectedCellSkipped;
    [Test] procedure FallsBackToCurrentFrameInSingleView;
    [Test] procedure CurrentFrameIgnoredOutsideSingleView;
    [Test] procedure FallsBackToCellZero;
    [Test] procedure ReturnsMinusOneWhenNothingLoaded;
    [Test] procedure ReturnsMinusOneWhenNoCells;
  end;

  [TestFixture]
  TTestFrameExportRender = class
  public
    { RenderCombinedFromCells }
    [Test] procedure TestRenderCombinedProducesBitmap;
    [Test] procedure TestRenderCombinedTightDimensions;
    [Test] procedure TestRenderCombinedIgnoresViewport;
    [Test] procedure TestRenderCombinedNoCellsReturnsNil;

    { RenderWithBanner }
    [Test] procedure TestRenderWithBannerDisabledReturnsSameSize;
    [Test] procedure TestRenderWithBannerEnabledIncreasesHeight;
    [Test] procedure TestRenderWithBannerEmptyInfoReturnsSameSize;
    [Test] procedure TestRenderWithBannerFreesInput;
  end;

  [TestFixture]
  TTestFrameExportSaveIndices = class
  public
    [Test] procedure TestSingleResolvesContextCell;
    [Test] procedure TestSingleEmptyWhenNoLoadedFrames;
    [Test] procedure TestAllLoadedSkipsUnloadedCells;
    [Test] procedure TestAllLoadedEmptyWhenNothingLoaded;
    [Test] procedure TestSelectedOrAllUsesSelectionWhenAny;
    [Test] procedure TestSelectedOrAllFallsBackToAllWhenNoSelection;
    [Test] procedure TestSelectedOrAllSkipsUnloadedSelected;
  end;

  [TestFixture]
  TTestFrameExportOverrideFrames = class
  public
    [Test] procedure TestOverrideAppliedWhenToggleOff;
    [Test] procedure TestOverrideIgnoredWhenToggleOn;
    [Test] procedure TestNilOverrideEntryFallsBackToLive;
    [Test] procedure TestClearOverrideFramesRestoresLive;
    [Test] procedure TestShorterOverrideArrayFallsBackToLive;
    {Contract: the renderer's live-resolution intent travels as a
     parameter and does NOT read FSettings.SaveAtLiveResolution. Test
     sets the persisted setting opposite to the passed intent and
     asserts the renderer follows the intent.}
    [Test] procedure TestRenderIntentIgnoresPersistedSetting_LiveIntentOff;
    [Test] procedure TestRenderIntentIgnoresPersistedSetting_LiveIntentOn;
  end;

  [TestFixture]
  TTestFrameExportGridColumns = class
  public
    {Pins the contract that vmGrid native-resolution save (toggle off)
     respects the live column count, not the auto-sqrt fallback. Before
     the fix, a narrow 1xN live layout was saved as 3x3 because the
     case statement only handled vmFilmstrip and vmScroll.}
    [Test] procedure TestSaveTracksLiveSingleColumn;
    [Test] procedure TestSaveTracksLiveTwoColumns;
  end;

  [TestFixture]
  TTestFrameExportScaling = class
  public
    {ScaleBitmapLetterbox / ScaleBitmapCropToFill mirror the live view's
     fitting logic and feed every "save at live resolution" path. The
     existing render tests exercise them indirectly; these pin the
     dimensions, background fill, and degenerate-input handling
     directly so a future fitting-logic regression surfaces here.}
    [Test] procedure Letterbox_OutputMatchesRequestedDimensions;
    [Test] procedure Letterbox_NilSourceFillsBackground;
    [Test] procedure Letterbox_OutputIsPf24bit;
    [Test] procedure CropToFill_OutputMatchesRequestedDimensions;
    [Test] procedure CropToFill_NilSourceFillsBackgroundFromSettings;
    [Test] procedure CropToFill_OutputIsPf24bit;
  end;

  [TestFixture]
  TTestFrameExportLiveResolution = class
  public
    {RenderCellAtLiveSize routes through ScaleBitmapCropToFill for
     vmSmartGrid and ScaleBitmapLetterbox otherwise. The result must
     match the live cell rect's dimensions in either case.
     RenderGridCombinedAtLiveResolution and RenderSmartCombinedFromCells
     are the entry points for "save at live resolution = ON" combined
     output; tests here verify they return non-nil bitmaps and free
     cleanly. Pixel-perfect dimensions depend on the live layout pass,
     which TFrameView controls; we assert structural properties only.}
    [Test] procedure RenderCellAtLiveSize_GridMode_ReturnsCellSizedBitmap;
    [Test] procedure RenderCellAtLiveSize_SmartGridMode_ReturnsCellSizedBitmap;
    [Test] procedure RenderGridCombinedAtLiveResolution_ProducesBitmap;
    [Test] procedure RenderGridCombinedAtLiveResolution_NoLoadedFrames_ReturnsNil;
    [Test] procedure RenderSmartCombinedFromCells_ProducesBitmap;
    [Test] procedure RenderSmartCombinedFromCells_NoLoadedFrames_ReturnsNil;
  end;

  [TestFixture]
  TTestFrameExportSaveFramesToDir = class
  strict private
    FTempDir: string;
    function CountFiles(const APattern: string): Integer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    {SaveFramesToDir is the dialog-free leaf of the SaveFrames pipeline:
     it iterates loaded cells (or selected loaded cells when
     ASelectedOnly is True), formats per-frame names, and writes through
     uBitmapSaver. Tests here verify the file count, selection
     filtering, and the placeholder-skip rule.}
    [Test] procedure SavesAllLoadedFramesAsSeparateFiles;
    [Test] procedure SkipsPlaceholderCells;
    [Test] procedure SelectedOnly_OnlyWritesSelectedLoadedCells;
    [Test] procedure NoSelectedAndSelectedOnly_WritesNothing;
    [Test] procedure FormatExtensionMatchesArgument;
  end;

  [TestFixture]
  TTestPredictMatchesRender = class
  public
    {Pinning tests: PredictCombinedSize duplicates layout math from three
     renderers (RenderCombinedFromCells, RenderGridCombinedAtLiveResolution,
     RenderSmartCombinedFromCells). Without these tests, any future change
     to renderer layout silently desynchronises the prediction used by
     toolbar dropdown labels and the status-bar resolution panel. Each
     test drives both paths from the same TFrameView+settings and asserts
     identical output dimensions; if a refactor breaks the contract these
     fail fast, not at the next user-visible release.}
    [Test] procedure VmGrid_Native;
    [Test] procedure VmGrid_Live;
    [Test] procedure VmFilmstrip_Native;
    [Test] procedure VmFilmstrip_Live;
    [Test] procedure VmScroll_Native;
    [Test] procedure VmScroll_Live;
    [Test] procedure VmSmartGrid_Native;
    [Test] procedure VmSmartGrid_Live;
  end;

  [TestFixture]
  TTestFrameExportClipboardNoOp = class
  public
    {The Save* paths all end in a modal TSaveDialog so they can't be driven
     headlessly. The Copy* paths, however, have guard-rail early returns
     (CellCount = 0 or ResolveFrameIndex returns False) that skip the
     VCL Clipboard entirely — safe to verify without a real clipboard.}
    [Test] procedure CopyFrameToClipboard_EmptyView_NoException;
    [Test] procedure CopyFrameToClipboard_UnloadedCell_NoException;
    [Test] procedure CopyAllToClipboard_EmptyView_NoException;
  end;

  [TestFixture]
  TTestRunBitmapWorkInModal = class
  public
    {RunBitmapWorkInModal is the shared scaffolding behind
     PublishBitmapAsFileReference and PublishBitmapToClipboardAsImage:
     it transfers bitmap ownership to a TBitmapWorkThread, runs it via
     an optional TAsyncTaskRunner (host modal) or synchronously when nil,
     and maps the thread's outcome to a tri-state TClipboardPublishResult.
     The cancel path is exercised at integration level (manual TC test);
     unit tests would either leak a DLL handle or race on FreeOnTerminate.}
    [Test] procedure WorkSucceeds_ReturnsSuccess;
    [Test] procedure WorkFails_ReturnsFailedWithOutcomePopulated;
    [Test] procedure WorkRaises_ReturnsFailedWithErrorMsg;
    [Test] procedure NilRunner_RunsSynchronouslyAndSucceeds;
    [Test] procedure NilBitmap_ReturnsFailedWithoutCallingWork;
    [Test] procedure BitmapOwnershipTransferred_ABitmapBecomesNil;
    [Test] procedure OutcomePreClearedEvenWhenCallerPrePopulates;
    [Test] procedure RunnerReceivesStatusText;
    [Test] procedure PostWorkRunsAfterWorkProc;
    [Test] procedure PostWorkRunsEvenOnWorkFailure;
  end;

  {BuildClipboardCopyFailureMessage composes the user-facing MessageDlg
   text after a failed PublishBitmapToClipboardAsImage call. Two axes:
     1. Did a specific format's Allocate fail (AFailedFormat non-empty)
        vs did the clipboard fail to open (AFailedFormat empty)?
     2. Is the caller a combined-view operation (remedies include
        "lower Scale target" and "reduce frame count") or a single-frame
        operation (those remedies do not apply)?
   The pure helper lives in the uFrameExport interface section so these
   tests can exercise it without the WLX form harness.}
  [TestFixture]
  TTestBuildClipboardCopyFailureMessage = class
  public
    [Test] procedure EmptyFormat_ProducesClipboardOpenFailureMessage;
    [Test] procedure EmptyFormat_IsCombinedViewIrrelevant;
    [Test] procedure NamedFormat_IncludesFormatNameInOutput;
    [Test] procedure FrameContext_RemedyDoesNotMentionScaleOrFrameCount;
    [Test] procedure CombinedContext_RemedyMentionsScaleAndFrameCount;
    [Test] procedure BothContexts_MentionClipboardTabAndFileReference;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.IOUtils, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  uTypes, uBitmapSaver, uFrameView, uFrameOffsets, uSettings, uFrameExport, uBannerInfo,
  uBitmapWorkThread;

type
  { Test subclass that exposes protected render methods }
  TTestableExporter = class(TFrameExporter)
  public
    {Default False matches the pre-step-48 production behaviour for
     callers that did not set SaveAtLiveResolution (DEF_SAVE_AT_LIVE_RESOLUTION
     = False). Tests that need the live branch pass True explicitly.}
    function TestRenderCombinedFromCells(ALiveResolutionIntent: Boolean = False): TBitmap;
    function TestRenderWithBanner(ABmp: TBitmap): TBitmap;
    function TestScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    function TestScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
    function TestRenderCellAtLiveSize(AIndex: Integer): TBitmap;
    function TestRenderGridCombinedAtLiveResolution: TBitmap;
    function TestRenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean = False): TBitmap;
    procedure TestSaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
  end;

function TTestableExporter.TestRenderCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
begin
  Result := RenderCombinedFromCells(ALiveResolutionIntent);
end;

function TTestableExporter.TestRenderWithBanner(ABmp: TBitmap): TBitmap;
begin
  Result := RenderWithBanner(ABmp);
end;

function TTestableExporter.TestScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
begin
  Result := ScaleBitmapLetterbox(ASrc, AW, AH, ABg);
end;

function TTestableExporter.TestScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
begin
  Result := ScaleBitmapCropToFill(ASrc, AW, AH);
end;

function TTestableExporter.TestRenderCellAtLiveSize(AIndex: Integer): TBitmap;
begin
  Result := RenderCellAtLiveSize(AIndex);
end;

function TTestableExporter.TestRenderGridCombinedAtLiveResolution: TBitmap;
begin
  Result := RenderGridCombinedAtLiveResolution;
end;

function TTestableExporter.TestRenderSmartCombinedFromCells(ALiveResolutionIntent: Boolean): TBitmap;
begin
  Result := RenderSmartCombinedFromCells(ALiveResolutionIntent);
end;

procedure TTestableExporter.TestSaveFramesToDir(const ADir: string;
  AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
begin
  SaveFramesToDir(ADir, AFormat, ASelectedOnly, AFileName);
end;

{ Helper: creates a temporary TFrameView parented to a form }
function CreateTestFrameView(AForm: TForm; ACellCount: Integer;
  const ALoadedIndices: array of Integer): TFrameView;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
  Bmp: TBitmap;
begin
  Result := TFrameView.Create(AForm);
  Result.Parent := AForm;
  Result.SetViewport(800, 600);
  Result.AspectRatio := 9 / 16;

  SetLength(Offsets, ACellCount);
  for I := 0 to ACellCount - 1 do
  begin
    Offsets[I].Index := I + 1;
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Result.SetCellCount(ACellCount, Offsets);

  for I := 0 to High(ALoadedIndices) do
  begin
    {pf24bit: TFrameView.SetFrame's contract; default pfDevice would
     trip the runtime check.}
    Bmp := TBitmap.Create;
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(160, 90);
    Result.SetFrame(ALoadedIndices[I], Bmp);
  end;
end;

{ TTestResolveFrameIndex }

procedure TTestResolveFrameIndex.TestContextCellPreferred;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2, 4]);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(2, Idx));
      Assert.AreEqual(2, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestFallsBackToCurrentFrame;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 3]);
    View.CurrentFrameIndex := 3;
    Exporter := TFrameExporter.Create(View, nil);
    try
      { Context index -1 => falls back to CurrentFrameIndex }
      Assert.IsTrue(Exporter.ResolveFrameIndex(-1, Idx));
      Assert.AreEqual(3, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestFallsBackToZero;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0]);
    View.CurrentFrameIndex := -1;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(-1, Idx));
      Assert.AreEqual(0, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestReturnsFalseWhenEmpty;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsFalse(Exporter.ResolveFrameIndex(-1, Idx));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestReturnsFalseWhenNotLoaded;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    { 3 cells, none loaded }
    View := CreateTestFrameView(Form, 3, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsFalse(Exporter.ResolveFrameIndex(1, Idx));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestNegativeContextIgnored;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    View.CurrentFrameIndex := 1;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(-5, Idx));
      Assert.AreEqual(1, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestOutOfRangeContextIgnored;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    View.CurrentFrameIndex := 2;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(99, Idx));
      Assert.AreEqual(2, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestPickActionCell }

procedure TTestPickActionCell.SelectionWinsOverContextCell;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(1); { selection = [1] }
    Exporter := TFrameExporter.Create(View, nil);
    try
      { Right-click on cell 3 with cell 1 selected -> menu acts on 1.
        Selection is the more deliberate gesture and wins regardless of
        where the right-click landed; matches TC's context-menu rule. }
      Assert.AreEqual(1, Exporter.PickActionCell(3));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ContextCellUsedWhenNoSelection;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    { No selection, right-click on cell 3 -> menu acts on 3.
      Confirms the context cell is the fallback when selection is empty. }
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(3, Exporter.PickActionCell(3));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ContextCellOutOfRangeFallsThrough;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(2); { selection = [2] }
    Exporter := TFrameExporter.Create(View, nil);
    try
      { Out-of-range context falls through to selection }
      Assert.AreEqual(2, Exporter.PickActionCell(99));
      Assert.AreEqual(2, Exporter.PickActionCell(-5));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ContextCellNotLoadedFallsThrough;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    { Cells 0, 1, 2 exist; only 0 and 2 are loaded; cell 1 is a placeholder }
    View := CreateTestFrameView(Form, 3, [0, 2]);
    View.ToggleSelection(2); { selection = [2] }
    Exporter := TFrameExporter.Create(View, nil);
    try
      { Context points at cell 1 which is in range but not loaded -> falls
        through to first selected loaded cell (2) }
      Assert.AreEqual(2, Exporter.PickActionCell(1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.SelectionUsedWhenNoContext;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(3); { selection = [3] }
    Exporter := TFrameExporter.Create(View, nil);
    try
      { No context, single-selected cell wins over cell-0 fallback }
      Assert.AreEqual(3, Exporter.PickActionCell(-1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.FirstSelectedLoadedCellWins;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(2);
    View.ToggleSelection(4); { selection = [2, 4]; Copy frame picks 2 }
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(2, Exporter.PickActionCell(-1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.UnloadedSelectedCellSkipped;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    { Cells 0..4 exist; only 2 and 4 are loaded }
    View := CreateTestFrameView(Form, 5, [2, 4]);
    View.ToggleSelection(1); { selected but not loaded }
    View.ToggleSelection(2); { selected and loaded }
    Exporter := TFrameExporter.Create(View, nil);
    try
      { First-loaded-selected wins (2), the unloaded selected (1) is skipped }
      Assert.AreEqual(2, Exporter.PickActionCell(-1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.FallsBackToCurrentFrameInSingleView;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ViewMode := vmSingle;
    View.CurrentFrameIndex := 3;
    { No selection, no context -> CurrentFrameIndex in single-view mode }
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(3, Exporter.PickActionCell(-1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.CurrentFrameIgnoredOutsideSingleView;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    {Default view mode is vmGrid (not single-view), so CurrentFrameIndex
     should not influence the pick — falls back to cell 0 instead.}
    View.CurrentFrameIndex := 3;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(0, Exporter.PickActionCell(-1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.FallsBackToCellZero;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    { No selection, no context, not single-view -> cell 0 }
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(0, Exporter.PickActionCell(-1));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ReturnsMinusOneWhenNothingLoaded;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    { 5 placeholder cells, none loaded -> nothing usable }
    View := CreateTestFrameView(Form, 5, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(-1, Exporter.PickActionCell(-1));
      Assert.AreEqual(-1, Exporter.PickActionCell(2));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPickActionCell.ReturnsMinusOneWhenNoCells;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.AreEqual(-1, Exporter.PickActionCell(-1));
      Assert.AreEqual(-1, Exporter.PickActionCell(0));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestFrameExportRender }

function CreateSettingsWithBanner(AShowBanner: Boolean): TPluginSettings;
begin
  { Non-existent INI path: settings use defaults }
  Result := TPluginSettings.Create('__nonexistent__.ini');
  Result.ShowBanner := AShowBanner;
end;

procedure TTestFrameExportRender.TestRenderCombinedProducesBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderCombinedFromCells;
        try
          Assert.IsNotNull(Bmp, 'RenderCombinedFromCells must return a bitmap');
          Assert.IsTrue(Bmp.Width > 0, 'Bitmap width must be positive');
          Assert.IsTrue(Bmp.Height > 0, 'Bitmap height must be positive');
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderCombinedTightDimensions;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  { Output dimensions must follow the grid math, NOT the FrameView control
    size. With 4 frames of 160x90, default cell gap 0 and border 0,
    auto columns = ceil(sqrt(4)) = 2 -> a 2x2 grid -> 320x180. Settling
    this regression-pins the fix for the "background bands" bug: the old
    PaintTo-the-control approach would produce a 640x480 image. }
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.Width := 640;
    View.Height := 480;
    Settings := CreateSettingsWithBanner(False);
    try
      Settings.CellGap := 0;
      Settings.CombinedBorder := 0;
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderCombinedFromCells;
        try
          Assert.AreEqual(320, Bmp.Width,
            'Width must equal cols*frameW + gaps + 2*border, not control width');
          Assert.AreEqual(180, Bmp.Height,
            'Height must equal rows*frameH + gaps + 2*border, not control height');
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderCombinedIgnoresViewport;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  BmpA, BmpB: TBitmap;
begin
  { Two renderings of the same cells with wildly different control sizes
    must produce identical output dimensions. This is the user-facing
    promise behind moving away from PaintTo: "Combined" must be the same
    image regardless of the live view's geometry. }
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        View.Width := 800;
        View.Height := 600;
        BmpA := Exporter.TestRenderCombinedFromCells;
        try
          View.Width := 100;
          View.Height := 100;
          BmpB := Exporter.TestRenderCombinedFromCells;
          try
            Assert.AreEqual(BmpA.Width, BmpB.Width,
              'Combined output width must not depend on FrameView size');
            Assert.AreEqual(BmpA.Height, BmpB.Height,
              'Combined output height must not depend on FrameView size');
          finally
            BmpB.Free;
          end;
        finally
          BmpA.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderCombinedNoCellsReturnsNil;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  { Zero cells -> nil result; callers (SaveCombinedFrame, CopyAllToClipboard)
    are gated by CellCount = 0 today, but the renderer must hold the same
    contract as RenderCombinedImage so the gating can simplify later. }
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderCombinedFromCells;
        Assert.IsNull(Bmp, 'Empty view must return nil');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderWithBannerDisabledReturnsSameSize;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Input, Output: TBitmap;
  OrigH: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Input := TBitmap.Create;
        Input.SetSize(200, 150);
        OrigH := Input.Height;
        { When ShowBanner=False, RenderWithBanner returns the same bitmap }
        Output := Exporter.TestRenderWithBanner(Input);
        try
          Assert.AreEqual(OrigH, Output.Height,
            'Height must be unchanged when banner is disabled');
          Assert.IsTrue(Input = Output,
            'Must return the same bitmap instance when banner is disabled');
        finally
          Output.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderWithBannerEnabledIncreasesHeight;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Input, Output: TBitmap;
  OrigH: Integer;
  Info: TBannerInfo;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(True);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Info := Default(TBannerInfo);
        Info.FileName := 'test_video.mp4';
        Info.FileSizeBytes := 1024 * 1024;
        Info.DurationSec := 120.0;
        Info.Width := 1920;
        Info.Height := 1080;
        Info.VideoCodec := 'h264';
        Exporter.UpdateBannerInfo(Info);

        Input := TBitmap.Create;
        Input.SetSize(400, 300);
        OrigH := Input.Height;
        { RenderWithBanner frees Input and returns a new, taller bitmap }
        Output := Exporter.TestRenderWithBanner(Input);
        try
          Assert.IsTrue(Output.Height > OrigH,
            Format('Banner must increase height: got %d, original %d',
              [Output.Height, OrigH]));
          Assert.AreEqual(400, Output.Width,
            'Width must be preserved when adding banner');
        finally
          Output.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderWithBannerEmptyInfoReturnsSameSize;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Input, Output: TBitmap;
  OrigH: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(True);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        { No UpdateBannerInfo called: FBannerInfo is default (all zeroes/empty).
          FormatBannerLines with empty info still produces lines, but
          PrependBanner handles them; the test verifies no crash. }
        Input := TBitmap.Create;
        Input.SetSize(300, 200);
        OrigH := Input.Height;
        Output := Exporter.TestRenderWithBanner(Input);
        try
          Assert.IsTrue(Output.Height >= OrigH,
            'Output height must be >= input even with empty banner info');
        finally
          Output.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportRender.TestRenderWithBannerFreesInput;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Input, Output: TBitmap;
  Info: TBannerInfo;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(True);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Info := Default(TBannerInfo);
        Info.FileName := 'video.mp4';
        Info.DurationSec := 60.0;
        Exporter.UpdateBannerInfo(Info);

        Input := TBitmap.Create;
        Input.SetSize(200, 100);
        Output := Exporter.TestRenderWithBanner(Input);
        try
          { When banner is enabled, Output must be a different object
            because RenderWithBanner frees the input and returns a new bitmap }
          Assert.IsTrue(Input <> Output,
            'Must return a new bitmap instance when banner is enabled');
        finally
          Output.Free;
        end;
        { Input was freed by RenderWithBanner; do NOT free it again }
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TTestFrameExportSaveIndices}

procedure TTestFrameExportSaveIndices.TestSingleResolvesContextCell;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2, 4]);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesSingle(2);
      Assert.AreEqual(1, Integer(Length(Indices)),
        'Single must return exactly one element when context resolves');
      Assert.AreEqual(2, Indices[0]);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveIndices.TestSingleEmptyWhenNoLoadedFrames;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  {Cells exist but none are loaded -> ResolveFrameIndex returns False;
   Single must hand back an empty array so WithReExtract no-ops.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesSingle(0);
      Assert.AreEqual(0, Integer(Length(Indices)));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveIndices.TestAllLoadedSkipsUnloadedCells;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [1, 3]);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesAllLoaded;
      Assert.AreEqual(2, Integer(Length(Indices)));
      Assert.AreEqual(1, Indices[0]);
      Assert.AreEqual(3, Indices[1]);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveIndices.TestAllLoadedEmptyWhenNothingLoaded;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesAllLoaded;
      Assert.AreEqual(0, Integer(Length(Indices)));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveIndices.TestSelectedOrAllUsesSelectionWhenAny;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  {When at least one cell is selected, only loaded selected cells
   must be returned — mirrors TFrameExporter.SaveFrames selection-
   aware semantics.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ToggleSelection(1);
    View.ToggleSelection(3);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesSelectedOrAll;
      Assert.AreEqual(2, Integer(Length(Indices)));
      Assert.AreEqual(1, Indices[0]);
      Assert.AreEqual(3, Indices[1]);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveIndices.TestSelectedOrAllFallsBackToAllWhenNoSelection;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesSelectedOrAll;
      Assert.AreEqual(4, Integer(Length(Indices)),
        'No selection -> every loaded cell');
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveIndices.TestSelectedOrAllSkipsUnloadedSelected;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Indices: TArray<Integer>;
begin
  {Selection over an unloaded cell must be ignored: the action cannot
   read a frame that does not exist yet, so re-extraction would hand it
   a nil bitmap.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2]);
    View.ToggleSelection(0);
    View.ToggleSelection(1); {unloaded, must drop}
    View.ToggleSelection(2);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Indices := Exporter.BuildSaveIndicesSelectedOrAll;
      Assert.AreEqual(2, Integer(Length(Indices)));
      Assert.AreEqual(0, Indices[0]);
      Assert.AreEqual(2, Indices[1]);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TTestFrameExportOverrideFrames}

{Helper: builds an array of fresh TBitmaps of the given size, parallel to
 the FrameView's cell count. Caller owns and must free the bitmaps after
 the test (the exporter never owns override frames).}
function MakeOverrideBitmaps(ACount, AW, AH: Integer): TArray<TBitmap>;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I] := TBitmap.Create;
    Result[I].SetSize(AW, AH);
  end;
end;

procedure FreeOverrideBitmaps(var ABitmaps: TArray<TBitmap>);
var
  I: Integer;
begin
  for I := 0 to High(ABitmaps) do
    ABitmaps[I].Free;
  SetLength(ABitmaps, 0);
end;

procedure TTestFrameExportOverrideFrames.TestOverrideAppliedWhenToggleOff;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  Bmp: TBitmap;
begin
  {With SaveAtLiveResolution off and override frames set, the combined
   render must use the override bitmap dimensions (320x180) rather than
   the live cell dimensions (160x90). Anchors the contract that the save
   path consumes the higher-resolution save bitmaps when supplied.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Overrides := MakeOverrideBitmaps(4, 320, 180);
        try
          Exporter.SetOverrideFrames(Overrides);
          Bmp := Exporter.TestRenderCombinedFromCells;
          try
            Assert.AreEqual(640, Bmp.Width, 'Override 320 * 2 cols');
            Assert.AreEqual(360, Bmp.Height, 'Override 180 * 2 rows');
          finally
            Bmp.Free;
          end;
        finally
          Exporter.ClearOverrideFrames;
          FreeOverrideBitmaps(Overrides);
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportOverrideFrames.TestOverrideIgnoredWhenToggleOn;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  BmpBaseline, BmpWithOverride: TBitmap;
begin
  {Toggle on means "save at view resolution" — the toggle's contract is
   to mirror the on-screen view, so override frames must not influence
   the rendered cells. Render twice: once with no override, once with
   override set; the two renders must have identical dimensions, proving
   the override array was ignored. (We avoid pinning specific dimensions
   here because the live-resolution path derives cell sizes from the
   FrameView's viewport layout, which is implementation detail.)}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := True;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        BmpBaseline := Exporter.TestRenderCombinedFromCells(True);
        try
          Overrides := MakeOverrideBitmaps(4, 320, 180);
          try
            Exporter.SetOverrideFrames(Overrides);
            BmpWithOverride := Exporter.TestRenderCombinedFromCells(True);
            try
              Assert.AreEqual(BmpBaseline.Width, BmpWithOverride.Width,
                'Toggle-on must ignore override (width unchanged)');
              Assert.AreEqual(BmpBaseline.Height, BmpWithOverride.Height,
                'Toggle-on must ignore override (height unchanged)');
            finally
              BmpWithOverride.Free;
            end;
          finally
            Exporter.ClearOverrideFrames;
            FreeOverrideBitmaps(Overrides);
          end;
        finally
          BmpBaseline.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportOverrideFrames.TestRenderIntentIgnoresPersistedSetting_LiveIntentOff;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  Bmp: TBitmap;
begin
  {Persisted SaveAtLiveResolution=True, but render is invoked with
   intent=False. The renderer must follow the intent (native), which
   means it must respect the override array. The width of an override
   bitmap is 320 (set by MakeOverrideBitmaps), so rendering with
   intent=False on a 4-cell single-column grid gives width >= 320.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := True;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Overrides := MakeOverrideBitmaps(4, 320, 180);
        try
          Exporter.SetOverrideFrames(Overrides);
          Bmp := Exporter.TestRenderCombinedFromCells(False);
          try
            {Native intent + override means each cell is the override
             bitmap (320x180). Width must be a multiple of 320.}
            Assert.AreEqual<Integer>(0, Bmp.Width mod 320,
              'Native intent with override must use 320-wide override bitmaps regardless of the persisted SaveAtLiveResolution=True setting');
          finally
            Bmp.Free;
          end;
        finally
          FreeOverrideBitmaps(Overrides);
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportOverrideFrames.TestRenderIntentIgnoresPersistedSetting_LiveIntentOn;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  BmpLiveNoOverride, BmpLiveWithOverride: TBitmap;
begin
  {Persisted SaveAtLiveResolution=False, but render is invoked with
   intent=True. The renderer must follow the intent (live), which means
   the override array must be ignored. Render twice and assert the two
   widths match — if override was honoured (a settings-driven read
   would do that) the widths would diverge.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        BmpLiveNoOverride := Exporter.TestRenderCombinedFromCells(True);
        try
          Overrides := MakeOverrideBitmaps(4, 320, 180);
          try
            Exporter.SetOverrideFrames(Overrides);
            BmpLiveWithOverride := Exporter.TestRenderCombinedFromCells(True);
            try
              Assert.AreEqual(BmpLiveNoOverride.Width, BmpLiveWithOverride.Width,
                'Live intent must ignore override (width unchanged) regardless of the persisted SaveAtLiveResolution=False setting');
              Assert.AreEqual(BmpLiveNoOverride.Height, BmpLiveWithOverride.Height,
                'Live intent must ignore override (height unchanged)');
            finally
              BmpLiveWithOverride.Free;
            end;
          finally
            FreeOverrideBitmaps(Overrides);
          end;
        finally
          BmpLiveNoOverride.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportOverrideFrames.TestNilOverrideEntryFallsBackToLive;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  BmpFull, BmpAllNil: TBitmap;
begin
  {nil entries in the override array must fall back to the live cell.
   Verified indirectly: an all-nil override array of matching length
   must produce the same dimensions as having no override at all
   (every cell falls back to live).}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        BmpFull := Exporter.TestRenderCombinedFromCells;
        try
          SetLength(Overrides, 4); {all entries nil by default}
          Exporter.SetOverrideFrames(Overrides);
          BmpAllNil := Exporter.TestRenderCombinedFromCells;
          try
            Assert.AreEqual(BmpFull.Width, BmpAllNil.Width,
              'All-nil override must render same width as no-override');
            Assert.AreEqual(BmpFull.Height, BmpAllNil.Height,
              'All-nil override must render same height as no-override');
          finally
            BmpAllNil.Free;
          end;
          Exporter.ClearOverrideFrames;
        finally
          BmpFull.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportOverrideFrames.TestClearOverrideFramesRestoresLive;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  BmpAfterClear: TBitmap;
begin
  {After ClearOverrideFrames, save paths must use live cells again. Set
   override (which would force 320x180 cells), clear, then render — the
   output must match the live-cell dimensions (160x90 cells -> 320x180
   in a 2x2 grid).}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Overrides := MakeOverrideBitmaps(4, 320, 180);
        try
          Exporter.SetOverrideFrames(Overrides);
          Exporter.ClearOverrideFrames;
          BmpAfterClear := Exporter.TestRenderCombinedFromCells;
          try
            Assert.AreEqual(320, BmpAfterClear.Width,
              'After clear: live 160 * 2 cols');
            Assert.AreEqual(180, BmpAfterClear.Height,
              'After clear: live 90 * 2 rows');
          finally
            BmpAfterClear.Free;
          end;
        finally
          FreeOverrideBitmaps(Overrides);
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportOverrideFrames.TestShorterOverrideArrayFallsBackToLive;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Overrides: TArray<TBitmap>;
  Bmp: TBitmap;
begin
  {Defensive contract: an override array shorter than the cell count
   must not crash; missing entries fall back to live cells. Set 2
   override entries for a 4-cell view; the live cells (160x90) drive the
   layout because the renderer normalises cell pixel size.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Overrides := MakeOverrideBitmaps(2, 320, 180);
        try
          Exporter.SetOverrideFrames(Overrides);
          Bmp := Exporter.TestRenderCombinedFromCells;
          try
            Assert.IsNotNull(Bmp, 'Short override array must not crash');
            Assert.IsTrue(Bmp.Width > 0, 'Width positive');
            Assert.IsTrue(Bmp.Height > 0, 'Height positive');
          finally
            Bmp.Free;
          end;
        finally
          Exporter.ClearOverrideFrames;
          FreeOverrideBitmaps(Overrides);
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TTestFrameExportGridColumns}

procedure TTestFrameExportGridColumns.TestSaveTracksLiveSingleColumn;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  {9 cells of 160x90 forced to a 1-column live layout. With toggle off,
   the saved combined image must be 1 col x 9 rows = 160 x 810. Before
   the fix, vmGrid hit the auto-sqrt branch and produced a 3x3 = 480 x
   270 image (the user's original report).}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 9, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
    View.ColumnCount := 1; {force 1-column live layout}
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderCombinedFromCells;
        try
          Assert.AreEqual(160, Bmp.Width, '1 col * 160 = 160');
          Assert.AreEqual(810, Bmp.Height, '9 rows * 90 = 810');
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportGridColumns.TestSaveTracksLiveTwoColumns;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  {6 cells of 160x90 forced to 2 columns -> live 2x3. Saved must be
   2 col * 160 = 320 wide, 3 rows * 90 = 270 tall.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 6, [0, 1, 2, 3, 4, 5]);
    View.ColumnCount := 2;
    Settings := CreateSettingsWithBanner(False);
    Settings.SaveAtLiveResolution := False;
    Settings.CellGap := 0;
    Settings.CombinedBorder := 0;
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderCombinedFromCells;
        try
          Assert.AreEqual(320, Bmp.Width, '2 cols * 160 = 320');
          Assert.AreEqual(270, Bmp.Height, '3 rows * 90 = 270');
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TTestFrameExportClipboardNoOp}

procedure TTestFrameExportClipboardNoOp.CopyFrameToClipboard_EmptyView_NoException;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TFrameExporter;
begin
  {A copy request with zero cells must bail before touching the Clipboard —
   otherwise any environment without a clipboard (headless CI, sandboxes)
   would throw from inside the guard.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TFrameExporter.Create(View, Settings);
      try
        Exporter.CopyFrame(-1);
        Exporter.CopyFrame(0);
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportClipboardNoOp.CopyFrameToClipboard_UnloadedCell_NoException;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TFrameExporter;
begin
  {Cells exist but none have a bitmap assigned — ResolveFrameIndex returns
   False and the method exits before the Clipboard call. Same contract as
   the empty-view case but exercised through a different branch.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, []);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TFrameExporter.Create(View, Settings);
      try
        Exporter.CopyFrame(1);
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportClipboardNoOp.CopyAllToClipboard_EmptyView_NoException;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TFrameExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TFrameExporter.Create(View, Settings);
      try
        Exporter.CopyView(Settings.SaveAtLiveResolution);
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestFrameExportScaling }

function MakeColorSrcBitmap(AW, AH: Integer; AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(Rect(0, 0, AW, AH));
end;

procedure TTestFrameExportScaling.Letterbox_OutputMatchesRequestedDimensions;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Src := MakeColorSrcBitmap(160, 90, clRed);
        try
          Out := Exporter.TestScaleBitmapLetterbox(Src, 320, 200, clBlue);
          try
            Assert.AreEqual(320, Out.Width, 'Output width must match request');
            Assert.AreEqual(200, Out.Height, 'Output height must match request');
          finally
            Out.Free;
          end;
        finally
          Src.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportScaling.Letterbox_NilSourceFillsBackground;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Out: TBitmap;
begin
  {Defensive: nil source must not crash. Output is just the background
   colour at the requested dimensions.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Out := Exporter.TestScaleBitmapLetterbox(nil, 100, 60, clYellow);
        try
          Assert.IsNotNull(Out);
          Assert.AreEqual(100, Out.Width);
          Assert.AreEqual(60, Out.Height);
        finally
          Out.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportScaling.Letterbox_OutputIsPf24bit;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Src := MakeColorSrcBitmap(80, 45, clGreen);
        try
          Out := Exporter.TestScaleBitmapLetterbox(Src, 200, 120, clBlack);
          try
            Assert.AreEqual(Ord(pf24bit), Ord(Out.PixelFormat),
              'Output must be pf24bit (TFrameView.SetFrame contract).');
          finally
            Out.Free;
          end;
        finally
          Src.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportScaling.CropToFill_OutputMatchesRequestedDimensions;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Src := MakeColorSrcBitmap(160, 90, clRed);
        try
          Out := Exporter.TestScaleBitmapCropToFill(Src, 256, 256);
          try
            Assert.AreEqual(256, Out.Width);
            Assert.AreEqual(256, Out.Height);
          finally
            Out.Free;
          end;
        finally
          Src.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportScaling.CropToFill_NilSourceFillsBackgroundFromSettings;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Out: TBitmap;
begin
  {Nil source: function fills the result with FSettings.Background and
   returns. Different from Letterbox where the caller passes a bg colour.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Out := Exporter.TestScaleBitmapCropToFill(nil, 80, 80);
        try
          Assert.IsNotNull(Out);
          Assert.AreEqual(80, Out.Width);
          Assert.AreEqual(80, Out.Height);
        finally
          Out.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportScaling.CropToFill_OutputIsPf24bit;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Src := MakeColorSrcBitmap(80, 45, clGreen);
        try
          Out := Exporter.TestScaleBitmapCropToFill(Src, 200, 120);
          try
            Assert.AreEqual(Ord(pf24bit), Ord(Out.PixelFormat));
          finally
            Out.Free;
          end;
        finally
          Src.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestFrameExportLiveResolution }

procedure TTestFrameExportLiveResolution.RenderCellAtLiveSize_GridMode_ReturnsCellSizedBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ViewMode := vmGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        R := View.GetCellRect(1);
        Bmp := Exporter.TestRenderCellAtLiveSize(1);
        try
          Assert.IsNotNull(Bmp);
          Assert.AreEqual<Integer>(Max(1, R.Width), Bmp.Width,
            'Output width must equal the live cell rect width');
          Assert.AreEqual<Integer>(Max(1, R.Height), Bmp.Height,
            'Output height must equal the live cell rect height');
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportLiveResolution.RenderCellAtLiveSize_SmartGridMode_ReturnsCellSizedBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ViewMode := vmSmartGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        R := View.GetCellRect(0);
        Bmp := Exporter.TestRenderCellAtLiveSize(0);
        try
          Assert.IsNotNull(Bmp);
          Assert.AreEqual<Integer>(Max(1, R.Width), Bmp.Width);
          Assert.AreEqual<Integer>(Max(1, R.Height), Bmp.Height);
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportLiveResolution.RenderGridCombinedAtLiveResolution_ProducesBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ViewMode := vmGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderGridCombinedAtLiveResolution;
        try
          Assert.IsNotNull(Bmp,
            'Live-resolution grid render must produce a bitmap');
          Assert.IsTrue(Bmp.Width > 0);
          Assert.IsTrue(Bmp.Height > 0);
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportLiveResolution.RenderGridCombinedAtLiveResolution_NoLoadedFrames_ReturnsNil;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Empty: TFrameOffsetArray;
begin
  {Zero cells -> CollectFramesAndOffsets returns 0 -> render exits nil.
   N>0 cells with all-nil bitmaps still renders (placeholder cells), so
   to hit the nil-return path the cell count itself must be zero.}
  Form := TForm.CreateNew(nil);
  try
    View := TFrameView.Create(Form);
    View.Parent := Form;
    View.SetViewport(800, 600);
    View.ViewMode := vmGrid;
    SetLength(Empty, 0);
    View.SetCellCount(0, Empty);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Assert.IsNull(Exporter.TestRenderGridCombinedAtLiveResolution,
          'Zero cells -> nothing to render -> nil');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportLiveResolution.RenderSmartCombinedFromCells_ProducesBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ViewMode := vmSmartGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderSmartCombinedFromCells;
        try
          Assert.IsNotNull(Bmp);
          Assert.IsTrue(Bmp.Width > 0);
          Assert.IsTrue(Bmp.Height > 0);
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportLiveResolution.RenderSmartCombinedFromCells_NoLoadedFrames_ReturnsNil;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Empty: TFrameOffsetArray;
begin
  Form := TForm.CreateNew(nil);
  try
    View := TFrameView.Create(Form);
    View.Parent := Form;
    View.SetViewport(800, 600);
    View.ViewMode := vmSmartGrid;
    SetLength(Empty, 0);
    View.SetCellCount(0, Empty);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Assert.IsNull(Exporter.TestRenderSmartCombinedFromCells,
          'Zero cells -> nothing to render -> nil');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestFrameExportSaveFramesToDir }

procedure TTestFrameExportSaveFramesToDir.Setup;
begin
  FTempDir := IncludeTrailingPathDelimiter(
    System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetTempPath,
      'VT_FrameExportSaveDir_' + TGuid.NewGuid.ToString));
  System.IOUtils.TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestFrameExportSaveFramesToDir.TearDown;
begin
  if (FTempDir <> '') and System.IOUtils.TDirectory.Exists(FTempDir) then
    System.IOUtils.TDirectory.Delete(FTempDir, True);
end;

function TTestFrameExportSaveFramesToDir.CountFiles(const APattern: string): Integer;
begin
  Result := Length(System.IOUtils.TDirectory.GetFiles(FTempDir, APattern));
end;

procedure TTestFrameExportSaveFramesToDir.SavesAllLoadedFramesAsSeparateFiles;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    {3 cells, all loaded}
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Exporter.TestSaveFramesToDir(FTempDir, sfPNG, False, 'video.mp4');
        Assert.AreEqual(3, CountFiles('*.png'),
          'Every loaded cell must produce a PNG');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveFramesToDir.SkipsPlaceholderCells;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    {5 cells, only 2 loaded (indices 0 and 3); the other three are
     placeholders and must be skipped.}
    View := CreateTestFrameView(Form, 5, [0, 3]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Exporter.TestSaveFramesToDir(FTempDir, sfPNG, False, 'video.mp4');
        Assert.AreEqual(2, CountFiles('*.png'),
          'Placeholder cells must be skipped');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveFramesToDir.SelectedOnly_OnlyWritesSelectedLoadedCells;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ToggleSelection(1);
    View.ToggleSelection(3);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Exporter.TestSaveFramesToDir(FTempDir, sfPNG, True, 'video.mp4');
        Assert.AreEqual(2, CountFiles('*.png'),
          'Only selected loaded cells must be saved');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveFramesToDir.NoSelectedAndSelectedOnly_WritesNothing;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Exporter.TestSaveFramesToDir(FTempDir, sfPNG, True, 'video.mp4');
        Assert.AreEqual(0, CountFiles('*.png'),
          'ASelectedOnly with no selection writes nothing; production callers gate with SelectedCount>0 first');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestFrameExportSaveFramesToDir.FormatExtensionMatchesArgument;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Exporter.TestSaveFramesToDir(FTempDir, sfJPEG, False, 'video.mp4');
        Assert.AreEqual(2, CountFiles('*.jpg'),
          'AFormat=sfJPEG must produce .jpg files via GenerateFrameFileName');
        Assert.AreEqual(0, CountFiles('*.png'),
          'No .png files must be produced when AFormat=sfJPEG');
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestPredictMatchesRender }

procedure AssertPredictEqualsRender(AMode: TViewMode; AForceLive: Boolean; ACellCount: Integer);
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  PW, PH: Integer;
  Bmp: TBitmap;
  LoadedAll: array of Integer;
  I: Integer;
  ContextLabel: string;
begin
  SetLength(LoadedAll, ACellCount);
  for I := 0 to ACellCount - 1 do
    LoadedAll[I] := I;

  ContextLabel := Format('Mode=%d ForceLive=%s N=%d', [Ord(AMode), BoolToStr(AForceLive, True), ACellCount]);

  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, ACellCount, LoadedAll);
    View.ViewMode := AMode;
    Settings := CreateSettingsWithBanner(False);
    try
      {Predictor and renderer both take live-resolution intent as a
       parameter; the settings field is no longer read by the render
       path. Keeping it in sync documents intent for dialog-seeding tests.}
      Settings.SaveAtLiveResolution := AForceLive;
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Exporter.PredictCombinedSize(AForceLive, PW, PH);
        Bmp := Exporter.TestRenderCombinedFromCells(AForceLive);
        try
          Assert.IsNotNull(Bmp, ContextLabel + ': renderer returned nil; cannot compare');
          Assert.AreEqual(Bmp.Width, PW, ContextLabel + ': predicted width must equal rendered width');
          Assert.AreEqual(Bmp.Height, PH, ContextLabel + ': predicted height must equal rendered height');
        finally
          Bmp.Free;
        end;
      finally
        Exporter.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestPredictMatchesRender.VmGrid_Native;
begin
  AssertPredictEqualsRender(vmGrid, False, 6);
end;

procedure TTestPredictMatchesRender.VmGrid_Live;
begin
  AssertPredictEqualsRender(vmGrid, True, 6);
end;

procedure TTestPredictMatchesRender.VmFilmstrip_Native;
begin
  AssertPredictEqualsRender(vmFilmstrip, False, 5);
end;

procedure TTestPredictMatchesRender.VmFilmstrip_Live;
begin
  AssertPredictEqualsRender(vmFilmstrip, True, 5);
end;

procedure TTestPredictMatchesRender.VmScroll_Native;
begin
  AssertPredictEqualsRender(vmScroll, False, 5);
end;

procedure TTestPredictMatchesRender.VmScroll_Live;
begin
  AssertPredictEqualsRender(vmScroll, True, 5);
end;

procedure TTestPredictMatchesRender.VmSmartGrid_Native;
begin
  AssertPredictEqualsRender(vmSmartGrid, False, 6);
end;

procedure TTestPredictMatchesRender.VmSmartGrid_Live;
begin
  AssertPredictEqualsRender(vmSmartGrid, True, 6);
end;

{ TTestRunBitmapWorkInModal }

function MakeWorkTestBitmap: Vcl.Graphics.TBitmap;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  Result.SetSize(4, 4);
end;

procedure TTestRunBitmapWorkInModal.WorkSucceeds_ReturnsSuccess;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
begin
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := True;
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprSuccess, Res);
  Assert.IsTrue(Outcome.Success);
end;

procedure TTestRunBitmapWorkInModal.WorkFails_ReturnsFailedWithOutcomePopulated;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
begin
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := False;
      AOut.ErrorMsg := 'work declined';
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprFailed, Res);
  Assert.IsFalse(Outcome.Success);
  Assert.AreEqual('work declined', Outcome.ErrorMsg);
end;

procedure TTestRunBitmapWorkInModal.WorkRaises_ReturnsFailedWithErrorMsg;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
begin
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      raise Exception.Create('mid-work crash');
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprFailed, Res);
  Assert.AreEqual('mid-work crash', Outcome.ErrorMsg);
end;

procedure TTestRunBitmapWorkInModal.NilRunner_RunsSynchronouslyAndSucceeds;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
  WorkRan: Boolean;
begin
  WorkRan := False;
  Bmp := MakeWorkTestBitmap;
  Res := RunBitmapWorkInModal(Bmp, 'ignored',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      WorkRan := True;
      AOut.Success := True;
    end,
    nil,
    nil,
    Outcome);
  Assert.AreEqual(cprSuccess, Res);
  Assert.IsTrue(WorkRan, 'Work proc executed via the synchronous fallback');
end;

procedure TTestRunBitmapWorkInModal.NilBitmap_ReturnsFailedWithoutCallingWork;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  Res: TClipboardPublishResult;
  WorkRan: Boolean;
begin
  WorkRan := False;
  Bmp := nil;
  Res := RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      WorkRan := True;
      AOut.Success := True;
    end,
    nil, nil, Outcome);
  Assert.AreEqual(cprFailed, Res);
  Assert.IsFalse(WorkRan, 'Work proc must not run when bitmap is nil');
end;

procedure TTestRunBitmapWorkInModal.BitmapOwnershipTransferred_ABitmapBecomesNil;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
begin
  Bmp := MakeWorkTestBitmap;
  RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := True;
    end,
    nil, nil, Outcome);
  Assert.IsNull(Bmp, 'Caller-side var becomes nil — ownership moved into the thread');
end;

procedure TTestRunBitmapWorkInModal.OutcomePreClearedEvenWhenCallerPrePopulates;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
begin
  {Caller may reuse the same Outcome variable across calls. The helper
   must clear it on entry so a stale ErrorMsg from a previous call does
   not bleed into a subsequent nil-bitmap early-exit.}
  Outcome.Success := True;
  Outcome.ErrorMsg := 'stale value';
  Bmp := nil;
  RunBitmapWorkInModal(Bmp, '', nil, nil, nil, Outcome);
  Assert.IsFalse(Outcome.Success, 'Pre-cleared on entry');
  Assert.AreEqual('', Outcome.ErrorMsg);
end;

procedure TTestRunBitmapWorkInModal.RunnerReceivesStatusText;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  CapturedText: string;
begin
  Bmp := MakeWorkTestBitmap;
  CapturedText := '';
  RunBitmapWorkInModal(Bmp, 'hello status',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := True;
    end,
    nil,
    function(AT: TThread; const AText: string): Boolean
    begin
      CapturedText := AText;
      AT.Start;
      AT.WaitFor;
      Result := True;
    end,
    Outcome);
  Assert.AreEqual('hello status', CapturedText);
end;

procedure TTestRunBitmapWorkInModal.PostWorkRunsAfterWorkProc;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  Order: TStringList;
begin
  Order := TStringList.Create;
  try
    Bmp := MakeWorkTestBitmap;
    RunBitmapWorkInModal(Bmp, '',
      procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
      begin
        Order.Add('work');
        AOut.Success := True;
      end,
      procedure(const AOut: uBitmapWorkThread.TBitmapWorkOutcome; ACancelled: Boolean)
      begin
        Order.Add('post');
      end,
      nil, Outcome);
    Assert.AreEqual(2, Order.Count);
    Assert.AreEqual('work', Order[0]);
    Assert.AreEqual('post', Order[1]);
  finally
    Order.Free;
  end;
end;

procedure TTestRunBitmapWorkInModal.PostWorkRunsEvenOnWorkFailure;
var
  Bmp: Vcl.Graphics.TBitmap;
  Outcome: uBitmapWorkThread.TBitmapWorkOutcome;
  PostRan: Boolean;
begin
  {Mirrors the file-reference path: even when SaveBitmapToFile fails,
   the post-work fires so any cleanup (delete partial file) can run.
   The current file-reference post-work guards with AOut.Success — this
   test does not assert that policy, only that the post-work hook is
   invoked at all.}
  PostRan := False;
  Bmp := MakeWorkTestBitmap;
  RunBitmapWorkInModal(Bmp, '',
    procedure(AB: Vcl.Graphics.TBitmap; var AOut: uBitmapWorkThread.TBitmapWorkOutcome)
    begin
      AOut.Success := False;
      AOut.ErrorMsg := 'declined';
    end,
    procedure(const AOut: uBitmapWorkThread.TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      PostRan := True;
    end,
    nil, Outcome);
  Assert.IsTrue(PostRan);
end;

{ TTestBuildClipboardCopyFailureMessage }

procedure TTestBuildClipboardCopyFailureMessage.EmptyFormat_ProducesClipboardOpenFailureMessage;
var
  S: string;
begin
  S := BuildClipboardCopyFailureMessage('', False);
  Assert.Contains(S, 'could not open the system clipboard',
    'Empty format name signals a clipboard-open failure; the message must say so');
end;

procedure TTestBuildClipboardCopyFailureMessage.EmptyFormat_IsCombinedViewIrrelevant;
var
  SFrame, SCombined: string;
begin
  {When the failure is at clipboard-open (no specific format), the
   combined-view distinction does not apply — both contexts must yield
   the same message.}
  SFrame := BuildClipboardCopyFailureMessage('', False);
  SCombined := BuildClipboardCopyFailureMessage('', True);
  Assert.AreEqual(SFrame, SCombined,
    'Clipboard-open failure message must not branch on view context');
end;

procedure TTestBuildClipboardCopyFailureMessage.NamedFormat_IncludesFormatNameInOutput;
var
  S: string;
begin
  {The whole point of the failing-format out-param is that the dialog
   names the format the user should disable.}
  S := BuildClipboardCopyFailureMessage('Alpha-aware bitmap', False);
  Assert.Contains(S, 'Alpha-aware bitmap',
    'Failing format name must appear in the dialog body');
end;

procedure TTestBuildClipboardCopyFailureMessage.FrameContext_RemedyDoesNotMentionScaleOrFrameCount;
var
  S: string;
begin
  {Single-frame paths cannot lower the Scale target or reduce frame
   count — those remedies belong to combined-view operations only.}
  S := BuildClipboardCopyFailureMessage('Compressed PNG', False);
  Assert.IsFalse(S.Contains('Scale target'),
    'Frame-context remedy must not suggest lowering Scale target');
  Assert.IsFalse(S.Contains('frame count'),
    'Frame-context remedy must not suggest reducing frame count');
end;

procedure TTestBuildClipboardCopyFailureMessage.CombinedContext_RemedyMentionsScaleAndFrameCount;
var
  S: string;
begin
  S := BuildClipboardCopyFailureMessage('Compressed PNG', True);
  Assert.Contains(S, 'Scale target',
    'Combined-context remedy must suggest lowering Scale target');
  Assert.Contains(S, 'frame count',
    'Combined-context remedy must suggest reducing frame count');
end;

procedure TTestBuildClipboardCopyFailureMessage.BothContexts_MentionClipboardTabAndFileReference;
var
  SFrame, SCombined: string;
begin
  {Both single-frame and combined-view remedies share the two universal
   suggestions: disable the format on the Clipboard tab, or switch on
   the file-reference override. Pin both for both contexts so a remedy
   rewording does not accidentally drop one.}
  SFrame := BuildClipboardCopyFailureMessage('GDI bitmap handle', False);
  SCombined := BuildClipboardCopyFailureMessage('GDI bitmap handle', True);
  Assert.Contains(SFrame, 'Clipboard tab');
  Assert.Contains(SFrame, 'file reference');
  Assert.Contains(SCombined, 'Clipboard tab');
  Assert.Contains(SCombined, 'file reference');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestResolveFrameIndex);
  TDUnitX.RegisterTestFixture(TTestFrameExportRender);
  TDUnitX.RegisterTestFixture(TTestFrameExportSaveIndices);
  TDUnitX.RegisterTestFixture(TTestFrameExportOverrideFrames);
  TDUnitX.RegisterTestFixture(TTestFrameExportGridColumns);
  TDUnitX.RegisterTestFixture(TTestFrameExportScaling);
  TDUnitX.RegisterTestFixture(TTestFrameExportLiveResolution);
  TDUnitX.RegisterTestFixture(TTestFrameExportSaveFramesToDir);
  TDUnitX.RegisterTestFixture(TTestFrameExportClipboardNoOp);
  TDUnitX.RegisterTestFixture(TTestPredictMatchesRender);
  TDUnitX.RegisterTestFixture(TTestRunBitmapWorkInModal);
  TDUnitX.RegisterTestFixture(TTestBuildClipboardCopyFailureMessage);

end.
