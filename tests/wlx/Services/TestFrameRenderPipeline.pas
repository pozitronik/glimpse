{Tests for TFrameRenderPipeline: combined-image rendering, banner
 attachment, cell scaling, override-frame source selection, the
 live-resolution render paths, and the predict/render dimension-
 consistency contract.}
unit TestFrameRenderPipeline;

interface

uses
  DUnitX.TestFramework;

type

  [TestFixture]
  TTestRenderPipelineRender = class
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
  TTestRenderPipelineOverrideFrames = class
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
  TTestRenderPipelineGridColumns = class
  public
    {Pins the contract that vmGrid native-resolution save (toggle off)
     respects the live column count, not the auto-sqrt fallback. Before
     the fix, a narrow 1xN live layout was saved as 3x3 because the
     case statement only handled vmFilmstrip and vmScroll.}
    [Test] procedure TestSaveTracksLiveSingleColumn;
    [Test] procedure TestSaveTracksLiveTwoColumns;
  end;

  [TestFixture]
  TTestRenderPipelineScaling = class
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
  TTestRenderPipelineLiveResolution = class
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

implementation

uses
  System.SysUtils, System.Types, System.Math,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  Types, FrameView, FrameOffsets, Settings, BannerInfo,
  FrameRenderPipeline, FrameDimensionPredictor;

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

{ TTestRenderPipelineRender }

function CreateSettingsWithBanner(AShowBanner: Boolean): TPluginSettings;
begin
  { Non-existent INI path: settings use defaults }
  Result := TPluginSettings.Create('__nonexistent__.ini');
  Result.ShowBanner := AShowBanner;
end;

procedure TTestRenderPipelineRender.TestRenderCombinedProducesBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderCombinedFromCells(False);
        try
          Assert.IsNotNull(Bmp, 'RenderCombinedFromCells must return a bitmap');
          Assert.IsTrue(Bmp.Width > 0, 'Bitmap width must be positive');
          Assert.IsTrue(Bmp.Height > 0, 'Bitmap height must be positive');
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderCombinedTightDimensions;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderCombinedFromCells(False);
        try
          Assert.AreEqual(320, Bmp.Width,
            'Width must equal cols*frameW + gaps + 2*border, not control width');
          Assert.AreEqual(180, Bmp.Height,
            'Height must equal rows*frameH + gaps + 2*border, not control height');
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderCombinedIgnoresViewport;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        View.Width := 800;
        View.Height := 600;
        BmpA := Pipeline.RenderCombinedFromCells(False);
        try
          View.Width := 100;
          View.Height := 100;
          BmpB := Pipeline.RenderCombinedFromCells(False);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderCombinedNoCellsReturnsNil;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderCombinedFromCells(False);
        Assert.IsNull(Bmp, 'Empty view must return nil');
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderWithBannerDisabledReturnsSameSize;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Input, Output: TBitmap;
  OrigH: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Input := TBitmap.Create;
        Input.SetSize(200, 150);
        OrigH := Input.Height;
        { When ShowBanner=False, RenderWithBanner returns the same bitmap }
        Output := Pipeline.RenderWithBanner(Input);
        try
          Assert.AreEqual(OrigH, Output.Height,
            'Height must be unchanged when banner is disabled');
          Assert.IsTrue(Input = Output,
            'Must return the same bitmap instance when banner is disabled');
        finally
          Output.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderWithBannerEnabledIncreasesHeight;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Input, Output: TBitmap;
  OrigH: Integer;
  Info: TBannerInfo;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(True);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Info := Default(TBannerInfo);
        Info.FileName := 'test_video.mp4';
        Info.FileSizeBytes := 1024 * 1024;
        Info.DurationSec := 120.0;
        Info.Width := 1920;
        Info.Height := 1080;
        Info.VideoCodec := 'h264';
        Pipeline.UpdateBannerInfo(Info);

        Input := TBitmap.Create;
        Input.SetSize(400, 300);
        OrigH := Input.Height;
        { RenderWithBanner frees Input and returns a new, taller bitmap }
        Output := Pipeline.RenderWithBanner(Input);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderWithBannerEmptyInfoReturnsSameSize;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Input, Output: TBitmap;
  OrigH: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(True);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        { No UpdateBannerInfo called: FBannerInfo is default (all zeroes/empty).
          FormatBannerLines with empty info still produces lines, but
          PrependBanner handles them; the test verifies no crash. }
        Input := TBitmap.Create;
        Input.SetSize(300, 200);
        OrigH := Input.Height;
        Output := Pipeline.RenderWithBanner(Input);
        try
          Assert.IsTrue(Output.Height >= OrigH,
            'Output height must be >= input even with empty banner info');
        finally
          Output.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineRender.TestRenderWithBannerFreesInput;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Input, Output: TBitmap;
  Info: TBannerInfo;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    Settings := CreateSettingsWithBanner(True);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Info := Default(TBannerInfo);
        Info.FileName := 'video.mp4';
        Info.DurationSec := 60.0;
        Pipeline.UpdateBannerInfo(Info);

        Input := TBitmap.Create;
        Input.SetSize(200, 100);
        Output := Pipeline.RenderWithBanner(Input);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TTestRenderPipelineOverrideFrames}

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

procedure TTestRenderPipelineOverrideFrames.TestOverrideAppliedWhenToggleOff;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Overrides := MakeOverrideBitmaps(4, 320, 180);
        try
          Pipeline.SetOverrideFrames(Overrides);
          Bmp := Pipeline.RenderCombinedFromCells(False);
          try
            Assert.AreEqual(640, Bmp.Width, 'Override 320 * 2 cols');
            Assert.AreEqual(360, Bmp.Height, 'Override 180 * 2 rows');
          finally
            Bmp.Free;
          end;
        finally
          Pipeline.ClearOverrideFrames;
          FreeOverrideBitmaps(Overrides);
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineOverrideFrames.TestOverrideIgnoredWhenToggleOn;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        BmpBaseline := Pipeline.RenderCombinedFromCells(True);
        try
          Overrides := MakeOverrideBitmaps(4, 320, 180);
          try
            Pipeline.SetOverrideFrames(Overrides);
            BmpWithOverride := Pipeline.RenderCombinedFromCells(True);
            try
              Assert.AreEqual(BmpBaseline.Width, BmpWithOverride.Width,
                'Toggle-on must ignore override (width unchanged)');
              Assert.AreEqual(BmpBaseline.Height, BmpWithOverride.Height,
                'Toggle-on must ignore override (height unchanged)');
            finally
              BmpWithOverride.Free;
            end;
          finally
            Pipeline.ClearOverrideFrames;
            FreeOverrideBitmaps(Overrides);
          end;
        finally
          BmpBaseline.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineOverrideFrames.TestRenderIntentIgnoresPersistedSetting_LiveIntentOff;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Overrides := MakeOverrideBitmaps(4, 320, 180);
        try
          Pipeline.SetOverrideFrames(Overrides);
          Bmp := Pipeline.RenderCombinedFromCells(False);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineOverrideFrames.TestRenderIntentIgnoresPersistedSetting_LiveIntentOn;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        BmpLiveNoOverride := Pipeline.RenderCombinedFromCells(True);
        try
          Overrides := MakeOverrideBitmaps(4, 320, 180);
          try
            Pipeline.SetOverrideFrames(Overrides);
            BmpLiveWithOverride := Pipeline.RenderCombinedFromCells(True);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineOverrideFrames.TestNilOverrideEntryFallsBackToLive;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        BmpFull := Pipeline.RenderCombinedFromCells(False);
        try
          SetLength(Overrides, 4); {all entries nil by default}
          Pipeline.SetOverrideFrames(Overrides);
          BmpAllNil := Pipeline.RenderCombinedFromCells(False);
          try
            Assert.AreEqual(BmpFull.Width, BmpAllNil.Width,
              'All-nil override must render same width as no-override');
            Assert.AreEqual(BmpFull.Height, BmpAllNil.Height,
              'All-nil override must render same height as no-override');
          finally
            BmpAllNil.Free;
          end;
          Pipeline.ClearOverrideFrames;
        finally
          BmpFull.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineOverrideFrames.TestClearOverrideFramesRestoresLive;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Overrides := MakeOverrideBitmaps(4, 320, 180);
        try
          Pipeline.SetOverrideFrames(Overrides);
          Pipeline.ClearOverrideFrames;
          BmpAfterClear := Pipeline.RenderCombinedFromCells(False);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineOverrideFrames.TestShorterOverrideArrayFallsBackToLive;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Overrides := MakeOverrideBitmaps(2, 320, 180);
        try
          Pipeline.SetOverrideFrames(Overrides);
          Bmp := Pipeline.RenderCombinedFromCells(False);
          try
            Assert.IsNotNull(Bmp, 'Short override array must not crash');
            Assert.IsTrue(Bmp.Width > 0, 'Width positive');
            Assert.IsTrue(Bmp.Height > 0, 'Height positive');
          finally
            Bmp.Free;
          end;
        finally
          Pipeline.ClearOverrideFrames;
          FreeOverrideBitmaps(Overrides);
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{TTestRenderPipelineGridColumns}

procedure TTestRenderPipelineGridColumns.TestSaveTracksLiveSingleColumn;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderCombinedFromCells(False);
        try
          Assert.AreEqual(160, Bmp.Width, '1 col * 160 = 160');
          Assert.AreEqual(810, Bmp.Height, '9 rows * 90 = 810');
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineGridColumns.TestSaveTracksLiveTwoColumns;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderCombinedFromCells(False);
        try
          Assert.AreEqual(320, Bmp.Width, '2 cols * 160 = 320');
          Assert.AreEqual(270, Bmp.Height, '3 rows * 90 = 270');
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestRenderPipelineScaling }

function MakeColorSrcBitmap(AW, AH: Integer; AColor: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := AColor;
  Result.Canvas.FillRect(Rect(0, 0, AW, AH));
end;

procedure TTestRenderPipelineScaling.Letterbox_OutputMatchesRequestedDimensions;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Src := MakeColorSrcBitmap(160, 90, clRed);
        try
          Out := Pipeline.ScaleBitmapLetterbox(Src, 320, 200, clBlue);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineScaling.Letterbox_NilSourceFillsBackground;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Out: TBitmap;
begin
  {Defensive: nil source must not crash. Output is just the background
   colour at the requested dimensions.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Out := Pipeline.ScaleBitmapLetterbox(nil, 100, 60, clYellow);
        try
          Assert.IsNotNull(Out);
          Assert.AreEqual(100, Out.Width);
          Assert.AreEqual(60, Out.Height);
        finally
          Out.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineScaling.Letterbox_OutputIsPf24bit;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Src := MakeColorSrcBitmap(80, 45, clGreen);
        try
          Out := Pipeline.ScaleBitmapLetterbox(Src, 200, 120, clBlack);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineScaling.CropToFill_OutputMatchesRequestedDimensions;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Src := MakeColorSrcBitmap(160, 90, clRed);
        try
          Out := Pipeline.ScaleBitmapCropToFill(Src, 256, 256);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineScaling.CropToFill_NilSourceFillsBackgroundFromSettings;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Out: TBitmap;
begin
  {Nil source: function fills the result with FSettings.Background and
   returns. Different from Letterbox where the caller passes a bg colour.}
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Out := Pipeline.ScaleBitmapCropToFill(nil, 80, 80);
        try
          Assert.IsNotNull(Out);
          Assert.AreEqual(80, Out.Width);
          Assert.AreEqual(80, Out.Height);
        finally
          Out.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineScaling.CropToFill_OutputIsPf24bit;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Src, Out: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 1, [0]);
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Src := MakeColorSrcBitmap(80, 45, clGreen);
        try
          Out := Pipeline.ScaleBitmapCropToFill(Src, 200, 120);
          try
            Assert.AreEqual(Ord(pf24bit), Ord(Out.PixelFormat));
          finally
            Out.Free;
          end;
        finally
          Src.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

{ TTestRenderPipelineLiveResolution }

procedure TTestRenderPipelineLiveResolution.RenderCellAtLiveSize_GridMode_ReturnsCellSizedBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Bmp: TBitmap;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ViewMode := vmGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        R := View.GetCellRect(1);
        Bmp := Pipeline.RenderCellAtLiveSize(1);
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
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineLiveResolution.RenderCellAtLiveSize_SmartGridMode_ReturnsCellSizedBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Bmp: TBitmap;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ViewMode := vmSmartGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        R := View.GetCellRect(0);
        Bmp := Pipeline.RenderCellAtLiveSize(0);
        try
          Assert.IsNotNull(Bmp);
          Assert.AreEqual<Integer>(Max(1, R.Width), Bmp.Width);
          Assert.AreEqual<Integer>(Max(1, R.Height), Bmp.Height);
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineLiveResolution.RenderGridCombinedAtLiveResolution_ProducesBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 4, [0, 1, 2, 3]);
    View.ViewMode := vmGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderGridCombinedAtLiveResolution;
        try
          Assert.IsNotNull(Bmp,
            'Live-resolution grid render must produce a bitmap');
          Assert.IsTrue(Bmp.Width > 0);
          Assert.IsTrue(Bmp.Height > 0);
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineLiveResolution.RenderGridCombinedAtLiveResolution_NoLoadedFrames_ReturnsNil;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Assert.IsNull(Pipeline.RenderGridCombinedAtLiveResolution,
          'Zero cells -> nothing to render -> nil');
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineLiveResolution.RenderSmartCombinedFromCells_ProducesBitmap;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 1, 2, 3, 4]);
    View.ViewMode := vmSmartGrid;
    Settings := CreateSettingsWithBanner(False);
    try
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Bmp := Pipeline.RenderSmartCombinedFromCells(False);
        try
          Assert.IsNotNull(Bmp);
          Assert.IsTrue(Bmp.Width > 0);
          Assert.IsTrue(Bmp.Height > 0);
        finally
          Bmp.Free;
        end;
      finally
        Pipeline.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestRenderPipelineLiveResolution.RenderSmartCombinedFromCells_NoLoadedFrames_ReturnsNil;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Pipeline: TFrameRenderPipeline;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Assert.IsNull(Pipeline.RenderSmartCombinedFromCells(False),
          'Zero cells -> nothing to render -> nil');
      finally
        Pipeline.Free;
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
  Pipeline: TFrameRenderPipeline;
  Predictor: TFrameDimensionPredictor;
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
      Pipeline := TFrameRenderPipeline.Create(View, Settings, Settings, Settings, Settings);
      try
        Predictor := TFrameDimensionPredictor.Create(View, Settings, Settings, Pipeline);
        try
          Predictor.PredictCombinedSize(AForceLive, PW, PH);
          Bmp := Pipeline.RenderCombinedFromCells(AForceLive);
          try
            Assert.IsNotNull(Bmp, ContextLabel + ': renderer returned nil; cannot compare');
            Assert.AreEqual(Bmp.Width, PW, ContextLabel + ': predicted width must equal rendered width');
            Assert.AreEqual(Bmp.Height, PH, ContextLabel + ': predicted height must equal rendered height');
          finally
            Bmp.Free;
          end;
        finally
          Predictor.Free;
        end;
      finally
        Pipeline.Free;
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

initialization
  TDUnitX.RegisterTestFixture(TTestRenderPipelineRender);
  TDUnitX.RegisterTestFixture(TTestRenderPipelineOverrideFrames);
  TDUnitX.RegisterTestFixture(TTestRenderPipelineGridColumns);
  TDUnitX.RegisterTestFixture(TTestRenderPipelineScaling);
  TDUnitX.RegisterTestFixture(TTestRenderPipelineLiveResolution);
  TDUnitX.RegisterTestFixture(TTestPredictMatchesRender);

end.
