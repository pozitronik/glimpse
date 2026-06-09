{Coverage for TClipboardPublisher. TTestClipboardPublisher pins the
 user-facing failure message format (pure text, no clipboard).
 TTestClipboardPublisherPublishing drives the publish flows against fake
 clipboard surfaces: the file-reference temp-file bookkeeping (delete the
 fresh file when the clipboard rejects it, replace the previous file on
 success) and the image-path failure routing are deterministic here,
 without ever touching the real Win32 clipboard.

 Not covered: the cancel-after-encode delete. Cancellation requires the
 worker thread to observe the cancel flag mid-work; with a fake runner the
 flag can only flip after the work proc finished, so the path cannot be
 reached deterministically. The generic cancel machinery is covered by
 TestBitmapWorkThread.}
unit TestClipboardPublisher;

interface

uses
  DUnitX.TestFramework,
  Vcl.Graphics,
  ClipboardPublisher, ClipboardImage, ClipboardFileDrop,
  SettingsInterfaces, SettingsGroups, BitmapSaver;

type
  [TestFixture]
  TTestClipboardPublisher = class
  public
    [Test] procedure EmptyFormatReturnsClipboardOpenFailureMessage;
    [Test] procedure EmptyFormatMessageOmitsFormatPlaceholder;
    [Test] procedure CombinedViewIncludesScaleTargetRemedy;
    [Test] procedure CombinedViewIncludesFrameCountRemedy;
    [Test] procedure FrameViewOmitsScaleTargetRemedy;
    [Test] procedure FrameViewIncludesFileReferenceRemedy;
    [Test] procedure FailedFormatNameAppearsInMessage;
  end;

  {Fixed-value IClipboardPolicy; fields are mutated by tests before the
   publish call.}
  TFakeClipboardPolicy = class(TInterfacedObject, IClipboardPolicy)
  public
    Formats: TClipboardFormatsGroup;
    JpegQuality: Integer;
    PngCompression: Integer;
    FileReferenceFormat: TSaveFormat;
    TempFolder: string;
    function GetClipboardFormats: TClipboardFormatsGroup;
    function GetPngCompression: Integer;
    function GetJpegQuality: Integer;
    function GetClipboardFileReferenceFormat: TSaveFormat;
    function GetClipboardTempFolder: string;
  end;

  TFakeFileDropClipboard = class(TInterfacedObject, IFileDropClipboard)
  public
    PutResult: Boolean;
    PutPaths: TArray<string>;
    function PutFilePathOnClipboard(const AFilePath: string): Boolean;
  end;

  TFakeImageClipboard = class(TInterfacedObject, IImageClipboard)
  public
    OpenResult: Boolean;
    OpenCount: Integer;
    AssignCount: Integer;
    EmptyCount: Integer;
    CloseCount: Integer;
    procedure AssignBitmap(ABitmap: Vcl.Graphics.TBitmap);
    function TryOpen: Boolean;
    procedure Empty;
    procedure Close;
  end;

  [TestFixture]
  TTestClipboardPublisherPublishing = class
  strict private
    FTempDir: string;
    FPolicy: TFakeClipboardPolicy;
    FPolicyIntf: IClipboardPolicy;
    FDrop: TFakeFileDropClipboard;
    FDropIntf: IFileDropClipboard;
    FImage: TFakeImageClipboard;
    FImageIntf: IImageClipboard;
    FPublisher: TClipboardPublisher;
    function MakeBitmap(AFormat: TPixelFormat): TBitmap;
    function TempFileCount: Integer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FileReference_Success_PublishesExistingPngFile;
    [Test] procedure FileReference_PublishFailure_DeletesFreshTempFile;
    [Test] procedure FileReference_SecondSuccess_DeletesPreviousTempFile;
    [Test] procedure FileReference_JpegPolicy_WritesJpegTempFile;
    [Test] procedure Image_OpenFailure_FailsWithClipboardStageSentinel;
    [Test] procedure Image_NoStrategiesPf24_AssignsLegacyBitmap;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils, System.Classes;

{ TTestClipboardPublisher }

procedure TTestClipboardPublisher.EmptyFormatReturnsClipboardOpenFailureMessage;
var
  Msg: string;
begin
  {Empty format string is the sentinel for "could not even open the
   clipboard". Message must signal that distinct failure mode so the
   user does not chase format-specific remedies.}
  Msg := BuildClipboardCopyFailureMessage('', False);
  Assert.IsTrue(Pos('could not open the system clipboard', Msg) > 0,
    'must name the open-stage failure');
  Assert.IsTrue(Pos('closing other clipboard-using apps', Msg) > 0,
    'must surface the retry-after-closing-apps hint');
end;

procedure TTestClipboardPublisher.EmptyFormatMessageOmitsFormatPlaceholder;
var
  Msg: string;
begin
  {With no format involved, the message must not leak '[]' or '[%s]'
   placeholders from the Format() template; the empty-format branch
   takes a separate template entirely.}
  Msg := BuildClipboardCopyFailureMessage('', True);
  Assert.IsFalse(Pos('[]', Msg) > 0, 'empty-format branch must not emit empty brackets');
  Assert.IsFalse(Pos('%s', Msg) > 0, 'no unfilled format token');
end;

procedure TTestClipboardPublisher.CombinedViewIncludesScaleTargetRemedy;
var
  Msg: string;
begin
  Msg := BuildClipboardCopyFailureMessage('CF_DIB', True);
  Assert.IsTrue(Pos('Scale target', Msg) > 0,
    'combined view remedy must mention lowering the Scale target');
end;

procedure TTestClipboardPublisher.CombinedViewIncludesFrameCountRemedy;
var
  Msg: string;
begin
  Msg := BuildClipboardCopyFailureMessage('PNG', True);
  Assert.IsTrue(Pos('frame count', Msg) > 0,
    'combined view remedy must mention reducing frame count');
end;

procedure TTestClipboardPublisher.FrameViewOmitsScaleTargetRemedy;
var
  Msg: string;
begin
  {Single-frame view has no Scale target / frame-count knobs; remedy
   must not suggest them or the user will waste time looking.}
  Msg := BuildClipboardCopyFailureMessage('CF_DIB', False);
  Assert.IsFalse(Pos('Scale target', Msg) > 0,
    'frame view remedy must not mention Scale target');
  Assert.IsFalse(Pos('frame count', Msg) > 0,
    'frame view remedy must not mention frame count');
end;

procedure TTestClipboardPublisher.FrameViewIncludesFileReferenceRemedy;
var
  Msg: string;
begin
  Msg := BuildClipboardCopyFailureMessage('PNG', False);
  Assert.IsTrue(Pos('file reference', Msg) > 0,
    'frame view remedy must suggest enabling file reference');
end;

procedure TTestClipboardPublisher.FailedFormatNameAppearsInMessage;
var
  Msg: string;
begin
  {The failing strategy name must appear so the user can find it in the
   settings dialog. Tested separately for both view modes so a future
   message-template refactor cannot silently drop it.}
  Msg := BuildClipboardCopyFailureMessage('CF_HDROP', True);
  Assert.IsTrue(Pos('CF_HDROP', Msg) > 0, 'combined: failed format name must appear');
  Msg := BuildClipboardCopyFailureMessage('CF_HDROP', False);
  Assert.IsTrue(Pos('CF_HDROP', Msg) > 0, 'frame: failed format name must appear');
end;

{ TFakeClipboardPolicy }

function TFakeClipboardPolicy.GetClipboardFormats: TClipboardFormatsGroup;
begin
  Result := Formats;
end;

function TFakeClipboardPolicy.GetPngCompression: Integer;
begin
  Result := PngCompression;
end;

function TFakeClipboardPolicy.GetJpegQuality: Integer;
begin
  Result := JpegQuality;
end;

function TFakeClipboardPolicy.GetClipboardFileReferenceFormat: TSaveFormat;
begin
  Result := FileReferenceFormat;
end;

function TFakeClipboardPolicy.GetClipboardTempFolder: string;
begin
  Result := TempFolder;
end;

{ TFakeFileDropClipboard }

function TFakeFileDropClipboard.PutFilePathOnClipboard(const AFilePath: string): Boolean;
begin
  PutPaths := PutPaths + [AFilePath];
  Result := PutResult;
end;

{ TFakeImageClipboard }

procedure TFakeImageClipboard.AssignBitmap(ABitmap: Vcl.Graphics.TBitmap);
begin
  Inc(AssignCount);
end;

function TFakeImageClipboard.TryOpen: Boolean;
begin
  Inc(OpenCount);
  Result := OpenResult;
end;

procedure TFakeImageClipboard.Empty;
begin
  Inc(EmptyCount);
end;

procedure TFakeImageClipboard.Close;
begin
  Inc(CloseCount);
end;

{ TTestClipboardPublisherPublishing }

procedure TTestClipboardPublisherPublishing.Setup;
begin
  {Unique per-test folder so file-count assertions cannot see another
   test's leftovers; the publisher's resolver creates it on first use.}
  FTempDir := TPath.Combine(TPath.GetTempPath,
    'glimpse_pubtest_' + TGUID.NewGuid.ToString);
  FPolicy := TFakeClipboardPolicy.Create;
  FPolicyIntf := FPolicy;
  FPolicy.Formats := Default(TClipboardFormatsGroup); {all toggles off}
  FPolicy.JpegQuality := 90;
  FPolicy.PngCompression := 6;
  FPolicy.FileReferenceFormat := sfPNG;
  FPolicy.TempFolder := FTempDir;
  FDrop := TFakeFileDropClipboard.Create;
  FDropIntf := FDrop;
  FDrop.PutResult := True;
  FImage := TFakeImageClipboard.Create;
  FImageIntf := FImage;
  FImage.OpenResult := True;
  {No OnAsyncTaskRun: publish flows run synchronously, no UI.}
  FPublisher := TClipboardPublisher.Create(FPolicyIntf, FDropIntf, FImageIntf);
end;

procedure TTestClipboardPublisherPublishing.TearDown;
begin
  FreeAndNil(FPublisher);
  FPolicyIntf := nil;
  FDropIntf := nil;
  FImageIntf := nil;
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestClipboardPublisherPublishing.MakeBitmap(AFormat: TPixelFormat): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := AFormat;
  Result.SetSize(4, 4);
end;

function TTestClipboardPublisherPublishing.TempFileCount: Integer;
begin
  if TDirectory.Exists(FTempDir) then
    Result := Length(TDirectory.GetFiles(FTempDir))
  else
    Result := 0;
end;

procedure TTestClipboardPublisherPublishing.FileReference_Success_PublishesExistingPngFile;
var
  Bmp: TBitmap;
  R: TClipboardPublishResult;
begin
  Bmp := MakeBitmap(pf24bit);
  R := FPublisher.PublishAsFileReference(Bmp);
  Assert.IsTrue(R = cprSuccess, 'publish must succeed');
  Assert.AreEqual(1, Integer(Length(FDrop.PutPaths)), 'exactly one CF_HDROP publish');
  Assert.IsTrue(TFile.Exists(FDrop.PutPaths[0]), 'published temp file must exist on disk');
  Assert.IsTrue(EndsText('.png', FDrop.PutPaths[0]), 'extension must follow the policy format');
  Assert.IsTrue(StartsText(IncludeTrailingPathDelimiter(FTempDir), FDrop.PutPaths[0]),
    'file must land in the configured temp folder');
end;

procedure TTestClipboardPublisherPublishing.FileReference_PublishFailure_DeletesFreshTempFile;
var
  Bmp: TBitmap;
  R: TClipboardPublishResult;
begin
  FDrop.PutResult := False;
  Bmp := MakeBitmap(pf24bit);
  R := FPublisher.PublishAsFileReference(Bmp);
  Assert.IsTrue(R = cprFailed, 'rejected publish must report failure');
  Assert.AreEqual(1, Integer(Length(FDrop.PutPaths)), 'the publish attempt must have happened');
  Assert.AreEqual(0, TempFileCount,
    'the freshly encoded temp file must be deleted when the clipboard rejects it');
end;

procedure TTestClipboardPublisherPublishing.FileReference_SecondSuccess_DeletesPreviousTempFile;
var
  Bmp: TBitmap;
  FirstPath: string;
begin
  Bmp := MakeBitmap(pf24bit);
  Assert.IsTrue(FPublisher.PublishAsFileReference(Bmp) = cprSuccess);
  FirstPath := FDrop.PutPaths[0];

  Bmp := MakeBitmap(pf24bit);
  Assert.IsTrue(FPublisher.PublishAsFileReference(Bmp) = cprSuccess);

  {At most one Glimpse temp lives at a time: the second publish must
   delete the first file and leave only its own.}
  Assert.AreEqual(2, Integer(Length(FDrop.PutPaths)));
  Assert.IsFalse(TFile.Exists(FirstPath), 'previous temp file must be deleted');
  Assert.IsTrue(TFile.Exists(FDrop.PutPaths[1]), 'current temp file must remain');
  Assert.AreEqual(1, TempFileCount);
end;

procedure TTestClipboardPublisherPublishing.FileReference_JpegPolicy_WritesJpegTempFile;
var
  Bmp: TBitmap;
  Bytes: TBytes;
begin
  FPolicy.FileReferenceFormat := sfJPEG;
  Bmp := MakeBitmap(pf24bit);
  Assert.IsTrue(FPublisher.PublishAsFileReference(Bmp) = cprSuccess);
  Assert.IsTrue(EndsText('.jpg', FDrop.PutPaths[0]), 'extension must follow the policy format');
  {JPEG SOI marker pins that the format snapshot reached the encoder.}
  Bytes := TFile.ReadAllBytes(FDrop.PutPaths[0]);
  Assert.IsTrue(Length(Bytes) > 2);
  Assert.AreEqual(Byte($FF), Bytes[0]);
  Assert.AreEqual(Byte($D8), Bytes[1]);
end;

procedure TTestClipboardPublisherPublishing.Image_OpenFailure_FailsWithClipboardStageSentinel;
var
  Bmp: TBitmap;
  R: TClipboardPublishResult;
  ErrorMsg: string;
begin
  {A strategy must be enabled, otherwise the orchestrator never opens
   the clipboard at all.}
  FPolicy.Formats.PublishFlattenedBitmap := True;
  FImage.OpenResult := False;
  Bmp := MakeBitmap(pf32bit);
  R := FPublisher.PublishAsImage(Bmp, clBlack, ErrorMsg);
  Assert.IsTrue(R = cprFailed, 'open failure must surface as cprFailed');
  Assert.AreEqual('', ErrorMsg,
    'open-stage failure uses the empty-format sentinel, not a strategy name');
  Assert.IsTrue(FImage.OpenCount > 0, 'the injected surface must have been asked to open');
end;

procedure TTestClipboardPublisherPublishing.Image_NoStrategiesPf24_AssignsLegacyBitmap;
var
  Bmp: TBitmap;
  R: TClipboardPublishResult;
  ErrorMsg: string;
begin
  {All format toggles off + pf24bit input takes the legacy one-shot
   AssignBitmap path; the orchestrated open/empty/close cycle must not run.}
  Bmp := MakeBitmap(pf24bit);
  R := FPublisher.PublishAsImage(Bmp, clBlack, ErrorMsg);
  Assert.IsTrue(R = cprSuccess, 'legacy path must succeed');
  Assert.AreEqual(1, FImage.AssignCount, 'one AssignBitmap call expected');
  Assert.AreEqual(0, FImage.OpenCount, 'legacy path must not open the clipboard');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardPublisher);
  TDUnitX.RegisterTestFixture(TTestClipboardPublisherPublishing);

end.
