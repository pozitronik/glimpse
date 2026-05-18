{Command-line tokeniser shared by preset validation and the preset
 extractor.

 Tokenises a whitespace-separated argument string into individual
 tokens, treating double-quoted runs as a single token (the surrounding
 quotes are stripped, matching CreateProcess's command-line parser).
 Pure / no I/O / no dependencies beyond the RTL.

 Lives in its own unit so the preset validator (uWcxPresetValidation)
 and the future argv builder in uWcxPresetExtractor can share one
 implementation — having both grow their own copy would risk subtle
 parsing drift between what the validator allows and what the
 extractor actually feeds to ffmpeg.}
unit uCmdLineTokens;

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
        {Toggle quote state without copying the quote into the token —
         CreateProcess's command-line parser treats the same way, so the
         token shape we validate matches what ffmpeg eventually sees.}
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
