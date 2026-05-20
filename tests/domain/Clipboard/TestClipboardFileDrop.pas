unit TestClipboardFileDrop;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestClipboardFileDrop = class
  public
    [Test] procedure BuildDropFilesHandle_EmptyReturnsZero;
    [Test] procedure BuildDropFilesHandle_HappyPath;
    [Test] procedure BuildDropFilesHandle_IsWideAndDoubleNullTerminated;
    [Test] procedure CreateFileDropClipboard_ReturnsLiveInterface;
    [Test] procedure PutFilePathOnClipboard_EmptyPath_ReturnsFalse;
  end;

implementation

uses
  Winapi.Windows, Winapi.ShlObj,
  ClipboardFileDrop;

procedure TTestClipboardFileDrop.BuildDropFilesHandle_EmptyReturnsZero;
begin
  Assert.AreEqual<NativeUInt>(0, BuildDropFilesHandle(''),
    'Empty path is a programmer error in the caller; helper signals via 0 rather than allocating a degenerate DROPFILES');
end;

procedure TTestClipboardFileDrop.BuildDropFilesHandle_HappyPath;
const
  PATH = 'C:\Temp\sample.png';
var
  H: NativeUInt;
  Drop: PDropFiles;
begin
  H := BuildDropFilesHandle(PATH);
  try
    Assert.AreNotEqual<NativeUInt>(0, H);
    Drop := GlobalLock(H);
    try
      Assert.AreEqual<DWORD>(SizeOf(TDropFiles), Drop^.pFiles,
        'pFiles must point at the start of the file list (right after the header)');
      Assert.IsTrue(Drop^.fWide,
        'fWide=True signals Unicode payload to paste targets');
      Assert.AreEqual<Integer>(0, Drop^.pt.x);
      Assert.AreEqual<Integer>(0, Drop^.pt.y);
    finally
      GlobalUnlock(H);
    end;
  finally
    GlobalFree(H);
  end;
end;

procedure TTestClipboardFileDrop.BuildDropFilesHandle_IsWideAndDoubleNullTerminated;
const
  PATH = 'D:\Glimpse\out.png';
var
  H: NativeUInt;
  Drop: PDropFiles;
  PathStart: PChar;
  ReadBack: string;
begin
  H := BuildDropFilesHandle(PATH);
  try
    Drop := GlobalLock(H);
    try
      PathStart := PChar(NativeUInt(Drop) + Drop^.pFiles);
      SetString(ReadBack, PathStart, Length(PATH));
      Assert.AreEqual(PATH, ReadBack,
        'Wide path written verbatim immediately after the DROPFILES header');
      Assert.AreEqual<Word>(0, Word(PathStart[Length(PATH)]),
        'First null terminates the path');
      Assert.AreEqual<Word>(0, Word(PathStart[Length(PATH) + 1]),
        'Second null terminates the file list - required by CF_HDROP contract');
    finally
      GlobalUnlock(H);
    end;
  finally
    GlobalFree(H);
  end;
end;

procedure TTestClipboardFileDrop.CreateFileDropClipboard_ReturnsLiveInterface;
var
  Clip: IFileDropClipboard;
begin
  Clip := CreateFileDropClipboard;
  Assert.IsTrue(Assigned(Clip),
    'Factory must return a usable IFileDropClipboard, never nil');
end;

procedure TTestClipboardFileDrop.PutFilePathOnClipboard_EmptyPath_ReturnsFalse;
begin
  {Empty path is rejected by the guard before any clipboard call, so this
   exercises the interface method without touching the system clipboard.}
  Assert.IsFalse(CreateFileDropClipboard.PutFilePathOnClipboard(''),
    'Empty path must fail fast and not open the clipboard');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClipboardFileDrop);

end.
