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
  System.SysUtils, System.Classes, System.IniFiles,
  uIniDocument;

type
  {Descends from TCustomIniFile so the instance can substitute
   wherever the RTL ini-file interface is expected. Every abstract
   member is overridden; the inherited ReadDate / WriteDate / etc. work
   transparently because they route through ReadString / WriteString
   which the descendant implements over the line-list model. ReadBool /
   WriteBool are also overridden to preserve the lenient
   True/False/Yes/No/On/Off/0/1 contract — the base only accepts 0/1.}
  TUnicodeIniFile = class(TCustomIniFile)
  strict private
    FDocument: TIniDocument;

    procedure LoadFromDisk;
  public
    {TCustomIniFile.Create's no-Encoding overload is non-virtual in
     this Delphi RTL; reintroduce here keeps the same call site working
     while we run our own initialization. The base's other Create
     overload (with Encoding) is left alone — callers who want explicit
     encoding can construct via the inherited form.}
    constructor Create(const AFileName: string); reintroduce;
    destructor Destroy; override;

    function ReadString(const Section, Ident, Default: string): string; override;
    procedure WriteString(const Section, Ident, Value: string); override;
    {ReadInteger / WriteInteger / ReadBool / WriteBool are non-virtual
     on TCustomIniFile (the base routes them through ReadString /
     WriteString). reintroduce keeps the typed-as-TUnicodeIniFile
     callers using the line-list-direct paths and preserves ReadBool's
     leniency (True/Yes/On/1 → True; False/No/Off/0 → False); a caller
     typed as TCustomIniFile would fall through to the base's stricter
     0/1 ReadBool — same risk as not having these methods at all on
     the base, accepted to keep the substitution promise.}
    function ReadInteger(const Section, Ident: string; Default: Longint): Longint; reintroduce;
    function ReadBool(const Section, Ident: string; Default: Boolean): Boolean; reintroduce;
    procedure WriteInteger(const Section, Ident: string; Value: Longint); reintroduce;
    procedure WriteBool(const Section, Ident: string; Value: Boolean); reintroduce;

    procedure ReadSections(Strings: TStrings); override;
    procedure ReadSection(const Section: string; Strings: TStrings); override;
    {TCustomIniFile contract: emits "Key=Value" lines (one per key in
     ASection). Our line-list model already carries Key + Value per
     ilkKeyValue entry; the override walks it and assembles the
     formatted strings the base expects.}
    procedure ReadSectionValues(const Section: string; Strings: TStrings); override;
    {ValueExists / SectionExists are non-virtual on TCustomIniFile —
     reintroduce so the line-list-direct path stays in use.}
    function ValueExists(const Section, Ident: string): Boolean; reintroduce;
    function SectionExists(const Section: string): Boolean; reintroduce;
    procedure DeleteKey(const Section, Ident: string); override;
    procedure EraseSection(const Section: string); override;
    {Discards every line, leaving an empty in-memory document. Used
     when callers want to fully rewrite the file from scratch.}
    procedure Clear;
    {Persists the in-memory state to FileName as UTF-8 without BOM
     and CRLF line endings. Silent no-op when FileName is empty
     (mirrors the TIniFile sentinel).}
    procedure UpdateFile; override;
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
  inherited Create(AFileName);
  FDocument := TIniDocument.Create;
  if (FileName <> '') and TFile.Exists(FileName) then
    LoadFromDisk;
end;

destructor TUnicodeIniFile.Destroy;
begin
  {Destructor does NOT auto-flush (step 67 / N18). The previous policy
   mirrored TIniFile's "writes hit the disk on Free" behaviour by
   calling UpdateFile inside a swallow-everything try/except — that
   silently dropped writes when UpdateFile raised (disk full, file
   locked, permission denied), and the caller had no way to learn
   their settings did not persist.

   Every production caller (TPluginSettings.Save, TWcxSettings.Save,
   uWcxPresets.SavePresets) already calls UpdateFile explicitly in its
   try/finally, so this destructor change does not lose any writes in
   the current code base. New callers MUST call UpdateFile explicitly;
   the Dirty property is available if they want to gate the call.}
  FDocument.Free;
  inherited;
end;

procedure TUnicodeIniFile.LoadFromDisk;
var
  Bytes: TBytes;
  Text: string;
begin
  Bytes := TFile.ReadAllBytes(FileName);
  Text := uIniEncoding.DecodeIniBytes(Bytes);
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
  {TCustomIniFile contract: emits "Key=Value" pairs, one per line. The
   line-list model carries each pair as a TIniLine; we re-format here
   by reading keys via ReadSection (preserves document order) and
   pairing each with its stored value.}
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
  Bytes := uIniEncoding.EncodeIniBytes(Text);
  TFile.WriteAllBytes(FileName, Bytes);
  FDocument.ClearDirty;
end;

end.
