{Tests for TFrameSaver.SaveFramesToDir, the dialog-free leaf of the save
 pipeline. SaveFrame / SaveFrames / SaveView end in a modal save dialog
 and are verified manually in the running plugin.}
unit TestFrameSaver;

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Settings, FrameView, ExportTargetResolver, SaveDialogPresenter,
  FrameRenderPipeline, FrameSaver;

type
  [TestFixture]
  TTestSaveFramesToDir = class
  strict private
    FTempDir: string;
    FForm: TForm;
    FSettings: TPluginSettings;
    FView: TFrameView;
    FResolver: TExportTargetResolver;
    FSaveDialog: TSaveDialogPresenter;
    FRenderPipeline: TFrameRenderPipeline;
    FSaver: TFrameSaver;
    function CountFiles(const APattern: string): Integer;
    {Builds a TFrameSaver over a fresh frame view with ACellCount cells and
     the listed indices loaded. Everything is freed in TearDown.}
    procedure BuildSaver(ACellCount: Integer; const ALoadedIndices: array of Integer);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;

    {SaveFramesToDir iterates loaded cells (or selected loaded cells when
     ASelectedOnly is True), formats per-frame names, and writes each
     through BitmapSaver. Tests verify the file count, selection filtering
     and the placeholder-skip rule.}
    [Test] procedure SavesAllLoadedFramesAsSeparateFiles;
    [Test] procedure SkipsPlaceholderCells;
    [Test] procedure SelectedOnly_OnlyWritesSelectedLoadedCells;
    [Test] procedure NoSelectedAndSelectedOnly_WritesNothing;
    [Test] procedure FormatExtensionMatchesArgument;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  Vcl.Graphics,
  BitmapSaver, FrameOffsets;

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
    {pf24bit: TFrameView.SetFrame's contract.}
    Bmp := TBitmap.Create;
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(160, 90);
    Result.SetFrame(ALoadedIndices[I], Bmp);
  end;
end;

procedure TTestSaveFramesToDir.Setup;
begin
  FTempDir := IncludeTrailingPathDelimiter(
    TPath.Combine(TPath.GetTempPath, 'VT_FrameSaverDir_' + TGuid.NewGuid.ToString));
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestSaveFramesToDir.TearDown;
begin
  FreeAndNil(FSaver);
  FreeAndNil(FRenderPipeline);
  FreeAndNil(FSaveDialog);
  FreeAndNil(FResolver);
  FreeAndNil(FSettings);
  FreeAndNil(FForm);
  if (FTempDir <> '') and TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestSaveFramesToDir.BuildSaver(ACellCount: Integer; const ALoadedIndices: array of Integer);
begin
  FForm := TForm.CreateNew(nil);
  FView := CreateTestFrameView(FForm, ACellCount, ALoadedIndices);
  {Non-existent INI path: settings use defaults.}
  FSettings := TPluginSettings.Create('__nonexistent__.ini');
  FResolver := TExportTargetResolver.Create(FView);
  FSaveDialog := TSaveDialogPresenter.Create(FSettings);
  FRenderPipeline := TFrameRenderPipeline.Create(FView, FSettings, FSettings, FSettings, FSettings);
  FSaver := TFrameSaver.Create(FView, FSettings, FResolver, FSaveDialog, FRenderPipeline);
end;

function TTestSaveFramesToDir.CountFiles(const APattern: string): Integer;
begin
  Result := Length(TDirectory.GetFiles(FTempDir, APattern));
end;

procedure TTestSaveFramesToDir.SavesAllLoadedFramesAsSeparateFiles;
begin
  {3 cells, all loaded.}
  BuildSaver(3, [0, 1, 2]);
  FSaver.SaveFramesToDir(FTempDir, sfPNG, False, 'video.mp4');
  Assert.AreEqual(3, CountFiles('*.png'), 'Every loaded cell must produce a PNG');
end;

procedure TTestSaveFramesToDir.SkipsPlaceholderCells;
begin
  {5 cells, only 2 loaded (indices 0 and 3); the rest are placeholders.}
  BuildSaver(5, [0, 3]);
  FSaver.SaveFramesToDir(FTempDir, sfPNG, False, 'video.mp4');
  Assert.AreEqual(2, CountFiles('*.png'), 'Placeholder cells must be skipped');
end;

procedure TTestSaveFramesToDir.SelectedOnly_OnlyWritesSelectedLoadedCells;
begin
  BuildSaver(4, [0, 1, 2, 3]);
  FView.ToggleSelection(1);
  FView.ToggleSelection(3);
  FSaver.SaveFramesToDir(FTempDir, sfPNG, True, 'video.mp4');
  Assert.AreEqual(2, CountFiles('*.png'), 'Only selected loaded cells must be saved');
end;

procedure TTestSaveFramesToDir.NoSelectedAndSelectedOnly_WritesNothing;
begin
  BuildSaver(3, [0, 1, 2]);
  FSaver.SaveFramesToDir(FTempDir, sfPNG, True, 'video.mp4');
  Assert.AreEqual(0, CountFiles('*.png'),
    'ASelectedOnly with no selection writes nothing; production callers gate with SelectedCount>0 first');
end;

procedure TTestSaveFramesToDir.FormatExtensionMatchesArgument;
begin
  BuildSaver(2, [0, 1]);
  FSaver.SaveFramesToDir(FTempDir, sfJPEG, False, 'video.mp4');
  Assert.AreEqual(2, CountFiles('*.jpg'),
    'AFormat=sfJPEG must produce .jpg files via GenerateFrameFileName');
  Assert.AreEqual(0, CountFiles('*.png'), 'No .png files must be produced when AFormat=sfJPEG');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSaveFramesToDir);

end.
