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
    { RenderFrameView }
    [Test] procedure TestRenderFrameViewProducesBitmap;
    [Test] procedure TestRenderFrameViewMatchesViewportSize;

    { RenderWithBanner }
    [Test] procedure TestRenderWithBannerDisabledReturnsSameSize;
    [Test] procedure TestRenderWithBannerEnabledIncreasesHeight;
    [Test] procedure TestRenderWithBannerEmptyInfoReturnsSameSize;
    [Test] procedure TestRenderWithBannerFreesInput;
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
    function TestRenderFrameView: TBitmap;
    function TestRenderWithBanner(ABmp: TBitmap): TBitmap;
  end;

function TTestableExporter.TestRenderFrameView: TBitmap;
begin
  Result := RenderFrameView;
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

procedure TTestFrameExportRender.TestRenderFrameViewProducesBitmap;
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
    View.Width := 800;
    View.Height := 600;
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderFrameView;
        try
          Assert.IsNotNull(Bmp, 'RenderFrameView must return a bitmap');
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

procedure TTestFrameExportRender.TestRenderFrameViewMatchesViewportSize;
var
  Form: TForm;
  View: TFrameView;
  Settings: TPluginSettings;
  Exporter: TTestableExporter;
  Bmp: TBitmap;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 2, [0, 1]);
    View.Width := 640;
    View.Height := 480;
    Settings := CreateSettingsWithBanner(False);
    try
      Exporter := TTestableExporter.Create(View, Settings);
      try
        Bmp := Exporter.TestRenderFrameView;
        try
          Assert.AreEqual(640, Bmp.Width, 'Bitmap width must match control width');
          Assert.AreEqual(480, Bmp.Height, 'Bitmap height must match control height');
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
        Exporter.CopyFrameToClipboard(-1);
        Exporter.CopyFrameToClipboard(0);
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
        Exporter.CopyFrameToClipboard(1);
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
        Exporter.CopyAllToClipboard;
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
  TDUnitX.RegisterTestFixture(TTestFrameExportClipboardNoOp);

end.
