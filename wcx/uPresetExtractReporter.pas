{Failure reporter for the preset-extraction code path.

 DoExtractPreset (in uWcxExports) used to call MessageBox directly when
 a preset failed. That coupling made the failure path untestable —
 every test would have popped a modal dialog. This unit provides:

 1. IPresetExtractFailureReporter, a one-method interface that
    decouples the "tell the user something went wrong" action from
    its medium (MessageBox in production, a captured-string list in
    tests).

 2. TMessageBoxFailureReporter, the production adapter that wraps
    MessageBox with the foreground window as parent (so the dialog
    lands in front of TC on multi-monitor setups).

 3. SummarizeFFmpegError + MakeFailureMessage, the pure string
    composition that used to live inline in ShowPresetExtractError.
    Exposed because the composed message is the unit's externally
    visible contract and worth pinning with unit tests.}
unit uPresetExtractReporter;

interface

uses
  uWcxPresetExtractor;

type
  IPresetExtractFailureReporter = interface
    ['{C7A4F1B8-3E2D-4B95-9A6F-2E8D7C1B5A4E}']
    {Surfaces a composed user-visible message about a failed preset
     extraction. Implementations decide the delivery medium; production
     MessageBoxes, tests capture.}
    procedure Report(const AMsg: string);
  end;

  {Production reporter. Pops a MessageBox parented to GetForegroundWindow
   with the title "Glimpse preset extraction failed" and a warning icon.
   Foreground window as parent (rather than 0) keeps the dialog in front
   of TC's panel on multi-monitor setups — passing 0 occasionally landed
   the dialog behind the active TC window.}
  TMessageBoxFailureReporter = class(TInterfacedObject, IPresetExtractFailureReporter)
  public
    procedure Report(const AMsg: string);
  end;

{Trims the ffmpeg stderr down to the most signal-rich one-liner for a
 dialog box. ffmpeg often emits a multi-line preamble before the actual
 error; the LAST non-empty line is preferred because the immediate
 cause is typically last (e.g. "Output file does not contain any
 stream"). When ffmpeg said nothing useful, falls back to the exit code
 so the user still has a handle for searching docs.}
function SummarizeFFmpegError(const AErrorMessage: string; AExitCode: Integer): string;

{Composes the user-visible failure message. Format is stable so users
 (and tests) can rely on it; if it ever needs to change, update both
 the production reporter's expectations and the message tests.}
function MakeFailureMessage(const APresetName, AOutputPath: string;
  const AResult: TPresetExtractResult): string;

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

end.
