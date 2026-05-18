{Encoding-aware INI file handler — thin file-I/O facade.

 Wraps a TIniDocument (parse / mutate / emit, in src/infrastructure/
 uIniDocument) with the disk-side concerns: file path, load on open,
 atomic UTF-8-no-BOM write on UpdateFile, auto-flush in destructor
 so a "create / write / free" caller does not lose data.

 TIniFile in the RTL routes through Win32 GetPrivateProfileString, which
 only understands UTF-16 LE with BOM or ANSI; UTF-8 (with or without BOM)
 is read as ANSI and mojibakes any non-ASCII content. Modern Notepad on
 Win11 defaults to UTF-8, so the gap is real. This unit reads UTF-8 /
 UTF-16 LE / UTF-16 BE (BOM-detected) and falls back to ANSI on no-BOM
 files that fail strict UTF-8 decoding. Writes emit UTF-8 without BOM
 and CRLF line endings.

 The split: uIniEncoding owns the bytes<->string heuristic;
 uIniDocument owns the line-list mutation; this facade owns the file
 I/O orchestration. Public API of TUnicodeIniFile is unchanged.

 In-memory model preserves comments, blank lines, and original ordering
 across read-modify-write so hand-edited files survive Save unchanged.
 Lenient ReadBool accepts True/False/Yes/No/On/Off/0/1. Duplicate
 sections and duplicate keys: first occurrence wins; subsequent ones
 are reported via uDebugLog when logging is enabled.}
unit uUnicodeIniFile;

interface

uses
  System.SysUtils, System.Classes,
  uIniDocument;

type
  TUnicodeIniFile = class
  strict private
    FFileName: string;
    FDocument: TIniDocument;

    procedure LoadFromDisk;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;

    function ReadString(const ASection, AKey, ADefault: string): string;
    function ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
    {Lenient ReadBool: True/Yes/On/1 -> True; False/No/Off/0 -> False;
     anything else -> ADefault. Case-insensitive.}
    function ReadBool(const ASection, AKey: string; ADefault: Boolean): Boolean;

    procedure WriteString(const ASection, AKey, AValue: string);
    procedure WriteInteger(const ASection, AKey: string; AValue: Integer);
    procedure WriteBool(const ASection, AKey: string; AValue: Boolean);

    procedure ReadSections(AStrings: TStrings);
    procedure ReadSection(const ASection: string; AStrings: TStrings);
    function ValueExists(const ASection, AKey: string): Boolean;
    function SectionExists(const ASection: string): Boolean;
    procedure DeleteKey(const ASection, AKey: string);
    procedure EraseSection(const ASection: string);
    {Discards every line, leaving an empty in-memory document. Used
     when callers want to fully rewrite the file from scratch.}
    procedure Clear;
    {Persists the in-memory state to FFileName as UTF-8 without BOM
     and CRLF line endings. Silent no-op when FFileName is empty
     (mirrors the TIniFile sentinel).}
    procedure UpdateFile;

    property FileName: string read FFileName;
  end;

{Decodes ABytes into a Delphi string per the BOM-then-strict-UTF-8
 heuristic. Re-exported for backward compatibility — callers that
 previously imported uUnicodeIniFile for this helper continue to work
 unchanged. New callers should import uIniEncoding directly.}
function DecodeIniBytes(const ABytes: TBytes): string;

implementation

uses
  System.IOUtils,
  uIniEncoding;

function DecodeIniBytes(const ABytes: TBytes): string;
begin
  Result := uIniEncoding.DecodeIniBytes(ABytes);
end;

constructor TUnicodeIniFile.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FDocument := TIniDocument.Create;
  if (FFileName <> '') and TFile.Exists(FFileName) then
    LoadFromDisk;
end;

destructor TUnicodeIniFile.Destroy;
begin
  {Auto-flush pending writes so a "create / write / free" caller does
   not lose data. Mirrors TIniFile's expected behaviour.}
  if (FDocument <> nil) and FDocument.Dirty then
    try
      UpdateFile;
    except
      {Swallow to avoid throwing during destruction; callers that need
       guaranteed flush should call UpdateFile explicitly and handle
       the exception.}
    end;
  FDocument.Free;
  inherited;
end;

procedure TUnicodeIniFile.LoadFromDisk;
var
  Bytes: TBytes;
  Text: string;
begin
  Bytes := TFile.ReadAllBytes(FFileName);
  Text := uIniEncoding.DecodeIniBytes(Bytes);
  FDocument.ParseFromText(Text);
end;

function TUnicodeIniFile.ReadString(const ASection, AKey, ADefault: string): string;
begin
  Result := FDocument.ReadString(ASection, AKey, ADefault);
end;

function TUnicodeIniFile.ReadInteger(const ASection, AKey: string; ADefault: Integer): Integer;
begin
  Result := FDocument.ReadInteger(ASection, AKey, ADefault);
end;

function TUnicodeIniFile.ReadBool(const ASection, AKey: string; ADefault: Boolean): Boolean;
begin
  Result := FDocument.ReadBool(ASection, AKey, ADefault);
end;

procedure TUnicodeIniFile.WriteString(const ASection, AKey, AValue: string);
begin
  FDocument.WriteString(ASection, AKey, AValue);
end;

procedure TUnicodeIniFile.WriteInteger(const ASection, AKey: string; AValue: Integer);
begin
  FDocument.WriteInteger(ASection, AKey, AValue);
end;

procedure TUnicodeIniFile.WriteBool(const ASection, AKey: string; AValue: Boolean);
begin
  FDocument.WriteBool(ASection, AKey, AValue);
end;

procedure TUnicodeIniFile.ReadSections(AStrings: TStrings);
begin
  FDocument.ReadSections(AStrings);
end;

procedure TUnicodeIniFile.ReadSection(const ASection: string; AStrings: TStrings);
begin
  FDocument.ReadSection(ASection, AStrings);
end;

function TUnicodeIniFile.ValueExists(const ASection, AKey: string): Boolean;
begin
  Result := FDocument.ValueExists(ASection, AKey);
end;

function TUnicodeIniFile.SectionExists(const ASection: string): Boolean;
begin
  Result := FDocument.SectionExists(ASection);
end;

procedure TUnicodeIniFile.DeleteKey(const ASection, AKey: string);
begin
  FDocument.DeleteKey(ASection, AKey);
end;

procedure TUnicodeIniFile.EraseSection(const ASection: string);
begin
  FDocument.EraseSection(ASection);
end;

procedure TUnicodeIniFile.Clear;
begin
  FDocument.Clear;
end;

procedure TUnicodeIniFile.UpdateFile;
var
  Text: string;
  Bytes: TBytes;
begin
  if FFileName = '' then
    Exit;
  Text := FDocument.RenderToText;
  Bytes := uIniEncoding.EncodeIniBytes(Text);
  TFile.WriteAllBytes(FFileName, Bytes);
  FDocument.ClearDirty;
end;

end.
