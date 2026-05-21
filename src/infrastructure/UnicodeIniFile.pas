{UTF-8 / UTF-16-aware INI file handler. TIniFile in the RTL routes
 through Win32 GetPrivateProfileString which only understands UTF-16 LE
 with BOM or ANSI; UTF-8 is read as ANSI and mojibakes any non-ASCII
 content. This unit reads UTF-8 / UTF-16 LE / UTF-16 BE (BOM-detected)
 with strict-UTF-8 fallback on no-BOM files, and writes UTF-8 without
 BOM + CRLF.

 In-memory model preserves comments, blank lines, and original ordering
 across read-modify-write so hand-edited files survive Save unchanged.
 ReadBool is lenient: True/False/Yes/No/On/Off/0/1.}
unit UnicodeIniFile;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles,
  IniStore, IniDocument;

type
  {Descends from TCustomIniFile so the instance can substitute wherever
   the RTL ini-file interface is expected. ReadBool/WriteBool are
   overridden to preserve lenient parsing; the base only accepts 0/1.}
  TUnicodeIniFile = class(TCustomIniFile, IIniFile)
  strict private
    FDocument: TIniDocument;

    procedure LoadFromDisk;
  public
    {The base's no-Encoding Create is non-virtual; reintroduce so the
     existing call sites keep working while we run our own initialisation.}
    constructor Create(const AFileName: string); reintroduce;
    destructor Destroy; override;

    {IIniFile is exposed for substitution; lifetime stays manual
     (TCustomIniFile is not refcounted), so _AddRef/_Release are inert.}
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;

    function ReadString(const Section, Ident, Default: string): string; override;
    procedure WriteString(const Section, Ident, Value: string); override;
    {Overridden to keep lenient bool parsing: the base ReadBool accepts
     only 0/1, ours also honours True/False/Yes/No/On/Off.}
    function ReadInteger(const Section, Ident: string; Default: Longint): Longint; override;
    function ReadBool(const Section, Ident: string; Default: Boolean): Boolean; override;
    procedure WriteInteger(const Section, Ident: string; Value: Longint); override;
    procedure WriteBool(const Section, Ident: string; Value: Boolean); override;

    procedure ReadSections(Strings: TStrings); override;
    procedure ReadSection(const Section: string; Strings: TStrings); override;
    procedure ReadSectionValues(const Section: string; Strings: TStrings); override;
    function ValueExists(const Section, Ident: string): Boolean; override;
    function SectionExists(const Section: string): Boolean; override;
    procedure DeleteKey(const Section, Ident: string); override;
    procedure EraseSection(const Section: string); override;
    procedure Clear;
    {Silent no-op when FileName is empty (mirrors the TIniFile sentinel).}
    procedure UpdateFile; override;
  end;

{Re-exported for callers that previously imported from this unit; new
 callers should import IniEncoding directly.}
function DecodeIniBytes(const ABytes: TBytes): string;

implementation

uses
  System.IOUtils,
  IniEncoding;

function DecodeIniBytes(const ABytes: TBytes): string;
begin
  Result := IniEncoding.DecodeIniBytes(ABytes);
end;

constructor TUnicodeIniFile.Create(const AFileName: string);
begin
  inherited Create(AFileName);
  FDocument := TIniDocument.Create;
  if (FileName <> '') and TFile.Exists(FileName) then
    LoadFromDisk;
end;

destructor TUnicodeIniFile.Destroy;
begin
  {No auto-flush. Callers MUST call UpdateFile explicitly — a destructor-
   time flush would have to swallow exceptions (disk full, file locked,
   permission denied), leaving the caller with no signal that the save
   did not persist. Use the Dirty property to gate the UpdateFile call.}
  FDocument.Free;
  inherited;
end;

function TUnicodeIniFile.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TUnicodeIniFile._AddRef: Integer;
begin
  Result := -1;
end;

function TUnicodeIniFile._Release: Integer;
begin
  Result := -1;
end;

procedure TUnicodeIniFile.LoadFromDisk;
var
  Bytes: TBytes;
  Text: string;
begin
  Bytes := TFile.ReadAllBytes(FileName);
  Text := IniEncoding.DecodeIniBytes(Bytes);
  FDocument.ParseFromText(Text);
end;

function TUnicodeIniFile.ReadString(const Section, Ident, Default: string): string;
begin
  Result := FDocument.ReadString(Section, Ident, Default);
end;

function TUnicodeIniFile.ReadInteger(const Section, Ident: string; Default: Longint): Longint;
begin
  Result := FDocument.ReadInteger(Section, Ident, Default);
end;

function TUnicodeIniFile.ReadBool(const Section, Ident: string; Default: Boolean): Boolean;
begin
  Result := FDocument.ReadBool(Section, Ident, Default);
end;

procedure TUnicodeIniFile.WriteString(const Section, Ident, Value: string);
begin
  FDocument.WriteString(Section, Ident, Value);
end;

procedure TUnicodeIniFile.WriteInteger(const Section, Ident: string; Value: Longint);
begin
  FDocument.WriteInteger(Section, Ident, Value);
end;

procedure TUnicodeIniFile.WriteBool(const Section, Ident: string; Value: Boolean);
begin
  FDocument.WriteBool(Section, Ident, Value);
end;

procedure TUnicodeIniFile.ReadSections(Strings: TStrings);
begin
  FDocument.ReadSections(Strings);
end;

procedure TUnicodeIniFile.ReadSection(const Section: string; Strings: TStrings);
begin
  FDocument.ReadSection(Section, Strings);
end;

procedure TUnicodeIniFile.ReadSectionValues(const Section: string; Strings: TStrings);
var
  Keys: TStringList;
  I: Integer;
  Key: string;
begin
  {TCustomIniFile contract: emit "Key=Value" pairs, one per line, in
   document order.}
  Strings.Clear;
  Keys := TStringList.Create;
  try
    FDocument.ReadSection(Section, Keys);
    for I := 0 to Keys.Count - 1 do
    begin
      Key := Keys[I];
      Strings.Add(Key + '=' + FDocument.ReadString(Section, Key, ''));
    end;
  finally
    Keys.Free;
  end;
end;

function TUnicodeIniFile.ValueExists(const Section, Ident: string): Boolean;
begin
  Result := FDocument.ValueExists(Section, Ident);
end;

function TUnicodeIniFile.SectionExists(const Section: string): Boolean;
begin
  Result := FDocument.SectionExists(Section);
end;

procedure TUnicodeIniFile.DeleteKey(const Section, Ident: string);
begin
  FDocument.DeleteKey(Section, Ident);
end;

procedure TUnicodeIniFile.EraseSection(const Section: string);
begin
  FDocument.EraseSection(Section);
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
  if FileName = '' then
    Exit;
  Text := FDocument.RenderToText;
  Bytes := IniEncoding.EncodeIniBytes(Text);
  TFile.WriteAllBytes(FileName, Bytes);
  FDocument.ClearDirty;
end;

end.
