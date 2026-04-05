{ Finds the next or previous supported file in the same directory,
  sorted alphabetically, with wrap-around at boundaries. }
unit uFileNavigator;

interface

{ Returns the path of the adjacent supported file in the same directory
  as ACurrentFile. ADelta = +1 for next, -1 for previous. Extensions is
  a comma-separated list (e.g. 'mp4,mkv,avi'). Returns empty string if
  no other supported file exists. Wraps around at first/last file. }
function FindAdjacentFile(const ACurrentFile, AExtensions: string;
  ADelta: Integer): string;

implementation

uses
  System.SysUtils, System.IOUtils, System.Types, System.Generics.Collections,
  System.Generics.Defaults;

function FindAdjacentFile(const ACurrentFile, AExtensions: string;
  ADelta: Integer): string;
var
  Dir, Ext, CurName: string;
  ExtList: TArray<string>;
  ExtSet: TDictionary<string, Boolean>;
  Files: TStringDynArray;
  Sorted: TList<string>;
  I, CurIdx: Integer;
begin
  Result := '';
  Dir := ExtractFilePath(ACurrentFile);
  if (Dir = '') or not TDirectory.Exists(Dir) then Exit;
  CurName := ExtractFileName(ACurrentFile);

  { Build a set of supported extensions for fast lookup }
  ExtList := AExtensions.Split([',', ' ']);
  ExtSet := TDictionary<string, Boolean>.Create(Length(ExtList));
  try
    for I := 0 to High(ExtList) do
    begin
      Ext := ExtList[I].Trim;
      if Ext <> '' then
        ExtSet.AddOrSetValue('.' + Ext.ToUpper, True);
    end;
    if ExtSet.Count = 0 then Exit;

    { Enumerate all files in the directory }
    Files := TDirectory.GetFiles(Dir);
    Sorted := TList<string>.Create;
    try
      for I := 0 to High(Files) do
      begin
        Ext := ExtractFileExt(Files[I]).ToUpper;
        if ExtSet.ContainsKey(Ext) then
          Sorted.Add(ExtractFileName(Files[I]));
      end;
      if Sorted.Count < 2 then Exit;

      { Sort case-insensitive, same as TC's default alphabetical order }
      Sorted.Sort(TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          Result := CompareText(A, B);
        end));

      { Find current file position }
      CurIdx := -1;
      for I := 0 to Sorted.Count - 1 do
        if CompareText(Sorted[I], CurName) = 0 then
        begin
          CurIdx := I;
          Break;
        end;
      if CurIdx < 0 then Exit;

      { Navigate with wrap-around }
      I := (CurIdx + ADelta + Sorted.Count) mod Sorted.Count;
      Result := Dir + Sorted[I];
    finally
      Sorted.Free;
    end;
  finally
    ExtSet.Free;
  end;
end;

end.
