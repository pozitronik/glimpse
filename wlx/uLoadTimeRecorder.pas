{Load-time recorder for TPluginForm.

 Step 105 (C1, part 2 of 4): companion to TViewportRefreshDebouncer.
 Owns the "remember when extraction started, format the elapsed string
 on completion" bookkeeping that previously lived as two scattered
 fields on the form (FLoadStartTick, FLoadTimeStr) plus the
 FinalizeLoadTime method body.

 The recorder is intentionally callback-free: the form already drives
 the lifecycle explicitly (Start in StartExtraction, Finalize in
 WMExtractionDone), and reads the formatted string back in
 BuildStatusBarValues. No need for an OnFinalized hook.}
unit uLoadTimeRecorder;

interface

type
  TLoadTimeRecorder = class
  strict private
    FStartTick: Cardinal;
    FFormatted: string;
  public
    {Records the current tick as the extraction start. Clears any
     previously-formatted result so a second extraction starts fresh.
     Called from TPluginForm.StartExtraction.}
    procedure Start;
    {Computes elapsed-since-Start, formats via FormatLoadTimeMs, stores
     in Formatted. Idempotent: a second call with the same Start tick
     is a no-op (preserves the first finalization for the status bar).
     Called from TPluginForm.WMExtractionDone.}
    procedure Finalize;
    {Formatted "X.Xs" / "Xm Ys" elapsed-time string, populated by
     Finalize. Empty before the first Finalize or after a Start with
     no Finalize yet. Read by TPluginForm.BuildStatusBarValues to
     surface load time in the status bar.}
    property Formatted: string read FFormatted;
  end;

implementation

uses
  Winapi.Windows,
  uFrameOffsets;

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
  {Cast guards correct unsigned wraparound; GetTickCount avoids the
   Vista+ GetTickCount64 dependency that crashes on XP via delay-load.}
  ElapsedMs := Cardinal(GetTickCount - FStartTick);
  FFormatted := FormatLoadTimeMs(ElapsedMs);
end;

end.
