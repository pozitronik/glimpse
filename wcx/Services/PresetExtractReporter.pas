{Failure reporter for preset extraction. Decouples user notification from
 its medium (MessageBox in production, captured strings in tests).}
unit PresetExtractReporter;

interface

uses
  WcxPresetExtractor;

type
  IPresetExtractFailureReporter = interface
    ['{C7A4F1B8-3E2D-4B95-9A6F-2E8D7C1B5A4E}']
    procedure Report(const AMsg: string);
  end;

  {Parents to GetForegroundWindow rather than 0; passing 0 occasionally
   landed the dialog behind the active TC window on multi-monitor setups.}
  TMessageBoxFailureReporter = class(TInterfacedObject, IPresetExtractFailureReporter)
  public
    procedure Report(const AMsg: string);
  end;

{Picks the LAST non-empty line from ffmpeg stderr because the immediate
 cause typically appears last (e.g. "Output file does not contain any
 stream"). Falls back to the exit code when stderr is empty.}
function SummarizeFFmpegError(const AErrorMessage: string; AExitCode: Integer): string;

function MakeFailureMessage(const APresetName, AOutputPath: string;
  const AResult: TPresetExtractResult): string;

{Process-global active reporter, swappable in tests. Lives here rather
 than in WcxExports so WcxEntryExtractors can reach it without
 back-linking into the dispatcher unit.}
function GetPresetFailureReporter: IPresetExtractFailureReporter;
procedure SetPresetFailureReporter(const AReporter: IPresetExtractFailureReporter);

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.Classes;

function SummarizeFFmpegError(const AErrorMessage: string; AExitCode: Integer): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := AErrorMessage;
    for I := Lines.Count - 1 downto 0 do
      if Trim(Lines[I]) <> '' then
      begin
        Result := Trim(Lines[I]);
        Break;
      end;
  finally
    Lines.Free;
  end;
  if Result = '' then
    Result := Format('ffmpeg exited with code %d (no stderr captured)', [AExitCode]);
end;

function MakeFailureMessage(const APresetName, AOutputPath: string;
  const AResult: TPresetExtractResult): string;
begin
  Result := Format('Preset "%s" could not produce "%s":'#13#10#13#10'%s',
    [APresetName, TPath.GetFileName(AOutputPath),
     SummarizeFFmpegError(AResult.ErrorMessage, AResult.ExitCode)]);
end;

{ TMessageBoxFailureReporter }

procedure TMessageBoxFailureReporter.Report(const AMsg: string);
begin
  MessageBox(GetForegroundWindow, PChar(AMsg), 'Glimpse preset extraction failed',
    MB_OK or MB_ICONWARNING);
end;

var
  GReporter: IPresetExtractFailureReporter;

function GetPresetFailureReporter: IPresetExtractFailureReporter;
begin
  Result := GReporter;
end;

procedure SetPresetFailureReporter(const AReporter: IPresetExtractFailureReporter);
begin
  GReporter := AReporter;
end;

initialization

finalization

GReporter := nil;

end.
