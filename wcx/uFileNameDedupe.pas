{Listing-time filename collision resolver.

 Walks an array of filenames and renames colliding entries TC-style:
 the first occurrence keeps its bare name; later occurrences become
 "<base>(N)<ext>" with N starting at 2 and incrementing until a free
 slot is found.

 Lives in its own unit because the algorithm has nothing to do with
 preset semantics — it operates on opaque strings and would apply
 equally to any future listing builder that needs collision-safe names.
 Pure function; no I/O.}
unit uFileNameDedupe;

interface

{Walks ANames in order and renames colliding entries TC-style: the first
 occurrence keeps its bare name; later occurrences become "<base>(N)<ext>"
 with N starting at 2 and incrementing until a free slot is found.
 Comparison is case-insensitive because Windows filesystems are
 case-insensitive — TC would otherwise treat "Poster.jpg" and "poster.jpg"
 as the same listing entry. The probe-against-running-set algorithm also
 protects literal hand-written entries: if a user defines a preset that
 produces "poster(2).jpg" verbatim, the auto-dedupe of a colliding
 "poster.jpg" entry skips 2 and lands on 3.}
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
  {Case-insensitive set of already-claimed names. Lowercased keys avoid
   pulling in IEqualityComparer<string> just for one collision check.}
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
