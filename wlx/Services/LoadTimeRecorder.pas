{Load-time recorder for TPluginForm — records the extraction start tick
 and formats the elapsed string on completion.}
unit LoadTimeRecorder;

interface

type
  TLoadTimeRecorder = class
  strict private
    FStartTick: Cardinal;
    FFormatted: string;
  public
    procedure Start;
    {Idempotent — a second call preserves the first finalisation.}
    procedure Finalize;
    property Formatted: string read FFormatted;
  end;

implementation

uses
  Winapi.Windows,
  FrameOffsets;

procedure TLoadTimeRecorder.Start;
begin
  FStartTick := GetTickCount;
  FFormatted := '';
end;

procedure TLoadTimeRecorder.Finalize;
var
  ElapsedMs: Cardinal;
begin
  if FStartTick = 0 then
    Exit;
  if FFormatted <> '' then
    Exit;
  {Cardinal cast preserves correct unsigned wraparound.}
  ElapsedMs := Cardinal(GetTickCount - FStartTick);
  FFormatted := FormatLoadTimeMs(ElapsedMs);
end;

end.
