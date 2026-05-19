{Listing-time filename collision resolver. TC-style renames: first
 occurrence keeps its bare name; later occurrences become
 "<base>(N)<ext>" starting at N=2.}
unit FileNameDedupe;

interface

{Comparison is case-insensitive because Windows filesystems are; without
 this TC would treat "Poster.jpg" and "poster.jpg" as the same entry.
 If a user-authored preset literally produces "poster(2).jpg", the
 auto-dedupe of a colliding "poster.jpg" skips 2 and lands on 3.}
function DeduplicateFileNames(const ANames: TArray<string>): TArray<string>;

implementation

uses
  System.SysUtils, System.Generics.Collections;

function DeduplicateFileNames(const ANames: TArray<string>): TArray<string>;
var
  Taken: TDictionary<string, Boolean>;
  I, N: Integer;
  Name, Base, Ext, Candidate: string;
begin
  SetLength(Result, Length(ANames));
  {Lowercased keys avoid pulling in IEqualityComparer<string> for one check.}
  Taken := TDictionary<string, Boolean>.Create;
  try
    for I := 0 to High(ANames) do
    begin
      Name := ANames[I];
      if not Taken.ContainsKey(Name.ToLower) then
      begin
        Result[I] := Name;
        Taken.Add(Name.ToLower, True);
        Continue;
      end;
      Ext := ExtractFileExt(Name);
      Base := Copy(Name, 1, Length(Name) - Length(Ext));
      N := 2;
      repeat
        Candidate := Format('%s(%d)%s', [Base, N, Ext]);
        Inc(N);
      until not Taken.ContainsKey(Candidate.ToLower);
      Result[I] := Candidate;
      Taken.Add(Candidate.ToLower, True);
    end;
  finally
    Taken.Free;
  end;
end;

end.
