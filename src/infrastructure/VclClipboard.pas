{VCL/Win32 clipboard access: the open-with-retry helper and the
 IImageClipboard adapter used to publish bitmap images.}
unit VclClipboard;

interface

uses
  ClipboardImage;

type
  {Test seam — production passes Clipboard.Open.}
  TClipboardOpenAction = reference to procedure;

{Retries 20 times with 10 ms sleeps; matches only EClipboardException
 so unrelated failures (EAccessViolation/EOutOfMemory) propagate.}
function TryClipboardOpenWithRetry: Boolean; overload;
function TryClipboardOpenWithRetry(const AOpenAction: TClipboardOpenAction): Boolean; overload;

function CreateImageClipboard: IImageClipboard;

implementation

uses
  Winapi.Windows, Vcl.Graphics, Vcl.Clipbrd;

type
  TVclImageClipboard = class(TInterfacedObject, IImageClipboard)
  public
    procedure AssignBitmap(ABitmap: Vcl.Graphics.TBitmap);
    function TryOpen: Boolean;
    procedure Empty;
    procedure Close;
  end;

function TryClipboardOpenWithRetry(const AOpenAction: TClipboardOpenAction): Boolean;
var
  I: Integer;
begin
  {OpenClipboard fails transiently when another opener held it before
   Windows propagated WM_DESTROYCLIPBOARD; common in console DUnitX runs
   without a message pump.}
  for I := 1 to 20 do
  begin
    try
      AOpenAction;
      Exit(True);
    except
      on E: EClipboardException do
        Sleep(10);
    end;
  end;
  Result := False;
end;

function TryClipboardOpenWithRetry: Boolean;
begin
  Result := TryClipboardOpenWithRetry(
    procedure
    begin
      Clipboard.Open;
    end);
end;

{ TVclImageClipboard }

procedure TVclImageClipboard.AssignBitmap(ABitmap: Vcl.Graphics.TBitmap);
begin
  Clipboard.Assign(ABitmap);
end;

function TVclImageClipboard.TryOpen: Boolean;
begin
  Result := TryClipboardOpenWithRetry;
end;

procedure TVclImageClipboard.Empty;
begin
  EmptyClipboard;
end;

procedure TVclImageClipboard.Close;
begin
  Clipboard.Close;
end;

function CreateImageClipboard: IImageClipboard;
begin
  Result := TVclImageClipboard.Create;
end;

end.
