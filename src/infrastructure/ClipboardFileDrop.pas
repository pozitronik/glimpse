{CF_HDROP "paste as file reference" clipboard helpers.}
unit ClipboardFileDrop;

interface

type
  {Publishes a file path to the system clipboard as CF_HDROP, so paste
   targets receive a file reference rather than image bytes.}
  IFileDropClipboard = interface
    ['{9B4D1E7A-2C68-4F35-A0D9-7E3B5C81F406}']
    {Returns False on clipboard-open failure, empty path, or HGLOBAL failure.}
    function PutFilePathOnClipboard(const AFilePath: string): Boolean;
  end;

{Returns 0 on GlobalAlloc failure. No clipboard side effects.}
function BuildDropFilesHandle(const AFilePath: string): NativeUInt;

{Reads the first path from the clipboard's CF_HDROP entry, or '' when the
 clipboard holds no file drop. The temp-file sweep uses this to never delete
 the file the user has copied but not yet pasted (the clipboard holds at most
 one entry, so this protects the one file that matters across instances).}
function GetClipboardFilePath: string;

function CreateFileDropClipboard: IFileDropClipboard;

implementation

uses
  Winapi.Windows, Winapi.ShlObj, Winapi.ShellAPI, Vcl.Clipbrd, VclClipboard;

type
  TFileDropClipboard = class(TInterfacedObject, IFileDropClipboard)
  public
    function PutFilePathOnClipboard(const AFilePath: string): Boolean;
  end;

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

{ TFileDropClipboard }

function TFileDropClipboard.PutFilePathOnClipboard(const AFilePath: string): Boolean;
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

function GetClipboardFilePath: string;
var
  Drop: HDROP;
  Len: UINT;
  Buf: array of Char;
begin
  Result := '';
  {Raw open/close (not the VCL Clipboard) keeps this a side-effect-free
   read with no interaction with the VCL clipboard open-refcount.}
  if not OpenClipboard(0) then
    Exit;
  try
    Drop := HDROP(GetClipboardData(CF_HDROP));
    if Drop = 0 then
      Exit;
    {Probe the path length (excluding terminator); 0 = empty drop.}
    Len := DragQueryFile(Drop, 0, nil, 0);
    if Len = 0 then
      Exit;
    SetLength(Buf, Len + 1);
    DragQueryFile(Drop, 0, @Buf[0], Len + 1);
    Result := PChar(@Buf[0]);
  finally
    CloseClipboard;
  end;
end;

function CreateFileDropClipboard: IFileDropClipboard;
begin
  Result := TFileDropClipboard.Create;
end;

end.
