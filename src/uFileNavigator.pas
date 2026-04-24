{ Finds the next or previous supported file in the same directory,
  and reports the current file's 1-based position among the supported
  siblings. Sorted alphabetically, case-insensitive, with wrap-around
  at boundaries for navigation. }
unit uFileNavigator;

interface

{ Returns the path of the adjacent supported file in the same directory
  as ACurrentFile. ADelta = +1 for next, -1 for previous. AExtensions is
  a comma-separated list (e.g. 'mp4,mkv,avi'). Returns empty string if
  fewer than two supported files exist. Wraps around at first/last file. }
function FindAdjacentFile(const ACurrentFile, AExtensions: string;
  ADelta: Integer): string;

{ Reports the 1-based position (AIndex) of ACurrentFile within the sorted
  list of supported files in its directory, plus the total count (ATotal).
  Returns True on success. Returns False with both out params at 0 when
  the directory is unreadable, no supported files are present, or
  ACurrentFile itself isn't in the sorted list. }
function GetFilePosition(const ACurrentFile, AExtensions: string;
  out AIndex, ATotal: Integer): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils, System.Types, System.Generics.Collections,
  System.Generics.Defaults;

{ Enumerates supported files in ADir and returns their base names sorted
  case-insensitively. Shared by FindAdjacentFile and GetFilePosition so
  both use the exact same ordering. }
function CollectSupportedFiles(const ADir, AExtensions: string): TArray<string>;
var
  Ext: string;
  ExtList: TArray<string>;
  ExtSet: TDictionary<string, Boolean>;
  RawFiles: TStringDynArray;
  Sorted: TList<string>;
  I: Integer;
begin
  Result := nil;
  if (ADir = '') or not TDirectory.Exists(ADir) then
    Exit;

  ExtList := AExtensions.Split([',', ' ']);
  ExtSet := TDictionary<string, Boolean>.Create(Length(ExtList));
  try
    for I := 0 to High(ExtList) do
    begin
      Ext := ExtList[I].Trim;
      if Ext <> '' then
        ExtSet.AddOrSetValue('.' + Ext.ToUpper, True);
    end;
    if ExtSet.Count = 0 then
      Exit;

    RawFiles := TDirectory.GetFiles(ADir);
    Sorted := TList<string>.Create;
    try
      for I := 0 to High(RawFiles) do
      begin
        Ext := ExtractFileExt(RawFiles[I]).ToUpper;
        if ExtSet.ContainsKey(Ext) then
          Sorted.Add(ExtractFileName(RawFiles[I]));
      end;
      { Case-insensitive sort, same as TC's default alphabetical order }
      Sorted.Sort(TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          Result := CompareText(A, B);
        end));
      Result := Sorted.ToArray;
    finally
      Sorted.Free;
    end;
  finally
    ExtSet.Free;
  end;
end;

function IndexOfName(const AFiles: TArray<string>; const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AFiles) do
    if CompareText(AFiles[I], AName) = 0 then
      Exit(I);
  Result := -1;
end;

function FindAdjacentFile(const ACurrentFile, AExtensions: string;
  ADelta: Integer): string;
var
  Dir, CurName: string;
  Files: TArray<string>;
  CurIdx, NewIdx: Integer;
begin
  Result := '';
  Dir := ExtractFilePath(ACurrentFile);
  CurName := ExtractFileName(ACurrentFile);
  Files := CollectSupportedFiles(Dir, AExtensions);
  if Length(Files) < 2 then
    Exit;
  CurIdx := IndexOfName(Files, CurName);
  if CurIdx < 0 then
    Exit;
  { Double-mod keeps the result non-negative even for large negative deltas;
    plain Delphi mod preserves the dividend's sign. }
  NewIdx := ((CurIdx + ADelta) mod Length(Files) + Length(Files)) mod Length(Files);
  Result := Dir + Files[NewIdx];
end;

function GetFilePosition(const ACurrentFile, AExtensions: string;
  out AIndex, ATotal: Integer): Boolean;
var
  Dir, CurName: string;
  Files: TArray<string>;
  Idx: Integer;
begin
  AIndex := 0;
  ATotal := 0;
  Result := False;
  Dir := ExtractFilePath(ACurrentFile);
  CurName := ExtractFileName(ACurrentFile);
  Files := CollectSupportedFiles(Dir, AExtensions);
  if Length(Files) = 0 then
    Exit;
  Idx := IndexOfName(Files, CurName);
  if Idx < 0 then
    Exit;
  AIndex := Idx + 1;
  ATotal := Length(Files);
  Result := True;
end;

end.
