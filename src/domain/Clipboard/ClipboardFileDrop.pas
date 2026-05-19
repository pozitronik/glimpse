{CF_HDROP "paste as file reference" helpers.}
unit ClipboardFileDrop;

interface

{Returns 0 on GlobalAlloc failure. No clipboard side effects.}
function BuildDropFilesHandle(const AFilePath: string): NativeUInt;

{Returns False on clipboard-open failure, empty path, or HGLOBAL failure.}
function PutFilePathOnClipboard(const AFilePath: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ShlObj, Vcl.Clipbrd, ClipboardImage;

function BuildDropFilesHandle(const AFilePath: string): NativeUInt;
var
  Drop: PDropFiles;
  PathBytes, TotalBytes: NativeUInt;
  Dest: PChar;
begin
  Result := 0;
  if AFilePath = '' then
    Exit;
  {DROPFILES + wide path + double-null terminator (path-end + list-end).}
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
    {On SetClipboardData failure we still own H and must free it.}
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
