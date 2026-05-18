unit TestClipboardFormatStrategies;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardFormatStrategies = class
  public
    {Factory: BuildClipboardFormatStrategies(ASettings, APngCompression)
     translates the user's per-format toggle record into an ordered array
     of IClipboardFormatStrategy. Order is documented as
     DIBV5 -> PNG -> DIB -> BITMAP and is publicly observable through the
     Name property of each strategy.}
    [Test] procedure Factory_AllTogglesOn_ReturnsFourStrategiesInDocumentedOrder;
    [Test] procedure Factory_AllTogglesOff_ReturnsEmptyArray;
    [Test] procedure Factory_OnlyPngOn_ReturnsSingleCompressedPngStrategy;
    [Test] procedure Factory_MixedToggles_PreservesPublishOrder;

    {PNG strategy specifics. The other three strategies are exercised
     through the existing TestClipboardImage round-trip tests; only the
     PNG strategy gains dedicated coverage here because it is new code
     (the other three are extractions of pre-existing logic).}
    [Test] procedure PngStrategy_AllocateForPf32Bit_Succeeds;
    [Test] procedure PngStrategy_AllocateForPf24Bit_Succeeds;
    [Test] procedure PngStrategy_AllocatedBytesStartWithPngSignature;
    [Test] procedure PngStrategy_DiscardOnEmpty_IsNoOp;
    [Test] procedure PngStrategy_UnpublishedDestructor_DoesNotLeak;

    {Orchestrator behaviour pinned via inline IClipboardFormatStrategy
     mocks. Exercises the contracts the production strategies must obey
     (allocate, publish, discard counts) and verifies the failure-path
     contract: prior allocations are Discarded in reverse order and the
     failing format's Name surfaces via the out-param.}
    [Test] procedure Orchestrator_EmptyStrategyArray_ReturnsTrueAndEmptyError;
    [Test] procedure Orchestrator_NilBitmap_ReturnsFalse;
    [Test] procedure Orchestrator_AllAllocateSucceed_PublishCalledOnEach;
    [Test] procedure Orchestrator_OneAllocateFails_AbortsAndSurfacesFailingName;
    [Test] procedure Orchestrator_OneAllocateFails_DiscardsPriorInReverseOrder;

    {The strategy Name strings appear in the user-facing
     BuildClipboardCopyFailureMessage dialog text and in the Clipboard
     tab's checkbox captions. Pin the strings so renaming triggers a
     test failure and forces a coordinated update of caption, hint, and
     error-message expectations.}
    [Test] procedure StrategyNames_MatchClipboardTabCaptions;
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Classes,
  Winapi.Windows, Vcl.Graphics, Vcl.Clipbrd,
  uClipboardImage, uClipboardFormatStrategies, uSettingsGroups;

{Test helper: opens the system clipboard with the same retry policy
 production code uses (TryClipboardOpenWithRetry). The console DUnitX
 runner has no message pump, so OpenClipboard transiently fails right
 after another opener releases it. Mirrors the helper in
 TestClipboardImage.pas.}
procedure ClipboardOpenWithRetry;
var
  I: Integer;
begin
  for I := 1 to 20 do
  begin
    try
      Clipboard.Open;
      Exit;
    except
      Sleep(10);
    end;
  end;
  Clipboard.Open; {Last attempt — let any remaining exception escape}
end;

{Test helper: minimal pf32bit bitmap with a single colour.}
function MakePf32Bitmap(AWidth, AHeight: Integer;
  AB, AG, AR, AAlpha: Byte): Vcl.Graphics.TBitmap;
var
  X, Y: Integer;
  Row: PByte;
begin
  Result := Vcl.Graphics.TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.AlphaFormat := afDefined;
  Result.SetSize(AWidth, AHeight);
  for Y := 0 to AHeight - 1 do
  begin
    Row := PByte(Result.ScanLine[Y]);
    for X := 0 to AWidth - 1 do
    begin
      Row^ := AB; Inc(Row);
      Row^ := AG; Inc(Row);
      Row^ := AR; Inc(Row);
      Row^ := AAlpha; Inc(Row);
    end;
  end;
end;

{Mock strategy. Records call counts and lets the test pin the
 orchestrator's iteration contract without depending on the system
 clipboard or any specific format's allocation logic.

 ACallLog is a shared TStringList: each method appends a 'name.method'
 line so the test can verify call order across multiple strategy
 instances (e.g. reverse-order Discard).

 The Publish path is intentionally never exercised by the orchestrator
 in failure scenarios; Publish below returns True trivially because no
 test asserts the success-path SetClipboardData outcome.}
type
  TMockStrategy = class(TInterfacedObject, IClipboardFormatStrategy)
  private
    FName: string;
    FAllocateResult: Boolean;
    FAllocateCount, FPublishCount, FDiscardCount: Integer;
    FCallLog: TStringList;
    procedure LogCall(const AMethod: string);
  public
    constructor Create(const AName: string; AAllocateResult: Boolean;
      ACallLog: TStringList);
    function Name: string;
    function Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;
    function Publish: Boolean;
    procedure Discard;
    property AllocateCount: Integer read FAllocateCount;
    property PublishCount: Integer read FPublishCount;
    property DiscardCount: Integer read FDiscardCount;
  end;

constructor TMockStrategy.Create(const AName: string; AAllocateResult: Boolean;
  ACallLog: TStringList);
begin
  inherited Create;
  FName := AName;
  FAllocateResult := AAllocateResult;
  FCallLog := ACallLog;
end;

procedure TMockStrategy.LogCall(const AMethod: string);
begin
  if FCallLog <> nil then
    FCallLog.Add(FName + '.' + AMethod);
end;

function TMockStrategy.Name: string;
begin
  Result := FName;
end;

function TMockStrategy.Allocate(ASrc: Vcl.Graphics.TBitmap; ABackground: TColor): Boolean;
begin
  Inc(FAllocateCount);
  LogCall('Allocate');
  Result := FAllocateResult;
end;

function TMockStrategy.Publish: Boolean;
begin
  Inc(FPublishCount);
  LogCall('Publish');
  Result := True;
end;

procedure TMockStrategy.Discard;
begin
  Inc(FDiscardCount);
  LogCall('Discard');
end;

{ -------- Factory tests -------- }

procedure TTestClipboardFormatStrategies.Factory_AllTogglesOn_ReturnsFourStrategiesInDocumentedOrder;
var
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  Settings := TClipboardFormatsGroup.Defaults; {all True}
  Strategies := BuildClipboardFormatStrategies(Settings, 6);
  Assert.AreEqual(4, Integer(Length(Strategies)), 'All-on must produce four strategies');
  Assert.AreEqual('Alpha-aware bitmap', Strategies[0].Name, 'Slot 0 = CF_DIBV5');
  Assert.AreEqual('Compressed PNG', Strategies[1].Name, 'Slot 1 = PNG');
  Assert.AreEqual('Flattened bitmap for legacy apps', Strategies[2].Name, 'Slot 2 = CF_DIB');
  Assert.AreEqual('GDI bitmap handle', Strategies[3].Name, 'Slot 3 = CF_BITMAP');
end;

procedure TTestClipboardFormatStrategies.Factory_AllTogglesOff_ReturnsEmptyArray;
var
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := False;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);
  Assert.AreEqual(0, Integer(Length(Strategies)),
    'All-off must produce an empty array so the orchestrator silently skips publishing');
end;

procedure TTestClipboardFormatStrategies.Factory_OnlyPngOn_ReturnsSingleCompressedPngStrategy;
var
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := True;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);
  Assert.AreEqual(1, Integer(Length(Strategies)));
  Assert.AreEqual('Compressed PNG', Strategies[0].Name);
end;

procedure TTestClipboardFormatStrategies.Factory_MixedToggles_PreservesPublishOrder;
var
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  {DIBV5 + DIB only — skip PNG and BITMAP. Verifies the factory does
   not collapse adjacent gaps; ordering is by category not by
   array-position contiguity.}
  Settings.PublishAlphaAwareBitmap := True;
  Settings.PublishCompressedPng := False;
  Settings.PublishFlattenedBitmap := True;
  Settings.PublishBitmapHandle := False;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);
  Assert.AreEqual(2, Integer(Length(Strategies)));
  Assert.AreEqual('Alpha-aware bitmap', Strategies[0].Name);
  Assert.AreEqual('Flattened bitmap for legacy apps', Strategies[1].Name);
end;

{ -------- PNG strategy specifics -------- }

procedure TTestClipboardFormatStrategies.PngStrategy_AllocateForPf32Bit_Succeeds;
var
  Bmp: Vcl.Graphics.TBitmap;
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  {Build a one-strategy array via the factory rather than constructing
   the strategy class directly — the class is implementation-private to
   uClipboardFormatStrategies.}
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := True;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);

  Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 128);
  try
    Assert.IsTrue(Strategies[0].Allocate(Bmp, clBlack),
      'PNG strategy must allocate successfully for a small pf32bit source');
  finally
    Bmp.Free;
    Strategies[0].Discard;
  end;
end;

procedure TTestClipboardFormatStrategies.PngStrategy_AllocateForPf24Bit_Succeeds;
var
  Bmp: Vcl.Graphics.TBitmap;
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := True;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);

  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(4, 4);
    Bmp.Canvas.Brush.Color := clRed;
    Bmp.Canvas.FillRect(Rect(0, 0, 4, 4));
    Assert.IsTrue(Strategies[0].Allocate(Bmp, clBlack),
      'PNG strategy must accept pf24bit sources (paste path is alpha-aware but encoder is not picky)');
  finally
    Bmp.Free;
    Strategies[0].Discard;
  end;
end;

procedure TTestClipboardFormatStrategies.PngStrategy_AllocatedBytesStartWithPngSignature;
var
  Bmp: Vcl.Graphics.TBitmap;
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
  PngFormatId: UINT;
  Mem: HGLOBAL;
  Ptr: PByte;
begin
  {End-to-end: allocate via PNG strategy, publish, then read the
   registered PNG format off the clipboard and assert the first byte
   matches the PNG signature (0x89). Catches a regression where
   EncodeBitmapAsPng silently produces non-PNG bytes (e.g. JPEG by
   accident).}
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := True;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);

  Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 255);
  try
    ClipboardOpenWithRetry;
    try
      EmptyClipboard;
      Assert.IsTrue(Strategies[0].Allocate(Bmp, clBlack));
      Assert.IsTrue(Strategies[0].Publish,
        'PNG strategy must publish under the registered PNG format');
    finally
      Clipboard.Close;
    end;
  finally
    Bmp.Free;
  end;

  PngFormatId := RegisterClipboardFormat('PNG');
  Assert.IsTrue(PngFormatId <> 0, 'RegisterClipboardFormat("PNG") must succeed');
  ClipboardOpenWithRetry;
  try
    Mem := GetClipboardData(PngFormatId);
    Assert.IsTrue(Mem <> 0, 'Registered "PNG" format must be present after publish');
    Ptr := PByte(GlobalLock(Mem));
    try
      Assert.IsNotNull(Ptr);
      Assert.AreEqual<Integer>($89, Integer(Ptr^),
        'First byte of the published PNG must be the PNG signature byte ($89)');
    finally
      GlobalUnlock(Mem);
    end;
  finally
    Clipboard.Close;
  end;
end;

procedure TTestClipboardFormatStrategies.PngStrategy_DiscardOnEmpty_IsNoOp;
var
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  {A strategy that has never had Allocate called must accept Discard
   without error. The orchestrator relies on this when an early-index
   Allocate fails — later-index strategies that the loop has not reached
   yet would still have their destructors call Discard via TInterfaced
   refcounting.}
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := True;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);
  Strategies[0].Discard;
  Strategies[0].Discard; {Idempotent}
  Assert.Pass('Repeated Discard on an empty strategy did not raise');
end;

procedure TTestClipboardFormatStrategies.PngStrategy_UnpublishedDestructor_DoesNotLeak;
var
  Bmp: Vcl.Graphics.TBitmap;
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  {Allocate but do not Publish or Discard. The strategy goes out of
   scope when Strategies drops its reference at the end of the procedure.
   The destructor must call Discard internally so the HGLOBAL is freed.
   DUnitX's leak detector catches a regression here.}
  Settings.PublishAlphaAwareBitmap := False;
  Settings.PublishFlattenedBitmap := False;
  Settings.PublishBitmapHandle := False;
  Settings.PublishCompressedPng := True;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);

  Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 128);
  try
    Assert.IsTrue(Strategies[0].Allocate(Bmp, clBlack));
    {Intentionally NOT calling Publish or Discard — destructor must clean up.}
  finally
    Bmp.Free;
  end;
end;

{ -------- Orchestrator behaviour via mock strategies -------- }

procedure TTestClipboardFormatStrategies.Orchestrator_EmptyStrategyArray_ReturnsTrueAndEmptyError;
var
  Bmp: Vcl.Graphics.TBitmap;
  ErrMsg: string;
begin
  Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 255);
  try
    Assert.IsTrue(CopyBitmapToClipboard(Bmp, clBlack, nil, ErrMsg),
      'Empty strategy array must return True (silent skip) per the agreed UX');
    Assert.AreEqual('', ErrMsg,
      'No format failed, so the failing-format out-param must be empty');
  finally
    Bmp.Free;
  end;
end;

procedure TTestClipboardFormatStrategies.Orchestrator_NilBitmap_ReturnsFalse;
var
  ErrMsg: string;
begin
  Assert.IsFalse(CopyBitmapToClipboard(nil, clBlack, nil, ErrMsg),
    'Nil source must fail cleanly without touching the clipboard');
  Assert.AreEqual('', ErrMsg, 'Nil-source path is not a per-strategy failure');
end;

procedure TTestClipboardFormatStrategies.Orchestrator_AllAllocateSucceed_PublishCalledOnEach;
var
  Bmp: Vcl.Graphics.TBitmap;
  M0, M1: TMockStrategy;
  Strategies: TArray<IClipboardFormatStrategy>;
  ErrMsg: string;
  Log: TStringList;
begin
  Log := TStringList.Create;
  try
    M0 := TMockStrategy.Create('Mock0', True, Log);
    M1 := TMockStrategy.Create('Mock1', True, Log);
    Strategies := [M0 as IClipboardFormatStrategy, M1 as IClipboardFormatStrategy];

    Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 255);
    try
      Assert.IsTrue(CopyBitmapToClipboard(Bmp, clBlack, Strategies, ErrMsg));
      Assert.AreEqual(1, M0.AllocateCount, 'M0.Allocate called once');
      Assert.AreEqual(1, M1.AllocateCount, 'M1.Allocate called once');
      Assert.AreEqual(1, M0.PublishCount, 'M0.Publish called once');
      Assert.AreEqual(1, M1.PublishCount, 'M1.Publish called once');
      Assert.AreEqual(0, M0.DiscardCount, 'M0.Discard NOT called on success path');
      Assert.AreEqual(0, M1.DiscardCount, 'M1.Discard NOT called on success path');
      Assert.AreEqual('', ErrMsg, 'Failing-format name is empty on success');
    finally
      Bmp.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TTestClipboardFormatStrategies.Orchestrator_OneAllocateFails_AbortsAndSurfacesFailingName;
var
  Bmp: Vcl.Graphics.TBitmap;
  M0, M1, M2: TMockStrategy;
  Strategies: TArray<IClipboardFormatStrategy>;
  ErrMsg: string;
  Log: TStringList;
begin
  Log := TStringList.Create;
  try
    {M0 OK, M1 fails. M2 must never be reached.}
    M0 := TMockStrategy.Create('Mock0', True, Log);
    M1 := TMockStrategy.Create('FailingMock', False, Log);
    M2 := TMockStrategy.Create('Mock2', True, Log);
    Strategies := [M0 as IClipboardFormatStrategy, M1 as IClipboardFormatStrategy, M2 as IClipboardFormatStrategy];

    Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 255);
    try
      Assert.IsFalse(CopyBitmapToClipboard(Bmp, clBlack, Strategies, ErrMsg),
        'Allocation failure must abort the whole copy');
      Assert.AreEqual('FailingMock', ErrMsg,
        'Out-param must name the failing strategy so the caller can compose an actionable message');
      Assert.AreEqual(1, M0.AllocateCount);
      Assert.AreEqual(1, M1.AllocateCount, 'Failing strategy is still asked to Allocate');
      Assert.AreEqual(0, M2.AllocateCount,
        'Strategies after the failing one must NOT be allocated (early abort)');
      Assert.AreEqual(0, M0.PublishCount, 'Publish never called on the failure path');
      Assert.AreEqual(0, M1.PublishCount);
      Assert.AreEqual(0, M2.PublishCount);
    finally
      Bmp.Free;
    end;
  finally
    Log.Free;
  end;
end;

procedure TTestClipboardFormatStrategies.Orchestrator_OneAllocateFails_DiscardsPriorInReverseOrder;
var
  Bmp: Vcl.Graphics.TBitmap;
  M0, M1, M2, M3: TMockStrategy;
  Strategies: TArray<IClipboardFormatStrategy>;
  ErrMsg: string;
  Log: TStringList;
begin
  Log := TStringList.Create;
  try
    {M0, M1, M2 succeed; M3 fails. Expect Discard on M2 then M1 then M0.}
    M0 := TMockStrategy.Create('M0', True, Log);
    M1 := TMockStrategy.Create('M1', True, Log);
    M2 := TMockStrategy.Create('M2', True, Log);
    M3 := TMockStrategy.Create('M3', False, Log);
    Strategies := [M0 as IClipboardFormatStrategy, M1 as IClipboardFormatStrategy,
                   M2 as IClipboardFormatStrategy, M3 as IClipboardFormatStrategy];

    Bmp := MakePf32Bitmap(4, 4, 0, 200, 0, 255);
    try
      Assert.IsFalse(CopyBitmapToClipboard(Bmp, clBlack, Strategies, ErrMsg));
      Assert.AreEqual(1, M0.DiscardCount);
      Assert.AreEqual(1, M1.DiscardCount);
      Assert.AreEqual(1, M2.DiscardCount);
      Assert.AreEqual(0, M3.DiscardCount,
        'The failing strategy frees its own handle internally; orchestrator must NOT call Discard on it');

      {Verify reverse order via the shared log. Expected suffix:
         M0.Allocate M1.Allocate M2.Allocate M3.Allocate M2.Discard M1.Discard M0.Discard}
      Assert.AreEqual('M0.Allocate', Log[0]);
      Assert.AreEqual('M1.Allocate', Log[1]);
      Assert.AreEqual('M2.Allocate', Log[2]);
      Assert.AreEqual('M3.Allocate', Log[3]);
      Assert.AreEqual('M2.Discard', Log[4], 'Reverse-order discard: M2 first');
      Assert.AreEqual('M1.Discard', Log[5], 'Then M1');
      Assert.AreEqual('M0.Discard', Log[6], 'Then M0');
    finally
      Bmp.Free;
    end;
  finally
    Log.Free;
  end;
end;

{ -------- Strategy name pinning -------- }

procedure TTestClipboardFormatStrategies.StrategyNames_MatchClipboardTabCaptions;
var
  Settings: TClipboardFormatsGroup;
  Strategies: TArray<IClipboardFormatStrategy>;
begin
  {These strings appear in:
     - the Clipboard tab checkbox captions (uSettingsDlg.dfm),
     - the BuildClipboardCopyFailureMessage dialog body (uFrameExport).
   Pin them so a rename triggers a coordinated update across all three
   surfaces rather than a silent dialog/checkbox divergence.}
  Settings := TClipboardFormatsGroup.Defaults;
  Strategies := BuildClipboardFormatStrategies(Settings, 6);
  Assert.AreEqual('Alpha-aware bitmap', Strategies[0].Name);
  Assert.AreEqual('Compressed PNG', Strategies[1].Name);
  Assert.AreEqual('Flattened bitmap for legacy apps', Strategies[2].Name);
  Assert.AreEqual('GDI bitmap handle', Strategies[3].Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardFormatStrategies);

end.
