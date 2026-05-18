{CF_HDROP "paste as file reference" helpers.

 Packages a single file path into the DROPFILES + wide-char-path +
 double-null layout the shell expects, and publishes it on the clipboard
 so paste targets that accept dropped files (most image editors, Office,
 browsers, chat apps) can read the file from disk on paste.

 Unrelated to the bitmap-format strategies in uClipboardFormatStrategies
 and the bitmap orchestrator in uClipboardImage — kept in its own unit so
 the layout can be unit-tested without dragging the bitmap publish path
 into the test fixture.}
unit uClipboardFileDrop;

interface

{Allocates a moveable HGLOBAL containing the DROPFILES header plus the
 wide-character file path and required trailing double-null terminator,
 ready to hand to SetClipboardData(CF_HDROP, ...). Returns 0 on
 GlobalAlloc failure. Pure / no clipboard side effects so the layout
 can be unit-tested in isolation.}
function BuildDropFilesHandle(const AFilePath: string): NativeUInt;

{Publishes AFilePath as a single-item CF_HDROP entry on the clipboard.
 Paste targets that accept dropped files (most image editors, Office,
 browsers, chat apps) will read the file from disk. Other paste
 targets will silently ignore the entry. Returns False on clipboard
 open failure, empty path, or HGLOBAL allocation failure.}
function PutFilePathOnClipboard(const AFilePath: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ShlObj, Vcl.Clipbrd, uClipboardImage;

function BuildDropFilesHandle(const AFilePath: string): NativeUInt;
var
  Drop: PDropFiles;
  PathBytes, TotalBytes: NativeUInt;
  Dest: PChar;
begin
  Result := 0;
  if AFilePath = '' then
    Exit;
  {DROPFILES is followed by the wide-character file path, then a
   double-null terminator (one null for the path, one to end the list).
   Reusing the same Unicode string the rest of Delphi works in means
   fWide=True; the system reads code units literally.}
  PathBytes := (Length(AFilePath) + 2) * SizeOf(Char);
  TotalBytes := SizeOf(TDropFiles) + PathBytes;
  Result := GlobalAlloc(GMEM_MOVEABLE, TotalBytes);
  if Result = 0 then
    Exit;
  Drop := GlobalLock(Result);
  if Drop = nil then
  begin
    GlobalFree(Result);
    Result := 0;
    Exit;
  end;
  try
    Drop^.pFiles := SizeOf(TDropFiles);
    Drop^.pt.x := 0;
    Drop^.pt.y := 0;
    Drop^.fNC := False;
    Drop^.fWide := True;
    Dest := PChar(NativeUInt(Drop) + SizeOf(TDropFiles));
    Move(AFilePath[1], Dest^, Length(AFilePath) * SizeOf(Char));
    Dest[Length(AFilePath)] := #0;
    Dest[Length(AFilePath) + 1] := #0;
  finally
    GlobalUnlock(Result);
  end;
end;

function PutFilePathOnClipboard(const AFilePath: string): Boolean;
var
  H: NativeUInt;
begin
  Result := False;
  if AFilePath = '' then
    Exit;
  H := BuildDropFilesHandle(AFilePath);
  if H = 0 then
    Exit;
  if not TryClipboardOpenWithRetry then
  begin
    GlobalFree(H);
    Exit;
  end;
  try
    Clipboard.Clear;
    {SetClipboardData transfers ownership to the system when it succeeds;
     on failure we still own the HGLOBAL and must free it.}
    if SetClipboardData(CF_HDROP, H) = 0 then
    begin
      GlobalFree(H);
      Exit;
    end;
    Result := True;
  finally
    Clipboard.Close;
  end;
end;

end.
