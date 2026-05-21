{Tests for TFrameCopier's guard-rail no-op paths. The real clipboard-copy
 flows touch the VCL Clipboard and a modal error dialog, so they are
 verified manually in the running plugin; only the early-return guards
 (empty view, unloaded cell) are headlessly testable.}
unit TestFrameCopier;

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Settings, FrameView, ExportTargetResolver, ClipboardPublisher,
  FrameRenderPipeline, FrameCopier;

type
  [TestFixture]
  TTestFrameCopierNoOp = class
  strict private
    FForm: TForm;
    FSettings: TPluginSettings;
    FView: TFrameView;
    FResolver: TExportTargetResolver;
    FClipboardPublisher: TClipboardPublisher;
    FRenderPipeline: TFrameRenderPipeline;
    FCopier: TFrameCopier;
    {Builds a TFrameCopier over a fresh frame view with ACellCount cells and
     the listed indices loaded. Everything is freed in TearDown.}
    procedure BuildCopier(ACellCount: Integer; const ALoadedIndices: array of Integer);
  public
    [TearDown] procedure TearDown;

    {Copy* must bail at the CellCount=0 / ResolveFrameIndex-False guard
     before touching the VCL Clipboard - otherwise a headless environment
     throws from inside the guard. Reaching the end without an exception
     is the assertion.}
    [Test] procedure CopyFrame_EmptyView_NoException;
    [Test] procedure CopyFrame_UnloadedCell_NoException;
    [Test] procedure CopyView_EmptyView_NoException;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Graphics,
  FrameOffsets;

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

procedure TTestFrameCopierNoOp.BuildCopier(ACellCount: Integer; const ALoadedIndices: array of Integer);
begin
  FForm := TForm.CreateNew(nil);
  FView := CreateTestFrameView(FForm, ACellCount, ALoadedIndices);
  {Non-existent INI path: settings use defaults.}
  FSettings := TPluginSettings.Create('__nonexistent__.ini');
  FResolver := TExportTargetResolver.Create(FView);
  FClipboardPublisher := TClipboardPublisher.Create(FSettings);
  FRenderPipeline := TFrameRenderPipeline.Create(FView, FSettings, FSettings, FSettings, FSettings);
  FCopier := TFrameCopier.Create(FView, FSettings, FResolver, FClipboardPublisher, FRenderPipeline);
end;

procedure TTestFrameCopierNoOp.TearDown;
begin
  FreeAndNil(FCopier);
  FreeAndNil(FRenderPipeline);
  FreeAndNil(FClipboardPublisher);
  FreeAndNil(FResolver);
  FreeAndNil(FSettings);
  FreeAndNil(FForm);
end;

procedure TTestFrameCopierNoOp.CopyFrame_EmptyView_NoException;
begin
  {Zero cells: ResolveFrameIndex returns False, CopyFrame exits early.}
  BuildCopier(0, []);
  FCopier.CopyFrame(-1);
  FCopier.CopyFrame(0);
end;

procedure TTestFrameCopierNoOp.CopyFrame_UnloadedCell_NoException;
begin
  {Cells exist but none are loaded: ResolveFrameIndex returns False and
   CopyFrame exits before the Clipboard call. Same contract as the empty
   view, exercised through a different branch.}
  BuildCopier(3, []);
  FCopier.CopyFrame(1);
end;

procedure TTestFrameCopierNoOp.CopyView_EmptyView_NoException;
begin
  {Zero cells: CopyView's CellCount guard exits before the Clipboard call.}
  BuildCopier(0, []);
  FCopier.CopyView(FSettings.SaveAtLiveResolution);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFrameCopierNoOp);

end.
