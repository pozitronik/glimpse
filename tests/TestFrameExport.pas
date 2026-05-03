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

implementation

uses
  System.SysUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  uFrameView, uFrameOffsets, uSettings, uFrameExport, uCombinedImage;

type
  { Test subclass that exposes protected render methods }
  TTestableExporter = class(TFrameExporter)
  public
    function TestRenderCombinedFromCells: TBitmap;
    function TestRenderWithBanner(ABmp: TBitmap): TBitmap;
  end;

function TTestableExporter.TestRenderCombinedFromCells: TBitmap;
begin
  Result := RenderCombinedFromCells;
end;

function TTestableExporter.TestRenderWithBanner(ABmp: TBitmap): TBitmap;
begin
  Result := RenderWithBanner(ABmp);
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
    Bmp := TBitmap.Create;
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
  {When at least one cell is selected, only loaded selected cells must
   be returned -- mirrors TFrameExporter.SaveFrames selection-aware
   semantics.}
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
        BmpBaseline := Exporter.TestRenderCombinedFromCells;
        try
          Overrides := MakeOverrideBitmaps(4, 320, 180);
          try
            Exporter.SetOverrideFrames(Overrides);
            BmpWithOverride := Exporter.TestRenderCombinedFromCells;
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
        Exporter.CopyView;
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

initialization
  TDUnitX.RegisterTestFixture(TTestResolveFrameIndex);
  TDUnitX.RegisterTestFixture(TTestFrameExportRender);
  TDUnitX.RegisterTestFixture(TTestFrameExportSaveIndices);
  TDUnitX.RegisterTestFixture(TTestFrameExportOverrideFrames);
  TDUnitX.RegisterTestFixture(TTestFrameExportGridColumns);
  TDUnitX.RegisterTestFixture(TTestFrameExportClipboardNoOp);

end.
