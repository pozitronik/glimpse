{ Tests for WCX API type declarations.
  Verifies struct layouts match the Total Commander WCX SDK specification.
  Field order and sizes are critical because mismatches cause silent
  data corruption (e.g. sizes shifted by 32 bits). }
unit TestWcxAPI;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxAPI = class
  public
    { THeaderDataExW layout must match C SDK exactly }
    [Test] procedure ExW_SizeMatchesSDK;
    [Test] procedure ExW_PackSizeBeforePackSizeHigh;
    [Test] procedure ExW_UnpSizeBeforeUnpSizeHigh;
    [Test] procedure ExW_ReservedIs1024Bytes;
    [Test] procedure ExW_FileNameCapacity;
    [Test] procedure ExW_FillCharZeroesAllFields;
    { THeaderData }
    [Test] procedure Header_FieldOrder_UnpSizeAfterPackSize;
    [Test] procedure Header_FileNameCapacity;
    { TWcxDefaultParams }
    [Test] procedure DefaultParams_IniNameCapacityIsMaxPath;
    { Constants }
    [Test] procedure Caps_FlagsArePowersOfTwo;
    [Test] procedure ErrorCodes_UniqueValues;
    {Concurrency: TC may dispatch OpenArchive / ConfigurePacker on different
     threads. The cache mutator must serialise via GCacheLock so two threads
     cannot interleave directory deletion and field assignments.}
    [Test] procedure InvalidateFrameCache_Concurrent_DoesNotCrash;
    {Regression: when DoOpenArchive's body raises after PreExtractFrames has
     populated GCachedVideoFile and GCachedTempDir, the except branch must
     invalidate the cache. Without that, a subsequent OpenArchive on the
     same file finds a stale cache hit and returns paths into a partial /
     deleted directory. The seed helper mimics what PreExtractFrames leaves
     behind; InvalidateFrameCache (called from the except block) wipes it.}
    [Test] procedure InvalidateFrameCache_AfterSeed_ResetsAllFieldsAndDeletesTempDir;
    {Regression: when the temp directory contained a file held by a sharing-
     violating handle (antivirus, another process), TDirectory.Delete raised
     and the exception escaped InvalidateFrameCache. The procedure runs from
     finalization, so an unhandled exception there could crash the host on
     DLL unload. The fix swallows the delete failure and still resets every
     field, leaving a (best-effort) clean state.}
    [Test] procedure InvalidateFrameCache_DeleteFailureSwallowedAndStateReset;
    {ANSI ReadHeader's THeaderData.UnpSize is 32-bit signed; the 64-bit
     EntrySize must be clamped before assignment, otherwise a >2 GB
     combined image wraps into a negative or truncated size in the
     legacy ANSI path. The Wide path splits into UnpSize + UnpSizeHigh
     and is unaffected.}
    [Test] procedure ClampSize_BelowMaxInt_PassesThrough;
    [Test] procedure ClampSize_ExactlyMaxInt_PassesThrough;
    [Test] procedure ClampSize_AboveMaxInt_SaturatesToMaxInt;
    [Test] procedure ClampSize_FiveGigabytes_SaturatesToMaxInt;
    [Test] procedure ClampSize_Negative_PromotedToZero;
    [Test] procedure ClampSize_Zero_PassesThrough;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.Classes, System.SyncObjs,
  uWcxAPI, uWcxExports;

{ THeaderDataExW }

procedure TTestWcxAPI.ExW_SizeMatchesSDK;
const
  { SDK: WCHAR[1024]*2 + 11 ints + char[1024] }
  ExpectedSize = 2 * 1024 * SizeOf(WideChar)
    + 11 * SizeOf(DWORD)
    + 1024 * SizeOf(AnsiChar);
begin
  Assert.AreEqual(ExpectedSize, SizeOf(THeaderDataExW));
end;

procedure TTestWcxAPI.ExW_PackSizeBeforePackSizeHigh;
var
  H: THeaderDataExW;
begin
  { PackSize (low) must precede PackSizeHigh in memory, matching the C struct }
  Assert.IsTrue(NativeUInt(@H.PackSize) < NativeUInt(@H.PackSizeHigh),
    'PackSize must precede PackSizeHigh');
  { They must be adjacent (no padding between them) }
  Assert.AreEqual(NativeUInt(SizeOf(DWORD)),
    NativeUInt(@H.PackSizeHigh) - NativeUInt(@H.PackSize),
    'PackSize and PackSizeHigh must be adjacent');
end;

procedure TTestWcxAPI.ExW_UnpSizeBeforeUnpSizeHigh;
var
  H: THeaderDataExW;
begin
  { UnpSize (low) must precede UnpSizeHigh in memory }
  Assert.IsTrue(NativeUInt(@H.UnpSize) < NativeUInt(@H.UnpSizeHigh),
    'UnpSize must precede UnpSizeHigh');
  Assert.AreEqual(NativeUInt(SizeOf(DWORD)),
    NativeUInt(@H.UnpSizeHigh) - NativeUInt(@H.UnpSize),
    'UnpSize and UnpSizeHigh must be adjacent');
end;

procedure TTestWcxAPI.ExW_ReservedIs1024Bytes;
var
  H: THeaderDataExW;
begin
  FillChar(H, SizeOf(H), 0);
  Assert.AreEqual(1024, SizeOf(H.Reserved));
end;

procedure TTestWcxAPI.ExW_FileNameCapacity;
var
  H: THeaderDataExW;
begin
  FillChar(H, SizeOf(H), 0);
  { SDK: WCHAR FileName[1024] }
  Assert.AreEqual(1024, Length(H.FileName));
end;

procedure TTestWcxAPI.ExW_FillCharZeroesAllFields;
var
  H: THeaderDataExW;
begin
  { FillChar(H, SizeOf(H), 0) must leave all numeric fields at zero.
    This guards against padding or alignment surprises. }
  FillChar(H, SizeOf(H), $FF);
  FillChar(H, SizeOf(H), 0);
  Assert.AreEqual(Integer(0), H.Flags);
  Assert.AreEqual(DWORD(0), H.PackSize);
  Assert.AreEqual(DWORD(0), H.PackSizeHigh);
  Assert.AreEqual(DWORD(0), H.UnpSize);
  Assert.AreEqual(DWORD(0), H.UnpSizeHigh);
  Assert.AreEqual(0, H.FileTime);
  Assert.AreEqual(0, H.FileAttr);
end;

{ THeaderData }

procedure TTestWcxAPI.Header_FieldOrder_UnpSizeAfterPackSize;
var
  H: THeaderData;
begin
  Assert.IsTrue(NativeUInt(@H.UnpSize) > NativeUInt(@H.PackSize),
    'UnpSize must follow PackSize');
  Assert.AreEqual(NativeUInt(SizeOf(Integer)),
    NativeUInt(@H.UnpSize) - NativeUInt(@H.PackSize),
    'PackSize and UnpSize must be adjacent');
end;

procedure TTestWcxAPI.Header_FileNameCapacity;
var
  H: THeaderData;
begin
  FillChar(H, SizeOf(H), 0);
  { SDK: char FileName[260] }
  Assert.AreEqual(260, Length(H.FileName));
end;

{ TWcxDefaultParams }

procedure TTestWcxAPI.DefaultParams_IniNameCapacityIsMaxPath;
var
  P: TWcxDefaultParams;
begin
  FillChar(P, SizeOf(P), 0);
  Assert.AreEqual(MAX_PATH, Length(P.DefaultIniName));
end;

{ Constants }

procedure TTestWcxAPI.Caps_FlagsArePowersOfTwo;

  function IsPowerOfTwo(V: Integer): Boolean;
  begin
    Result := (V > 0) and (V and (V - 1) = 0);
  end;

begin
  { Each capability flag must be a single bit }
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_NEW));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_MODIFY));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_MULTIPLE));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_DELETE));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_OPTIONS));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_MEMPACK));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_BY_CONTENT));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_SEARCHTEXT));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_HIDE));
  Assert.IsTrue(IsPowerOfTwo(PK_CAPS_ENCRYPT));
end;

procedure TTestWcxAPI.ErrorCodes_UniqueValues;
var
  Codes: array of Integer;
  I, J: Integer;
begin
  { All error codes must be distinct }
  Codes := [E_SUCCESS, E_END_ARCHIVE, E_NO_MEMORY, E_BAD_DATA, E_BAD_ARCHIVE,
    E_UNKNOWN_FORMAT, E_EOPEN, E_ECREATE, E_ECLOSE, E_EREAD, E_EWRITE,
    E_NOT_SUPPORTED];
  for I := 0 to Length(Codes) - 2 do
    for J := I + 1 to Length(Codes) - 1 do
      Assert.AreNotEqual(Codes[I], Codes[J],
        Format('Error codes at [%d] and [%d] must differ', [I, J]));
end;

type
  TInvalidateThread = class(TThread)
  strict private
    FStart: TEvent;
    FIterations: Integer;
    FException: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AStart: TEvent; AIterations: Integer);
    property Exc: string read FException;
  end;

constructor TInvalidateThread.Create(AStart: TEvent; AIterations: Integer);
begin
  FStart := AStart;
  FIterations := AIterations;
  inherited Create(False);
end;

procedure TInvalidateThread.Execute;
var
  I: Integer;
begin
  FStart.WaitFor(INFINITE);
  try
    for I := 1 to FIterations do
      InvalidateFrameCache;
  except
    on E: Exception do
      FException := E.ClassName + ': ' + E.Message;
  end;
end;

procedure TTestWcxAPI.InvalidateFrameCache_Concurrent_DoesNotCrash;
const
  THREAD_COUNT = 8;
  ITERATIONS = 200;
var
  Threads: array [0 .. THREAD_COUNT - 1] of TInvalidateThread;
  StartGate: TEvent;
  Handles: array [0 .. THREAD_COUNT - 1] of THandle;
  I: Integer;
  FailureMsg: string;
begin
  {Manual-reset start gate so all threads charge into InvalidateFrameCache
   simultaneously, maximising the chance of contention. Without GCacheLock,
   the directory-delete and field-clear sequence races; with the lock,
   every iteration is atomic and the unit must survive the storm cleanly.}
  StartGate := TEvent.Create(nil, True, False, '');
  try
    for I := 0 to THREAD_COUNT - 1 do
    begin
      Threads[I] := TInvalidateThread.Create(StartGate, ITERATIONS);
      Handles[I] := Threads[I].Handle;
    end;
    StartGate.SetEvent;
    WaitForMultipleObjects(THREAD_COUNT, @Handles[0], True, 30000);

    FailureMsg := '';
    for I := 0 to THREAD_COUNT - 1 do
    begin
      if Threads[I].Exc <> '' then
        FailureMsg := FailureMsg + Format('thread %d: %s; ', [I, Threads[I].Exc]);
      Threads[I].Free;
    end;
    Assert.AreEqual('', FailureMsg,
      'No thread may raise an exception under contention');
  finally
    StartGate.Free;
  end;
end;

procedure TTestWcxAPI.InvalidateFrameCache_AfterSeed_ResetsAllFieldsAndDeletesTempDir;
var
  TempDir: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'wcx_seed_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(TempDir);
  try
    {Mimic PreExtractFrames partial population: globals point to a real
     temp directory holding (in production) some half-written frames.}
    WcxTest_SeedCacheState('C:\fake_video.mp4', TempDir);
    Assert.AreEqual('C:\fake_video.mp4', WcxTest_CachedVideoFile,
      'Sanity: seed populated the video-file slot');
    Assert.AreEqual(TempDir, WcxTest_CachedTempDir,
      'Sanity: seed populated the temp-dir slot');
    Assert.IsTrue(TDirectory.Exists(TempDir));

    {This is what DoOpenArchive's except branch now does. Both fields must
     end up empty and the temp directory must be deleted, otherwise a
     subsequent OpenArchive on the same video would erroneously reuse it.}
    InvalidateFrameCache;

    Assert.AreEqual('', WcxTest_CachedVideoFile,
      'Video-file slot must be empty after invalidation');
    Assert.AreEqual('', WcxTest_CachedTempDir,
      'Temp-dir slot must be empty after invalidation');
    Assert.IsFalse(TDirectory.Exists(TempDir),
      'Temp directory must be deleted by InvalidateFrameCache');
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

procedure TTestWcxAPI.InvalidateFrameCache_DeleteFailureSwallowedAndStateReset;
var
  TempDir: string;
begin
  {Direct simulation of the failure mode the bug report describes:
   TDirectory.Delete raises mid-flight (locked file, antivirus, missing
   permission, race-removed directory, etc.). Because the production
   primitive is hard to make fail deterministically across Delphi RTL
   versions, the unit exposes a test-only injection point. The test
   binds a thrower in place of TDirectory.Delete and asserts:
   1. InvalidateFrameCache does not propagate the exception (finalization-
      safe, the original bug).
   2. Every cache field is still cleared even though the deletion failed.}
  TempDir := TPath.Combine(TPath.GetTempPath, 'wcx_inject_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(TempDir);
  try
    WcxTest_SeedCacheState('C:\fake.mp4', TempDir);
    WcxTest_SetDeleteDirectoryProc(
      procedure(const APath: string)
      begin
        raise EInOutError.Create('simulated delete failure');
      end);
    try
      Assert.WillNotRaise(
        procedure begin InvalidateFrameCache; end,
        nil,
        'InvalidateFrameCache must not propagate delete failures');

      Assert.AreEqual('', WcxTest_CachedVideoFile,
        'Field reset must run even when delete failed');
      Assert.AreEqual('', WcxTest_CachedTempDir);
    finally
      WcxTest_ResetDeleteDirectoryProc;
    end;
  finally
    if TDirectory.Exists(TempDir) then
      TDirectory.Delete(TempDir, True);
  end;
end;

{ -------- ClampSizeForAnsiHeader -------- }

procedure TTestWcxAPI.ClampSize_BelowMaxInt_PassesThrough;
begin
  Assert.AreEqual(1024, ClampSizeForAnsiHeader(1024));
  Assert.AreEqual(1024 * 1024 * 100, ClampSizeForAnsiHeader(1024 * 1024 * 100));
end;

procedure TTestWcxAPI.ClampSize_ExactlyMaxInt_PassesThrough;
begin
  Assert.AreEqual(MaxInt, ClampSizeForAnsiHeader(Int64(MaxInt)));
end;

procedure TTestWcxAPI.ClampSize_AboveMaxInt_SaturatesToMaxInt;
begin
  Assert.AreEqual(MaxInt, ClampSizeForAnsiHeader(Int64(MaxInt) + 1),
    'One past MaxInt must saturate, not wrap to negative');
end;

procedure TTestWcxAPI.ClampSize_FiveGigabytes_SaturatesToMaxInt;
begin
  {Real-world large value: 5 GiB combined image.}
  Assert.AreEqual(MaxInt, ClampSizeForAnsiHeader(Int64(5) * 1024 * 1024 * 1024));
end;

procedure TTestWcxAPI.ClampSize_Negative_PromotedToZero;
begin
  {Defensive clamp: file sizes from disk are non-negative, but if a caller
   ever fed in a negative value (sentinel or computation error), surfacing
   a negative UnpSize would be worse than zero.}
  Assert.AreEqual(0, ClampSizeForAnsiHeader(-1));
  Assert.AreEqual(0, ClampSizeForAnsiHeader(Low(Int64)));
end;

procedure TTestWcxAPI.ClampSize_Zero_PassesThrough;
begin
  Assert.AreEqual(0, ClampSizeForAnsiHeader(0));
end;

end.
