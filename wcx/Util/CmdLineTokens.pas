{Command-line tokeniser shared by preset validation and the preset
 extractor. Splits on whitespace, treats double-quoted runs as one
 token (quotes stripped), matching CreateProcess's parser so the
 validator and extractor never drift in what ffmpeg actually sees.}
unit CmdLineTokens;

interface

function TokenizeArgs(const AArgs: string): TArray<string>;

implementation

uses
  System.Generics.Collections;

function TokenizeArgs(const AArgs: string): TArray<string>;
var
  List: TList<string>;
  I: Integer;
  Token: string;
  InQuote: Boolean;
  C: Char;
begin
  List := TList<string>.Create;
  try
    Token := '';
    InQuote := False;
    I := 1;
    while I <= Length(AArgs) do
    begin
      C := AArgs[I];
      if C = '"' then
      begin
        {Quote character is consumed, not appended, matching CreateProcess.}
        InQuote := not InQuote;
      end
      else if (not InQuote) and ((C = ' ') or (C = #9)) then
      begin
        if Token <> '' then
        begin
          List.Add(Token);
          Token := '';
        end;
      end
      else
        Token := Token + C;
      Inc(I);
    end;
    if Token <> '' then
      List.Add(Token);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
