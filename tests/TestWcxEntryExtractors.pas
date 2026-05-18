unit TestWcxEntryExtractors;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxEntryExtractors = class
  public
    { TFrameEntry: size + extract contract }
    [Test] procedure TestFrameEntryFileNameReturnedFromConstructor;
    [Test] procedure TestFrameEntryFrameIndexReturnedFromConstructor;
    [Test] procedure TestFrameEntryReportedSizeReturnsEntrySizesEntry;
    [Test] procedure TestFrameEntryReportedSizeZeroWhenNoCache;
    [Test] procedure TestFrameEntryReportedSizeZeroWhenOutOfRange;
    [Test] procedure TestFrameEntryExtractEmptyPathsReturnsECreate;
    [Test] procedure TestFrameEntryExtractCallsFrameExtractorAndSaver;
    [Test] procedure TestFrameEntryExtractReturnsBadDataOnNilBitmap;
    { TCombinedEntry: size + extract contract }
    [Test] procedure TestCombinedEntryFileNameReturnedFromConstructor;
    [Test] procedure TestCombinedEntryCombinedSlotReturnedFromConstructor;
    [Test] procedure TestCombinedEntryReportedSizeReturnsEntrySizesAtListingIndex;
    [Test] procedure TestCombinedEntryReportedSizeZeroWhenNoCache;
    { TPresetEntry: structural contract only — Extract is exercised via
      its production dependencies in TestWcxPresetExtractor }
    [Test] procedure TestPresetEntryFileNameReturnedFromConstructor;
    [Test] procedure TestPresetEntryPresetIndexReturnedFromConstructor;
    [Test] procedure TestPresetEntryReportedSizeReturnsSourceFileSize;
    [Test] procedure TestPresetEntryReportedSizeIgnoresAListingIndex;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, Vcl.Graphics,
  uTypes, uBitmapSaver, uFrameExtractor, uFrameOffsets, uVideoInfo,
  uWcxAPI, uWcxSettings, uWcxPresets, uWcxEntryExtractors;

type
  {Captures one Save call. Never touches disk so frame/combined extract
   tests are safe in CI where the temp directory may be read-only.}
  TFakeBitmapSaverRouter = class(TInterfacedObject, IBitmapSaverRouter)
  strict private
    FCalled: Boolean;
    FPath: string;
    FFormat: TSaveFormat;
    FJpegQuality: Integer;
    FPngCompression: Integer;
  public
    procedure Save(ABitmap: TBitmap; const APath: string; AFormat: TSaveFormat;
      AJpegQuality, APngCompression: Integer);
    property Called: Boolean read FCalled;
    property Path: string read FPath;
    property Format: TSaveFormat read FFormat;
    property JpegQuality: Integer read FJpegQuality;
    property PngCompression: Integer read FPngCompression;
  end;

  {Returns a deterministic canned bitmap. Records the request so
   tests can pin the offset and path the extractor was asked to read.}
  TFakeFrameExtractor = class(TInterfacedObject, IFrameExtractor)
  strict private
    FReturnNil: Boolean;
    FLastFileName: string;
    FLastTimeOffset: Double;
    FCallCount: Integer;
  public
    constructor Create(AReturnNil: Boolean = False);
    function ExtractFrame(const AFileName: string; ATimeOffset: Double;
      const AOptions: TExtractionOptions; ACancelHandle: THandle = 0): TBitmap;
    property LastFileName: string read FLastFileName;
    property LastTimeOffset: Double read FLastTimeOffset;
    property CallCount: Integer read FCallCount;
  end;

  {Lightweight stub of IWcxExtractionContext for entry tests. Owns the
   TWcxSettings instance it builds so the test fixture does not leak.
   Field-backed getters keep the tests' arrange step trivial.}
  TFakeContext = class(TInterfacedObject, IWcxExtractionContext)
  strict private
    FFileName: string;
    FFFmpegPath: string;
    FSourceFileSize: Int64;
    FSettings: TWcxSettings;
    FOffsets: TFrameOffsetArray;
    FPresets: TWcxPresetArray;
    FVideoInfo: TVideoInfo;
    FTempPaths: TArray<string>;
    FEntrySizes: TArray<Int64>;
    FProcessDataProc: TProcessDataProc;
    FProcessDataProcW: TProcessDataProcW;
    FFrameExtractor: IFrameExtractor;
    FBitmapSaver: IBitmapSaverRouter;
  public
    constructor Create;
    destructor Destroy; override;
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

    procedure SetFileName(const AValue: string);
    procedure SetFFmpegPath(const AValue: string);
    procedure SetSourceFileSize(AValue: Int64);
    procedure SetOffsets(const AValue: TFrameOffsetArray);
    procedure SetPresets(const AValue: TWcxPresetArray);
    procedure SetEntrySizes(const AValue: TArray<Int64>);
    procedure SetTempPaths(const AValue: TArray<string>);
    procedure SetFrameExtractor(const AValue: IFrameExtractor);
    procedure SetBitmapSaver(const AValue: IBitmapSaverRouter);
  end;

{ TFakeBitmapSaverRouter }

procedure TFakeBitmapSaverRouter.Save(ABitmap: TBitmap; const APath: string;
  AFormat: TSaveFormat; AJpegQuality, APngCompression: Integer);
begin
  FCalled := True;
  FPath := APath;
  FFormat := AFormat;
  FJpegQuality := AJpegQuality;
  FPngCompression := APngCompression;
end;

{ TFakeFrameExtractor }

constructor TFakeFrameExtractor.Create(AReturnNil: Boolean);
begin
  inherited Create;
  FReturnNil := AReturnNil;
end;

function TFakeFrameExtractor.ExtractFrame(const AFileName: string; ATimeOffset: Double;
  const AOptions: TExtractionOptions; ACancelHandle: THandle): TBitmap;
begin
  Inc(FCallCount);
  FLastFileName := AFileName;
  FLastTimeOffset := ATimeOffset;
  if FReturnNil then
    Exit(nil);
  Result := TBitmap.Create;
  Result.SetSize(8, 8);
end;

{ TFakeContext }

constructor TFakeContext.Create;
begin
  inherited Create;
  FSettings := TWcxSettings.Create('');
  {Defaults match the production constructor: PNG with mid-quality
   knobs so frame/combined save calls land deterministic values that
   the assertions can pin.}
  FSettings.ResetDefaults;
end;

destructor TFakeContext.Destroy;
begin
  FSettings.Free;
  inherited;
end;

function TFakeContext.GetFileName: string;
begin
  Result := FFileName;
end;

function TFakeContext.GetFFmpegPath: string;
begin
  Result := FFFmpegPath;
end;

function TFakeContext.GetSourceFileSize: Int64;
begin
  Result := FSourceFileSize;
end;

function TFakeContext.GetSettings: TWcxSettings;
begin
  Result := FSettings;
end;

function TFakeContext.GetOffsets: TFrameOffsetArray;
begin
  Result := FOffsets;
end;

function TFakeContext.GetPresets: TWcxPresetArray;
begin
  Result := FPresets;
end;

function TFakeContext.GetVideoInfo: TVideoInfo;
begin
  Result := FVideoInfo;
end;

function TFakeContext.GetTempPaths: TArray<string>;
begin
  Result := FTempPaths;
end;

function TFakeContext.GetEntrySizes: TArray<Int64>;
begin
  Result := FEntrySizes;
end;

function TFakeContext.GetProcessDataProc: TProcessDataProc;
begin
  Result := FProcessDataProc;
end;

function TFakeContext.GetProcessDataProcW: TProcessDataProcW;
begin
  Result := FProcessDataProcW;
end;

function TFakeContext.GetFrameExtractor: IFrameExtractor;
begin
  Result := FFrameExtractor;
end;

function TFakeContext.GetBitmapSaver: IBitmapSaverRouter;
begin
  Result := FBitmapSaver;
end;

procedure TFakeContext.SetFileName(const AValue: string);
begin
  FFileName := AValue;
end;

procedure TFakeContext.SetFFmpegPath(const AValue: string);
begin
  FFFmpegPath := AValue;
end;

procedure TFakeContext.SetSourceFileSize(AValue: Int64);
begin
  FSourceFileSize := AValue;
end;

procedure TFakeContext.SetOffsets(const AValue: TFrameOffsetArray);
begin
  FOffsets := AValue;
end;

procedure TFakeContext.SetPresets(const AValue: TWcxPresetArray);
begin
  FPresets := AValue;
end;

procedure TFakeContext.SetEntrySizes(const AValue: TArray<Int64>);
begin
  FEntrySizes := AValue;
end;

procedure TFakeContext.SetTempPaths(const AValue: TArray<string>);
begin
  FTempPaths := AValue;
end;

procedure TFakeContext.SetFrameExtractor(const AValue: IFrameExtractor);
begin
  FFrameExtractor := AValue;
end;

procedure TFakeContext.SetBitmapSaver(const AValue: IBitmapSaverRouter);
begin
  FBitmapSaver := AValue;
end;

function MakeOffsets(ACount: Integer): TFrameOffsetArray;
var
  I: Integer;
begin
  SetLength(Result, ACount);
  for I := 0 to ACount - 1 do
  begin
    Result[I].Index := I + 1;
    Result[I].TimeOffset := (I + 1) * 5.0;
  end;
end;

{ TFrameEntry }

procedure TTestWcxEntryExtractors.TestFrameEntryFileNameReturnedFromConstructor;
var
  Entry: IWcxEntryExtractor;
begin
  Entry := TFrameEntry.Create('frame_001.png', 0);
  Assert.AreEqual('frame_001.png', Entry.FileName);
end;

procedure TTestWcxEntryExtractors.TestFrameEntryFrameIndexReturnedFromConstructor;
var
  Entry: TFrameEntry;
begin
  Entry := TFrameEntry.Create('frame_007.png', 7);
  try
    Assert.AreEqual(7, Entry.FrameIndex);
  finally
    {Constructed as a bare class instance; no interface refcount holds
     this one, so a manual Free keeps the leak detector quiet.}
    Entry.Free;
  end;
end;

procedure TTestWcxEntryExtractors.TestFrameEntryReportedSizeReturnsEntrySizesEntry;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetEntrySizes(TArray<Int64>.Create(1024, 2048, 4096));
  Entry := TFrameEntry.Create('frame.png', 0);
  Assert.AreEqual(Int64(2048), Entry.ReportedSize(ICtx, 1));
end;

procedure TTestWcxEntryExtractors.TestFrameEntryReportedSizeZeroWhenNoCache;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  {EntrySizes nil (ShowFileSizes off) — must surface as 0 instead of a
   range-check trap.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Entry := TFrameEntry.Create('frame.png', 0);
  Assert.AreEqual(Int64(0), Entry.ReportedSize(ICtx, 0));
end;

procedure TTestWcxEntryExtractors.TestFrameEntryReportedSizeZeroWhenOutOfRange;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  {AListingIndex >= Length(EntrySizes) — guard the bounds.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetEntrySizes(TArray<Int64>.Create(100));
  Entry := TFrameEntry.Create('frame.png', 0);
  Assert.AreEqual(Int64(0), Entry.ReportedSize(ICtx, 5));
end;

procedure TTestWcxEntryExtractors.TestFrameEntryExtractEmptyPathsReturnsECreate;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  {Both ADestPath and ADestName empty: nowhere to write — must return
   E_ECREATE, not crash on an empty join.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetOffsets(MakeOffsets(1));
  Entry := TFrameEntry.Create('frame.png', 0);
  Assert.AreEqual(E_ECREATE, Entry.Extract(ICtx, '', ''));
end;

procedure TTestWcxEntryExtractors.TestFrameEntryExtractCallsFrameExtractorAndSaver;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
  FrameExtractor: TFakeFrameExtractor;
  Saver: TFakeBitmapSaverRouter;
  IFrameExtr: IFrameExtractor;
  ISaver: IBitmapSaverRouter;
  Status: Integer;
begin
  {Verifies the Extract path goes through both seams: the frame
   extractor is asked at the entry's offset, and the saver receives a
   non-empty destination path. Save format / quality / compression are
   pulled from Settings (defaults) so the assertions pin those too.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetFileName('C:\v\sample.mkv');
  Ctx.SetOffsets(MakeOffsets(2));
  FrameExtractor := TFakeFrameExtractor.Create;
  IFrameExtr := FrameExtractor;
  Saver := TFakeBitmapSaverRouter.Create;
  ISaver := Saver;
  Ctx.SetFrameExtractor(IFrameExtr);
  Ctx.SetBitmapSaver(ISaver);

  Entry := TFrameEntry.Create('frame_001.png', 0);
  Status := Entry.Extract(ICtx, 'C:\out', '');
  Assert.AreEqual(E_SUCCESS, Status);
  Assert.AreEqual(1, FrameExtractor.CallCount, 'Frame extractor should be invoked once');
  Assert.AreEqual('C:\v\sample.mkv', FrameExtractor.LastFileName);
  Assert.AreEqual(5.0, FrameExtractor.LastTimeOffset, 0.001);
  Assert.IsTrue(Saver.Called, 'Bitmap saver should be invoked');
  Assert.AreEqual(Ctx.GetSettings.SaveFormat, Saver.Format);
end;

procedure TTestWcxEntryExtractors.TestFrameEntryExtractReturnsBadDataOnNilBitmap;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
  IFrameExtr: IFrameExtractor;
  ISaver: IBitmapSaverRouter;
begin
  {ExtractFrame returning nil (ffmpeg failure path) maps to E_BAD_DATA
   per the prior DoExtractSeparate contract.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetFileName('C:\v\bad.mkv');
  Ctx.SetOffsets(MakeOffsets(1));
  IFrameExtr := TFakeFrameExtractor.Create(True);
  ISaver := TFakeBitmapSaverRouter.Create;
  Ctx.SetFrameExtractor(IFrameExtr);
  Ctx.SetBitmapSaver(ISaver);

  Entry := TFrameEntry.Create('frame.png', 0);
  Assert.AreEqual(E_BAD_DATA, Entry.Extract(ICtx, 'C:\out', ''));
end;

{ TCombinedEntry }

procedure TTestWcxEntryExtractors.TestCombinedEntryFileNameReturnedFromConstructor;
var
  Entry: IWcxEntryExtractor;
begin
  Entry := TCombinedEntry.Create('combined.jpg', 5);
  Assert.AreEqual('combined.jpg', Entry.FileName);
end;

procedure TTestWcxEntryExtractors.TestCombinedEntryCombinedSlotReturnedFromConstructor;
var
  Entry: TCombinedEntry;
begin
  Entry := TCombinedEntry.Create('combined.jpg', 5);
  try
    Assert.AreEqual(5, Entry.CombinedSlot);
  finally
    Entry.Free;
  end;
end;

procedure TTestWcxEntryExtractors.TestCombinedEntryReportedSizeReturnsEntrySizesAtListingIndex;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  {ReportedSize indexes EntrySizes by the listing position (TC's
   iteration index), not by the per-entry combined slot. This split is
   intentional and matches the cache layout.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetEntrySizes(TArray<Int64>.Create(1, 2, 3, 4));
  Entry := TCombinedEntry.Create('combined.jpg', 0);
  Assert.AreEqual(Int64(3), Entry.ReportedSize(ICtx, 2));
end;

procedure TTestWcxEntryExtractors.TestCombinedEntryReportedSizeZeroWhenNoCache;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Entry := TCombinedEntry.Create('combined.jpg', 0);
  Assert.AreEqual(Int64(0), Entry.ReportedSize(ICtx, 0));
end;

{ TPresetEntry — structural only; behavioural coverage lives in
  TestWcxPresetExtractor. }

procedure TTestWcxEntryExtractors.TestPresetEntryFileNameReturnedFromConstructor;
var
  Entry: IWcxEntryExtractor;
begin
  Entry := TPresetEntry.Create('Movie_audio.mp3', 0);
  Assert.AreEqual('Movie_audio.mp3', Entry.FileName);
end;

procedure TTestWcxEntryExtractors.TestPresetEntryPresetIndexReturnedFromConstructor;
var
  Entry: TPresetEntry;
begin
  Entry := TPresetEntry.Create('preset.out', 4);
  try
    Assert.AreEqual(4, Entry.PresetIndex);
  finally
    Entry.Free;
  end;
end;

procedure TTestWcxEntryExtractors.TestPresetEntryReportedSizeReturnsSourceFileSize;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  {Preset reports SourceFileSize as the synthetic UnpSize regardless of
   EntrySizes: output size is unknown in advance, and using the source
   size gives the progress bridge a meaningful denominator.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetSourceFileSize(123456);
  Ctx.SetEntrySizes(TArray<Int64>.Create(999));
  Entry := TPresetEntry.Create('preset.out', 0);
  Assert.AreEqual(Int64(123456), Entry.ReportedSize(ICtx, 0));
end;

procedure TTestWcxEntryExtractors.TestPresetEntryReportedSizeIgnoresAListingIndex;
var
  Ctx: TFakeContext;
  ICtx: IWcxExtractionContext;
  Entry: IWcxEntryExtractor;
begin
  {Same result regardless of AListingIndex — preset's size is not keyed
   by listing position.}
  Ctx := TFakeContext.Create;
  ICtx := Ctx;
  Ctx.SetSourceFileSize(777);
  Entry := TPresetEntry.Create('preset.out', 0);
  Assert.AreEqual(Int64(777), Entry.ReportedSize(ICtx, 0));
  Assert.AreEqual(Int64(777), Entry.ReportedSize(ICtx, 999));
  Assert.AreEqual(Int64(777), Entry.ReportedSize(ICtx, -1));
end;

initialization

TDUnitX.RegisterTestFixture(TTestWcxEntryExtractors);

end.
