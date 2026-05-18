unit TestWcxProgressCallback;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxProcessDataProc = class
  public
    {Selection contract: Wide wins when both are wired (the modern TC
     path); ANSI is the fallback for legacy / embedded TC builds; nil
     for both is a silent no-op (returns 1 = continue) so the
     extractor does not treat "no UI" as "user cancelled".}
    [Test] procedure TestPrefersWideWhenBothSet;
    [Test] procedure TestFallsBackToAnsiWhenWideNil;
    [Test] procedure TestReturnsOneWhenBothNil;
    {The Notify size argument and the callback's return value must
     round-trip — the bridge depends on this to compute deltas and
     observe cancel.}
    [Test] procedure TestPropagatesSizeArgument;
    [Test] procedure TestPropagatesCallbackReturnValue;
    {Filename plumbing: each variant must receive the supplied filename
     in its expected encoding. Verified by capturing the string at the
     callback site and asserting equality with the constructor arg.}
    [Test] procedure TestFileNameReachesWideCallback;
    [Test] procedure TestFileNameReachesAnsiCallback;
  end;

implementation

uses
  System.SysUtils, Winapi.Windows,
  uWcxAPI, uWcxProgressCallback;

{Module-level capture slots driven by the stdcall callbacks below. The
 WCX callback ABI prevents using closures or method pointers; these
 globals are the simplest faithful test-double. Setup zeros them.}
var
  GAnsiCallCount: Integer;
  GAnsiLastFileName: AnsiString;
  GAnsiLastSize: Integer;
  GAnsiReturnValue: Integer;
  GWideCallCount: Integer;
  GWideLastFileName: string;
  GWideLastSize: Integer;
  GWideReturnValue: Integer;

procedure ResetCaptures;
begin
  GAnsiCallCount := 0;
  GAnsiLastFileName := '';
  GAnsiLastSize := 0;
  GAnsiReturnValue := 1;
  GWideCallCount := 0;
  GWideLastFileName := '';
  GWideLastSize := 0;
  GWideReturnValue := 1;
end;

function CapturingAnsi(FileName: PAnsiChar; Size: Integer): Integer; stdcall;
begin
  Inc(GAnsiCallCount);
  if FileName <> nil then
    GAnsiLastFileName := AnsiString(FileName);
  GAnsiLastSize := Size;
  Result := GAnsiReturnValue;
end;

function CapturingWide(FileName: PWideChar; Size: Integer): Integer; stdcall;
begin
  Inc(GWideCallCount);
  if FileName <> nil then
    GWideLastFileName := FileName;
  GWideLastSize := Size;
  Result := GWideReturnValue;
end;

procedure TTestWcxProcessDataProc.TestPrefersWideWhenBothSet;
var
  Proc: IProcessDataProc;
begin
  ResetCaptures;
  Proc := TWcxProcessDataProc.Create('Movie.mp4', CapturingAnsi, CapturingWide);
  try
    Proc.Notify(64);
    Assert.AreEqual<Integer>(1, GWideCallCount, 'Wide must be invoked');
    Assert.AreEqual<Integer>(0, GAnsiCallCount, 'ANSI must not be invoked when Wide is wired');
  finally
    Proc := nil;
  end;
end;

procedure TTestWcxProcessDataProc.TestFallsBackToAnsiWhenWideNil;
var
  Proc: IProcessDataProc;
begin
  ResetCaptures;
  Proc := TWcxProcessDataProc.Create('Movie.mp4', CapturingAnsi, nil);
  try
    Proc.Notify(32);
    Assert.AreEqual<Integer>(1, GAnsiCallCount, 'ANSI must be invoked when Wide is nil');
    Assert.AreEqual<Integer>(0, GWideCallCount);
  finally
    Proc := nil;
  end;
end;

procedure TTestWcxProcessDataProc.TestReturnsOneWhenBothNil;
var
  Proc: IProcessDataProc;
  Verdict: Integer;
begin
  ResetCaptures;
  Proc := TWcxProcessDataProc.Create('Movie.mp4', nil, nil);
  try
    Verdict := Proc.Notify(99);
    Assert.AreEqual<Integer>(1, Verdict, 'Null wrapper must return 1 = continue');
    Assert.AreEqual<Integer>(0, GAnsiCallCount);
    Assert.AreEqual<Integer>(0, GWideCallCount);
  finally
    Proc := nil;
  end;
end;

procedure TTestWcxProcessDataProc.TestPropagatesSizeArgument;
var
  Proc: IProcessDataProc;
begin
  ResetCaptures;
  Proc := TWcxProcessDataProc.Create('Movie.mp4', nil, CapturingWide);
  try
    Proc.Notify(12345);
    Assert.AreEqual<Integer>(12345, GWideLastSize);
  finally
    Proc := nil;
  end;
end;

procedure TTestWcxProcessDataProc.TestPropagatesCallbackReturnValue;
var
  Proc: IProcessDataProc;
begin
  ResetCaptures;
  GWideReturnValue := 0;
  Proc := TWcxProcessDataProc.Create('Movie.mp4', nil, CapturingWide);
  try
    Assert.AreEqual<Integer>(0, Proc.Notify(10),
      'Callback verdict must round-trip — the bridge keys cancel detection on it');
  finally
    Proc := nil;
  end;
end;

procedure TTestWcxProcessDataProc.TestFileNameReachesWideCallback;
var
  Proc: IProcessDataProc;
const
  Expected = 'My Movie.mp4';
begin
  ResetCaptures;
  Proc := TWcxProcessDataProc.Create(Expected, nil, CapturingWide);
  try
    Proc.Notify(0);
    Assert.AreEqual(Expected, GWideLastFileName);
  finally
    Proc := nil;
  end;
end;

procedure TTestWcxProcessDataProc.TestFileNameReachesAnsiCallback;
var
  Proc: IProcessDataProc;
const
  Expected = 'My Movie.mp4';
begin
  ResetCaptures;
  Proc := TWcxProcessDataProc.Create(Expected, CapturingAnsi, nil);
  try
    Proc.Notify(0);
    Assert.AreEqual(AnsiString(Expected), GAnsiLastFileName);
  finally
    Proc := nil;
  end;
end;

end.
